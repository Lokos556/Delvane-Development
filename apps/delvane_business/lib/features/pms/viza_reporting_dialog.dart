import 'package:material_ui/material_ui.dart';

import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';
import 'inventory_controls.dart';
import 'guest_reporting_controls.dart';

String vizaState(String? value) => ui(switch (value) {
  'accepted' ||
  'accepted_by_thf' => 'THF receipt recorded; VIZA delivery unconfirmed',
  'accepted_candidate' || 'review_required' => 'Mixed receipt needs review',
  'uncertain' => 'Outcome unknown; automatic replay blocked',
  'rejected' => 'Rejected; source correction or support required',
  'pending' || 'retry' => 'Pending automatic processing',
  'claimed' || 'sending' => 'Processing in progress',
  'superseded_before_submission' => 'Superseded before submission',
  _ => 'Reporting blocked',
});

const vizaDetailLabels = <String, String>{
  "owner_verification_required": "Owner identity verification is required",
  "country_mapping_requires_review": "Review the nationality code mapping",
  "mrz_birth_century_confirmation": "Confirm the full birth year",
  "Q5_submitted_correction_unresolved":
      "Submitted-data corrections require official guidance",
  "Q6_same_day_expected_departure_unresolved":
      "Same-day VIZA reporting rules need clarification",
  "Q7_uncertain_arrival_closure":
      "Resolve the uncertain arrival before reporting its closure",
  "Q7_duplicate_receipt_requires_review":
      "A duplicate receipt needs outcome review",
  "never_sent_arrival_voided_no_submission":
      "Erroneous arrival voided before any submission",
  "legacy_arrival_uuid_unknown":
      "The historical arrival identifier is unavailable",
  "environment_or_configuration_changed":
      "Reporting binding changed; existing packages remain held",
  "request_validation_failed":
      "Reporting data does not meet the required format",
  "definitely_not_sent":
      "The request was definitely not sent; retry is scheduled",
  "worker_interrupted_outcome_unknown":
      "Processing was interrupted; verify the outcome before replaying",
  "message_rejected_guest_scope_unknown":
      "The message was rejected; individual guest outcome is unresolved",
  "official_transmission_disabled": "Official communication is disabled",
  "Q2_outer_ws_security_unresolved":
      "Official SOAP security requirements need clarification",
  "viza_credentials_and_thf_trust_not_verified":
      "VIZA credentials and THF trust are unverified",
  "missing_configuration": "Reporting configuration is missing",
  "mock_observed": "Local mock observation",
  "not_due": "The next observation is not due yet",
  "matched": "Matched local message",
  "unknown_message": "Message needs correlation review",
  "outcome_unknown": "Submission outcome is unknown; do not replay",
  "Q4_mixed_receipt_requires_review": "Mixed receipt requires support review",
  "property_configuration_not_bound": "Property security binding is incomplete",
  "monitor_response_unavailable_or_invalid":
      "THF response is unavailable or invalid",
  "VIZA-OFFLINE": "THF cannot reach VIZA",
  "KM-OFFLINE": "THF cannot reach the encryption key service",
  "OUTOFKEYS": "THF has no encryption keys remaining",
  "RA-OFFLINE": "THF certificate renewal service is unavailable",
  "CERT-WARNING": "A THF certificate expires soon",
  "CERT-EXPIRED": "A THF certificate has expired",
  "CERT-RENEWED": "Renewed THF certificate needs activation",
  "RESTART-THF": "THF needs a restart",
  "DATA-REJECTED": "VIZA rejected messages with data errors",
};
String vizaDetail(String value) => ui(vizaDetailLabels[value] ?? value);

class VizaReportingDialog extends StatefulWidget {
  const VizaReportingDialog({
    super.key,
    required this.c,
    required this.propertyId,
    required this.propertyName,
  });
  final PmsController c;
  final String propertyId, propertyName;
  @override
  State<VizaReportingDialog> createState() => _VizaReportingState();
}

