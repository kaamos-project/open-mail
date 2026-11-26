import 'dart:io';
import 'dart:typed_data';

import 'package:kaamos_mail/src/core/mail_service.dart';
import 'package:kaamos_mail/src/core/models.dart';
import 'package:kaamos_mail/src/data/account_repository.dart';
import 'package:kaamos_mail/src/data/secret_store.dart';
import 'package:kaamos_mail/src/ui/environment.dart';

/// Un account d'esempio.
const testAccount = Account(
  id: 'acc1',
  displayName: 'Alessio Test',
  email: 'alessio@esempio.org',
  username: 'alessio@esempio.org',
  imap: ServerConfig(
    host: 'imap.esempio.org',
    port: 993,
    security: ConnectionSecurity.tls,
  ),
  smtp: ServerConfig(
    host: 'smtp.esempio.org',
    port: 465,
    security: ConnectionSecurity.tls,
  ),
);

/// Un messaggio d'esempio con UID [uid].
MessageSummary summary(
  int uid, {
  String subject = 'Oggetto',
  bool seen = false,
  String from = 'marta@esempio.org',
}) => MessageSummary(
  uid: uid,
  from: Address(from, 'Marta'),
  to: const [Address('alessio@esempio.org', 'Alessio')],
  subject: '$subject $uid',
  date: DateTime.utc(2026, 11, 20, 10, uid % 60),
  preview: 'Anteprima $uid',
  seen: seen,
  flagged: false,
  answered: false,
  hasAttachments: false,
);

/// Una cartella del server finto.
class FakeFolder {
  /// Crea la cartella.
  FakeFolder(this.folder, {this.uidValidity = 1});

  /// La cartella.
  final Folder folder;

  /// UIDVALIDITY.
  int uidValidity;

  /// Messaggi per UID.
  final Map<int, MessageSummary> messages = {};

  /// Testo dei messaggi per UID.
  final Map<int, String> bodies = {};
}

/// Un server IMAP/SMTP in memoria.
class FakeMailService implements MailService {
  /// Crea il server con Inbox, Inviati, Bozze, Archivio e Cestino.
  FakeMailService() {
    for (final f in const [
      Folder(path: 'INBOX', name: 'INBOX', role: FolderRole.inbox),
      Folder(path: 'Sent', name: 'Sent', role: FolderRole.sent),
      Folder(path: 'Drafts', name: 'Drafts', role: FolderRole.drafts),
      Folder(path: 'Archive', name: 'Archive', role: FolderRole.archive),
      Folder(path: 'Trash', name: 'Trash', role: FolderRole.trash),
    ]) {
      folders[f.path] = FakeFolder(f);
    }
  }

  /// Le cartelle per percorso.
  final Map<String, FakeFolder> folders = {};

  /// Messaggi inviati.
  final List<OutgoingMessage> sent = [];

  /// Messaggi aggiunti con APPEND: (cartella, flag).
  final List<(String, List<String>)> appended = [];

  /// Quanti UID sono stati chiesti con [fetchSummaries].
  int fetchedSummaries = 0;

  /// Se non null, ogni chiamata fallisce con questo errore.
  Object? failWith;

  /// Chiamato da [close].
  bool closed = false;

  /// Aggiunge [count] messaggi in [path] con UID 1..count.
  void seed(String path, int count) {
    for (var uid = 1; uid <= count; uid++) {
      folders[path]!.messages[uid] = summary(uid);
      folders[path]!.bodies[uid] = 'Testo del messaggio $uid';
    }
  }

  void _check() {
    final e = failWith;
    if (e != null) throw e;
  }

  @override
  Future<List<Folder>> listFolders() async {
    _check();
    return [for (final f in folders.values) f.folder];
  }

  @override
  Future<FolderStatus> openFolder(String path) async {
    _check();
    final f = folders[path]!;
    final uids = f.messages.keys;
    return FolderStatus(
      uidValidity: f.uidValidity,
      uidNext: uids.isEmpty ? 1 : uids.reduce((a, b) => a > b ? a : b) + 1,
      exists: uids.length,
    );
  }

  @override
  Future<List<int>> listUids(String path) async {
    _check();
    // Come un server con SORT: in ordine di data, dal più vecchio.
    final f = folders[path]!;
    final uids = f.messages.keys.toList()
      ..sort((a, b) {
        final da = f.messages[a]!.date, db = f.messages[b]!.date;
        final byDate = (da ?? DateTime(0)).compareTo(db ?? DateTime(0));
        return byDate != 0 ? byDate : a.compareTo(b);
      });
    return uids;
  }

  @override
  Future<List<MessageSummary>> fetchSummaries(
    String path,
    List<int> uids,
  ) async {
    _check();
    fetchedSummaries += uids.length;
    final f = folders[path]!;
    return [
      for (final u in uids)
        if (f.messages[u] != null) f.messages[u]!,
    ];
  }

  @override
  Future<Map<int, MessageFlagsState>> fetchFlags(
    String path,
    List<int> uids,
  ) async {
    _check();
    final f = folders[path]!;
    return {
      for (final u in uids)
        if (f.messages[u] != null)
          u: (
            seen: f.messages[u]!.seen,
            flagged: f.messages[u]!.flagged,
            answered: f.messages[u]!.answered,
          ),
    };
  }

