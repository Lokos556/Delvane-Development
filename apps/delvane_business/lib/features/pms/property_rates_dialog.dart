import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'channel_api.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

class PropertyRatesDialog extends StatefulWidget {
  const PropertyRatesDialog({
    super.key,
    required this.c,
    required this.propertyId,
  });
  final PmsController c;
  final String propertyId;
  @override
  State<PropertyRatesDialog> createState() => _PropertyRatesDialogState();
}

class _PropertyRatesDialogState extends State<PropertyRatesDialog>
    with PmsActions<PropertyRatesDialog> {
  List<Json>? rooms, plans;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await perform(() async {
      final api = PmsWorkflows(widget.c),
          path = '/api/properties/${idPath(widget.propertyId)}';
      final r = await api.object('$path/room-types'),
          p = await api.object('$path/rate-plans');
      if (mounted) {
        setState(() {
          rooms = optionalRows(r['room_types']);
          plans = optionalRows(p['rate_plans']);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Rate plans'),
    eyebrow: ui('PROPERTY'),
    canClose: !busy,
    actions: [
      PmsButton(
        ui('+ Add rate plan'),
        primary: true,
        onPressed: busy || rooms == null || rooms!.isEmpty
            ? null
            : () async {
                final changed = await showDialog<bool>(
                  context: context,
                  useRootNavigator: false,
                  barrierDismissible: false,
                  builder: (_) => RatePlanEditor(
                    c: widget.c,
                    propertyId: widget.propertyId,
                    rooms: rooms!,
                  ),
                );
                if (changed == true && mounted) await load();
              },
      ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        if (plans == null && !busy) PmsButton(ui('Retry'), onPressed: load),
        if (plans != null) ...[
          for (final plan in plans!)
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    text(plan, 'name'),
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${text(plan, 'room_type_name')} · ${text(plan, 'code')} · ${enabled(plan['active']) ? 'Active' : 'Inactive'}',
                  ),
                  Text(
                    ui(
                      'Base rate ${plan['base_rate_huf'] == null ? ui('Not set') : uiDecimal('${plan['base_rate_huf']}')} HUF · ${text(plan, 'meal_type')} · ${text(plan, 'cancellation_policy')}',
                    ),
                  ),
                  for (final mapping in optionalRows(plan['channex_mappings']))
                    Text(
                      '${text(mapping, 'provider')} · ${text(mapping, 'channex_room_type_id')} · ${text(mapping, 'channex_rate_plan_id')} · ${enabled(mapping['active']) ? 'Active mapping' : 'Inactive mapping'}',
                    ),
                ],
              ),
            ),
          if (plans!.isEmpty) PmsEmpty(ui('No rate plans.')),
          Text(
            ui(
              'Rate-plan creation is supported by the existing API. Editing/deleting existing plans and changing room inventory are not exposed by that API.',
            ),
          ),
        ],
      ],
    ),
  );
}

class RatePlanEditor extends StatefulWidget {
  const RatePlanEditor({
    super.key,
    required this.c,
    required this.propertyId,
    required this.rooms,
  });
  final PmsController c;
  final String propertyId;
  final List<Json> rooms;
  @override
  State<RatePlanEditor> createState() => _RatePlanEditorState();
}

class _RatePlanEditorState extends State<RatePlanEditor>
    with PmsActions<RatePlanEditor> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      code = TextEditingController(),
      meal = TextEditingController(text: 'none'),
      cancellation = TextEditingController(text: 'flexible'),
      rate = TextEditingController();
  late String room = widget.rooms.isEmpty ? '' : text(widget.rooms.first, 'id');
  @override
  void dispose() {
    for (final c in [name, code, meal, cancellation, rate]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Add rate plan'),
    eyebrow: ui('RATE PLAN'),
    width: 650,
    canClose: !busy,
    actions: [
      PmsButton(
        ui('Cancel'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(
        ui('Create rate plan'),
        primary: true,
        onPressed: busy || room.isEmpty
            ? null
            : () async {
                if (!form.currentState!.validate()) return;
                final ok = await perform(() async {
                  await PmsWorkflows(widget.c).change(
                    'POST',
                    '/api/properties/${idPath(widget.propertyId)}/rate-plans',
                    {
                      'room_type_id': room,
                      'name': name.text,
                      'code': code.text,
                      'meal_type': meal.text,
                      'cancellation_policy': cancellation.text,
                      'base_rate_huf': rate.text.trim().isEmpty
                          ? null
                          : int.parse(rate.text.trim()),
                    },
                  );
                });
                if (ok && context.mounted) Navigator.pop(context, true);
              },
      ),
    ],
    child: PmsForm(
      formKey: form,
      child: Column(
        children: [
          errors(),
          PmsColumns([
            PmsSelect(
              ui('Room type'),
              required: true,
              value: room,
              items: {
                for (final r in widget.rooms) text(r, 'id'): text(r, 'name'),
              },
              onChanged: busy ? null : (v) => setState(() => room = v),
            ),
            PmsField(ui('Name'), controller: name, required: true),
            PmsField(ui('Code'), controller: code),
            PmsField(ui('Meal type'), controller: meal),
            PmsField(ui('Cancellation policy'), controller: cancellation),
            PmsField(
              ui('Base rate · HUF'),
              controller: rate,
              keyboard: TextInputType.number,
              validator: (v) =>
                  (v ?? '').trim().isEmpty || int.tryParse(v!) != null
                  ? null
                  : 'Enter whole HUF.',
            ),
          ], columns: 2),
        ],
      ),
    ),
  );
}
