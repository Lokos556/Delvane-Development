import 'package:material_ui/material_ui.dart';

import 'dart:math';

import '../workspace/workspace_models.dart' show text;
import 'inventory_controls.dart';
import 'operational_visuals.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';
import 'unit_assignment.dart';

enum StayOperation { checkIn, checkOut }

String stayRequestId() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String actualState(String state) => ui(switch (state) {
  'arrived' => 'Actually arrived',
  'departed' => 'Actually departed',
  _ => 'Expected; not arrived',
});

String stayBlocker(String code) => ui(switch (code) {
  'identity_normalization_unresolved' => 'Guest reporting identity awaits the official normalization policy. The actual event is saved.',
  'missing_guest_reporting_profile' => 'Complete the effective guest residence and tax profile. The actual event is saved.',
  'nationality_country_mapping_required' =>
    'Confirm the nationality country code. The actual event is saved.',
  'reporting_not_enabled' =>
    'Local reporting is not enabled; the actual event is saved.',
  'superseded_before_submission' ||
  'original_not_submitted_no_counter_needed' =>
    'Corrected before submission; no counter-message is required.',
  _ => 'Reporting is blocked; the actual event has been saved.',
});

class ActualOccupancyPanel extends StatefulWidget {
  const ActualOccupancyPanel({super.key, required this.c});
  final PmsController c;
  @override
  State<ActualOccupancyPanel> createState() => _ActualOccupancyPanelState();
}

class _ActualOccupancyPanelState extends State<ActualOccupancyPanel>
    with PmsActions<ActualOccupancyPanel> {
  List<Json> rows = [];
  Future<void> refresh() => perform(() async {
    final data = await PmsWorkflows(widget.c)
        .object('/api/operations/actual-occupancy');
    if (mounted) {
      setState(
        () => rows = (data['reservations'] as List? ?? [])
            .map<Json>((v) => Map<String, dynamic>.from(v))
            .toList(),
      );
    }
  });
  @override
  Widget build(BuildContext context) => PmsExpandablePanel(
    title: ui('Actual occupancy and guest stays'),
    subtitle: ui('Review arrivals, departures and guests currently staying.'),
    icon: Icons.bed_outlined,
    onExpansionChanged: (v) {
      if (v) refresh();
    },
    children: [
      errors(),
      PmsButton(ui('Refresh'), onPressed: busy ? null : refresh),
      for (final r in rows)
        ListTile(
          title: Text(
            '${widget.c.propertyLabel(text(r, 'property_name'))} · ${r['guest_name']}',
          ),
          subtitle: Text(
            '${ui('Actual occupants')}: ${r['actual_occupants']} · ${ui('Expected guests')}: ${r['guest_count']}',
          ),
          onTap: () =>
              showDialog(
                context: context,
                useRootNavigator: false,
                builder: (_) => ActualStayDialog(
                  api: PmsWorkflows(widget.c),
                  reservationId: '${r['id']}',
                ),
              ).then((_) {
                if (mounted) refresh();
              }),
        ),
    ],
  );
}

class ActualStayDialog extends StatefulWidget {
  const ActualStayDialog({
    super.key,
    required this.api,
    required this.reservationId,
    this.operation,
    this.reviewBooking,
    this.reviewGuests,
    this.onChanged,
  });
  final PmsWorkflows api;
  final String reservationId;
  final StayOperation? operation;
  final VoidCallback? reviewBooking, reviewGuests, onChanged;
  @override
  State<ActualStayDialog> createState() => _ActualStayDialogState();
}

