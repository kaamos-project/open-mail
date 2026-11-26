import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as em;

import '../core/mail_service.dart';
import '../core/models.dart';
import '../core/text_utils.dart';

/// [MailServiceFactory] reale: IMAP e SMTP con `enough_mail`.
class ImapMailServiceFactory implements MailServiceFactory {
  /// Crea la factory.
  const ImapMailServiceFactory();

  @override
  Future<MailService> connect(Account account, String password) async {
    final service = ImapMailService(account, password);
    await service._ensureImap();
    return service;
  }

  @override
  Future<ConnectionCheckResult> check(Account account, String password) async {
    String? imapError;
    String? smtpError;
    var folders = 0;
    final service = ImapMailService(account, password);
    try {
      folders = (await service.listFolders()).length;
    } on Object catch (e) {
      imapError = describeMailError(e);
    }
    try {
      final smtp = await service._connectSmtp();
      await smtp.quit();
    } on Object catch (e) {
      smtpError = describeMailError(e);
    }
    await service.close();
    return ConnectionCheckResult(
      imapError: imapError,
      smtpError: smtpError,
      folderCount: folders,
    );
  }
}

/// Traduce gli errori di rete e di protocollo in frasi per l'utente.
String describeMailError(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('authentication') ||
      text.contains('login') ||
      text.contains('credentials') ||
      text.contains('535')) {
    return 'Nome utente o password non accettati.';
  }
  if (text.contains('handshake') || text.contains('certificate')) {
    return 'Connessione sicura non riuscita: controlla porta e sicurezza.';
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return 'Il server non risponde.';
  }
  if (text.contains('socketexception') ||
      text.contains('failed host lookup') ||
      text.contains('connection refused')) {
    return 'Server non raggiungibile: controlla indirizzo e porta.';
  }
  return 'Errore del server: $error';
}

/// Un account collegato via IMAP (lettura) e SMTP (invio).
///
/// Usa il client IMAP "di basso livello" di enough_mail e non il suo
/// `MailClient` completo: per la cache ci servono UID e `UIDVALIDITY` sotto
/// il nostro controllo.
///
/// IMAP ha uno stato (la cartella selezionata): due comandi che si
/// intrecciano potrebbero leggere la cartella sbagliata. Per questo ogni
/// operazione passa da [_serial], che le mette in fila una alla volta.
class ImapMailService implements MailService {
  /// Crea il servizio; la connessione si apre al primo uso.
  ImapMailService(this.account, this._password);

  /// L'account collegato.
  final Account account;
  final String _password;

  em.ImapClient? _imap;
  String? _selectedPath;
  Future<void> _queue = Future.value();

  static const _timeout = Duration(seconds: 30);

  /// Esegue [task] dopo che le operazioni precedenti sono finite.
  Future<T> _serial<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    // La coda prosegue anche se task fallisce.
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<em.ImapClient> _ensureImap() async {
    final existing = _imap;
    if (existing != null && existing.isConnected && existing.isLoggedIn) {
      return existing;
    }
    final client = em.ImapClient(
      defaultResponseTimeout: _timeout,
      defaultWriteTimeout: _timeout,
    );
    final imap = account.imap;
    await client.connectToServer(
      imap.host,
      imap.port,
      isSecure: imap.security == ConnectionSecurity.tls,
      timeout: _timeout,
    );
    if (imap.security == ConnectionSecurity.startTls) {
      await client.startTls();
    }
    await client.login(account.username, _password);
    _imap = client;
    _selectedPath = null;
    return client;
  }

  /// Seleziona [path] se non è già la cartella selezionata.
  Future<(em.ImapClient, em.Mailbox?)> _select(String path) async {
    final client = await _ensureImap();
    if (_selectedPath == path) return (client, null);
    final box = await client.selectMailboxByPath(path);
    _selectedPath = path;
    return (client, box);
  }

