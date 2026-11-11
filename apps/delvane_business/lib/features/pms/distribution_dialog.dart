import 'package:flutter/material.dart';
import '../workspace/workspace_models.dart';
import 'channel_api.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';

/// Form values only: pricing, inventory and restriction rules stay in FastAPI.
class AriInput {
  AriInput(DateTime today) {
    fields['date_from']!.text = isoDate(today.add(const Duration(days: 7)));
    fields['date_to']!.text = isoDate(today.add(const Duration(days: 13)));
  }
  final fields = <String, TextEditingController>{
    for (final k in [
      'date_from',
      'date_to',
      'rate_huf',
      'availability',
      'min_stay_arrival',
      'min_stay_through',
      'max_stay',
    ])
      k: TextEditingController(),
  };
  final flags = <String, String>{
    'stop_sell': '',
    'closed_to_arrival': '',
    'closed_to_departure': '',
  };
  String plan = '', room = '';
  bool force = false;
  Json payload({bool bulk = false}) => {
    'date_from': fields['date_from']!.text,
    'date_to': fields['date_to']!.text,
    'rate_plan_id': plan.isEmpty ? null : plan,
    'rate_huf': channelPrice(fields['rate_huf']!.text),
    for (final k in [
      'min_stay_arrival',
      'min_stay_through',
      'max_stay',
      if (!bulk) 'availability',
    ])
      k: fields[k]!.text.trim().isEmpty ? null : int.parse(fields[k]!.text),
    for (final e in flags.entries)
      e.key: e.value.isEmpty ? null : e.value == 'true',
    if (!bulk) ...{
      'room_type_id': room.isEmpty ? null : room,
      'force_availability': force,
    },
  };
  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
  }
}

class DistributionDialog extends StatefulWidget {
  const DistributionDialog({
    super.key,
    required this.api,
    required this.propertyName,
    this.today,
  });
  final ChannelApi api;
  final String propertyName;
  final DateTime? today;
  @override
  State<DistributionDialog> createState() => _DistributionDialogState();
}

