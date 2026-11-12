import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:flutter/material.dart';
import '../workspace/workspace_models.dart';
import 'channel_api.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';

class ChannexMappingDialog extends StatefulWidget {
  const ChannexMappingDialog({super.key, required this.api});
  final ChannelApi api;
  @override
  State<ChannexMappingDialog> createState() => _ChannexMappingDialogState();
}

class _ChannexMappingDialogState extends State<ChannexMappingDialog>
    with PmsActions<ChannexMappingDialog> {
  Json? data;
  String property = '';
  final rooms = <String, String>{}, rates = <String, String>{};
  bool saved = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load([String? selection]) async {
    // Never retain a previous property's inventory after a failed selection read.
    setState(() {
      data = null;
      rooms.clear();
      rates.clear();
    });
    await perform(() async {
      final d = await widget.api.get(
        '/channex/inventory-mapping${selection == null ? '' : '?channex_property_id=${Uri.encodeQueryComponent(selection)}'}',
      );
      if (!mounted) return;
      setState(() {
        data = d;
        property = text(d, 'selected_channex_property_id');
        for (final m in optionalRows(d['room_mappings'])) {
          rooms[text(m, 'room_type_id')] = text(m, 'channex_room_type_id');
        }
        for (final m in optionalRows(d['rate_mappings'])) {
          rates[text(m, 'rate_plan_id')] = text(m, 'channex_rate_plan_id');
        }
      });
    });
  }

  List<Json> get localRooms => optionalRows(
    data?['local_room_types'],
  ).where((r) => enabled(r['active'])).toList();
  List<Json> get localRates => optionalRows(
    data?['local_rate_plans'],
  ).where((r) => enabled(r['active'])).toList();
  Future<void> save() async {
    if (saved || data == null) return;
    if (property.isEmpty ||
        localRooms.any((r) => (rooms[text(r, 'id')] ?? '').isEmpty) ||
        localRates.any((r) => (rates[text(r, 'id')] ?? '').isEmpty)) {
      setState(
        () => failure =
            'Map every active Delvane room type and rate plan before saving.',
      );
      return;
    }
    final ok = await perform(() async {
      await widget.api.change('PUT', '/channex/inventory-mapping', {
        'channex_property_id': property,
        'room_mappings': [
          for (final r in localRooms)
            {'room_type_id': r['id'], 'channex_room_type_id': rooms[r['id']]},
        ],
        'rate_mappings': [
          for (final r in localRates)
            {
              'rate_plan_id': r['id'],
              'channex_room_type_id': rooms[r['room_type_id']],
              'channex_rate_plan_id': rates[r['id']],
            },
        ],
      });
      saved = true;
    });
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Map existing inventory'),
    eyebrow: ui('BOOKING.COM · CHANNEX'),
    canClose: !busy,
    actions: [
      PmsButton(
        ui('Cancel'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(
        ui('Save mapping'),
        primary: true,
        onPressed: busy || data == null || property.isEmpty || saved
            ? null
            : save,
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ui(
            'Delvane will only map existing Channex rooms and rate plans. It will not create anything in Channex.',
          ),
        ),
        errors(),
        if (failure != null)
          PmsButton(
            ui('Retry inventory read'),
            onPressed: busy
                ? null
                : () => load(property.isEmpty ? null : property),
          ),
        if (data != null) ...[
          PmsSelect(
            ui('Channex property'),
            value: property,
            items: {
              '': ui('Choose…'),
              for (final p in optionalRows(data!['properties']))
                text(p, 'id'): text(p, 'title'),
            },
            onChanged: busy
                ? null
                : (v) {
                    property = v;
                    load(v);
                  },
          ),
          Text(
            ui(
              '${optionalRows(data!['remote_room_types']).length} existing room types · ${optionalRows(data!['remote_rate_plans']).length} existing rate plans',
            ),
          ),
          for (final room in localRooms)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PmsEyebrow(ui('ROSA ROOM TYPE')),
                    Text(
                      text(room, 'name'),
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ui(
                        '${room['inventory_count']} units · up to ${room['max_guests']} guests',
                      ),
                    ),
                    PmsSelect(
                      ui('Channex room · ${text(room, 'name')}'),
                      value: rooms[room['id']] ?? '',
                      items: {
                        '': ui('Choose Channex room…'),
                        for (final r in optionalRows(
                          data!['remote_room_types'],
                        ))
                          text(
                            r,
                            'id',
                          ): '${text(r, 'title')} · ${r['count_of_rooms']} units',
                      },
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              rooms[text(room, 'id')] = v;
                              for (final rate in localRates.where(
                                (r) => r['room_type_id'] == room['id'],
                              )) {
                                final available =
                                    optionalRows(data!['remote_rate_plans'])
                                        .where((r) => r['room_type_id'] == v)
                                        .map((r) => r['id']);
                                if (!available.contains(rates[rate['id']])) {
                                  rates.remove(rate['id']);
                                }
                              }
                            }),
                    ),
                    for (final rate in localRates.where(
                      (r) => r['room_type_id'] == room['id'],
                    ))
                      PmsSelect(
                        text(rate, 'name'),
                        value: rates[rate['id']] ?? '',
                        items: {
                          '': ui('Choose Channex rate…'),
                          for (final r
                              in optionalRows(data!['remote_rate_plans']).where(
                                (r) => r['room_type_id'] == rooms[room['id']],
                              ))
                            text(r, 'id'): text(r, 'title'),
                        },
                        onChanged: busy
                            ? null
                            : (v) =>
                                  setState(() => rates[text(rate, 'id')] = v),
                      ),
                    if (!localRates.any((r) => r['room_type_id'] == room['id']))
                      Text(
                        ui('No active rate plans on this Delvane room type.'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ],
    ),
  );
}
