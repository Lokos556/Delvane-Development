import 'package:material_ui/material_ui.dart';

import '../../core/localization/web_strings.dart';
import 'pms_style.dart';

const operationalGreen = Color(0xff317452);
const operationalBlue = Color(0xff3c6486);
const operationalAmber = Color(0xff966500);
const operationalPlum = Color(0xff765788);
const operationalRed = Color(0xffa2353d);

/// A shared baseline for related figures. At narrow widths the figures remain
/// together in two columns rather than becoming a stack of independent cards.
class MetricRail extends StatelessWidget {
  const MetricRail({super.key, required this.metrics});
  final List<(String, String)> metrics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 570 && metrics.length > 2
          ? metrics.length
          : 2;
      final width = box.maxWidth / columns;
      final numberSize = box.maxWidth >= 570 ? 32.0 : 28.0;
      return DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: PmsStyle.panelLine),
            bottom: BorderSide(color: PmsStyle.panelLine),
          ),
        ),
        child: Wrap(
          children: [
            for (final (label, value) in metrics)
              SizedBox(
                width: width,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: numberSize,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.9,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        style: const TextStyle(
                          color: PmsStyle.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

/// Selectable configuration and diagnostic values with a quiet type hierarchy.
class FactGrid extends StatelessWidget {
  const FactGrid({super.key, required this.facts});
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      const gap = 12.0;
      final columns = box.maxWidth >= 650 && facts.length >= 4 ? 4 : 2;
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final (label, value) in facts)
            SizedBox(
              width: width,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12, color: PmsStyle.muted),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class WorkProgress extends StatelessWidget {
  const WorkProgress({
    super.key,
    required this.completed,
    required this.total,
    this.label,
  });
  final String? label;
  final int completed, total;

  @override
  Widget build(BuildContext context) => total <= 0
      ? const SizedBox.shrink()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 4,
              children: [
                Text(
                  label ?? ui('$completed / $total completed'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (completed == total)
                  const Icon(
                    Icons.check_circle_outline,
                    color: operationalGreen,
                    size: 19,
                  ),
              ],
            ),
            const SizedBox(height: 7),
            LinearProgressIndicator(
              value: (completed / total).clamp(0.0, 1.0),
              semanticsLabel: label ?? ui('$completed / $total completed'),
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              color: completed == total ? operationalGreen : PmsStyle.yellow,
              backgroundColor: PmsStyle.panelLine,
            ),
          ],
        );
}

class ReadinessStrip extends StatelessWidget {
  const ReadinessStrip({super.key, required this.states});
  final List<String> states;

  static (String, Color) mark(String state) => switch (state) {
    'ready' => ('Ready', operationalGreen),
    'occupied' => ('Occupied', operationalBlue),
    'waiting_for_checkout' => ('Waiting for actual checkout', operationalAmber),
    'cleaning' => ('Cleaning pending', operationalPlum),
    _ => ('Room unavailable', PmsStyle.muted),
  };

  @override
  Widget build(BuildContext context) {
    if (states.isEmpty) return const SizedBox.shrink();
    final counts = <(String, Color), int>{};
    for (final state in states) {
      counts.update(mark(state), (n) => n + 1, ifAbsent: () => 1);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                for (final state in states)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: ColoredBox(
                        color: mark(state).$2,
                        child: const SizedBox(height: 8),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 15,
          runSpacing: 4,
          children: [
            for (final entry in counts.entries)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Icon(Icons.circle, size: 8, color: entry.key.$2),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '${entry.value} · ${ui(entry.key.$1)}',
                      style: const TextStyle(
                        color: PmsStyle.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class TimelineEntry extends StatelessWidget {
  const TimelineEntry({
    super.key,
    required this.time,
    required this.title,
    this.detail = '',
    this.color = operationalBlue,
    this.onTap,
    this.action,
    this.timeWidth = 66,
  });
  final String time, title, detail;
  final Color color;
  final double timeWidth;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: timeWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                time,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: color.withValues(alpha: .55),
                    width: 2,
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 5, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: const TextStyle(
                          fontSize: 12,
                          color: PmsStyle.muted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (action != null)
            action!
          else if (onTap != null)
            const Padding(
              padding: EdgeInsets.only(top: 13),
              child: Icon(Icons.chevron_right, size: 18, color: PmsStyle.muted),
            ),
        ],
      ),
    ),
  );
}
