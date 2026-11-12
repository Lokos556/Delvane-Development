import 'package:flutter/material.dart';
import '../workspace/workspace_models.dart';
import 'channel_api.dart';
import 'channex_mapping_dialog.dart';
import 'distribution_dialog.dart';
import 'sandbox_dialog.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

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
    if (!c.user.isOperator) return const PmsEmpty('No access');
    final items = c.rows('integrations'), government = c.object('government');
    final booking = items
        .where((i) => text(i, 'provider').toLowerCase().contains('booking'))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PmsEyebrow('INTEGRATIONS'),
        const PmsPageTitle('Channel distribution'),
        const Text(
          'Base prices and availability stay published automatically, while reservations and date-specific overrides update Channex safely.',
        ),
        const SizedBox(height: 24),
        const PmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PmsEyebrow('CURRENT PHASE'),
              Text(
                'Two-way channel control',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              Text(
                'Changes made in Delvane are saved first, queued durably, batched by date range and retried automatically if Channex is temporarily unavailable.',
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
                  PmsEyebrow(e.key),
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
        const PmsEyebrow('BOOKING.COM'),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 8,
          children: [
            const Text(
              'Booking.com connections',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
            ),
            if (c.user.role == 'owner')
              PmsButton(
                '+ Add connection',
                onPressed: () => dialog(context, IntegrationSlotDialog(c: c)),
              ),
          ],
        ),
        const SizedBox(height: 16),
        PmsColumns([
          for (final item in booking) card(context, item),
        ], columns: 2),
        if (booking.isEmpty) const PmsEmpty('No Booking.com connections.'),
        const SizedBox(height: 24),
        const PmsEyebrow('OTHER CHANNELS'),
        const Text(
          'Szallas.hu and test feeds',
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
              const PmsEyebrow('HUNGARIAN GOVERNMENT REPORTING'),
              Text(
                government['rosa_mtu_certified'] == true
                    ? 'Server certification flag is enabled; each property still requires configured transport.'
                    : 'NTAK and VIZA transmission remains locked until MTÜ certifies commercial Delvane. Reservation reports stay queued safely.',
              ),
              for (final row in optionalRows(government['queue']))
                Text(
                  '${text(row, 'system')} · ${text(row, 'status')} · ${row['count']}',
                ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const PmsEyebrow('HISTORY'),
        for (final event in c.rows('integrationEvents').take(12))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              '${text(event, 'property_name')} · ${text(event, 'provider')}',
            ),
            subtitle: Text(
              '${text(event, 'event_type')} · ${text(event, 'created_at')}',
            ),
          ),
        if (c.rows('integrationEvents').isEmpty)
          const PmsEmpty('No sync history.'),
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
                    ? 'NEEDS ATTENTION'
                    : !booking
                    ? 'SANDBOX ONLY'
                    : !ready
                    ? 'NOT CONNECTED'
                    : i['receiver_state'] == 'active'
                    ? 'RECEIVER ACTIVE'
                    : 'SETUP REQUIRED',
              ),
              PmsBadge(
                cfg['certification_workspace'] == true
                    ? 'Certification workspace'
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
                ? 'Szallas.hu production access has not been configured.'
                : ready
                ? i['receiver_state'] == 'active'
                      ? 'Reservation receiver is running'
                      : 'Receiver setup incomplete. Shared server credentials are required.'
                : 'Connection not prepared. No Channex room or rate is mapped.',
          ),
          const SizedBox(height: 16),
          Text('OUTGOING QUEUE  ${i['ari_pending_count'] ?? 0}'),
          Text(
            'LAST DISTRIBUTION UPDATE  ${text(i, 'last_ari_sent_at', 'Never')}',
          ),
          if (i['status'] == 'error')
            const Text('Needs attention. Review the delivery diagnostics.'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (booking)
                PmsButton(
                  ready ? 'Manage inventory mapping' : 'Map Channex inventory',
                  onPressed: () =>
                      dialog(context, ChannexMappingDialog(api: api)),
                ),
              if (ready) ...[
                PmsButton(
                  'Rates & availability',
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
                  'Check bookings',
                  onPressed: i['receiver_state'] != 'active'
                      ? null
                      : () => dialog(context, ReceiveBookingsDialog(api: api)),
                ),
                PmsButton(
                  'Reservations',
                  onPressed: () => c.navigate(PmsPage.reservations),
                ),
              ] else ...[
                PmsButton(
                  'Test feed',
                  onPressed: () => dialog(context, SandboxDialog(api: api)),
                ),
                PmsButton(
                  'Review test data',
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
    title: 'Reservation sync sandbox',
    eyebrow: 'ADD CONNECTION',
    width: 600,
    canClose: !busy,
    actions: [
      PmsButton('Close', onPressed: busy ? null : () => Navigator.pop(context)),
      PmsButton(
        'Save slot',
        primary: true,
        onPressed: busy || property.isEmpty || widget.c.user.role != 'owner'
            ? null
            : () async {
                final ok = await perform(() async {
                  if (widget.c.user.role != 'owner') {
                    throw StateError('Owner required');
                  }
                  await PmsWorkflows(
                    widget.c,
                  ).change('POST', '/api/integrations', {
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
        errors(),
        PmsSelect(
          'Property',
          value: property,
          items: {
            '': '—',
            for (final p in widget.c.rows('properties'))
              text(p, 'id'): text(p, 'name'),
          },
          onChanged: busy ? null : (v) => setState(() => property = v),
        ),
        PmsSelect(
          'Provider',
          value: provider,
          items: const {
            'Booking.com': 'Booking.com',
            'Szallas.hu': 'Szallas.hu',
            'Other': 'Other',
          },
          onChanged: busy ? null : (v) => setState(() => provider = v),
        ),
        PmsField('Connection type', controller: type),
        const Text(
          'Local sandbox only. No real OTA URL, password or token is stored.',
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
        ? 'Checking Channex…'
        : '${result!['fetched'] ?? 0} revisions checked',
    eyebrow: 'CHANNEX RESERVATION RECEIVER',
    canClose: !busy,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        if (result == null && !busy) PmsButton('Retry', onPressed: receive),
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
                    ? 'Saved and acknowledged'
                    : 'Saved; acknowledgement will retry automatically',
              ),
            ),
          for (final e in optionalRows(result!['errors']))
            Text(text(e, 'error')),
        ],
      ],
    ),
  );
}
