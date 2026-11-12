import 'package:delvane_business/core/localization/web_strings.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key, required this.c});
  final PmsController c;
  @override
  Widget build(BuildContext context) {
    final sec = c.object('security');
    if (!c.user.isOperator) return PmsEmpty(ui('No access'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsEyebrow(ui('PRODUCTION CORE')),
        PmsPageTitle(ui('Security center')),
        Text(
          ui(
            'Sessions, tenant boundaries, access controls and audit evidence in one place.',
          ),
        ),
        const SizedBox(height: 20),
        PmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                ui('Production core'),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              Text(
                ui(
                  'Production deployments require PostgreSQL, secure cookies, encryption keys and demo mode disabled.',
                ),
              ),
              const SizedBox(height: 16),
              PmsColumns([
                for (final entry in {
                  'environment': 'Environment',
                  'database_backend': 'Database',
                  'schema_version': 'Schema',
                  'version': 'Version',
                }.entries)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.value,
                        style: const TextStyle(
                          fontSize: 12,
                          color: PmsStyle.muted,
                        ),
                      ),
                      SelectableText(
                        '${c.object('runtime')[entry.key] ?? 'Unknown'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
              ], columns: 4),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PmsColumns([
          for (final entry in {
            'Active sessions': '${optionalRows(sec['sessions']).length}',
            'MFA users':
                '${sec['mfa_enabled_users'] ?? 0}/${sec['active_users'] ?? 0}',
            'Passwords': text(sec, 'password_scheme', 'Unknown'),
            'CSRF': 'ACTIVE',
            'Tenant isolation': 'SERVER',
            'Secure cookie': sec['secure_cookie_required'] == true
                ? 'ON'
                : 'LOCAL OFF',
          }.entries)
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key, style: const TextStyle(fontSize: 12)),
                  Text(
                    entry.value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ], columns: 3),
        const SizedBox(height: 24),
        PmsColumns([
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PmsEyebrow(ui('ACTIVE SESSIONS')),
                for (final s in optionalRows(sec['sessions']))
                  PmsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          text(s, 'full_name'),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text('${text(s, 'role')} · ${text(s, 'ip_address')}'),
                        Text(text(s, 'user_agent')),
                        Text(
                          ui(
                            'Last seen ${text(s, 'last_seen_at')} · expires ${text(s, 'expires_at')}',
                          ),
                        ),
                        if (c.user.role == 'owner')
                          Align(
                            alignment: Alignment.centerRight,
                            child: PmsButton(
                              ui('Revoke session'),
                              onPressed: c.saving
                                  ? null
                                  : () async {
                                      if (await pmsConfirm(
                                            context,
                                            ui('Revoke this active session?'),
                                            ui(
                                              'The selected session will be signed out.',
                                            ),
                                          ) &&
                                          c.auth.user?.role == 'owner') {
                                        await c.act(() async {
                                          await c.mutate(
                                            'DELETE',
                                            '/api/security/sessions/${idPath(text(s, 'id'))}',
                                          );
                                        });
                                      }
                                    },
                            ),
                          ),
                      ],
                    ),
                  ),
                if (optionalRows(sec['sessions']).isEmpty)
                  PmsEmpty(ui('No active sessions.')),
                const SizedBox(height: 24),
              ],
            ),
          ),
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PmsEyebrow(ui('LEAST PRIVILEGE')),
                Text(
                  ui('Role permissions'),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                PmsColumns([
                  for (final role in optionalObject(sec['permissions']).entries)
                    PmsCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            role.key,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            ui(
                              '${role.value is List ? (role.value as List).length : 0} permissions',
                            ),
                          ),
                          if (role.value is List)
                            Text(
                              (role.value as List).take(5).join(' \u00b7 '),
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                ], columns: 2),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ], columns: 2),
        const SizedBox(height: 24),
        PmsColumns([
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PmsEyebrow(ui('EVIDENCE')),
                Text(
                  ui('Audit trail'),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                for (final a in c.rows('audit').take(35))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(text(a, 'summary')),
                    subtitle: Text(
                      '${text(a, 'event_type')} · ${text(a, 'actor_name', text(a, 'actor_type'))}\n${text(a, 'created_at')}',
                    ),
                  ),
              ],
            ),
          ),
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PmsEyebrow(ui('PRIVACY')),
                Text(
                  ui('Data retention'),
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                for (final r in c.rows('retention'))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(text(r, 'data_class').replaceAll('_', ' ')),
                    subtitle: Text(
                      '${r['retention_days'] == null ? 'Not configured' : '${r['retention_days']} days'}\n${text(r, 'description')}',
                    ),
                  ),
              ],
            ),
          ),
        ], columns: 2),
      ],
    );
  }
}

