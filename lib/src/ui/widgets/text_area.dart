// La libreria non esporta ancora i controlli di selezione e il menu
// contestuale: li importiamo da src finché non arriva un KaamosTextArea
// ufficiale (da proporre in open-ui-flutter).
// ignore_for_file: implementation_imports

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';
import 'package:kaamos_project_ui/src/components/text_field/context_menu.dart';
import 'package:kaamos_project_ui/src/components/text_field/selection_controls.dart';

/// Un campo di testo senza cornice, a una o più righe.
///
/// È una copia ridotta di `KaamosEditable` della libreria, con due
/// differenze: [maxLines] (il corpo della mail va a capo) e nessuna cornice
/// (le righe A/Da/Oggetto hanno solo la linea sotto, come nel mockup).
class MailTextArea extends StatefulWidget {
  /// Crea il campo.
  const MailTextArea({
    super.key,
    required this.controller,
    this.focusNode,
    this.placeholder,
    this.semanticLabel,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.style,
  });

  /// Il testo.
  final TextEditingController controller;

  /// Il focus, se serve controllarlo da fuori.
  final FocusNode? focusNode;

  /// Testo grigio quando il campo è vuoto.
  final String? placeholder;

  /// Nome per gli screen reader.
  final String? semanticLabel;

  /// `null` = quante righe servono.
  final int? maxLines;

  /// Tipo di tastiera.
  final TextInputType? keyboardType;

  /// Tasto azione della tastiera.
  final TextInputAction? textInputAction;

  /// Invio premuto.
  final ValueChanged<String>? onSubmitted;

  /// Testo cambiato.
  final ValueChanged<String>? onChanged;

  /// Prende il focus appena compare.
  final bool autofocus;

  /// Stile del testo.
  final TextStyle? style;

  @override
  State<MailTextArea> createState() => _MailTextAreaState();
}

class _MailTextAreaState extends State<MailTextArea>
    implements TextSelectionGestureDetectorBuilderDelegate {
  FocusNode? _ownFocus;
  bool _showHandles = false;
  late final TextSelectionGestureDetectorBuilder _gestures =
      TextSelectionGestureDetectorBuilder(delegate: this);

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  final GlobalKey<EditableTextState> editableTextKey =
      GlobalKey<EditableTextState>();

  @override
  bool get forcePressEnabled => false;

  @override
  bool get selectionEnabled => true;

  @override
  void dispose() {
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onSelectionChanged(TextSelection s, SelectionChangedCause? cause) {
    final show =
        _gestures.shouldShowSelectionHandles &&
        cause != SelectionChangedCause.keyboard &&
        (cause == SelectionChangedCause.longPress ||
            widget.controller.text.isNotEmpty);
    if (show != _showHandles) setState(() => _showHandles = show);
  }

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    final style = (widget.style ?? KaamosTypography.bodyMd).copyWith(
      color: theme.onDark,
    );
    final multiline = widget.maxLines != 1;
    final editable = EditableText(
      key: editableTextKey,
      controller: widget.controller,
      focusNode: _focus,
      style: style,
      cursorColor: theme.cursor,
      backgroundCursorColor: theme.mute,
      selectionColor: theme.selection,
      cursorWidth: 1.5,
      cursorRadius: const Radius.circular(1),
      autofocus: widget.autofocus,
      keyboardType:
          widget.keyboardType ??
          (multiline ? TextInputType.multiline : TextInputType.text),
      textInputAction:
          widget.textInputAction ??
          (multiline ? TextInputAction.newline : TextInputAction.next),
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      rendererIgnoresPointer: true,
      showSelectionHandles: _showHandles,
      selectionControls: kaamosTextSelectionControls,
      onSelectionChanged: _onSelectionChanged,
      contextMenuBuilder: (kIsWeb && BrowserContextMenu.enabled)
          ? null
          : (context, state) => KaamosTextContextMenu(
              anchors: state.contextMenuAnchors,
              items: state.contextMenuButtonItems,
            ),
      maxLines: widget.maxLines,
    );
    final placeholder = widget.placeholder;
    return Semantics(
      label: widget.semanticLabel,
      hint: placeholder,
      textField: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        child: _gestures.buildGestureDetector(
          behavior: HitTestBehavior.translucent,
          child: Stack(
            alignment: multiline
                ? AlignmentDirectional.topStart
                : AlignmentDirectional.centerStart,
            children: [
              if (placeholder != null)
                IgnorePointer(
                  child: ExcludeSemantics(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: widget.controller,
                      builder: (context, value, _) => value.text.isEmpty
                          ? Text(
                              placeholder,
                              style: style.copyWith(color: theme.mute),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              editable,
            ],
          ),
        ),
      ),
    );
  }
}

/// Rende selezionabile (e copiabile) il testo dentro [child], senza
/// Material: una `SelectableRegion` con i controlli di selezione Kaamos.
class MailSelectable extends StatefulWidget {
  /// Avvolge [child].
  const MailSelectable({super.key, required this.child});

  /// Il contenuto con il testo.
  final Widget child;

  @override
  State<MailSelectable> createState() => _MailSelectableState();
}

class _MailSelectableState extends State<MailSelectable> {
  final _focus = FocusNode(debugLabel: 'MailSelectable');

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectableRegion(
    focusNode: _focus,
    selectionControls: kaamosTextSelectionControls,
    contextMenuBuilder: (context, state) => KaamosTextContextMenu(
      anchors: state.contextMenuAnchors,
      items: state.contextMenuButtonItems,
    ),
    child: widget.child,
  );
}
