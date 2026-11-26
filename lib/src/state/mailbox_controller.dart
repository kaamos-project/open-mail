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

  /// Cartella del messaggio aperto. Di solito è [current], ma dall'Inbox
  /// unificata si apre un messaggio della Inbox anche se l'account sta
  /// guardando un'altra cartella.
  String? openPath;

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
    final isCurrent = current.path == path;
    final cached = cache.cachedUids(account.id, path);

    // La finestra visibile: gli ultimi N messaggi per data. Per una
    // cartella sincronizzata in sottofondo (la Inbox per la vista
    // unificata) basta la prima pagina.
    final size = math.min(
      isCurrent ? math.max(_window, pageSize) : pageSize,
      serverUids.length,
    );
    if (isCurrent) {
      _serverUids = serverUids;
      _window = size;
    }
    final window = serverUids.sublist(serverUids.length - size);
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
    if (isCurrent && searchQuery == null) {
      messages = cache.loadSummaries(account.id, path, limit: _window);
    }
  }

  bool _inboxSyncing = false;

  /// La Inbox si sta aggiornando (in sottofondo o perché è aperta).
  bool get inboxSyncing =>
      _inboxSyncing || (syncing && current.path == inbox.path);

  /// La Inbox, anche se il server non la dichiara con SPECIAL-USE.
  Folder get inbox =>
      folderWithRole(FolderRole.inbox) ??
      const Folder(path: 'INBOX', name: 'INBOX', role: FolderRole.inbox);

  /// Aggiorna la Inbox senza cambiare la cartella aperta: serve all'Inbox
  /// unificata, che legge le Inbox di tutti gli account dalla cache.
  Future<void> syncInbox() async {
    if (inbox.path == current.path) return refresh();
    if (_inboxSyncing) return;
    _inboxSyncing = true;
    _notify();
    try {
      await _syncFolder(await _ensureService(), inbox.path);
    } on Object catch (e) {
      error = describeMailError(e);
    } finally {
      _inboxSyncing = false;
      _notify();
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

  /// Apre un messaggio (della cartella aperta, o di [path]) e lo segna
  /// come letto.
  Future<void> open(int uid, {String? path}) async {
    final folder = path ?? current.path;
    openUid = uid;
    openPath = folder;
    openMessage = null;
    loadingMessage = true;
    error = null;
    _notify();
    try {
      final service = await _ensureService();
      final content = await service.fetchMessage(folder, uid);
      if (openUid != uid) return;
      openMessage = content;
      final summary = _summaries(folder, [uid]).firstOrNull;
      if (summary != null && !summary.seen) {
        await setSeen([uid], seen: true, path: folder);
      }
    } on Object catch (e) {
      if (openUid == uid) error = describeMailError(e);
    } finally {
      if (openUid == uid) loadingMessage = false;
      _notify();
    }
  }

  /// La riga del messaggio aperto, con stella e letto aggiornati (il
  /// contenuto scaricato resta com'era al momento dell'apertura).
  MessageSummary? get openSummary {
    final uid = openUid;
    if (uid == null) return null;
    return _summaries(openPath ?? current.path, [uid]).firstOrNull;
  }

  /// La cartella del messaggio aperto.
  Folder get openFolder {
    final path = openPath;
    if (path == null || path == current.path) return current;
    return folders.where((f) => f.path == path).firstOrNull ??
        Folder(path: path, name: path, role: FolderRole.other);
  }

  /// Chiude il messaggio aperto (su mobile: torna alla lista).
  void closeMessage() {
    openUid = null;
    openPath = null;
    openMessage = null;
    loadingMessage = false;
    _notify();
  }

  /// Le righe di [uids] in [path]: dalla lista se è la cartella aperta
  /// (copre anche i risultati di ricerca, che non sono in cache),
  /// altrimenti dalla cache.
  List<MessageSummary> _summaries(String path, Iterable<int> uids) {
    final set = uids.toSet();
    if (path == current.path) {
      final inList = [
        for (final m in messages)
          if (set.contains(m.uid)) m,
      ];
      if (inList.length == set.length) return inList;
    }
    return cache.summariesFor(account.id, path, set);
  }

  /// Rimette [rows] nella lista (se è la cartella aperta) e in cache.
  void _apply(String path, List<MessageSummary> rows) {
    final byUid = {for (final m in rows) m.uid: m};
    if (path == current.path) {
      messages = [for (final m in messages) byUid[m.uid] ?? m];
    }
    final cached = cache
        .summariesFor(account.id, path, byUid.keys)
        .map((m) => m.uid);
    cache.upsertSummaries(account.id, path, [
      for (final uid in cached) byUid[uid]!,
    ]);
  }

  /// Aggiorna subito la UI e la cache, poi il server. Se il server
  /// fallisce, torna indietro: l'interfaccia non deve mentire.
  Future<void> _optimistic(
    String path,
    List<int> uids,
    MessageSummary Function(MessageSummary) change,
    Future<void> Function(MailService) remote,
  ) async {
    final before = _summaries(path, uids);
    _apply(path, [for (final m in before) change(m)]);
    _notify();
    try {
      await remote(await _ensureService());
    } on Object catch (e) {
      _apply(path, before);
      error = describeMailError(e);
      _notify();
    }
  }

  /// Letto / non letto. [path]: cartella dei messaggi, di default quella
  /// aperta.
  Future<void> setSeen(List<int> uids, {required bool seen, String? path}) {
    final folder = path ?? current.path;
    return _optimistic(
      folder,
      uids,
      (m) => m.copyWith(seen: seen),
      (s) => s.setSeen(folder, uids, seen: seen),
    );
  }

  /// Stella sì / no.
  Future<void> setFlagged(
    List<int> uids, {
    required bool flagged,
    String? path,
  }) {
    final folder = path ?? current.path;
    return _optimistic(
      folder,
      uids,
      (m) => m.copyWith(flagged: flagged),
      (s) => s.setFlagged(folder, uids, flagged: flagged),
    );
  }

  /// Toglie i messaggi da lista e cache, poi esegue [remote]. Se il server
  /// rifiuta, tornano al loro posto.
  Future<void> _removeFromList(
    String path,
    List<int> uids,
    Future<void> Function(MailService) remote,
  ) async {
    final set = uids.toSet();
    final isCurrent = path == current.path;
    final beforeList = messages;
    final beforeRows = cache.summariesFor(account.id, path, set);
    if (isCurrent) {
      messages = [
        for (final m in messages)
          if (!set.contains(m.uid)) m,
      ];
    }
    cache.removeUids(account.id, path, set);
    if (openPath == path && openUid != null && set.contains(openUid)) {
      closeMessage();
    }
    _notify();
    try {
      await remote(await _ensureService());
      if (isCurrent) {
        _serverUids = [
          for (final u in _serverUids)
            if (!set.contains(u)) u,
        ];
        _window = math.min(_window, _serverUids.length);
      }
    } on Object catch (e) {
      if (isCurrent) messages = beforeList;
      cache.upsertSummaries(account.id, path, beforeRows);
      error = describeMailError(e);
      _notify();
    }
  }

  /// Sposta in una cartella.
  Future<void> move(List<int> uids, Folder target, {String? path}) {
    final folder = path ?? current.path;
    return _removeFromList(
      folder,
      uids,
      (s) => s.move(folder, uids, target.path),
    );
  }

  /// Archivia (se il server ha una cartella Archivio).
  Future<void> archive(List<int> uids, {String? path}) async {
    final target = folderWithRole(FolderRole.archive);
    if (target == null) {
      error = 'Questo account non ha una cartella Archivio.';
      _notify();
      return;
    }
    await move(uids, target, path: path);
  }

  /// Elimina: sposta nel Cestino; se sei già nel Cestino (o non c'è),
  /// cancella per sempre.
  Future<void> delete(List<int> uids, {String? path}) {
    final folder = path ?? current.path;
    final trash = folderWithRole(FolderRole.trash);
    if (trash == null || trash.path == folder) {
      return _removeFromList(
        folder,
        uids,
        (s) => s.deletePermanently(folder, uids),
      );
    }
    return move(uids, trash, path: folder);
  }

  /// Invia un messaggio, ne salva una copia in Inviati e, se è una
  /// risposta, segna l'originale come risposto.
  Future<void> send(
    OutgoingMessage message, {
    int? answeredUid,
    String? answeredPath,
  }) async {
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
      final folder = answeredPath ?? current.path;
      unawaited(
        _optimistic(
          folder,
          [answeredUid],
          (m) => m.copyWith(answered: true),
          (s) => s.setAnswered(folder, [answeredUid]),
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
    return service.fetchAttachment(
      openPath ?? current.path,
      uid,
      attachment.fetchId,
    );
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
