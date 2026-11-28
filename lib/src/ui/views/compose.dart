import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/mail_errors.dart';
import '../../core/models.dart';
import '../../core/text_utils.dart';
import '../../state/compose_draft.dart';
import '../../state/mailbox_controller.dart';
import '../environment.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';
import '../widgets/text_area.dart';

/// The addresses of one row (To, Cc, Bcc): the confirmed chips plus the text
/// being typed.
class _Recipients {
  _Recipients(List<Address> initial) : list = [...initial];

  final List<Address> list;
  final text = TextEditingController();
  final focus = FocusNode();

  /// Addresses typed but not valid, to show in red.
  List<String> invalid = const [];

  /// Turns the typed text into chips. Returns `false` if something was invalid
  /// (it stays in the field).
  bool commit() {
    final parsed = parseAddressList(text.text);
    for (final a in parsed.valid) {
      if (!list.any((x) => x.email.toLowerCase() == a.email.toLowerCase())) {
        list.add(a);
      }
    }
    invalid = parsed.invalid;
    text.text = parsed.invalid.join(', ');
    return parsed.invalid.isEmpty;
  }

  bool get isEmpty => list.isEmpty && text.text.trim().isEmpty;

  void dispose() {
    text.dispose();
    focus.dispose();
  }
}

/// The state of the desktop compose window, owned by whoever places it.
class ComposeWindowControls {
  /// Creates the controls.
  const ComposeWindowControls({
    required this.minimized,
    required this.expanded,
    required this.onToggleMinimized,
    required this.onToggleExpanded,
  });

  /// Only the title bar is shown. The text stays: it lives in the State.
  final bool minimized;

  /// The window is large, in the middle of the screen.
  final bool expanded;

  /// Minimizes, or restores a minimized window.
  final VoidCallback onToggleMinimized;

  /// Switches between the normal and the large size.
  final VoidCallback onToggleExpanded;
}

/// The screen for writing a message (plain text only, as decided for the MVP).
///
/// On the phone it is a full page with Send at the top. On desktop it is a
/// floating window like Gmail's ([window] not null): a title bar with
/// minimize, expand and close, and Send at the bottom.
class ComposeView extends StatefulWidget {
  /// Creates the screen starting from [draft].
  const ComposeView({
    super.key,
    required this.controller,
    required this.draft,
    required this.onClose,
    this.window,
  });

  /// Null = a full page; otherwise the desktop window's state.
  final ComposeWindowControls? window;

  /// The mailbox to send from.
  final MailboxController controller;

  /// The starting point.
  final ComposeDraft draft;

  /// Closes the screen (after sending, discarding or saving).
  final VoidCallback onClose;

  @override
  State<ComposeView> createState() => ComposeViewState();
}

