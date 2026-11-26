import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/models.dart';
import '../../state/compose_draft.dart';
import '../../state/mailbox_controller.dart';
import '../../state/unified_inbox.dart';
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
    this.accounts = const [],
    this.onSelectAccount,
    this.onAddAccount,
    this.unified,
    this.onShowUnified,
    this.onLeaveUnified,
  });

  /// Lo stato della casella.
  final MailboxController controller;

  /// "Rimuovi account": cancella account, password e cache.
  final VoidCallback onRemoveAccount;

  /// Tutti gli account, per passare dall'uno all'altro.
  final List<Account> accounts;

  /// Mostra un altro account.
  final ValueChanged<String>? onSelectAccount;

  /// Apre l'aggiunta di un account.
  final VoidCallback? onAddAccount;

  /// L'Inbox unificata, se è quella mostrata.
  final UnifiedInbox? unified;

  /// Mostra "Tutte le caselle". `null` con un account solo.
  final VoidCallback? onShowUnified;

  /// Torna alle cartelle dell'account.
  final VoidCallback? onLeaveUnified;

  @override
  State<MailHome> createState() => _MailHomeState();
}

class _MailHomeState extends State<MailHome> {
  /// Su desktop la scrittura prende il posto del lettore.
  ComposeDraft? _desktopDraft;

  /// L'account da cui si scrive (una risposta dall'Inbox unificata parte
  /// dall'account del messaggio).
  MailboxController? _draftFrom;
  int _draftKey = 0;

  MailboxController get _c => widget.controller;

  /// Il controller del messaggio nel lettore: nell'Inbox unificata è
  /// quello dell'account del messaggio aperto.
  MailboxController get _reader => widget.unified?.openController ?? _c;

