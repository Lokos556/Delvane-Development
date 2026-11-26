import 'section_picker.dart';

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

/// Active web v264OpsLayer: reference decisions are record resolutions, not an
/// executor for purchases, refunds or other commercial operations.
Future<void> openOperationalDesk(
  BuildContext context,
  PmsController c, {
  int tab = 0,
  String property = '',
}) async {
  if (!c.user.isOperator) return;
  await showGeneralDialog<void>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: false,
    barrierLabel: 'Live context',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (_, animation, secondaryAnimation) =>
        OperationalDesk(c: c, tab: tab, property: property),
    transitionBuilder: (_, animation, secondaryAnimation, child) =>
        SlideTransition(
          position: Tween(
            begin: const Offset(.03, 0),
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
  );
}

class OperationalDesk extends StatefulWidget {
  const OperationalDesk({
    super.key,
    required this.c,
    this.tab = 0,
    this.property = '',
  });
  final PmsController c;
  final int tab;
  final String property;
  @override
  State<OperationalDesk> createState() => _OperationalDeskState();
}

class _OperationalDeskState extends State<OperationalDesk>
    with PmsActions<OperationalDesk> {
  late int selected = widget.tab;
  // The parent refresh clears its page data while this route animates closed.
  // Keep only the opened session's snapshot until the protected route is disposed.
  late final Json snapshot = Map<String, dynamic>.from(
    widget.c.object('intelligence'),
  );
  static const labels = ['At a glance', 'Needs you', 'Exceptions', 'Next 48h'];

  Future<void> resolve(Json item, String decision) async {
    final ok = await perform(() async {
      await PmsWorkflows(widget.c).change(
        'POST',
        '/api/approvals/${idPath(text(item, 'id'))}/resolve',
        {'decision': decision},
      );
    });
    // Close the accepted action before refreshing. A later read failure must not
    // leave an accepted decision available to submit again.
    if (ok && mounted) {
      Navigator.pop(context);
      await widget.c.load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = snapshot;
    List<Json> scoped(String key) => optionalRows(d[key])
        .where(
          (row) =>
              widget.property.isEmpty || row['property_id'] == widget.property,
        )
        .toList();
    final approvals = scoped('approvals');
    final exceptions = scoped('exceptions');
    final arrivals = scoped('arrivals');
    final allTasks = scoped('tasks');
    final handled = widget.property.isEmpty
        ? d['handled'] ?? 0
        : math.max(
            0,
            allTasks.length +
                arrivals.length +
                scoped('departures').length -
                approvals.length,
          );
    final tasks = allTasks.where((t) => t['status'] != 'complete').take(8);
    final viewport = MediaQuery.sizeOf(context);
    final mobile = viewport.width <= 850;
    final workspace = math.max(
      0.0,
      viewport.width - (viewport.width > 760 ? 273 : 22),
    );
    final width = mobile
        ? viewport.width
        : math.min(
            viewport.width <= 1180 ? 820.0 : 860.0,
            workspace * (viewport.width <= 1180 ? .82 : .72),
          );
    final counts = [null, approvals.length, exceptions.length, arrivals.length];
    return PopScope(
      canPop: !busy,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          viewport.width > 760 ? 254 : 11,
          viewport.width > 760 ? 17 : 75,
          viewport.width > 760 ? 19 : 11,
          viewport.width > 760 ? 19 : 10,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(mobile ? 18 : 24),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: busy ? null : () => Navigator.pop(context),
                  child: const ColoredBox(color: Color(0x36000000)),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: width,
                  child: Material(
                    color: PmsStyle.canvas,
                    child: SafeArea(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              mobile ? 17 : 26,
                              mobile ? 17 : 22,
                              mobile ? 17 : 26,
                              mobile ? 12 : 16,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.c.t(labels[0]),
                                        style: const TextStyle(
                                          fontSize: 26.4,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PmsIconButton(
                                  '×',
                                  label: ui('Close live context'),
                                  onPressed: busy
                                      ? null
                                      : () => Navigator.pop(context),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1, color: Color(0xFFE1D6C5)),
                          PmsSectionPicker(
                            labels: [
                              for (var i = 0; i < labels.length; i++)
                                '${widget.c.t(labels[i])}${counts[i] == null ? '' : '  ${counts[i]}'}',
                            ],
                            selected: selected,
                            onChanged: busy
                                ? null
                                : (i) => setState(() => selected = i),
                          ),
                          const Divider(height: 1, color: Color(0xFFE6DCCB)),
                          Expanded(
                            child: PmsScrollPane(
                              key: ValueKey(selected),
                              padding: EdgeInsets.fromLTRB(
                                mobile ? 16 : 28,
                                mobile ? 18 : 24,
                                mobile ? 16 : 28,
                                mobile ? 28 : 34,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  errors(),
                                  if (selected == 0) ...[
                                    card([
                                      PmsEyebrow(ui('LIVE BRIEFING')),
                                      Text(
                                        intelligenceBrief(d),
                                        style: const TextStyle(
                                          fontSize: 19.52,
                                          height: 1.48,
                                        ),
                                      ),
                                    ]),
                                    const SizedBox(height: 18),
                                    PmsColumns([
                                      for (final metric in [
                                        ('Needs you', approvals.length),
                                        ('Delvane handling', handled),
                                        ('Exceptions', exceptions.length),
                                        ('Next 48h', arrivals.length),
                                      ])
                                        card([
                                          Text(
                                            widget.c.t(metric.$1),
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(
                                            '${metric.$2}',
                                            style: const TextStyle(
                                              fontSize: 27.2,
                                            ),
                                          ),
                                        ]),
                                    ], columns: mobile ? 2 : 4),
                                    const SizedBox(height: 26),
                                    heading(ui('Delvane handling')),
                                    if (tasks.isEmpty)
                                      PmsEmpty(
                                        ui(
                                          'No exceptions. Everything is moving.',
                                        ),
                                      ),
                                    for (final task in tasks)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 9,
                                        ),
                                        child: card([
                                          Text(
                                            text(task, 'property_name'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(text(task, 'title')),
                                          PmsBadge(text(task, 'status')),
                                        ]),
                                      ),
                                  ],
                                  if (selected == 1) ...[
                                    heading(ui('Needs you')),
                                    if (approvals.isEmpty)
                                      PmsEmpty(
                                        ui('No decisions waiting for you.'),
                                      ),
                                    PmsColumns([
                                      for (final item in approvals)
                                        card([
                                          PmsEyebrow(
                                            text(
                                              item,
                                              'kind',
                                            ).replaceAll('_', ' '),
                                          ),
                                          Text(
                                            text(item, 'title'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            text(item, 'detail'),
                                            style: const TextStyle(
                                              fontSize: 13.12,
                                            ),
                                          ),
                                          const SizedBox(height: 13),
                                          PmsCard(
                                            radius: 11,
                                            shadow: false,
                                            color: const Color(0xFFF1E9DC),
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 11,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  ui('ROSA RECOMMENDS'),
                                                  style: TextStyle(
                                                    fontSize: 8.32,
                                                  ),
                                                ),
                                                Text(
                                                  text(item, 'recommendation'),
                                                  style: const TextStyle(
                                                    fontSize: 11.68,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          Wrap(
                                            alignment: WrapAlignment.end,
                                            spacing: 8,
                                            children: [
                                              PmsButton(
                                                ui('Decline'),
                                                small: true,
                                                onPressed: busy
                                                    ? null
                                                    : () => resolve(
                                                        item,
                                                        'Declined',
                                                      ),
                                              ),
                                              PmsButton(
                                                ui('Approve'),
                                                small: true,
                                                onPressed: busy
                                                    ? null
                                                    : () => resolve(
                                                        item,
                                                        'Approved',
                                                      ),
                                              ),
                                            ],
                                          ),
                                        ]),
                                    ], columns: mobile ? 1 : 2),
                                  ],
                                  if (selected == 2) ...[
                                    heading(ui('Exceptions')),
                                    if (exceptions.isEmpty)
                                      PmsEmpty(
                                        ui(
                                          'No exceptions. Everything is moving.',
                                        ),
                                      ),
                                    PmsColumns([
                                      for (final item in exceptions)
                                        card([
                                          PmsEyebrow(text(item, 'kind')),
                                          PmsBadge(
                                            text(item, 'severity'),
                                            tone: text(item, 'severity'),
                                          ),
                                          Text(
                                            text(item, 'title'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            text(item, 'detail'),
                                            style: const TextStyle(
                                              fontSize: 13.12,
                                            ),
                                          ),
                                        ]),
                                    ], columns: mobile ? 1 : 2),
                                  ],
                                  if (selected == 3) ...[
                                    heading(ui('Next 48h')),
                                    if (arrivals.isEmpty)
                                      PmsEmpty(
                                        ui(
                                          'No exceptions. Everything is moving.',
                                        ),
                                      ),
                                    for (final arrival in arrivals)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 9,
                                        ),
                                        child: card([
                                          PmsEyebrow(
                                            text(arrival, 'property_name'),
                                          ),
                                          Text(
                                            text(arrival, 'guest_name'),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            '${text(arrival, 'arrival_date')} · ${text(arrival, 'arrival_time')}',
                                          ),
                                          Text(
                                            ui(
                                              '${arrival['guest_count'] ?? 1} guests',
                                            ),
                                            style: const TextStyle(
                                              fontSize: 11,
                                            ),
                                          ),
                                        ]),
                                      ),
                                  ],
                                ],
                              ),
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
      ),
    );
  }

  Widget heading(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PmsEyebrow(ui('ROSA AI')),
        Text(
          widget.c.t(label),
          style: const TextStyle(fontSize: 23.2, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
  Widget card(List<Widget> children) => PmsCard(
    radius: 24,
    shadow: true,
    color: const Color(0xFFFFFAF2),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}
