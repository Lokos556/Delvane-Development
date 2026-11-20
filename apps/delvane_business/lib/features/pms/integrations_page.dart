import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'channel_api.dart';
import 'channex_mapping_dialog.dart';
import 'distribution_dialog.dart';
import 'sandbox_dialog.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';
import 'ntak_reporting_dialog.dart';
import 'viza_reporting_dialog.dart';

class IntegrationsPage extends StatelessWidget {
  const IntegrationsPage({super.key, required this.c});
  final PmsController c;
  Future<void> dialog(BuildContext context, Widget child) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => child,
    );
    if (c.auth.user != null) await c.load();
  }

  @override
  Widget build(BuildContext context) {
    if (!c.user.isOperator) return PmsEmpty(ui('No access'));
    final items = c.rows('integrations'), government = c.object('government');
    final booking = items
        .where((i) => text(i, 'provider').toLowerCase().contains('booking'))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsEyebrow(ui('INTEGRATIONS')),
        PmsPageTitle(ui('Channel distribution')),
        Text(
          ui(
            'Base prices and availability stay published automatically, while reservations and date-specific overrides update Channex safely.',
          ),
        ),
        const SizedBox(height: 24),
        PmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PmsEyebrow(ui('CURRENT PHASE')),
              Text(
                ui('Two-way channel control'),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              Text(
                ui(
                  'Changes made in Delvane are saved first, queued durably, batched by date range and retried automatically if Channex is temporarily unavailable.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PmsColumns([
          for (final e in {
            'ACTIVE DISTRIBUTION': booking
                .where((i) => i['distribution_state'] == 'active')
                .length,
            'OUTGOING QUEUE': booking.fold<int>(
              0,
              (n, i) => n + (i['ari_pending_count'] as num? ?? 0).toInt(),
            ),
            'UNACKNOWLEDGED BOOKINGS': booking.fold<int>(
              0,
              (n, i) => n + (i['unacknowledged_count'] as num? ?? 0).toInt(),
            ),
            'STILL DISCONNECTED': booking
                .where((i) => i['connection_stage'] != 'channex_ready')
                .length,
          }.entries)
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PmsEyebrow(ui(e.key)),
                  Text(
                    '${e.value}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ], columns: 4),
        const SizedBox(height: 24),
        PmsEyebrow(ui('BOOKING.COM')),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 8,
          children: [
            Text(
              ui('Booking.com connections'),
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            if (c.user.role == 'owner')
              PmsButton(
                ui('+ Add connection'),
                onPressed: () => dialog(context, IntegrationSlotDialog(c: c)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        PmsColumns([
          for (final item in booking) card(context, item),
        ], columns: 2),
        if (booking.isEmpty) PmsEmpty(ui('No Booking.com connections.')),
        const SizedBox(height: 24),
        PmsEyebrow(ui('OTHER CHANNELS')),
        Text(
          ui('Szallas.hu and test feeds'),
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        PmsColumns([
          for (final item in items.where((i) => !booking.contains(i)))
            card(context, item),
        ], columns: 2),
        const SizedBox(height: 24),
        PmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PmsEyebrow(ui('HUNGARIAN GOVERNMENT REPORTING')),
              for (final property in c.rows('properties'))
                PmsButton(
                  '${ui('NTAK reporting')} · ${text(property, 'name')}',
                  onPressed: () => dialog(
                    context,
                    NtakReportingDialog(
                      c: c,
                      propertyId: text(property, 'id'),
                      propertyName: text(property, 'name'),
                    ),
                  ),
                ),
              for (final property in c.rows('properties'))
                PmsButton(
                  '${ui('VIZA reporting')} · ${text(property, 'name')}',
                  onPressed: () => dialog(
                    context,
                    VizaReportingDialog(
                      c: c,
                      propertyId: text(property, 'id'),
                      propertyName: text(property, 'name'),
                    ),
                  ),
                ),
              Text(
                government['rosa_mtu_certified'] == true
                    ? ui(
                        'Server certification flag is enabled; each property still requires configured transport.',
                      )
                    : ui(
                        'NTAK and VIZA transmission remains locked until MTÜ certifies commercial Delvane. Reservation reports stay queued safely.',
                      ),
              ),
              for (final row in optionalRows(government['queue']))
                Text(
                  '${text(row, 'system')} · ${ui(text(row, 'status'))} · ${row['count']}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        PmsEyebrow(ui('HISTORY')),
        for (final event in c.rows('integrationEvents').take(12))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${text(event, 'property_name')} · ${text(event, 'provider')}',
            ),
            subtitle: Text(
              '${text(event, 'event_type')} · ${uiDateTime(text(event, 'created_at'))}',
            ),
          ),
        if (c.rows('integrationEvents').isEmpty)
          PmsEmpty(ui('No sync history.')),
      ],
    );
  }

  Widget card(BuildContext context, Json i) {
    final booking = text(i, 'provider').toLowerCase().contains('booking'),
        ready = i['connection_stage'] == 'channex_ready';
    final cfg = optionalObject(i['public_config']),
        api = ChannelApi(c, text(i, 'id'));
    return PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PmsEyebrow(text(i, 'property_name')),
          Text(
            text(i, 'provider'),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PmsBadge(
                i['status'] == 'error'
                    ? ui('NEEDS ATTENTION')
                    : !booking
                    ? ui('SANDBOX ONLY')
                    : !ready
                    ? ui('NOT CONNECTED')
                    : i['receiver_state'] == 'active'
                    ? ui('RECEIVER ACTIVE')
                    : ui('SETUP REQUIRED'),
              ),
              PmsBadge(
                cfg['certification_workspace'] == true
                    ? ui('Certification workspace')
                    : text(
                        cfg,
                        'channex_environment',
                        booking ? 'Environment not reported' : 'Sandbox only',
                      ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            !booking
                ? ui('Szallas.hu production access has not been configured.')
                : ready
                ? i['receiver_state'] == 'active'
                      ? ui('Reservation receiver is running')
                      : ui(
                          'Receiver setup incomplete. Shared server credentials are required.',
                        )
                : ui(
                    'Connection not prepared. No Channex room or rate is mapped.',
                  ),
          ),
          const SizedBox(height: 16),
          Text(ui('OUTGOING QUEUE  ${i['ari_pending_count'] ?? 0}')),
          Text(
            ui(
              'LAST DISTRIBUTION UPDATE  ${uiDateTime(text(i, 'last_ari_sent_at', ui('Never')))}',
            ),
          ),
          if (i['status'] == 'error')
            Text(ui('Needs attention. Review the delivery diagnostics.')),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (booking)
                PmsButton(
                  ready
                      ? ui('Manage inventory mapping')
                      : ui('Map Channex inventory'),
                  onPressed: () =>
                      dialog(context, ChannexMappingDialog(api: api)),
                ),
              if (ready) ...[
                PmsButton(
                  ui('Rates & availability'),
                  primary: true,
                  onPressed: () => dialog(
                    context,
                    DistributionDialog(
                      api: api,
                      propertyName: text(i, 'property_name'),
                    ),
                  ),
                ),
                PmsButton(
                  ui('Check bookings'),
                  onPressed: i['receiver_state'] != 'active'
                      ? null
                      : () => dialog(context, ReceiveBookingsDialog(api: api)),
                ),
                PmsButton(
                  ui('Reservations'),
                  onPressed: () => c.navigate(PmsPage.reservations),
                ),
              ] else ...[
                PmsButton(
                  ui('Test feed'),
                  onPressed: () => dialog(context, SandboxDialog(api: api)),
                ),
                PmsButton(
                  ui('Review test data'),
                  onPressed: () => dialog(context, SyncPreviewDialog(api: api)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class IntegrationSlotDialog extends StatefulWidget {
  const IntegrationSlotDialog({super.key, required this.c});
  final PmsController c;
  @override
  State<IntegrationSlotDialog> createState() => _IntegrationSlotDialogState();
}

class _IntegrationSlotDialogState extends State<IntegrationSlotDialog>
    with PmsActions<IntegrationSlotDialog> {
  String property = '', provider = 'Booking.com';
  final type = TextEditingController(text: 'calendar feed / future API');
  @override
  void dispose() {
    type.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Reservation sync sandbox'),
    eyebrow: ui('ADD CONNECTION'),
    width: 600,
    canClose: !busy,
    actions: [
      PmsButton(
        ui('Close'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(
        ui('Save slot'),
        primary: true,
        onPressed: busy || property.isEmpty || widget.c.user.role != 'owner'
            ? null
            : () async {
                final ok = await perform(() async {
                  if (widget.c.user.role != 'owner') {
                    throw StateError('Owner required');
                  }
                  await PmsWorkflows(widget.c)
                      .change('POST', '/api/integrations', {
                        'property_id': property,
                        'provider': provider,
                        'connection_type': type.text,
                      });
                });
                if (ok && context.mounted) Navigator.pop(context, true);
              },
      ),
    ],
    child: Column(
      children: [
        const PmsRequiredNote(),
        errors(),
        PmsSelect(
          ui('Property'),
          required: true,
          value: property,
          items: {
            '': '—',
            for (final p in widget.c.rows('properties'))
              text(p, 'id'): text(p, 'name'),
          },
          onChanged: busy ? null : (v) => setState(() => property = v),
        ),
        PmsSelect(
          ui('Provider'),
          required: true,
          value: provider,
          items: {
            'Booking.com': ui('Booking.com'),
            'Szallas.hu': ui('Szallas.hu'),
            'Other': ui('Other'),
          },
          onChanged: busy ? null : (v) => setState(() => provider = v),
        ),
        PmsField(ui('Connection type'), controller: type),
        Text(
          ui(
            'Local sandbox only. No real OTA URL, password or token is stored.',
          ),
        ),
      ],
    ),
  );
}

class ReceiveBookingsDialog extends StatefulWidget {
  const ReceiveBookingsDialog({super.key, required this.api});
  final ChannelApi api;
  @override
  State<ReceiveBookingsDialog> createState() => _ReceiveBookingsDialogState();
}

class _ReceiveBookingsDialogState extends State<ReceiveBookingsDialog>
    with PmsActions<ReceiveBookingsDialog> {
  Json? result;
  @override
  void initState() {
    super.initState();
    receive();
  }

  Future<void> receive() async {
    await perform(() async {
      final r = await widget.api.change('POST', '/channex/receive');
      if (mounted) setState(() => result = r);
    });
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: result == null
        ? ui('Checking Channex…')
        : ui('${result!['fetched'] ?? 0} revisions checked'),
    eyebrow: ui('CHANNEX RESERVATION RECEIVER'),
    canClose: !busy,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        if (result == null && !busy) PmsButton(ui('Retry'), onPressed: receive),
        if (result != null) ...[
          for (final e in optionalObject(result!['counts']).entries)
            Text('${e.key}: ${e.value}'),
          for (final r in optionalRows(result!['reservations']))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${text(r, 'property_name')} · ${text(r, 'external_ref')}',
              ),
              subtitle: Text(
                r['acknowledged'] == true
                    ? ui('Saved and acknowledged')
                    : ui('Saved; acknowledgement will retry automatically'),
              ),
            ),
          for (final e in optionalRows(result!['errors']))
            Text(text(e, 'error')),
        ],
      ],
    ),
  );
}