class _DistributionDialogState extends State<DistributionDialog>
    with PmsActions<DistributionDialog> {
  late final single = AriInput(widget.today ?? DateTime.now());
  late final bulk = <AriInput>[AriInput(widget.today ?? DateTime.now())];
  final base = TextEditingController();
  final form = GlobalKey<FormState>();
  Json? data, queue, result;
  List<Json> mappings = [];
  String? queueFailure;
  bool changed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    single.dispose();
    for (final r in bulk) {
      r.dispose();
    }
    base.dispose();
    super.dispose();
  }

  Future<void> load() async {
    await perform(() async {
      final d = await widget.api.get(
        '/channex/ari?date_from=${single.fields['date_from']!.text}&date_to=${single.fields['date_to']!.text}',
      );
      final m = await widget.api.rows('/channex/rate-mappings');
      if (!mounted) return;
      setState(() {
        data = d;
        mappings = m;
        single.force = d['certification_workspace'] == true;
        base.text =
            '${optionalObject(d['base_rate'])['base_nightly_rate_huf'] ?? ''}';
        single.plan = m.isEmpty ? '' : text(m.first, 'rate_plan_id');
        bulk.first.plan = single.plan;
      });
    });
    if (mounted && data != null) await refreshQueue();
  }

  Future<void> refreshQueue() async {
    await perform(() async {
      final q = await widget.api.get('/channex/outbox');
      if (mounted) {
        setState(() {
          queue = q;
          queueFailure = null;
        });
      }
    });
  }

  Future<void> send(String suffix, String method, [Json? body]) async {
    if (changed) return;
    await perform(() async {
      final response = await widget.api.change(
        method,
        '/channex/$suffix',
        body,
      );
      // An accepted save must never be repeated merely because a later read fails.
      changed = true;
      if (mounted) setState(() => result = response);
    });
  }

  Future<void> saveRange({bool batch = false}) async {
    if (!form.currentState!.validate()) return;
    try {
      if (batch) {
        final seen = <String>{};
        final updates = <Json>[];
        for (final row in bulk) {
          if (row.plan.isEmpty || !seen.add(row.plan)) {
            throw const FormatException('Each rate plan can appear only once.');
          }
          updates.add(row.payload(bulk: true));
        }
        if (updates.isEmpty) throw const FormatException('Add a rate plan.');
        await send('ari/batch', 'PUT', {'updates': updates});
      } else {
        await send('ari', 'PUT', single.payload());
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => failure = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (result != null) {
      return DistributionResult(
        result: result!,
        propertyName: widget.propertyName,
      );
    }
    final d = data ?? <String, dynamic>{}, outbox = optionalObject(d['outbox']);
    return PmsModal(
      title: widget.propertyName,
      eyebrow: 'CHANNEL DISTRIBUTION · CHANNEX',
      canClose: !busy,
      actions: [
        PmsButton(
          'Cancel',
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        PmsButton(
          'Save & send',
          primary: true,
          onPressed: busy || data == null || changed ? null : () => saveRange(),
        ),
      ],
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Change a date or range once. Delvane saves it locally and sends one batched update per Channex endpoint.',
            ),
            errors(),
            if (data == null && !busy) PmsButton('Retry', onPressed: load),
            if (data != null) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                runSpacing: 8,
                children: [
                  Text(
                    'OUTGOING QUEUE  ${(outbox['queued'] as num? ?? 0) + (outbox['retry'] as num? ?? 0) + (outbox['sending'] as num? ?? 0)}',
                  ),
                  Text('CONFIGURED DAYS  ${optionalRows(d['values']).length}'),
                  Text('LAST DELIVERED  ${text(d, 'last_sent_at', 'Never')}'),
                ],
              ),
              const SizedBox(height: 24),
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PmsEyebrow('DELIVERY DIAGNOSTICS'),
                    const Text(
                      'Channex delivery queue',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Pending requests, retry timing and last provider error. No credentials or payload data are shown.',
                    ),
                    if (queue == null) const Text('Queue status unavailable.'),
                    if (queue != null && optionalRows(queue!['items']).isEmpty)
                      const Text(
                        'Queue is clear — no pending Channex ARI requests.',
                      ),
                    for (final item in optionalRows(queue?['items']))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${text(item, 'endpoint_label')} · ${text(item, 'status')} · attempt ${item['attempts'] ?? 0}',
                            ),
                            Text(
                              item['retry_due'] == true
                                  ? 'Eligible now'
                                  : 'Retry in ${((item['seconds_until_retry'] as num? ?? 0) / 60).ceil()} min',
                            ),
                            if (item['last_error'] != null)
                              Text(text(item, 'last_error')),
                          ],
                        ),
                      ),
                    if (queueFailure != null) Text(queueFailure!),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        PmsButton(
                          'Refresh queue',
                          onPressed: busy ? null : refreshQueue,
                        ),
                        PmsButton(
                          'Retry pending now',
                          primary: true,
                          onPressed: busy
                              ? null
                              : () => perform(() async {
                                  final out = await widget.api.change(
                                    'POST',
                                    '/channex/outbox/retry',
                                  );
                                  if (mounted) {
                                    setState(() {
                                      queue = optionalObject(out['queue']);
                                      queueFailure =
                                          '${optionalRows(optionalObject(out['delivery'])['delivered']).length} requests delivered · ${optionalRows(optionalObject(out['delivery'])['failed']).length} awaiting retry';
                                    });
                                  }
                                }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const PmsEyebrow('DEFAULT CALENDAR PRICE'),
              const Text(
                'Base nightly price',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
              ),
              const Text(
                'Publish one normal price for the next 365 days. Existing date-specific prices remain overrides.',
              ),
              PmsField(
                '${text(d, 'currency', 'HUF')} per night',
                controller: base,
                keyboard: TextInputType.number,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: PmsButton(
                  d['base_rate'] == null
                      ? 'Set & publish 365 days'
                      : 'Update & republish',
                  primary: true,
                  onPressed: busy
                      ? null
                      : () {
                          final price = int.tryParse(base.text.trim());
                          if (price == null || price <= 0) {
                            setState(
                              () => failure =
                                  'The base-rate endpoint requires a positive whole-unit price.',
                            );
                            return;
                          }
                          send('base-rate', 'PUT', {
                            'base_rate_huf': price,
                            'horizon_days': 365,
                          });
                        },
                ),
              ),
              const SizedBox(height: 24),
              const PmsEyebrow('CHANNEX CERTIFICATION'),
              const Text(
                '500-day full sync',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
              ),
              const Text(
                'Send the complete 500-day availability and rates/restrictions state. Task acceptance is not certification or final OTA confirmation.',
              ),
              Align(
                alignment: Alignment.centerRight,
                child: PmsButton(
                  'Run 500-day full sync',
                  onPressed: busy ? null : () => send('full-sync', 'POST'),
                ),
              ),
              const SizedBox(height: 24),
              const PmsEyebrow('DATE-SPECIFIC OVERRIDES'),
              fields(single),
              const SizedBox(height: 24),
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PmsEyebrow('RATE PLAN UPDATES'),
                    const Text(
                      'Bulk rate & restriction changes',
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'Only changed fields are sent. Keep current leaves that value untouched.',
                    ),
                    for (final row in bulk) ...[
                      const Divider(),
                      fields(row, bulkRow: true),
                      if (bulk.length > 1)
                        Align(
                          alignment: Alignment.centerRight,
                          child: PmsButton(
                            'Remove rate plan',
                            onPressed: busy
                                ? null
                                : () => setState(() {
                                    bulk.remove(row);
                                    row.dispose();
                                  }),
                          ),
                        ),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        PmsButton(
                          '+ Add rate plan',
                          onPressed: busy || mappings.isEmpty
                              ? null
                              : () => setState(
                                  () => bulk.add(
                                    AriInput(widget.today ?? DateTime.now())
                                      ..plan = text(
                                        mappings.first,
                                        'rate_plan_id',
                                      ),
                                  ),
                                ),
                        ),
                        PmsButton(
                          'Save & send bulk updates',
                          primary: true,
                          onPressed: busy || mappings.isEmpty
                              ? null
                              : () => saveRange(batch: true),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Durable delivery: saved changes remain queued for retry if Channex is unavailable. Shared credentials stay on the server.',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget fields(AriInput input, {bool bulkRow = false}) => Column(
    children: [
      PmsColumns([
        PmsDateField('From', controller: input.fields['date_from']!),
        PmsDateField('To', controller: input.fields['date_to']!),
        if (!bulkRow)
          PmsSelect(
            'Room type',
            value: input.room,
            items: {
              '': 'Default room type',
              '__all__': 'All mapped room types',
              for (final r in optionalRows(data?['room_types']))
                text(r, 'id'):
                    '${text(r, 'name')} · ${r['inventory_count']} units',
            },
            onChanged: busy ? null : (v) => setState(() => input.room = v),
          ),
        PmsSelect(
          'Rate plan',
          value: input.plan,
          items: {
            for (final m in mappings)
              text(
                m,
                'rate_plan_id',
              ): '${text(m, 'room_type_name', 'Room type')} · ${text(m, 'rate_plan_name')}',
          },
          onChanged: busy ? null : (v) => setState(() => input.plan = v),
        ),
        PmsField(
          'Nightly price · ${text(data ?? {}, 'currency', 'HUF')}',
          controller: input.fields['rate_huf']!,
          hint: 'Keep current',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
          validator: (v) {
            try {
              channelPrice(v ?? '');
              return null;
            } on FormatException {
              return 'Enter a decimal price.';
            }
          },
        ),
        for (final e in {
          if (!bulkRow) 'availability': 'Availability · available units',
          'min_stay_arrival': 'Min stay · arrival',
          'min_stay_through': 'Min stay · through',
          'max_stay': 'Max stay · 0 = off',
        }.entries)
          PmsField(
            e.value,
            controller: input.fields[e.key]!,
            hint: 'Keep current',
            keyboard: TextInputType.number,
            validator: (v) =>
                (v ?? '').trim().isEmpty || int.tryParse(v!) != null
                ? null
                : 'Enter a whole number.',
          ),
        for (final e in {
          'stop_sell': 'Stop sell',
          'closed_to_arrival': 'Closed to arrival',
          'closed_to_departure': 'Closed to departure',
        }.entries)
          PmsSelect(
            e.value,
            value: input.flags[e.key]!,
            items: const {'': 'Keep current', 'false': 'No', 'true': 'Yes'},
            onChanged: busy
                ? null
                : (v) => setState(() => input.flags[e.key] = v),
          ),
      ], columns: 2),
      if (!bulkRow && data?['certification_workspace'] == true)
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Certification resend · resend even when unchanged',
          ),
          value: input.force,
          onChanged: busy ? null : (v) => setState(() => input.force = v!),
        ),
    ],
  );
}

