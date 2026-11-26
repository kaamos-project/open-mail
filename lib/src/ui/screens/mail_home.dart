import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/models.dart';
import '../../state/compose_draft.dart';
import '../../state/mailbox_controller.dart';
import '../views/compose.dart';
import '../views/folder_list.dart';
import '../views/message_list.dart';
import '../views/message_view.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';

/// Da questa larghezza in su: tre colonne (desktop). Sotto: pagine una
/// sopra l'altra (mobile).
const double desktopBreakpoint = 900;

/// Una pagina senza animazione con lo sfondo del tema, per il Navigator.
Route<T> mailPage<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => ColoredBox(
    color: KaamosTheme.of(context).canvas,
    child: SafeArea(child: Builder(builder: builder)),
  ),
);

/// La casella: tre colonne su desktop, pagine su mobile.
class MailHome extends StatefulWidget {
  /// Crea la casella per [controller].
  const MailHome({
    super.key,
    required this.controller,
    required this.onRemoveAccount,
  });

  /// Lo stato della casella.
  final MailboxController controller;

  /// "Rimuovi account": cancella account, password e cache.
  final VoidCallback onRemoveAccount;

  @override
  State<MailHome> createState() => _MailHomeState();
}

class _MailHomeState extends State<MailHome> {
  /// Su desktop la scrittura prende il posto del lettore.
  ComposeDraft? _desktopDraft;
  int _draftKey = 0;

  MailboxController get _c => widget.controller;

  void _compose(BuildContext context, ComposeDraft draft, bool desktop) {
    if (desktop) {
      setState(() {
        _desktopDraft = draft;
        _draftKey++;
      });
      return;
    }
    Navigator.of(context).push<void>(
      mailPage(
        (context) => ComposeView(
          controller: _c,
          draft: draft,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _open(BuildContext context, MessageSummary m, bool desktop) {
    _c.open(m.uid);
    if (desktop) {
      setState(() => _desktopDraft = null);
      return;
    }
    Navigator.of(context).push<void>(
      mailPage(
        (context) => PopScope<void>(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) _c.closeMessage();
          },
          child: MessageView(
            controller: _c,
            onBack: () => Navigator.of(context).maybePop(),
            onCompose: (draft) => _compose(context, draft, false),
          ),
        ),
      ),
    );
  }

  Future<void> _showAccount(BuildContext context) async {
    final remove = await showKaamosDialog<bool>(
      context: context,
      builder: (context) => KaamosDialog(
        title: _c.account.displayName,
        content: Text(
          '${_c.account.email}\n'
          'IMAP ${_c.account.imap.host}:${_c.account.imap.port}\n'
          'SMTP ${_c.account.smtp.host}:${_c.account.smtp.port}\n\n'
          'Rimuovendo l\'account cancello da questo dispositivo la password '
          'dal portachiavi e la copia locale delle mail. Sul server non '
          'cambia niente.',
        ),
        actions: [
          KaamosButton(
            variant: KaamosButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rimuovi account'),
          ),
          KaamosButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
    if (remove ?? false) widget.onRemoveAccount();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= desktopBreakpoint;
        return desktop ? _desktop(context, constraints) : _mobile(context);
      },
    );
  }

  Widget _desktop(BuildContext context, BoxConstraints constraints) {
    final listWidth = constraints.maxWidth >= 1200 ? 400.0 : 340.0;
    final draft = _desktopDraft;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 240,
          child: FolderList(
            controller: _c,
            onCompose: () => _compose(context, const ComposeDraft(), true),
            onSelected: (_) {},
            onAccount: () => _showAccount(context),
          ),
        ),
        const VerticalHairline(),
        SizedBox(
          width: listWidth,
          child: MessageList(
            controller: _c,
            onOpen: (m) => _open(context, m, true),
          ),
        ),
        const VerticalHairline(),
        Expanded(
          child: draft != null
              ? ComposeView(
                  key: ValueKey(_draftKey),
                  controller: _c,
                  draft: draft,
                  onClose: () => setState(() => _desktopDraft = null),
                )
              : MessageView(
                  controller: _c,
                  onCompose: (d) => _compose(context, d, true),
                ),
        ),
      ],
    );
  }

  Widget _mobile(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: MessageList(
              controller: _c,
              onOpen: (m) => _open(context, m, false),
              leading: MailIconButton(
                icon: MailIcon.folder,
                label: 'Cartelle',
                size: 44,
                onPressed: () => Navigator.of(context).push<void>(
                  mailPage(
                    (pageContext) => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                          child: Row(
                            children: [
                              MailIconButton(
                                icon: MailIcon.back,
                                label: 'Indietro',
                                size: 44,
                                onPressed: () =>
                                    Navigator.of(pageContext).pop(),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: FolderList(
                            controller: _c,
                            onCompose: () {
                              Navigator.of(pageContext).pop();
                              _compose(context, const ComposeDraft(), false);
                            },
                            onSelected: (_) => Navigator.of(pageContext).pop(),
                            onAccount: () => _showAccount(pageContext),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: KaamosPressable(
              onPressed: () => _compose(context, const ComposeDraft(), false),
              semanticLabel: 'Scrivi',
              builder: (context, states) => KaamosFocusRing(
                visible: states.contains(WidgetState.focused),
                color: theme.focusRing,
                borderRadius: 28,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: theme.ink,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: MailIconView(
                    MailIcon.edit,
                    size: 22,
                    color: theme.canvas,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
