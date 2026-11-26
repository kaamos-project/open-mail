import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/mail_service.dart';
import '../core/models.dart';
import '../core/text_utils.dart';
import '../data/imap_mail_service.dart' show describeMailError;
import '../data/mail_cache.dart';

/// Lo stato della casella di un account: cartelle, lista, messaggio aperto.
///
/// Niente librerie di stato: un `ChangeNotifier` e `ListenableBuilder` nella
/// UI, come nella libreria `kaamos_project_ui`. La UI legge i campi e chiama
/// i metodi; non parla mai con IMAP o SQLite direttamente.
///
/// Flusso di una cartella (opzione A decisa con Alessio):
/// 1. si mostra subito quello che c'è in cache;
/// 2. si chiede al server `UIDVALIDITY` e la lista degli UID;
/// 3. si scaricano solo i messaggi nuovi, si aggiornano i flag di quelli
///    noti e si tolgono quelli spariti;
/// 4. si rilegge la cache e si avvisa la UI.
class MailboxController extends ChangeNotifier {
  /// Crea il controller. La connessione arriva da [connect], così la UI può
  /// partire dalla cache anche senza rete.
  MailboxController({
    required this.account,
    required this.cache,
    required Future<MailService> Function() connect,
    this.pageSize = 50,
  }) : _connect = connect;

  /// L'account mostrato.
  final Account account;

  /// La cache locale.
  final MailCache cache;

  /// Quanti messaggi scaricare per volta.
  final int pageSize;

  /// Quante date di arrivo chiedere per comando: ~50 byte l'una, quindi un
  /// blocco è circa 100 KB.
  static const _dateChunk = 2000;

  final Future<MailService> Function() _connect;
  MailService? _service;
  Future<MailService>? _connecting;

  /// Le cartelle (dalla cache finché il server non risponde).
  List<Folder> folders = const [];

  /// La cartella aperta.
  Folder current = const Folder(
    path: 'INBOX',
    name: 'INBOX',
    role: FolderRole.inbox,
  );

  /// La lista della cartella aperta (o i risultati della ricerca).
  List<MessageSummary> messages = const [];

  /// Il testo cercato, `null` se non si sta cercando.
  String? searchQuery;

  /// UID del messaggio aperto.
  int? openUid;

  /// Contenuto del messaggio aperto, `null` mentre si scarica.
  MessageContent? openMessage;

  /// Sincronizzazione in corso.
  bool syncing = false;

  /// Download del messaggio aperto in corso.
  bool loadingMessage = false;

  /// Ultimo errore da mostrare, `null` se tutto va bene.
  String? error;

  /// Quando la cartella è stata aggiornata l'ultima volta.
  DateTime? lastSync;

  /// Tutti gli UID della cartella sul server, crescenti.
  List<int> _serverUids = const [];

  /// Quanti messaggi della cartella mostriamo (cresce con "carica altri").
  int _window = 0;

  bool _disposed = false;

  /// Ci sono messaggi più vecchi da scaricare.
  bool get hasMore => searchQuery == null && _serverUids.length > _window;

  /// Quanti messaggi ci sono nella cartella sul server.
  int get totalOnServer => _serverUids.length;

  /// La cartella con un certo ruolo, se il server ce l'ha.
  Folder? folderWithRole(FolderRole role) =>
      folders.where((f) => f.role == role).firstOrNull;

  Future<MailService> _ensureService() {
    final service = _service;
    if (service != null) return Future.value(service);
    return _connecting ??= _connect()
        .then((s) {
          _service = s;
          return s;
        })
        .whenComplete(() => _connecting = null);
  }

  /// Primo avvio: cache subito, poi server.
  Future<void> start() async {
    folders = cache.loadFolders(account.id);
    current = folderWithRole(FolderRole.inbox) ?? current;
    messages = cache.loadSummaries(account.id, current.path);
    _window = messages.length;
    _notify();
    await refresh(withFolders: true);
  }

  /// Aggiorna la cartella aperta dal server.
  Future<void> refresh({bool withFolders = false}) async {
    if (syncing) return;
    syncing = true;
    error = null;
    _notify();
    try {
      final service = await _ensureService();
      if (withFolders || folders.isEmpty) {
        final serverFolders = await service.listFolders();
        cache.saveFolders(account.id, serverFolders);
        folders = cache.loadFolders(account.id);
        current =
            folders.where((f) => f.path == current.path).firstOrNull ??
            folderWithRole(FolderRole.inbox) ??
            current;
      }
      await _syncFolder(service, current.path);
      lastSync = DateTime.now();
    } on Object catch (e) {
      error = describeMailError(e);
    } finally {
      syncing = false;
      _notify();
    }
  }

