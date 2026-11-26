import 'package:material_ui/material_ui.dart';

import 'pms_controller.dart';
import 'pms_workflows.dart';
import 'pms_style.dart';

class BookingReportingState {
  Json reporting = {};
  Json _initialReporting = {};
  Json get changes => {
    for (final entry in reporting.entries)
      if (entry.value != _initialReporting[entry.key]) entry.key: entry.value,
  };
  List<String> missingFields = [];
  List<Json> allocations = [];
  final unitLabels = <String, String>{};
  String? selectedUnit;
  bool allocationsChanged = false;
  final country = TextEditingController(), expected = TextEditingController();
  Future<void> load(PmsWorkflows api, String id) async {
    final result = await api.object('/api/reservations/$id/reporting-details');
    reporting = Map<String, dynamic>.from(result['values'] as Map? ?? {});
    _initialReporting = Map.of(reporting);
    missingFields = (result['missing_fields'] as List? ?? [])
        .map((v) => v.toString())
        .toList();
    country.text = '${reporting['vendegKuldoOrszaga'] ?? ''}';
    expected.text = '${reporting['expected_guest_count'] ?? ''}';
    final a = await api.object('/api/reservations/$id/allocations');
    for (final allocation in optionalRows(a['active'])) {
      if (allocation['label'] case final String label) {
        unitLabels[allocation['unit_id'] as String] = label;
      }
    }
    allocations = (a['active'] as List? ?? [])
        .map<Json>(
          (v) => {
            'unit_id': v['unit_id'],
            'date_from': v['date_from'],
            'date_to': v['date_to'],
          },
        )
        .toList();
  }

  void dispose() {
    country.dispose();
    expected.dispose();
  }
}

class BookingReportingControls extends StatefulWidget {
  const BookingReportingControls({
    super.key,
    required this.state,
    required this.api,
    required this.propertyId,
    required this.roomTypeId,
    required this.stayType,
    required this.editing,
    required this.arrival,
    required this.departure,
  });
  final BookingReportingState state;
  final PmsWorkflows api;
  final String propertyId, roomTypeId, stayType, arrival, departure;
  final bool editing;
  @override
  State<BookingReportingControls> createState() =>
      _BookingReportingControlsState();
}

class _BookingReportingControlsState extends State<BookingReportingControls> {
  List<Json>? units;
  String? failure;
  @override
  void didUpdateWidget(covariant BookingReportingControls old) {
    super.didUpdateWidget(old);
    final s = widget.state;
    if (old.propertyId != widget.propertyId ||
        old.roomTypeId != widget.roomTypeId ||
        old.stayType != widget.stayType) {
      units = null;
      s.allocationsChanged =
          widget.editing && (s.allocations.isNotEmpty || s.allocationsChanged);
      s.allocations = [];
      s.selectedUnit = null;
    } else if (old.arrival != widget.arrival ||
        old.departure != widget.departure) {
      units = null;
      if (s.allocationsChanged) {
        for (final item in s.allocations) {
          if (item['date_from'] == old.arrival &&
              item['date_to'] == old.departure) {
            item['date_from'] = widget.arrival;
            item['date_to'] = widget.departure;
          }
        }
      }
    }
  }

