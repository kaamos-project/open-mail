import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/html_sanitizer.dart';
import '../../core/models.dart';
import '../../core/text_utils.dart';
import '../../data/imap_mail_service.dart' show describeMailError;
import '../../state/compose_draft.dart';
import '../../state/mailbox_controller.dart';
import '../environment.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';
import '../widgets/text_area.dart';

/// The open message: header, actions, body and attachments.
class MessageView extends StatelessWidget {
  /// Creates the view.
  const MessageView({
    super.key,
    required this.controller,
    required this.onCompose,
    this.onBack,
  });

  /// The mailbox state.
  final MailboxController controller;

  /// Reply / forward: opens compose with this draft.
  final ValueChanged<ComposeDraft> onCompose;

  /// On mobile: back to the list. On desktop `null`.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final uid = controller.openUid;
        final content = controller.openMessage;
        if (uid == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MailIconView(MailIcon.mail, size: 32, color: theme.mute),
                const SizedBox(height: 12),
                Text(
                  'Scegli un messaggio da leggere',
                  style: KaamosTypography.bodySm.copyWith(color: theme.mute),
                ),
              ],
            ),
          );
        }
        if (content == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onBack != null) _BackBar(onBack: onBack!),
              Expanded(
                child: Center(
                  child: Text(
                    controller.loadingMessage
                        ? 'Apro il messaggio…'
                        : 'Il messaggio non si è aperto.',
                    style: KaamosTypography.bodySm.copyWith(color: theme.mute),
                  ),
                ),
              ),
            ],
          );
        }
        // Keyed on the UID: switching message resets the state (loaded images,
        // cleaned document).
        return _MessageBody(
          key: ValueKey(content.summary.uid),
          controller: controller,
          content: content,
          onCompose: onCompose,
          onBack: onBack,
        );
      },
    );
  }
}

class _BackBar extends StatelessWidget {
  const _BackBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
    child: Row(
      children: [
        MailIconButton(
          icon: MailIcon.back,
          label: 'Indietro',
          onPressed: onBack,
          size: 44,
        ),
      ],
    ),
  );
}

class _MessageBody extends StatefulWidget {
  const _MessageBody({
    super.key,
    required this.controller,
    required this.content,
    required this.onCompose,
    required this.onBack,
  });

  final MailboxController controller;
  final MessageContent content;
  final ValueChanged<ComposeDraft> onCompose;
  final VoidCallback? onBack;

  @override
  State<_MessageBody> createState() => _MessageBodyState();
}

class _MessageBodyState extends State<_MessageBody> {
  bool _allowRemote = false;
  SanitizedHtml? _sanitized;
  String? _attachmentError;
  String? _downloading;

  @override
  void initState() {
    super.initState();
    _sanitize();
  }

  // Cleaning runs on the UI thread: a few milliseconds for normal mail. If it
  // ever gets slow (huge newsletters) it moves to an Isolate with `compute`.
  void _sanitize() {
    final html = widget.content.html;
    if (html == null) return;
    _sanitized = const HtmlSanitizer().sanitize(
      html,
      inlineImages: widget.content.inlineImages,
      allowRemote: _allowRemote,
    );
  }

  void _loadImages() => setState(() {
    _allowRemote = true;
    _sanitize();
  });

