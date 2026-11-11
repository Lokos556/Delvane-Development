import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import '../../shared/components.dart';
import 'record_page.dart';
import 'workspace_controller.dart';
import 'workspace_models.dart';
import 'workspace_repository.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key, required this.auth});
  final AuthController auth;
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage>
    with WidgetsBindingObserver {
  late final controller = WorkspaceController(
    widget.auth,
    WorkspaceRepository(widget.auth.api),
  );
  bool signingOut = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(controller.load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !signingOut) {
      unawaited(controller.load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  String _label(WorkspaceTab tab) => switch (tab) {
    WorkspaceTab.today =>
      widget.auth.user!.role == 'maintenance'
          ? 'My cases'
          : widget.auth.user!.role == 'cleaner'
          ? 'My day'
          : 'Today',
    WorkspaceTab.reservations => 'Stays',
    WorkspaceTab.properties => 'Properties',
    WorkspaceTab.work => 'Work',
    WorkspaceTab.account => 'Account',
  };
  IconData _icon(WorkspaceTab tab) => switch (tab) {
    WorkspaceTab.today => Icons.grid_view_rounded,
    WorkspaceTab.reservations => Icons.calendar_month_outlined,
    WorkspaceTab.properties => Icons.apartment_rounded,
    WorkspaceTab.work => Icons.checklist_rounded,
    WorkspaceTab.account => Icons.manage_accounts_outlined,
  };
  void _open(RecordRef ref) {
    final data = controller.workspace;
    if (data == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordPage(
          auth: widget.auth,
          repository: controller.repository,
          workspace: data,
          ref: ref,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final user = widget.auth.user!;
      final tabs = controller.tabs;
      final width = MediaQuery.sizeOf(context).width;
      final desktop = width >= 1100;
      final rail =
          !desktop && width >= 760 && MediaQuery.sizeOf(context).height >= 600;
      final data = controller.workspace;
      return Scaffold(
        bottomNavigationBar: desktop || rail
            ? null
            : NavigationBar(
                selectedIndex: tabs.indexOf(controller.tab),
                indicatorColor: DelvaneColors.yellow,
                onDestinationSelected: (index) =>
                    controller.navigate(tabs[index]),
                destinations: [
                  for (final tab in tabs)
                    NavigationDestination(
                      key: ValueKey('live-nav-${tab.name}'),
                      icon: Icon(_icon(tab)),
                      label: _label(tab),
                    ),
                ],
              ),
        body: SafeArea(
          child: Row(
            children: [
              if (desktop)
                Container(
                  width: 218,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 22,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'delvane',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const Text(
                        'BUSINESS',
                        style: TextStyle(fontSize: 10, letterSpacing: 3),
                      ),
                      const SizedBox(height: 28),
                      for (final tab in tabs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ListTile(
                            key: ValueKey('live-nav-${tab.name}'),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            selected: tab == controller.tab,
                            selectedTileColor: DelvaneColors.yellow,
                            leading: Icon(_icon(tab)),
                            title: Text(_label(tab)),
                            onTap: () => controller.navigate(tab),
                          ),
                        ),
                      const Spacer(),
                      Text(user.name),
                      Text(user.role),
                    ],
                  ),
                ),
              if (rail)
                NavigationRail(
                  selectedIndex: tabs.indexOf(controller.tab),
                  onDestinationSelected: (i) => controller.navigate(tabs[i]),
                  labelType: NavigationRailLabelType.all,
                  indicatorColor: DelvaneColors.yellow,
                  destinations: [
                    for (final tab in tabs)
                      NavigationRailDestination(
                        icon: Icon(_icon(tab)),
                        label: Text(_label(tab)),
                      ),
                  ],
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(18, 10, 10, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user.organization,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  'Connected · isolated data · ${user.role}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: DelvaneColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Refresh workspace',
                            onPressed:
                                controller.phase == WorkspacePhase.loading ||
                                    signingOut
                                ? null
                                : controller.load,
                            icon: const Icon(Icons.refresh),
                          ),
                          IconButton(
                            key: const ValueKey('logout'),
                            tooltip: 'Sign out',
                            onPressed: signingOut
                                ? null
                                : () async {
                                    setState(() => signingOut = true);
                                    await widget.auth.logout();
                                    if (mounted) {
                                      setState(() => signingOut = false);
                                    }
                                  },
                            icon: const Icon(Icons.logout),
                          ),
                        ],
                      ),
                    ),
                    if (data != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(
                            'live-property-${controller.propertyId}',
                          ),
                          value: controller.propertyId ?? '',
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Property scope',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('All accessible properties'),
                            ),
                            for (final prop in data.properties)
                              DropdownMenuItem(
                                value: prop.id,
                                child: Text(
                                  prop.name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) => controller.selectProperty(
                            value == '' ? null : value,
                          ),
                        ),
                      ),
                    Expanded(
                      child: controller.tab == WorkspaceTab.account
                          ? _account(user)
                          : controller.phase == WorkspacePhase.loading
                          ? const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 16),
                                  Text('Loading operational workspace…'),
                                ],
                              ),
                            )
                          : controller.phase == WorkspacePhase.error
                          ? _error()
                          : controller.tab == WorkspaceTab.reservations
                          ? _ReservationsView(
                              key: ObjectKey(data),
                              controller: controller,
                              onOpen: _open,
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _label(controller.tab),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineMedium,
                                  ),
                                  Text(
                                    '${data!.date} · Read-only operational workspace',
                                  ),
                                  const SizedBox(height: 16),
                                  if (controller.tab == WorkspaceTab.properties)
                                    _properties(data)
                                  else if (controller.tab == WorkspaceTab.work)
                                    _grid([
                                      if (user.role != 'maintenance')
                                        _queue(
                                          'Cleaning schedule',
                                          controller.scoped(data.cleaning),
                                        ),
                                      _queue(
                                        'Maintenance issues',
                                        controller.scoped(data.maintenance),
                                      ),
                                    ])
                                  else
                                    _grid([
                                      _queue(
                                        'Operational priorities',
                                        controller.scoped(data.priorities),
                                      ),
                                      if (user.isOperator)
                                        _queue(
                                          'Arrivals',
                                          controller.scoped(data.arrivals),
                                        ),
                                      if (user.isOperator)
                                        _queue(
                                          'Departures',
                                          controller.scoped(data.departures),
                                        ),
                                      if (user.role != 'maintenance')
                                        _queue(
                                          user.isOperator
                                              ? 'Cleaning turnovers'
                                              : 'My cleaning schedule',
                                          controller.scoped(data.cleaning),
                                        ),
                                      _queue(
                                        'Maintenance issues',
                                        controller.scoped(data.maintenance),
                                      ),
                                      if (user.isOperator)
                                        _queue(
                                          'Registration issues',
                                          controller.scoped(data.registration),
                                        ),
                                      _properties(data),
                                    ]),
                                  const SizedBox(height: 14),
                                  const Text(
                                    'Messaging, AI actions, booking edits and integration controls remain in the web PMS during migration.',
                                    style: TextStyle(
                                      color: DelvaneColors.muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _grid(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final tileWidth = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children)
            SizedBox(width: tileWidth, child: child),
        ],
      );
    },
  );
  Widget _queue(String title, List<OperationalItem> items) => Panel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '$title · ${items.length}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('No items in this scope.'),
          ),
        for (final item in items)
          _recordTile(
            item,
            controller.workspace!.propertyName(item.propertyId),
            _open,
          ),
      ],
    ),
  );
  Widget _properties(OperationalWorkspace data) => Panel(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Property readiness',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (data.properties.where((p) => controller.includes(p.id)).isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('No accessible properties.'),
          ),
        for (final p in data.properties.where((p) => controller.includes(p.id)))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.apartment_outlined),
            title: Text(p.name),
            subtitle: Text(
              p.state == null
                  ? 'Operational context · readiness restricted'
                  : '${p.state} ${p.reasons.isEmpty ? '' : '· ${p.reasons.join(' · ')}'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(RecordRef(RecordKind.property, p.id)),
          ),
      ],
    ),
  );
  Widget _error() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_outlined, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Workspace unavailable',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(controller.error!, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('No demo data has been substituted.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: controller.load, child: const Text('Retry')),
        ],
      ),
    ),
  );
  Widget _account(AuthUser user) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Account', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(user.name),
          Text('Role: ${user.role}'),
          Text(user.organization),
          const SizedBox(height: 16),
          Text('Development server: ${widget.auth.api.baseUrl.origin}'),
          const Text(
            'Session cookie is stored using platform-secure storage. Passwords and guest records are not persisted.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Permissions are supplied by the backend. All writes remain server-authorized.',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final permission in user.permissions)
                Chip(label: Text(permission)),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'This milestone is read-only apart from authentication. Use the existing web PMS for unfinished workflows.',
          ),
        ],
      ),
    ),
  );
}

