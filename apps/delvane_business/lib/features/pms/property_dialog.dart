import 'package:flutter/material.dart';
import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'property_rates_dialog.dart';

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
      title: text(p, 'name', 'Property'),
      eyebrow: 'PROPERTY',
      width: 760,
      canClose: !busy,
      actions: [
        PmsButton(
          'Rate plans',
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
        if (failure != null) PmsButton('Retry', onPressed: busy ? null : load),
        PmsButton(
          'Open calendar',
          onPressed: data == null || busy
              ? null
              : () {
                  Navigator.pop(context);
                  widget.openCalendar();
                },
        ),
        if (primary.isNotEmpty)
          PmsButton(
            'Open reservation',
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
                    const PmsEyebrow('SAME-DAY TURNOVER'),
                    PmsColumns([
                      Text(
                        '${text(p, 'checkout_time')}\n${text(optionalObject(d['departing_today']), 'guest_name')} leaves',
                      ),
                      Text(
                        'Cleaning\n${text(p, 'checkout_time')} → ${text(p, 'checkin_time')}',
                      ),
                      Text(
                        '${text(p, 'checkin_time')}\n${text(optionalObject(d['arriving_today']), 'guest_name')} checks in',
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
                Text('Max ${p['max_guests'] ?? 1} guests'),
                Text('Check-in ${text(p, 'checkin_time')}'),
                Text('Checkout ${text(p, 'checkout_time')}'),
              ],
            ),
            const SizedBox(height: 24),
            PmsColumns([
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PmsEyebrow('TODAY'),
                    for (final key in ['departing_today', 'arriving_today'])
                      if (optionalObject(d[key]).isNotEmpty)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            key == 'arriving_today' ? 'Arrival' : 'Departure',
                          ),
                          subtitle: Text(
                            text(optionalObject(d[key]), 'guest_name'),
                          ),
                        ),
                    if (d['departing_today'] == null &&
                        d['arriving_today'] == null)
                      const Text('No changeover today'),
                  ],
                ),
              ),
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PmsEyebrow('CLEANING'),
                    PmsBadge(text(cleaning, 'status', 'No cleaning scheduled')),
                    const SizedBox(height: 12),
                    Text(
                      cleaning.isEmpty
                          ? 'Nothing currently scheduled.'
                          : '${text(cleaning, 'scheduled_date')} · ${text(cleaning, 'earliest_time', 'Flexible')} → ${text(cleaning, 'deadline_time')} · ${text(cleaning, 'assigned_name', 'Unassigned')}',
                    ),
                  ],
                ),
              ),
            ], columns: 2),
            const SizedBox(height: 24),
            PmsEyebrow(
              d['arriving_today'] != null
                  ? 'ARRIVING RESERVATION'
                  : d['current'] != null
                  ? 'CURRENT STAY'
                  : 'NEXT STAY',
            ),
            primary.isEmpty
                ? const PmsEmpty('No upcoming reservation.')
                : ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(text(primary, 'guest_name')),
                    subtitle: Text(
                      '${text(primary, 'arrival_date')} → ${text(primary, 'departure_date')} · ${primary['guest_count'] ?? ''} guests',
                    ),
                  ),
            const SizedBox(height: 24),
            const PmsEyebrow('ROOM TYPES'),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              runSpacing: 8,
              children: [
                const Text(
                  'Sellable room types',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
                PmsButton('+ Add room type', onPressed: busy ? null : addRoom),
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
                        '${room['inventory_count']} units · up to ${room['max_guests']} guests · ${room['active'] == 1 ? 'Active' : 'Inactive'}',
                      ),
                      Text(text(room, 'code')),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            const Text(
              'Rate plans and Channex room mappings belong to a room type.',
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
    title: 'Add room type',
    eyebrow: 'ROOM TYPE',
    width: 650,
    canClose: !busy,
    actions: [
      PmsButton(
        'Cancel',
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(
        'Create room type',
        primary: true,
        onPressed: busy || saved ? null : save,
      ),
    ],
    child: Form(
      key: form,
      child: Column(
        children: [
          errors(),
          PmsColumns([
            PmsField(
              'Name',
              controller: name,
              required: true,
              hint: 'e.g. One-bedroom apartment',
            ),
            PmsField('Code', controller: code, hint: 'e.g. one-bedroom'),
            PmsField(
              'Units',
              controller: units,
              keyboard: TextInputType.number,
              validator: (v) =>
                  int.tryParse(v ?? '') == null ? 'Enter whole units' : null,
            ),
            PmsField(
              'Max guests',
              controller: guests,
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
