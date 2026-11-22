import 'actual_stay_controls.dart';
import 'financial_controls.dart';
import 'booking_calendar.dart';
import 'operations_dashboard.dart';

import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_controller.dart';
import '../workspace/workspace_models.dart';
import '../workspace/workspace_repository.dart';
import '../workspace/record_page.dart';
import 'pms_controller.dart';
import 'pms_style.dart';
import 'pms_icons.dart';
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
import 'intelligence_workspace.dart';
import 'ask_bar.dart';

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
  final calendarSelection = CalendarSelection(DateTime.now());
  String? operationsProperty;
  late final Timer operationsRefresh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(c.load());
    operationsRefresh = Timer.periodic(const Duration(seconds: 30), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          !c.loading &&
          !c.refreshing &&
          !c.saving &&
          const [
            PmsPage.today,
            PmsPage.operations,
            PmsPage.schedule,
          ].contains(c.page)) {
        unawaited(c.refreshIfStale());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(c.refreshIfStale());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    operationsRefresh.cancel();
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
      final readRevision = c.readRevision;
      final changed = await showDialog<bool>(
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
      if (mounted &&
          c.auth.user != null &&
          (changed == true || c.readRevision != readRevision)) {
        await c.refreshIfStale();
      }
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ui(safeError(e)))));
      }
    }
  }

  Future<void> newReservation([String? date, String? property]) async {
    final changed = await showDialog<bool>(
      useRootNavigator: false,
      context: context,
      barrierDismissible: false,
      builder: (_) => ReservationEditor(
        api: PmsWorkflows(c),
        initialDate: date,
        initialProperty: property,
      ),
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
              ui('DELVANE'),
              style: TextStyle(
                fontSize: mobile ? 17.28 : 19.2,
                fontWeight: FontWeight.w800,
                letterSpacing: mobile ? 1.296 : 1.728,
              ),
            ),
            if (!mobile)
              Text(ui('INTELLIGENCE OS'), style: TextStyle(fontSize: 10)),
          ],
        ),
      ),
    ],
  );
  Widget sidebar({VoidCallback? closeDrawer}) => Container(
    key: const ValueKey('pms-sidebar'),
    width: PmsStyle.sidebarWidth,
    color: const Color(0xFFFFFDFA),
    padding: const EdgeInsets.fromLTRB(18, 28, 18, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        brand(),
        const SizedBox(height: 34),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final page in c.primary)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9, right: 5),
                    child: PmsNavItem(
                      c.label(page),
                      key: ValueKey('pms-nav-${page.name}'),
                      selected: c.page == page,
                      mobile: MediaQuery.sizeOf(context).width <= 760,
                      onPressed: () {
                        closeDrawer?.call();
                        c.navigate(page);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        Row(
          children: [
            const SizedBox(width: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.connectionIssue == null
                    ? PmsStyle.yellow
                    : PmsStyle.muted,
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 8, height: 8),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                ui(
                  c.connectionIssue == null
                      ? (c.isUat ? 'UAT test workspace' : 'Workspace active')
                      : c.isUat
                      ? 'UAT updates delayed'
                      : 'Some updates delayed',
                ),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (c.user.isOperator)
          Material(
            color: Colors.transparent,
            child: InkWell(
              key: const ValueKey('pms-account'),
              onTap: Theme.of(context).platform == TargetPlatform.android
                  ? null
                  : () {
                      settings();
                    },
              borderRadius: BorderRadius.circular(24),
              child: Container(
                constraints: const BoxConstraints(minHeight: 74),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white),
                  gradient: const LinearGradient(
                    colors: [Color(0xFAFFFFFF), Color(0xA6FFF2AD)],
                  ),
                  boxShadow: const [PmsStyle.shadow],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white,
                      child: Text(
                        c.user.name
                            .split(' ')
                            .where((n) => n.isNotEmpty)
                            .take(2)
                            .map((n) => n[0])
                            .join()
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            c.user.organization,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10),
                          ),
                          Text(
                            c.user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            c.roleLabel,
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    if (Theme.of(context).platform != TargetPlatform.android)
                      const PmsVectorIcon('chevron', size: 12),
                  ],
                ),
              ),
            ),
          )
        else ...[
          Text(
            c.user.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(c.roleLabel, style: const TextStyle(fontSize: 12)),
          PmsButton(c.t('Sign out'), onPressed: widget.auth.logout),
        ],
      ],
    ),
  );
  void settings() => showGeneralDialog<void>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: true,
    barrierLabel: ui('Close settings'),
    barrierColor: const Color(0x142D2719),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, __) => PmsSideSheet(
      title: c.t('Settings'),
      eyebrow: c.t('Workspace').toUpperCase(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PmsCard(
            padding: const EdgeInsets.all(14),
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.user.organization, style: const TextStyle(fontSize: 12)),
                Text(
                  c.user.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(c.roleLabel, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final page in c.settings)
                  SizedBox(
                    width: (constraints.maxWidth - 8) / 2,
                    child: Semantics(
                      selected: c.page == page,
                      child: Material(
                        color: c.page == page
                            ? const Color(0x66FFD500)
                            : const Color(0xAFFFFFFF),
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.pop(context);
                            c.navigate(page);
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 76),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  PmsVectorIcon(switch (page) {
                                    PmsPage.team => '♙',
                                    PmsPage.simulation => '◎',
                                    PmsPage.maintenance => '◇',
                                    PmsPage.supplies => '▦',
                                    PmsPage.integrations => '↔',
                                    PmsPage.security => '⌾',
                                    _ => 'R',
                                  }, size: 20),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.label(page),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Icon(
                                        c.page == page
                                            ? Icons.check
                                            : Icons.chevron_right,
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          PmsSelect(
            c.t('Language'),
            value: c.strings.language,
            items: {for (final l in c.strings.languages) l[0]: l[1]},
            onChanged: (v) async {
              try {
                await c.language(v);
                if (context.mounted) Navigator.pop(context);
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ui('Language preference could not be saved.'),
                      ),
                    ),
                  );
                }
              }
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
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                controller: input,
                decoration: InputDecoration(hintText: ui('Search Delvane')),
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
              if (error != null) Text(ui(error!)),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ui(safeError(e)))));
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
            final intelligencePage = c.page == PmsPage.intelligence;
            final gap = intelligencePage && !mobile
                ? 18.0
                : mobile
                ? 10.0
                : (MediaQuery.sizeOf(context).width * .026).clamp(20.0, 48.0);
            return Scaffold(
              drawer: mobile
                  ? Drawer(
                      width: 320,
                      child: Builder(
                        builder: (drawerContext) => SafeArea(
                          child: sidebar(
                            closeDrawer: () => Navigator.pop(drawerContext),
                          ),
                        ),
                      ),
                    )
                  : null,
              body: SafeArea(
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!mobile) sidebar(),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, viewport) => RawScrollbar(
                              controller: scroll,
                              thumbVisibility: !mobile,
                              thumbColor: PmsStyle.yellow,
                              thickness: mobile ? 2.5 : 9,
                              radius: const Radius.circular(6),
                              crossAxisMargin: 3,
                              child: SingleChildScrollView(
                                key: const ValueKey('pms-main-scroll'),
                                controller: scroll,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    gap,
                                    mobile
                                        ? 12
                                        : intelligencePage
                                        ? 16
                                        : 14,
                                    gap + (mobile || intelligencePage ? 0 : 15),
                                    intelligencePage ? 18 : 100,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      if (mobile)
                                        Padding(
                                          padding: EdgeInsets.only(
                                            bottom: intelligencePage ? 20 : 24,
                                          ),
                                          child: SizedBox(
                                            height: intelligencePage ? 44 : 56,
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                const Center(
                                                  child: PmsMobileBrand(
                                                    key: ValueKey(
                                                      'mobile-wordmark',
                                                    ),
                                                  ),
                                                ),
                                                Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: Builder(
                                                    builder: (context) =>
                                                        PmsIconButton(
                                                          'menu',
                                                          label: ui(
                                                            'Open main menu',
                                                          ),
                                                          surface: true,
                                                          onPressed: () =>
                                                              Scaffold.of(
                                                                context,
                                                              ).openDrawer(),
                                                        ),
                                                  ),
                                                ),
                                                Align(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (c.user.isOperator)
                                                        PmsIconButton(
                                                          'search',
                                                          label: ui(
                                                            'Search Delvane',
                                                          ),
                                                          onPressed: search,
                                                        ),
                                                      PmsIconButton(
                                                        'settings',
                                                        key: const ValueKey(
                                                          'pms-mobile-settings',
                                                        ),
                                                        label: ui(
                                                          'Open settings',
                                                        ),
                                                        onPressed: settings,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      else if (!intelligencePage)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 18,
                                          ),
                                          child: utility(),
                                        ),
                                      if (c.actionError != null)
                                        Text(
                                          ui(c.actionError!),
                                          style: const TextStyle(
                                            color: Colors.red,
                                          ),
                                        ),
                                      if (c.loading)
                                        const Padding(
                                          padding: EdgeInsets.all(48),
                                          child: Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        )
                                      else if (c.error != null ||
                                          c.sectionErrors.isNotEmpty)
                                        PmsCard(
                                          child: Wrap(
                                            spacing: 12,
                                            runSpacing: 8,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                ui(
                                                  c.error ?? 'Some sections could not be updated.',
                                                ),
                                              ),
                                              if (c.error == null)
                                                Text(
                                                  ui(
                                                    c
                                                        .sectionErrors
                                                        .values
                                                        .first,
                                                  ),
                                                ),
                                              PmsButton(
                                                ui('Retry'),
                                                onPressed: c.load,
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (!c.loading && c.refreshing)
                                        const Padding(
                                          padding: EdgeInsets.only(bottom: 8),
                                          child: LinearProgressIndicator(
                                            minHeight: 2,
                                          ),
                                        ),
                                      if (!c.loading && c.data.isNotEmpty)
                                        content(
                                          viewportHeight: viewport.maxHeight,
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!c.loading &&
                        c.error == null &&
                        c.user.isOperator &&
                        const [
                          PmsPage.inbox,
                          PmsPage.team,
                          PmsPage.train,
                        ].contains(c.page))
                      Positioned(
                        left: mobile ? 12 : PmsStyle.sidebarWidth,
                        right: mobile
                            ? (c.page == PmsPage.inbox ? 12 : 27)
                            : 15,
                        bottom: mobile ? 12 : 22,
                        child: Align(
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 900),
                            child: PmsAskBar(
                              key: ValueKey('ask-${c.page.name}'),
                              c: c,
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
  Widget utility() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      if (c.user.isOperator) ...[
        TextButton(
          onPressed: search,
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(32, 41),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const PmsVectorIcon('search', size: 14),
              if (MediaQuery.sizeOf(context).width >= 1100) ...[
                const SizedBox(width: 8),
                Text(
                  c.t('Search Delvane'),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0ECE6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ui('Ctrl K'),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
        Tooltip(
          message: c.t('Notifications'),
          child: TextButton(
            onPressed: notifications,
            child: Row(
              children: [
                const PmsVectorIcon('notifications', size: 16),
                const SizedBox(width: 6),
                Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFFC19452),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${c.unread}',
                    style: const TextStyle(fontSize: 10, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
        ),
        TextButton(
          onPressed: () => c.navigate(PmsPage.simulation),
          child: Text(
            c.modeLabel,
            style: const TextStyle(
              fontSize: 14,
              letterSpacing: 2,
              color: Colors.black,
            ),
          ),
        ),
      ],
      PmsIconButton(
        '↻',
        label: ui('Refresh'),
        size: 32,
        onPressed: c.loading ? null : c.load,
      ),
    ],
  );
  Widget heading(String eyebrow, String title, String description) =>
      PmsPageHeader(
        eyebrow: c.t(eyebrow),
        title: c.t(title),
        description: c.t(description),
      );
  Widget content({double? viewportHeight}) {
    switch (c.page) {
      case PmsPage.today:
        return c.user.isOperator ? today() : workers(false);
      case PmsPage.schedule:
        return workers(true);
      case PmsPage.reservations:
        return calendar(viewportHeight: viewportHeight);
      case PmsPage.intelligence:
        return intelligence(viewportHeight: viewportHeight);
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
        PmsPageHeader(
          key: const ValueKey('today-header'),
          eyebrow: '',
          title: c.t("Today's command center"),
          description: text(cmd, 'date').isEmpty
              ? ''
              : uiDate(text(cmd, 'date')),
          actions: [
            if (c.hasSection('command'))
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF2B8),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text(
                  ui('$urgent URGENT'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ),
          ],
        ),
        if (c.hasSection('command')) ...[
          LayoutBuilder(
            builder: (context, box) {
              final count = box.maxWidth < 780 ? 2 : 4,
                  w = (box.maxWidth - 12 * (count - 1)) / count;
              final metrics = {
                'Arrivals': arrivals.length,
                'Departures': optionalRows(cmd['departures']).length,
                'Turnovers': cleaning
                    .where((r) => r['deadline_time'] != null)
                    .length,
                'Registration issues': registration.length,
              };
              return Wrap(
                key: const ValueKey('today-metrics'),
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final e in metrics.entries)
                    SizedBox(
                      width: w,
                      child: PmsCard(
                        radius: 12,
                        shadow: false,
                        color: Colors.white,
                        borderColor: PmsStyle.panelLine,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 12,
                        ),
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
                                fontSize: 24,
                                color: Colors.black,
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
              key: const ValueKey('registration-strip'),
              radius: 22,
              shadow: false,
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 54),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              PmsEyebrow(
                                c.t('Guest registration').toUpperCase(),
                              ),
                              Text(
                                c.t('Registration needs attention'),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Text(
                          '${registration.length}',
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final r in registration)
                    InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () =>
                          record(RecordKind.reservation, text(r, 'id')),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF5E8C8),
                                shape: BoxShape.circle,
                              ),
                              child: const Text(
                                '!',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    text(r, 'guest_name'),
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    '${c.propertyLabel(text(r, 'property_name'))} · ${c.t('arrives today')} · ${text(r, 'arrival_time')}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (MediaQuery.sizeOf(context).width <= 720)
                                    Padding(
                                      padding: EdgeInsets.only(top: 12),
                                      child: Text(
                                        ui('Open stay →'),
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (MediaQuery.sizeOf(context).width > 720)
                              Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  ui('Open stay →'),
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
          PmsColumns(key: const ValueKey('today-board'), [
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
        ],
        if (c.hasSection('dashboard')) ...[
          const SizedBox(height: 18),
          Text(
            c.t('Properties'),
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          PmsColumns(key: const ValueKey('properties-grid'), [
            for (final p in optionalRows(dashboard['properties']))
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => record(RecordKind.property, text(p, 'id')),
                  borderRadius: BorderRadius.circular(18),
                  child: PmsCard(
                    radius: 18,
                    shadow: false,
                    borderColor: PmsStyle.panelLine,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                c.propertyLabel(text(p, 'name')),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            PmsBadge(
                              c.t(switch (p['state']) {
                                'ready' => 'Ready',
                                'occupied' => 'Occupied',
                                'cleaning' => 'Cleaning pending',
                                _ => 'Attention',
                              }),
                              tone: text(p, 'state'),
                              large: p['state'] != 'ready',
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          (p['reasons'] as List? ?? []).isEmpty
                              ? c.t('No blockers detected.')
                              : (p['reasons'] as List)
                                    .map((reason) => ui('$reason'))
                                    .join(' · '),
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                ui(
                                  'Next: ${displayDate(p['next_arrival'] as String?)}',
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Text(
                              ui('Open →'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 18),
        stayAndClosingTools(),
      ],
    );
  }

  Widget stayAndClosingTools() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        ui('Stay and closing tools'),
        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      ActualOccupancyPanel(c: c),
      const SizedBox(height: 8),
      BusinessClosingPanel(c: c),
    ],
  );

  Widget queue(
    String label,
    List<Json> rows,
    void Function(Json) open, {
    required String time,
    String title = '',
  }) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: PmsCard(
      radius: 20,
      padding: EdgeInsets.zero,
      color: const Color(0xEBFFFDF8),
      shadow: false,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            color: PmsStyle.soft,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    c.t(label),
                    style: const TextStyle(
                      fontSize: 11.68,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      color: Color(0xFF685F4F),
                    ),
                  ),
                ),
                PmsCount('${rows.length}'),
              ],
            ),
          ),
          if (rows.isEmpty) const PmsEmpty('—'),
          for (final r in rows)
            InkWell(
              onTap: () => open(r),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 66),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: time == 'severity'
                            ? PmsBadge(
                                text(r, time),
                                tone: text(r, time),
                                compact: true,
                              )
                            : Text(
                                text(r, time, '—'),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF554F43),
                                ),
                              ),
                      ),
                      const SizedBox(width: 10),
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
                              time == 'arrival_time'
                                  ? ui(
                                      '${c.propertyLabel(text(r, 'property_name'))} · ${ui("${r['guest_count'] ?? 0} guests")}',
                                    )
                                  : '${text(r, 'assigned_name', c.propertyLabel(text(r, 'property_name')))} · ${ui(text(r, 'status'))}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      PmsCount(
                        time == 'arrival_time'
                            ? '!'
                            : time == 'deadline_time'
                            ? '◷'
                            : '›',
                        symbol: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  Widget workers(bool schedule) {
    final d = c.object('worker');
    final tasks = optionalRows(d['tasks'])
        .where(
          (r) =>
              (schedule ||
                  r['scheduled_date'] == d['date'] ||
                  (r['status'] != 'complete' &&
                      text(r, 'scheduled_date').compareTo(text(d, 'date')) <
                          0) ||
                  r['status'] == 'in_progress') &&
              r['status'] != 'cancelled',
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          c.label(c.page),
          schedule ? ui('Schedule') : ui("Today's command center"),
          ui('${tasks.length} active items'),
        ),
        PmsColumns([
          for (final t in tasks)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PmsCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${text(t, 'scheduled_date')} \u00b7 ${ui(text(t, 'status'))}',
                    ),
                    Text(
                      text(t, 'property_name'),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ui(
                        'Checkout ${text(t, 'earliest_time', '—')} · Check-in ${text(t, 'deadline_time', '—')} · ${t['next_guest_count'] ?? '—'} guests',
                      ),
                    ),
                    if (t['waiting_for_checkout'] == true)
                      PmsBadge(
                        ui('Waiting for actual checkout'),
                        tone: 'attention',
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
                      ui(
                        '${t['checklist_done'] ?? 0}/${t['checklist_total'] ?? optionalRows(t['checklist']).length} checklist items',
                      ),
                    ),
                    for (final item in optionalRows(t['checklist']))
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(text(item, 'label')),
                        value:
                            item['completed'] == 1 || item['completed'] == true,
                        onChanged:
                            c.saving ||
                                t['status'] == 'complete' ||
                                t['waiting_for_checkout'] == true
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
                        onPressed: c.saving || t['waiting_for_checkout'] == true
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
                        ui('Ready to finish'),
                        primary: true,
                        onPressed:
                            c.saving ||
                                t['waiting_for_checkout'] == true ||
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
                                    title: ui(
                                      'Anything the owner should know?',
                                    ),
                                    label: ui('Optional note'),
                                    submitLabel: ui('Mark ready'),
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
                        ui(
                          '✓ Complete${text(t, 'worker_note').isEmpty ? '' : ' · ${text(t, 'worker_note')}'}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ], columns: 2),
        if (tasks.isEmpty) PmsEmpty(c.t('Nothing currently scheduled.')),
      ],
    );
  }

  Widget calendar({double? viewportHeight}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      BookingCalendar(
        selection: calendarSelection,
        properties: c.rows('properties'),
        reservations: c.rows('reservations'),
        propertyLabel: c.propertyLabel,
        onOpen: (id) => record(RecordKind.reservation, id),
        onCreate: (date) => newReservation(date, calendarSelection.property),
        onZoom: () {
          if (scroll.hasClients) scroll.jumpTo(0);
        },
        viewportHeight: viewportHeight,
        loading: !c.hasSection('reservations') && c.refreshing,
      ),
      if (c.user.isOperator && c.error == null) ...[
        const SizedBox(height: 20),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: PmsAskBar(key: const ValueKey('ask-reservations'), c: c),
          ),
        ),
      ],
    ],
  );

  Widget intelligence({double? viewportHeight}) => IntelligenceWorkspace(
    c: c,
    input: chat,
    openSearch: search,
    viewportHeight: viewportHeight,
  );

  Widget operations() => OperationsDashboard(
    c: c,
    property: operationsProperty,
    onPropertyChanged: (value) => setState(() => operationsProperty = value),
    openReservation: (id) => record(RecordKind.reservation, id),
    tools: stayAndClosingTools(),
  );

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
        PmsCard(
          child: Text(
            ui(
              'This interface is not yet fully ported. Continue this workflow in the existing web PMS. No simulated action is performed.',
            ),
          ),
        ),
      ],
    );
  }
}
