import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/mail_service.dart';
import '../../core/models.dart';
import '../../core/oauth.dart';
import '../../core/text_utils.dart';
import '../environment.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';

/// "Add an account": sign in with Google or Microsoft, or manual IMAP and
/// SMTP; then check and save.
class AccountSetupScreen extends StatefulWidget {
  /// Creates the screen. [onSaved] receives the freshly saved account.
  const AccountSetupScreen({super.key, required this.onSaved, this.onCancel});

  /// Account checked and saved.
  final ValueChanged<Account> onSaved;

  /// `null` on first start (there is nothing to go back to).
  final VoidCallback? onCancel;

  @override
  State<AccountSetupScreen> createState() => _AccountSetupScreenState();
}

enum _CheckState { idle, running, ok, failed }

class _AccountSetupScreenState extends State<AccountSetupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _imapHost = TextEditingController();
  final _imapPort = TextEditingController(text: '993');
  final _smtpHost = TextEditingController();
  final _smtpPort = TextEditingController(text: '587');
  var _imapSecurity = ConnectionSecurity.tls;
  var _smtpSecurity = ConnectionSecurity.startTls;

  var _imapState = _CheckState.idle;
  var _smtpState = _CheckState.idle;
  ConnectionCheckResult? _result;
  String? _formError;

  /// The provider whose sign-in is running.
  OAuthProvider? _signingIn;

  @override
  void initState() {
    super.initState();
    // Suggests the servers from the address: you@example.com →
    // imap.example.com.
    _email.addListener(_suggestServers);
  }

  String _lastDomain = '';

  void _suggestServers() {
    final email = _email.text.trim();
    final at = email.lastIndexOf('@');
    if (at < 0) return;
    final domain = email.substring(at + 1);
    if (domain.isEmpty) return;
    if (_imapHost.text.isEmpty || _imapHost.text == 'imap.$_lastDomain') {
      _imapHost.text = 'imap.$domain';
    }
    if (_smtpHost.text.isEmpty || _smtpHost.text == 'smtp.$_lastDomain') {
      _smtpHost.text = 'smtp.$domain';
    }
    _lastDomain = domain;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _email,
      _password,
      _imapHost,
      _imapPort,
      _smtpHost,
      _smtpPort,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Account? _buildAccount() {
    final email = _email.text.trim();
    final imapPort = int.tryParse(_imapPort.text.trim());
    final smtpPort = int.tryParse(_smtpPort.text.trim());
    if (!isValidEmail(email)) {
      _formError = 'Inserisci un indirizzo email valido.';
    } else if (_password.text.isEmpty) {
      _formError = 'Inserisci la password o la password per app.';
    } else if (_imapHost.text.trim().isEmpty || _smtpHost.text.trim().isEmpty) {
      _formError = 'Inserisci i server IMAP e SMTP.';
    } else if (imapPort == null || smtpPort == null) {
      _formError = 'Le porte devono essere numeri.';
    } else {
      _formError = null;
      return Account(
        id: _newAccountId(),
        displayName: _name.text.trim().isEmpty
            ? email.split('@').first
            : _name.text.trim(),
        email: email,
        username: email,
        imap: ServerConfig(
          host: _imapHost.text.trim(),
          port: imapPort,
          security: _imapSecurity,
        ),
        smtp: ServerConfig(
          host: _smtpHost.text.trim(),
          port: smtpPort,
          security: _smtpSecurity,
        ),
      );
    }
    return null;
  }

  /// It only needs to be unique on this device.
  static String _newAccountId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${math.Random.secure().nextInt(1 << 30).toRadixString(36)}';

  Future<void> _verifyAndSave() async {
    final account = _buildAccount();
    if (account == null) {
      setState(() {});
      return;
    }
    await _checkAndSave(account, _password.text, showInBoxes: true);
  }

  /// Signs in with [provider] in the browser, then checks and saves the
  /// account with the provider's servers.
  Future<void> _signIn(OAuthProvider provider) async {
    final env = MailEnvironment.of(context);
    final signIn = env.oauth;
    if (signIn == null) return;
    final config = oauthConfig(provider, target: signIn.target);
    setState(() {
      _signingIn = provider;
      _formError = null;
    });
    try {
      final result = await signIn.signIn(config);
      if (!mounted) return;
      final email = result.identity.email;
      final account = Account(
        id: _newAccountId(),
        displayName: result.identity.name ?? email.split('@').first,
        email: email,
        username: email,
        imap: config.imap,
        smtp: config.smtp,
        oauth: provider,
      );
      await _checkAndSave(account, result.tokens.refreshToken!);
    } on OAuthException catch (e) {
      if (mounted) setState(() => _formError = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _formError = 'Accesso con ${config.label} non riuscito.',
        );
      }
    } finally {
      if (mounted) setState(() => _signingIn = null);
    }
  }

  /// Checks IMAP and SMTP with [secret] (password or refresh token) and
  /// saves. With [showInBoxes] the result shows in the server boxes;
  /// otherwise errors go under the form.
  Future<void> _checkAndSave(
    Account account,
    String secret, {
    bool showInBoxes = false,
  }) async {
    final env = MailEnvironment.of(context);
    // The same address on the same server twice would create two identical
    // mailboxes stepping on each other.
    final existing = await env.accounts.load();
    if (!mounted) return;
    if (existing.any(
      (a) =>
          a.email.toLowerCase() == account.email.toLowerCase() &&
          a.imap.host.toLowerCase() == account.imap.host.toLowerCase(),
    )) {
      setState(() => _formError = 'Questo account c\'è già.');
      return;
    }
    if (showInBoxes) {
      setState(() {
        _imapState = _CheckState.running;
        _smtpState = _CheckState.running;
        _result = null;
      });
    }
    final result = await env.services.check(account, secret);
    if (!mounted) return;
    setState(() {
      if (showInBoxes) {
        _result = result;
        _imapState = result.imapError == null
            ? _CheckState.ok
            : _CheckState.failed;
        _smtpState = result.smtpError == null
            ? _CheckState.ok
            : _CheckState.failed;
      } else if (!result.ok) {
        _formError = result.imapError ?? result.smtpError;
      }
    });
    if (!result.ok) return;
    try {
      await env.accounts.save(account, secret);
    } on Object {
      if (!mounted) return;
      setState(() => _formError = 'Non riesco a salvare nel portachiavi.');
      return;
    }
    widget.onSaved(account);
  }

  bool get _busy =>
      _signingIn != null ||
      _imapState == _CheckState.running ||
      _smtpState == _CheckState.running;

  /// "Sign in with Google / Microsoft", only where the platform supports
  /// it. A button without a client ID stays disabled and says why.
  Widget? _providerButtons(BuildContext context) {
    final signIn = MailEnvironment.of(context).oauth;
    if (signIn == null) return null;
    final theme = KaamosTheme.of(context);
    final configs = [
      for (final p in OAuthProvider.values)
        oauthConfig(p, target: signIn.target),
    ];
    final missing = configs.where((c) => !c.isConfigured).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in configs)
              KaamosButton(
                variant: KaamosButtonVariant.secondary,
                onPressed: _busy || !c.isConfigured
                    ? null
                    : () => _signIn(c.provider),
                child: Text(
                  _signingIn == c.provider
                      ? 'Completa l\'accesso nel browser…'
                      : 'Accedi con ${c.label}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          missing.isEmpty
              ? 'Si apre il browser: la password la vede solo il provider.'
              : 'Accesso con ${missing.map((c) => c.label).join(' e ')} non '
                    'configurato in questa build (vedi docs/oauth.md).',
          style: KaamosTypography.captionSm.copyWith(color: theme.mute),
        ),
        const SizedBox(height: 20),
        const Hairline(),
        const SizedBox(height: 20),
        Text(
          'Oppure configura IMAP e SMTP a mano',
          style: KaamosTypography.bodySmStrong.copyWith(color: theme.ink),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final servers = [
          _ServerBox(
            title: 'Posta in arrivo · IMAP',
            host: _imapHost,
            port: _imapPort,
            security: _imapSecurity,
            onSecurity: (s) => setState(() {
              _imapSecurity = s;
              _imapPort.text = s == ConnectionSecurity.tls ? '993' : '143';
            }),
            state: _imapState,
            okText: 'Connesso, ${_result?.folderCount ?? 0} cartelle trovate',
            error: _result?.imapError,
          ),
          _ServerBox(
            title: 'Posta in uscita · SMTP',
            host: _smtpHost,
            port: _smtpPort,
            security: _smtpSecurity,
            onSecurity: (s) => setState(() {
              _smtpSecurity = s;
              _smtpPort.text = s == ConnectionSecurity.tls ? '465' : '587';
            }),
            state: _smtpState,
            okText: 'Connesso',
            error: _result?.smtpError,
          ),
        ];
        final form = AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Aggiungi un account',
                  style: KaamosTypography.headingXl.copyWith(color: theme.ink),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Kaamos Mail si collega direttamente al tuo provider. '
                'Nessun server Kaamos vede i tuoi dati.',
                style: KaamosTypography.bodySm.copyWith(color: theme.mute),
              ),
              const SizedBox(height: 20),
              ?_providerButtons(context),
              _twoUp(wide, [
                _Labeled(
                  label: 'Nome visualizzato',
                  child: KaamosTextField(
                    controller: _name,
                    placeholder: 'Alessio',
                    autofillHints: const [AutofillHints.name],
                  ),
                ),
                _Labeled(
                  label: 'Indirizzo email',
                  child: KaamosTextField(
                    controller: _email,
                    placeholder: 'tu@esempio.it',
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _Labeled(
                label: 'Password o password per app',
                child: KaamosTextField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  MailIconView(MailIcon.lock, size: 13, color: theme.mute),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Salvata solo nel portachiavi di sistema, mai in un file.',
                      style: KaamosTypography.captionSm.copyWith(
                        color: theme.mute,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _twoUp(wide, servers, gap: 16),
              if (_formError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _formError!,
                  style: KaamosTypography.bodySm.copyWith(color: theme.danger),
                ),
              ],
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 12,
                children: [
                  if (MailEnvironment.of(context).oauth == null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Text(
                        'Usi Gmail o Outlook? Crea una password per app '
                        'nelle impostazioni di sicurezza del tuo account.',
                        style: KaamosTypography.captionSm.copyWith(
                          color: theme.mute,
                        ),
                      ),
                    ),
                  if (widget.onCancel != null)
                    KaamosButton(
                      variant: KaamosButtonVariant.secondary,
                      onPressed: _busy ? null : widget.onCancel,
                      child: const Text('Annulla'),
                    ),
                  KaamosButton(
                    onPressed: _busy ? null : _verifyAndSave,
                    child: Text(_busy ? 'Verifica…' : 'Verifica e salva'),
                  ),
                ],
              ),
            ],
          ),
        );
        // The form sits on the page itself, with no card: a framed box on
        // the dark background read as a pop-up. Adding another account
        // looks the same as the first start; only "Annulla" tells them
        // apart.
        return Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(wide ? 24 : 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: form,
            ),
          ),
        );
      },
    );
  }

  Widget _twoUp(bool wide, List<Widget> children, {double gap = 16}) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            children[i],
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: KaamosTypography.captionMd.copyWith(color: theme.body),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _ServerBox extends StatelessWidget {
  const _ServerBox({
    required this.title,
    required this.host,
    required this.port,
    required this.security,
    required this.onSecurity,
    required this.state,
    required this.okText,
    required this.error,
  });

  final String title;
  final TextEditingController host;
  final TextEditingController port;
  final ConnectionSecurity security;
  final ValueChanged<ConnectionSecurity> onSecurity;
  final _CheckState state;
  final String okText;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final status = switch (state) {
      _CheckState.idle => null,
      _CheckState.running => Text(
        'Verifica in corso…',
        style: KaamosTypography.captionMd.copyWith(color: theme.mute),
      ),
      _CheckState.ok => Row(
        children: [
          const MailIconView(
            MailIcon.lock,
            size: 14,
            color: KaamosColors.accentGreen,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              okText,
              style: KaamosTypography.captionMd.copyWith(
                color: KaamosColors.accentGreen,
              ),
            ),
          ),
        ],
      ),
      _CheckState.failed => Text(
        error ?? 'Errore',
        style: KaamosTypography.captionMd.copyWith(color: theme.danger),
      ),
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: theme.hairline),
        borderRadius: const BorderRadius.all(Radius.circular(KaamosRadius.md)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: KaamosTypography.bodySmStrong.copyWith(color: theme.ink),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _Labeled(
                  label: 'Server',
                  child: KaamosTextField(
                    controller: host,
                    keyboardType: TextInputType.url,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: _Labeled(
                  label: 'Porta',
                  child: KaamosTextField(
                    controller: port,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Sicurezza',
            child: Wrap(
              spacing: 4,
              children: [
                KaamosPillTab(
                  label: 'SSL/TLS',
                  selected: security == ConnectionSecurity.tls,
                  onPressed: () => onSecurity(ConnectionSecurity.tls),
                ),
                KaamosPillTab(
                  label: 'STARTTLS',
                  selected: security == ConnectionSecurity.startTls,
                  onPressed: () => onSecurity(ConnectionSecurity.startTls),
                ),
              ],
            ),
          ),
          if (status != null) ...[const SizedBox(height: 12), status],
        ],
      ),
    );
  }
}
