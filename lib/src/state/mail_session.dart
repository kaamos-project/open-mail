import 'package:flutter/foundation.dart';

import '../core/mail_service.dart';
import '../core/models.dart';
import '../data/account_repository.dart';
import '../data/mail_cache.dart';
import 'mailbox_controller.dart';
import 'unified_inbox.dart';

/// All the accounts and the one shown now.
///
/// Each account has its own [MailboxController], created the first time you
/// open it and kept alive as long as the account exists: going back to an
/// account you already opened, the list is right there without reloading. A
/// controller's IMAP connection opens only when needed, so accounts you aren't
/// looking at hold no open connections until you use them.
class MailSession extends ChangeNotifier {
  /// Creates the session.
  MailSession({
    required this.repository,
    required this.cache,
    required this.services,
  });

  /// Where accounts and passwords live.
  final AccountRepository repository;

  /// The shared cache (every row has its `account_id`).
  final MailCache cache;

  /// Creates the connections.
  final MailServiceFactory services;

  final Map<String, MailboxController> _controllers = {};

  /// The accounts, in the order they were added.
  List<Account> accounts = const [];

  String? _activeId;
  UnifiedInbox? _unified;
  bool _disposed = false;

  /// The unified Inbox, if it is the one shown.
  UnifiedInbox? get unified => _unified;

  /// Whether offering the unified Inbox makes sense: with a single account it
  /// would equal its Inbox.
  bool get canUnify => accounts.length > 1;

  /// The account shown (`null` if there are none).
  Account? get active =>
      accounts.where((a) => a.id == _activeId).firstOrNull ??
      accounts.firstOrNull;

  /// The controller of the account shown.
  MailboxController? get controller {
    final account = active;
    return account == null ? null : controllerFor(account);
  }

  /// The controller of [account], created and started the first time.
  MailboxController controllerFor(Account account) =>
      _controllers.putIfAbsent(account.id, () {
        final c = MailboxController(
          account: account,
          cache: cache,
          connect: () async {
            final password = await repository.password(account.id);
            if (password == null) {
              throw StateError(
                'La password non è nel portachiavi: rimuovi e aggiungi di '
                'nuovo l\'account.',
              );
            }
            return services.connect(account, password);
          },
        );
        c.start();
        return c;
      });

  /// Reads the saved accounts.
  Future<void> load() async {
    accounts = await repository.load();
    _notify();
  }

  /// Shows account [id] (and leaves the unified Inbox).
  void select(String id) {
    if (_activeId == id && _unified == null) return;
    _closeUnified();
    _activeId = id;
    _notify();
  }

  /// Shows every account's Inbox together.
  ///
  /// Starts the controllers of all accounts: each opens its connection and
  /// refreshes its Inbox.
  void showUnified() {
    if (!canUnify || _unified != null) return;
    // A message opened earlier would stay in the reader without being in the
    // list: better to start clean.
    controller?.closeMessage();
    final unified = UnifiedInbox(
      controllers: [for (final a in accounts) controllerFor(a)],
    );
    _unified = unified;
    _notify();
    unified.refresh();
  }

  /// Goes back to the shown account's folder.
  void leaveUnified() {
    if (_unified == null) return;
    _closeUnified();
    _notify();
  }

  void _closeUnified() {
    final unified = _unified;
    if (unified == null) return;
    _unified = null;
    unified.openController?.closeMessage();
    unified.dispose();
  }

  void _updateUnified() {
    if (_unified == null) return;
    if (!canUnify) {
      _closeUnified();
    } else {
      _unified!.setControllers([for (final a in accounts) controllerFor(a)]);
    }
  }

  /// A freshly saved account: it becomes the one shown.
  void added(Account account) {
    accounts = [
      for (final a in accounts)
        if (a.id != account.id) a,
      account,
    ];
    _activeId = account.id;
    _updateUnified();
    _notify();
  }

  /// Removes an account: controller, password and cache.
  Future<void> remove(String id) async {
    final removed = _controllers.remove(id);
    accounts = [
      for (final a in accounts)
        if (a.id != id) a,
    ];
    if (_activeId == id) _activeId = accounts.firstOrNull?.id;
    _updateUnified();
    removed?.dispose();
    _notify();
    await repository.remove(id);
    cache.deleteAccount(id);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _unified?.dispose();
    _unified = null;
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }
}
