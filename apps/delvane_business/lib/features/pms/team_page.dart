import 'package:delvane_business/core/localization/web_strings.dart';
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
    if (!c.user.isOperator) return PmsEmpty(ui('No access'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsPageHeader(
          eyebrow: ui('TEAM & ACCESS'),
          title: ui('Your people, their work, and exactly what they can see.'),
          description: ui(
            'Add cleaners, maintenance workers and managers, review access, suspend accounts and understand workload without mixing it into the day-to-day task screens.',
          ),
          actions: [
            canManage
                ? PmsButton(
                    ui('+ Add team member'),
                    primary: true,
                    onPressed: edit,
                  )
                : Text(
                    ui('Manager view - owner controls accounts'),
                    style: TextStyle(fontSize: 12),
                  ),
          ],
        ),
        PmsColumns(gap: 0, [
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
                      fontFamily: 'Georgia',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    e.value.toUpperCase(),
                    style: const TextStyle(fontSize: 10, letterSpacing: .5),
                  ),
                ],
              ),
            ),
        ], columns: 4),
        const SizedBox(height: 24),
        PmsTabs(
          plain: true,
          labels: ['People (${members.length})', 'Access & roles', 'Workload'],
          selected: tab,
          onChanged: (v) => setState(() => tab = v),
        ),
        const SizedBox(height: 24),
        if (tab == 0)
          PmsColumns([for (final m in members) person(m)], columns: 2),
        if (tab == 0 && members.isEmpty) PmsEmpty(ui('No team members.')),
        if (tab == 1) ...[
          PmsEyebrow(ui('ACCESS MODEL')),
          Text(
            ui('People see only what their job requires.'),
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: PmsButton(
              ui('Open Security Center'),
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
          PmsEyebrow(ui('ACCOUNT POSTURE')),
          Text(
            ui(
              '${stats['unverified'] ?? 0} unverified emails · ${stats['active_sessions'] ?? 0} active sessions · ${members.where((m) => m['mfa_enabled'] == 1).length} MFA enabled',
            ),
          ),
          Text(
            ui(
              'These are stored account indicators. Email delivery and MFA enrollment are not provided by this screen.',
            ),
          ),
        ],
        if (tab == 2) ...[
          PmsEyebrow(ui('NEXT 7 DAYS')),
          Text(
            ui('Workload by person'),
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
          ),
          for (final m in members.where(
            (m) => ['cleaner', 'maintenance'].contains(m['role']),
          ))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(text(m, 'full_name')),
              subtitle: Text(
                ui(
                  '${m['upcoming_cleaning']} clean · ${m['open_maintenance']} maintenance',
                ),
              ),
            ),
          const SizedBox(height: 24),
          PmsEyebrow(ui('ASSIGNMENTS')),
          Text(
            ui('Upcoming work'),
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
            PmsEmpty(ui('No upcoming work.')),
        ],
      ],
    );
  }

  Widget person(Json m) => Opacity(
    opacity: m['active'] == 0 ? .68 : 1,
    child: PmsCard(
      radius: 24,
      padding: const EdgeInsets.all(18),
      color: m['active'] == 0
          ? const Color(0xFFF7F3EC)
          : const Color(0xFFFFFDF8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFF204A3A),
                child: Text(
                  text(m, 'full_name')
                      .split(' ')
                      .where((s) => s.isNotEmpty)
                      .take(2)
                      .map((s) => s[0])
                      .join()
                      .toUpperCase(),
                  style: const TextStyle(
                    fontFamily: 'Georgia',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      children: [
                        PmsBadge(text(m, 'role').toUpperCase()),
                        if (m['active'] == 0)
                          PmsBadge(ui('Suspended'), tone: 'high'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text(m, 'full_name'),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      text(m, 'job_title').isEmpty
                          ? text(m, 'role')
                          : text(m, 'job_title'),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
              if (canManage)
                PmsButton(ui('Manage'), small: true, onPressed: () => edit(m)),
            ],
          ),
          const SizedBox(height: 16),
          PmsColumns(
            [
              for (final e in {
                'EMAIL': text(m, 'email'),
                'PHONE': text(m, 'phone').isEmpty
                    ? 'Not added'
                    : text(m, 'phone'),
              }.entries)
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F4EE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.key,
                        style: const TextStyle(fontSize: 10, letterSpacing: .5),
                      ),
                      const SizedBox(height: 3),
                      SelectableText(
                        e.value,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            columns: 2,
            mobileColumns: 2,
            gap: 10,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PmsBadge(
                m['email_verified'] == 1
                    ? ui('Email verified')
                    : ui('! Email unverified'),
              ),
              Text(
                m['mfa_enabled'] == 1 ? ui('MFA') : ui('MFA off'),
                style: const TextStyle(fontSize: 11),
              ),
              Text(
                ui('${m['active_sessions'] ?? 0} active sessions'),
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in {
                'open / next 7 days':
                    '${(m['upcoming_cleaning'] as num? ?? 0) + (m['open_maintenance'] as num? ?? 0)}',
                'in progress': '${m['in_progress'] ?? 0}',
                'completed 30d': '${m['completed_30d'] ?? 0}',
                'last sign-in': text(m, 'last_login_at', 'Never'),
              }.entries)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.value,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(e.key, style: const TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
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
      reset ? ui('Reset access?') : ui('Revoke sessions?'),
      reset
          ? ui(
              'Generate a new setup password and revoke all previous sessions for ${name.text}?',
            )
          : ui('Sign ${name.text} out of all Delvane sessions?'),
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
      return PmsModal(
        title: ui('No access'),
        child: Text(ui('Owner access required.')),
      );
    }
    if (credential != null) {
      return PmsModal(
        title: ui('Give these details to ${name.text}.'),
        eyebrow: editing ? ui('ACCESS RESET') : ui('ACCOUNT CREATED'),
        width: 600,
        actions: [
          PmsButton(
            ui('Copy setup details'),
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
            ui('Done'),
            primary: true,
            onPressed: () => Navigator.pop(context),
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ui(
                'The setup password is shown once. Share it securely. No email has been sent.',
              ),
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
      title: editing ? name.text : ui('Add someone to Rosa'),
      eyebrow: editing ? ui('TEAM ACCOUNT') : ui('NEW TEAM MEMBER'),
      width: 760,
      canClose: !busy,
      actions: [
        PmsButton(
          ui('Cancel'),
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        PmsButton(
          editing ? ui('Save changes') : ui('Create account'),
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
              PmsField(ui('Full name'), controller: name, required: true),
              PmsField(
                ui('Email'),
                controller: email,
                required: true,
                keyboard: TextInputType.emailAddress,
              ),
              PmsField(ui('Phone (optional)'), controller: phone),
              PmsField(ui('Job title (optional)'), controller: title),
              PmsSelect(
                ui('Delvane role'),
                value: role,
                items: {
                  'cleaner': ui('Cleaner'),
                  'maintenance': ui('Maintenance'),
                  'manager': ui('Manager'),
                  'owner': ui('Owner'),
                },
                onChanged: busy || self
                    ? null
                    : (v) => setState(() => role = v),
              ),
              if (editing)
                PmsSelect(
                  ui('Account status'),
                  value: active ? 'active' : 'suspended',
                  items: {'active': ui('Active'), 'suspended': ui('Suspended')},
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
                    Text(
                      ui(
                        'Owners can manage people, access, settings and security.',
                      ),
                    ),
                ],
              ),
            ),
            if (editing && !self) ...[
              const SizedBox(height: 20),
              PmsEyebrow(ui('ACCESS TOOLS')),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PmsButton(
                    ui('Reset access'),
                    onPressed: busy || changed ? null : () => access(true),
                  ),
                  PmsButton(
                    ui('Revoke sessions'),
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
