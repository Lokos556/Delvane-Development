import 'package:material_ui/material_ui.dart';

import '../../core/localization/system_labels.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';
import 'guest_history_dialog.dart';

class ReceptionPage extends StatefulWidget {
  const ReceptionPage({
    super.key,
    required this.controller,
    required this.openStay,
  });
  final PmsController controller;
  final ValueChanged<String> openStay;
  @override
  State<ReceptionPage> createState() => _ReceptionPageState();
}

class _ReceptionPageState extends State<ReceptionPage>
    with PmsActions<ReceptionPage> {
  late final api = PmsWorkflows(widget.controller);
  final drafts = <String, TextEditingController>{};
  final search = TextEditingController();
  Json summary = {};
  List<Json> inbox = [], outbox = [], rules = [];
  String? selected;
  bool stale = false;
  bool get locked => busy || stale;
  int get tab => widget.controller.receptionTab;
  String t(String s) => widget.controller.t(s);
  String status(String code) => t(switch (code) {
    'new' => 'NEW',
    'analyzed' => 'UNDERSTOOD',
    'actioned' => 'ACTIONED',
    'replied' => 'REPLIED',
    'awaiting_approval' => t('Needs approval'),
    'simulated_sent' => t('Simulated'),
    'preview' => t('Preview'),
    'ready' => t('Ready'),
    'cancelled' => t('Cancelled'),
    _ => code,
  }).toUpperCase();
  @override
  void initState() {
    super.initState();
    api.authorize();
    final c = widget.controller;
    summary = c.object('summary');
    inbox = c.rows('inbox');
    outbox = c.rows('outbox');
    rules = c.rows('rules');
    selected = c.receptionSelected;
  }

  TextEditingController draft(String key, String initial) => drafts.putIfAbsent(
    key,
    () => TextEditingController(
      text: widget.controller.receptionDrafts[key] ?? initial,
    ),
  );
  Future<void> refresh({String? select}) async {
    final data = await api.object('/api/reception/summary');
    final messages = await api.rows('/api/inbox'),
        scheduled = await api.rows('/api/communications/outbox'),
        automation = await api.rows('/api/automation/rules');
    if (!mounted) return;
    setState(() {
      summary = data;
      inbox = messages;
      outbox = scheduled;
      rules = automation;
      stale = false;
      if (select != null) selected = select;
      if (!messages.any((m) => m['id'] == selected)) selected = null;
      widget.controller.receptionSelected = selected;
    });
  }

  Future<void> action(Future<void> Function() operation) async {
    if (locked) return;
    final ok = await perform(operation);
    if (ok) {
      setState(() => stale = true);
      await perform(() async {
        await refresh();
      });
    }
    // If refresh fails, action is not repeated automatically. Server state is authoritative.
  }

  Future<void> messageAction(Json m, String operation) async {
    final id = text(m, 'id'), key = 'inbox:${text(m, 'id')}';
    final controller = draft(key, text(m, 'draft_reply'));
    if (operation == 'draft' &&
        widget.controller.receptionDrafts.containsKey(key)) {
      if (!await pmsConfirm(
        context,
        ui('Generate smart reply'),
        ui('Replace your unsaved draft with a generated reply?'),
      )) {
        return;
      }
    }
    await action(() async {
      final response = await api.messageAction(
        id,
        operation,
        switch (operation) {
          'draft' => {'tone': 'warm_concise'},
          'save-draft' ||
          'apply' ||
          'reply-sent' => {'draft_reply': controller.text},
          _ => null,
        },
      );
      if (operation == 'draft') {
        controller.text = text(jsonObject(response), 'draft_reply');
        widget.controller.receptionDrafts.remove(key);
      }
      if (operation == 'save-draft') {
        widget.controller.receptionDrafts.remove(key);
      }
    });
  }

  Future<void> newMessage() async {
    final result = await showDialog<String>(
      useRootNavigator: false,
      context: context,
      barrierDismissible: false,
      builder: (_) => NewInboxMessage(api: api),
    );
    if (result != null) {
      await perform(() async {
        await refresh(select: result);
      });
    }
  }

  @override
  void dispose() {
    for (final d in drafts.values) {
      d.dispose();
    }
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width <= 760;
    final active =
        inbox.where((m) => m['id'] == selected).firstOrNull ??
        (!mobile && inbox.isNotEmpty ? inbox.first : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsColumns(
          [
            for (final entry in {
              'New messages': summary['new'],
              'Awaiting approval': summary['waiting_approval'],
              'Prepared touchpoints': summary['scheduled'],
              'Live external sending': 'OFF',
            }.entries)
              PmsCard(
                radius: 24,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t(entry.key).toUpperCase(),
                      style: const TextStyle(fontSize: 10, letterSpacing: .8),
                    ),
                    Text(
                      entry.key == 'Live external sending'
                          ? t('OFF')
                          : '${entry.value ?? 0}',
                      style: const TextStyle(
                        fontFamily: 'Georgia',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          columns: 4,
          mobileColumns: 2,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            PmsTabs(
              labels: [
                '${t('Inbox')} ${summary['new'] ?? 0}',
                '${t('Scheduled')} ${summary['scheduled'] ?? 0}',
                '${t('Automations')} ${summary['enabled_rules'] ?? 0}',
              ],
              selected: tab,
              onChanged: locked
                  ? (_) {}
                  : (v) => setState(() => widget.controller.receptionTab = v),
            ),
            PmsButton(
              '+ ${t('Paste message')}',
              small: true,
              onPressed: locked ? null : newMessage,
            ),
          ],
        ),
        const SizedBox(height: 16),
        errors(),
        if (stale)
          Text(
            ui(
              'The server accepted the action. Refresh data before making another change.',
            ),
          ),
        if (failure != null)
          PmsButton(
            ui('Refresh data'),
            onPressed: busy
                ? null
                : () => perform(() async {
                    await refresh();
                  }),
          ),
        if (tab == 0) ...[
          if (!mobile || active == null) inboxList(active, mobile),
          if (active != null && mobile) message(active, true),
        ],
        if (tab == 1) scheduled(),
        if (tab == 2) automations(),
      ],
    );
  }

  Widget inboxList(Json? active, bool mobile) {
    final query = search.text.trim().toLowerCase();
    final filtered = inbox
        .where(
          (m) =>
              '${m['sender_name']} ${m['subject']} ${m['body']} ${m['source']}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    final list = PmsCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: search,
            decoration: InputDecoration(hintText: ui('Search in mail')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          PmsEyebrow(ui('All inboxes')),
          if (filtered.isEmpty)
            PmsEmpty(
              ui('Your inbox is clear. Guest messages will appear here.'),
            ),
          for (final m in filtered)
            Material(
              color: active?['id'] == m['id']
                  ? PmsStyle.soft
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFFFF3BD),
                  foregroundColor: PmsStyle.ink,
                  child: Text(
                    text(m, 'sender_name', '?').isEmpty
                        ? '?'
                        : text(m, 'sender_name')[0].toUpperCase(),
                  ),
                ),
                title: Text(
                  text(m, 'sender_name', 'Guest'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      text(m, 'subject', 'Guest message'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      text(m, 'body'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${text(m, 'source')} · ${status(text(m, 'status'))}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                trailing: m['status'] == 'new'
                    ? const Text(
                        '●',
                        style: TextStyle(color: Color(0xFF8B5A00)),
                      )
                    : null,
                onTap: locked
                    ? null
                    : () => setState(() {
                        selected = text(m, 'id');
                        widget.controller.receptionSelected = selected;
                      }),
              ),
            ),
        ],
      ),
    );
    if (mobile) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (MediaQuery.sizeOf(context).height - 260).clamp(320, 1200),
        ),
        child: list,
      );
    }
    return LayoutBuilder(
      builder: (context, box) => SizedBox(
        height: (MediaQuery.sizeOf(context).height - 235).clamp(480, 1200),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: (box.maxWidth * .36).clamp(300.0, 365.0),
              child: PmsScrollPane(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (MediaQuery.sizeOf(context).height - 235).clamp(
                      480,
                      1200,
                    ),
                  ),
                  child: list,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PmsScrollPane(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (MediaQuery.sizeOf(context).height - 235).clamp(
                      480,
                      1200,
                    ),
                  ),
                  child: active == null
                      ? PmsCard(
                          child: Padding(
                            padding: EdgeInsets.only(top: 112),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Text(
                                ui('Select a message to review it.'),
                                style: TextStyle(
                                  fontFamily: 'Georgia',
                                  fontSize: 22,
                                ),
                              ),
                            ),
                          ),
                        )
                      : message(active, false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget message(Json m, bool mobile) {
    final a = m['analysis'] is Json
        ? jsonObject(m['analysis'])
        : <String, dynamic>{};
    final analyzed = a.isNotEmpty, key = 'inbox:${text(m, 'id')}';
    final editor = draft(key, text(m, 'draft_reply', text(a, 'draft_reply')));
    final guest = m['guest_context'];
    return PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mobile)
            Align(
              alignment: Alignment.centerLeft,
              child: PmsButton(
                ui('‹ Back to inbox'),
                small: true,
                onPressed: () => setState(() {
                  selected = null;
                  widget.controller.receptionSelected = null;
                }),
              ),
            ),
          PmsEyebrow('${text(m, 'source')} · ${status(text(m, 'status'))}'),
          Text(
            text(m, 'sender_name', 'Guest'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          Text(
            '${text(m, 'property_name')} · ${text(m, 'reservation_arrival')} → ${text(m, 'reservation_departure')}',
          ),
          Wrap(
            spacing: 8,
            children: [
              if (m['reservation_id'] != null)
                PmsButton(
                  ui('Open stay'),
                  small: true,
                  onPressed: () => widget.openStay(text(m, 'reservation_id')),
                ),
              PmsButton(
                ui('Archive'),
                small: true,
                onPressed: locked
                    ? null
                    : () => action(() async {
                        await api.messageAction(text(m, 'id'), 'archive');
                      }),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (guest is Json)
            PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PmsEyebrow(ui('GUEST CONTEXT')),
                  Text(ui('${guest['stays']} stays')),
                  for (final pref in optionalRows(guest['preferences']))
                    Text(text(pref, 'preference_value')),
                  if (m['reservation_id'] != null)
                    PmsButton(
                      ui('View guest history'),
                      onPressed: () => showDialog<void>(
                        useRootNavigator: false,
                        context: context,
                        builder: (_) =>
                            GuestHistoryDialog(api: api, id: text(guest, 'id')),
                      ),
                    ),
                ],
              ),
            ),
          PmsEyebrow(t('Guest message')),
          PmsCard(
            color: PmsStyle.soft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text(m, 'subject')),
                const SizedBox(height: 8),
                SelectableText(text(m, 'body')),
              ],
            ),
          ),
          if (!analyzed) ...[
            const SizedBox(height: 16),
            Text(
              ui('Let Delvane understand this first.'),
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            Text(
              ui(
                'Structured facts and actions stay deterministic. Luna is optional.',
              ),
            ),
            PmsButton(
              t('Analyze'),
              primary: true,
              onPressed: locked ? null : () => messageAction(m, 'analyze'),
            ),
          ] else ...[
            const SizedBox(height: 16),
            PmsEyebrow(ui('ROSA UNDERSTOOD')),
            if (a['extracted'] is Json)
              analysisChips(jsonObject(a['extracted'])),
            if ((a['unresolved'] as List? ?? []).isNotEmpty) ...[
              Text(ui('Needs confirmation')),
              for (final issue in a['unresolved'] as List)
                Text(issue.toString()),
            ],
            PmsEyebrow(t('Delvane draft')),
            Text(
              m['draft_provider'] == 'openai' ? t('Luna') : t('Local'),
              style: const TextStyle(fontSize: 11),
            ),
            Text(
              ui(
                'Delvane is not connected to a live guest-messaging channel yet. Sending remains manual or simulated.',
              ),
            ),
            TextField(
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              controller: editor,
              maxLines: 6,
              onChanged: (v) => widget.controller.receptionDrafts[key] = v,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PmsButton(
                  t('Generate smart reply'),
                  onPressed: locked ? null : () => messageAction(m, 'draft'),
                ),
                PmsButton(
                  t('Save'),
                  onPressed: locked
                      ? null
                      : () => messageAction(m, 'save-draft'),
                ),
                if (m['status'] == 'analyzed')
                  PmsButton(
                    t('Apply actions'),
                    onPressed: locked ? null : () => messageAction(m, 'apply'),
                  ),
                if (['analyzed', 'actioned'].contains(m['status']))
                  PmsButton(
                    t('Mark sent externally'),
                    primary: true,
                    onPressed: locked
                        ? null
                        : () => messageAction(m, 'reply-sent'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget analysisChips(Json extracted) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      if (extracted['property_name'] != null)
        PmsBadge(text(extracted, 'property_name'), localizeLabel: false),
      if (extracted['arrival_time'] != null)
        PmsBadge(ui('Arrival ${text(extracted, 'arrival_time')}')),
      if (extracted['guest_count'] != null)
        PmsBadge(ui('${extracted['guest_count']} guests')),
      for (final request in extracted['special_requests'] as List? ?? [])
        PmsBadge(request.toString(), localizeLabel: false),
    ],
  );
  Widget scheduled() {
    final active = outbox.where((x) => x['status'] != 'cancelled').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsCard(
          color: PmsStyle.soft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('Communication sandbox'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                ui(
                  'Delvane is not connected to a live guest-messaging channel yet. Sending remains manual or simulated.',
                ),
              ),
            ],
          ),
        ),
        if (active.isEmpty)
          PmsEmpty(t('No scheduled guest communication yet.')),
        for (final x in active)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: scheduledCard(x),
          ),
      ],
    );
  }

  Widget scheduledCard(Json x) {
    final key = 'outbox:${text(x, 'id')}', id = idPath(text(x, 'id'));
    final editor = draft(key, text(x, 'body'));
    return PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PmsEyebrow(
            x['rule_label'] == null
                ? text(x, 'subject', t('Guest message'))
                : automationText(x, 'rule_label'),
          ),
          Text(
            '${text(x, 'guest_name', 'Guest')} · ${text(x, 'property_name')}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          Text(uiDateTime(text(x, 'scheduled_for', t('Unscheduled')))),
          Align(
            alignment: Alignment.centerLeft,
            child: PmsBadge(status(text(x, 'status')), tone: text(x, 'status')),
          ),
          TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: editor,
            maxLines: 4,
            onChanged: (v) => widget.controller.receptionDrafts[key] = v,
          ),
          Text(ui('No live external send'), style: TextStyle(fontSize: 12)),
          if (widget.controller.receptionDrafts.containsKey(key))
            Text(
              ui(
                'Unsaved draft. Save before approving or simulating this text.',
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PmsButton(
                t('Save'),
                onPressed: locked
                    ? null
                    : () => action(() async {
                        await api.change(
                          'PATCH',
                          '/api/communications/outbox/$id',
                          {'body': editor.text},
                        );
                        widget.controller.receptionDrafts.remove(key);
                      }),
              ),
              if (![
                'ready',
                'simulated_sent',
                'cancelled',
              ].contains(x['status']))
                PmsButton(
                  t('Approve'),
                  onPressed: locked
                      ? null
                      : () => action(() async {
                          await api.change(
                            'POST',
                            '/api/communications/outbox/$id/approve',
                          );
                        }),
                ),
              if (x['status'] != 'cancelled') ...[
                PmsButton(
                  t('Simulate send'),
                  primary: true,
                  onPressed: locked
                      ? null
                      : () => action(() async {
                          await api.change(
                            'POST',
                            '/api/communications/outbox/$id/simulate-send',
                          );
                        }),
                ),
                PmsButton(
                  t('Cancel'),
                  onPressed: locked
                      ? null
                      : () => action(() async {
                          await api.change(
                            'PATCH',
                            '/api/communications/outbox/$id',
                            {'status': 'cancelled'},
                          );
                        }),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget automations() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PmsEyebrow(ui('GUEST JOURNEY AUTOMATION')),
      Text(
        ui('Delvane prepares the next touchpoint before you think about it.'),
        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
      ),
      Text(
        ui(
          'Rules create drafts only. OBSERVE previews, ASSIST requests approval, and AUTONOMOUS can prepare approved items. No external channel is connected yet.',
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: PmsButton(
          t('Run Delvane scheduler'),
          primary: true,
          onPressed: locked
              ? null
              : () => action(() async {
                  await api.change('POST', '/api/automation/run');
                  widget.controller.receptionTab = 1;
                }),
        ),
      ),
      const SizedBox(height: 16),
      PmsColumns([
        for (final rule in rules)
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PmsEyebrow(automationTrigger(text(rule, 'trigger_key'))),
                Text(
                  automationText(rule, 'label'),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(automationText(rule, 'description')),
                Row(
                  children: [
                    Expanded(child: Text(t('Enabled'))),
                    PmsToggle(
                      value: rule['enabled'] == true || rule['enabled'] == 1,
                      onChanged: locked
                          ? null
                          : (value) => action(() async {
                              await api.change(
                                'PATCH',
                                '/api/automation/rules/${idPath(text(rule, 'id'))}',
                                {'enabled': value},
                              );
                            }),
                    ),
                  ],
                ),
                PmsSelect(
                  t('Authority'),
                  value: text(rule, 'authority_mode'),
                  items: {
                    'ask': ui('Ask owner'),
                    'auto': ui('Automatic'),
                    'never': ui('Never'),
                  },
                  onChanged: locked
                      ? null
                      : (value) => action(() async {
                          await api.change(
                            'PATCH',
                            '/api/automation/rules/${idPath(text(rule, 'id'))}',
                            {'authority_mode': value},
                          );
                        }),
                ),
                Text(ui('${rule['run_count']} evaluations')),
              ],
            ),
          ),
      ], columns: 2),
    ],
  );
}

class NewInboxMessage extends StatefulWidget {
  const NewInboxMessage({super.key, required this.api});
  final PmsWorkflows api;
  @override
  State<NewInboxMessage> createState() => _NewInboxMessageState();
}

class _NewInboxMessageState extends State<NewInboxMessage>
    with PmsActions<NewInboxMessage> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in ['sender_name', 'sender_contact', 'subject', 'body'])
      key: TextEditingController(),
  };
  List<Json>? properties, reservations;
  String source = 'Direct email', property = '', reservation = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await perform(() async {
      properties = await widget.api.rows('/api/properties');
      reservations = await widget.api.rows('/api/reservations');
    });
  }

  @override
  void dispose() {
    for (final f in fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: PmsModal(
      title: ui('Paste a guest message'),
      eyebrow: ui('NEW INBOX ITEM'),
      canClose: !busy,
      width: 760,
      actions: [
        PmsButton(
          ui('Cancel'),
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        PmsButton(
          ui('Add to Inbox'),
          primary: true,
          onPressed: busy || properties == null || reservations == null
              ? null
              : () async {
                  if (!form.currentState!.validate()) return;
                  String? id;
                  final ok = await perform(() async {
                    final out = jsonObject(
                      await widget.api.change('POST', '/api/inbox', {
                        'source': source,
                        'property_id': property.isEmpty ? null : property,
                        'reservation_id': reservation.isEmpty
                            ? null
                            : reservation,
                        for (final f in fields.entries) f.key: f.value.text,
                      }),
                    );
                    id = text(out, 'id');
                  });
                  if (ok && context.mounted) Navigator.pop(context, id);
                },
        ),
      ],
      child: Form(
        key: form,
        child: Column(
          children: [
            errors(),
            if ((properties == null || reservations == null) && !busy)
              PmsButton(ui('Retry'), onPressed: load),
            if (properties != null) ...[
              PmsColumns([
                PmsSelect(
                  ui('Source'),
                  value: source,
                  items: {
                    for (final v in [
                      'Direct email',
                      'Booking.com',
                      'Szallas.hu',
                      'Phone / manual',
                    ])
                      v: v,
                  },
                  onChanged: busy ? null : (v) => setState(() => source = v),
                ),
                PmsSelect(
                  ui('Property'),
                  value: property,
                  items: {
                    '': ui('Let Delvane detect it'),
                    for (final p in properties!) text(p, 'id'): text(p, 'name'),
                  },
                  onChanged: busy ? null : (v) => setState(() => property = v),
                ),
                PmsField(
                  ui('Sender name'),
                  controller: fields['sender_name']!,
                  hint: ui('Guest name'),
                ),
                PmsField(
                  ui('Contact'),
                  controller: fields['sender_contact']!,
                  hint: ui('Email or phone, optional'),
                ),
              ], columns: 2),
              PmsSelect(
                ui('Link to existing reservation'),
                value: reservation,
                items: {
                  '': ui('New inquiry / not linked'),
                  for (final r in reservations ?? <Json>[])
                    if (r['status'] == 'confirmed')
                      text(
                        r,
                        'id',
                      ): '${text(r, 'guest_name')} · ${text(r, 'property_name')} · ${text(r, 'arrival_date')}',
                },
                onChanged: busy ? null : (v) => setState(() => reservation = v),
              ),
              PmsField(
                ui('Subject'),
                controller: fields['subject']!,
                hint: ui('Optional'),
              ),
              PmsField(
                ui('Message'),
                controller: fields['body']!,
                lines: 5,
                required: true,
                hint: ui("Paste the guest's message here…"),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
