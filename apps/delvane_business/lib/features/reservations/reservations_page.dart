import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/controller.dart';
import '../../domain/models.dart';
import '../../shared/components.dart';

class ReservationsPage extends StatelessWidget {
  const ReservationsPage({super.key, required this.controller});
  final BusinessController controller;
  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          'Every stay, in one place',
          subtitle:
              'Synthetic reservations · Select a stay to preview its details',
        ),
        TextFormField(
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          key: const ValueKey('reservation-search'),
          initialValue: controller.search,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: ui('Search guest, property, or reference'),
          ),
          onChanged: controller.filterSearch,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(ui('All stays')),
              selected: controller.status == null,
              onSelected: (_) => controller.filterStatus(null),
            ),
            for (final status in StayStatus.values)
              ChoiceChip(
                label: Text(ui(status.label)),
                selected: controller.status == status,
                onSelected: (_) => controller.filterStatus(status),
              ),
          ],
        ),
        const SizedBox(height: 16),
        StayList(
          stays: controller.filteredStays,
          snapshot: controller.snapshot!,
        ),
        const Divider(height: 30),
        Text(
          ui(
            '${controller.filteredStays.length} demo reservations · All amounts in HUF',
          ),
        ),
      ],
    ),
  );
}