  Future<void> _openAttachment(AttachmentInfo a) async {
    final env = MailEnvironment.of(context);
    setState(() {
      _downloading = a.fetchId;
      _attachmentError = null;
    });
    try {
      final bytes = await widget.controller.downloadAttachment(a);
      await env.files.openAttachment(a.fileName, bytes);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _attachmentError =
              'Non riesco ad aprire ${a.fileName}: ${describeMailError(e)}',
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final env = MailEnvironment.of(context);
    final c = widget.controller;
    final m = widget.content;
    final s = m.summary;
    // The star changes in the list (optimistic update), not in the content
    // already downloaded: read it from there.
    final flagged = c.openSummary?.flagged ?? s.flagged;
    final labels = c.openSummary?.labels ?? s.labels;
    final me = c.account;
    // The message may come from a folder other than the open one (unified
    // Inbox): every action says which.
    final path = c.openPath;
    final folder = c.openFolder;
    final archive = c.folderWithRole(FolderRole.archive);
    final inArchive = folder.role == FolderRole.archive;

    final actions = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        MailIconButton(
          icon: MailIcon.reply,
          label: 'Rispondi',
          onPressed: () =>
              widget.onCompose(ComposeDraft.reply(m, me: me, path: path)),
        ),
        if (s.to.length + m.cc.length > 1)
          MailIconButton(
            icon: MailIcon.reply,
            label: 'Rispondi a tutti',
            iconColor: theme.accent,
            onPressed: () => widget.onCompose(
              ComposeDraft.reply(m, me: me, all: true, path: path),
            ),
          ),
        MailIconButton(
          icon: MailIcon.forward,
          label: 'Inoltra',
          onPressed: () => widget.onCompose(ComposeDraft.forward(m)),
        ),
        MailIconButton(
          icon: flagged ? MailIcon.starFilled : MailIcon.star,
          label: flagged ? 'Togli la stella' : 'Metti la stella',
          iconColor: flagged ? theme.accent : null,
          onPressed: () => c.setFlagged([s.uid], flagged: !flagged, path: path),
        ),
        MailIconButton(
          icon: MailIcon.mail,
          label: 'Segna come non letto',
          onPressed: () {
            c.setSeen([s.uid], seen: false, path: path);
            c.closeMessage();
            widget.onBack?.call();
          },
        ),
        if (archive != null && !inArchive)
          MailIconButton(
            icon: MailIcon.archive,
            label: 'Archivia',
            onPressed: () {
              c.archive([s.uid], path: path);
              widget.onBack?.call();
            },
          ),
        MailIconButton(
          icon: MailIcon.trash,
          label: folder.role == FolderRole.trash
              ? 'Elimina definitivamente'
              : 'Sposta nel cestino',
          onPressed: () {
            c.delete([s.uid], path: path);
            widget.onBack?.call();
          },
        ),
      ],
    );

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.onBack != null) ...[
                MailIconButton(
                  icon: MailIcon.back,
                  label: 'Indietro',
                  onPressed: widget.onBack,
                  size: 44,
                ),
                const Spacer(),
              ],
              Flexible(child: actions),
            ],
          ),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              s.subject.trim().isEmpty ? '(senza oggetto)' : s.subject,
              style: KaamosTypography.headingMd.copyWith(color: theme.ink),
            ),
          ),
          if (MailLabels.visible(labels, path).isNotEmpty) ...[
            const SizedBox(height: 8),
            MailLabels(labels: labels, hide: path),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MailAvatar(label: s.from?.label ?? '?'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.from?.toString() ?? '(nessun mittente)',
                      style: KaamosTypography.bodySmStrong.copyWith(
                        color: theme.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        'A: ${s.to.map((a) => a.label).join(', ')}',
                        if (m.cc.isNotEmpty)
                          'Cc: ${m.cc.map((a) => a.label).join(', ')}',
                      ].join('\n'),
                      style: KaamosTypography.captionMd.copyWith(
                        color: theme.mute,
                      ),
                    ),
                  ],
                ),
              ),
              if (s.date != null)
                Text(
                  formatFullDate(s.date!),
                  style: KaamosTypography.captionSm.copyWith(color: theme.mute),
                ),
            ],
          ),
        ],
      ),
    );

    final sanitized = _sanitized;
    final Widget body;
    if (sanitized != null) {
      body = env.htmlBody(context, sanitized.document, env.files.openLink);
    } else {
      body = SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: MailSelectable(
          child: Text(
            (m.plainText ?? '').trimRight(),
            style: KaamosTypography.bodyMd.copyWith(color: theme.body),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MailSelectable(child: header),
        if (sanitized != null && sanitized.blockedRemote > 0 && !_allowRemote)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: MailBanner(
              icon: MailIcon.shield,
              message:
                  'Ho bloccato ${sanitized.blockedRemote} immagini remote: '
                  'chi le manda saprebbe quando e da dove leggi.',
              action: KaamosButton(
                variant: KaamosButtonVariant.install,
                onPressed: _loadImages,
                child: const Text('Carica immagini'),
              ),
            ),
          ),
        if (m.attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in m.attachments)
                  _AttachmentChip(
                    attachment: a,
                    busy: _downloading == a.fetchId,
                    onPressed: _downloading == null
                        ? () => _openAttachment(a)
                        : null,
                  ),
              ],
            ),
          ),
        if (_attachmentError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: MailBanner(
              icon: MailIcon.paperclip,
              danger: true,
              message: _attachmentError!,
            ),
          ),
        const Hairline(),
        Expanded(child: body),
      ],
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    required this.busy,
    required this.onPressed,
  });

  final AttachmentInfo attachment;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final size = attachment.size == null ? '' : formatSize(attachment.size!);
    return KaamosPressable(
      onPressed: onPressed,
      semanticLabel: 'Apri allegato ${attachment.fileName} $size',
      builder: (context, states) => KaamosFocusRing(
        visible: states.contains(WidgetState.focused),
        color: theme.focusRing,
        borderRadius: KaamosRadius.md,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 280),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: states.contains(WidgetState.hovered)
                ? theme.surfaceElevated
                : theme.surface,
            border: Border.all(color: theme.hairline),
            borderRadius: const BorderRadius.all(
              Radius.circular(KaamosRadius.md),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              MailIconView(MailIcon.paperclip, size: 16, color: theme.mute),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KaamosTypography.captionMd.copyWith(color: theme.ink),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                busy ? 'apro…' : size,
                style: KaamosTypography.captionSm.copyWith(color: theme.mute),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
