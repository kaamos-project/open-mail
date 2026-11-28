import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/models.dart';
import '../../core/text_utils.dart';
import '../../state/mailbox_controller.dart';
import '../../state/unified_inbox.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';

/// The message list of the open folder, with search and "Load more".
class MessageList extends StatefulWidget {
  /// Creates the list.
  const MessageList({
    super.key,
    required this.controller,
    required this.onOpen,
    this.leading,
    this.trailing,
  });

  /// The mailbox state.
  final MailboxController controller;

  /// A message was chosen.
  final ValueChanged<MessageSummary> onOpen;

  /// Widget before the title (on mobile: the folders button).
  final Widget? leading;

  /// Widget at the right of the search bar, or of the title where there is
  /// no search (on mobile: the account avatar).
  final Widget? trailing;

  @override
  State<MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<MessageList> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _submitSearch(String value) {
    final query = value.trim();
    widget.controller.search(query);
  }

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final title = c.searchQuery == null
            ? c.currentLabel
            : 'Risultati per "${c.searchQuery}"';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  if (widget.leading != null) ...[
                    widget.leading!,
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KaamosTypography.headingSm.copyWith(
                          color: theme.ink,
                        ),
                      ),
                    ),
                  ),
                  MailIconButton(
                    icon: MailIcon.refresh,
                    label: c.syncing ? 'Aggiornamento in corso' : 'Aggiorna',
                    onPressed: c.syncing ? null : () => c.refresh(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: KaamosSearchBar(
                      controller: _search,
                      placeholder: 'Cerca nella cartella',
                      semanticLabel: 'Cerca nella cartella',
                      onSubmitted: _submitSearch,
                      onChanged: (v) {
                        if (v.isEmpty && c.searchQuery != null) c.search('');
                      },
                    ),
                  ),
                  if (widget.trailing != null) ...[
                    const SizedBox(width: 8),
                    widget.trailing!,
                  ],
                ],
              ),
            ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: MailBanner(
                  icon: MailIcon.shield,
                  danger: true,
                  message: c.error!,
                  action: KaamosButton(
                    variant: KaamosButtonVariant.install,
                    onPressed: c.dismissError,
                    child: const Text('Chiudi'),
                  ),
                ),
              ),
            const Hairline(),
            Expanded(child: _buildList(context, c)),
          ],
        );
      },
    );
  }

  Widget _buildList(BuildContext context, MailboxController c) {
    final theme = KaamosTheme.of(context);
    if (c.messages.isEmpty) {
      final text = c.syncing
          ? 'Sto scaricando i messaggi…'
          : c.searchQuery != null
          ? 'Nessun messaggio trovato.'
          : 'Questa cartella è vuota.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: KaamosTypography.bodySm.copyWith(color: theme.mute),
          ),
        ),
      );
    }
    final extra = c.hasMore ? 1 : 0;
    return ListView.builder(
      itemCount: c.messages.length + extra,
      itemBuilder: (context, i) {
        if (i == c.messages.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: KaamosButton(
                variant: KaamosButtonVariant.tertiary,
                onPressed: c.syncing ? null : c.loadMore,
                child: const Text('Carica altri'),
              ),
            ),
          );
        }
        final m = c.messages[i];
        return MessageRow(
          message: m,
          selected:
              m.uid == c.openUid &&
              (c.openPath ?? c.current.path) == c.current.path,
          onPressed: () => widget.onOpen(m),
        );
      },
    );
  }
}

/// A list row: sender, date, subject, preview.
class MessageRow extends StatelessWidget {
  /// Creates the row.
  const MessageRow({
    super.key,
    required this.message,
    required this.selected,
    required this.onPressed,
    this.account,
  });

  /// The message.
  final MessageSummary message;

  /// In the unified Inbox: the message's account.
  final String? account;

  /// It is the open one.
  final bool selected;

