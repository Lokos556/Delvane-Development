import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/components.dart';

class PropertiesPage extends StatelessWidget {
  const PropertiesPage({super.key, required this.controller});
  final BusinessController controller;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 1000
          ? 3
          : c.maxWidth >= 600
          ? 2
          : 1;
      final width = (c.maxWidth - 20 * (columns - 1)) / columns;
      return Wrap(
        spacing: 20,
        runSpacing: 20,
        children: controller.snapshot!.properties
            .where((p) => controller.includes(p.id))
            .map(
              (p) => SizedBox(
                width: width,
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 130,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: p.id == 'olive'
                              ? DelvaneColors.yellowSoft
                              : DelvaneColors.canvas,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          p.id == 'atelier'
                              ? Icons.holiday_village_outlined
                              : Icons.apartment_rounded,
                          size: 66,
                          color: DelvaneColors.ink,
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        p.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        p.location,
                        style: const TextStyle(
                          color: DelvaneColors.muted,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Tag(
                        p.ready ? 'Ready for guests' : 'Needs attention',
                        color: p.ready
                            ? DelvaneColors.greenSoft
                            : DelvaneColors.yellowSoft,
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              ui('${p.occupied} of ${p.units} units occupied'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(p.occupied / p.units * 100).round()}%',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: p.occupied / p.units,
                          minHeight: 6,
                          color: DelvaneColors.yellow,
                          backgroundColor: DelvaneColors.canvas,
                        ),
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(p.name),
                            content: Text(
                              ui(
                                '${p.location}\n${p.units} demo units\n${p.occupied} occupied\n\nIllustrative property only. No channel manager, locks, or live inventory connected.',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(ui('Close')),
                              ),
                            ],
                          ),
                        ),
                        icon: const Icon(Icons.arrow_outward_rounded, size: 16),
                        label: Text(ui('Property overview')),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );
}
