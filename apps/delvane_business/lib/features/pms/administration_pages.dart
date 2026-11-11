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
    if (!c.user.isOperator) return const PmsEmpty('No access');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PmsEyebrow('SECURITY'),
        const Text(
          'Security Center',
          style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 20),
        const PmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Production-shaped, still local.',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              Text(
                'Tenant isolation, server-side roles, scrypt passwords, hashed session tokens, CSRF protection, security headers and audit evidence are active. MFA and production HTTPS are intentionally not claimed as complete in this local build.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PmsColumns([
          for (final e in {
            'active_users': 'Active users',
            'email_verified_users': 'Verified email',
            'mfa_enabled_users': 'MFA enabled',
          }.entries)
            PmsCard(
              child: Column(
                children: [
                  Text(
                    '${sec[e.key] ?? 0}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(e.value),
                ],
              ),
            ),
        ], columns: 3),
        const SizedBox(height: 24),
        const PmsEyebrow('ACTIVE SESSIONS'),
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
                  'Last seen ${text(s, 'last_seen_at')} · expires ${text(s, 'expires_at')}',
                ),
                if (c.user.role == 'owner')
                  Align(
                    alignment: Alignment.centerRight,
                    child: PmsButton(
                      'Revoke session',
                      onPressed: c.saving
                          ? null
                          : () async {
                              if (await pmsConfirm(
                                    context,
                                    'Revoke this active session?',
                                    'The selected session will be signed out.',
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
          const PmsEmpty('No active sessions.'),
        const SizedBox(height: 24),
        PmsColumns([
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PmsEyebrow('EVIDENCE'),
                const Text(
                  'Audit trail',
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
                const PmsEyebrow('PRIVACY'),
                const Text(
                  'Data retention',
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
        const PmsEyebrow('TRAIN DELVANE'),
        const Text(
          'Train Delvane',
          style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700),
        ),
        const Text(
          'Shared knowledge applies across properties. Property-specific knowledge overrides shared guidance.',
        ),
        const SizedBox(height: 24),
        errors(),
        PmsSelect(
          'Knowledge scope',
          value: scope,
          items: {
            'shared': 'Shared knowledge',
            for (final p in optionalRows(d['properties']))
              text(p, 'id'): text(p, 'name'),
          },
          onChanged: busy
              ? null
              : (v) async {
                  if (!await pmsConfirm(
                        context,
                        'Change knowledge scope?',
                        'Unsaved changes in this scope will be discarded.',
                      ) ||
                      !mounted) {
                    return;
                  }
                  setState(() {
                    scope = v;
                    populate();
                    saved = false;
                  });
                },
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
                controller: inputs[text(f, 'key')]!,
                lines: 3,
                onChanged: (_) {
                  if (saved) setState(() => saved = false);
                },
              ),
          ], columns: 2),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: PmsButton(
            saved ? 'Saved' : 'Save knowledge',
            primary: true,
            onPressed: busy || saved ? null : save,
          ),
        ),
        const SizedBox(height: 24),
        const PmsEyebrow('AUTHORITY'),
        for (final entry in optionalObject(d['authority']).entries)
          PmsCard(
            child: Wrap(
              spacing: 20,
              children: [
                Text(text(optionalObject(entry.value), 'label')),
                SizedBox(
                  width: 260,
                  child: PmsSelect(
                    'Authority',
                    value: text(optionalObject(entry.value), 'mode'),
                    items: const {
                      'auto': 'Handle automatically',
                      'ask': 'Ask owner',
                      'never': 'Never without owner',
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
          'Enable AUTONOMOUS mode?',
          'Only Delvane actions marked Automatic can execute.',
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
        const PmsEyebrow('PRODUCTION PILOT CONTROL'),
        const Text(
          'Simulation / Operating mode',
          style: TextStyle(fontSize: 38, fontWeight: FontWeight.w700),
        ),
        errors(),
        const SizedBox(height: 24),
        Text('Current mode: $current'),
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
                      current == e.key ? 'Current mode' : 'Select',
                      onPressed: busy || current == e.key
                          ? null
                          : () => mode(e.key),
                    ),
                ],
              ),
            ),
        ], columns: 3),
        const SizedBox(height: 24),
        const PmsEyebrow('SIMULATION LEDGER'),
        for (final a in c.rows('actions').take(30))
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PmsBadge(text(a, 'status')),
                Text(text(a, 'summary', text(a, 'action_type'))),
                Text(text(a, 'created_at')),
                if (a['reversible'] == 1 &&
                    a['status'] == 'executed' &&
                    a['undone_at'] == null)
                  PmsButton(
                    'Undo',
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
        if (c.rows('actions').isEmpty) const PmsEmpty('No actions recorded.'),
        const SizedBox(height: 24),
        const PmsEyebrow('NOTIFICATIONS'),
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
            'Save notifications',
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
        const PmsEyebrow('STRUCTURED BUSINESS MEMORY'),
        const Text('Facts, not hidden model memory.'),
        for (final m in optionalRows(memory['business']))
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(text(m, 'memory_key').replaceAll('_', ' ')),
            subtitle: Text(
              text(
                optionalObject(m['value']),
                'note',
                text(optionalObject(m['value']), 'topic'),
              ),
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