  /// Ripete una volta l'operazione se la connessione è caduta (succede
  /// spesso su mobile quando l'app torna in primo piano).
  Future<T> _withRetry<T>(Future<T> Function() task) => _serial(() async {
    try {
      return await task();
    } on Object catch (e) {
      if (e is em.ImapException || e.toString().contains('Socket')) {
        _imap = null;
        _selectedPath = null;
        return task();
      }
      rethrow;
    }
  });

  @override
  Future<List<Folder>> listFolders() => _withRetry(() async {
    final client = await _ensureImap();
    final boxes = await client.listMailboxes(recursive: true);
    final folders = [
      for (final box in boxes)
        if (!box.isNotSelectable)
          Folder(path: box.path, name: _folderName(box), role: _role(box)),
    ];
    folders.sort(compareFolders);
    return folders;
  });

  static FolderRole _role(em.Mailbox box) {
    if (box.isInbox || box.path.toUpperCase() == 'INBOX') {
      return FolderRole.inbox;
    }
    if (box.isSent) return FolderRole.sent;
    if (box.isDrafts) return FolderRole.drafts;
    if (box.isArchive) return FolderRole.archive;
    if (box.isTrash) return FolderRole.trash;
    if (box.isJunk) return FolderRole.junk;
    return FolderRole.other;
  }

  static String _folderName(em.Mailbox box) =>
      box.path.toUpperCase() == 'INBOX' ? 'INBOX' : box.name;

  @override
  Future<FolderStatus> openFolder(String path) => _withRetry(() async {
    final client = await _ensureImap();
    // SELECT sempre: è la risposta di SELECT che porta UIDNEXT e gli
    // altri contatori aggiornati.
    final box = await client.selectMailboxByPath(path);
    _selectedPath = path;
    return FolderStatus(
      uidValidity: box.uidValidity ?? 0,
      uidNext: box.uidNext ?? 0,
      exists: box.messagesExists,
    );
  });

  @override
  Future<List<int>> listUids(String path) => _withRetry(() async {
    final (client, _) = await _select(path);
    // Con SORT (RFC 5256) il server ci dà gli UID già in ordine di data:
    // l'UID dice solo quando il messaggio è entrato nella cartella, e una
    // mail vecchia appena archiviata avrebbe l'UID più alto.
    if (client.serverInfo.supports('SORT')) {
      final sorted = await client.uidSortMessages('DATE');
      return sorted.matchingSequence?.toList() ?? <int>[];
    }
    // Senza SORT (es. Gmail): ordine di arrivo nella cartella. La lista
    // mostrata viene comunque riordinata per data dalla cache.
    final result = await client.uidSearchMessages(searchCriteria: 'ALL');
    final uids = result.matchingSequence?.toList() ?? <int>[];
    uids.sort();
    return uids;
  });

  @override
  Future<List<MessageSummary>> fetchSummaries(String path, List<int> uids) {
    if (uids.isEmpty) return Future.value(const []);
    return _withRetry(() async {
      final (client, _) = await _select(path);
      final sequence = em.MessageSequence.fromIds(uids, isUid: true);
      final result = await client.uidFetchMessages(
        sequence,
        '(UID FLAGS ENVELOPE BODYSTRUCTURE)',
      );
      final previews = await _fetchPreviews(client, result.messages);
      return [
        for (final m in result.messages) _summary(m, previews[m.uid] ?? ''),
      ];
    });
  }

