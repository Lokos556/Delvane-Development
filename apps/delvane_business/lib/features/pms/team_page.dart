import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../workspace/workspace_models.dart';
import 'operations_workflows.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';

class TeamPage extends StatefulWidget {
  const TeamPage({super.key, required this.c});
  final PmsController c;
  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  int tab = 0;
  PmsController get c => widget.c;
  bool get canManage =>
      c.user.role == 'owner' && c.object('team')['can_manage'] == true;
  Future<void> edit([Json? member]) async {
    if (!canManage) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => TeamMemberEditor(
        c: c,
        member: member,
        roles: optionalObject(c.object('team')['roles']),
      ),
    );
    if (mounted && c.auth.user != null) await c.load();
  }

  @override
  Widget build(BuildContext context) {
    final d = c.object('team'),
        stats = optionalObject(d['stats']),
        members = optionalRows(d['members']);
    if (!c.user.isOperator) return const PmsEmpty('No access');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PmsEyebrow('TEAM & ACCESS'),
        const Text(
          'Your people, their work, and exactly what they can see.',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.5,
          ),
        ),
        const Text(
          'Add cleaners, maintenance workers and managers, review access, suspend accounts and understand workload without mixing it into the day-to-day task screens.',
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: canManage
              ? PmsButton('+ Add team member', primary: true, onPressed: edit)
              : const Text('Manager view · account changes are owner-only.'),
        ),
        const SizedBox(height: 24),
        PmsColumns([
          for (final e in {
            'active': 'Active people',
            'cleaners': 'Cleaners',
            'maintenance': 'Maintenance',
            'unverified': 'Access attention',
          }.entries)
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${stats[e.key] ?? 0}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(e.value),
                ],
              ),
            ),
        ], columns: 4),
        const SizedBox(height: 24),
        PmsTabs(
          labels: ['People (${members.length})', 'Access & roles', 'Workload'],
          selected: tab,
          onChanged: (v) => setState(() => tab = v),
        ),
        const SizedBox(height: 24),
        if (tab == 0)
          PmsColumns([for (final m in members) person(m)], columns: 2),
        if (tab == 0 && members.isEmpty) const PmsEmpty('No team members.'),
        if (tab == 1) ...[
          const PmsEyebrow('ACCESS MODEL'),
          const Text(
            'People see only what their job requires.',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: PmsButton(
              'Open Security Center',
              onPressed: () => c.navigate(PmsPage.security),
            ),
          ),
          const SizedBox(height: 16),
          PmsColumns([
            for (final entry in optionalObject(d['roles']).entries)
              PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PmsBadge(entry.key),
                    for (final group in optionalRows(
                      optionalObject(entry.value)['groups'],
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          '${group['enabled'] == true ? '✓' : '—'} ${text(group, 'label')}',
                        ),
                      ),
                  ],
                ),
              ),
          ], columns: 2),
          const SizedBox(height: 24),
          const PmsEyebrow('ACCOUNT POSTURE'),
          Text(
            '${stats['unverified'] ?? 0} unverified emails · ${stats['active_sessions'] ?? 0} active sessions · ${members.where((m) => m['mfa_enabled'] == 1).length} MFA enabled',
          ),
          const Text(
            'These are stored account indicators. Email delivery and MFA enrollment are not provided by this screen.',
          ),
        ],
        if (tab == 2) ...[
          const PmsEyebrow('NEXT 7 DAYS'),
          const Text(
            'Workload by person',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          for (final m in members.where(
            (m) => ['cleaner', 'maintenance'].contains(m['role']),
          ))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(text(m, 'full_name')),
              subtitle: Text(
                '${m['upcoming_cleaning']} clean · ${m['open_maintenance']} maintenance',
              ),
            ),
          const SizedBox(height: 24),
          const PmsEyebrow('ASSIGNMENTS'),
          const Text(
            'Upcoming work',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          for (final w in optionalRows(d['workload']))
            PmsCard(
              child: Wrap(
                spacing: 20,
                runSpacing: 8,
                children: [
                  PmsBadge(text(w, 'kind')),
                  Text(text(w, 'title')),
                  Text(
                    '${text(w, 'property_name')} · ${text(w, 'scheduled_date')}',
                  ),
                  Text(text(w, 'assigned_name', 'Unassigned')),
                  PmsBadge(text(w, 'status')),
                ],
              ),
            ),
          if (optionalRows(d['workload']).isEmpty)
            const PmsEmpty('No upcoming work.'),
        ],
      ],
    );
  }

  Widget person(Json m) => PmsCard(
    radius: 19,
    padding: const EdgeInsets.all(18),
    color: m['active'] == 0 ? const Color(0xFFF7F3EC) : const Color(0xFFFFFDF8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          children: [
            PmsBadge(text(m, 'role')),
            if (m['active'] == 0) const PmsBadge('Suspended', tone: 'high'),
            if (canManage)
              PmsButton('Manage', small: true, onPressed: () => edit(m)),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          text(m, 'full_name'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        Text(text(m, 'job_title', text(m, 'role'))),
        const SizedBox(height: 16),
        SelectableText(text(m, 'email')),
        Text(text(m, 'phone', 'Not added')),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            PmsBadge(
              m['email_verified'] == 1 ? 'Email verified' : 'Email unverified',
            ),
            PmsBadge(m['mfa_enabled'] == 1 ? 'MFA' : 'MFA off'),
            PmsBadge('${m['active_sessions'] ?? 0} active sessions'),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '${(m['upcoming_cleaning'] as num? ?? 0) + (m['open_maintenance'] as num? ?? 0)} open next 7 days · ${m['in_progress'] ?? 0} in progress · ${m['completed_30d'] ?? 0} completed / 30d',
        ),
        Text('Last sign-in: ${text(m, 'last_login_at', 'Never')}'),
      ],
    ),
  );
}

