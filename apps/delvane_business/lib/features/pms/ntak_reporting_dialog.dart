import 'package:material_ui/material_ui.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';

String ntakState(String? state) => ui(switch (state) {
  'ready' || 'retry' => 'Waiting to submit',
  'accepted' => 'Accepted; processing pending',
  'succeeded' => 'Processing completed',
  'uncertain' => 'Submission outcome unknown',
  'review_required' => 'Review required',
  'retry_exhausted' => 'Retries stopped; resolution required',
  'rejected' => 'Submission rejected',
  'sending' => 'Submission in progress',
  'awaiting_closing_facts' => 'Closing facts need confirmation',
  'replaced_by_correction' => 'Replaced by a correction',
  _ => 'Reporting blocked',
});

String ntakProblem(String? code) => ui(switch (code) {
  'missing_reporting_data' => 'Required reporting details are missing.',
  'signature_profile_unresolved' => 'Official message-signing requirements need clarification.',
  'information_response_contract_unresolved' => 'The official reporting start-date response needs clarification.',
  'outcome_unknown' || 'worker_interrupted' => 'Check the submission outcome before sending again.',
  'property_identity_changed' || 'environment_or_configuration_changed' => 'The reporting identity or environment has changed.',
  'past_arrival_policy_conflict' => 'Reporting rules for changes after arrival need clarification.',
  'schema_validation_failed' || 'invalid_reporting_data' => 'Reporting details do not meet the official format.',
  'hourly_rate_limit' => 'Reporting is waiting to stay within the hourly limit.',
  'resend_version_review_required' => 'The requested resend needs a reporting-version review.',
  'SzerverHiba' => 'NTAK reported a server error.',
  _ => 'Review the reporting details and official response.',
});

class NtakReportingDialog extends StatefulWidget {
  const NtakReportingDialog({super.key, required this.c, required this.propertyId, required this.propertyName});
  final PmsController c;
  final String propertyId, propertyName;
  @override
  State<NtakReportingDialog> createState() => _NtakReportingDialogState();
}

class _NtakReportingDialogState extends State<NtakReportingDialog> with PmsActions<NtakReportingDialog> {
  Json? data;
  String get base => '/api/government/ntak/properties/${Uri.encodeComponent(widget.propertyId)}';
  bool get owner => widget.c.user.role == 'owner';
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    await perform(() async {
      final result = await widget.c.api.get(base);
      if (mounted) setState(() => data = Map<String, dynamic>.from(result as Map));
    });
  }
  Future<void> configure() async {
    await showDialog<void>(context: context, useRootNavigator: false,
      builder: (_) => NtakConfigurationDialog(c: widget.c, path: base,
        initial: data?['configuration'] is Map ? Map<String, dynamic>.from(data!['configuration']) : {}));
    if (mounted) await load();
  }
  Future<void> recovery(Json job) async {
    await showDialog<void>(context: context, useRootNavigator: false,
      builder: (_) => NtakRecoveryDialog(c: widget.c, path: '$base/jobs/${job['id']}/recovery', uncertain: job['state'] == 'uncertain'));
    if (mounted) await load();
  }
  @override
  Widget build(BuildContext context) {
    final config = data?['configuration'];
    final jobs = (data?['jobs'] as List? ?? []).cast<Map>();
    final days = (data?['daily_closings'] as List? ?? []).cast<Map>();
    final certificate = data?['certificate'] as Map? ?? {};
    return PmsModal(title: '${ui('NTAK reporting')} · ${widget.propertyName}', width: 900,
      actions: [PmsButton(ui('Refresh'), onPressed: busy ? null : load),
        if (owner) PmsButton(ui('Reporting settings'), onPressed: busy ? null : configure)],
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        errors(),
        Text(ui('Official transmission is blocked. Local preparation does not mean connection or certification.')),
        const SizedBox(height: 16),
        if (data != null) ...[
          PmsEyebrow(ui('CONFIGURATION')),
          Text(ui(config == null ? 'Not configured' : config['enabled'] == true ? 'Local reporting preparation enabled' : 'Local reporting preparation paused')),
          if (config != null) Text(ui(config['environment'] == 'production' ? 'Production environment' : 'Test environment')),
          Text('${ui('Certificate')}: ${ui(certificate['state'] == 'locally_valid' ? 'Locally valid; official validation pending' : certificate['state'] == 'certificate_expired_or_expiring' ? 'Expired or nearing expiry' : 'Not available or requires review')}'),
          if (certificate['expires_at'] != null) Text('${ui('Expires')}: ${certificate['expires_at']}'),
          Text('${ui('Last successful submission')}: ${data!['last_success_at'] ?? ui('None')}'),
          const SizedBox(height: 20),
          PmsEyebrow(ui('REPORTING QUEUE')),
          for (final count in (data!['counts'] as List? ?? [])) Text('${ntakState(count['state'])}: ${count['count']}'),
          if (jobs.isEmpty) Text(ui('No reporting submissions yet.')),
          for (final job in jobs) Padding(padding: const EdgeInsets.symmetric(vertical: 8),
            child: PmsCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${ui(switch (job['operation']) { 'reservation' => 'Reservation report', 'stay' => 'Guest stay event', 'daily_close' => 'Daily closing', _ => 'Reporting information' })} · ${ntakState(job['state'])}'),
              Text('${ui('Attempts')}: ${job['attempts']}'),
              if (job['error_code'] != null) Text(ntakProblem(job['error_code'])),
              if (job['state'] == 'accepted') Text(ui('Receipt received. Final processing has not completed.')),
              if (job['processing_id'] != null) SelectableText('${ui('Processing reference')}: ${job['processing_id']}'),
              if (owner && ['uncertain','retry_exhausted'].contains(job['state']))
                PmsButton(ui('Review recovery'), onPressed: busy ? null : () => recovery(Map<String,dynamic>.from(job))),
            ]))),
          const SizedBox(height: 20),
          PmsEyebrow(ui('DAILY CLOSINGS')),
          Text(ui('Closing requires confirmed stay and financial facts. Scheduled times do not confirm guest arrivals.')),
          if (days.isEmpty) Text(ui('No daily closing requirements recorded.')),
          for (final day in days) Padding(padding: const EdgeInsets.symmetric(vertical: 5),
            child: Text('${day['business_date']} · ${ntakState(day['state'])}')),
        ],
      ]));
  }
}

