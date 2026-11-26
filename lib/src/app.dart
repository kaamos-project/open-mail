import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import 'core/mail_service.dart';
import 'core/models.dart';
import 'data/account_repository.dart';
import 'data/mail_cache.dart';
import 'data/secret_store.dart';
import 'state/mailbox_controller.dart';
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

enum _Phase { checking, keychainMissing, setup, ready }

/// Avvio: portachiavi → account → casella.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  _Phase _phase = _Phase.checking;
  MailboxController? _controller;
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
    _controller?.dispose();
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
    final accounts = await env.accounts.load();
    if (!mounted) return;
    if (accounts.isEmpty) {
      setState(() => _phase = _Phase.setup);
    } else {
      _startMailbox(accounts.first);
    }
  }

  void _startMailbox(Account account) {
    final env = MailEnvironment.of(context);
    _controller?.dispose();
    final controller = MailboxController(
      account: account,
      cache: env.cache,
      connect: () async {
        final password = await env.accounts.password(account.id);
        if (password == null) {
          throw StateError(
            'La password non è nel portachiavi: rimuovi e aggiungi di '
            'nuovo l\'account.',
          );
        }
        return env.services.connect(account, password);
      },
    );
    setState(() {
      _controller = controller;
      _phase = _Phase.ready;
    });
    controller.start();
  }

  Future<void> _removeAccount() async {
    final env = MailEnvironment.of(context);
    final controller = _controller;
    if (controller == null) return;
    final id = controller.account.id;
    setState(() {
      _controller = null;
      _phase = _Phase.setup;
    });
    controller.dispose();
    await env.accounts.remove(id);
    env.cache.deleteAccount(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final Widget child = switch (_phase) {
      _Phase.checking => const SizedBox.shrink(),
      _Phase.keychainMissing => KeychainMissingScreen(onRetry: _boot),
      _Phase.setup => AccountSetupScreen(onSaved: _startMailbox),
      _Phase.ready => MailHome(
        controller: _controller!,
        onRemoveAccount: _removeAccount,
      ),
    };
    return ColoredBox(color: theme.canvas, child: child);
  }
}
