import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/models.dart';
import '../../core/text_utils.dart';
import '../../state/mailbox_controller.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';

/// La lista dei messaggi della cartella aperta, con ricerca e "Carica altri".
class MessageList extends StatefulWidget {
  /// Crea la lista.
  const MessageList({
    super.key,
    required this.controller,
    required this.onOpen,
    this.leading,
  });

  /// Lo stato della casella.
  final MailboxController controller;

  /// Un messaggio è stato scelto.
  final ValueChanged<MessageSummary> onOpen;

  /// Widget prima del titolo (su mobile: il bottone delle cartelle).
  final Widget? leading;

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
          selected: m.uid == c.openUid,
          onPressed: () => widget.onOpen(m),
        );
      },
    );
  }
}

/// Una riga della lista: mittente, data, oggetto, anteprima.
class MessageRow extends StatelessWidget {
  /// Crea la riga.
  const MessageRow({
    super.key,
    required this.message,
    required this.selected,
    required this.onPressed,
  });

  /// Il messaggio.
  final MessageSummary message;

  /// È quello aperto.
  final bool selected;

  /// Apre il messaggio.
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
                  // Il pallino dei non letti: un colore più un peso del
                  // testo diverso, così non dipende solo dal colore.
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