/// Public so that the desktop window can ask to close it (see
/// [requestClose]) before opening another message.
class ComposeViewState extends State<ComposeView> {
  late final _to = _Recipients(widget.draft.to);
  late final _cc = _Recipients(widget.draft.cc);
  final _bcc = _Recipients(const []);
  late final _subject = TextEditingController(text: widget.draft.subject);
  late final _body = TextEditingController(text: widget.draft.body);
  final _bodyFocus = FocusNode();
  final List<OutgoingAttachment> _attachments = [];
  late bool _showCopies = widget.draft.cc.isNotEmpty;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final r in [_to, _cc, _bcc]) {
      r.focus.addListener(() {
        if (!r.focus.hasFocus) setState(r.commit);
      });
    }
  }

  @override
  void dispose() {
    for (final r in [_to, _cc, _bcc]) {
      r.dispose();
    }
    _subject.dispose();
    _body.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  String get _title => switch (widget.draft.kind) {
    ComposeKind.fresh => 'Nuovo messaggio',
    ComposeKind.reply || ComposeKind.replyAll => 'Rispondi',
    ComposeKind.forward => 'Inoltra',
  };

  bool get _hasContent =>
      !_to.isEmpty ||
      !_cc.isEmpty ||
      !_bcc.isEmpty ||
      _subject.text.trim().isNotEmpty ||
      _body.text.trim() != widget.draft.body.trim() ||
      _attachments.isNotEmpty;

  OutgoingMessage _message() {
    final account = widget.controller.account;
    return OutgoingMessage(
      from: Address(account.email, account.displayName),
      to: List.of(_to.list),
      cc: List.of(_cc.list),
      bcc: List.of(_bcc.list),
      subject: _subject.text.trim(),
      body: _body.text,
      attachments: List.of(_attachments),
      inReplyTo: widget.draft.inReplyTo,
      references: widget.draft.references,
    );
  }

  Future<void> _send() async {
    final ok = [_to.commit(), _cc.commit(), _bcc.commit()].every((v) => v);
    if (!ok) {
      setState(() => _error = 'Alcuni indirizzi non sono validi.');
      return;
    }
    if (_to.list.isEmpty && _cc.list.isEmpty && _bcc.list.isEmpty) {
      setState(() => _error = 'Aggiungi almeno un destinatario.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.controller.send(
        _message(),
        answeredUid: widget.draft.answeredUid,
        answeredPath: widget.draft.answeredPath,
      );
      if (mounted) widget.onClose();
    } on MailFailure catch (e) {
      _failed('Non inviato: ${e.message}');
    } catch (e, st) {
      _failed('Non inviato: ${describeInternalError(e, st)}');
    }
  }

  void _failed(String message) {
    if (mounted) {
      setState(() {
        _sending = false;
        _error = message;
      });
    }
  }

  Future<void> _attach() async {
    final files = await MailEnvironment.of(context).files.pickAttachments();
    if (files.isNotEmpty && mounted) setState(() => _attachments.addAll(files));
  }

  void _close() => requestClose();

  /// Closes, asking whether to save the draft if something was written.
  /// Returns false if the message stays open ("Continua a scrivere", or the
  /// draft could not be saved).
  Future<bool> requestClose() async {
    if (_sending) return false;
    if (!_hasContent) {
      widget.onClose();
      return true;
    }
    // A minimized window has to show what is being asked about.
    final window = widget.window;
    if (window != null && window.minimized) window.onToggleMinimized();
    final choice = await showKaamosDialog<String>(
      context: context,
      barrierLabel: 'Annulla',
      builder: (context) => KaamosDialog(
        title: 'Salvare la bozza?',
        content: const Text(
          'Il messaggio non è stato inviato. Puoi tenerlo nelle Bozze '
          'del server e riprenderlo da qualsiasi dispositivo.',
        ),
        actions: [
          KaamosButton(
            variant: KaamosButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop('discard'),
            child: const Text('Elimina'),
          ),
          KaamosButton(
            variant: KaamosButtonVariant.tertiary,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continua a scrivere'),
          ),
          KaamosButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    if (choice == 'discard') {
      widget.onClose();
      return true;
    } else if (choice == 'save') {
      for (final r in [_to, _cc, _bcc]) {
        r.commit();
      }
      try {
        final saved = await widget.controller.saveDraft(_message());
        if (!mounted) return false;
        if (saved) {
          widget.onClose();
          return true;
        }
        setState(() => _error = 'Questo account non ha una cartella Bozze.');
      } on MailFailure catch (e) {
        _failed('Bozza non salvata: ${e.message}');
      } catch (e, st) {
        _failed('Bozza non salvata: ${describeInternalError(e, st)}');
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final window = widget.window;
    if (window != null) return _windowed(context, window);
    final theme = KaamosTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
          child: Row(
            children: [
              MailIconButton(
                icon: MailIcon.back,
                label: 'Chiudi',
                size: 44,
                onPressed: _sending ? null : _close,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    _title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KaamosTypography.headingSm.copyWith(
                      color: theme.ink,
                    ),
                  ),
                ),
              ),
              MailIconButton(
                icon: MailIcon.paperclip,
                label: 'Allega file',
                size: 44,
                onPressed: _sending ? null : _attach,
              ),
              const SizedBox(width: 8),
              _sendButton(theme),
            ],
          ),
        ),
        const Hairline(),
        ..._fields(context),
      ],
    );
  }

  Widget _windowed(BuildContext context, ComposeWindowControls window) {
    final theme = KaamosTheme.of(context);
    final bar = _WindowBar(
      subject: _subject,
      fallback: _title,
      window: window,
      onClose: _sending ? null : _close,
    );
    // Minimized: the title bar only. The fields are not built, but what was
    // written stays in this State's controllers.
    if (window.minimized) return bar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _fields(context),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.hairline)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            child: Row(
              children: [
                _sendButton(theme),
                const SizedBox(width: 8),
                MailIconButton(
                  icon: MailIcon.paperclip,
                  label: 'Allega file',
                  size: 40,
                  onPressed: _sending ? null : _attach,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sendButton(KaamosThemeData theme) => KaamosButton(
    onPressed: _sending ? null : _send,
    leading: MailIconView(
      MailIcon.send,
      size: 16,
      color: _sending ? theme.disabledForeground : theme.canvas,
    ),
    child: Text(_sending ? 'Invio…' : 'Invia'),
  );

  List<Widget> _fields(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final account = widget.controller.account;
    return [
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: MailBanner(
            icon: MailIcon.send,
            danger: true,
            message: _error!,
          ),
        ),
      _RecipientRow(
        label: 'A:',
        recipients: _to,
        autofocus: widget.draft.to.isEmpty,
        onChanged: () => setState(() {}),
        trailing: _showCopies
            ? null
            : KaamosLink(
                label: 'Cc Ccn',
                onPressed: () => setState(() => _showCopies = true),
              ),
      ),
      if (_showCopies) ...[
        _RecipientRow(
          label: 'Cc:',
          recipients: _cc,
          onChanged: () => setState(() {}),
        ),
        _RecipientRow(
          label: 'Ccn:',
          recipients: _bcc,
          onChanged: () => setState(() {}),
        ),
      ],
      _FieldRow(
        label: 'Da:',
        child: Text(
          '${account.displayName} <${account.email}>',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: KaamosTypography.bodySm.copyWith(color: theme.body),
        ),
      ),
      _FieldRow(
        label: 'Oggetto:',
        child: MailTextArea(
          controller: _subject,
          semanticLabel: 'Oggetto',
          style: KaamosTypography.bodySm,
          onSubmitted: (_) => _bodyFocus.requestFocus(),
        ),
      ),
      if (_attachments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _attachments.length; i++)
                _Chip(
                  label:
                      '${_attachments[i].fileName} · '
                      '${formatSize(_attachments[i].bytes.length)}',
                  removeLabel: 'Togli ${_attachments[i].fileName}',
                  onRemove: () => setState(() => _attachments.removeAt(i)),
                ),
            ],
          ),
        ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: MailTextArea(
            controller: _body,
            focusNode: _bodyFocus,
            autofocus: widget.draft.to.isNotEmpty,
            maxLines: null,
            placeholder: 'Scrivi il messaggio',
            semanticLabel: 'Testo del messaggio',
          ),
        ),
      ),
    ];
  }
}

