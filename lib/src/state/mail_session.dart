import 'package:flutter/foundation.dart';

import '../core/mail_service.dart';
import '../core/models.dart';
import '../data/account_repository.dart';
import '../data/mail_cache.dart';
import 'mailbox_controller.dart';

/// Tutti gli account e quello mostrato adesso.
///
/// Ogni account ha il suo [MailboxController], creato la prima volta che
/// lo apri e tenuto vivo finché l'account esiste: tornando su un account
/// già aperto la lista è subito lì, senza ricaricare. La connessione IMAP
/// di un controller si apre solo quando serve, quindi gli account che non
/// guardi non tengono connessioni aperte finché non li usi.
class MailSession extends ChangeNotifier {
  /// Crea la sessione.
  MailSession({
    required this.repository,
    required this.cache,
    required this.services,
  });

  /// Dove stanno account e password.
  final AccountRepository repository;

  /// La cache condivisa (ogni riga ha il suo `account_id`).
  final MailCache cache;

  /// Crea le connessioni.
  final MailServiceFactory services;

  final Map<String, MailboxController> _controllers = {};

  /// Gli account, nell'ordine in cui sono stati aggiunti.
  List<Account> accounts = const [];

  String? _activeId;
  bool _disposed = false;

  /// L'account mostrato (`null` se non ce ne sono).
  Account? get active =>
      accounts.where((a) => a.id == _activeId).firstOrNull ??
      accounts.firstOrNull;

  /// Il controller dell'account mostrato.
  MailboxController? get controller {
    final account = active;
    return account == null ? null : controllerFor(account);
  }

  /// Il controller di [account], creato e avviato la prima volta.
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

  /// Legge gli account salvati.
  Future<void> load() async {
    accounts = await repository.load();
    _notify();
  }

  /// Mostra l'account [id].
  void select(String id) {
    if (_activeId == id) return;
    _activeId = id;
    _notify();
  }

  /// Un account appena salvato: diventa quello mostrato.
  void added(Account account) {
    accounts = [
      for (final a in accounts)
        if (a.id != account.id) a,
      account,
    ];
    _activeId = account.id;
    _notify();
  }

  /// Rimuove un account: controller, password e cache.
  Future<void> remove(String id) async {
    _controllers.remove(id)?.dispose();
    accounts = [
      for (final a in accounts)
        if (a.id != id) a,
    ];
    if (_activeId == id) _activeId = accounts.firstOrNull?.id;
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
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }
}