class NtakConfigurationDialog extends StatefulWidget {
  const NtakConfigurationDialog({super.key,required this.c,required this.path,required this.initial});
  final PmsController c;
  final String path;
  final Json initial;
  @override
  State<NtakConfigurationDialog> createState() => _NtakConfigurationDialogState();
}

class _NtakConfigurationDialogState extends State<NtakConfigurationDialog> with PmsActions<NtakConfigurationDialog> {
  final form = GlobalKey<FormState>();
  static const labels = {'registration_id':'NTAK registration number','provider_vat':'Provider tax number',
    'software_id':'Software identifier','software_version':'Software version',
    'reporting_start_date':'Confirmed reporting start date','reporting_start_evidence':'Source of start-date confirmation',
    'closing_hour':'Closing review hour'};
  late final fields = {for (final key in labels.keys) key: TextEditingController(text: '${widget.initial[key] ?? (key == 'closing_hour' ? 10 : '')}')};
  late bool enabled = widget.initial['enabled'] == true;
  late String environment = widget.initial['environment'] as String? ?? 'test';
  @override
  void dispose() { for (final field in fields.values) {field.dispose();} super.dispose(); }
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final hour = int.tryParse(fields['closing_hour']!.text);
    if (hour == null || hour < 1 || hour > 23) {setState(() => failure = 'Enter an hour between 1 and 23.'); return;}
    final ok = await perform(() async {
      await widget.c.api.put(widget.path, {
        for (final e in fields.entries) if (!['closing_hour','reporting_start_date'].contains(e.key)) e.key:e.value.text.trim(),
        'reporting_start_date':fields['reporting_start_date']!.text.trim().isEmpty ? null : fields['reporting_start_date']!.text.trim(),
        'closing_hour':hour,'timezone':widget.initial['timezone'] ?? 'Europe/Budapest',
        'environment':environment,'enabled':enabled,
      });
    });
    if (ok && mounted) Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) => PmsModal(title:ui('Reporting settings'),width:620,canClose:!busy,
    actions:[PmsButton(ui('Save'),primary:true,onPressed:busy?null:save)],
    child:PmsForm(formKey:form,child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      errors(),
      Text(ui('Use the assigned identifiers. Certificates and private keys stay on the server.')),
      PmsSelect('Environment',value:environment,items:{'test':ui('Test environment'),'production':ui('Production environment')},
        onChanged:busy || widget.initial.isNotEmpty ? null : (v)=>setState(()=>environment=v)),
      for(final e in labels.entries) PmsField(e.value,controller:fields[e.key]!,
        required:!['reporting_start_date','reporting_start_evidence'].contains(e.key)),
      Text(ui('Leave the start date empty until it is confirmed. No reporting start date is assumed.')),
      SwitchListTile(contentPadding:EdgeInsets.zero,title:Text(ui('Prepare reporting automatically')),
        subtitle:Text(ui('This does not enable official transmission.')),value:enabled,onChanged:busy?null:(v)=>setState(()=>enabled=v)),
    ])));
}

class NtakRecoveryDialog extends StatefulWidget {
  const NtakRecoveryDialog({super.key,required this.c,required this.path,required this.uncertain});
  final PmsController c;
  final String path;
  final bool uncertain;
  @override
  State<NtakRecoveryDialog> createState()=>_NtakRecoveryDialogState();
}
class _NtakRecoveryDialogState extends State<NtakRecoveryDialog> with PmsActions<NtakRecoveryDialog> {
  final reason=TextEditingController(),receipt=TextEditingController();
  final form=GlobalKey<FormState>();
  @override
  void dispose(){reason.dispose();receipt.dispose();super.dispose();}
  Future<void> save() async {
    if(!form.currentState!.validate())return;
    final ok=await perform(()async{await widget.c.api.post(widget.path,{
      'action':widget.uncertain?'record_processing_id':'retry_after_resolution','reason':reason.text.trim(),
      if(widget.uncertain)'processing_id':receipt.text.trim(),
    });});
    if(ok&&mounted)Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context)=>PmsModal(title:ui('Review recovery'),width:600,canClose:!busy,
    actions:[PmsButton(ui('Save recovery record'),onPressed:busy?null:save)],
    child:PmsForm(formKey:form,child:Column(children:[errors(),
      Text(ui(widget.uncertain?'Record the processing reference from official evidence. An uncertain submission cannot be sent again blindly.':'Confirm that the reported server problem has been resolved before restarting retries.')),
      if(widget.uncertain)PmsField('Processing reference',controller:receipt,required:true),
      PmsField('Resolution evidence',controller:reason,required:true,lines:3),
    ])));
}
