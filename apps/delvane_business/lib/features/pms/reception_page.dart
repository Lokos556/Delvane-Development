import 'package:material_ui/material_ui.dart';

import '../../core/localization/system_labels.dart';
import '../../core/network/api_client.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'operational_visuals.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';
import 'guest_history_dialog.dart';
import 'guest_link_picker.dart';
import 'guest_delivery_status.dart';
import 'actual_stay_controls.dart';
import 'scoped_search.dart';

class ReceptionPage extends StatefulWidget {
  const ReceptionPage({
    super.key,
    required this.controller,
    required this.openStay,
  }) : conversation = null,
       onConversationChanged = null;
  const ReceptionPage._conversation({
    required this.controller,
    required this.openStay,
    required this.conversation,
    required this.onConversationChanged,
  });
  final PmsController controller;
  final ValueChanged<String> openStay;
  final Json? conversation;
  final VoidCallback? onConversationChanged;
  @override
  State<ReceptionPage> createState() => _ReceptionPageState();
}

class _ReceptionPageState extends State<ReceptionPage>
    with PmsActions<ReceptionPage> {
  late final api = PmsWorkflows(widget.controller);
  final drafts = <String, TextEditingController>{};
  late final search = TextEditingController(
    text: widget.controller.receptionQuery,
  );
  PmsController get c => widget.controller;
  Json get summary => c.object('summary');
  List<Json> get inbox => c.auth.offline ? [] : c.rows('inbox');
  List<Json> get outbox => c.rows('outbox');
  List<Json> get rules => c.rows('rules');
  bool stale = false;
  bool unreadOnly = false;
  bool get locked =>
      busy || stale || c.auth.offline || c.auth.user?.isOperator != true;
  int get tab => c.receptionTab;
  String get section => PmsController.receptionSections[tab];
  String? get selected => c.receptionSelected;
  String t(String s) => widget.controller.t(s);
  bool get usesConversationRoute =>
      MediaQuery.sizeOf(context).width <= 760 &&
      Theme.of(context).platform == TargetPlatform.android;
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
  TextEditingController draft(String key, String initial) => drafts.putIfAbsent(
    key,
    () => TextEditingController(
      text: widget.controller.receptionDrafts[key] ?? initial,
    ),
  );
  Future<void> refresh({String? select}) async {
    final requiredSection = widget.conversation == null ? section : 'inbox';
    await c.refreshReception();
    if (!mounted) return;
    final cause =
        c.sectionErrors[requiredSection] ??
        c.sectionErrors['summary'] ??
        c.error;
    if (cause != null) throw ApiException(cause);
    if (!c.hasSection(requiredSection) || c.auth.offline) {
      throw const ApiException(
        'Reception is unavailable. Try again when connected.',
      );
    }
    setState(() {
      stale = false;
      if (select != null) c.receptionSelected = select;
      if (c.hasSection('inbox') && !inbox.any((m) => m['id'] == selected)) {
        c.receptionSelected = null;
      }
    });
  }

  Future<void> action(Future<void> Function() operation) async {
    if (locked) return;
    final ok = await perform(operation);
    if (ok && mounted) {
      widget.onConversationChanged?.call();
      setState(() => stale = true);
      await perform(() async {
        await refresh();
      });
    }
    // If refresh fails, action is not repeated automatically. Server state is authoritative.
  }

  Future<void> openMessage(Json row) async {
    final id = text(row, 'id');
    if (!usesConversationRoute) {
      setState(() {
        c.receptionSelected = id;
      });
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    var changed = false;
    final theme = Theme.of(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Theme(
          data: theme,
          child: ReceptionPage._conversation(
            controller: widget.controller,
            openStay: widget.openStay,
            conversation: row,
            onConversationChanged: () => changed = true,
          ),
        ),
      ),
    );
    if (changed && mounted) {
      setState(() => stale = true);
      await perform(() => refresh());
    }
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
      if (!mounted) return;
      final openRoute = usesConversationRoute;
      final updated = await perform(() async {
        await refresh(select: openRoute ? null : result);
      });
      if (updated && mounted && openRoute) {
        final row = inbox.where((row) => row['id'] == result).firstOrNull;
        if (row != null) await openMessage(row);
      }
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
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) => workspace(context),
  );

  Widget workspace(BuildContext context) {
    if (widget.conversation case final conversation?) {
      final id = text(conversation, 'id');
      final active = inbox.where((m) => m['id'] == id).firstOrNull;
      return PopScope(
        canPop: !busy,
        child: Scaffold(
          appBar: AppBar(title: Text(t('Inbox'))),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                errors(),
                if (stale || failure != null)
                  PmsButton(
                    t('Refresh data'),
                    onPressed: busy ? null : () => perform(refresh),
                  ),
                if (c.auth.offline)
                  PmsEmpty(
                    t('Reception is unavailable. Try again when connected.'),
                  )
                else if (active != null)
                  message(active, false)
                else if (!c.hasSection('inbox') && c.refreshing)
                  skeleton(t('Loading conversations…'))
                else
                  PmsEmpty(t('This message is no longer in the inbox.')),
              ],
            ),
          ),
        ),
      );
    }
    final mobile = MediaQuery.sizeOf(context).width <= 760;
    final active =
        inbox.where((m) => m['id'] == selected).firstOrNull ??
        (!mobile && inbox.isNotEmpty ? inbox.first : null);
    return LayoutBuilder(
      builder: (context, box) {
        final folderRail = box.maxWidth >= 950;
        final folders = navigation(folderRail);
        final main = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!folderRail) ...[folders, const SizedBox(height: 10)],
            if (c.auth.offline) ...[
              PmsEmpty(
                t('Reception is unavailable. Try again when connected.'),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: PmsButton(
                  t('Retry'),
                  onPressed: busy ? null : () => perform(refresh),
                ),
              ),
            ] else ...[
              toolbar(),
              errors(),
              if (stale)
                Text(
                  t(
                    'The server accepted the action. Refresh data before making another change.',
                  ),
                ),
              if (stale || failure != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: PmsButton(
                    t('Refresh data'),
                    onPressed: busy ? null : () => perform(refresh),
                  ),
                ),
              if (!c.hasSection(section))
                if (c.sectionErrors[section] ?? c.error case final reason?)
                  loadFailure(reason)
                else
                  skeleton(
                    t(
                      tab == 0
                          ? 'Loading conversations…'
                          : 'Loading Reception…',
                    ),
                  )
              else ...[
                if (c.sectionErrors[section] ?? c.error case final reason?
                    when !stale)
                  loadFailure(reason),
                if (tab == 0) ...[
                  if (!mobile || active == null) inboxList(active, mobile),
                  if (active != null && mobile) message(active, true),
                ],
                if (tab == 1) scheduled(),
                if (tab == 2) automations(),
              ],
            ],
          ],
        );
        if (!folderRail) return main;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 168, child: folders),
            const SizedBox(width: 18),
            Expanded(child: main),
          ],
        );
      },
    );
  }

  Widget loadFailure(String reason) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      children: [
        Text(t(reason), style: const TextStyle(color: operationalRed)),
        TextButton(
          onPressed: busy ? null : () => perform(refresh),
          child: Text(t('Retry')),
        ),
      ],
    ),
  );

  Widget skeleton(String label) => Semantics(
    liveRegion: true,
    label: label,
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(label),
          ),
          for (var i = 0; i < 3; i++)
            Container(
              height: 60,
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: PmsStyle.panelLine)),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 15,
                    backgroundColor: PmsStyle.soft,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: 112, height: 9, color: PmsStyle.soft),
                        const SizedBox(height: 10),
                        FractionallySizedBox(
                          widthFactor: .64,
                          child: Container(height: 7, color: PmsStyle.soft),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget navigation(bool vertical) {
    final folders = [
      ('Inbox', summary['new'], Icons.inbox_outlined),
      ('Scheduled', summary['scheduled'], Icons.schedule),
      ('Automations', summary['enabled_rules'], Icons.tune),
    ];
    Widget destination(int index) {
      final (label, count, icon) = folders[index];
      final active = index == tab;
      final title = '${t(label)}${count == null ? '' : ' $count'}';
      final labelText = Text(
        title,
        textAlign: vertical ? TextAlign.start : TextAlign.center,
        style: TextStyle(
          color: active ? PmsStyle.ink : PmsStyle.muted,
          fontSize: 12,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      );
      return Semantics(
        selected: active,
        button: true,
        child: Material(
          color: vertical && active
              ? const Color(0xFFFFF2B4)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            onTap: locked ? null : () => c.selectReception(index),
            child: Container(
              constraints: const BoxConstraints(minHeight: 51),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: vertical
                  ? null
                  : BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          width: 3,
                          color: active ? PmsStyle.yellow : PmsStyle.panelLine,
                        ),
                      ),
                    ),
              child: Flex(
                direction: vertical ? Axis.horizontal : Axis.vertical,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: active ? PmsStyle.ink : PmsStyle.muted,
                  ),
                  SizedBox(width: vertical ? 9 : 0, height: vertical ? 0 : 4),
                  if (vertical) Expanded(child: labelText) else labelText,
                ],
              ),
            ),
          ),
        ),
      );
    }

    return vertical
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(7, 0, 0, 12),
                child: Text(
                  t('Reception'),
                  style: PmsStyle.pageTitle(context, size: 22),
                ),
              ),
              for (var i = 0; i < folders.length; i++) destination(i),
            ],
          )
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < folders.length; i++)
                  Expanded(child: destination(i)),
              ],
            ),
          );
  }

  Widget toolbar() => Row(
    children: [
      Expanded(
        child: ExpansionTile(
          title: Text(
            t('Reception overview'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          tilePadding: EdgeInsets.zero,
          shape: const Border(),
          collapsedShape: const Border(),
          children: [overview()],
        ),
      ),
      if (c.refreshing && c.hasSection(section))
        Tooltip(
          message: t('Synchronizing Reception…'),
          child: Semantics(
            label: t('Synchronizing Reception…'),
            child: const SizedBox.square(
              dimension: 13,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      const SizedBox(width: 6),
      IconButton(
        tooltip: t('Refresh'),
        onPressed: busy ? null : () => perform(refresh),
        icon: const Icon(Icons.refresh, size: 18),
      ),
    ],
  );

  Widget overview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ActualOccupancyPanel(c: widget.controller),
      MetricRail(
        metrics: [
          for (final entry in {
            'New messages': summary['new'],
            'Awaiting approval': summary['waiting_approval'],
            'Prepared touchpoints': summary['scheduled'],
            'Live external sending':
                switch (summary['external_sending_connected']) {
                  true => t('Connected'),
                  false => t('OFF'),
                  _ => '—',
                },
          }.entries)
            (t(entry.key).toUpperCase(), '${entry.value ?? '—'}'),
        ],
      ),
    ],
  );

  Widget inboxList(Json? active, bool mobile) {
    final query = search.text.trim().toLowerCase();
    final filtered = inbox
        .where((message) => !unreadOnly || message['status'] == 'new')
        .where(
          (m) =>
              '${m['sender_name']} ${m['subject']} ${m['body']} ${m['source']}'
                  .toLowerCase()
                  .contains(query),
        )
        .toList();
    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ScopedSearch(
                query: search,
                label: 'Search in mail',
                onChanged: (value) {
                  setState(() => c.receptionQuery = value);
                },
              ),
            ),
            IconButton(
              tooltip: t('Unread only'),
              icon: const Icon(Icons.mark_email_unread_outlined, size: 19),
              isSelected: unreadOnly,
              selectedIcon: const Icon(
                Icons.mark_email_unread,
                color: operationalAmber,
                size: 19,
              ),
              onPressed: () => setState(() => unreadOnly = !unreadOnly),
            ),
            PmsButton(
              '+ ${t('Paste message')}',
              small: true,
              onPressed: locked ? null : newMessage,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          PmsEmpty(
            ui(
              query.isNotEmpty || unreadOnly
                  ? 'No matching conversations.'
                  : 'Your inbox is clear. Guest messages will appear here.',
            ),
          ),
        for (final m in filtered) ...[
          Material(
            color: active?['id'] == m['id']
                ? PmsStyle.soft
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFFFF3BD),
                foregroundColor: PmsStyle.ink,
                child: Text(firstInitial(text(m, 'sender_name').trim())),
              ),
              title: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      text(m, 'sender_name', t('Guest')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: m['status'] == 'new'
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (received(m).isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      received(m),
                      style: const TextStyle(
                        color: PmsStyle.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text(m, 'subject', t('Guest message')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
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
                  ? Tooltip(
                      message: t('New message'),
                      child: const Icon(
                        Icons.circle,
                        size: 8,
                        color: operationalAmber,
                      ),
                    )
                  : null,
              onTap: locked ? null : () => openMessage(m),
            ),
          ),
          const Divider(height: 1, color: PmsStyle.panelLine),
        ],
      ],
    );
    if (mobile) return list;
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
                      ? PmsEmpty(
                          ui('Select a message to review it.'),
                          tall: true,
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

  String received(Json message) {
    final date = DateTime.tryParse(text(message, 'received_at'))?.toLocal();
    if (date == null) return '';
    final localizations = MaterialLocalizations.of(context);
    return isoDate(date) == isoDate(DateTime.now())
        ? localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date))
        : localizations.formatShortDate(date);
  }

  String firstInitial(String name) =>
      name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();

  Widget message(Json m, bool mobile) {
    final a = m['analysis'] is Json
        ? jsonObject(m['analysis'])
        : <String, dynamic>{};
    final analyzed = a.isNotEmpty, key = 'inbox:${text(m, 'id')}';
    final editor = draft(key, text(m, 'draft_reply', text(a, 'draft_reply')));
    final guest = m['guest_context'];
    return Padding(
      padding: EdgeInsets.fromLTRB(mobile ? 0 : 20, 8, mobile ? 0 : 12, 16),
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
                  c.receptionSelected = null;
                }),
              ),
            ),
          PmsEyebrow('${text(m, 'source')} · ${status(text(m, 'status'))}'),
          Text(
            text(m, 'subject', ui('Guest message')),
            style: const TextStyle(
              fontSize: 29,
              height: 1.12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            text(m, 'sender_name', ui('Guest')),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (m['received_at'] != null)
            Text(
              uiDateTime(text(m, 'received_at')),
              style: const TextStyle(color: PmsStyle.muted, fontSize: 12),
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
          const Divider(height: 26),
          SelectableText(
            text(m, 'body'),
            style: const TextStyle(fontSize: 15, height: 1.55),
          ),
          const Divider(height: 26),
          if (!analyzed) ...[
            const SizedBox(height: 16),
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
    final active = outbox
        .where((x) => x['status'] != 'cancelled' || x['delivery'] is Map)
        .toList();
    final configured =
        summary['guest_email_available'] == true ||
        active.any((x) => x['delivery'] is Map);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsCard(
          color: PmsStyle.soft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t(
                  configured
                      ? 'Guest invitation email'
                      : 'Communication sandbox',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                ui(
                  configured
                      ? 'Approval queues an invitation. Only a delivery receipt confirms delivery.'
                      : 'Delvane is not connected to a live guest-messaging channel yet. Sending remains manual or simulated.',
                ),
              ),
              if (configured)
                PmsButton(
                  ui('Refresh deliveries'),
                  onPressed: busy ? null : () => perform(() => refresh()),
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
    final invitation = x['message_type'] == 'guest_checkin_invitation';
    final delivery = optionalObject(x['delivery']);
    final canQueue = invitation && summary['guest_email_available'] == true;
    final editor = invitation ? null : draft(key, text(x, 'body'));
    final current = text(x, 'status');
    return PmsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PmsEyebrow(
            x['rule_label'] == null
                ? t(text(x, 'subject', 'Guest message'))
                : automationText(x, 'rule_label'),
          ),
          Text(
            '${text(x, 'guest_name', 'Guest')} · ${text(x, 'property_name')}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          Text(uiDateTime(text(x, 'scheduled_for', t('Unscheduled')))),
          if (delivery.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: PmsBadge(
                status(text(x, 'status')),
                tone: text(x, 'status'),
              ),
            ),
          if (invitation)
            Text(t(text(x, 'body')))
          else
            TextField(
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              controller: editor,
              maxLines: 4,
              onChanged: (v) => widget.controller.receptionDrafts[key] = v,
            ),
          if (invitation)
            GuestDeliveryStatus(
              delivery: delivery,
              invitationStatus: current,
              onRetry: locked
                  ? null
                  : () => action(() async {
                      await api.change(
                        'POST',
                        '/api/communications/outbox/$id/retry',
                      );
                    }),
            ),
          if (delivery.isEmpty && !canQueue)
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
              if (editor != null)
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
              if ((canQueue && current == 'ready' && delivery.isEmpty) ||
                  ![
                    'ready',
                    'simulated_sent',
                    'cancelled',
                  ].contains(x['status']))
                PmsButton(
                  t(canQueue ? 'Approve and queue email' : 'Approve'),
                  onPressed: locked
                      ? null
                      : () => action(() async {
                          await api.change(
                            'POST',
                            '/api/communications/outbox/$id/approve',
                          );
                        }),
                ),
              if (invitation
                  ? current == 'ready' && delivery.isEmpty && !canQueue
                  : current != 'cancelled')
                PmsButton(
                  t('Simulate send'),
                  primary: true,
                  onPressed: locked
                      ? null
                      : () => simulate(id, invitation: invitation),
                ),
              if (current != 'cancelled' &&
                  (!invitation || current != 'simulated_sent'))
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
          ),
        ],
      ),
    );
  }

  Future<void> simulate(String id, {required bool invitation}) async {
    List<Json> links = [];
    await action(() async {
      final response = await api.change(
        'POST',
        '/api/communications/outbox/$id/simulate-send',
      );
      if (invitation) links = optionalRows(jsonObject(response)['links']);
    });
    if (mounted && links.isNotEmpty) {
      await showGuestCheckinLinks(context, links, simulated: true);
    }
  }

  Widget automations() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        ui('Automation rules'),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      Text(
        ui(
          'The server prepares scheduled messages according to your operating mode and approval rules.',
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
      child: PmsForm(
        formKey: form,
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
