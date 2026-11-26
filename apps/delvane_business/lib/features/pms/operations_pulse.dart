import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:flutter/foundation.dart';

import '../../core/localization/web_strings.dart';
import 'pms_style.dart';

/// Fractions are operational measurements with their actual denominators.
typedef OperationalMetric = (String, int, int, Color);

class OperationsPulse extends StatelessWidget {
  const OperationsPulse({
    super.key,
    required this.metrics,
    required this.urgent,
    required this.onSelect,
  });
  final List<OperationalMetric> metrics;
  final int? urgent;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff201f19),
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
      child: LayoutBuilder(
        builder: (context, box) {
          final graphic = SizedBox.square(
            dimension: box.maxWidth < 560 ? 172 : 210,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _OperationalRings(metrics)),
                ),
                if (urgent != null)
                  TextButton(
                    onPressed: () => onSelect(2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$urgent',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: box.maxWidth < 560 ? 36 : 42,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                        Text(
                          ui('Urgent'),
                          style: const TextStyle(
                            color: PmsStyle.yellow,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
          final legend = Column(
            children: [
              for (var i = 0; i < metrics.length; i++)
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.standard,
                  onTap: () => onSelect(i),
                  leading: Icon(Icons.circle, size: 11, color: metrics[i].$4),
                  title: Text(
                    ui(metrics[i].$1),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: Text(
                    metrics[i].$3 == 0
                        ? '—'
                        : '${metrics[i].$2} / ${metrics[i].$3}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          );
          return box.maxWidth < 560
              ? Column(children: [graphic, const SizedBox(height: 12), legend])
              : Row(
                  children: [
                    graphic,
                    const SizedBox(width: 24),
                    Expanded(child: legend),
                  ],
                );
        },
      ),
    ),
  );
}

class _OperationalRings extends CustomPainter {
  _OperationalRings(this.metrics);
  final List<OperationalMetric> metrics;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < metrics.length; i++) {
      final (_, count, total, color) = metrics[i];
      final radius = size.shortestSide / 2 - 8 - i * 15;
      canvas.drawCircle(center, radius, paint..color = const Color(0xff403d33));
      if (count <= 0 || total <= 0) continue;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        math.pi * 2 * (count / total).clamp(0.0, 1.0),
        false,
        paint..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_OperationalRings oldDelegate) =>
      !listEquals(oldDelegate.metrics, metrics);
}
