import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/auth/auth_controller.dart';
import '../workspace/workspace_models.dart';
import '../workspace/workspace_repository.dart';
import '../workspace/record_page.dart';
import 'pms_controller.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';
import 'reservation_dialogs.dart';
import 'reception_page.dart';
import 'pms_dialogs.dart';
import 'property_dialog.dart';
import 'team_page.dart';
import 'operations_pages.dart';
import 'operations_workflows.dart';
import 'administration_pages.dart';
import 'integrations_page.dart';
import 'guest_history_dialog.dart';

class PmsShell extends StatefulWidget {
  const PmsShell({super.key, required this.auth, this.initialPage});
  final AuthController auth;
  final PmsPage? initialPage;
  @override
  State<PmsShell> createState() => _PmsShellState();
}

class _PmsShellState extends State<PmsShell> with WidgetsBindingObserver {
  late final c = PmsController(widget.auth, initialPage: widget.initialPage);
  final scroll = ScrollController();
  final chat = TextEditingController();
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  int journeyPage = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(c.load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(c.load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    c.dispose();
    scroll.dispose();
    chat.dispose();
    super.dispose();
  }

  Future<void> record(
    RecordKind kind,
    String id, {
    String? reservationId,
  }) async {
    if (kind == RecordKind.property && c.user.isOperator) {
      await showDialog<void>(
        context: context,
        useRootNavigator: false,
        barrierDismissible: false,
        builder: (_) => PropertyWorkspace(
          c: c,
          id: id,
          openReservation: (id) => record(RecordKind.reservation, id),
          openCalendar: () => c.navigate(PmsPage.reservations),
        ),
      );
      return;
    }
    if (kind == RecordKind.reservation) {
      await showDialog<bool>(
        useRootNavigator: false,
        context: context,
        barrierDismissible: false,
        builder: (_) => ReservationWorkspace(
          api: PmsWorkflows(c),
          id: id,
          openTask: (taskId) =>
              record(RecordKind.cleaning, taskId, reservationId: id),
          openReception: () {
            c.receptionTab = 1;
            c.navigate(PmsPage.inbox);
          },
        ),
      );
      if (mounted && c.auth.user != null) await c.load();
      return;
    }
    // Preserve the verified record/permission implementation while its visual modal port continues.
    final repo = WorkspaceRepository(c.api);
    try {
      final workspace = await repo.load(c.user);
      if (reservationId != null) {
        await repo.detail(
          c.user,
          RecordRef(RecordKind.reservation, reservationId),
          workspace,
        );
      }
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RecordPage(
            auth: widget.auth,
            repository: repo,
            workspace: workspace,
            ref: RecordRef(kind, id),
            openReservation: (id) => record(RecordKind.reservation, id),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safeError(e))));
      }
    }
  }

  Future<void> newReservation([String? date]) async {
    final changed = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          ReservationEditor(api: PmsWorkflows(c), initialDate: date),
    );
    if (changed == true && mounted && c.auth.user != null) await c.load();
  }

  void go(PmsPage page) {
    Navigator.of(context).maybePop();
    unawaited(c.navigate(page));
  }

  Widget brand({bool mobile = false}) => Row(
    children: [
      Image.asset(
        PmsStyle.logo,
        width: mobile ? 36 : 48,
        height: mobile ? 36 : 48,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DELVANE',
              style: TextStyle(
                fontSize: mobile ? 18 : 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
              ),
            ),
            if (!mobile)
              const Text('INTELLIGENCE OS', style: TextStyle(fontSize: 10)),
          ],
        ),
      ),
    ],
  );
  Widget sidebar() => Container(
    width: 235,
    color: const Color(0xFFFFFDFA),
    padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        brand(),
        const SizedBox(height: 34),
        for (final page in c.primary)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: PmsButton(
              c.label(page),
              key: ValueKey('pms-nav-${page.name}'),
              primary: c.page == page,
              onPressed: () => c.navigate(page),
            ),
          ),
        const Spacer(),
        const Text(
          '\u25cf DELVANE ONLINE',
          style: TextStyle(fontSize: 9, letterSpacing: 1),
        ),
        const SizedBox(height: 12),
        PmsButton(
          '${c.user.organization}\n${c.user.name}  ?',
          onPressed: settings,
        ),
      ],
    ),
  );
  void settings() => showDialog<void>(
    useRootNavigator: false,
    context: context,
    builder: (context) => PmsModal(
      title: c.t('Workspace settings'),
      eyebrow: 'SETTINGS',
      width: 490,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(c.user.name),
          Text(c.user.role),
          const SizedBox(height: 18),
          for (final page in c.settings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PmsButton(
                c.label(page),
                onPressed: () {
                  Navigator.pop(context);
                  c.navigate(page);
                },
              ),
            ),
          PmsSelect(
            c.t('Language'),
            value: c.strings.language,
            items: {for (final l in c.strings.languages) l[0]: l[1]},
            onChanged: (v) {
              c.language(v);
              Navigator.pop(context);
            },
          ),
          PmsButton(
            c.t('Sign out'),
            onPressed: () {
              Navigator.pop(context);
              widget.auth.logout();
            },
          ),
        ],
      ),
    ),
  );
  Future<void> search() async {
    final input = TextEditingController();
    List<Json> results = [];
    String? error;
    if (!mounted) return;
    await showDialog<void>(
      useRootNavigator: false,
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => PmsModal(
          title: c.t('Search Delvane'),
          width: 720,
          child: Column(
            children: [
              TextField(
                controller: input,
                decoration: const InputDecoration(hintText: 'Search Delvane'),
                onSubmitted: (q) async {
                  try {
                    final response = jsonObject(
                      await c.api.get(
                        '/api/search?q=${Uri.encodeQueryComponent(q)}',
                      ),
                    );
                    if (context.mounted) {
                      update(() {
                        results = optionalRows(response['results']);
                        error = null;
                      });
                    }
                  } catch (e) {
                    if (context.mounted) update(() => error = safeError(e));
                  }
                },
              ),
              if (error != null) Text(error!),
              for (final r in results)
                ListTile(
                  title: Text(text(r, 'title')),
                  subtitle: Text(text(r, 'subtitle')),
                  onTap: () {
                    final kind = switch (text(r, 'type')) {
                      'reservation' => RecordKind.reservation,
                      'property' => RecordKind.property,
                      _ => null,
                    };
                    if (kind != null) {
                      Navigator.pop(context);
                      record(kind, text(r, 'id'));
                    } else if (r['type'] == 'guest') {
                      Navigator.pop(context);
                      showDialog<void>(
                        context: this.context,
                        useRootNavigator: false,
                        builder: (_) => GuestHistoryDialog(
                          api: PmsWorkflows(c),
                          id: text(r, 'id'),
                        ),
                      );
                    } else if (r['type'] == 'message') {
                      Navigator.pop(context);
                      c.receptionSelected = text(r, 'id');
                      c.receptionTab = 0;
                      c.navigate(PmsPage.inbox);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
    input.dispose();
  }

  Future<void> notifications() async {
    try {
      final body = jsonObject(await c.api.get('/api/notifications'));
      if (!mounted) return;
      await showDialog<void>(
        useRootNavigator: false,
        context: context,
        builder: (context) => PmsModal(
          title: c.t('Notifications'),
          width: 490,
          child: Column(
            children: [
              PmsButton(
                c.t('Mark all read'),
                onPressed: () async {
                  await c.api.post('/api/notifications/read-all', {});
                  if (context.mounted) Navigator.pop(context);
                  await c.load();
                },
              ),
              for (final r in optionalRows(body['items']))
                ListTile(
                  title: Text(text(r, 'title')),
                  subtitle: Text(text(r, 'detail')),
                  onTap: () async {
                    await c.api.post(
                      '/api/notifications/${idPath(text(r, 'id'))}/read',
                      {},
                    );
                    if (context.mounted) Navigator.pop(context);
                    await c.load();
                  },
                ),
              if (optionalRows(body['items']).isEmpty)
                PmsEmpty(c.t('Nothing new.')),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(safeError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
        if (c.user.isOperator) search();
      },
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
        if (c.user.isOperator) search();
      },
    },
    child: Focus(
      autofocus: true,
      child: Theme(
        data: pmsTheme(),
        child: AnimatedBuilder(
          animation: c,
          builder: (context, _) {
            final mobile = MediaQuery.sizeOf(context).width <= 760;
            final gap = mobile
                ? 10.0
                : (MediaQuery.sizeOf(context).width * .05).clamp(24.0, 80.0);
            return Scaffold(
              drawer: mobile
                  ? Drawer(width: 320, child: SafeArea(child: sidebar()))
                  : null,
              body: SafeArea(
                child: Row(
                  children: [
                    if (!mobile) sidebar(),
                    Expanded(
                      child: RawScrollbar(
                        controller: scroll,
                        thumbVisibility: true,
                        thumbColor: PmsStyle.yellow,
                        thickness: 9,
                        radius: const Radius.circular(6),
                        crossAxisMargin: 3,
                        child: SingleChildScrollView(
                          controller: scroll,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              gap,
                              mobile ? 12 : 14,
                              gap + 15,
                              100,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (mobile)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    child: SizedBox(
                                      height: 56,
                                      child: Row(
                                        children: [
                                          Builder(
                                            builder: (context) => PmsButton(
                                              '\u203a',
                                              small: true,
                                              onPressed: () => Scaffold.of(
                                                context,
                                              ).openDrawer(),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(child: brand(mobile: true)),
                                          if (c.user.isOperator)
                                            PmsButton(
                                              '\u203a',
                                              small: true,
                                              onPressed: search,
                                            ),
                                          PmsButton(
                                            '\u203a',
                                            small: true,
                                            onPressed: settings,
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 28),
                                    child: SizedBox(
                                      height: 41,
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          if (c.user.isOperator) ...[
                                            PmsButton(
                                              MediaQuery.sizeOf(context).width <
                                                      1100
                                                  ? c.t('Search')
                                                  : '\u2315  ${c.t('Search Delvane')}   Ctrl K',
                                              small: true,
                                              onPressed: search,
                                            ),
                                            PmsButton(
                                              '\u25cc  ${c.unread}',
                                              small: true,
                                              onPressed: notifications,
                                            ),
                                            PmsButton(
                                              c.mode.toUpperCase(),
                                              small: true,
                                              onPressed: () => c.navigate(
                                                PmsPage.simulation,
                                              ),
                                            ),
                                          ],
                                          PmsButton(
                                            '\u203a',
                                            small: true,
                                            onPressed: c.loading
                                                ? null
                                                : c.load,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (c.actionError != null)
                                  Text(
                                    c.actionError!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                if (c.loading)
                                  const Padding(
                                    padding: EdgeInsets.all(48),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else if (c.error != null)
                                  PmsCard(
                                    child: Column(
                                      children: [
                                        Text(c.error!),
                                        const Text(
                                          'No demo data has been substituted.',
                                        ),
                                        PmsButton('Retry', onPressed: c.load),
                                      ],
                                    ),
                                  )
                                else
                                  content(),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  Widget heading(String eyebrow, String title, String description) => Padding(
    padding: const EdgeInsets.only(bottom: 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PmsEyebrow(c.t(eyebrow)),
        Text(
          c.t(title),
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width <= 760 ? 38.4 : 57.6,
            height: 1.04,
            letterSpacing: -2,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(c.t(description)),
      ],
    ),
  );
  Widget content() {
    switch (c.page) {
      case PmsPage.today:
        return c.user.isOperator ? today() : workers(false);
      case PmsPage.schedule:
        return workers(true);
      case PmsPage.reservations:
        return calendar();
      case PmsPage.intelligence:
        return intelligence();
      case PmsPage.operations:
        return operations();
      case PmsPage.inbox:
        return ReceptionPage(
          controller: c,
          openStay: (id) => record(RecordKind.reservation, id),
        );
      default:
        return administration();
    }
  }

  Widget today() {
    final cmd = c.object('command'), dashboard = c.object('dashboard');
    final arrivals = optionalRows(cmd['arrivals']),
        cleaning = optionalRows(cmd['cleaning']),
        issues = optionalRows(cmd['maintenance']),
        registration = optionalRows(cmd['registration_risks']);
    final urgent =
        cmd['urgent_count'] ??
        registration.length +
            cleaning.where((r) => r['priority'] == 'high').length +
            issues.where((r) => r['severity'] == 'high').length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(text(cmd, 'date'), "Today's command center", '$urgent urgent'),
        LayoutBuilder(
          builder: (context, box) {
            final count = MediaQuery.sizeOf(context).width <= 720 ? 2 : 4;
            final w = (box.maxWidth - 12 * (count - 1)) / count;
            final metrics = {
              'Arrivals': arrivals.length,
              'Departures': optionalRows(cmd['departures']).length,
              'Turnovers': cleaning
                  .where((r) => r['deadline_time'] != null)
                  .length,
              'Registration issues': registration.length,
            };
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final e in metrics.entries)
                  SizedBox(
                    width: w,
                    height: 66,
                    child: PmsCard(
                      radius: 24,
                      shadow: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      color: PmsStyle.soft,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              c.t(e.key),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${e.value}',
                            style: const TextStyle(
                              fontFamily: 'Georgia',
                              fontSize: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        if (registration.isNotEmpty) ...[
          PmsCard(
            radius: 22,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PmsEyebrow(c.t('Guest registration').toUpperCase()),
                Text(
                  c.t('Registration needs attention'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final r in registration)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const PmsBadge('!', tone: 'attention'),
                    title: Text(
                      text(r, 'guest_name'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${text(r, 'property_name')} \u00b7 ${c.t('arrives today')} \u00b7 ${text(r, 'arrival_time')}',
                    ),
                    trailing: MediaQuery.sizeOf(context).width > 720
                        ? const Text('Open stay \u2192')
                        : null,
                    onTap: () => record(RecordKind.reservation, text(r, 'id')),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 22),
        ],
        PmsColumns([
          queue(
            'Arrivals',
            arrivals,
            (r) => record(RecordKind.reservation, text(r, 'id')),
            time: 'arrival_time',
            title: 'guest_name',
          ),
          queue(
            'Turnovers',
            cleaning,
            (r) => record(RecordKind.property, text(r, 'property_id')),
            time: 'deadline_time',
            title: 'property_name',
          ),
          queue(
            'Open maintenance',
            issues.take(5).toList(),
            (r) => c.navigate(PmsPage.maintenance),
            time: 'severity',
            title: 'title',
          ),
        ]),
        const SizedBox(height: 34),
        PmsEyebrow(c.t('Properties')),
        Text(
          c.t('Properties'),
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        PmsColumns([
          for (final p in optionalRows(dashboard['properties']))
            GestureDetector(
              onTap: () => record(RecordKind.property, text(p, 'id')),
              child: PmsCard(
                child: SizedBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              text(p, 'name'),
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          PmsBadge(
                            c.t(
                              text(p, 'state') == 'ready'
                                  ? 'Ready'
                                  : 'Attention',
                            ),
                            tone: text(p, 'state'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        (p['reasons'] as List? ?? []).isEmpty
                            ? c.t('No blockers detected.')
                            : (p['reasons'] as List).join(' \u00b7 '),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Next: ${displayDate(p['next_arrival'] as String?)}                         Open \u2192',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ]),
      ],
    );
  }

  Widget queue(
    String label,
    List<Json> rows,
    void Function(Json) open, {
    required String time,
    String title = '',
  }) => PmsCard(
    padding: EdgeInsets.zero,
    shadow: true,
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: PmsStyle.soft,
          child: Row(
            children: [
              Expanded(child: PmsEyebrow(c.t(label))),
              PmsBadge('${rows.length}', tone: 'attention'),
            ],
          ),
        ),
        if (rows.isEmpty) const PmsEmpty('\u2014'),
        for (final r in rows)
          InkWell(
            onTap: () => open(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    child: Text(
                      text(r, time, '\u2014'),
                      style: const TextStyle(
                        fontFamily: 'Georgia',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text(r, title),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${text(r, 'assigned_name', text(r, 'property_name'))} \u00b7 ${text(r, 'status')}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Text('\u203a'),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  Widget workers(bool schedule) {
    final d = c.object('worker');
    final tasks = optionalRows(d['tasks'])
        .where(
          (r) =>
              schedule ||
              r['scheduled_date'] == d['date'] ||
              r['status'] == 'in_progress',
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          c.label(c.page),
          schedule ? 'Schedule' : "Today's command center",
          '${tasks.length} active items',
        ),
        for (final t in tasks)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${text(t, 'scheduled_date')} \u00b7 ${text(t, 'status')}',
                  ),
                  Text(
                    text(t, 'property_name'),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Checkout ${text(t, 'earliest_time', '—')} · Check-in ${text(t, 'deadline_time', '—')} · ${t['next_guest_count'] ?? '—'} guests',
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final request
                          in (t['special_requests'] is List
                              ? t['special_requests'] as List
                              : const []))
                        PmsBadge('$request'),
                    ],
                  ),
                  Text(
                    '${t['checklist_done'] ?? 0}/${t['checklist_total'] ?? optionalRows(t['checklist']).length} checklist items',
                  ),
                  for (final item in optionalRows(t['checklist']))
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(text(item, 'label')),
                      value:
                          item['completed'] == 1 || item['completed'] == true,
                      onChanged: c.saving || t['status'] == 'complete'
                          ? null
                          : (v) => c.act(() async {
                              await c.mutate(
                                'PATCH',
                                '/api/work-tasks/${idPath(text(t, 'id'))}/checklist/${idPath(text(item, 'id'))}',
                                {'completed': v},
                              );
                            }),
                    ),
                  if (t['status'] == 'pending' || t['status'] == 'open')
                    PmsButton(
                      c.t('Start cleaning'),
                      primary: true,
                      onPressed: c.saving
                          ? null
                          : () => c.act(() async {
                              await c.mutate(
                                'POST',
                                '/api/work-tasks/${idPath(text(t, 'id'))}/start',
                              );
                            }),
                    ),
                  if (t['status'] == 'in_progress')
                    PmsButton(
                      'Ready to finish',
                      primary: true,
                      onPressed:
                          c.saving ||
                              optionalRows(t['checklist']).any(
                                (i) =>
                                    i['completed'] != 1 &&
                                    i['completed'] != true,
                              )
                          ? null
                          : () async {
                              final changed = await showDialog<bool>(
                                context: context,
                                useRootNavigator: false,
                                barrierDismissible: false,
                                builder: (_) => PmsTextDialog(
                                  title: 'Anything the owner should know?',
                                  label: 'Optional note',
                                  submitLabel: 'Mark ready',
                                  required: false,
                                  save: (note) =>
                                      OperationsWorkflows(c).finish(t, note),
                                ),
                              );
                              if (changed == true && mounted) await c.load();
                            },
                    ),
                  if (t['status'] == 'complete')
                    Text(
                      '✓ Complete${text(t, 'worker_note').isEmpty ? '' : ' · ${text(t, 'worker_note')}'}',
                    ),
                ],
              ),
            ),
          ),
        if (tasks.isEmpty) PmsEmpty(c.t('Nothing currently scheduled.')),
      ],
    );
  }

  Widget calendar() {
    final rows = c
            .rows('reservations')
            .where((r) => r['status'] == 'confirmed')
            .toList(),
        props = c.rows('properties');
    final start = month.subtract(Duration(days: month.weekday - 1));
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const colors = [
      Color(0xFF087F8C),
      Color(0xFF7357D9),
      Color(0xFFD65B22),
      Color(0xFF1971C2),
      Color(0xFFB02E72),
      Color(0xFF477A36),
      Color(0xFF8A6418),
      Color(0xFF52616B),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'DELVANE · RESERVATIONS',
          'Calendar',
          'All properties. One clear view.',
        ),
        Align(
          alignment: Alignment.centerRight,
          child: PmsButton(
            '+ New reservation',
            primary: true,
            onPressed: () => newReservation(),
          ),
        ),
        const SizedBox(height: 12),
        PmsCard(
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  PmsButton(
                    '\u2039',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month - 1),
                    ),
                  ),
                  PmsButton(
                    'Today',
                    onPressed: () => setState(
                      () => month = DateTime(
                        DateTime.now().year,
                        DateTime.now().month,
                      ),
                    ),
                  ),
                  PmsButton(
                    '\u203a',
                    onPressed: () => setState(
                      () => month = DateTime(month.year, month.month + 1),
                    ),
                  ),
                  Text(
                    '${months[month.month - 1]} ${month.year}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  PmsButton(
                    'Go to month',
                    small: true,
                    onPressed: () => showDialog<bool>(
                      useRootNavigator: false,
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => PmsTextDialog(
                        title: 'Go to month',
                        lines: 1,
                        label: 'Month (YYYY-MM)',
                        submitLabel: 'Go',
                        initial: isoDate(month).substring(0, 7),
                        save: (value) async {
                          if (!validDate('$value-01')) {
                            throw const FormatException('Invalid month');
                          }
                          setState(() => month = DateTime.parse('$value-01'));
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final day in [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ])
                    Expanded(
                      child: Center(
                        child: Text(day, style: const TextStyle(fontSize: 10)),
                      ),
                    ),
                ],
              ),
              LayoutBuilder(
                builder: (context, box) {
                  final width = box.maxWidth / 7;
                  return Wrap(
                    children: [
                      for (var i = 0; i < 42; i++)
                        Builder(
                          builder: (context) {
                            final date = start.add(Duration(days: i)),
                                iso = isoDate(start.add(Duration(days: i)));
                            final stays = rows
                                .where(
                                  (r) =>
                                      text(r, 'arrival_date').compareTo(iso) <=
                                          0 &&
                                      text(r, 'departure_date').compareTo(iso) >
                                          0,
                                )
                                .toList();
                            return Container(
                              width: width,
                              height: MediaQuery.sizeOf(context).width < 760
                                  ? 106
                                  : 150,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: date.month == month.month
                                    ? Colors.white
                                    : const Color(0xFFF8F7F4),
                                border: Border.all(
                                  color: const Color(0xFFE8E6E1),
                                  width: .5,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SizedBox(
                                    height: 25,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: InkWell(
                                        key: ValueKey('calendar-day-$iso'),
                                        onTap: () => newReservation(iso),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                          child: Text(
                                            '${date.day}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (MediaQuery.sizeOf(context).width > 760 &&
                                      rows.any(
                                        (r) =>
                                            r['arrival_date'] == iso ||
                                            r['departure_date'] == iso,
                                      ))
                                    Text(
                                      '${rows.where((r) => r['arrival_date'] == iso).length} in · ${rows.where((r) => r['departure_date'] == iso).length} out',
                                      style: const TextStyle(fontSize: 9),
                                    ),
                                  for (final r in stays.take(3))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: InkWell(
                                        onTap: () => record(
                                          RecordKind.reservation,
                                          text(r, 'id'),
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                colors[(props
                                                        .indexWhere(
                                                          (p) =>
                                                              p['id'] ==
                                                              r['property_id'],
                                                        )
                                                        .clamp(0, 99)) %
                                                    colors.length],
                                            borderRadius: BorderRadius.circular(
                                              5,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(
                                                text(r, 'guest_name'),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  height: 1.1,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              if (MediaQuery.sizeOf(
                                                    context,
                                                  ).width >
                                                  760)
                                                Text(
                                                  text(r, 'source'),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    height: 1.1,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (stays.length > 3)
                                    InkWell(
                                      onTap: () => showDialog<void>(
                                        useRootNavigator: false,
                                        context: context,
                                        builder: (_) => PmsModal(
                                          title: iso,
                                          child: Column(
                                            children: [
                                              for (final stay in stays)
                                                ListTile(
                                                  title: Text(
                                                    text(stay, 'guest_name'),
                                                  ),
                                                  subtitle: Text(
                                                    text(stay, 'property_name'),
                                                  ),
                                                  onTap: () {
                                                    Navigator.pop(context);
                                                    record(
                                                      RecordKind.reservation,
                                                      text(stay, 'id'),
                                                    );
                                                  },
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '+${stays.length - 3} more',
                                        style: const TextStyle(fontSize: 9),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 20,
                children: [
                  const Text('PROPERTIES'),
                  for (final p in props) Text(text(p, 'name')),
                ],
              ),
              const Text(
                'Stay covers check-in through the night before checkout',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        PmsEyebrow('WORKSPACE'),
        const Text(
          'Everything else, close at hand',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final page in [
              PmsPage.today,
              PmsPage.inbox,
              PmsPage.team,
              PmsPage.train,
            ])
              PmsButton(c.label(page), onPressed: () => c.navigate(page)),
          ],
        ),
        if (c.rows('reservations').any((r) => r['status'] == 'inquiry')) ...[
          const SizedBox(height: 24),
          const PmsEyebrow('NOT CONFIRMED'),
          const Text(
            'Inquiries',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          for (final inquiry
              in c
                  .rows('reservations')
                  .where((r) => r['status'] == 'inquiry')
                  .take(8))
            ListTile(
              title: Text(text(inquiry, 'guest_name')),
              subtitle: Text(
                '${text(inquiry, 'property_name')} · ${text(inquiry, 'arrival_date')} → ${text(inquiry, 'departure_date')}',
              ),
              trailing: Text(text(inquiry, 'source')),
              onTap: () => record(RecordKind.reservation, text(inquiry, 'id')),
            ),
        ],
      ],
    );
  }

  Widget intelligence() {
    final d = c.object('intelligence'),
        conversation = c.object('conversation'),
        provider = c.object('provider');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Image.asset(PmsStyle.logo, width: 44, height: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delvane AI',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    provider['external_fallback_configured'] == true
                        ? 'Local first ? Luna ready'
                        : 'Local first ? No Luna',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        PmsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PmsEyebrow(c.t('Briefing')),
              Text(text(d, 'brief')),
              const SizedBox(height: 16),
              Wrap(
                spacing: 24,
                children: [
                  Text('Needs you  ${optionalRows(d['approvals']).length}'),
                  Text('Delvane handling  ${d['handled'] ?? 0}'),
                  Text('Exceptions  ${optionalRows(d['exceptions']).length}'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final message in optionalRows(conversation['messages']))
          Align(
            alignment: message['role'] == 'user'
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: PmsCard(child: Text(text(message, 'content'))),
          ),
        for (final proposal in optionalRows(conversation['proposals']))
          PmsCard(
            child: Column(
              children: [
                Text(text(proposal, 'summary', text(proposal, 'action_type'))),
                Text(text(proposal, 'status')),
                if (proposal['status'] == 'awaiting_approval')
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final choice in ['approve', 'decline'])
                        PmsButton(
                          choice == 'approve' ? 'Approve' : 'Decline',
                          onPressed: c.saving
                              ? null
                              : () => c.act(() async {
                                  await c.mutate(
                                    'POST',
                                    '/api/rosa/proposals/${idPath(text(proposal, 'id'))}/resolve',
                                    {'decision': choice},
                                  );
                                }),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final prompt in [
              'Anything concerning tomorrow?',
              'Who still needs registration?',
              "Which properties aren?t ready?",
            ])
              PmsButton(
                c.t(prompt),
                small: true,
                onPressed: () => chat.text = prompt,
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: chat,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: c.t('Ask anything about the operation?'),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: PmsButton(
            '\u203a',
            primary: true,
            onPressed: c.saving
                ? null
                : () => c.act(() async {
                    if (chat.text.trim().isEmpty) return;
                    await c.mutate('POST', '/api/rosa/chat', {
                      'message': chat.text,
                      'language': c.strings.language,
                    });
                    chat.clear();
                  }),
          ),
        ),
      ],
    );
  }

  Widget operations() {
    final journeys = c.rows('journeys'),
        timeline = c.rows('timeline'),
        intel = c.object('intelligence');
    final pages = (journeys.length / 8).ceil().clamp(1, 1000000);
    journeyPage = journeyPage.clamp(0, pages - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'OPERATIONS',
          'One living timeline.',
          'Reservations, Delvane decisions, guest preparation and team actions stay connected.',
        ),
        const PmsEyebrow('GUEST STATUS'),
        const Text(
          'Preparation intelligence',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
        ),
        if (journeys.length > 8)
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PmsButton(
                '‹',
                onPressed: journeyPage == 0
                    ? null
                    : () => setState(() => journeyPage--),
              ),
              Text(
                '${journeyPage * 8 + 1}–${((journeyPage + 1) * 8).clamp(0, journeys.length)} / ${journeys.length}',
              ),
              PmsButton(
                '›',
                onPressed: journeyPage >= pages - 1
                    ? null
                    : () => setState(() => journeyPage++),
              ),
            ],
          ),
        if (journeys.isEmpty) const PmsEmpty('No upcoming guests.'),
        for (final r in journeys.skip(journeyPage * 8).take(8))
          PmsCard(
            child: ListTile(
              title: Text(text(r, 'guest_name')),
              subtitle: Text(
                '${text(r, 'property_name')} \u00b7 ${text(r, 'current_stage')}',
              ),
              trailing: Text('${r['current_stage_index']}/${r['stage_total']}'),
              onTap: () => record(RecordKind.reservation, text(r, 'id')),
            ),
          ),
        const SizedBox(height: 24),
        PmsColumns([
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Activity timeline',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
                for (final r in timeline)
                  ListTile(
                    title: Text(text(r, 'message')),
                    subtitle: Text(
                      '${text(r, 'created_at')} \u00b7 ${text(r, 'actor', 'Delvane')}',
                    ),
                  ),
              ],
            ),
          ),
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cleaner coordination',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
                ),
                for (final r in optionalRows(intel['tasks']))
                  ListTile(
                    title: Text(text(r, 'property_name')),
                    subtitle: Text(
                      '${text(r, 'scheduled_date')} \u00b7 ${text(r, 'assigned_name', 'Unassigned')}',
                    ),
                  ),
              ],
            ),
          ),
        ], columns: 2),
      ],
    );
  }

  Widget administration() {
    if (c.page == PmsPage.integrations) return IntegrationsPage(c: c);
    if (c.page == PmsPage.security) return SecurityPage(c: c);
    if (c.page == PmsPage.train) return KnowledgePage(c: c);
    if (c.page == PmsPage.simulation) return OperatingModePage(c: c);
    if (c.page == PmsPage.team) return TeamPage(c: c);
    if (c.page == PmsPage.supplies) return SuppliesPage(c: c);
    if (c.page == PmsPage.maintenance) return MaintenancePage(c: c);
    // Unported controls are explicitly disclosed; no fabricated success or mock data.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(c.label(c.page).toUpperCase(), c.label(c.page), ''),
        const PmsCard(
          child: Text(
            'This interface is not yet fully ported. Continue this workflow in the existing web PMS. No simulated action is performed.',
          ),
        ),
      ],
    );
  }
}
