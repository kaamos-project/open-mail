import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/mail_errors.dart';
import '../core/mail_service.dart';
import '../core/models.dart';
import '../core/text_utils.dart';
import '../data/mail_cache.dart';

/// The mailbox state of one account: folders, list, open message.
///
/// No state management library: a `ChangeNotifier` and `ListenableBuilder` in
/// the UI, as in the `kaamos_project_ui` library. The UI reads the fields and
/// calls the methods; it never talks to IMAP or SQLite directly.
///
/// Folder flow (option A, agreed with Alessio):
/// 1. show what is in the cache right away;
/// 2. ask the server for `UIDVALIDITY` and the list of UIDs;
/// 3. download only new messages, update the flags of known ones and drop the
///    ones that disappeared;
/// 4. re-read the cache and notify the UI.
class MailboxController extends ChangeNotifier {
  /// Creates the controller. The connection comes from [connect], so the UI can
  /// start from the cache even without a network.
  MailboxController({
    required this.account,
    required this.cache,
    required Future<MailService> Function() connect,
    this.pageSize = 50,
  }) : _connect = connect;

  /// The account shown.
  final Account account;

  /// The local cache.
  final MailCache cache;

  /// How many messages to download at a time.
  final int pageSize;

  /// How many arrival dates to ask for per command: ~50 bytes each, so a chunk
  /// is about 100 KB.
  static const _dateChunk = 2000;

  final Future<MailService> Function() _connect;
  MailService? _service;
  Future<MailService>? _connecting;

  /// The folders (from the cache until the server answers).
  List<Folder> folders = const [];

  /// The open folder.
  Folder current = const Folder(
    path: 'INBOX',
    name: 'INBOX',
    role: FolderRole.inbox,
  );

  /// The list of the open folder (or the search results).
  List<MessageSummary> messages = const [];

  /// The search text, `null` when not searching.
  String? searchQuery;

  /// UID of the open message.
  int? openUid;

  /// Folder of the open message. Usually [current], but the unified Inbox opens
  /// an Inbox message even while the account is showing another folder.
  String? openPath;

  /// Content of the open message, `null` while downloading.
  MessageContent? openMessage;

  /// Sync in progress.
  bool syncing = false;

  /// Download of the open message in progress.
  bool loadingMessage = false;

  /// Last error to show, `null` if all is well.
  String? error;

  /// When the folder was last refreshed.
  DateTime? lastSync;

  /// All UIDs of the folder on the server, ascending.
  List<int> _serverUids = const [];

  /// How many messages of the folder we show (grows with "load more").
  int _window = 0;

  bool _disposed = false;

  /// There are older messages to download.
  bool get hasMore => searchQuery == null && _serverUids.length > _window;

  /// How many messages the folder holds on the server.
  int get totalOnServer => _serverUids.length;

  /// The folder with a given role, if the server has one.
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

  /// First start: cache right away, then the server.
  Future<void> start() async {
    folders = cache.loadFolders(account.id);
    current = folderWithRole(FolderRole.inbox) ?? current;
    messages = cache.loadSummaries(account.id, current.path);
    _window = messages.length;
    _notify();
    await refresh(withFolders: true);
  }

