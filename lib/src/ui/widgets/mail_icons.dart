import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Kaamos Mail icons the UI library doesn't have yet.
///
/// Same style as `KaamosIcon` (lines with rounded caps, drawn with CustomPaint,
/// colour from [IconTheme]). When the library gets its icon font, these move
/// there.
enum MailIcon {
  /// Inbox.
  inbox,

  /// Star (outline).
  star,

  /// Filled star.
  starFilled,

  /// Sent.
  send,

  /// Draft / file.
  file,

  /// Archive.
  archive,

  /// Trash.
  trash,

  /// Folder.
  folder,

  /// Spam.
  junk,

  /// Refresh.
  refresh,

  /// Reply.
  reply,

  /// Forward.
  forward,

  /// Paperclip.
  paperclip,

  /// Pencil: compose.
  edit,

  /// Back.
  back,

  /// Shield: privacy.
  shield,

  /// Envelope: unread.
  mail,

  /// Padlock.
  lock,

  /// Label (Gmail).
  tag,

  /// Hamburger: opens the folders drawer.
  menu,

  /// Minus: shrinks a window to its title bar.
  minimize,

  /// Arrows out: makes a window bigger.
  expand,

  /// Arrows in: back to the normal size.
  collapse,

  /// X: closes.
  close,
}

/// Draws a [MailIcon].
class MailIconView extends StatelessWidget {
  /// Creates the icon.
  const MailIconView(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  /// Which icon.
  final MailIcon icon;

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
    final paint = CustomPaint(
      size: Size.square(side),
      painter: _MailIconPainter(
        icon,
        color ?? theme.color ?? const Color(0xFFFFFFFF),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: paint);
    return Semantics(label: semanticLabel, image: true, child: paint);
  }
}

class _MailIconPainter extends CustomPainter {
  _MailIconPainter(this.icon, this.color);