class _VizaReportingState extends State<VizaReportingDialog>
    with PmsActions<VizaReportingDialog> {
  Map<String, dynamic>? data;
  String? actionResult;
  final listPages = <String, Map<String, dynamic>>{};
  late final api = PmsWorkflows(widget.c);
  String get path => '/api/government/viza/properties/${widget.propertyId}';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await perform(() async {
      final result = await api.object(path);
      if (mounted) {
        setState(() {
          data = result;
          listPages.clear();
        });
      }
    });
  }

  Future<void> command(String suffix, [Object? body]) async {
    final ok = await perform(() async {
      final result = await api.change('POST', '$path$suffix', body);
      if (mounted) {
        setState(
          () => actionResult = result is Map
              ? '${result['code'] ?? result['state'] ?? "unknown"}'
              : 'unknown',
        );
      }
    });
    if (ok && mounted) await load();
  }

  Future<void> listPage(String selector, int offset) async {
    await perform(() async {
      final page = await api.object(
        '$path/lists/$selector?offset=$offset&limit=100',
      );
      if (mounted) setState(() => listPages[selector] = page);
    });
  }

  Future<void> configure() async {
    final cfg = Map<String, dynamic>.from(data?['configuration'] as Map? ?? {});
    await showDialog(
      context: context,
      useRootNavigator: false,
      builder: (_) => InventoryForm(
        title: 'VIZA local reporting settings',
        labels: const {
          'environment': 'Environment',
          'reporting_id': 'Property reporting identifier (8 characters)',
          'endpoint': 'Assigned HTTPS THF endpoint',
          'property_name': 'Property name',
          'provider_name': 'Provider name',
          'provider_tax': 'Provider tax number',
          'poll_minutes': 'THF polling interval (1–60 minutes)',
        },
        initial: {
          'environment': 'test',
          'property_name': widget.propertyName,
          'poll_minutes': 5,
          ...cfg,
        },
        selects: {
          'environment': {
            'test': ui('Test'),
            'staging': ui('Staging'),
            'production': ui('Production'),
          },
        },
        intro: Text(
          ui(
            'Saving settings does not enable official communication or verify certificates.',
          ),
        ),
        save: (values) async {
          values['poll_minutes'] = int.tryParse('${values['poll_minutes']}');
          await api.change('PUT', '$path/settings', values);
        },
      ),
    );
    if (mounted) await load();
  }

  @override
  Widget build(BuildContext context) {
    final health = data?['health'] as Map? ?? {};
    final config = data?['configuration'] as Map?;
    final mock = health['mode'] == 'mock';
    final lists = {...(data?['lists'] as Map? ?? {}), ...listPages};
    return PmsModal(
      title: '${ui('VIZA reporting')} · ${widget.propertyName}',
      width: 900,
      actions: [
        PmsButton(ui('Refresh'), onPressed: busy ? null : load),
        if (widget.c.user.role == 'owner')
          PmsButton(
            ui('Reporting settings'),
            onPressed: busy ? null : configure,
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          errors(),
          Text(
            ui(
              'Official government transmission is disabled. Actual stays continue to be captured automatically.',
            ),
          ),
          if (config == null) Text(ui('VIZA configuration is missing.')),
          Text(ui('VIZA credentials and THF trust have not been verified.')),
          for (final code in (data?['security_blockers'] as List? ?? []))
            Text(vizaDetail('$code')),
          const SizedBox(height: 12),
          Text(
            ui(
              mock
                  ? 'Local mock observation; no official connection or acceptance'
                  : 'THF connection has not been verified',
            ),
          ),
          Text(
            '${ui('THF observation')}: ${vizaDetail('${health['state'] ?? "unknown"}')}',
          ),
          if (health['primary'] != null)
            Text('${ui('THF status')}: ${health['primary']}'),
          for (final flag in (health['flags'] as List? ?? []))
            Text(vizaDetail('$flag')),
          Text('${ui('Last observation')}: ${health['observed_at'] ?? "—"}'),
          Text(
            '${ui('THF software version')}: ${health['software_version'] ?? "—"}',
          ),
          Text('${ui('THF unsent messages')}: ${health['unsent'] ?? "—"}'),
          Text('${ui('THF rejected messages')}: ${health['rejected'] ?? "—"}'),
          Text(
            ui(
              'THF counters may include other properties. Local queue state is separate.',
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PmsButton(
                ui('Request THF observation'),
                onPressed: busy ? null : () => command('/observe'),
              ),
              for (final selector in ['NEMBEKULDOTT', 'HIBAS'])
                PmsButton(
                  ui(
                    selector == 'HIBAS'
                        ? 'Retrieve rejected list'
                        : 'Retrieve unsent list',
                  ),
                  onPressed: busy ? null : () => command('/lists/$selector'),
                ),
            ],
          ),
          if (actionResult != null)
            Text('${ui('Action result')}: ${vizaDetail(actionResult!)}'),
          for (final schedule in (data?['schedules'] as List? ?? []))
            if ((schedule as Map)['last_error'] != null)
              Text(ui('${schedule['last_error']}')),
          for (final entry in lists.entries) ...[
            const SizedBox(height: 12),
            Text(ui(entry.key == 'HIBAS' ? 'Rejected list' : 'Unsent list')),
            Text(ui('List absence does not prove delivery.')),
            if ((entry.value as Map)['mode'] == 'mock')
              Text(ui('Local mock only')),
            if ((entry.value as Map)['limit_reached'] == true)
              Text(
                ui('List limit reached; completeness requires support review.'),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (((entry.value as Map)['offset'] as num? ?? 0) > 0)
                  PmsButton(
                    ui('Previous list page'),
                    onPressed: busy
                        ? null
                        : () => listPage(
                            '${entry.key}',
                            (((entry.value as Map)['offset'] as num).toInt() -
                                    100)
                                .clamp(0, 10000)
                                .toInt(),
                          ),
                  ),
                if ((((entry.value as Map)['offset'] as num? ?? 0) + 100) <
                    ((entry.value as Map)['total'] as num? ?? 0))
                  PmsButton(
                    ui('Next list page'),
                    onPressed: busy
                        ? null
                        : () => listPage(
                            '${entry.key}',
                            ((entry.value as Map)['offset'] as num? ?? 0)
                                    .toInt() +
                                100,
                          ),
                  ),
              ],
            ),
            for (final item in ((entry.value as Map)['items'] as List? ?? []))
              Text(
                '${(item as Map)['message_id']} · ${ui('${item['correlation']}')} · ${(item['codes'] as List? ?? []).join(", ")}',
              ),
          ],
          const SizedBox(height: 16),
          Text(ui('Captured guest reporting work')),
          for (final job in (data?['jobs'] as List? ?? []))
            jobCard(Map<String, dynamic>.from(job as Map)),
          const SizedBox(height: 16),
          Text(ui('VIZA action history')),
          for (final action in (data?['actions'] as List? ?? []))
            Text(
              '${(action as Map)['created_at']} · ${ui('${action['action']}')} · ${ui('${action['result_code']}')}',
            ),
        ],
      ),
    );
  }

  Widget jobCard(Map<String, dynamic> job) => PmsCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${job['kind']} · ${job['id']}'),
        Text('${ui('Environment')}: ${job['environment'] ?? "—"}'),
        for (final attempt in (job['attempt_history'] as List? ?? []))
          Text(
            '${ui('Attempt')} ${(attempt as Map)['attempt_no']} · ${vizaState('${attempt['state']}')} · ${attempt['wire_timestamp']}',
          ),
        if (job['mode'] == 'mock') Text(ui('Local mock only')),
        Text(vizaState('${job['state']}')),
        Text('${ui('Next automatic attempt')}: ${job['due_at'] ?? "—"}'),
        if (job['receipt_id'] != null)
          Text('${ui('THF receipt identifier')}: ${job['receipt_id']}'),
        for (final blocker in (job['blockers'] as List? ?? []))
          Text(vizaDetail('$blocker')),
        if (job['error_code'] != null) Text(vizaDetail('${job['error_code']}')),
        for (final guest in (job['guests'] as List? ?? [])) ...[
          Text(
            '${ui('Arrival identifier')}: ${(guest as Map)['arrival_uuid']}',
          ),
          Text(vizaState('${guest['state']}')),
          Text(
            '${ui('Downstream delivery')}: ${vizaDetail('${guest['downstream_state'] ?? "unknown"}')}',
          ),
          for (final error in (guest['errors'] as List? ?? []))
            Text(
              '${(error as Map)['code']}: ${error[widget.c.strings.language == "hu" ? "message_hu" : "message_en"]}',
            ),
          PmsButton(
            ui('Review guest identity source'),
            onPressed: busy
                ? null
                : () async {
                    await perform(
                      () => openGuestRegistration(
                        context,
                        api,
                        guestId: '${guest['guest_id']}',
                      ),
                    );
                    if (mounted) await load();
                  },
          ),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (job['can_refresh_identity'] == true)
              PmsButton(
                ui('Refresh never-sent identity facts'),
                onPressed: busy
                    ? null
                    : () => command('/jobs/${job['id']}/recover', {
                        'action': 'refresh_identity',
                      }),
              ),
            if (job['can_retry_not_sent'] == true)
              PmsButton(
                ui('Reschedule definitely-not-sent work'),
                onPressed: busy
                    ? null
                    : () => command('/jobs/${job['id']}/recover', {
                        'action': 'retry_not_sent',
                      }),
              ),
          ],
        ),
      ],
    ),
  );
}