/// The title bar of the desktop compose window. A click on the title
/// minimizes or restores, as in Gmail.
class _WindowBar extends StatelessWidget {
  const _WindowBar({
    required this.subject,
    required this.fallback,
    required this.window,
    required this.onClose,
  });

  /// The title is the subject once there is one, like Gmail. Listening to
  /// the field rebuilds only this bar while typing, not the whole form.
  final ValueListenable<TextEditingValue> subject;

  /// The title while the subject is empty ("Nuovo messaggio", "Rispondi").
  final String fallback;

  final ComposeWindowControls window;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: subject,
    builder: (context, value, _) {
      final text = value.text.trim();
      return _bar(context, text.isEmpty ? fallback : text);
    },
  );

  Widget _bar(BuildContext context, String title) {
    final theme = KaamosTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(bottom: BorderSide(color: theme.hairline)),
      ),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            Expanded(
              child: KaamosPressable(
                onPressed: window.onToggleMinimized,
                semanticLabel: window.minimized
                    ? 'Ripristina $title'
                    : 'Riduci $title',
                builder: (context, states) => Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KaamosTypography.bodySmStrong.copyWith(
                        color: theme.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            MailIconButton(
              icon: window.minimized ? MailIcon.expand : MailIcon.minimize,
              label: window.minimized ? 'Ripristina' : 'Riduci',
              size: 36,
              onPressed: window.onToggleMinimized,
            ),
            if (!window.minimized)
              MailIconButton(
                icon: window.expanded ? MailIcon.collapse : MailIcon.expand,
                label: window.expanded ? 'Dimensione normale' : 'Ingrandisci',
                size: 36,
                onPressed: window.onToggleExpanded,
              ),
            MailIconButton(
              icon: MailIcon.close,
              label: 'Chiudi',
              size: 36,
              onPressed: onClose,
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

/// A "Label: value" row with the line below. The value sits right after the
/// label (8px), as in the mockup.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.child, this.trailing});

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.hairline)),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Text(
              label,
              style: KaamosTypography.bodySm.copyWith(color: theme.mute),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _RecipientRow extends StatelessWidget {
  const _RecipientRow({
    required this.label,
    required this.recipients,
    required this.onChanged,
    this.trailing,
    this.autofocus = false,
  });

  final String label;
  final _Recipients recipients;
  final VoidCallback onChanged;
  final Widget? trailing;
  final bool autofocus;

  void _onText(String value) {
    // Comma, semicolon or newline closes an address.
    if (value.contains(RegExp(r'[,;\n]'))) {
      recipients.commit();
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final field = label.replaceAll(':', '');
    return _FieldRow(
      label: label,
      trailing: trailing,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final a in recipients.list)
            _Chip(
              label: a.label,
              tooltip: a.email,
              removeLabel: 'Togli ${a.email} da $field',
              onRemove: () {
                recipients.list.remove(a);
                onChanged();
              },
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 160, maxWidth: 360),
            child: IntrinsicWidth(
              child: MailTextArea(
                controller: recipients.text,
                focusNode: recipients.focus,
                autofocus: autofocus,
                semanticLabel: 'Destinatari $field',
                keyboardType: TextInputType.emailAddress,
                style: KaamosTypography.bodySm.copyWith(
                  color: recipients.invalid.isEmpty ? null : theme.danger,
                ),
                onChanged: _onText,
                onSubmitted: (_) {
                  recipients.commit();
                  onChanged();
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A chip with the button to remove it. It never wraps and never shrinks (the
/// "all squashed" fix on the mockup).
class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.removeLabel,
    required this.onRemove,
    this.tooltip,
  });

  final String label;
  final String removeLabel;
  final VoidCallback onRemove;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: BoxDecoration(
        color: theme.surfaceElevated,
        border: Border.all(color: theme.hairline),
        borderRadius: const BorderRadius.all(Radius.circular(14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Semantics(
              container: true,
              label: tooltip == null ? label : '$label, $tooltip',
              child: ExcludeSemantics(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: KaamosTypography.captionMd.copyWith(color: theme.ink),
                ),
              ),
            ),
          ),
          // A node of its own: otherwise the screen reader merges the name and
          // "Togli" (remove).
          Semantics(
            container: true,
            child: KaamosPressable(
              onPressed: onRemove,
              semanticLabel: removeLabel,
              builder: (context, states) => SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: KaamosIcon(
                    KaamosIcons.close,
                    size: 12,
                    color: states.contains(WidgetState.hovered)
                        ? theme.ink
                        : theme.mute,
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
