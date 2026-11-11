import 'package:flutter/material.dart';
import '../app/controller.dart';
import '../app/destination.dart';
import '../app/theme.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/reservations/reservations_page.dart';
import '../features/reception/reception_page.dart';
import '../features/properties/properties_page.dart';
import '../features/operations/operations_page.dart';
import '../features/ai/ai_page.dart';
import '../features/settings/settings_page.dart';
import 'components.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.controller});
  final BusinessController controller;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final width = MediaQuery.sizeOf(context).width;
      final desktop = width >= 1120;
      final mobile =
          width < 760 || (!desktop && MediaQuery.sizeOf(context).height < 600);
      final rail = !desktop && !mobile;
      final data = controller.snapshot;
      return Scaffold(
        drawer: mobile
            ? Drawer(
                backgroundColor: Colors.white,
                child: SafeArea(child: _sidebar(context, drawer: true)),
              )
            : null,
        bottomNavigationBar: mobile
            ? Builder(
                builder: (context) => NavigationBar(
                  backgroundColor: Colors.white,
                  indicatorColor: DelvaneColors.yellow,
                  selectedIndex: controller.destination.index < 3
                      ? controller.destination.index
                      : 3,
                  onDestinationSelected: (index) => index < 3
                      ? controller.navigate(Destination.values[index])
                      : Scaffold.of(context).openDrawer(),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      label: 'Stays',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.inbox_outlined),
                      label: 'Reception',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.more_horiz),
                      label: 'More',
                    ),
                  ],
                ),
              )
            : null,
        body: SafeArea(
          child: Row(
            children: [
              if (desktop) SizedBox(width: 240, child: _sidebar(context)),
              if (rail)
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      right: BorderSide(color: DelvaneColors.line),
                    ),
                  ),
                  child: NavigationRail(
                    backgroundColor: Colors.white,
                    indicatorColor: DelvaneColors.yellow,
                    selectedIndex: controller.destination.index,
                    onDestinationSelected: (index) =>
                        controller.navigate(Destination.values[index]),
                    leading: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: _BrandMark(),
                    ),
                    labelType: NavigationRailLabelType.none,
                    destinations: Destination.values
                        .map(
                          (d) => NavigationRailDestination(
                            icon: Tooltip(
                              message: d.label,
                              child: Icon(d.icon),
                            ),
                            label: Text(d.label),
                          ),
                        )
                        .toList(),
                  ),
                ),
              Expanded(
                child: Column(
                  children: [
                    _topbar(context, mobile),
                    Expanded(
                      child: data == null
                          ? Center(
                              child: controller.loadError == null
                                  ? const CircularProgressIndicator()
                                  : Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(controller.loadError!),
                                        TextButton(
                                          onPressed: controller.load,
                                          child: const Text('Retry'),
                                        ),
                                      ],
                                    ),
                            )
                          : SingleChildScrollView(
                              key: ValueKey(controller.destination),
                              padding: EdgeInsets.all(mobile ? 16 : 32),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1440,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const MockNotice(),
                                      Text(
                                        controller.destination ==
                                                Destination.dashboard
                                            ? 'Good morning, Alex.'
                                            : controller.destination.label,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineLarge,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        controller.destination.subtitle,
                                        style: const TextStyle(
                                          color: DelvaneColors.muted,
                                        ),
                                      ),
                                      const SizedBox(height: 28),
                                      switch (controller.destination) {
                                        Destination.dashboard => DashboardPage(
                                          controller: controller,
                                        ),
                                        Destination.reservations =>
                                          ReservationsPage(
                                            controller: controller,
                                          ),
                                        Destination.reception => ReceptionPage(
                                          controller: controller,
                                        ),
                                        Destination.properties =>
                                          PropertiesPage(
                                            controller: controller,
                                          ),
                                        Destination.operations =>
                                          OperationsPage(
                                            controller: controller,
                                          ),
                                        Destination.ai => AiPage(
                                          controller: controller,
                                        ),
                                        Destination.settings => SettingsPage(
                                          controller: controller,
                                        ),
                                      },
                                      const SizedBox(height: 30),
                                      const Text(
                                        'DELVANE BUSINESS  /  EARLY PREVIEW',
                                        style: TextStyle(
                                          fontSize: 9,
                                          letterSpacing: 2,
                                          color: DelvaneColors.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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

  Widget _sidebar(BuildContext context, {bool drawer = false}) => Container(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: DelvaneColors.line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 32, 24, 34),
          child: Row(
            children: [
              _BrandMark(),
              SizedBox(width: 10),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'delvane',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.2,
                        ),
                      ),
                      Text(
                        'B U S I N E S S',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: DelvaneColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 26),
          child: Text(
            'YOUR WORKSPACE',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 1.6,
              color: DelvaneColors.muted,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            children: [
              for (final d in Destination.values)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: 7,
                    top: d == Destination.settings ? 20 : 0,
                  ),
                  child: Material(
                    color: controller.destination == d
                        ? DelvaneColors.yellow
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      key: ValueKey('nav-${d.name}'),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        d.icon,
                        size: 20,
                        color: controller.destination == d
                            ? DelvaneColors.ink
                            : DelvaneColors.muted,
                      ),
                      title: Text(
                        d.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: controller.destination == d
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                      onTap: () {
                        if (drawer) Navigator.pop(context);
                        controller.navigate(d);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Panel(
            padding: const EdgeInsets.all(14),
            color: DelvaneColors.canvas,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Tag(
                  'MOCK WORKSPACE',
                  color: DelvaneColors.yellowSoft,
                  foreground: DelvaneColors.ink,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Initials(
                      'Alex Morgan',
                      size: 32,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alex Morgan',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const Text(
                            'Demo administrator',
                            style: TextStyle(
                              fontSize: 10,
                              color: DelvaneColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _topbar(BuildContext context, bool mobile) => Container(
    padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 32, vertical: 14),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: DelvaneColors.line)),
    ),
    child: Row(
      children: [
        if (mobile)
          Builder(
            builder: (context) => IconButton(
              tooltip: 'Open navigation',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
        Expanded(
          child: Text(
            controller.destination.label,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (!mobile && controller.snapshot != null) ...[
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: controller.propertyId ?? 'all',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(fontSize: 12),
              items: [
                const DropdownMenuItem(
                  value: 'all',
                  child: Text('All demo properties'),
                ),
                ...controller.snapshot!.properties.map(
                  (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                ),
              ],
              onChanged: (value) =>
                  controller.selectProperty(value == 'all' ? null : value),
            ),
          ),
          const SizedBox(width: 16),
        ],
        const Tag(
          'DEMO',
          color: DelvaneColors.yellowSoft,
          foreground: DelvaneColors.ink,
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Demo notifications',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Your demo briefing'),
              content: const Text(
                '2 synthetic arrivals and 2 priority tasks. These are sample notifications, not live events.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
          icon: const Icon(Icons.notifications_none_rounded, size: 22),
        ),
      ],
    ),
  );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: DelvaneColors.yellow,
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Icon(Icons.bolt_rounded, color: DelvaneColors.ink, size: 25),
  );
}