  /// Refreshes the open folder from the server.
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
    } on MailFailure catch (e) {
      error = e.message;
    } catch (e, st) {
      error = describeInternalError(e, st);
    } finally {
      syncing = false;
      _notify();
    }
  }

  Future<void> _syncFolder(MailService service, String path) async {
    final status = await service.openFolder(path);
    cache.checkUidValidity(account.id, path, status.uidValidity);
    final serverSet = (await service.listUids(path)).toSet();

    // Gone from the server: deleted or moved by another client.
    final dated = cache.datedUids(account.id, path);
    cache.removeUids(
      account.id,
      path,
      {
        ...cache.cachedUids(account.id, path),
        ...dated,
      }.where((u) => !serverSet.contains(u)),
    );

    // Arrival dates of messages never seen before: all of them the first time,
    // then only new ones. In chunks, to avoid huge commands.
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

    // Order by date (not by UID: an old mail that was just moved has the
    // highest UID in the folder).
    final serverUids = cache.uidsByArrival(account.id, path);
    final isCurrent = current.path == path;
    final cached = cache.cachedUids(account.id, path);

    // The visible window: the latest N messages by date. For a folder synced in
    // the background (the Inbox for the unified view) the first page is enough.
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

  /// The Inbox is refreshing (in the background or because it is open).
  bool get inboxSyncing =>
      _inboxSyncing || (syncing && current.path == inbox.path);

  /// The Inbox, even if the server doesn't declare it with SPECIAL-USE.
  Folder get inbox =>
      folderWithRole(FolderRole.inbox) ??
      const Folder(path: 'INBOX', name: 'INBOX', role: FolderRole.inbox);

  /// Refreshes the Inbox without changing the open folder: used by the unified
  /// Inbox, which reads every account's Inbox from the cache.
  Future<void> syncInbox() async {
    if (inbox.path == current.path) return refresh();
    if (_inboxSyncing) return;
    _inboxSyncing = true;
    _notify();
    try {
      await _syncFolder(await _ensureService(), inbox.path);
    } on MailFailure catch (e) {
      error = e.message;
    } catch (e, st) {
      error = describeInternalError(e, st);
    } finally {
      _inboxSyncing = false;
      _notify();
    }
  }

  /// Downloads the next page of older messages.
  Future<void> loadMore() async {
    if (!hasMore || syncing) return;
    _window = math.min(_window + pageSize, _serverUids.length);
    await refresh();
  }

  /// Opens another folder.
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

  /// Searches the open folder on the server. Empty string = end search.
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
      // Newest first, at most one page.
      final top = uids.reversed.take(pageSize).toList();
      // Copy: the service may return an unmodifiable list (const [] when
      // nothing matches), and sorting it in place would throw.
      final results = [...await service.fetchSummaries(current.path, top)];
      results.sort((a, b) => b.uid.compareTo(a.uid));
      if (searchQuery == q) messages = results;
    } on MailFailure catch (e) {
      error = e.message;
    } catch (e, st) {
      error = describeInternalError(e, st);
    } finally {
      syncing = false;
      _notify();
    }
  }

  /// Opens a message (of the open folder, or of [path]) and marks it as read.
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
    } on MailFailure catch (e) {
      if (openUid == uid) error = e.message;
    } catch (e, st) {
      if (openUid == uid) error = describeInternalError(e, st);
    } finally {
      if (openUid == uid) loadingMessage = false;
      _notify();
    }
  }

  /// The row of the open message, with up-to-date star and read state (the
  /// downloaded content stays as it was when opened).
  MessageSummary? get openSummary {
    final uid = openUid;
    if (uid == null) return null;
    return _summaries(openPath ?? current.path, [uid]).firstOrNull;
  }

  /// The folder of the open message.
  Folder get openFolder {
    final path = openPath;
    if (path == null || path == current.path) return current;
    return folders.where((f) => f.path == path).firstOrNull ??
        Folder(path: path, name: path, role: FolderRole.other);
  }

  /// Closes the open message (on mobile: back to the list).
  void closeMessage() {
    openUid = null;
    openPath = null;
    openMessage = null;
    loadingMessage = false;
    _notify();
  }

  /// The rows of [uids] in [path]: from the list if it is the open folder (this
  /// also covers search results, which aren't cached), otherwise from the
  /// cache.
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

  /// Puts [rows] back in the list (if it is the open folder) and in the cache.
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

  /// Updates the UI and the cache right away, then the server. If the server
  /// fails, it rolls back: the interface must not lie.
  Future<void> _optimistic(
    String path,
    List<int> uids,
    MessageSummary Function(MessageSummary) change,
    Future<void> Function(MailService) remote,
  ) async {
    final before = _summaries(path, uids);
    _apply(path, [for (final m in before) change(m)]);
    _notify();
    // Puts the rows back as they were and shows why.
    void undo(String message) {
      _apply(path, before);
      error = message;
      _notify();
    }

    try {
      await remote(await _ensureService());
    } on MailFailure catch (e) {
      undo(e.message);
    } catch (e, st) {
      undo(describeInternalError(e, st));
    }
  }

  /// Read / unread. [path]: folder of the messages, the open one by default.
  Future<void> setSeen(List<int> uids, {required bool seen, String? path}) {
    final folder = path ?? current.path;
    return _optimistic(
      folder,
      uids,
      (m) => m.copyWith(seen: seen),
      (s) => s.setSeen(folder, uids, seen: seen),
    );
  }

  /// Removes a Gmail label from a message: at once on screen and in the
  /// cache, then on the server; back as it was if the server refuses.
  Future<void> removeLabel(int uid, String label, {String? path}) {
    final folder = path ?? current.path;
    return _optimistic(
      folder,
      [uid],
      (m) => m.copyWith(
        labels: [
          for (final l in m.labels)
            if (l != label) l,
        ],
      ),
      (s) => s.storeLabels(folder, [uid], [label], add: false),
    );
  }

  /// Star on / off.
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

  /// Removes the messages from list and cache, then runs [remote]. If the
  /// server refuses, they go back where they were.
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
    // Puts the rows back as they were and shows why.
    void undo(String message) {
      if (isCurrent) messages = beforeList;
      cache.upsertSummaries(account.id, path, beforeRows);
      error = message;
      _notify();
    }

    try {
      await remote(await _ensureService());
      if (isCurrent) {
        _serverUids = [
          for (final u in _serverUids)
            if (!set.contains(u)) u,
        ];
        _window = math.min(_window, _serverUids.length);
      }
    } on MailFailure catch (e) {
      undo(e.message);
    } catch (e, st) {
      undo(describeInternalError(e, st));
    }
  }

  /// Moves to a folder.
  Future<void> move(List<int> uids, Folder target, {String? path}) {
    final folder = path ?? current.path;
    return _removeFromList(
      folder,
      uids,
      (s) => s.move(folder, uids, target.path),
    );
  }

  /// Archives (if the server has an Archive folder).
  Future<void> archive(List<int> uids, {String? path}) async {
    final target = folderWithRole(FolderRole.archive);
    if (target == null) {
      error = 'Questo account non ha una cartella Archivio.';
      _notify();
      return;
    }
    await move(uids, target, path: path);
  }

  /// Delete: moves to the Trash; if you are already in the Trash (or there is
  /// none), deletes for good.
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

  /// Sends a message, saves a copy in Sent and, if it is a reply, marks the
  /// original as answered.
  Future<void> send(
    OutgoingMessage message, {
    int? answeredUid,
    String? answeredPath,
  }) async {
    final service = await _ensureService();
    final raw = await service.send(message);
    final sent = folderWithRole(FolderRole.sent);
    // Gmail saves a copy in Sent on its own: adding one ourselves would
    // duplicate it.
    final serverSavesSent = account.smtp.host.toLowerCase().endsWith(
      'gmail.com',
    );
    if (sent != null && !serverSavesSent) {
      try {
        await service.append(sent.path, raw, flags: const [r'\Seen']);
      } on MailFailure catch (e) {
        error =
            'Inviato, ma la copia in Inviati non è stata salvata: '
            '${e.message}';
        _notify();
      } catch (e, st) {
        error =
            'Inviato, ma la copia in Inviati non è stata salvata: '
            '${describeInternalError(e, st)}';
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

  /// Saves a draft in the Drafts folder. Returns `false` if the account has no
  /// Drafts folder.
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

  /// Downloads an attachment of the open message.
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

  /// Hides the error shown.
  void dismissError() {
    error = null;
    _notify();
  }

  /// Label of the open folder.
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