  Future<void> _syncFolder(MailService service, String path) async {
    final status = await service.openFolder(path);
    cache.checkUidValidity(account.id, path, status.uidValidity);
    final serverSet = (await service.listUids(path)).toSet();

    // Spariti dal server: cancellati o spostati da un altro client.
    final dated = cache.datedUids(account.id, path);
    cache.removeUids(
      account.id,
      path,
      {
        ...cache.cachedUids(account.id, path),
        ...dated,
      }.where((u) => !serverSet.contains(u)),
    );

    // Le date di arrivo dei messaggi mai visti: la prima volta tutte, poi
    // solo i nuovi. A blocchi, per non mandare comandi enormi.
    final undated = [
      for (final u in serverSet)
        if (!dated.contains(u)) u,
    ]..sort();
    for (var i = 0; i < undated.length; i += _dateChunk) {
      final chunk = undated.sublist(
        i,
        math.min(i + _dateChunk, undated.length),
      );
      cache.saveArrivalDates(
        account.id,
        path,
        await service.fetchArrivalDates(path, chunk),
      );
    }

    // Ordine per data (non per UID: una mail vecchia appena spostata ha
    // l'UID più alto della cartella).
    final serverUids = cache.uidsByArrival(account.id, path);
    _serverUids = serverUids;
    final cached = cache.cachedUids(account.id, path);

    // La finestra visibile: gli ultimi N messaggi per data.
    _window = math.min(math.max(_window, pageSize), serverUids.length);
    final window = serverUids.sublist(serverUids.length - _window);
    final cachedSet = cached.toSet();
    final missing = [
      for (final u in window)
        if (!cachedSet.contains(u)) u,
    ];
    final known = [
      for (final u in window)
        if (cachedSet.contains(u)) u,
    ];

    for (var i = 0; i < missing.length; i += pageSize) {
      final chunk = missing.sublist(i, math.min(i + pageSize, missing.length));
      cache.upsertSummaries(
        account.id,
        path,
        await service.fetchSummaries(path, chunk),
      );
    }
    if (known.isNotEmpty) {
      cache.updateFlags(
        account.id,
        path,
        await service.fetchFlags(path, known),
      );
    }
    if (current.path == path && searchQuery == null) {
      messages = cache.loadSummaries(account.id, path, limit: _window);
    }
  }

  /// Scarica la pagina successiva di messaggi più vecchi.
  Future<void> loadMore() async {
    if (!hasMore || syncing) return;
    _window = math.min(_window + pageSize, _serverUids.length);
    await refresh();
  }

  /// Apre un'altra cartella.
  Future<void> selectFolder(Folder folder) async {
    if (folder.path == current.path && searchQuery == null) return;
    current = folder;
    searchQuery = null;
    openUid = null;
    openMessage = null;
    _serverUids = const [];
    messages = cache.loadSummaries(account.id, folder.path);
    _window = messages.length;
    _notify();
    await refresh();
  }

