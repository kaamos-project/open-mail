import 'package:flutter/services.dart' show TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../state/mailbox_controller.dart';

/// Gmail's "Etichetta come": every label of the account with a checkbox,
/// a search field on top, and "Crea «…»" when the name doesn't exist.
///
/// Each tick applies at once (optimistic, like the X on the chips): there
/// is no "Applica" button. On desktop it sits in a popover under the
/// toolbar button; on the phone it is a page of its own.
class LabelPicker extends StatefulWidget {
  /// Creates the picker for message [uid] in the folder at [path].
  const LabelPicker({
    super.key,
    required this.controller,
    required this.uid,
    required this.path,
    required this.onLeave,
  });

  /// The account of the message.
  final MailboxController controller;

  /// The message.
  final int uid;

  /// The folder the message is in.
  final String? path;

  /// Called after unticking the label of the folder the message is in:
  /// the message leaves the folder, so the picker and the message close.
  final VoidCallback onLeave;

  @override
  State<LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<LabelPicker> {
  final _query = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  MailboxController get _c => widget.controller;

  void _toggle(String label, bool add) {
    if (add) {
      _c.addLabel(widget.uid, label, path: widget.path);
      return;
    }
    final leaves = _c.isFolderLabel(label, widget.path);
    _c.removeLabel(widget.uid, label, path: widget.path);
    if (leaves) widget.onLeave();
  }

  Future<void> _create(String name) async {
    setState(() => _creating = true);
    final ok = await _c.createLabel(widget.uid, name, path: widget.path);
    if (!mounted) return;
    setState(() => _creating = false);
    if (ok) _query.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([_c, _query]),
      builder: (context, _) {
        final has = (_c.openSummary?.labels ?? const <String>[]).toSet();
        final query = _query.text.trim();
        final all = _c.labelNames;
        final shown = [
          for (final l in all)
            if (l.toLowerCase().contains(query.toLowerCase())) l,
        ];
        final canCreate =
            query.isNotEmpty &&
            !all.any((l) => l.toLowerCase() == query.toLowerCase());
        final error = _c.error;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KaamosTextField(
              controller: _query,
              placeholder: 'Cerca o crea un’etichetta',
              semanticLabel: 'Cerca etichetta',
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (canCreate && !_creating) _create(query);
              },
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                primary: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final l in shown)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: KaamosCheckbox(
                          value: has.contains(l),
                          onChanged: (v) => _toggle(l, v ?? false),
                          label: Text(
                            l,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    if (shown.isEmpty && !canCreate)
                      Text(
                        'Nessuna etichetta.',
                        style: KaamosTypography.bodySm.copyWith(
                          color: theme.mute,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (canCreate) ...[
              const SizedBox(height: 8),
              KaamosButton(
                variant: KaamosButtonVariant.secondary,
                onPressed: _creating ? null : () => _create(query),
                leading: const KaamosIcon(KaamosIcons.plus),
                child: Text(
                  'Crea «$query»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: KaamosTypography.captionMd.copyWith(color: theme.danger),
              ),
            ],
          ],
        );
      },
    );
  }
}
