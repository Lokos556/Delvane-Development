import 'package:material_ui/material_ui.dart';

import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';

const unitKinds = [
  'ECONOMY',
  'STANDARD',
  'SUPERIOR',
  'JUNIOR_SUITE',
  'SUITE',
  'MOBILHAZ',
  'UDULOHAZ',
  'PARCELLA',
  'SATORHELY_KEMPINGHELY',
  'EGYEDI',
  'PRIVAT_SZOBA_KOZOS_FURDOVEL',
  'PRIVAT_SZOBA_SAJAT_FURDOVEL',
  'HALOTERMI_AGY',
  'APARTMAN',
  'EGYEB',
];

const unitKindNames = {
  "ECONOMY": "Economy room",
  "STANDARD": "Standard room",
  "SUPERIOR": "Superior room",
  "JUNIOR_SUITE": "Junior suite",
  "SUITE": "Suite",
  "MOBILHAZ": "Mobile home",
  "UDULOHAZ": "Holiday house",
  "PARCELLA": "Parcel",
  "SATORHELY_KEMPINGHELY": "Tent site / camping site",
  "EGYEDI": "Special accommodation unit",
  "PRIVAT_SZOBA_KOZOS_FURDOVEL": "Private room with shared bathroom",
  "PRIVAT_SZOBA_SAJAT_FURDOVEL": "Private room with private bathroom",
  "HALOTERMI_AGY": "Dormitory bed",
  "APARTMAN": "Apartment",
  "EGYEB": "Other",
};

/// Explicit domain form shared by inventory and operational period editors.
class InventoryForm extends StatefulWidget {
  const InventoryForm({
    super.key,
    required this.title,
    required this.labels,
    required this.initial,
    required this.save,
    this.selects = const {},
    this.optional = const {},
    this.intro,
  });
  final Widget? intro;
  final String title;
  final Map<String, String> labels;
  final Json initial;
  final Map<String, Map<String, String>> selects;
  final Set<String> optional;
  final Future<void> Function(Json) save;
  @override
  State<InventoryForm> createState() => _InventoryFormState();
}

class _InventoryFormState extends State<InventoryForm>
    with PmsActions<InventoryForm> {
  final form = GlobalKey<FormState>();
  late final fields = {
    for (final key in widget.labels.keys)
      key: TextEditingController(text: '${widget.initial[key] ?? ''}'),
  };
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui(widget.title),
    width: 600,
    canClose: !busy,
    actions: [
      PmsButton(
        ui('Save'),
        primary: true,
        onPressed: busy
            ? null
            : () async {
                if (!form.currentState!.validate()) return;
                final ok = await perform(
                  () => widget.save({
                    for (final e in fields.entries) e.key: e.value.text.trim(),
                  }),
                );
                if (ok && context.mounted) Navigator.pop(context, true);
              },
      ),
    ],
    child: PmsForm(
      formKey: form,
      child: Column(
        children: [
          errors(),
          if (widget.intro != null) widget.intro!,
          for (final e in widget.labels.entries)
            if (widget.selects.containsKey(e.key))
              PmsSelect(
                e.value,
                value: fields[e.key]!.text,
                required: !widget.optional.contains(e.key),
                items: widget.selects[e.key]!,
                onChanged: busy
                    ? null
                    : (v) => setState(() => fields[e.key]!.text = v),
              )
            else
              PmsField(
                e.value,
                controller: fields[e.key]!,
                required: !widget.optional.contains(e.key),
              ),
        ],
      ),
    ),
  );
}

class PhysicalInventory extends StatefulWidget {
  const PhysicalInventory({
    super.key,
    required this.c,
    required this.propertyId,
  });
  final PmsController c;
  final String propertyId;
  @override
  State<PhysicalInventory> createState() => _PhysicalInventoryState();
}

