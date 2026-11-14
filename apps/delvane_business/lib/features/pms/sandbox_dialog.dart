import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'channel_api.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';

class SandboxDialog extends StatefulWidget {
  const SandboxDialog({super.key, required this.api, this.today});
  final ChannelApi api;
  final DateTime? today;
  @override
  State<SandboxDialog> createState() => _SandboxDialogState();
}

class _SandboxDialogState extends State<SandboxDialog>
    with PmsActions<SandboxDialog> {
  Json? data;
  bool stale = false, replace = false;
  final form = GlobalKey<FormState>();
  final guest = TextEditingController(text: 'Sandbox Guest'),
      guests = TextEditingController(text: '2'),
      ref = TextEditingController(),
      ical = TextEditingController();
  late final from = TextEditingController(
        text: isoDate(
          (widget.today ?? DateTime.now()).add(const Duration(days: 35)),
        ),
      ),
      to = TextEditingController(
        text: isoDate(
          (widget.today ?? DateTime.now()).add(const Duration(days: 38)),
        ),
      );
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [guest, guests, ref, ical, from, to]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    await perform(() async {
      final d = await widget.api.get('/feed');
      if (mounted) {
        setState(() {
          data = d;
          stale = false;
        });
      }
    });
  }

  Future<void> mutate(String method, String path, [Json? body]) async {
    if (stale) return;
    final ok = await perform(() async {
      await widget.api.change(method, path, body);
      stale = true;
    });
    if (ok && mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final i = optionalObject(data?['integration']),
        outage = optionalObject(i['public_config'])['sandbox_outage'] == true;
    final locked = busy || stale || data == null;
    return PmsModal(
      title: '${text(i, 'property_name')} · ${text(i, 'provider')}',
      eyebrow: ui('LOCAL SYNC SANDBOX'),
      canClose: !busy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ui(
              'Test feed only. These controls modify the local sandbox, not an OTA feed.',
            ),
          ),
          errors(),
          if (data == null || stale)
            PmsButton(ui('Refresh feed'), onPressed: busy ? null : load),
          if (stale)
            Text(
              ui(
                'The server accepted the change. Refresh the feed before another action.',
              ),
            ),
          if (data != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PmsBadge(
                  outage ? ui('Feed unavailable') : ui('Feed available'),
                ),
                PmsButton(
                  outage ? ui('Recover feed') : ui('Simulate outage'),
                  onPressed: locked
                      ? null
                      : () => mutate(
                          'POST',
                          outage ? '/sandbox/recover' : '/sandbox/outage',
                        ),
                ),
                PmsButton(
                  ui('Sync now'),
                  primary: true,
                  onPressed: locked || outage
                      ? null
                      : () async {
                          await showDialog<void>(
                            context: context,
                            useRootNavigator: false,
                            barrierDismissible: false,
                            builder: (_) => SyncPreviewDialog(api: widget.api),
                          );
                          if (mounted) await load();
                        },
                ),
              ],
            ),
            const SizedBox(height: 20),
            PmsEyebrow(ui('CURRENT FEED')),
            for (final item in optionalRows(data!['items']))
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      text(item, 'guest_name'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ui(
                        '${text(item, 'external_ref')} · ${text(item, 'arrival_date')} → ${text(item, 'departure_date')} · ${item['guest_count']} guests',
                      ),
                    ),
                    PmsBadge(text(item, 'status')),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        PmsButton(
                          ui('Extend one night'),
                          onPressed: locked || item['status'] == 'cancelled'
                              ? null
                              : () => mutate(
                                  'PATCH',
                                  '/sandbox/events/${idPath(text(item, 'external_ref'))}',
                                  {
                                    'departure_date': isoDate(
                                      DateTime.parse(
                                        text(item, 'departure_date'),
                                      ).add(const Duration(days: 1)),
                                    ),
                                    'status': 'active',
                                  },
                                ),
                        ),
                        PmsButton(
                          item['status'] == 'cancelled'
                              ? ui('Restore feed item')
                              : ui('Cancel feed item'),
                          onPressed: locked
                              ? null
                              : () => mutate(
                                  'PATCH',
                                  '/sandbox/events/${idPath(text(item, 'external_ref'))}',
                                  {
                                    'status': item['status'] == 'cancelled'
                                        ? 'active'
                                        : 'cancelled',
                                  },
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            if (optionalRows(data!['items']).isEmpty)
              PmsEmpty(ui('No feed items.')),
            const SizedBox(height: 24),
            PmsEyebrow(ui('TEST SCENARIOS')),
            Text(
              ui('Simulate booking'),
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            PmsForm(
              formKey: form,
              child: Column(
                children: [
                  PmsField(ui('Guest name'), controller: guest, required: true),
                  PmsColumns([
                    PmsDateField(ui('Arrival'), controller: from),
                    PmsDateField(ui('Departure'), controller: to),
                    PmsField(
                      ui('Guest count'),
                      controller: guests,
                      required: true,
                      keyboard: TextInputType.number,
                      validator: (v) => int.tryParse(v ?? '') == null
                          ? 'Enter a whole number.'
                          : null,
                    ),
                    PmsField(
                      ui('External reference'),
                      controller: ref,
                      hint: ui('auto'),
                    ),
                  ], columns: 2),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PmsButton(
                      ui('+ Add to feed'),
                      primary: true,
                      onPressed: locked
                          ? null
                          : () async {
                              if (!form.currentState!.validate()) return;
                              await mutate('POST', '/sandbox/events', {
                                'external_ref': ref.text.trim().isEmpty
                                    ? null
                                    : ref.text.trim(),
                                'guest_name': guest.text,
                                'arrival_date': from.text,
                                'departure_date': to.text,
                                'guest_count': int.parse(guests.text),
                              });
                            },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(ui('iCal sample')),
              children: [
                const PmsRequiredNote(),
                PmsField(
                  ui('iCal text'),
                  controller: ical,
                  required: true,
                  lines: 6,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ui('Replace feed')),
                  value: replace,
                  onChanged: locked
                      ? null
                      : (v) => setState(() => replace = v!),
                ),
                PmsButton(
                  ui('Load iCal'),
                  onPressed: locked
                      ? null
                      : () {
                          if (ical.text.trim().isNotEmpty) {
                            mutate('POST', '/sandbox/ical', {
                              'ical_text': ical.text.trim(),
                              'replace_feed': replace,
                            });
                          }
                        },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class SyncPreviewDialog extends StatefulWidget {
  const SyncPreviewDialog({super.key, required this.api});
  final ChannelApi api;
  @override
  State<SyncPreviewDialog> createState() => _SyncPreviewDialogState();
}

class _SyncPreviewDialogState extends State<SyncPreviewDialog>
    with PmsActions<SyncPreviewDialog> {
  Json? data, result;
  @override
  void initState() {
    super.initState();
    preview();
  }

  Future<void> preview() async {
    await perform(() async {
      final d = await widget.api.change('POST', '/sync/preview');
      if (mounted) setState(() => data = d);
    });
  }

  @override
  Widget build(BuildContext context) {
    final counts = optionalObject(data?['counts']);
    final actionable = [
      'new',
      'changed',
      'cancelled',
    ].fold<num>(0, (n, k) => n + (counts[k] as num? ?? 0));
    return PmsModal(
      title: result == null ? ui('Sync preview') : ui('Import complete'),
      eyebrow: ui('DRY RUN · LOCAL TEST FEED'),
      canClose: !busy,
      actions: [
        PmsButton(
          ui('Close'),
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        if (result == null)
          PmsButton(
            actionable == 0 ? ui('Nothing to import') : ui('Apply import'),
            primary: true,
            onPressed: busy || actionable == 0
                ? null
                : () => perform(() async {
                    final r = await widget.api.change('POST', '/sync/apply');
                    if (mounted) setState(() => result = r);
                  }),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          errors(),
          if (data == null && !busy)
            PmsButton(ui('Retry preview'), onPressed: preview),
          if (result != null)
            Text(
              ui(
                '${optionalObject(result!['counts'])['applied'] ?? 0} applied · ${optionalObject(result!['counts'])['skipped'] ?? 0} skipped',
              ),
            ),
          if (result == null && data != null) ...[
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                for (final e in counts.entries) Text('${e.key}: ${e.value}'),
              ],
            ),
            const SizedBox(height: 16),
            for (final change in optionalRows(data!['changes']))
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PmsBadge(text(change, 'kind')),
                    Text(text(change, 'guest_name')),
                    Text(
                      '${text(change, 'property_name')} · ${text(change, 'arrival_date')} → ${text(change, 'departure_date')}',
                    ),
                    Text(text(change, 'external_ref')),
                  ],
                ),
              ),
            Text(
              ui(
                'Preview does not import reservations. Apply revalidates the current feed and preserves conflicts for review.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
