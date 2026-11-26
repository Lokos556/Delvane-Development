import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'pms_style.dart';

class SignatureNavigation extends StatelessWidget {
  const SignatureNavigation({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });
  final List<(String, IconData, String)> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: 66 + inset,
      child: TweenAnimationBuilder<double>(
        tween: Tween(
          end: selected < 0 ? (items.length - 1) / 2 : selected.toDouble(),
        ),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 330),
        curve: const Cubic(.20, .82, .24, 1),
        builder: (context, position, _) => CustomPaint(
          painter: _NavigationSurface(position, items.length),
          child: Padding(
            padding: EdgeInsets.only(bottom: inset),
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: Semantics(
                      selected: i == selected,
                      button: true,
                      label: items[i].$1,
                      child: Tooltip(
                        message: items[i].$1,
                        excludeFromSemantics: true,
                        child: InkResponse(
                          key: ValueKey('android-tab-${items[i].$3}'),
                          onTap: () => onSelect(i),
                          highlightShape: BoxShape.rectangle,
                          child: SizedBox.expand(
                            child: Align(
                              alignment: Alignment.center,
                              child: Transform.translate(
                                offset: Offset(
                                  0,
                                  7 -
                                      12 *
                                          (1 - (position - i).abs()).clamp(
                                            0.0,
                                            1.0,
                                          ),
                                ),
                                child: Icon(
                                  items[i].$2,
                                  size: i == selected ? 26 : 23,
                                  color: i == selected
                                      ? PmsStyle.yellow
                                      : const Color(0xffe7e3d9),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavigationSurface extends CustomPainter {
  _NavigationSurface(this.position, this.count);
  final double position;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / count;
    final center = (position + .5) * step;
    final width = math.min(step * .78, 62.0);
    double y(double x) {
      final distance = ((x - center) / width).abs().clamp(0.0, 1.0);
      final shape = 1 - distance * distance;
      return 19 - 13 * shape * shape * shape;
    }

    final edge = Path()..moveTo(0, y(0));
    for (double x = 1; x < size.width; x++) {
      edge.lineTo(x, y(x));
    }
    edge.lineTo(size.width, y(size.width));
    final fill = Path.from(edge)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0xff1c1c19));
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawPath(
      edge,
      Paint()
        ..shader =
            RadialGradient(
              radius: .48,
              colors: [
                PmsStyle.yellow.withValues(alpha: .67),
                const Color(0xff383833),
              ],
            ).createShader(
              Rect.fromCenter(
                center: Offset(center, 12),
                width: width * 3,
                height: width * 3,
              ),
            )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.15,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_NavigationSurface oldDelegate) =>
      oldDelegate.position != position || oldDelegate.count != count;
}
