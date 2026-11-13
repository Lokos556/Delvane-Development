import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Brand-neutral outlined UI symbols. No platform emoji/font dependency.
class PmsVectorIcon extends StatelessWidget {
  const PmsVectorIcon(
    this.name, {
    super.key,
    this.size = 20,
    this.color = const Color(0xFF171717),
  });
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(painter: _Symbol(name, color)),
        ),
      ),
    ),
  );
}

class _Symbol extends CustomPainter {
  _Symbol(this.name, this.color);
  final String name;
  final Color color;
  @override
  void paint(Canvas c, Size size) {
    final scale = math.min(size.width, size.height) / 24;
    c.translate((size.width - 24 * scale) / 2, (size.height - 24 * scale) / 2);
    c.scale(scale);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double a, double b, double x, double y) =>
        c.drawLine(Offset(a, b), Offset(x, y), p);
    switch (name) {
      case '⚙':
      case 'settings':
        final path = Path();
        for (var i = 0; i < 32; i++) {
          final r = i % 4 == 0 || i % 4 == 3 ? 9.5 : 7.5;
          final a = i * math.pi / 16;
          final x = 12 + r * math.cos(a), y = 12 + r * math.sin(a);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        c.drawPath(path, p);
        c.drawCircle(const Offset(12, 12), 3, p);
      case '↔':
      case 'integrations':
        c.save();
        c.translate(12, 12);
        c.rotate(-math.pi / 4);
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-9, -4, 12, 8),
            const Radius.circular(4),
          ),
          p,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-3, -4, 12, 8),
            const Radius.circular(4),
          ),
          p,
        );
        c.restore();
      case '☰':
      case 'menu':
        line(4, 6, 20, 6);
        line(4, 12, 20, 12);
        line(4, 18, 20, 18);
      case '⌕':
      case 'search':
        c.drawCircle(const Offset(10.5, 10.5), 6, p);
        line(15, 15, 21, 21);
      case '×':
      case 'close':
        line(6, 6, 18, 18);
        line(18, 6, 6, 18);
      case '♙':
      case 'people':
        c.drawCircle(const Offset(9, 7), 3, p);
        c.drawArc(
          const Rect.fromLTWH(3, 12, 12, 12),
          math.pi,
          math.pi,
          false,
          p,
        );
        c.drawArc(
          const Rect.fromLTWH(14, 4, 6, 6),
          -math.pi / 2,
          math.pi,
          false,
          p,
        );
        line(17, 13, 21, 18);
      case '⌾':
      case 'security':
        c.drawPath(
          Path()
            ..moveTo(12, 3)
            ..lineTo(20, 6)
            ..lineTo(19, 14)
            ..quadraticBezierTo(18, 18, 12, 21)
            ..quadraticBezierTo(6, 18, 5, 14)
            ..lineTo(4, 6)
            ..close(),
          p,
        );
        line(8, 12, 11, 15);
        line(11, 15, 16, 9);
      case '▦':
      case 'supplies':
        for (final x in [4.0, 14.0]) {
          for (final y in [4.0, 14.0]) {
            c.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, 6, 6),
                const Radius.circular(1.5),
              ),
              p,
            );
          }
        }
      case '◇':
      case 'maintenance':
        c.drawPath(
          Path()
            ..moveTo(15, 3)
            ..lineTo(12, 7)
            ..lineTo(16, 11)
            ..lineTo(21, 8)
            ..quadraticBezierTo(22, 15, 15, 15)
            ..lineTo(7, 22)
            ..lineTo(3, 18)
            ..lineTo(10, 10)
            ..quadraticBezierTo(8, 3, 15, 3),
          p,
        );
      case '◎':
      case 'mode':
        c.drawCircle(const Offset(12, 12), 8, p);
        c.drawCircle(const Offset(12, 12), 3, p);
      case '↻':
      case 'refresh':
        c.drawArc(const Rect.fromLTWH(5, 5, 14, 14), .4, 5.2, false, p);
        line(19, 4, 19, 10);
        line(19, 10, 14, 9);
      case '➤':
      case 'send':
        c.drawPath(
          Path()
            ..moveTo(3, 3)
            ..lineTo(21, 12)
            ..lineTo(3, 21)
            ..lineTo(6, 12)
            ..close(),
          p,
        );
        line(6, 12, 15, 12);
      case '⌄':
      case 'chevron_down':
        line(6, 9, 12, 15);
        line(12, 15, 18, 9);
      case 'notifications':
        c.drawPath(
          Path()
            ..moveTo(6, 17)
            ..lineTo(6.8, 15)
            ..lineTo(6.8, 10)
            ..cubicTo(6.8, 3.5, 17.2, 3.5, 17.2, 10)
            ..lineTo(17.2, 15)
            ..lineTo(18, 17)
            ..close(),
          p,
        );
        c.drawArc(Rect.fromLTWH(10, 18, 4, 3), 0, math.pi, false, p);
        line(12, 3, 12, 4.5);
      case '›':
      case 'chevron':
        line(9, 6, 15, 12);
        line(15, 12, 9, 18);
      default:
        c.drawCircle(const Offset(12, 12), 7, p);
        line(12, 8, 12, 13);
        c.drawCircle(const Offset(12, 16), .5, p);
    }
  }

  @override
  bool shouldRepaint(covariant _Symbol old) =>
      name != old.name || color != old.color;
}

class PmsMobileBrand extends StatelessWidget {
  const PmsMobileBrand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Image.asset('assets/delvane-icon.png', width: 32, height: 32),
      const SizedBox(width: 8),
      Text(
        'DELVANE',
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: ['Segoe UI', 'Arial', 'sans-serif'],
          fontSize: 19.2,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.728,
          height: 1,
        ),
      ),
    ],
  );
}
