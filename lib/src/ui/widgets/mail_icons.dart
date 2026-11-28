import 'package:flutter/widgets.dart';
import 'package:kaamos_project_ui/kaamos_project_ui.dart';

/// Lucide's `star`, filled: a starred message.
///
/// Every other icon in the app is a Lucide icon from `KaamosIcons`. Lucide
/// draws only outlines and an icon font can't fill a shape, so here we paint
/// the inside of the star and put Lucide's outline on top: same shape, same
/// stroke as the empty star.
class FilledStarIcon extends StatelessWidget {
  /// Creates the icon. Without [semanticLabel] it is decorative.
  const FilledStarIcon({super.key, this.size, this.color, this.semanticLabel});

  /// Side in pixels (defaults to the IconTheme, then 16).
  final double? size;

  /// Colour (defaults to the IconTheme).
  final Color? color;

  /// Label for screen readers; without one the icon is decorative.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final side = size ?? theme.size ?? 16;
    final paint = color ?? theme.color ?? const Color(0xFFFFFFFF);
    return SizedBox.square(
      dimension: side,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _StarFill(paint))),
          KaamosIcon(
            KaamosIcons.star,
            size: side,
            color: paint,
            semanticLabel: semanticLabel,
          ),
        ],
      ),
    );
  }
}

class _StarFill extends CustomPainter {
  const _StarFill(this.color);

  final Color color;

  // Tips and inner corners of Lucide's star on its 24×24 grid. The outline
  // (2px wide) drawn on top covers the small rounding differences.
  static const _points = [
    Offset(12, 2.4),
    Offset(15.6, 7.9),
    Offset(21.6, 9.3),
    Offset(17.6, 14.4),
    Offset(18, 20.6),
    Offset(12, 18.3),
    Offset(6, 20.6),
    Offset(6.4, 14.4),
    Offset(2.4, 9.3),
    Offset(8.4, 7.9),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    canvas.drawPath(Path()..addPolygon(_points, true), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarFill old) => old.color != color;
}
