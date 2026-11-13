import 'package:material_ui/material_ui.dart';

enum Destination {
  dashboard(
    'Dashboard',
    Icons.grid_view_rounded,
    'Your day, beautifully in focus.',
  ),
  reservations(
    'Reservations',
    Icons.calendar_month_outlined,
    'Every stay. One clear picture.',
  ),
  reception(
    'Reception',
    Icons.inbox_outlined,
    'Make every conversation feel personal.',
  ),
  properties(
    'Properties',
    Icons.apartment_rounded,
    'A little care for every space.',
  ),
  operations(
    'Operations',
    Icons.check_circle_outline_rounded,
    'Good days start behind the scenes.',
  ),
  ai(
    'Delvane AI',
    Icons.auto_awesome_outlined,
    'More perspective. Less busywork.',
  ),
  settings(
    'Settings',
    Icons.tune_rounded,
    'A workspace that feels like yours.',
  );

  const Destination(this.label, this.icon, this.subtitle);
  final String label;
  final IconData icon;
  final String subtitle;
}
