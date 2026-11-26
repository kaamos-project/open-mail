import 'package:flutter/foundation.dart';

import '../core/models.dart';
import 'mailbox_controller.dart';

/// A row of the unified Inbox: the message and the account it comes from.
class UnifiedItem {
  /// Creates the row.
  const UnifiedItem({
    required this.controller,
    required this.summary,
    required this.sortMs,
  });

  /// The account's controller: actions go through it.
  final MailboxController controller;

  /// The message.
  final MessageSummary summary;

  /// The date used for sorting (arrival on the server), in milliseconds.
  final int sortMs;

  /// The account.
  Account get account => controller.account;

  /// The message's folder (its account's Inbox).
  String get path => controller.inbox.path;
}

/// Every account's Inbox in a single list, newest first.
///
/// It has no copy of its own of the messages: it reads the Inboxes from the
/// cache and re-reads them every time an account changes (sync, star,
/// archive…). Each action is done by the controller of the message's account,
/// on its Inbox, even if that account is showing another folder.
class UnifiedInbox extends ChangeNotifier {
  /// Creates the view over [controllers].
  UnifiedInbox({
    required List<MailboxController> controllers,
    this.pageSize = 50,
  }) {
    setControllers(controllers);
  }

  /// How many messages to show in total.
  final int pageSize;

  List<MailboxController> _controllers = const [];

  /// The messages, newest first.
  List<UnifiedItem> items = const [];

  /// The controller of the message opened from this view.
  MailboxController? openController;

  bool _disposed = false;

  /// The accounts shown.
  List<MailboxController> get controllers => _controllers;

  /// At least one Inbox is refreshing.
  bool get syncing => _controllers.any((c) => c.inboxSyncing);

  /// The first error among the accounts, prefixed with the address (so you can
  /// tell which account isn't answering).
  String? get error {
    for (final c in _controllers) {
      final e = c.error;
      if (e != null) return '${c.account.email}: $e';
    }
    return null;
  }

  /// The open message, if this view opened it.
  ({String accountId, int uid})? get open {
    final c = openController;
    final uid = c?.openUid;
    if (c == null || uid == null) return null;
    return (accountId: c.account.id, uid: uid);
  }

  /// Changes the accounts (added or removed).
  void setControllers(List<MailboxController> controllers) {
    for (final c in _controllers) {
      c.removeListener(_reload);
    }
    _controllers = List.unmodifiable(controllers);
    for (final c in _controllers) {
      c.addListener(_reload);
    }
    if (openController != null && !_controllers.contains(openController)) {
      openController = null;
    }
    _reload();
  }

  /// Re-reads the Inboxes from the cache and merges them by date.
  ///
  /// Each account contributes at most [pageSize] messages: the first [pageSize]
  /// of the merged list must be among them.
  void _reload() {
    if (_disposed) return;
    final all = <UnifiedItem>[
      for (final c in _controllers)
        for (final (m, ms) in c.cache.loadSorted(
          c.account.id,
          c.inbox.path,
          limit: pageSize,
        ))
          UnifiedItem(controller: c, summary: m, sortMs: ms),
    ];
    all.sort((a, b) {
      final byDate = b.sortMs.compareTo(a.sortMs);
      if (byDate != 0) return byDate;
      final byAccount = a.account.id.compareTo(b.account.id);
      if (byAccount != 0) return byAccount;
      return b.summary.uid.compareTo(a.summary.uid);
    });
    items = all.take(pageSize).toList();
    notifyListeners();
  }

  /// Refreshes every account's Inbox, in parallel.
  Future<void> refresh() =>
      Future.wait([for (final c in _controllers) c.syncInbox()]);

  /// Opens [item] in its account's controller.
  Future<void> openItem(UnifiedItem item) {
    final previous = openController;
    if (previous != null && previous != item.controller) {
      previous.closeMessage();
    }
    openController = item.controller;
    notifyListeners();
    return item.controller.open(item.summary.uid, path: item.path);
  }

  /// Closes the message opened from this view.
  void closeMessage() {
    openController?.closeMessage();
    openController = null;
    notifyListeners();
  }

  /// Hides the errors of every account.
  void dismissError() {
    for (final c in _controllers) {
      c.dismissError();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final c in _controllers) {
      c.removeListener(_reload);
    }
    super.dispose();
  }
}
