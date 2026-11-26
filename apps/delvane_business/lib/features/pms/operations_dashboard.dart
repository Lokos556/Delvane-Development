import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'actual_stay_controls.dart';
import 'operational_desk.dart';
import 'operations_pages.dart';
import 'pms_controller.dart';
import 'operational_visuals.dart';
import 'pms_style.dart';
import 'work_assignment_dialog.dart';

class OperationsDashboard extends StatelessWidget {
  const OperationsDashboard({
    super.key,
    required this.c,
    required this.property,
    required this.onPropertyChanged,
    required this.openReservation,
    this.openStay,
    this.openCleaning,
    required this.tools,
  });

  final PmsController c;
  final String? property;
  final ValueChanged<String?> onPropertyChanged;
  final ValueChanged<String> openReservation;
  final void Function(String, StayOperation)? openStay;
  final Future<void> Function(String, {VoidCallback? assign})? openCleaning;
  final Widget tools;

  Future<void> editWork(BuildContext context, Widget editor) async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => editor,
    );
    if (changed == true && context.mounted) await c.load();
  }

  Future<void> openMaintenance(BuildContext context, Json item) =>
      showDialog<void>(
        context: context,
        useRootNavigator: false,
        builder: (dialogContext) => PmsModal(
          title: ui('Maintenance'),
          child: MaintenanceCaseCard(
            c: c,
            item: item,
            onStatusChanged: () async {
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final properties = c.rows('properties');
    final selected = properties.any((p) => p['id'] == property)
        ? property!
        : '';
    List<Json> scoped(List<Json> rows) => selected.isEmpty
        ? rows
        : rows.where((row) => row['property_id'] == selected).toList();
    String propertyName(Json row) =>
        c.propertyLabel(text(row, 'property_name'));
    final intel = c.object('intelligence');
    final guests = scoped(c.rows('journeys'));
    final cleaning = scoped(optionalRows(intel['tasks']));
    final maintenance = scoped(optionalRows(intel['maintenance']))
        .where((row) => row['status'] != 'verified')
        .toList();
    final approvals = scoped(optionalRows(intel['approvals']));
    final urgent = scoped(optionalRows(intel['exceptions']))
        .where((row) => row['severity'] == 'high')
        .toList();
    Widget reviewDecisions() => TextButton(
      onPressed: () =>
          openOperationalDesk(context, c, tab: 1, property: selected),
      child: Text(ui('Review decisions')),
    );
    Widget reviewExceptions() => TextButton(
      onPressed: () =>
          openOperationalDesk(context, c, tab: 2, property: selected),
      child: Text(ui('Review exceptions')),
    );
    final sections = [
      _OperationsSection(
        title: ui('Guest readiness'),
        icon: Icons.how_to_reg_outlined,
        empty: ui('No upcoming guests.'),
        pending: !c.hasSection('journeys') && c.refreshing,
        items: [
          for (final row in guests)
            _OperationRow(
              title: text(row, 'guest_name'),
              detail:
                  '${propertyName(row)} · ${uiDate(text(row, 'arrival_date'))}',
              status: ui(switch (row['actual_stay_state']) {
                'arrived' => 'Actually arrived',
                'departed' => 'Actually departed',
                _ => text(row, 'current_stage'),
              }),
              onTap: () => openReservation(text(row, 'id')),
              action: openStay == null
                  ? null
                  : TextButton(
                      onPressed: () => openStay!(
                        text(row, 'id'),
                        row['actual_stay_state'] == 'arrived' ||
                                row['actual_stay_state'] == 'departed'
                            ? StayOperation.checkOut
                            : StayOperation.checkIn,
                      ),
                      child: Text(
                        ui(switch (row['actual_stay_state']) {
                          'arrived' => 'Check out',
                          'departed' => 'Review stay',
                          _ => 'Check in',
                        }),
                      ),
                    ),
            ),
        ],
      ),
      _OperationsSection(
        title: ui('Cleaning assignments'),
        icon: Icons.cleaning_services_outlined,
        empty: ui('No cleaning assignments for today or tomorrow.'),
        pending: !c.hasSection('intelligence') && c.refreshing,
        items: [
          for (final row in cleaning)
            _OperationRow(
              title: [
                propertyName(row),
                text(row, 'unit_label'),
              ].where((value) => value.isNotEmpty).join(' · '),
              detail:
                  '${uiDate(text(row, 'scheduled_date'))} · ${row['assigned_name'] ?? ui('Unassigned')}',
              status: ui(text(row, 'status')),
              onTap: openCleaning == null
                  ? null
                  : () => openCleaning!(
                      text(row, 'id'),
                      assign:
                          c.hasSection('team') && row['status'] != 'complete'
                          ? () => editWork(
                              context,
                              WorkAssignmentDialog(c: c, work: row),
                            )
                          : null,
                    ),
            ),
        ],
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add, size: 17),
            onPressed: !c.hasSection('team') || properties.isEmpty
                ? null
                : () => editWork(
                    context,
                    WorkAssignmentDialog(
                      c: c,
                      initialProperty: selected.isEmpty ? null : selected,
                    ),
                  ),
            label: Text(ui('Create cleaning task')),
          ),
        ],
      ),
      _OperationsSection(
        title: ui('Open maintenance'),
        icon: Icons.handyman_outlined,
        empty: ui('No open maintenance.'),
        pending: !c.hasSection('intelligence') && c.refreshing,
        items: [
          for (final row in maintenance)
            _OperationRow(
              title: text(row, 'title'),
              detail: propertyName(row),
              status: ui(text(row, 'status')),
              onTap: () => openMaintenance(context, row),
            ),
        ],
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.add, size: 17),
            onPressed: properties.isEmpty
                ? null
                : () => editWork(
                    context,
                    MaintenanceEditor(
                      c: c,
                      initialProperty: selected.isEmpty ? null : selected,
                    ),
                  ),
            label: Text(ui('Report issue')),
          ),
        ],
      ),
      _OperationsSection(
        title: ui('Needs attention'),
        icon: Icons.priority_high,
        empty: ui('No urgent actions or decisions.'),
        pending: !c.hasSection('intelligence') && c.refreshing,
        items: [
          for (final row in urgent)
            _OperationRow(
              title: ui(text(row, 'title')),
              detail: ui(text(row, 'detail')),
              onTap: text(row, 'reservation_id').isEmpty
                  ? () => openOperationalDesk(
                      context,
                      c,
                      tab: 2,
                      property: selected,
                    )
                  : () => openReservation(text(row, 'reservation_id')),
            ),
          for (final row in approvals)
            _OperationRow(
              title: ui(text(row, 'title')),
              detail: propertyName(row),
              onTap: () =>
                  openOperationalDesk(context, c, tab: 1, property: selected),
            ),
        ],
        actions: [
          if (approvals.isNotEmpty) reviewDecisions(),
          if (scoped(optionalRows(intel['exceptions'])).isNotEmpty)
            reviewExceptions(),
        ],
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PmsPageHeader(
          eyebrow: '',
          title: ui('Operations'),
          description: c.hasSection('intelligence')
              ? [
                  ui('${urgent.length} urgent'),
                  ui('${approvals.length} decisions pending'),
                ].join(' · ')
              : '',
          actions: [
            if (properties.length > 1)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 250),
                child: DropdownButton<String>(
                  key: const ValueKey('operations-property'),
                  value: selected,
                  isExpanded: true,
                  onChanged: onPropertyChanged,
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(ui('All properties')),
                    ),
                    for (final item in properties)
                      DropdownMenuItem(
                        value: text(item, 'id'),
                        child: Text(
                          c.propertyLabel(text(item, 'name')),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        LayoutBuilder(
          builder: (context, box) {
            final columns = box.maxWidth >= 750 ? 2 : 1;
            final width = (box.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final section in sections)
                  SizedBox(width: width, child: section),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        _OperationsSection(
          title: ui('Activity timeline'),
          icon: Icons.history,
          empty: ui('No recent activity.'),
          pending: !c.hasSection('timeline') && c.refreshing,
          subtitle: selected.isEmpty ? '' : ui('All properties'),
          items: [
            for (final row in c.activity)
              TimelineEntry(
                time: uiDateTime(text(row, 'created_at')),
                timeWidth: 118,
                title: c.activityLabel(row),
                detail: text(row, 'actor', 'Delvane'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        tools,
      ],
    );
  }
}

class _OperationsSection extends StatelessWidget {
  const _OperationsSection({
    required this.title,
    required this.icon,
    required this.empty,
    required this.pending,
    required this.items,
    this.subtitle = '',
    this.actions = const [],
  });

  final String title, subtitle, empty;
  final IconData icon;
  final bool pending;
  final List<Widget> items, actions;

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: PmsStyle.panelLine)),
    ),
    padding: const EdgeInsets.fromLTRB(2, 13, 2, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: PmsStyle.ink),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (items.isNotEmpty)
              Text(
                '${items.length}',
                style: const TextStyle(color: PmsStyle.muted),
              ),
          ],
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: const TextStyle(color: PmsStyle.muted, fontSize: 12),
          ),
        const SizedBox(height: 8),
        if (pending) const LinearProgressIndicator(),
        if (!pending && items.isEmpty)
          Text(
            empty,
            style: const TextStyle(color: PmsStyle.muted, fontSize: 13),
          ),
        ...items.take(4),
        if (items.length > 4)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            dense: true,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(ui('+${items.length - 4} more')),
            children: items.skip(4).toList(),
          ),
        if (actions.isNotEmpty) Wrap(spacing: 8, children: actions),
      ],
    ),
  );
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({
    required this.title,
    required this.detail,
    this.status = '',
    this.onTap,
    this.action,
  });

  final String title, detail, status;
  final VoidCallback? onTap;
  final Widget? action;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 2),
    leading: onTap == null ? const Icon(Icons.circle, size: 7) : null,
    dense: true,
    minTileHeight: 42,
    visualDensity: VisualDensity.compact,
    title: Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: detail.isEmpty && status.isEmpty
        ? null
        : Text(
            [
              if (detail.isNotEmpty) detail,
              if (status.isNotEmpty) status,
            ].join(' · '),
            style: const TextStyle(color: PmsStyle.muted, fontSize: 12),
          ),
    trailing:
        action ??
        (onTap == null ? null : const Icon(Icons.chevron_right, size: 18)),
    onTap: onTap,
  );
}