  void _compose(
    BuildContext context,
    ComposeDraft draft,
    bool desktop, [
    MailboxController? from,
  ]) {
    final c = from ?? _c;
    if (desktop) {
      setState(() {
        _desktopDraft = draft;
        _draftFrom = c;
        _draftKey++;
      });
      return;
    }
    Navigator.of(context).push<void>(
      mailPage(
        (context) => ComposeView(
          controller: c,
          draft: draft,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  void _open(BuildContext context, MessageSummary m, bool desktop) {
    _c.open(m.uid);
    _show(context, _c, desktop);
  }

  void _openUnified(BuildContext context, UnifiedItem item, bool desktop) {
    widget.unified?.openItem(item);
    _show(context, item.controller, desktop);
  }

  /// Mostra il messaggio aperto in [c]: su desktop nel lettore, su mobile
  /// in una pagina nuova.
  void _show(BuildContext context, MailboxController c, bool desktop) {
    if (desktop) {
      setState(() => _desktopDraft = null);
      return;
    }
    Navigator.of(context).push<void>(
      mailPage(
        (context) => PopScope<void>(
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) c.closeMessage();
          },
          child: MessageView(
            controller: c,
            onBack: () => Navigator.of(context).maybePop(),
            onCompose: (draft) => _compose(context, draft, false, c),
          ),
        ),
      ),
    );
  }

  /// La colonna dei messaggi: Inbox unificata o cartella dell'account.
  Widget _list(BuildContext context, bool desktop, {Widget? leading}) {
    final unified = widget.unified;
    if (unified != null) {
      return UnifiedMessageList(
        inbox: unified,
        leading: leading,
        onOpen: (item) => _openUnified(context, item, desktop),
      );
    }
    return MessageList(
      controller: _c,
      leading: leading,
      onOpen: (m) => _open(context, m, desktop),
    );
  }

  /// Scegliere una cartella esce dall'Inbox unificata.
  void _folderChosen() {
    if (widget.unified != null) widget.onLeaveUnified?.call();
  }

  Future<void> _showAccount(BuildContext context) async {
    final choice = await showKaamosDialog<String>(
      context: context,
      builder: (context) => KaamosDialog(
        title: 'Account',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in widget.accounts)
              _AccountRow(
                account: a,
                active: a.id == _c.account.id,
                onPressed: () => Navigator.of(context).pop('select:${a.id}'),
              ),
            const SizedBox(height: 12),
            Text(
              'Rimuovendo un account cancello da questo dispositivo la '
              'password dal portachiavi e la copia locale delle mail. Sul '
              'server non cambia niente.',
              style: KaamosTypography.captionMd.copyWith(
                color: KaamosTheme.of(context).mute,
              ),
            ),
          ],
        ),
        actions: [
          KaamosButton(
            variant: KaamosButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop('remove'),
            child: Text('Rimuovi ${_c.account.email}'),
          ),
          if (widget.onAddAccount != null)
            KaamosButton(
              variant: KaamosButtonVariant.tertiary,
              onPressed: () => Navigator.of(context).pop('add'),
              child: const Text('Aggiungi account'),
            ),
          KaamosButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Chiudi'),
          ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'remove') {
      await _confirmRemove(context);
    } else if (choice == 'add') {
      widget.onAddAccount?.call();
    } else if (choice.startsWith('select:')) {
      widget.onSelectAccount?.call(choice.substring(7));
    }
  }

  /// Rimuovere è irreversibile in locale: si chiede conferma.
  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showKaamosDialog<bool>(
      context: context,
      builder: (context) => KaamosDialog(
        title: 'Rimuovere ${_c.account.email}?',
        content: const Text(
          'Password e mail salvate su questo dispositivo vengono cancellate. '
          'Le mail sul server restano dove sono.',
        ),
        actions: [
          KaamosButton(
            variant: KaamosButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annulla'),
          ),
          KaamosButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (ok ?? false) widget.onRemoveAccount();
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
            onSelected: (_) => _folderChosen(),
            onAccount: () => _showAccount(context),
            onUnified: widget.onShowUnified,
            unified: widget.unified != null,
          ),
        ),
        const VerticalHairline(),
        SizedBox(width: listWidth, child: _list(context, true)),
        const VerticalHairline(),
        Expanded(
          child: draft != null
              ? ComposeView(
                  key: ValueKey(_draftKey),
                  controller: _draftFrom ?? _c,
                  draft: draft,
                  onClose: () => setState(() => _desktopDraft = null),
                )
              : _desktopReader(context),
        ),
      ],
    );
  }

  /// Il lettore su desktop. Nell'Inbox unificata cambia controller quando
  /// apri un messaggio di un altro account, quindi ascolta la vista.
  Widget _desktopReader(BuildContext context) {
    Widget reader() => MessageView(
      // Cambiando account il lettore riparte pulito.
      key: ValueKey(_reader.account.id),
      controller: _reader,
      onCompose: (d) => _compose(context, d, true, _reader),
    );
    final unified = widget.unified;
    if (unified == null) return reader();
    return ListenableBuilder(
      listenable: unified,
      builder: (context, _) => reader(),
    );
  }

  Widget _mobile(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: _list(
              context,
              false,
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
                            onSelected: (_) {
                              Navigator.of(pageContext).pop();
                              _folderChosen();
                            },
                            onAccount: () => _showAccount(pageContext),
                            onUnified: widget.onShowUnified == null
                                ? null
                                : () {
                                    Navigator.of(pageContext).pop();
                                    widget.onShowUnified!();
                                  },
                            unified: widget.unified != null,
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

/// Una riga della lista account nel dialog.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.account,
    required this.active,
    required this.onPressed,
  });

  final Account account;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return Semantics(
      selected: active,
      child: KaamosPressable(
        onPressed: onPressed,
        semanticLabel: '${account.displayName}, ${account.email}',
        builder: (context, states) => KaamosFocusRing(
          visible: states.contains(WidgetState.focused),
          color: theme.focusRing,
          borderRadius: KaamosRadius.md,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: active || states.contains(WidgetState.hovered)
                  ? theme.surfaceElevated
                  : null,
              borderRadius: const BorderRadius.all(
                Radius.circular(KaamosRadius.md),
              ),
            ),
            child: Row(
              children: [
                MailAvatar(label: account.displayName, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KaamosTypography.bodySmStrong.copyWith(
                          color: theme.ink,
                        ),
                      ),
                      Text(
                        account.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KaamosTypography.captionSm.copyWith(
                          color: theme.mute,
                        ),
                      ),
                    ],
                  ),
                ),
                if (active)
                  KaamosIcon(KaamosIcons.check, size: 14, color: theme.ink),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