class _PhysicalInventoryState extends State<PhysicalInventory>
    with PmsActions<PhysicalInventory> {
  final day = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  Json data = {};
  List<Json> rooms = [];
  String get base => '/api/properties/${widget.propertyId}/physical-units';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    day.dispose();
    super.dispose();
  }

  Future<void> load() => perform(() async {
    final cap = await widget.c.api.get(
      '$base/capacity?business_date=${Uri.encodeQueryComponent(day.text)}',
    );
    final types = await widget.c.api.get(
      '/api/properties/${widget.propertyId}/room-types',
    );
    final all = await widget.c.api.get(
      '$base?business_date=${Uri.encodeQueryComponent(day.text)}',
    ) as Map;
    if (mounted) {
      setState(() {
        data = Map<String, dynamic>.from(cap as Map);
        final effective = Map<String, dynamic>.fromEntries(
          (data['units'] as List).map((u) => MapEntry('${u['id']}', u)),
        );
        data['units'] = (all['units'] as List)
            .map(
              (u) =>
                  effective['${u['id']}'] ??
                  {
                    ...Map<String, dynamic>.from(u),
                    'regular_places': u['single_beds'] + 2 * u['double_beds'],
                    'operational_state': ui('Inactive'),
                  },
            )
            .toList();
        rooms = (types as Map)['room_types']
            .cast<Map>()
            .map<Json>((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    }
  });
  Future<void> edit([Json? unit]) async {
    await showDialog(
      context: context,
      useRootNavigator: false,
      builder: (_) => InventoryForm(
        title: 'Physical accommodation unit',
        labels: const {
          'effective_from': 'Effective date',
          'building': 'Building',
          'unit_number': 'Apartment / room identifier',
          'room_type_id': 'Room type',
          'classification': 'Accommodation type',
          'single_beds': 'Single beds',
          'double_beds': 'Double beds',
          'extra_beds': 'Extra beds',
          'active': 'Active',
          'reason': 'Reason',
        },
        initial: unit == null
            ? {
                'effective_from': day.text,
                'single_beds': 0,
                'double_beds': 0,
                'extra_beds': 0,
                'active': 'true',
              }
            : {
                ...unit,
                'effective_from': day.text,
                'active': unit['active'] == 1 ? 'true' : 'false',
                'reason': '',
              },
        selects: {
          'room_type_id': {for (final r in rooms) '${r['id']}': '${r['name']}'},
          'classification': {
            for (final k in unitKinds) k: ui(unitKindNames[k] ?? k),
          },
          'active': {'true': ui('Yes'), 'false': ui('No')},
        },
        save: (v) async {
          for (final k in ['single_beds', 'double_beds', 'extra_beds']) {
            v[k] = int.parse(v[k]);
          }
          v['active'] = v['active'] == 'true';
          if (unit == null) {
            await widget.c.api.post(base, v);
          } else {
            await widget.c.api.put('$base/${unit['id']}', v);
          }
        },
      ),
    );
    if (mounted) await load();
  }

  Future<void> periods(Json unit) async {
    await perform(() async {
      final history =
          await widget.c.api.get('$base/${unit['id']}/history') as Map;
      if (!mounted) return;
      await showDialog(
        context: context,
        useRootNavigator: false,
        builder: (ctx) => PmsModal(
          title: ui('Unavailable periods'),
          width: 650,
          actions: [
            if (widget.c.user.role == 'owner')
              PmsButton(
                ui('Add period'),
                onPressed: () async {
                  await showDialog(
                    context: ctx,
                    useRootNavigator: false,
                    builder: (_) => InventoryForm(
                      title: 'Unavailable period',
                      labels: const {
                        'state': 'Operational state',
                        'date_from': 'From date',
                        'date_to': 'Through date',
                        'reason': 'Reason',
                      },
                      initial: {'date_from': day.text, 'date_to': day.text},
                      selects: {
                        'state': {
                          'OOO': ui('OOO — unsuitable for renting'),
                          'OOS': ui('OOS — temporarily unavailable'),
                        },
                      },
                      save: (v) async {
                        await widget.c.api.post(
                          '$base/${unit['id']}/periods',
                          v,
                        );
                      },
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
          ],
          child: Column(
            children: [
              Text(
                ui(
                  'Maintenance periods do not automatically close availability on external channels.',
                ),
              ),
              for (final p in history['periods'] as List)
                ListTile(
                  title: Text(
                    '${p['state']} · ${p['date_from']} – ${p['date_to']}',
                  ),
                  subtitle: Text('${p['reason']}'),
                  trailing: p['cancelled_from'] != null
                      ? Text('${ui('Reopened')}: ${p['cancelled_from']}')
                      : widget.c.user.role != 'owner'
                      ? null
                      : TextButton(
                          onPressed: () async {
                            await showDialog(
                              context: ctx,
                              useRootNavigator: false,
                              builder: (_) => InventoryForm(
                                title: 'Reopen unit',
                                labels: const {
                                  'effective_from': 'Effective date',
                                  'reason': 'Reason',
                                },
                                initial: {'effective_from': day.text},
                                save: (v) async {
                                  await widget.c.api.post(
                                    '$base/${unit['id']}/periods/${p['id']}/cancel',
                                    v,
                                  );
                                },
                              ),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                          child: Text(ui('Reopen unit')),
                        ),
                ),
            ],
          ),
        ),
      );
    });
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Apartments and rooms'),
    width: 800,
    actions: [
      PmsButton(ui('Refresh'), onPressed: busy ? null : load),
      if (widget.c.user.role == 'owner')
        PmsButton(ui('Add unit'), onPressed: busy ? null : () => edit()),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        PmsDateField('Business date', controller: day),
        Text(ui('Planned inventory is separate from actual guest occupancy.')),
        Text(
          ui(
            'Maintenance periods do not automatically close availability on external channels.',
          ),
        ),
        for (final comparison in data['aggregate_comparison'] as List? ?? [])
          if (comparison['matches'] != true)
            Text(
              '${ui('Physical units and channel inventory differ. Review room-type stock.')} ${comparison['physical_unit_count']} / ${comparison['aggregate_inventory_count']}',
            ),
        if ((data['units'] as List? ?? []).isEmpty)
          Text(
            ui(
              'No physical units configured. Enter actual bed counts; existing channel stock is unchanged.',
            ),
          ),
        for (final u in data['units'] as List? ?? [])
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${u['building']} · ${u['unit_number']}'),
                Text(
                  '${ui('Regular places')}: ${u['regular_places']} · ${ui('Extra beds')}: ${u['extra_beds']} · ${ui('${u['operational_state']}')}',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (widget.c.user.role == 'owner')
                      PmsButton(
                        ui('Edit'),
                        onPressed: busy
                            ? null
                            : () => edit(Map<String, dynamic>.from(u)),
                      ),
                    PmsButton(
                      ui('Unavailable periods'),
                      onPressed: busy
                          ? null
                          : () => periods(Map<String, dynamic>.from(u)),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