class KnowledgePage extends StatefulWidget {
  const KnowledgePage({super.key, required this.c});
  final PmsController c;
  @override
  State<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<KnowledgePage>
    with PmsActions<KnowledgePage> {
  String scope = 'shared';
  final inputs = <String, TextEditingController>{};
  bool saved = false;
  @override
  void initState() {
    super.initState();
    populate();
  }

  void populate() {
    for (final input in inputs.values) {
      input.dispose();
    }
    inputs.clear();
    final values = optionalObject(
      optionalObject(widget.c.object('knowledge')['scopes'])[scope],
    );
    for (final field in optionalRows(widget.c.object('knowledge')['fields'])) {
      final key = text(field, 'key');
      inputs[key] = TextEditingController(text: text(values, key));
    }
  }

  @override
  void dispose() {
    for (final input in inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    await perform(() async {
      if (!widget.c.user.isOperator) {
        throw StateError('Operator access required');
      }
      await widget.c.mutate('PUT', '/api/knowledge/${idPath(scope)}', {
        'entries': {for (final e in inputs.entries) e.key: e.value.text},
      });
      final scopes = optionalObject(widget.c.object('knowledge')['scopes']);
      scopes[scope] = {for (final e in inputs.entries) e.key: e.value.text};
      widget.c.object('knowledge')['scopes'] = scopes;
      if (mounted) setState(() => saved = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.c.object('knowledge');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsEyebrow(ui('TRAIN DELVANE')),
        PmsPageTitle(ui('Train Delvane')),
        Text(
          ui(
            'Shared knowledge applies across properties. Property-specific knowledge overrides shared guidance.',
          ),
        ),
        const SizedBox(height: 24),
        errors(),
        PmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ui('Prototype knowledge'),
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                ui(
                  'The seeded entries marked "DEMO ONLY" are placeholders, not real Casa Rosa policies. Replace them before guest messaging goes live.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PmsTabs(
          labels: [
            'Casa Rosa',
            for (final p in optionalRows(d['properties'])) text(p, 'name'),
          ],
          selected: [
            'shared',
            for (final p in optionalRows(d['properties'])) text(p, 'id'),
          ].indexOf(scope),
          onChanged: busy
              ? (_) {}
              : (index) async {
                  final next = [
                    'shared',
                    for (final p in optionalRows(d['properties']))
                      text(p, 'id'),
                  ][index];
                  if (next == scope) return;
                  if (!saved &&
                      !await pmsConfirm(
                        context,
                        ui('Change knowledge scope?'),
                        ui('Unsaved changes in this scope will be discarded.'),
                      )) {
                    return;
                  }
                  if (!mounted) return;
                  setState(() {
                    scope = next;
                    populate();
                    saved = false;
                  });
                },
        ),
        const SizedBox(height: 20),
        PmsEyebrow(ui('EDITING')),
        Text(
          scope == 'shared'
              ? ui('Casa Rosa \u00b7 shared')
              : text(
                  optionalRows(
                    d['properties'],
                  ).firstWhere((p) => p['id'] == scope, orElse: () => {}),
                  'name',
                ),
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        Text(
          scope == 'shared'
              ? ui('Used as a fallback for every apartment.')
              : ui('Overrides shared answers for this apartment.'),
        ),
        Text(
          ui(
            '${optionalObject(optionalObject(d['scopes'])[scope]).values.where((v) => v.toString().trim().isNotEmpty).length} of ${optionalRows(d['fields']).length} configured',
          ),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final category in optionalRows(
          d['fields'],
        ).map((f) => text(f, 'category')).toSet()) ...[
          const SizedBox(height: 16),
          PmsEyebrow(category),
          PmsColumns([
            for (final f in optionalRows(
              d['fields'],
            ).where((f) => f['category'] == category))
              PmsField(
                text(f, 'label'),
                status: inputs[text(f, 'key')]!.text.trim().isEmpty
                    ? 'Not configured'
                    : 'Configured',
                controller: inputs[text(f, 'key')]!,
                lines: 3,
                onChanged: (_) {
                  setState(() => saved = false);
                },
              ),
          ], columns: 2),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: PmsButton(
            saved ? ui('Saved') : ui('Save knowledge'),
            primary: true,
            onPressed: busy || saved ? null : save,
          ),
        ),
        const SizedBox(height: 24),
        PmsEyebrow(ui('AUTHORITY')),
        for (final entry in optionalObject(d['authority']).entries)
          PmsCard(
            child: Wrap(
              spacing: 20,
              children: [
                Text(text(optionalObject(entry.value), 'label')),
                SizedBox(
                  width: 260,
                  child: PmsSelect(
                    ui('Authority'),
                    value: text(optionalObject(entry.value), 'mode'),
                    items: {
                      'auto': ui('Handle automatically'),
                      'ask': ui('Ask owner'),
                      'never': ui('Never without owner'),
                    },
                    onChanged: busy
                        ? null
                        : (v) => perform(() async {
                            if (!widget.c.user.isOperator) {
                              throw StateError('Operator access required');
                            }
                            await widget.c.mutate(
                              'PATCH',
                              '/api/authority/${idPath(entry.key)}',
                              {'mode': v},
                            );
                            if (mounted) {
                              setState(
                                () => optionalObject(entry.value)['mode'] = v,
                              );
                            }
                          }),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class OperatingModePage extends StatefulWidget {
  const OperatingModePage({super.key, required this.c});
  final PmsController c;
  @override
  State<OperatingModePage> createState() => _OperatingModePageState();
}

class _OperatingModePageState extends State<OperatingModePage>
    with PmsActions<OperatingModePage> {
  late final preferences = <String, bool>{
    for (final key in events.keys)
      key: widget.c.object('preferences')[key] != false,
  };
  static const events = {
    'new_booking': 'New booking',
    'cancellation': 'Cancellation',
    'turnover_risk': 'Same-day turnover risk',
    'registration_due': 'Registration due',
    'cleaner_late': 'Cleaner late',
    'maintenance_risk': 'Maintenance risk',
  };
  static const descriptions = {
    'observe':
        'Real data may be analyzed, but Delvane records proposed actions instead of changing operational records.',
    'assist':
        'Delvane prepares actions. A human approval is required before operational changes.',
    'autonomous':
        'Only actions explicitly allowed by Train Delvane may execute automatically. High-risk authority rules remain blocked.',
  };
  Future<void> mode(String mode) async {
    if (widget.c.user.role != 'owner') return;
    if (mode == 'autonomous' &&
        !await pmsConfirm(
          context,
          ui('Enable AUTONOMOUS mode?'),
          ui('Only Delvane actions marked Automatic can execute.'),
        )) {
      return;
    }
    if (!mounted) return;
    final ok = await perform(() async {
      await widget.c.mutate('PATCH', '/api/organization/mode', {'mode': mode});
    });
    if (ok && mounted) await widget.c.load();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c,
        current = text(c.object('organization'), 'operating_mode', 'observe');
    final memory = c.object('memory');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsEyebrow(ui('PRODUCTION PILOT CONTROL')),
        PmsPageTitle(ui('Simulation / Operating mode')),
        errors(),
        const SizedBox(height: 24),
        Text(ui('Current mode: $current')),
        const SizedBox(height: 16),
        PmsColumns([
          for (final e in descriptions.entries)
            PmsCard(
              color: current == e.key ? const Color(0xFFFFF3AD) : PmsStyle.soft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.key.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(e.value),
                  const SizedBox(height: 16),
                  if (c.user.role == 'owner')
                    PmsButton(
                      current == e.key ? ui('Current mode') : ui('Select'),
                      onPressed: busy || current == e.key
                          ? null
                          : () => mode(e.key),
                    ),
                ],
              ),
            ),
        ], columns: 3),
        const SizedBox(height: 24),
        PmsEyebrow(ui('SIMULATION LEDGER')),
        PmsColumns([
          for (final entry in {
            'simulated': 'Simulated',
            'awaiting_approval': 'Awaiting approval',
            'executed': 'Executed',
          }.entries)
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.value),
                  Text(
                    '${c.rows('actions').where((a) => a['status'] == entry.key).length}',
                    style: const TextStyle(fontFamily: 'Georgia', fontSize: 28),
                  ),
                ],
              ),
            ),
        ], columns: 3),
        const SizedBox(height: 16),
        for (final a in c.rows('actions').take(30))
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PmsBadge(text(a, 'status')),
                Text(
                  text(
                    optionalObject(a['payload']),
                    'label',
                    text(
                      a,
                      'summary',
                      text(a, 'action_type').replaceAll('_', ' '),
                    ),
                  ),
                ),
                Text('${text(a, 'created_at')} · ${text(a, 'operating_mode')}'),
                if (a['reversible'] == 1 &&
                    a['status'] == 'executed' &&
                    a['undone_at'] == null)
                  PmsButton(
                    ui('Undo'),
                    onPressed: busy
                        ? null
                        : () async {
                            final ok = await perform(() async {
                              if (!c.user.isOperator) {
                                throw StateError('Operator access required');
                              }
                              await c.mutate(
                                'POST',
                                '/api/rosa/actions/${idPath(text(a, 'id'))}/undo',
                              );
                            });
                            if (ok && mounted) await c.load();
                          },
                  ),
              ],
            ),
          ),
        if (c.rows('actions').isEmpty) PmsEmpty(ui('No actions recorded.')),
        const SizedBox(height: 24),
        PmsEyebrow(ui('NOTIFICATIONS')),
        for (final e in events.entries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(e.value),
            value: preferences[e.key],
            onChanged: busy
                ? null
                : (v) => setState(() => preferences[e.key] = v!),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: PmsButton(
            ui('Save notifications'),
            onPressed: busy
                ? null
                : () => perform(() async {
                    await c.mutate('PUT', '/api/notifications/preferences', {
                      'preferences': preferences,
                    });
                  }),
          ),
        ),
        const SizedBox(height: 24),
        PmsEyebrow(ui('STRUCTURED BUSINESS MEMORY')),
        Text(ui('Facts, not hidden model memory.')),
        for (final m in optionalRows(memory['business']))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text(m, 'memory_key').replaceAll('_', ' ')),
            subtitle: Text(
              '${text(optionalObject(m['value']), 'note', text(optionalObject(m['value']), 'topic', jsonEncode(m['value'])))}\n'
              '${text(m, 'subject_type')} · confidence '
              '${m['confidence'] is num ? ((m['confidence'] as num) * 100).round() : 'Unknown'}%',
            ),
          ),
        for (final m in optionalRows(memory['guest_preferences']))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text(m, 'full_name')),
            subtitle: Text(
              '${text(m, 'preference_key')}: ${text(m, 'preference_value')} · ${text(m, 'source')}',
            ),
          ),
      ],
    );
  }
}
