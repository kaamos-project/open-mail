// The library doesn't export the selection controls and context menu yet: we
// import them from src until an official KaamosTextArea arrives (to be proposed
// in open-ui-flutter).
// ignore_for_file: implementation_imports

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';
import 'package:kaamos_project_ui/src/components/text_field/context_menu.dart';
import 'package:kaamos_project_ui/src/components/text_field/selection_controls.dart';

/// A borderless text field, single or multi-line.
///
/// It is a trimmed-down copy of the library's `KaamosEditable`, with two
/// differences: [maxLines] (the mail body wraps) and no border (the
/// To/From/Subject rows only have the line below, as in the mockup).
class MailTextArea extends StatefulWidget {
  /// Creates the field.
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

  /// The text.
  final TextEditingController controller;

  /// The focus, if it needs to be controlled from outside.
  final FocusNode? focusNode;

  /// Grey text when the field is empty.
  final String? placeholder;

  /// Name for screen readers.
  final String? semanticLabel;

  /// `null` = as many lines as needed.
  final int? maxLines;

  /// Keyboard type.
  final TextInputType? keyboardType;

  /// Keyboard action key.
  final TextInputAction? textInputAction;

  /// Enter pressed.
  final ValueChanged<String>? onSubmitted;

  /// Text changed.
  final ValueChanged<String>? onChanged;

  /// Takes focus as soon as it appears.
  final bool autofocus;

  /// Text style.
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

/// Makes the text inside [child] selectable (and copyable), without Material: a
/// `SelectableRegion` with the Kaamos selection controls.
class MailSelectable extends StatefulWidget {
  /// Wraps [child].
  const MailSelectable({super.key, required this.child});

  /// The content with the text.
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