  final MailIcon icon;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // 24×24 grid like the mockup's SVGs, scaled to the requested size.
    final s = size.width / 24;
    canvas.scale(s);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), stroke);
    void poly(List<double> xy, {bool close = false, Paint? paint}) {
      final p = Path()..moveTo(xy[0], xy[1]);
      for (var i = 2; i < xy.length; i += 2) {
        p.lineTo(xy[i], xy[i + 1]);
      }
      if (close) p.close();
      canvas.drawPath(p, paint ?? stroke);
    }

    void rect(double x, double y, double w, double h, double r) =>
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, w, h),
            Radius.circular(r),
          ),
          stroke,
        );
    List<double> starPoints() {
      final pts = <double>[];
      for (var i = 0; i < 10; i++) {
        final r = i.isEven ? 9.0 : 4.0;
        final a = -math.pi / 2 + i * math.pi / 5;
        pts
          ..add(12 + r * math.cos(a))
          ..add(12.5 + r * math.sin(a));
      }
      return pts;
    }

    switch (icon) {
      case MailIcon.inbox:
        poly([2, 12, 8, 12, 10, 15, 14, 15, 16, 12, 22, 12]);
        poly([
          5.5,
          5,
          18.5,
          5,
          22,
          12,
          22,
          18,
          20,
          20,
          4,
          20,
          2,
          18,
          2,
          12,
        ], close: true);
      case MailIcon.star:
        poly(starPoints(), close: true);
      case MailIcon.starFilled:
        poly(starPoints(), close: true, paint: fill);
        poly(starPoints(), close: true);
      case MailIcon.send:
        poly([22, 2, 15, 22, 11, 13, 2, 9], close: true);
        line(22, 2, 11, 13);
      case MailIcon.file:
        poly([
          14,
          3,
          6,
          3,
          4,
          5,
          4,
          19,
          6,
          21,
          18,
          21,
          20,
          19,
          20,
          9,
        ], close: true);
        poly([14, 3, 14, 9, 20, 9]);
      case MailIcon.archive:
        rect(3, 4, 18, 4, 1);
        poly([5, 8, 5, 20, 19, 20, 19, 8]);
        line(10, 12, 14, 12);
      case MailIcon.trash:
        line(3, 6, 21, 6);
        poly([8, 6, 8, 4, 16, 4, 16, 6]);
        poly([6, 6, 7, 20, 17, 20, 18, 6]);
      case MailIcon.folder:
        poly([
          3,
          7,
          5,
          5,
          9,
          5,
          11,
          7,
          19,
          7,
          21,
          9,
          21,
          17,
          19,
          19,
          5,
          19,
          3,
          17,
        ], close: true);
      case MailIcon.junk:
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        line(5.6, 5.6, 18.4, 18.4);
      case MailIcon.refresh:
        canvas.drawArc(
          Rect.fromCircle(center: const Offset(12, 12), radius: 8.5),
          -0.6,
          5.4,
          false,
          stroke,
        );
        poly([20.5, 3.5, 20.5, 8.5, 15.5, 8.5]);
      case MailIcon.reply:
        poly([9, 14, 4, 9, 9, 4]);
        final p = Path()
          ..moveTo(4, 9)
          ..lineTo(15, 9)
          ..arcToPoint(const Offset(20, 14), radius: const Radius.circular(5))
          ..lineTo(20, 20);
        canvas.drawPath(p, stroke);
      case MailIcon.forward:
        poly([15, 14, 20, 9, 15, 4]);
        final p = Path()
          ..moveTo(20, 9)
          ..lineTo(9, 9)
          ..arcToPoint(
            const Offset(4, 14),
            radius: const Radius.circular(5),
            clockwise: false,
          )
          ..lineTo(4, 20);
        canvas.drawPath(p, stroke);
      case MailIcon.paperclip:
        final p = Path()
          ..moveTo(20, 11)
          ..lineTo(12.5, 18.5)
          ..arcToPoint(
            const Offset(5.5, 11.5),
            radius: const Radius.circular(5),
          )
          ..lineTo(13, 4)
          ..arcToPoint(const Offset(18, 9), radius: const Radius.circular(3.5))
          ..lineTo(10.5, 16.5)
          ..arcToPoint(
            const Offset(7.5, 13.5),
            radius: const Radius.circular(2),
          )
          ..lineTo(14.5, 6.5);
        canvas.drawPath(p, stroke);
      case MailIcon.edit:
        line(12, 20, 21, 20);
        poly([16.5, 3.5, 19.5, 6.5, 7, 19, 3, 20, 4, 16], close: true);
      case MailIcon.back:
        poly([15, 5, 8, 12, 15, 19]);
      case MailIcon.shield:
        final p = Path()
          ..moveTo(12, 3)
          ..lineTo(4, 6)
          ..lineTo(4, 12)
          ..quadraticBezierTo(4.5, 19, 12, 21)
          ..quadraticBezierTo(19.5, 19, 20, 12)
          ..lineTo(20, 6)
          ..close();
        canvas.drawPath(p, stroke);
      case MailIcon.mail:
        rect(3, 5, 18, 14, 2);
        poly([3, 7, 12, 13, 21, 7]);
      case MailIcon.lock:
        rect(5, 11, 14, 9, 2);
        final p = Path()
          ..moveTo(8, 11)
          ..lineTo(8, 8)
          ..arcToPoint(const Offset(16, 8), radius: const Radius.circular(4))
          ..lineTo(16, 11);
        canvas.drawPath(p, stroke);
      case MailIcon.tag:
        poly([12, 2.5, 2.5, 2.5, 2.5, 12, 11.5, 21, 21, 11.5], close: true);
        canvas.drawCircle(const Offset(7.5, 7.5), 1.5, fill);
      case MailIcon.menu:
        line(4, 6, 20, 6);
        line(4, 12, 20, 12);
        line(4, 18, 20, 18);
      case MailIcon.minimize:
        line(5, 18, 19, 18);
      case MailIcon.expand:
        poly([14, 4, 20, 4, 20, 10]);
        line(20, 4, 13.5, 10.5);
        poly([10, 20, 4, 20, 4, 14]);
        line(4, 20, 10.5, 13.5);
      case MailIcon.collapse:
        poly([20, 10, 14, 10, 14, 4]);
        line(14, 10, 20.5, 3.5);
        poly([4, 14, 10, 14, 10, 20]);
        line(10, 14, 3.5, 20.5);
      case MailIcon.close:
        line(6, 6, 18, 18);
        line(18, 6, 6, 18);
    }
  }

  @override
  bool shouldRepaint(_MailIconPainter old) =>
      old.icon != icon || old.color != color;
}