Widget _recordTile(
  OperationalItem item,
  String property,
  void Function(RecordRef) onOpen,
) => ListTile(
  contentPadding: EdgeInsets.zero,
  leading: Icon(
    item.urgent ? Icons.priority_high_rounded : Icons.circle_outlined,
    color: item.urgent ? const Color(0xFF995100) : DelvaneColors.muted,
    size: 21,
  ),
  title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
  subtitle: Text(
    '$property · ${item.detail}\n${item.status.replaceAll('_', ' ')}',
  ),
  isThreeLine: true,
  trailing: const Icon(Icons.chevron_right),
  onTap: () => onOpen(item.ref),
);

class _ReservationsView extends StatefulWidget {
  const _ReservationsView({
    super.key,
    required this.controller,
    required this.onOpen,
  });
  final WorkspaceController controller;
  final void Function(RecordRef) onOpen;
  @override
  State<_ReservationsView> createState() => _ReservationsViewState();
}

class _ReservationsViewState extends State<_ReservationsView> {
  late Future<List<OperationalItem>> future = _load();
  String search = '';
  Future<List<OperationalItem>> _load() async {
    await widget.controller.auth.revalidate();
    final user = widget.controller.auth.user;
    if (user == null) throw const ApiException('Sign in again.');
    return widget.controller.repository.reservations(user);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<OperationalItem>>(
    future: future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Reservation list unavailable.'),
              FilledButton(
                onPressed: () => setState(() {
                  future = _load();
                  future.ignore();
                }),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      final items = widget.controller
          .scoped(snapshot.requireData)
          .where(
            (item) => '${item.title} ${item.ref.id} ${item.detail}'
                .toLowerCase()
                .contains(search.toLowerCase()),
          )
          .toList();
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Reservations',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Text('Real backend records · Read-only'),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('live-reservation-search'),
            decoration: const InputDecoration(
              labelText: 'Search guest, reference, dates or source',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => search = value),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty) const Text('No reservations match this scope.'),
          for (final item in items)
            _recordTile(
              item,
              widget.controller.workspace!.propertyName(item.propertyId),
              widget.onOpen,
            ),
        ],
      );
    },
  );
}