  /// Scarica i primi byte della parte di testo di ogni messaggio, per
  /// l'anteprima nella lista. Due giri invece di uno, ma molto più leggero
  /// che scaricare tutti i messaggi.
  Future<Map<int, String>> _fetchPreviews(
    em.ImapClient client,
    List<em.MimeMessage> messages,
  ) async {
    // Raggruppa per fetchId ("1", "1.1"...): un comando per gruppo.
    final groups = <String, List<em.MimeMessage>>{};
    final parts = <int, em.BodyPart>{};
    for (final m in messages) {
      final uid = m.uid;
      final body = m.body;
      if (uid == null || body == null) continue;
      final part =
          body.findFirst(em.MediaSubtype.textPlain) ??
          body.findFirst(em.MediaSubtype.textHtml);
      final fetchId = part?.fetchId;
      if (part == null || fetchId == null) continue;
      parts[uid] = part;
      groups.putIfAbsent(fetchId, () => []).add(m);
    }
    final previews = <int, String>{};
    for (final entry in groups.entries) {
      final fetchId = entry.key;
      final result = await client.uidFetchMessages(
        em.MessageSequence.fromIds([
          for (final m in entry.value) m.uid!,
        ], isUid: true),
        '(BODY.PEEK[$fetchId]<0.1024>)',
      );
      for (final m in result.messages) {
        final uid = m.uid;
        final part = uid == null ? null : parts[uid];
        final raw = m.getPart(fetchId)?.mimeData;
        if (part == null || raw == null) continue;
        final text = switch (raw) {
          em.TextMimeData() => raw.text,
          em.BinaryMimeData() => String.fromCharCodes(raw.data),
          _ => '',
        };
        final decoded = decodePartialText(
          text,
          transferEncoding: part.encoding,
          charset: part.contentType?.charset,
        );
        final isHtml =
            part.contentType?.mediaType.sub == em.MediaSubtype.textHtml;
        previews[uid!] = makePreview(isHtml ? htmlToText(decoded) : decoded);
      }
    }
    return previews;
  }

  static Address? _address(em.MailAddress? a) =>
      a == null ? null : Address(a.email, a.personalName);

  static List<Address> _addresses(List<em.MailAddress>? list) => [
    for (final a in list ?? const <em.MailAddress>[])
      Address(a.email, a.personalName),
  ];

  static MessageSummary _summary(em.MimeMessage m, String preview) {
    final envelope = m.envelope;
    return MessageSummary(
      uid: m.uid ?? 0,
      from: _address(envelope?.from?.firstOrNull ?? m.from?.firstOrNull),
      to: _addresses(envelope?.to ?? m.to),
      subject: (envelope?.subject ?? m.decodeSubject() ?? '').trim(),
      date: envelope?.date ?? m.decodeDate(),
      preview: preview,
      seen: m.isSeen,
      flagged: m.isFlagged,
      answered: m.isAnswered,
      hasAttachments: m.body != null && m.hasAttachments(),
    );
  }

  @override
  Future<Map<int, MessageFlagsState>> fetchFlags(String path, List<int> uids) {
    if (uids.isEmpty) return Future.value(const {});
    return _withRetry(() async {
      final (client, _) = await _select(path);
      final result = await client.uidFetchMessages(
        em.MessageSequence.fromIds(uids, isUid: true),
        '(UID FLAGS)',
      );
      return {
        for (final m in result.messages)
          if (m.uid != null)
            m.uid!: (
              seen: m.isSeen,
              flagged: m.isFlagged,
              answered: m.isAnswered,
            ),
      };
    });
  }

  @override
  Future<List<int>> search(String path, String query) => _withRetry(() async {
    final (client, _) = await _select(path);
    final q = imapQuote(query);
    // OR annidati: FROM o SUBJECT o TEXT.
    final result = await client.uidSearchMessages(
      searchCriteria: 'OR OR FROM $q SUBJECT $q TEXT $q',
    );
    final uids = result.matchingSequence?.toList() ?? <int>[];
    uids.sort();
    return uids;
  });

  @override
  Future<MessageContent> fetchMessage(String path, int uid) =>
      _withRetry(() async {
        final (client, _) = await _select(path);
        // BODY.PEEK: leggere il messaggio non deve segnarlo come letto da
        // solo; lo facciamo noi con setSeen, così l'utente può annullare.
        final result = await client.uidFetchMessage(
          uid,
          '(UID FLAGS ENVELOPE BODY.PEEK[])',
        );
        if (result.messages.isEmpty) {
          throw StateError('Messaggio $uid non trovato in $path');
        }
        return _content(result.messages.first);
      });

