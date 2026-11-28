import 'package:flutter/rendering.dart' show ScrollDirection;
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

/// From this width up: three columns (desktop). Below: pages stacked on each
/// other (mobile).
const double desktopBreakpoint = 900;

/// The gap between the desktop compose window and the window's edges: it
/// floats, like Gmail's.
const double composeWindowMargin = 16;

/// The desktop compose window's height for a window [available] pixels
/// tall: a bit less than half, like Gmail's (45%). At least 360px, or the
/// fields and a few lines of text would not fit; at most 720px, or on a
/// tall monitor it would become a page again. Never taller than the window
/// minus the margins.
double composeWindowHeight(double available) {
  final room = available - 2 * composeWindowMargin;
  final wanted = (available * 0.45).clamp(360.0, 720.0);
  return wanted < room ? wanted : room;
}

/// A page with no animation and the theme background, for the Navigator.
Route<T> mailPage<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (context, _, _) => ColoredBox(
    color: KaamosTheme.of(context).canvas,
    child: SafeArea(child: Builder(builder: builder)),
  ),
);

/// The mailbox: three columns on desktop, pages on mobile.
class MailHome extends StatefulWidget {
  /// Creates the mailbox for [controller].
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

  /// The mailbox state.
  final MailboxController controller;

  /// "Remove account": deletes account, password and cache.
  final VoidCallback onRemoveAccount;

  /// All accounts, to switch between them.
  final List<Account> accounts;

  /// Shows another account.
  final ValueChanged<String>? onSelectAccount;

  /// Opens the add-account screen.
  final VoidCallback? onAddAccount;

  /// The unified Inbox, if it is the one shown.
  final UnifiedInbox? unified;

  /// Shows "Tutte le caselle" (all inboxes). `null` with a single account.
  final VoidCallback? onShowUnified;

  /// Goes back to the account's folders.
  final VoidCallback? onLeaveUnified;

  @override
  State<MailHome> createState() => _MailHomeState();
}

class _MailHomeState extends State<MailHome> {
  /// On desktop, the message being written, in a floating window at the
  /// bottom right (one at a time, as Alessio chose).
  ComposeDraft? _desktopDraft;

  /// The account to write from (a reply from the unified Inbox starts from the
  /// message's account).
  MailboxController? _draftFrom;

  /// A new key per draft: a new message starts from a clean State, and the
  /// key lets us ask the open one to close first.
  var _composeKey = GlobalKey<ComposeViewState>();
  bool _minimized = false;
  bool _expanded = false;

  /// The phone's "Scrivi" button shows its label until the list scrolls
  /// down, like Gmail's. A notifier, not setState: only the button
  /// rebuilds, not the whole list.
  final _fabExtended = ValueNotifier(true);

  @override
  void dispose() {
    _fabExtended.dispose();
    super.dispose();
  }

  MailboxController get _c => widget.controller;

  /// The controller of the message in the reader: in the unified Inbox it is
  /// the one of the open message's account.
  MailboxController get _reader => widget.unified?.openController ?? _c;

