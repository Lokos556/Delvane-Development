import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../app/destination.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../shared/components.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.controller});
  final BusinessController controller;
  @override
  Widget build(BuildContext context) {
    final data = controller.snapshot!;
    final properties = data.properties
        .where((p) => controller.includes(p.id))
        .toList();
    final stays = data.stays
        .where((s) => controller.includes(s.propertyId))
        .toList();
    final arrivals = stays
        .where((s) => s.status == StayStatus.arriving)
        .toList();
    final occupancy =
        properties.fold(0, (n, p) => n + p.occupied) /
        properties.fold(0, (n, p) => n + p.units);
    final tasks = data.tasks
        .where((t) => controller.includes(t.propertyId))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          color: DelvaneColors.ink,
          padding: const EdgeInsets.all(28),
          child: LayoutBuilder(
            builder: (context, c) => Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ui('A CALMER KIND OF HOSPITALITY'),
                        style: TextStyle(
                          color: DelvaneColors.yellow,
                          fontSize: 10,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        ui('Your spaces.\nIn good hands.'),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w600,
                          height: 1.12,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        ui(
                          'A clear view of your stays, your team, and what comes next.',
                        ),
                        style: TextStyle(
                          color: Color(0xFFB5BDB2),
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          controller.filterStatus(StayStatus.arriving);
                          controller.filterSearch('');
                          controller.navigate(Destination.reservations);
                        },
                        icon: const Icon(Icons.arrow_outward_rounded, size: 17),
                        label: Text(ui('View demo arrivals')),
                      ),
                    ],
                  ),
                ),
                if (c.maxWidth > 660)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: SizedBox(
                      width: 160,
                      height: 160,
                      child: CustomPaint(painter: _SunPainter()),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth > 880
                ? 4
                : c.maxWidth > 300
                ? 2
                : 1;
            final width = (c.maxWidth - (columns - 1) * 16) / columns;
            final stats = [
              (
                'Occupancy',
                '${(occupancy * 100).round()}%',
                'Across selected demo units',
                Icons.donut_large_rounded,
              ),
              (
                'Arrivals today',
                '${arrivals.length}',
                'A warm welcome awaits',
                Icons.south_west_rounded,
              ),
              (
                'Departures today',
                '${stays.where((s) => s.status == StayStatus.departing).length}',
                'Make the last impression count',
                Icons.north_east_rounded,
              ),
              (
                'Reservation value',
                money(stays.fold(0, (n, s) => n + s.totalHuf)),
                'Total of displayed demo stays',
                Icons.account_balance_wallet_outlined,
              ),
            ];
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              children: stats
                  .map(
                    (s) => SizedBox(
                      width: width,
                      child: Panel(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.$1,
                                    style: const TextStyle(
                                      color: DelvaneColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Icon(
                                  s.$4,
                                  size: 18,
                                  color: DelvaneColors.muted,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                s.$2,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -1,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              s.$3,
                              style: const TextStyle(
                                color: DelvaneColors.muted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 24),
        AdaptiveColumns(
          primary: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  'The week at a glance',
                  subtitle: 'Illustrative occupancy · 5–11 November 2026',
                  action: const Tag('MOCK'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 160,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (index, value) in [
                        .55,
                        .7,
                        .62,
                        .9,
                        .83,
                        .72,
                        .8,
                      ].indexed)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: FractionallySizedBox(
                                    heightFactor: value,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: index == 6
                                            ? DelvaneColors.yellow
                                            : DelvaneColors.canvas,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  [
                                    'Thu',
                                    'Fri',
                                    'Sat',
                                    'Sun',
                                    'Mon',
                                    'Tue',
                                    'Wed',
                                  ][index],
                                  style: const TextStyle(
                                    color: DelvaneColors.muted,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          secondary: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  'A little heads-up',
                  subtitle: 'Your sample operational briefing',
                  action: const Icon(Icons.auto_awesome_outlined, size: 20),
                ),
                const Tag(
                  '2 PRIORITY ITEMS',
                  color: DelvaneColors.yellowSoft,
                  foreground: DelvaneColors.ink,
                ),
                const SizedBox(height: 16),
                Text(
                  ui('Small details.\nBetter stays.'),
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                    letterSpacing: -.6,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  ui(
                    'An arrival suite needs preparation and a tap needs a quick check. Your demo team has the details.',
                  ),
                  style: TextStyle(color: DelvaneColors.muted, height: 1.7),
                ),
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: () => controller.navigate(Destination.operations),
                  label: Text(ui('Open operations')),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        AdaptiveColumns(
          primary: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  'Arriving today',
                  subtitle: 'Wednesday, 11 November · Demo date',
                  action: TextButton(
                    onPressed: () =>
                        controller.navigate(Destination.reservations),
                    child: Text(ui('View all')),
                  ),
                ),
                StayList(stays: arrivals, snapshot: data),
              ],
            ),
          ),
          secondary: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  'On the team’s list',
                  subtitle: 'Tap a task to update its demo state',
                ),
                for (final task in tasks.take(3))
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: controller.completedTasks.contains(task.id),
                    onChanged: (_) => controller.toggleTask(task.id),
                    title: Text(
                      task.title,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      '${task.assignee} · ${task.due}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: DelvaneColors.muted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SunPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = DelvaneColors.yellow
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * 3.14159265 / 4);
      canvas.drawOval(const Rect.fromLTWH(-16, -74, 32, 104), paint);
      canvas.restore();
    }
    canvas.drawCircle(center, 8, Paint()..color = DelvaneColors.yellow);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
