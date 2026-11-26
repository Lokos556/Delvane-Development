import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart' show text;
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

typedef RoomChoice = ({String? unitId, String label});

Future<bool?> reviewUnitAssignment(
  BuildContext context,
  PmsWorkflows api,
  String reservationId,
) async {
  final path = '/api/reservations/${idPath(reservationId)}/allocations';
  final result = await showDialog<RoomChoice>(
    context: context,
    useRootNavigator: false,
    builder: (_) => UnitAssignmentDialog(
      load: () => api.object('$path?include_options=true'),
      submit: (options, unit) async {
        await api.change('PUT', path, {
          'mode': unit == null ? 'automatic' : 'specific',
          if (unit != null) 'unit_id': unit,
          'expected_active_ids': options['expected_active_ids'],
        });
      },
    ),
  );
  return result != null;
}

String roomAssignmentBlocker(String code) => switch (code) {
  'no_configured_unit' =>
    'Set up a physical unit for this room type in Apartments and rooms.',
  'no_eligible_unit' => 'No compatible room is free for the whole stay. Check the dates, capacity and unavailable rooms.',
  'unit_plan_requires_review' => 'Review the planned units in Edit booking for a day-use, split or multi-room stay.',
  'unit_assignment_has_actual_stay' => 'This stay has actual occupancy records. Review the stay before changing rooms.',
  'stay_booking_not_confirmed' =>
    'Confirm the reservation before assigning a physical unit.',
  _ => 'Room selection requires the updated backend.',
};

class UnitAssignmentDialog extends StatefulWidget {
  const UnitAssignmentDialog({super.key, required this.load, this.submit});

  final Future<Json> Function() load;
  final Future<void> Function(Json, String?)? submit;

  @override
  State<UnitAssignmentDialog> createState() => _UnitAssignmentDialogState();
}

class _UnitAssignmentDialogState extends State<UnitAssignmentDialog>
    with PmsActions<UnitAssignmentDialog> {
  Json? data;
  String? selected;
  List<Json> get choices => optionalRows(data?['options']);

  @override
  void initState() {
    super.initState();
    loadOptions();
  }

  Future<void> loadOptions() => perform(() async {
    final options = await widget.load();
    if (!mounted) return;
    setState(() {
      data = options;
      selected = text(
        optionalRows(options['active']).firstOrNull ?? {},
        'unit_id',
      );
    });
  });

  Future<void> confirm(Json? unit) async {
    final submit = widget.submit;
    if (submit != null &&
        !await perform(() => submit(data!, unit?['unit_id'] as String?))) {
      return;
    }
    if (mounted) {
      Navigator.pop<RoomChoice>(context, (
        unitId: unit?['unit_id'] as String?,
        label: unit == null ? ui('Automatic assignment') : text(unit, 'label'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = choices
        .where((unit) => unit['unit_id'] == selected)
        .firstOrNull;
    return PmsModal(
      title: ui('Accommodation unit'),
      width: 520,
      canClose: !busy,
      actions: [
        if (choices.isNotEmpty)
          PmsButton(
            ui('Assign automatically'),
            primary: current == null,
            onPressed: busy ? null : () => confirm(null),
          ),
        if (current != null)
          PmsButton(
            ui('Confirm room'),
            primary: true,
            onPressed: busy ? null : () => confirm(current),
          ),
        if (failure != null)
          PmsButton(ui('Refresh'), onPressed: busy ? null : loadOptions),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          errors(),
          if (data != null && choices.isEmpty)
            Text(ui(roomAssignmentBlocker(text(data!, 'blocker'))))
          else if (choices.isNotEmpty) ...[
            Text(
              ui(
                'Choose an available room for the whole stay or let Delvane assign one.',
              ),
            ),
            const SizedBox(height: 8),
            for (final unit in choices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                selected: unit['unit_id'] == selected,
                leading: Icon(
                  unit['unit_id'] == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(text(unit, 'label')),
                onTap: busy
                    ? null
                    : () => setState(() => selected = text(unit, 'unit_id')),
              ),
          ],
        ],
      ),
    );
  }
}