class DistributionResult extends StatelessWidget {
  const DistributionResult({
    super.key,
    required this.result,
    required this.propertyName,
  });
  final Json result;
  final String propertyName;
  @override
  Widget build(BuildContext context) {
    final delivery = optionalObject(result['delivery']),
        delivered = optionalRows(delivery['delivered']),
        failed = optionalRows(delivery['failed']);
    return PmsModal(
      title: deliveryTitle(result),
      eyebrow: 'CHANNEL DISTRIBUTION',
      width: 650,
      actions: [
        PmsButton(
          'Done',
          primary: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$propertyName · ${result['days'] ?? '—'} days · ${delivered.length} requests submitted · ${failed.length} retrying',
          ),
          Text(text(result, 'message')),
          if (result['queued'] != null)
            Text('${result['queued']} requests saved for delivery.'),
          if (result['no_change'] != true && delivered.isEmpty)
            const Text(
              'Saved in the durable outbox. No provider task ID exists yet.',
            ),
          for (final item in delivered)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(text(item, 'endpoint')),
              subtitle: Text(
                (item['task_ids'] is List ? item['task_ids'] as List : const [])
                    .join(', '),
              ),
            ),
          for (final item in failed) Text(text(item, 'error')),
          const Text(
            'A submitted task is not proof of OTA acceptance or Channex certification.',
          ),
        ],
      ),
    );
  }
}