class TeamMemberEditor extends StatefulWidget {
  const TeamMemberEditor({
    super.key,
    required this.c,
    required this.roles,
    this.member,
  });
  final PmsController c;
  final Json roles;
  final Json? member;
  @override
  State<TeamMemberEditor> createState() => _TeamMemberEditorState();
}

class _TeamMemberEditorState extends State<TeamMemberEditor>
    with PmsActions<TeamMemberEditor> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
        text: text(widget.member ?? {}, 'full_name'),
      ),
      email = TextEditingController(text: text(widget.member ?? {}, 'email')),
      phone = TextEditingController(text: text(widget.member ?? {}, 'phone')),
      title = TextEditingController(
        text: text(widget.member ?? {}, 'job_title'),
      );
  late String role = text(widget.member ?? {}, 'role', 'cleaner');
  late bool active = widget.member?['active'] != 0;
  Json? credential;
  String? copyState;
  bool changed = false;
  bool get editing => widget.member != null;
  bool get self => widget.member?['id'] == widget.c.user.id;
  OperationsWorkflows get api => OperationsWorkflows(widget.c);
  @override
  void dispose() {
    for (final c in [name, email, phone, title]) {
      c.dispose();
    }
    credential = null;
    super.dispose();
  }

  Future<void> save() async {
    if (changed || !form.currentState!.validate()) return;
    final ok = await perform(() async {
      final result = await api.member({
        'full_name': name.text,
        'email': email.text,
        'phone': phone.text,
        'job_title': title.text,
        'role': role,
        if (editing) 'active': active,
      }, id: widget.member?['id']);
      changed = true;
      if (result['setup_password'] != null && mounted) {
        setState(() => credential = result);
      }
    });
    if (ok && credential == null && mounted) Navigator.pop(context);
  }

  Future<void> access(bool reset) async {
    final confirm = await pmsConfirm(
      context,
      reset ? 'Reset access?' : 'Revoke sessions?',
      reset
          ? 'Generate a new setup password and revoke all previous sessions for ${name.text}?'
          : 'Sign ${name.text} out of all Delvane sessions?',
    );
    if (!confirm || !mounted) return;
    final ok = await perform(() async {
      final result = await api.access(text(widget.member!, 'id'), reset: reset);
      changed = true;
      if (reset && mounted) setState(() => credential = result);
    });
    if (ok && !reset && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.c.user.role != 'owner') {
      return const PmsModal(
        title: 'No access',
        child: Text('Owner access required.'),
      );
    }
    if (credential != null) {
      return PmsModal(
        title: 'Give these details to ${name.text}.',
        eyebrow: editing ? 'ACCESS RESET' : 'ACCOUNT CREATED',
        width: 600,
        actions: [
          PmsButton(
            'Copy setup details',
            onPressed: () async {
              try {
                await Clipboard.setData(
                  ClipboardData(
                    text:
                        'Delvane\n${name.text}\n${email.text}\n${text(credential!, 'setup_password')}',
                  ),
                );
                if (mounted) setState(() => copyState = 'Copied.');
              } catch (_) {
                if (mounted) {
                  setState(
                    () => copyState =
                        'Copy unavailable — select the details manually.',
                  );
                }
              }
            },
          ),
          PmsButton(
            'Done',
            primary: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'The setup password is shown once. Share it securely. No email has been sent.',
            ),
            const SizedBox(height: 20),
            Text(email.text),
            SelectableText(
              text(credential!, 'setup_password'),
              style: const TextStyle(fontSize: 24, fontFamily: 'monospace'),
            ),
            if (copyState != null) Text(copyState!),
          ],
        ),
      );
    }
    return PmsModal(
      title: editing ? name.text : 'Add someone to Rosa',
      eyebrow: editing ? 'TEAM ACCOUNT' : 'NEW TEAM MEMBER',
      width: 760,
      canClose: !busy,
      actions: [
        PmsButton(
          'Cancel',
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        PmsButton(
          editing ? 'Save changes' : 'Create account',
          primary: true,
          onPressed: busy || changed ? null : save,
        ),
      ],
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            errors(),
            PmsColumns([
              PmsField('Full name', controller: name, required: true),
              PmsField(
                'Email',
                controller: email,
                required: true,
                keyboard: TextInputType.emailAddress,
              ),
              PmsField('Phone (optional)', controller: phone),
              PmsField('Job title (optional)', controller: title),
              PmsSelect(
                'Delvane role',
                value: role,
                items: const {
                  'cleaner': 'Cleaner',
                  'maintenance': 'Maintenance',
                  'manager': 'Manager',
                  'owner': 'Owner',
                },
                onChanged: busy || self
                    ? null
                    : (v) => setState(() => role = v),
              ),
              if (editing)
                PmsSelect(
                  'Account status',
                  value: active ? 'active' : 'suspended',
                  items: const {'active': 'Active', 'suspended': 'Suspended'},
                  onChanged: busy || self
                      ? null
                      : (v) => setState(() => active = v == 'active'),
                ),
            ], columns: 2),
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PmsBadge(role),
                  for (final group in optionalRows(
                    optionalObject(widget.roles[role])['groups'],
                  ).where((g) => g['enabled'] == true))
                    Text('✓ ${text(group, 'label')}'),
                  if (role == 'owner')
                    const Text(
                      'Owners can manage people, access, settings and security.',
                    ),
                ],
              ),
            ),
            if (editing && !self) ...[
              const SizedBox(height: 20),
              const PmsEyebrow('ACCESS TOOLS'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PmsButton(
                    'Reset access',
                    onPressed: busy || changed ? null : () => access(true),
                  ),
                  PmsButton(
                    'Revoke sessions',
                    onPressed: busy || changed ? null : () => access(false),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
