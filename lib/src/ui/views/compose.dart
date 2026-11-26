import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/models.dart';
import '../../core/text_utils.dart';
import '../../data/imap_mail_service.dart' show describeMailError;
import '../../state/compose_draft.dart';
import '../../state/mailbox_controller.dart';
import '../environment.dart';
import '../widgets/common.dart';
import '../widgets/mail_icons.dart';
import '../widgets/text_area.dart';

/// Gli indirizzi di una riga (A, Cc, Ccn): i chip già confermati più il
/// testo che si sta scrivendo.
class _Recipients {
  _Recipients(List<Address> initial) : list = [...initial];

  final List<Address> list;
  final text = TextEditingController();
  final focus = FocusNode();

  /// Indirizzi scritti ma non validi, da mostrare in rosso.
  List<String> invalid = const [];

  /// Trasforma in chip il testo scritto. Restituisce `false` se c'era
  /// qualcosa di non valido (che resta nel campo).
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

/// La schermata per scrivere un messaggio (solo testo semplice, come
/// deciso per l'MVP).
class ComposeView extends StatefulWidget {
  /// Crea la schermata partendo da [draft].
  const ComposeView({
    super.key,
    required this.controller,
    required this.draft,
    required this.onClose,
  });

  /// La casella da cui si invia.
  final MailboxController controller;

  /// Il punto di partenza.
  final ComposeDraft draft;

  /// Chiude la schermata (dopo l'invio, lo scarto o il salvataggio).
  final VoidCallback onClose;

  @override
  State<ComposeView> createState() => _ComposeViewState();
}

class _ComposeViewState extends State<ComposeView> {
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
      );
      if (mounted) widget.onClose();
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Non inviato: ${describeMailError(e)}';
        });
      }
    }
  }

  Future<void> _attach() async {
    final files = await MailEnvironment.of(context).files.pickAttachments();
    if (files.isNotEmpty && mounted) setState(() => _attachments.addAll(files));
  }

  /// Chiudendo con qualcosa di scritto chiede se salvare la bozza.
  Future<void> _close() async {
    if (!_hasContent) {
      widget.onClose();
      return;
    }
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
    if (!mounted) return;
    if (choice == 'discard') {
      widget.onClose();
    } else if (choice == 'save') {
      for (final r in [_to, _cc, _bcc]) {
        r.commit();
      }
      try {
        final saved = await widget.controller.saveDraft(_message());
        if (!mounted) return;
        if (saved) {
          widget.onClose();
        } else {
          setState(() => _error = 'Questo account non ha una cartella Bozze.');
        }
      } on Object catch (e) {
        if (mounted) {
          setState(() => _error = 'Bozza non salvata: ${describeMailError(e)}');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final account = widget.controller.account;
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
              KaamosButton(
                onPressed: _sending ? null : _send,
                leading: MailIconView(
                  MailIcon.send,
                  size: 16,
                  color: _sending ? theme.disabledForeground : theme.canvas,
                ),
                child: Text(_sending ? 'Invio…' : 'Invia'),
              ),
            ],
          ),
        ),
        const Hairline(),
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
      ],
    );
  }
}

/// Una riga "Etichetta: valore" con la linea sotto. Il valore sta subito
/// dopo l'etichetta (8px), come nel mockup.
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
    // Virgola, punto e virgola o a capo chiudono un indirizzo.
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

/// Un chip con il bottone per toglierlo. Non va mai a capo e non si
/// restringe (la correzione sul mockup "tutto schiacciato").
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
          // Un nodo a sé: altrimenti lo screen reader fonde nome e "Togli".
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
