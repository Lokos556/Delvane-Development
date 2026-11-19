import 'package:material_ui/material_ui.dart';

import 'dart:math';

import 'inventory_controls.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

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
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(ui('Actual occupancy and guest stays')),
    onExpansionChanged: (v) {
      if (v) refresh();
    },
    children: [
      errors(),
      PmsButton(ui('Refresh'), onPressed: busy ? null : refresh),
      for (final r in rows)
        ListTile(
          title: Text('${r['property_name']} · ${r['guest_name']}'),
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
  });
  final PmsWorkflows api;
  final String reservationId;
  @override
  State<ActualStayDialog> createState() => _ActualStayDialogState();
}

class _ActualStayDialogState extends State<ActualStayDialog>
    with PmsActions<ActualStayDialog> {
  Json? data;
  final selected = <String>{};
  Map<String, String> unitLabels = {};
  String get base => '/api/reservations/${widget.reservationId}/actual-stay';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() => perform(() async {
    final value = await widget.api.object(base);
    final detail = await widget.api.detail(widget.reservationId);
    final prop = (detail['reservation'] as Map?)?['property_id'];
    if (prop != null) {
      final units = await widget.api.object(
        '/api/properties/$prop/physical-units?business_date=${DateTime.now().toIso8601String().substring(0, 10)}',
      );
      unitLabels = {
        for (final u in units['units'] as List? ?? [])
          '${u['id']}': '${u['building']} · ${u['unit_number']}',
      };
    }
    if (mounted) setState(() => data = value);
  });
  Future<void> action(String kind) async {
    if (selected.isEmpty) return;
    final requestId = stayRequestId();
    final unitIds = (data?['planned_allocations'] as List? ?? [])
        .map((a) => '${a['unit_id']}')
        .toSet();
    await showDialog(
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
    if (mounted) {
      selected.clear();
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
    await showDialog(
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
    if (mounted) {
      selected.clear();
      await load();
    }
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Actual guest stays'),
    width: 760,
    actions: [
      PmsButton(ui('Refresh'), onPressed: busy ? null : load),
      PmsButton(
        ui('Check in selected guests'),
        onPressed: busy || selected.isEmpty ? null : () => action('arrive'),
      ),
      PmsButton(
        ui('Check out selected guests'),
        onPressed: busy || selected.isEmpty ? null : () => action('depart'),
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
          Text('${ui('Actual occupants')}: ${data!['actual_occupants']}'),
          for (final g in data!['guests'] as List? ?? [])
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
              onChanged: busy
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
      ],
    ),
  );
}
