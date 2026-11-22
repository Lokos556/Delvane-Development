import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
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
    final primary = optionalObject(
      d['arriving_today'] ?? d['current'] ?? d['next'],
    );
    return PmsModal(
      title: widget.c.propertyLabel(text(p, 'name', ui('Property'))),
      eyebrow: ui('PROPERTY'),
      width: 760,
      canClose: !busy,
      actions: [
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
            if (d['same_day_turnover'] == true)
              PmsCard(
                color: const Color(0xFFFFF4BD),
                child: Column(
                  children: [
                    PmsEyebrow(ui('SAME-DAY TURNOVER')),
                    PmsColumns([
                      Text(
                        ui(
                          '${text(p, 'checkout_time')}\n${text(optionalObject(d['departing_today']), 'guest_name')} leaves',
                        ),
                      ),
                      Text(
                        ui(
                          'Cleaning\n${text(p, 'checkout_time')} → ${text(p, 'checkin_time')}',
                        ),
                      ),
                      Text(
                        ui(
                          '${text(p, 'checkin_time')}\n${text(optionalObject(d['arriving_today']), 'guest_name')} checks in',
                        ),
                      ),
                    ], columns: 3),
                  ],
                ),
              ),
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
            PmsColumns([
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PmsEyebrow(ui('TODAY')),
                    for (final key in ['departing_today', 'arriving_today'])
                      if (optionalObject(d[key]).isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            key == 'arriving_today'
                                ? ui(
                                    'Arrival · ${text(optionalObject(d[key]), 'arrival_time', text(p, 'checkin_time'))}',
                                  )
                                : ui('Departure · ${text(p, 'checkout_time')}'),
                          ),
                          subtitle: Text(
                            text(optionalObject(d[key]), 'guest_name'),
                          ),
                        ),
                    if (d['departing_today'] == null &&
                        d['arriving_today'] == null)
                      Text(ui('No changeover today')),
                  ],
                ),
              ),
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PmsEyebrow(ui('CLEANING')),
                    PmsBadge(text(cleaning, 'status', 'No cleaning scheduled')),
                    const SizedBox(height: 12),
                    Text(
                      cleaning.isEmpty
                          ? ui('Nothing currently scheduled.')
                          : '${text(cleaning, 'scheduled_date')} · ${text(cleaning, 'earliest_time', ui('Flexible'))} → ${text(cleaning, 'deadline_time')} · ${text(cleaning, 'assigned_name', ui('Unassigned'))}',
                    ),
                  ],
                ),
              ),
            ], columns: 2),
            const SizedBox(height: 24),
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
            PmsEyebrow(ui('ROOM TYPES')),
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
