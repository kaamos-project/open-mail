import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

import '../../core/text_utils.dart';
import 'mail_icons.dart';

/// Bottone quadrato con solo un'icona (36px, 44px su touch).
class MailIconButton extends StatelessWidget {
  /// Crea il bottone. [label] è obbligatorio: è quello che legge lo screen
  /// reader al posto dell'icona.
  const MailIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 36,
    this.filled = false,
    this.iconColor,
  });

  /// L'icona.
  final MailIcon icon;

  /// Nome dell'azione.
  final String label;

  /// Azione; `null` = disabilitato.
  final VoidCallback? onPressed;

  /// Lato del bottone.
  final double size;

  /// Sfondo `surfaceElevated` invece che trasparente.
  final bool filled;

  /// Colore dell'icona, se diverso dal default.
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

/// Cerchio con le iniziali.
class MailAvatar extends StatelessWidget {
  /// Crea l'avatar per [label].
  const MailAvatar({super.key, required this.label, this.size = 40});

  /// Nome o indirizzo.
  final String label;

  /// Diametro.
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

/// Linea sottile orizzontale.
class Hairline extends StatelessWidget {
  /// Crea la linea.
  const Hairline({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: KaamosTheme.of(context).hairline);
}

/// Linea sottile verticale.
class VerticalHairline extends StatelessWidget {
  /// Crea la linea.
  const VerticalHairline({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, color: KaamosTheme.of(context).hairline);
}

/// Riquadro informativo (es. "immagini remote bloccate", errori).
class MailBanner extends StatelessWidget {
  /// Crea il riquadro.
  const MailBanner({
    super.key,
    required this.icon,
    required this.message,
    this.action,
    this.danger = false,
  });

  /// Icona a sinistra.
  final MailIcon icon;

  /// Testo.
  final String message;

  /// Bottone a destra.
  final Widget? action;

  /// Colore di errore per l'icona.
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