  void _compose(
    BuildContext context,
    ComposeDraft draft,
    bool desktop, [
    MailboxController? from,
  ]) {
    final c = from ?? _c;
    if (desktop) {
      _composeInWindow(draft, c);
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

  /// Opens [draft] in the desktop window. If one is already open, a new
  /// empty message just brings it back; anything else asks the open one to
  /// close first (with "Salvare la bozza?" if something is written).
  Future<void> _composeInWindow(ComposeDraft draft, MailboxController c) async {
    final open = _composeKey.currentState;
    if (_desktopDraft != null && open != null) {
      if (draft.kind == ComposeKind.fresh && _draftFrom == c) {
        setState(() => _minimized = false);
        return;
      }
      if (!await open.requestClose()) return;
    }
    if (!mounted) return;
    setState(() {
      _desktopDraft = draft;
      _draftFrom = c;
      _composeKey = GlobalKey<ComposeViewState>();
      _minimized = false;
      _expanded = false;
    });
  }

  void _closeWindow() => setState(() => _desktopDraft = null);

  void _open(BuildContext context, MessageSummary m, bool desktop) {
    _c.open(m.uid);
    _show(context, _c, desktop);
  }

  void _openUnified(BuildContext context, UnifiedItem item, bool desktop) {
    widget.unified?.openItem(item);
    _show(context, item.controller, desktop);
  }

  /// Shows the message open in [c]: on desktop in the reader, on mobile in a
  /// new page.
  void _show(BuildContext context, MailboxController c, bool desktop) {
    // On desktop the reader updates by itself; the compose window, if any,
    // stays open over it, as in Gmail.
    if (desktop) return;
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

  /// The message column: unified Inbox or the account's folder.
  Widget _list(
    BuildContext context,
    bool desktop, {
    Widget? leading,
    Widget? trailing,
  }) {
    final unified = widget.unified;
    if (unified != null) {
      return UnifiedMessageList(
        inbox: unified,
        leading: leading,
        trailing: trailing,
        onOpen: (item) => _openUnified(context, item, desktop),
      );
    }
    return MessageList(
      controller: _c,
      leading: leading,
      trailing: trailing,
      onOpen: (m) => _open(context, m, desktop),
    );
  }

  /// Choosing a folder leaves the unified Inbox.
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
      _closePages(context);
      widget.onAddAccount?.call();
    } else if (choice.startsWith('select:')) {
      _closePages(context);
      widget.onSelectAccount?.call(choice.substring(7));
    }
  }

  /// Adding, switching or removing an account replaces this whole screen,
  /// so any page on top of it must close first, or it would hide the change
  /// (this happened when the panel opened from the phone's folders page).
  /// Usually there are none and this does nothing.
  void _closePages(BuildContext context) =>
      Navigator.of(context).popUntil((route) => route.isFirst);

  /// Removing can't be undone locally: ask for confirmation.
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
    if (!(ok ?? false) || !context.mounted) return;
    _closePages(context);
    widget.onRemoveAccount();
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
    // Three columns scroll on their own. On Android and iOS (a tablet in
    // landscape) every vertical list would otherwise attach to the same
    // PrimaryScrollController, and the scrollbar breaks with "attached to
    // more than one ScrollPosition".
    final columns = PrimaryScrollController.none(
      child: Row(
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
          Expanded(child: _desktopReader(context)),
        ],
      ),
    );
    if (draft == null) return columns;
    return Stack(
      children: [
        Positioned.fill(child: columns),
        _composeWindow(context, constraints, draft),
      ],
    );
  }

  /// The desktop compose window, like Gmail's: bottom right over the
  /// columns, 560px wide; minimized it is just its title bar, expanded it
  /// fills most of the screen.
  Widget _composeWindow(
    BuildContext context,
    BoxConstraints constraints,
    ComposeDraft draft,
  ) {
    final theme = KaamosTheme.of(context);
    final view = ComposeView(
      key: _composeKey,
      controller: _draftFrom ?? _c,
      draft: draft,
      onClose: _closeWindow,
      window: ComposeWindowControls(
        minimized: _minimized,
        expanded: _expanded,
        onToggleMinimized: () => setState(() => _minimized = !_minimized),
        onToggleExpanded: () => setState(() {
          _expanded = !_expanded;
          _minimized = false;
        }),
      ),
    );
    final window = DecoratedBox(
      key: const ValueKey('compose-window'),
      decoration: BoxDecoration(
        color: theme.canvas,
        border: Border.all(color: theme.hairlineStrong),
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: view,
      ),
    );
    if (_expanded) {
      return Positioned(
        left: 48,
        right: 48,
        top: 32,
        bottom: 32,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: window,
          ),
        ),
      );
    }
    return Positioned(
      right: composeWindowMargin,
      bottom: composeWindowMargin,
      width: _minimized ? 320 : 560,
      height: _minimized ? 48 : composeWindowHeight(constraints.maxHeight),
      child: window,
    );
  }

  /// The desktop reader. In the unified Inbox its controller changes when you
  /// open a message of another account, so it listens to the view.
  Widget _desktopReader(BuildContext context) {
    Widget reader() => MessageView(
      // Switching account restarts the reader clean.
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

  /// Scrolling down hides the FAB's label, scrolling up shows it again.
  bool _onListScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final extended = switch (n.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _fabExtended.value,
    };
    _fabExtended.value = extended;
    return false;
  }

  /// The phone's folders: a drawer from the left over the dimmed list.
  void _showFolders(BuildContext context) {
    showKaamosDrawer<void>(
      context: context,
      barrierLabel: 'Chiudi cartelle',
      maxWidth: 320,
      builder: (drawerContext) => FolderList(
        controller: _c,
        onSelected: (_) {
          Navigator.of(drawerContext).pop();
          _folderChosen();
        },
        onUnified: widget.onShowUnified == null
            ? null
            : () {
                Navigator.of(drawerContext).pop();
                widget.onShowUnified!();
              },
        unified: widget.unified != null,
      ),
    );
  }

  Widget _mobile(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<UserScrollNotification>(
              onNotification: _onListScroll,
              child: _list(
                context,
                false,
                // Like Google's apps: the account is the avatar at the
                // right of the search bar, not in the folders.
                trailing: _AccountButton(
                  account: _c.account,
                  onPressed: () => _showAccount(context),
                ),
                leading: MailIconButton(
                  icon: MailIcon.menu,
                  label: 'Cartelle',
                  size: 44,
                  onPressed: () => _showFolders(context),
                ),
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 16,
            child: ValueListenableBuilder(
              valueListenable: _fabExtended,
              builder: (context, extended, _) => KaamosFab(
                onPressed: () => _compose(context, const ComposeDraft(), false),
                icon: const MailIconView(MailIcon.edit),
                label: 'Scrivi',
                extended: extended,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of the account list in the dialog.
/// The phone's account button: the active account's avatar.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.account, required this.onPressed});

  final Account account;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return KaamosPressable(
      onPressed: onPressed,
      semanticLabel: 'Account ${account.email}',
      builder: (context, states) => KaamosFocusRing(
        visible: states.contains(WidgetState.focused),
        color: theme.focusRing,
        borderRadius: 22,
        // 44 px: the smallest touch target on a phone.
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: MailAvatar(label: account.displayName, size: 36),
          ),
        ),
      ),
    );
  }
}

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
