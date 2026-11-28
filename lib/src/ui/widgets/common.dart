import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/text_utils.dart';
import 'mail_icons.dart';

/// Square icon-only button (36px, 44px on touch).
class MailIconButton extends StatelessWidget {
  /// Creates the button. [label] is required: it is what the screen reader
  /// reads instead of the icon.
  const MailIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 36,
    this.filled = false,
    this.iconColor,
  });

  /// The icon.
  final MailIcon icon;

  /// Name of the action.
  final String label;

  /// Action; `null` = disabled.
  final VoidCallback? onPressed;

  /// Side of the button.
  final double size;

  /// `surfaceElevated` background instead of transparent.
  final bool filled;

  /// Icon colour, if different from the default.
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return KaamosPressable(
      onPressed: onPressed,
      semanticLabel: label,
      builder: (context, states) {
        final hovered =
            states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed);
        final disabled = states.contains(WidgetState.disabled);
        return KaamosFocusRing(
          visible: states.contains(WidgetState.focused),
          color: theme.focusRing,
          borderRadius: KaamosRadius.md,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: filled || hovered ? theme.surfaceElevated : null,
              borderRadius: const BorderRadius.all(
                Radius.circular(KaamosRadius.md),
              ),
            ),
            alignment: Alignment.center,
            child: MailIconView(
              icon,
              size: 18,
              color: disabled
                  ? theme.disabledForeground
                  : iconColor ?? (filled ? theme.onDark : theme.body),
            ),
          ),
        );
      },
    );
  }
}

/// A message's Gmail labels as small badges. System labels are left out,
/// and so is [hide] (the label of the folder being shown: every message
/// there has it).
class MailLabels extends StatelessWidget {
  /// Creates the chips for [labels].
  const MailLabels({
    super.key,
    required this.labels,
    this.size = KaamosChipSize.small,
    this.onRemove,
  });

  /// All the message's labels, system ones included.
  final List<String> labels;

  /// Small in the list, medium in the open message.
  final KaamosChipSize size;

  /// Shows an X on each chip that removes the label. Null = no X (the
  /// list: removing from a row by mistake is too easy).
  final ValueChanged<String>? onRemove;

  /// The labels this widget shows.
  /// Every user label, also the one of the open folder: a message can
  /// have several, and Alessio wants to see (and remove) all of them.
  static List<String> visible(List<String> labels) => userLabels(labels);

  @override
  Widget build(BuildContext context) {
    final shown = visible(labels);
    if (shown.isEmpty) return const SizedBox.shrink();
    final remove = onRemove;
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final l in shown)
          KaamosChip(
            l,
            size: size,
            onRemove: remove == null ? null : () => remove(l),
            removeLabel: 'Togli etichetta $l',
          ),
      ],
    );
    // Without X the chips are read as one sentence; with X every chip and
    // its X must stay reachable.
    if (remove != null) return chips;
    return Semantics(
      label: 'Etichette: ${shown.join(', ')}',
      excludeSemantics: true,
      child: chips,
    );
  }
}

/// Circle with initials.
class MailAvatar extends StatelessWidget {
  /// Creates the avatar for [label].
  const MailAvatar({super.key, required this.label, this.size = 40});

  /// Name or address.
  final String label;

  /// Diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.surfaceCard,
          shape: BoxShape.circle,
          border: Border.all(color: theme.hairline),
        ),
        child: Text(
          initials(label),
          style: KaamosTypography.captionMd.copyWith(color: theme.ink),
        ),
      ),
    );
  }
}

/// Thin horizontal line.
class Hairline extends StatelessWidget {
  /// Creates the line.
  const Hairline({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: KaamosTheme.of(context).hairline);
}

/// Thin vertical line.
class VerticalHairline extends StatelessWidget {
  /// Creates the line.
  const VerticalHairline({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: KaamosTheme.of(context).hairline);
}

/// Information box (e.g. "remote images blocked", errors).
class MailBanner extends StatelessWidget {
  /// Creates the box.
  const MailBanner({
    super.key,
    required this.icon,
    required this.message,
    this.action,
    this.danger = false,
  });

  /// Icon on the left.
  final MailIcon icon;

  /// Text.
  final String message;

  /// Button on the right.
  final Widget? action;

  /// Error colour for the icon.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = KaamosTheme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        decoration: BoxDecoration(
          color: theme.surface,
          border: Border.all(color: theme.hairline),
          borderRadius: const BorderRadius.all(
            Radius.circular(KaamosRadius.md),
          ),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MailIconView(
                  icon,
                  size: 18,
                  color: danger ? theme.danger : theme.accent,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(
                    message,
                    style: KaamosTypography.bodySm.copyWith(color: theme.body),
                  ),
                ),
              ],
            ),
            ?action,
          ],
        ),
      ),
    );
  }
}
