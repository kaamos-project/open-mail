import 'package:flutter/foundation.dart';

import '../core/models.dart';
import 'mailbox_controller.dart';

/// Una riga dell'Inbox unificata: il messaggio e l'account da cui viene.
class UnifiedItem {
  /// Crea la riga.
  const UnifiedItem({
    required this.controller,
    required this.summary,
    required this.sortMs,
  });

  /// Il controller dell'account: le azioni passano da lui.
  final MailboxController controller;

  /// Il messaggio.
  final MessageSummary summary;

  /// La data usata per ordinare (arrivo sul server), in millisecondi.
  final int sortMs;

  /// L'account.
  Account get account => controller.account;

  /// La cartella del messaggio (la Inbox del suo account).
  String get path => controller.inbox.path;
}

/// Le Inbox di tutti gli account in una lista sola, la più recente prima.
///
/// Non ha una copia sua dei messaggi: legge le Inbox dalla cache e si
/// rilegge ogni volta che un account cambia (sincronizzazione, stella,
/// archivia…). Ogni azione la fa il controller dell'account del
/// messaggio, sulla sua Inbox, anche se quell'account sta guardando
/// un'altra cartella.
class UnifiedInbox extends ChangeNotifier {
  /// Crea la vista su [controllers].
  UnifiedInbox({
    required List<MailboxController> controllers,
    this.pageSize = 50,
  }) {
    setControllers(controllers);
  }

  /// Quanti messaggi mostrare in tutto.
  final int pageSize;

  List<MailboxController> _controllers = const [];

  /// I messaggi, il più recente prima.
  List<UnifiedItem> items = const [];

  /// Il controller del messaggio aperto da questa vista.
  MailboxController? openController;

  bool _disposed = false;

  /// Gli account mostrati.
  List<MailboxController> get controllers => _controllers;

  /// Almeno una Inbox si sta aggiornando.
  bool get syncing => _controllers.any((c) => c.inboxSyncing);

  /// Il primo errore tra gli account, con l'indirizzo davanti (così si
  /// capisce quale account non risponde).
  String? get error {
    for (final c in _controllers) {
      final e = c.error;
      if (e != null) return '${c.account.email}: $e';
    }
    return null;
  }

  /// Il messaggio aperto, se l'ha aperto questa vista.
  ({String accountId, int uid})? get open {
    final c = openController;
    final uid = c?.openUid;
    if (c == null || uid == null) return null;
    return (accountId: c.account.id, uid: uid);
  }

  /// Cambia gli account (aggiunto o rimosso).
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

  /// Rilegge le Inbox dalla cache e le mescola per data.
  ///
  /// Ogni account contribuisce al massimo [pageSize] messaggi: i primi
  /// [pageSize] della lista unita stanno per forza tra questi.
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

  /// Aggiorna le Inbox di tutti gli account, in parallelo.
  Future<void> refresh() =>
      Future.wait([for (final c in _controllers) c.syncInbox()]);

  /// Apre [item] nel controller del suo account.
  Future<void> openItem(UnifiedItem item) {
    final previous = openController;
    if (previous != null && previous != item.controller) {
      previous.closeMessage();
    }
    openController = item.controller;
    notifyListeners();
    return item.controller.open(item.summary.uid, path: item.path);
  }

  /// Chiude il messaggio aperto da questa vista.
  void closeMessage() {
    openController?.closeMessage();
    openController = null;
    notifyListeners();
  }

  /// Nasconde gli errori di tutti gli account.
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
