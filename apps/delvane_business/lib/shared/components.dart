import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../domain/models.dart';

class AdaptiveColumns extends StatelessWidget {
  const AdaptiveColumns({
    super.key,
    required this.primary,
    required this.secondary,
    this.breakpoint = 820,
  });
  final Widget primary, secondary;
  final double breakpoint;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => constraints.maxWidth >= breakpoint
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: primary),
              const SizedBox(width: 22),
              Expanded(flex: 2, child: secondary),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [primary, const SizedBox(height: 22), secondary],
          ),
  );
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(
        color: color == Colors.white ? DelvaneColors.line : color,
      ),
    ),
    child: child,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    subtitle!,
                    style: const TextStyle(
                      color: DelvaneColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (action != null) action!,
      ],
    ),
  );
}

class Tag extends StatelessWidget {
  const Tag(
    this.label, {
    super.key,
    this.color = DelvaneColors.greenSoft,
    this.foreground = DelvaneColors.green,
  });
  final String label;
  final Color color, foreground;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: foreground,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class MockNotice extends StatelessWidget {
  const MockNotice({super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 26),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: DelvaneColors.yellowSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      children: [
        Icon(Icons.science_outlined, size: 17),
        SizedBox(width: 9),
        Expanded(
          child: Text(
            'Demo workspace · Mock data only. Changes stay in memory; no live systems are connected.',
            style: TextStyle(fontSize: 11, height: 1.5),
          ),
        ),
      ],
    ),
  );
}

class Initials extends StatelessWidget {
  const Initials(
    this.name, {
    super.key,
    this.size = 38,
    this.color = DelvaneColors.canvas,
  });
  final String name;
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    backgroundColor: color,
    child: Text(
      name
          .split(' ')
          .where((s) => s.isNotEmpty)
          .take(2)
          .map((s) => s[0])
          .join(),
      style: TextStyle(
        color: DelvaneColors.ink,
        fontSize: size / 3,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.detail, {super.key});
  final String title, detail;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        const Icon(
          Icons.search_off_rounded,
          size: 32,
          color: DelvaneColors.muted,
        ),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: DelvaneColors.muted),
        ),
      ],
    ),
  );
}

void showStayDetails(
  BuildContext context,
  Stay stay,
  BusinessSnapshot snapshot,
) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(stay.guest),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tag(stay.status.label),
            const SizedBox(height: 22),
            Text(
              snapshot.propertyName(stay.propertyId),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              '${shortDate(stay.arrival)} – ${shortDate(stay.departure)} ${stay.departure.year}',
            ),
            Text(
              '${stay.guests} guests · ${stay.departure.difference(stay.arrival).inDays} nights',
            ),
            const Divider(height: 32),
            Text('${stay.channel} · ${stay.id}'),
            const SizedBox(height: 12),
            Text(
              money(stay.totalHuf),
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            const Text(
              'Synthetic reservation · Read-only preview',
              style: TextStyle(color: DelvaneColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class StayList extends StatelessWidget {
  const StayList({super.key, required this.stays, required this.snapshot});
  final List<Stay> stays;
  final BusinessSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    if (stays.isEmpty) {
      return const EmptyState(
        'No matching reservations',
        'Try another name, property, or status.',
      );
    }
    return Column(
      children: [
        for (final stay in stays)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => showStayDetails(context, stay, snapshot),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth > 580;
                  return Row(
                    children: [
                      Initials(stay.guest),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              stay.guest,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              snapshot.propertyName(stay.propertyId),
                              style: const TextStyle(
                                fontSize: 12,
                                color: DelvaneColors.muted,
                              ),
                            ),
                            if (!wide)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  '${shortDate(stay.arrival)} → ${shortDate(stay.departure)}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (wide) ...[
                        SizedBox(
                          width: 140,
                          child: Text(
                            '${shortDate(stay.arrival)} → ${shortDate(stay.departure)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        SizedBox(
                          width: 95,
                          child: Text(
                            money(stay.totalHuf),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      Tag(
                        stay.status.label,
                        color: stay.status == StayStatus.arriving
                            ? DelvaneColors.yellowSoft
                            : DelvaneColors.greenSoft,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
