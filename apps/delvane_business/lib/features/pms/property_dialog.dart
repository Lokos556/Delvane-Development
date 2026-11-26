import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'operational_visuals.dart';
import 'pms_style.dart';
import 'property_rates_dialog.dart';
import 'inventory_controls.dart';

class PropertyWorkspace extends StatefulWidget {
  const PropertyWorkspace({
    super.key,
    required this.c,
    required this.id,
    required this.openReservation,
    required this.openCalendar,
  });
  final PmsController c;
  final String id;
  final ValueChanged<String> openReservation;
  final VoidCallback openCalendar;
  @override
  State<PropertyWorkspace> createState() => _PropertyWorkspaceState();
}

class _PropertyWorkspaceState extends State<PropertyWorkspace>
    with PmsActions<PropertyWorkspace> {
  Json? data;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() => perform(() async {
    if (!widget.c.user.isOperator) throw StateError('Operator access required');
    final value = optionalObject(
      await widget.c.api.get('/api/properties/${idPath(widget.id)}/overview'),
    );
    if (mounted) setState(() => data = value);
  });
  Future<void> addRoom() async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => RoomTypeEditor(c: widget.c, propertyId: widget.id),
    );
    if (changed == true && mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final d = data ?? <String, dynamic>{}, p = optionalObject(d['property']);
    final cleaning = optionalObject(d['cleaning']);
    final rooms = optionalRows(d['unit_readiness']);
    final primary = optionalObject(
      d['arriving_today'] ?? d['current'] ?? d['next'],
    );
    return PmsModal(
      mobileFullScreen: true,
      title: widget.c.propertyLabel(text(p, 'name', ui('Property'))),
      eyebrow: ui('PROPERTY'),
      width: 760,
      canClose: !busy,
      actions: [
        if (rooms.isNotEmpty)
          PmsButton(ui('Refresh'), onPressed: busy ? null : load),
        PmsButton(
          ui('Apartments and rooms'),
          onPressed: busy
              ? null
              : () => showDialog(
                  context: context,
                  useRootNavigator: false,
                  builder: (_) =>
                      PhysicalInventory(c: widget.c, propertyId: widget.id),
                ),
        ),
        PmsButton(
          ui('Rate plans'),
          onPressed: busy || data == null
              ? null
              : () => showDialog<void>(
                  context: context,
                  useRootNavigator: false,
                  barrierDismissible: false,
                  builder: (_) =>
                      PropertyRatesDialog(c: widget.c, propertyId: widget.id),
                ),
        ),
        if (failure != null)
          PmsButton(ui('Retry'), onPressed: busy ? null : load),
        PmsButton(
          ui('Open calendar'),
          onPressed: data == null || busy
              ? null
              : () {
                  Navigator.pop(context);
                  widget.openCalendar();
                },
        ),
        if (primary.isNotEmpty)
          PmsButton(
            ui('Open reservation'),
            primary: true,
            onPressed: busy
                ? null
                : () {
                    Navigator.pop(context);
                    widget.openReservation(text(primary, 'id'));
                  },
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          errors(),
          if (data != null) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: [
                Text(text(p, 'address', 'Address not configured')),
                Text(ui('Max ${p['max_guests'] ?? 1} guests')),
                Text(ui('Check-in ${text(p, 'checkin_time')}')),
                Text(ui('Checkout ${text(p, 'checkout_time')}')),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              ui(
                d['same_day_turnover'] == true ? 'Same-day turnover' : 'Today',
              ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (optionalObject(d['departing_today']).isNotEmpty)
              TimelineEntry(
                time: text(p, 'checkout_time'),
                title: ui('Departure'),
                detail: text(
                  optionalObject(d['departing_today']),
                  'guest_name',
                ),
              ),
            TimelineEntry(
              color: operationalAmber,
              time: cleaning.isEmpty && d['same_day_turnover'] != true
                  ? '—'
                  : text(
                      cleaning,
                      'earliest_time',
                      text(p, 'checkout_time', ui('Flexible')),
                    ),
              title: ui('Cleaning'),
              detail: [
                ui(text(cleaning, 'status', 'No cleaning scheduled')),
                if (cleaning.isNotEmpty) ...[
                  uiDate(text(cleaning, 'scheduled_date')),
                  text(cleaning, 'deadline_time'),
                  text(cleaning, 'assigned_name', ui('Unassigned')),
                ],
              ].where((value) => value.isNotEmpty).join(' · '),
            ),
            if (optionalObject(d['arriving_today']).isNotEmpty)
              TimelineEntry(
                time: text(
                  optionalObject(d['arriving_today']),
                  'arrival_time',
                  text(p, 'checkin_time'),
                ),
                title: ui('Arrival'),
                detail: text(optionalObject(d['arriving_today']), 'guest_name'),
              ),
            if (d['departing_today'] == null && d['arriving_today'] == null)
              PmsEmpty(ui('No changeover today')),
            const SizedBox(height: 24),
            if (rooms.isNotEmpty) ...[
              Text(
                ui('Room readiness'),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              ReadinessStrip(
                states: [for (final room in rooms) text(room, 'state')],
              ),
              const SizedBox(height: 8),
              for (final room in rooms)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    text(room, 'label'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    ui(ReadinessStrip.mark(text(room, 'state')).$1),
                    style: TextStyle(
                      color: ReadinessStrip.mark(text(room, 'state')).$2,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
            PmsEyebrow(
              d['arriving_today'] != null
                  ? ui('ARRIVING RESERVATION')
                  : d['current'] != null
                  ? ui('CURRENT STAY')
                  : ui('NEXT STAY'),
            ),
            primary.isEmpty
                ? PmsEmpty(ui('No upcoming reservation.'))
                : PmsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PmsEyebrow(
                          '${ui(text(primary, 'source'))} · ${text(primary, 'external_ref')}',
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(text(primary, 'guest_name')),
                          subtitle: Text(
                            ui(
                              '${text(primary, 'arrival_date')} → ${text(primary, 'departure_date')} · ${primary['guest_count'] ?? ''} guests',
                            ),
                          ),
                        ),
                        PmsBadge(
                          text(primary, 'registration_status') == 'complete'
                              ? ui('Registration complete')
                              : ui('Registration incomplete'),
                          tone:
                              text(primary, 'registration_status') == 'complete'
                              ? 'ready'
                              : 'attention',
                        ),
                      ],
                    ),
                  ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              children: [
                Text(
                  ui('Sellable room types'),
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
                PmsButton(
                  ui('+ Add room type'),
                  onPressed: busy ? null : addRoom,
                ),
              ],
            ),
            for (final room in optionalRows(d['room_types']))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: PmsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text(room, 'name'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        ui(
                          '${room['inventory_count']} units · up to ${room['max_guests']} guests · ${ui(room['active'] == 1 ? 'Active' : 'Inactive')}',
                        ),
                      ),
                      Text(text(room, 'code')),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text(
              ui('Rate plans and Channex room mappings belong to a room type.'),
            ),
          ],
        ],
      ),
    );
  }
}

class RoomTypeEditor extends StatefulWidget {
  const RoomTypeEditor({super.key, required this.c, required this.propertyId});
  final PmsController c;
  final String propertyId;
  @override
  State<RoomTypeEditor> createState() => _RoomTypeEditorState();
}

class _RoomTypeEditorState extends State<RoomTypeEditor>
    with PmsActions<RoomTypeEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      code = TextEditingController(),
      units = TextEditingController(text: '1'),
      guests = TextEditingController(text: '2');
  bool saved = false;
  @override
  void dispose() {
    for (final c in [name, code, units, guests]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saved || !form.currentState!.validate()) return;
    final ok = await perform(() async {
      if (!widget.c.user.isOperator) {
        throw StateError('Operator access required');
      }
      await widget.c.mutate(
        'POST',
        '/api/properties/${idPath(widget.propertyId)}/room-types',
        {
          'name': name.text,
          'code': code.text,
          'inventory_count': int.parse(units.text),
          'max_guests': int.parse(guests.text),
        },
      );
      saved = true;
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Add room type'),
    eyebrow: ui('ROOM TYPE'),
    width: 650,
    canClose: !busy,
    actions: [
      PmsButton(
        ui('Cancel'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(
        ui('Create room type'),
        primary: true,
        onPressed: busy || saved ? null : save,
      ),
    ],
    child: PmsForm(
      formKey: form,
      child: Column(
        children: [
          errors(),
          PmsColumns([
            PmsField(
              ui('Name'),
              controller: name,
              required: true,
              hint: ui('e.g. One-bedroom apartment'),
            ),
            PmsField(
              ui('Code'),
              controller: code,
              hint: ui('e.g. one-bedroom'),
            ),
            PmsField(
              ui('Units'),
              controller: units,
              required: true,
              keyboard: TextInputType.number,
              validator: (v) =>
                  int.tryParse(v ?? '') == null ? 'Enter whole units' : null,
            ),
            PmsField(
              ui('Max guests'),
              controller: guests,
              required: true,
              keyboard: TextInputType.number,
              validator: (v) =>
                  int.tryParse(v ?? '') == null ? 'Enter whole guests' : null,
            ),
          ], columns: 2),
        ],
      ),
    ),
  );
}
