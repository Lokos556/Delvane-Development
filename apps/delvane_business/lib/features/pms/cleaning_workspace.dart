import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'operational_visuals.dart';
import 'pms_style.dart';

class CleaningWorkspace extends StatefulWidget {
  const CleaningWorkspace({
    super.key,
    required this.controller,
    required this.id,
    this.assign,
  });
  final PmsController controller;
  final String id;
  final VoidCallback? assign;

  @override
  State<CleaningWorkspace> createState() => _CleaningWorkspaceState();
}

class _CleaningWorkspaceState extends State<CleaningWorkspace>
    with PmsActions<CleaningWorkspace> {
  Json? task;
  bool needsRefresh = false;
  bool changed = false;
  String get path => '/api/work-tasks/${idPath(widget.id)}';

  @override
  void initState() {
    super.initState();
    perform(load);
  }

  Future<void> load() async {
    final value = jsonObject(await widget.controller.api.get(path));
    if (!mounted) return;
    setState(() {
      task = value;
      needsRefresh = false;
    });
  }

  Future<void> change(String method, String suffix, [Json? body]) =>
      perform(() async {
        await widget.controller.mutate(method, '$path/$suffix', body);
        changed = true;
        if (!mounted) return;
        setState(() => needsRefresh = true);
        await load();
      });

  @override
  Widget build(BuildContext context) {
    final row = task;
    final items = optionalRows(row?['checklist']);
    final working = row?['status'] == 'in_progress';
    final canWork = !busy && !needsRefresh && row?['can_work'] == true;
    bool complete(Json item) => const {true, 1}.contains(item['completed']);
    return PmsModal(
      mobileFullScreen: true,
      title: ui('Cleaning checklist'),
      canClose: !busy,
      actions: [
        if (row?['can_work'] == true)
          PmsButton(
            ui(working ? 'Finish cleaning' : 'Start cleaning'),
            primary: true,
            onPressed:
                !canWork ||
                    (working && (items.isEmpty || !items.every(complete)))
                ? null
                : () => change(
                    'POST',
                    working ? 'finish' : 'start',
                    working ? {'note': ''} : null,
                  ),
          ),
        if (row != null && widget.assign != null)
          PmsButton(
            ui('Assignment'),
            onPressed: busy
                ? null
                : () {
                    Navigator.pop(context, changed);
                    widget.assign!();
                  },
          ),
        PmsButton(
          ui('Back'),
          onPressed: busy ? null : () => Navigator.pop(context, changed),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          errors(),
          if (failure != null)
            PmsButton(
              ui('Retry'),
              onPressed: busy ? null : () => perform(load),
            ),
          if (row != null) ...[
            Text(
              [
                text(row, 'property_name'),
                text(row, 'unit_label'),
              ].where((s) => s.isNotEmpty).join(' · '),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              '${uiDate(text(row, 'scheduled_date'))} · ${ui(text(row, 'status'))}',
            ),
            Text(text(row, 'assigned_name', ui('Unassigned'))),
            if (text(row, 'detail').isNotEmpty) Text(text(row, 'detail')),
            const Divider(height: 24),
            WorkProgress(
              completed: items.where(complete).length,
              total: items.length,
            ),
            if (items.isNotEmpty) const SizedBox(height: 12),
            if (items.isEmpty) PmsEmpty(ui('No checklist items.')),
            for (final item in items)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(ui(text(item, 'label'))),
                value: complete(item),
                onChanged: canWork && working
                    ? (v) => change(
                        'PATCH',
                        'checklist/${idPath(text(item, 'id'))}',
                        {'completed': v == true},
                      )
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}