  Future<void> load() async {
    try {
      final result = await widget.api.object(
        '/api/properties/${widget.propertyId}/physical-units/capacity?business_date=${Uri.encodeQueryComponent(widget.arrival)}',
      );
      if (mounted) {
        setState(() {
          units = (result['units'] as List? ?? [])
              .map<Json>((v) => Map<String, dynamic>.from(v))
              .toList();
          failure = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => failure = ui(
            'Unable to load planned units. Check the dates and try again.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return ExpansionTile(
      title: Text(ui('Booking details and planned units')),
      children: [
        if (s.missingFields.isNotEmpty)
          Text(
            '${ui('Incomplete reporting information')}: ${s.missingFields.length}',
          ),
        Text(
          ui(
            'Missing reporting details do not prevent saving a booking. They will need review before reporting.',
          ),
        ),
        PmsSelect(
          'Guaranteed booking',
          value: s.reporting['garantaltFoglalas'] == null
              ? ''
              : s.reporting['garantaltFoglalas'] == true
              ? 'true'
              : 'false',
          items: {
            '': ui('Not specified'),
            'true': ui('Yes'),
            'false': ui('No'),
          },
          onChanged: (v) => setState(
            () => s.reporting['garantaltFoglalas'] = v.isEmpty
                ? null
                : v == 'true',
          ),
        ),
        PmsField(
          'Expected guest count',
          controller: s.expected,
          validator: (v) => v == null || v.trim().isEmpty
              ? null
              : (int.tryParse(v) == null ||
                        int.parse(v) < 1 ||
                        int.parse(v) > 99
                    ? ui('Enter a guest count between 1 and 99.')
                    : null),
          onChanged: (v) {
            s.reporting['expected_guest_count'] = v.trim().isEmpty
                ? null
                : int.tryParse(v);
          },
        ),
        PmsField(
          'Guest sending country (two-letter code)',
          controller: s.country,
          validator: (v) =>
              v == null ||
                  v.trim().isEmpty ||
                  RegExp(r'^[A-Za-z]{2}$').hasMatch(v.trim()) ||
                  v.trim() == 'EGYEBKULFOLDI'
              ? null
              : ui('Enter a two-letter country code.'),
          onChanged: (v) {
            s.reporting['vendegKuldoOrszaga'] = v.trim().isEmpty
                ? null
                : v.trim().toUpperCase();
          },
        ),
        if (s.country.text == 'EGYEBKULFOLDI')
          Text(
            ui(
              'Unknown foreign country reporting is blocked pending the official schema clarification.',
            ),
          ),
        PmsSelect(
          'Sales channel',
          value: s.reporting['ertekesitesiCsatorna'] as String? ?? '',
          items: {
            '': ui('Not specified'),
            for (final e in {
              'DIREKT_ONLINE': 'Direct online',
              'DIREKT_HAGYOMANYOS': 'Direct offline',
              'KOZVETITO_ONLINE': 'Third party online',
              'KOZVETITO_HAGYOMANYOS': 'Third party offline',
            }.entries)
              e.key: ui(e.value),
          },
          onChanged: (v) => setState(
            () => s.reporting['ertekesitesiCsatorna'] = v.isEmpty ? null : v,
          ),
        ),
        PmsSelect(
          'Purpose of stay',
          value: s.reporting['piaciSzegmens'] as String? ?? '',
          items: {
            '': ui('Not specified'),
            for (final e in {
              'SZABADIDOS_EGYENI': 'Leisure, individual',
              'SZABADIDOS_CSOPORTOS': 'Leisure, group',
              'UZLETI_EGYENI': 'Business, individual',
              'UZLETI_CSOPORTOS': 'Business, group',
              'ISMERETLEN': 'Unknown',
            }.entries)
              e.key: ui(e.value),
          },
          onChanged: (v) => setState(
            () => s.reporting['piaciSzegmens'] = v.isEmpty ? null : v,
          ),
        ),
        Text(ui('Planned allocations are not actual guest arrivals.')),
        for (final a in s.allocations)
          Text(
            '${s.unitLabels[a['unit_id']] ?? ui('Planned unit')} · ${a['date_from']} – ${a['date_to']}',
          ),
        PmsButton(ui('Choose planned units'), onPressed: load),
        if (failure != null) Text(failure!),
        for (final u in units ?? <Json>[])
          CheckboxListTile(
            title: Text('${u['building']} · ${u['unit_number']}'),
            subtitle: Text('${u['operational_state']}'),
            value: s.allocations.any((a) => a['unit_id'] == u['id']),
            onChanged: (selected) => setState(() {
              s.allocations.removeWhere((a) => a['unit_id'] == u['id']);
              if (selected == true) {
                s.unitLabels[u['id'] as String] =
                    "${u['building']} · ${u['unit_number']}";
                s.allocations.add({
                  'unit_id': u['id'],
                  'date_from': widget.arrival,
                  'date_to': widget.departure,
                });
              }
              s.allocationsChanged = true;
              s.selectedUnit = null;
            }),
          ),
        PmsButton(
          ui('Leave units unassigned'),
          onPressed: () => setState(() {
            s.allocations = [];
            s.allocationsChanged = true;
            s.selectedUnit = null;
          }),
        ),
      ],
    );
  }
}
