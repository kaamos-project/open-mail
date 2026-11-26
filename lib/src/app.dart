import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import 'core/mail_service.dart';
import 'data/account_repository.dart';
import 'data/mail_cache.dart';
import 'data/secret_store.dart';
import 'state/mail_session.dart';
import 'ui/environment.dart';
import 'ui/screens/account_setup.dart';
import 'ui/screens/keychain_missing.dart';
import 'ui/screens/mail_home.dart';

/// L'app: mette i servizi nel [MailEnvironment] e decide la prima
/// schermata.
class KaamosMailApp extends StatelessWidget {
  /// Crea l'app con i servizi già pronti (veri in `main.dart`, finti nei
  /// test).
  const KaamosMailApp({
    super.key,
    required this.accounts,
    required this.secrets,
    required this.cache,
    required this.services,
    required this.files,
    required this.htmlBody,
  });

  /// Account salvati.
  final AccountRepository accounts;

  /// Portachiavi.
  final SecretStore secrets;

  /// Cache SQLite.
  final MailCache cache;

  /// Connessioni ai server.
  final MailServiceFactory services;

  /// File e link.
  final FileActions files;

  /// Corpo HTML.
  final HtmlBodyBuilder htmlBody;

  @override
  Widget build(BuildContext context) {
    return MailEnvironment(
      accounts: accounts,
      secrets: secrets,
      cache: cache,
      services: services,
      files: files,
      htmlBody: htmlBody,
      child: const KaamosApp(
        title: 'Kaamos Mail',
        debugShowCheckedModeBanner: false,
        home: _Root(),
      ),
    );
  }
}

enum _Phase { checking, keychainMissing, ready }

/// Avvio: portachiavi → account → casella.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  _Phase _phase = _Phase.checking;
  MailSession? _session;
  bool _addingAccount = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _boot();
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    final env = MailEnvironment.of(context);
    setState(() => _phase = _Phase.checking);
    // Prima di tutto il portachiavi: senza, l'app non parte (decisione di
    // Alessio: niente password in chiaro, mai).
    if (!await env.secrets.isAvailable()) {
      if (mounted) setState(() => _phase = _Phase.keychainMissing);
      return;
    }
    final session =
        _session ??
        MailSession(
          repository: env.accounts,
          cache: env.cache,
          services: env.services,
        );
    await session.load();
    if (!mounted) {
      session.dispose();
      return;
    }
    setState(() {
      _session = session;
      _phase = _Phase.ready;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final session = _session;
    final Widget child = switch (_phase) {
      _Phase.checking => const SizedBox.shrink(),
      _Phase.keychainMissing => KeychainMissingScreen(onRetry: _boot),
      _Phase.ready => ListenableBuilder(
        listenable: session!,
        builder: (context, _) {
          final controller = session.controller;
          if (controller == null || _addingAccount) {
            return AccountSetupScreen(
              onSaved: (account) {
                session.added(account);
                setState(() => _addingAccount = false);
              },
              // Al primo avvio non c'è niente a cui tornare.
              onCancel: controller == null
                  ? null
                  : () => setState(() => _addingAccount = false),
            );
          }
          return MailHome(
            // Cambiando account la casella riparte pulita (es. una bozza
            // aperta su desktop resta dell'account in cui era).
            key: ValueKey(controller.account.id),
            controller: controller,
            accounts: session.accounts,
            onSelectAccount: session.select,
            onAddAccount: () => setState(() => _addingAccount = true),
            onRemoveAccount: () => session.remove(controller.account.id),
          );
        },
      ),
    };
    return ColoredBox(color: theme.canvas, child: child);
  }
}