  MessageContent _content(em.MimeMessage m) {
    final attachments = <AttachmentInfo>[];
    for (final info in m.findContentInfo()) {
      attachments.add(
        AttachmentInfo(
          fetchId: info.fetchId,
          fileName: info.fileName ?? 'allegato',
          size:
              info.size ??
              m.getPart(info.fetchId)?.decodeContentBinary()?.length,
          mimeType: info.mediaType?.text ?? 'application/octet-stream',
        ),
      );
    }
    final inline = <String, InlineImage>{};
    for (final info in m.findContentInfo(
      disposition: em.ContentDisposition.inline,
    )) {
      final part = m.getPart(info.fetchId);
      final cid = part?.getHeaderValue('content-id');
      final bytes = part?.decodeContentBinary();
      if (cid == null || bytes == null || !info.isImage) continue;
      inline[stripAngles(cid)] = InlineImage(
        mimeType: info.mediaType?.text ?? 'image/png',
        bytes: bytes,
      );
    }
    final summary = _summary(m, '');
    final plain = m.decodeTextPlainPart();
    final html = m.decodeTextHtmlPart();
    return MessageContent(
      summary: MessageSummary(
        uid: summary.uid,
        from: summary.from,
        to: summary.to,
        subject: summary.subject,
        date: summary.date,
        preview: makePreview(plain ?? (html == null ? '' : htmlToText(html))),
        seen: summary.seen,
        flagged: summary.flagged,
        answered: summary.answered,
        hasAttachments: attachments.isNotEmpty,
      ),
      cc: _addresses(m.envelope?.cc ?? m.cc),
      replyTo: _addresses(m.envelope?.replyTo ?? m.replyTo),
      messageId: m.getHeaderValue('message-id')?.trim(),
      references: parseMessageIds(m.getHeaderValue('references')),
      plainText: plain,
      html: html,
      attachments: attachments,
      inlineImages: inline,
    );
  }

  @override
  Future<Uint8List> fetchAttachment(String path, int uid, String fetchId) =>
      _withRetry(() async {
        final (client, _) = await _select(path);
        // La BODYSTRUCTURE dice come è codificata la parte (di solito
        // base64); BODY.PEEK[id] porta i byte ancora codificati.
        final result = await client.uidFetchMessage(
          uid,
          '(BODYSTRUCTURE BODY.PEEK[$fetchId])',
        );
        final message = result.messages.firstOrNull;
        final raw = message?.getPart(fetchId)?.mimeData;
        if (message == null || raw == null) {
          throw StateError('Allegato $fetchId non trovato');
        }
        return raw.decodeBinary(message.body?.getChildPart(fetchId)?.encoding);
      });

  Future<void> _store(
    String path,
    List<int> uids,
    List<String> flags, {
    required bool add,
  }) {
    if (uids.isEmpty) return Future.value();
    return _withRetry(() async {
      final (client, _) = await _select(path);
      await client.uidStore(
        em.MessageSequence.fromIds(uids, isUid: true),
        flags,
        action: add ? em.StoreAction.add : em.StoreAction.remove,
        silent: true,
      );
    });
  }

  @override
  Future<void> setSeen(String path, List<int> uids, {required bool seen}) =>
      _store(path, uids, [em.MessageFlags.seen], add: seen);

  @override
  Future<void> setFlagged(
    String path,
    List<int> uids, {
    required bool flagged,
  }) => _store(path, uids, [em.MessageFlags.flagged], add: flagged);

  @override
  Future<void> setAnswered(String path, List<int> uids) =>
      _store(path, uids, [em.MessageFlags.answered], add: true);

  @override
  Future<void> move(String path, List<int> uids, String targetPath) {
    if (uids.isEmpty) return Future.value();
    return _withRetry(() async {
      final (client, _) = await _select(path);
      final sequence = em.MessageSequence.fromIds(uids, isUid: true);
      if (client.serverInfo.supports('MOVE')) {
        await client.uidMove(sequence, targetMailboxPath: targetPath);
      } else {
        // Server vecchi senza MOVE (RFC 6851): copia, segna, cancella.
        await client.uidCopy(sequence, targetMailboxPath: targetPath);
        await client.uidMarkDeleted(sequence);
        await client.uidExpunge(sequence);
      }
    });
  }