  /// Opens the message.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final m = message;
    final unread = !m.seen;
    final sender = m.from?.label ?? '(nessun mittente)';
    final subject = m.subject.trim().isEmpty ? '(senza oggetto)' : m.subject;
    final date = m.date == null ? '' : formatListDate(m.date!);
    final label = [
      if (unread) 'Non letto',
      sender,
      subject,
      date,
      if (m.flagged) 'Con stella',
      if (m.hasAttachments) 'Con allegati',
      if (account != null) 'Account $account',
    ].join(', ');
    return Semantics(
      selected: selected,
      child: KaamosPressable(
        onPressed: onPressed,
        semanticLabel: label,
        builder: (context, states) {
          final hovered = states.contains(WidgetState.hovered);
          return KaamosFocusRing(
            visible: states.contains(WidgetState.focused),
            color: theme.focusRing,
            borderRadius: KaamosRadius.xs,
            child: Container(
              decoration: BoxDecoration(
                color: selected
                    ? theme.surfaceElevated
                    : hovered
                    ? theme.surface
                    : null,
                border: Border(bottom: BorderSide(color: theme.hairline)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The unread dot: a colour plus a different text weight, so
                  // it doesn't rely on colour alone.
                  SizedBox(
                    width: 16,
                    height: 20,
                    child: unread
                        ? Center(
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: theme.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                sender,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    (unread
                                            ? KaamosTypography.bodySmStrong
                                            : KaamosTypography.bodySm)
                                        .copyWith(color: theme.ink),
                              ),
                            ),
                            if (m.hasAttachments) ...[
                              MailIconView(
                                MailIcon.paperclip,
                                size: 14,
                                color: theme.mute,
                              ),
                              const SizedBox(width: 6),
                            ],
                            if (m.flagged) ...[
                              MailIconView(
                                MailIcon.starFilled,
                                size: 14,
                                color: theme.accent,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              date,
                              style: KaamosTypography.captionSm.copyWith(
                                color: theme.mute,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              (unread
                                      ? KaamosTypography.bodySmStrong
                                      : KaamosTypography.bodySm)
                                  .copyWith(
                                    color: unread ? theme.ink : theme.body,
                                  ),
                        ),
                        if (m.preview.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            m.preview,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: KaamosTypography.captionMd.copyWith(
                              color: theme.mute,
                            ),
                          ),
                        ],
                        if (account != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            account!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KaamosTypography.captionSm.copyWith(
                              color: theme.mute,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Every account's Inbox in one list. No search or "Load more" for now: search
/// inside the account.
class UnifiedMessageList extends StatelessWidget {
  /// Creates the list.
  const UnifiedMessageList({
    super.key,
    required this.inbox,
    required this.onOpen,
    this.leading,
    this.trailing,
  });

  /// The unified Inbox.
  final UnifiedInbox inbox;

  /// A message was chosen.
  final ValueChanged<UnifiedItem> onOpen;

  /// Widget before the title (on mobile: the folders button).
  final Widget? leading;

  /// Widget at the right of the search bar, or of the title where there is
  /// no search (on mobile: the account avatar).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return ListenableBuilder(
      listenable: inbox,
      builder: (context, _) {
        final error = inbox.error;
        final open = inbox.open;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 8)],
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        'Tutte le caselle',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: KaamosTypography.headingSm.copyWith(
                          color: theme.ink,
                        ),
                      ),
                    ),
                  ),
                  MailIconButton(
                    icon: MailIcon.refresh,
                    label: inbox.syncing
                        ? 'Aggiornamento in corso'
                        : 'Aggiorna',
                    onPressed: inbox.syncing ? null : inbox.refresh,
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: MailBanner(
                  icon: MailIcon.shield,
                  danger: true,
                  message: error,
                  action: KaamosButton(
                    variant: KaamosButtonVariant.install,
                    onPressed: inbox.dismissError,
                    child: const Text('Chiudi'),
                  ),
                ),
              ),
            const Hairline(),
            Expanded(
              child: inbox.items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          inbox.syncing
                              ? 'Sto scaricando i messaggi…'
                              : 'Le Inbox sono vuote.',
                          textAlign: TextAlign.center,
                          style: KaamosTypography.bodySm.copyWith(
                            color: theme.mute,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: inbox.items.length,
                      itemBuilder: (context, i) {
                        final item = inbox.items[i];
                        return MessageRow(
                          message: item.summary,
                          account: item.account.email,
                          selected:
                              open != null &&
                              open.accountId == item.account.id &&
                              open.uid == item.summary.uid,
                          onPressed: () => onOpen(item),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
