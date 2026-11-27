import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import 'core/mail_service.dart';
import 'data/account_repository.dart';
import 'data/mail_cache.dart';
import 'data/oauth_client.dart';
import 'data/secret_store.dart';
import 'state/mail_session.dart';
import 'ui/environment.dart';
import 'ui/screens/account_setup.dart';
import 'ui/screens/keychain_missing.dart';
import 'ui/screens/mail_home.dart';

/// The app: puts the services in the [MailEnvironment] and decides the first
/// screen.
class KaamosMailApp extends StatelessWidget {
  /// Creates the app with the services ready (real in `main.dart`, fake in
  /// tests).
  const KaamosMailApp({
    super.key,
    required this.accounts,
    required this.secrets,
    required this.cache,
    required this.services,
    required this.files,
    required this.htmlBody,
    this.oauth,
  });

  /// Saved accounts.
  final AccountRepository accounts;

  /// Keychain.
  final SecretStore secrets;

  /// SQLite cache.
  final MailCache cache;

  /// Server connections.
  final MailServiceFactory services;

  /// Files and links.
  final FileActions files;

  /// HTML body.
  final HtmlBodyBuilder htmlBody;

  /// Google and Microsoft sign-in, where available.
  final OAuthSignIn? oauth;

  @override
  Widget build(BuildContext context) {
    return MailEnvironment(
      accounts: accounts,
      secrets: secrets,
      cache: cache,
      services: services,
      files: files,
      htmlBody: htmlBody,
      oauth: oauth,
      child: const KaamosApp(
        title: 'Kaamos Mail',
        debugShowCheckedModeBanner: false,
        home: _Root(),
      ),
    );
  }
}

enum _Phase { checking, keychainMissing, ready }

/// Startup: keychain → accounts → mailbox.
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
    // Keychain first: without it the app doesn't start (Alessio's decision: no
    // plain-text passwords, ever).
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
              // On first start there is nothing to go back to.
              onCancel: controller == null
                  ? null
                  : () => setState(() => _addingAccount = false),
            );
          }
          return MailHome(
            // Switching account restarts the mailbox clean (e.g. a draft open
            // on desktop stays with the account it belongs to).
            key: ValueKey(controller.account.id),
            controller: controller,
            accounts: session.accounts,
            onSelectAccount: session.select,
            onAddAccount: () => setState(() => _addingAccount = true),
            onRemoveAccount: () => session.remove(controller.account.id),
            unified: session.unified,
            onShowUnified: session.canUnify ? session.showUnified : null,
            onLeaveUnified: session.leaveUnified,
          );
        },
      ),
    };
    return ColoredBox(color: theme.canvas, child: child);
  }
}