  @override
  Future<List<int>> search(String path, String query) async {
    _check();
    final q = query.toLowerCase();
    return [
      for (final m in folders[path]!.messages.values)
        if (m.subject.toLowerCase().contains(q)) m.uid,
    ]..sort();
  }

  @override
  Future<MessageContent> fetchMessage(String path, int uid) async {
    _check();
    final f = folders[path]!;
    return MessageContent(
      summary: f.messages[uid]!,
      cc: const [],
      replyTo: const [],
      messageId: '<m$uid@esempio.org>',
      references: const [],
      plainText: f.bodies[uid],
      html: null,
      attachments: const [],
      inlineImages: const {},
    );
  }

  @override
  Future<Uint8List> fetchAttachment(
    String path,
    int uid,
    String fetchId,
  ) async => Uint8List.fromList([1, 2, 3]);

  void _update(
    String path,
    List<int> uids,
    MessageSummary Function(MessageSummary) change,
  ) {
    final f = folders[path]!;
    for (final u in uids) {
      final m = f.messages[u];
      if (m != null) f.messages[u] = change(m);
    }
  }

  @override
  Future<void> setSeen(
    String path,
    List<int> uids, {
    required bool seen,
  }) async {
    _check();
    _update(path, uids, (m) => m.copyWith(seen: seen));
  }

  @override
  Future<void> setFlagged(
    String path,
    List<int> uids, {
    required bool flagged,
  }) async {
    _check();
    _update(path, uids, (m) => m.copyWith(flagged: flagged));
  }

  @override
  Future<void> setAnswered(String path, List<int> uids) async {
    _check();
    _update(path, uids, (m) => m.copyWith(answered: true));
  }

  @override
  Future<void> move(String path, List<int> uids, String targetPath) async {
    _check();
    final from = folders[path]!;
    final to = folders[targetPath]!;
    var next = to.messages.keys.fold(0, (a, b) => a > b ? a : b) + 1;
    for (final u in uids) {
      final m = from.messages.remove(u);
      if (m == null) continue;
      // Nella cartella di arrivo il messaggio ha un UID nuovo.
      to.messages[next] = MessageSummary(
        uid: next,
        from: m.from,
        to: m.to,
        subject: m.subject,
        date: m.date,
        preview: m.preview,
        seen: m.seen,
        flagged: m.flagged,
        answered: m.answered,
        hasAttachments: m.hasAttachments,
      );
      to.bodies[next] = from.bodies.remove(u) ?? '';
      next++;
    }
  }

  @override
  Future<void> deletePermanently(String path, List<int> uids) async {
    _check();
    uids.forEach(folders[path]!.messages.remove);
  }

  @override
  Future<void> append(
    String path,
    String rawMessage, {
    List<String> flags = const [],
  }) async {
    _check();
    appended.add((path, flags));
  }

  @override
  Future<String> send(OutgoingMessage message) async {
    _check();
    sent.add(message);
    return render(message);
  }

  @override
  String render(OutgoingMessage message) =>
      'Subject: ${message.subject}\r\n\r\n${message.body}';

  @override
  Future<void> close() async => closed = true;
}

/// Crea sempre lo stesso [FakeMailService].
class FakeMailServiceFactory implements MailServiceFactory {
  /// Crea la fabbrica.
  FakeMailServiceFactory(this.service);

  /// Il server finto.
  final FakeMailService service;

  /// Risultato di [check].
  ConnectionCheckResult checkResult = const ConnectionCheckResult(
    folderCount: 5,
  );

  @override
  Future<MailService> connect(Account account, String password) async =>
      service;

  @override
  Future<ConnectionCheckResult> check(Account account, String password) async =>
      checkResult;
}

/// File finti: niente plugin.
class FakeFileActions implements FileActions {
  /// Link aperti.
  final List<Uri> opened = [];

  @override
  Future<void> openAttachment(String fileName, Uint8List bytes) async {}

  @override
  Future<void> openLink(Uri uri) async => opened.add(uri);

  @override
  Future<List<OutgoingAttachment>> pickAttachments() async => const [];
}

/// Account in memoria: nei widget test l'I/O vero su file non finisce mai
/// (il tempo è finto), quindi sostituiamo il repository.
class MemoryAccountRepository implements AccountRepository {
  /// Crea il repository con [initial] già salvati.
  MemoryAccountRepository(this.secrets, [List<Account> initial = const []])
    : _accounts = [...initial];

  final List<Account> _accounts;

  @override
  final SecretStore secrets;

  @override
  File get file => throw UnimplementedError();

  @override
  Future<List<Account>> load() async => List.of(_accounts);

  @override
  Future<void> save(Account account, String password) async {
    await secrets.write('pwd.${account.id}', password);
    _accounts
      ..removeWhere((a) => a.id == account.id)
      ..add(account);
  }

  @override
  Future<String?> password(String accountId) => secrets.read('pwd.$accountId');

  @override
  Future<void> remove(String accountId) async {
    await secrets.delete('pwd.$accountId');
    _accounts.removeWhere((a) => a.id == accountId);
  }
}