  @override
  Future<void> deletePermanently(String path, List<int> uids) {
    if (uids.isEmpty) return Future.value();
    return _withRetry(() async {
      final (client, _) = await _select(path);
      final sequence = em.MessageSequence.fromIds(uids, isUid: true);
      await client.uidMarkDeleted(sequence);
      await client.uidExpunge(sequence);
    });
  }

  @override
  Future<void> append(
    String path,
    String rawMessage, {
    List<String> flags = const [],
  }) => _withRetry(() async {
    final client = await _ensureImap();
    await client.appendMessageText(
      rawMessage,
      targetMailboxPath: path,
      flags: flags,
    );
  });

  Future<em.SmtpClient> _connectSmtp() async {
    final smtp = account.smtp;
    final domain = account.email.contains('@')
        ? account.email.split('@').last
        : 'localhost';
    final client = em.SmtpClient(domain);
    await client.connectToServer(
      smtp.host,
      smtp.port,
      isSecure: smtp.security == ConnectionSecurity.tls,
      timeout: _timeout,
    );
    await client.ehlo();
    if (smtp.security == ConnectionSecurity.startTls) {
      await client.startTls();
    }
    await client.authenticate(
      account.username,
      _password,
      em.AuthMechanism.login,
    );
    return client;
  }

  em.MimeMessage _build(OutgoingMessage message) {
    final builder =
        em.MessageBuilder(
            text: message.body,
            characterSet: em.CharacterSet.utf8,
            transferEncoding: em.TransferEncoding.quotedPrintable,
          )
          ..from = [em.MailAddress(message.from.name, message.from.email)]
          ..to = [for (final a in message.to) em.MailAddress(a.name, a.email)]
          ..cc = [for (final a in message.cc) em.MailAddress(a.name, a.email)]
          // Ccn NON va negli header: chi riceve vedrebbe tutti i destinatari
          // nascosti. Va solo nella busta SMTP (vedi send).
          ..subject = message.subject;
    if (message.inReplyTo != null) {
      builder.setHeader('In-Reply-To', message.inReplyTo);
    }
    if (message.references.isNotEmpty) {
      builder.setHeader('References', message.references.join(' '));
    }
    for (final a in message.attachments) {
      builder.addBinary(
        a.bytes,
        em.MediaType.fromText(a.mimeType),
        filename: a.fileName,
      );
    }
    return builder.buildMimeMessage();
  }

  @override
  String render(OutgoingMessage message) => _build(message).renderMessage();

  @override
  Future<String> send(OutgoingMessage message) async {
    final mime = _build(message);
    final smtp = await _connectSmtp();
    try {
      await smtp.sendMessage(
        mime,
        recipients: [
          for (final a in message.allRecipients)
            em.MailAddress(a.name, a.email),
        ],
      );
    } finally {
      await smtp.quit().catchError((Object _) => em.SmtpResponse([]));
    }
    return mime.renderMessage();
  }

  @override
  Future<void> close() async {
    final client = _imap;
    _imap = null;
    if (client == null) return;
    try {
      await client.logout();
    } on Object {
      // Chiudiamo comunque.
    }
    await client.disconnect();
  }
}

/// Decodifica i primi byte di una parte di testo, troncati a metà.
///
/// Il troncamento può spezzare una sequenza base64 o quoted-printable:
/// tagliamo quello che resta a metà prima di decodificare.
String decodePartialText(
  String raw, {
  String? transferEncoding,
  String? charset,
}) {
  final encoding = transferEncoding?.toLowerCase();
  var text = raw;
  if (encoding == 'base64') {
    final clean = text.replaceAll(RegExp(r'\s'), '');
    text = clean.substring(0, clean.length - clean.length % 4);
  } else if (encoding == 'quoted-printable') {
    // Un "=" o "=X" a fine stringa sono un escape troncato.
    text = text.replaceFirst(RegExp(r'=[0-9A-Fa-f]?$'), '');
  }
  try {
    return em.MailCodec.decodeAnyText(text, encoding ?? '8bit', charset);
  } on Object {
    return utf8.decode(text.codeUnits, allowMalformed: true);
  }
}