  /// Cerca sul server nella cartella aperta. Stringa vuota = fine ricerca.
  Future<void> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      searchQuery = null;
      messages = cache.loadSummaries(account.id, current.path, limit: _window);
      _notify();
      return;
    }
    searchQuery = q;
    syncing = true;
    error = null;
    _notify();
    try {
      final service = await _ensureService();
      final uids = await service.search(current.path, q);
      // I più recenti prima, al massimo una pagina.
      final top = uids.reversed.take(pageSize).toList();
      final results = await service.fetchSummaries(current.path, top);
      results.sort((a, b) => b.uid.compareTo(a.uid));
      if (searchQuery == q) messages = results;
    } on Object catch (e) {
      error = describeMailError(e);
    } finally {
      syncing = false;
      _notify();
    }
  }

  /// Apre un messaggio e lo segna come letto.
  Future<void> open(int uid) async {
    openUid = uid;
    openMessage = null;
    loadingMessage = true;
    error = null;
    _notify();
    try {
      final service = await _ensureService();
      final content = await service.fetchMessage(current.path, uid);
      if (openUid != uid) return;
      openMessage = content;
      final summary = _find(uid);
      if (summary != null && !summary.seen) {
        await setSeen([uid], seen: true);
      }
    } on Object catch (e) {
      if (openUid == uid) error = describeMailError(e);
    } finally {
      if (openUid == uid) loadingMessage = false;
      _notify();
    }
  }

  /// Chiude il messaggio aperto (su mobile: torna alla lista).
  void closeMessage() {
    openUid = null;
    openMessage = null;
    loadingMessage = false;
    _notify();
  }

  MessageSummary? _find(int uid) =>
      messages.where((m) => m.uid == uid).firstOrNull;

  /// Aggiorna subito la UI e la cache, poi il server. Se il server
  /// fallisce, torna indietro: l'interfaccia non deve mentire.
  Future<void> _optimistic(
    List<int> uids,
    MessageSummary Function(MessageSummary) change,
    Future<void> Function(MailService) remote,
  ) async {
    final before = messages;
    final set = uids.toSet();
    messages = [for (final m in messages) set.contains(m.uid) ? change(m) : m];
    cache.upsertSummaries(account.id, current.path, [
      for (final m in messages)
        if (set.contains(m.uid)) m,
    ]);
    _notify();
    try {
      await remote(await _ensureService());
    } on Object catch (e) {
      messages = before;
      cache.upsertSummaries(account.id, current.path, [
        for (final m in before)
          if (set.contains(m.uid)) m,
      ]);
      error = describeMailError(e);
      _notify();
    }
  }

  /// Letto / non letto.
  Future<void> setSeen(List<int> uids, {required bool seen}) => _optimistic(
    uids,
    (m) => m.copyWith(seen: seen),
    (s) => s.setSeen(current.path, uids, seen: seen),
  );

  /// Stella sì / no.
  Future<void> setFlagged(List<int> uids, {required bool flagged}) =>
      _optimistic(
        uids,
        (m) => m.copyWith(flagged: flagged),
        (s) => s.setFlagged(current.path, uids, flagged: flagged),
      );

  /// Toglie i messaggi dalla lista e dalla cache, poi esegue [remote].
  Future<void> _removeFromList(
    List<int> uids,
    Future<void> Function(MailService) remote,
  ) async {
    final before = messages;
    final set = uids.toSet();
    messages = [
      for (final m in messages)
        if (!set.contains(m.uid)) m,
    ];
    if (openUid != null && set.contains(openUid)) closeMessage();
    _notify();
    try {
      await remote(await _ensureService());
      cache.removeUids(account.id, current.path, uids);
      _serverUids = [
        for (final u in _serverUids)
          if (!set.contains(u)) u,
      ];
      _window = math.min(_window, _serverUids.length);
    } on Object catch (e) {
      messages = before;
      error = describeMailError(e);
      _notify();
    }
  }

  /// Sposta in una cartella.
  Future<void> move(List<int> uids, Folder target) =>
      _removeFromList(uids, (s) => s.move(current.path, uids, target.path));

  /// Archivia (se il server ha una cartella Archivio).
  Future<void> archive(List<int> uids) async {
    final target = folderWithRole(FolderRole.archive);
    if (target == null) {
      error = 'Questo account non ha una cartella Archivio.';
      _notify();
      return;
    }
    await move(uids, target);
  }

  /// Elimina: sposta nel Cestino; se sei già nel Cestino (o non c'è),
  /// cancella per sempre.
  Future<void> delete(List<int> uids) {
    final trash = folderWithRole(FolderRole.trash);
    if (trash == null || trash.path == current.path) {
      return _removeFromList(
        uids,
        (s) => s.deletePermanently(current.path, uids),
      );
    }
    return move(uids, trash);
  }

  /// Invia un messaggio, ne salva una copia in Inviati e, se è una
  /// risposta, segna l'originale come risposto.
  Future<void> send(OutgoingMessage message, {int? answeredUid}) async {
    final service = await _ensureService();
    final raw = await service.send(message);
    final sent = folderWithRole(FolderRole.sent);
    // Gmail salva da solo una copia in Inviati: aggiungerla noi la
    // duplicherebbe.
    final serverSavesSent = account.smtp.host.toLowerCase().endsWith(
      'gmail.com',
    );
    if (sent != null && !serverSavesSent) {
      try {
        await service.append(sent.path, raw, flags: const [r'\Seen']);
      } on Object catch (e) {
        error =
            'Inviato, ma la copia in Inviati non è stata salvata: '
            '${describeMailError(e)}';
        _notify();
      }
    }
    if (answeredUid != null) {
      unawaited(
        _optimistic(
          [answeredUid],
          (m) => m.copyWith(answered: true),
          (s) => s.setAnswered(current.path, [answeredUid]),
        ),
      );
    }
  }

  /// Salva una bozza nella cartella Bozze. Restituisce `false` se l'account
  /// non ha una cartella Bozze.
  Future<bool> saveDraft(OutgoingMessage message) async {
    final drafts = folderWithRole(FolderRole.drafts);
    if (drafts == null) return false;
    final service = await _ensureService();
    await service.append(
      drafts.path,
      service.render(message),
      flags: const [r'\Draft', r'\Seen'],
    );
    return true;
  }

  /// Scarica un allegato del messaggio aperto.
  Future<Uint8List> downloadAttachment(AttachmentInfo attachment) async {
    final uid = openUid;
    if (uid == null) throw StateError('Nessun messaggio aperto');
    final service = await _ensureService();
    return service.fetchAttachment(current.path, uid, attachment.fetchId);
  }

  /// Nasconde l'errore mostrato.
  void dismissError() {
    error = null;
    _notify();
  }

  /// Etichetta della cartella aperta.
  String get currentLabel => folderLabel(current);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final service = _service;
    _service = null;
    if (service != null) unawaited(service.close());
    super.dispose();
  }
}