class _ActualStayDialogState extends State<ActualStayDialog>
    with PmsActions<ActualStayDialog> {
  Json? data;
  late StayOperation operation = widget.operation ?? StayOperation.checkIn;
  final selected = <String>{};
  Map<String, String> unitLabels = {};
  bool earlierArrival = false;
  bool get checkingIn => operation == StayOperation.checkIn;
  String get base =>
      '/api/reservations/${idPath(widget.reservationId)}/actual-stay';
  List<Json> get plan => optionalRows(data?['planned_allocations']);
  List<Json> get readiness => optionalRows(data?['unit_readiness']);
  List<Json> get guests => optionalRows(data?['guests']);
  bool eligible(Json guest) => checkingIn
      ? guest['actual_state'] != 'arrived'
      : guest['actual_state'] == 'arrived';

  Set<String> arrivalUnits({bool currentOnly = false}) {
    final day = text(data ?? {}, 'business_date');
    return {
      for (final allocation in plan)
        if (!currentOnly ||
            day.isEmpty ||
            (text(allocation, 'date_from').compareTo(day) <= 0 &&
                (text(allocation, 'date_to').compareTo(day) > 0 ||
                    allocation['date_from'] == day &&
                        allocation['date_to'] == day)))
          text(allocation, 'unit_id'),
    };
  }

  String? get blocker {
    if (text(data ?? {}, 'reservation_status', 'confirmed') != 'confirmed') {
      return 'Confirm the reservation before recording an actual stay.';
    }
    if (guests.isEmpty) {
      return 'There are no guest records for this reservation.';
    }
    if (!guests.any(eligible)) {
      return checkingIn
          ? 'All guests are already checked in.'
          : 'No guests are currently checked in.';
    }
    if (!checkingIn) {
      final units = {
        for (final guest in guests)
          if (selected.contains(guest['id']))
            optionalObject(guest['occupancy'])['unit_id'],
      };
      return units.length > 1
          ? 'Select guests occupying the same unit, or perform separate operations.'
          : null;
    }
    if (plan.isEmpty) {
      return 'Assign a planned physical unit before confirming arrival.';
    }
    if (earlierArrival) return null;
    final todayUnits = arrivalUnits(currentOnly: true);
    if (todayUnits.isEmpty) return 'No physical unit is allocated for today.';
    if (data?.containsKey('unit_readiness') == true &&
        !readiness.any(
          (room) =>
              todayUnits.contains(room['unit_id']) &&
              room['state'] != 'unavailable',
        )) {
      return 'The planned units are unavailable today. Review the room allocation.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() => perform(() async {
    final value = await widget.api.object(base);
    final labels = <String, String>{
      for (final room in optionalRows(value['unit_readiness']))
        text(room, 'unit_id'): text(room, 'label'),
    };
    if (!value.containsKey('unit_readiness')) {
      final detail = await widget.api.detail(widget.reservationId);
      final property = text(
        optionalObject(detail['reservation']),
        'property_id',
      );
      if (property.isNotEmpty) {
        final units = await widget.api.object(
          '/api/properties/${idPath(property)}/physical-units?business_date=${isoDate(DateTime.now())}',
        );
        for (final unit in optionalRows(units['units'])) {
          labels[text(unit, 'id')] = [
            text(unit, 'building'),
            text(unit, 'unit_number'),
          ].where((label) => label.isNotEmpty).join(' · ');
        }
      }
    }
    if (mounted) {
      setState(() {
        data = value;
        unitLabels = labels;
        selected.retainAll(
          guests.where(eligible).map((guest) => text(guest, 'id')),
        );
      });
    }
  });
  Future<void> action(String kind) async {
    if (selected.isEmpty || blocker != null) return;
    final requestId = stayRequestId();
    final unitIds = arrivalUnits(currentOnly: !earlierArrival);
    if (!earlierArrival && data?.containsKey('unit_readiness') == true) {
      unitIds.retainAll(
        readiness
            .where((room) => room['state'] != 'unavailable')
            .map((room) => text(room, 'unit_id')),
      );
    }
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => InventoryForm(
        title: kind == 'arrive'
            ? 'Confirm actual arrival'
            : 'Confirm actual departure',
        labels: {
          'occurred_at': 'Actual event time (with timezone)',
          if (kind == 'arrive' && unitIds.length != 1)
            'unit_id': 'Apartment / room',
          'reason': 'Observation or confirmation details',
        },
        initial: {'occurred_at': DateTime.now().toUtc().toIso8601String()},
        selects: {
          'unit_id': {
            for (final id in unitIds) id: unitLabels[id] ?? ui('Planned unit'),
          },
        },
        save: (v) async {
          await widget.api.change('POST', base, {
            'request_id': requestId,
            'kind': kind,
            'guest_ids': selected.toList(),
            'occurred_at': v['occurred_at'],
            'reason': v['reason'],
            if (kind == 'arrive')
              'unit_id': unitIds.length == 1 ? unitIds.single : v['unit_id'],
          });
        },
      ),
    );
    if (changed == true && mounted) {
      selected.clear();
      widget.onChanged?.call();
      await load();
    }
  }

  Future<void> assignRoom() async {
    if (await reviewUnitAssignment(context, widget.api, widget.reservationId) ==
            true &&
        mounted) {
      widget.onChanged?.call();
      await load();
    }
  }

  Future<void> correction(String kind, Map? event) async {
    final ids = event == null
        ? selected.toList()
        : (event['guest_ids'] as List).map((g) => g.toString()).toList();
    if (ids.isEmpty) return;
    final requestId = stayRequestId();
    final title = kind == 'transfer'
        ? 'Confirm actual room transfer'
        : kind == 'correct_timestamp'
        ? 'Correct actual event time'
        : 'Correct an erroneous stay event';
    if (!await pmsConfirm(
      context,
      ui(title),
      ui(
        'This records an audited factual correction or actual move. Planned changes alone do not move guests.',
      ),
    )) {
      return;
    }
    if (!mounted) return;
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (_) => InventoryForm(
        title: title,
        labels: {
          'occurred_at': 'Actual event time (with timezone)',
          if (kind == 'transfer') 'unit_id': 'Destination unit',
          if (kind == 'correct_timestamp')
            'corrected_at': 'Corrected original time (with timezone)',
          'reason': 'Correction or transfer reason',
        },
        initial: {
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          if (kind == 'correct_timestamp')
            'corrected_at': event?['occurred_at'],
        },
        selects: {'unit_id': unitLabels},
        save: (v) async {
          await widget.api.change('POST', base, {
            'request_id': requestId,
            'kind': kind,
            'guest_ids': ids,
            ...v,
            if (event != null) 'correction_of': event['id'],
          });
        },
      ),
    );
    if (changed == true && mounted) {
      selected.clear();
      widget.onChanged?.call();
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Actual guest stays'),
    mobileFullScreen: true,
    width: 760,
    actions: [
      PmsButton(ui('Refresh'), onPressed: busy ? null : load),
      PmsButton(
        ui(
          checkingIn ? 'Check in selected guests' : 'Check out selected guests',
        ),
        primary: true,
        onPressed: busy || selected.isEmpty || blocker != null
            ? null
            : () => action(checkingIn ? 'arrive' : 'depart'),
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        Text(
          ui(
            'Only confirm an observed physical arrival or departure. Registration and planned times do not confirm occupancy.',
          ),
        ),
        if (data != null) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final choice in StayOperation.values)
                ChoiceChip(
                  label: Text(
                    ui(
                      choice == StayOperation.checkIn
                          ? 'Check in'
                          : 'Check out',
                    ),
                  ),
                  selected: choice == operation,
                  onSelected: busy
                      ? null
                      : (_) => setState(() {
                          operation = choice;
                          selected.clear();
                          earlierArrival = false;
                        }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          FactGrid(
            facts: [
              (
                ui('Reservation status'),
                ui(text(data!, 'reservation_status', 'Unknown')),
              ),
              (
                ui('Registration'),
                ui(text(data!, 'registration_status', 'Unknown')),
              ),
              (ui('Actual occupants'), '${data!['actual_occupants']}'),
              if (data!['business_date'] case final String day)
                (ui('Business date'), uiDate(day)),
            ],
          ),
          if (checkingIn && data!.containsKey('unit_readiness')) ...[
            const SizedBox(height: 12),
            Text(
              ui('Room readiness'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            for (final allocation in arrivalUnits(currentOnly: true))
              Text(
                '${unitLabels[allocation] ?? ui('Planned unit')} · ${ui(ReadinessStrip.mark(text(readiness.where((room) => room['unit_id'] == allocation).firstOrNull ?? {}, 'state')).$1)}',
              ),
            if (arrivalUnits(currentOnly: true).isEmpty)
              Text(ui('No physical unit is allocated for today.')),
          ],
          if (blocker case final reason?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                ui(reason),
                style: const TextStyle(color: operationalAmber),
              ),
            )
          else if (selected.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                ui(
                  'Select the guests whose arrival or departure you observed.',
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              if (checkingIn &&
                  plan.isEmpty &&
                  data!['reservation_status'] == 'confirmed' &&
                  data!['stay_type'] == 'overnight')
                PmsButton(
                  ui('Assign a room'),
                  primary: true,
                  onPressed: busy ? null : assignRoom,
                ),
              if (widget.reviewBooking != null && blocker != null)
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          Navigator.pop(context);
                          widget.reviewBooking!();
                        },
                  child: Text(ui('Review booking')),
                ),
              if (widget.reviewGuests != null &&
                  data!['registration_status'] != 'complete')
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          Navigator.pop(context);
                          widget.reviewGuests!();
                        },
                  child: Text(ui('Review guest registration')),
                ),
              if (checkingIn &&
                  plan.isNotEmpty &&
                  data!['business_date'] != null &&
                  !earlierArrival)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => earlierArrival = true),
                  child: Text(ui('Record an earlier arrival')),
                ),
            ],
          ),
          for (final g in guests)
            CheckboxListTile(
              title: Text('${g['full_name']}'),
              subtitle: Text(
                '${actualState('${g['actual_state']}')} · ${ui('Registration')}: ${ui('${g['registration_state'] ?? g['completeness']}')}',
              ),
              secondary: g['occupancy'] == null
                  ? null
                  : Text(
                      unitLabels[g['occupancy']['unit_id']] ??
                          ui('Assigned unit'),
                    ),
              value: selected.contains(g['id']),
              onChanged: busy || !eligible(g)
                  ? null
                  : (v) => setState(() {
                      if (v == true) {
                        selected.add(g['id']);
                      } else {
                        selected.remove(g['id']);
                      }
                    }),
            ),
          const SizedBox(height: 16),
          PmsEyebrow(ui('Actual stay history')),
          for (final e in data!['events'] as List? ?? [])
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${ui('${e['kind']}')} · ${e['occurred_at']}'),
                  Text(
                    '${ui('Business date')}: ${e['business_date']} · ${e['timezone']}',
                  ),
                  Text('${e['reason']}'),
                  if (e['kind'] == 'arrive' || e['kind'] == 'depart')
                    Wrap(
                      spacing: 8,
                      children: [
                        PmsButton(
                          ui(
                            e['kind'] == 'arrive'
                                ? 'Correct erroneous arrival'
                                : 'Correct erroneous departure',
                          ),
                          onPressed: busy
                              ? null
                              : () => correction(
                                  e['kind'] == 'arrive'
                                      ? 'undo_arrival'
                                      : 'undo_departure',
                                  e,
                                ),
                        ),
                        PmsButton(
                          ui('Correct event time'),
                          onPressed: busy
                              ? null
                              : () => correction('correct_timestamp', e),
                        ),
                      ],
                    ),
                  if (e['error_code'] != null)
                    Text(stayBlocker('${e['error_code']}')),
                ],
              ),
            ),
        ],
        if (failure != null)
          PmsButton(ui('Retry'), onPressed: busy ? null : load),
      ],
    ),
  );
}
