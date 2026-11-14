import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'operations_workflows.dart';

class WorkAssignmentDialog extends StatefulWidget {
  const WorkAssignmentDialog({super.key, required this.c, this.work});
  final PmsController c;
  final Json? work;
  @override
  State<WorkAssignmentDialog> createState() => _WorkAssignmentDialogState();
}

class _WorkAssignmentDialogState extends State<WorkAssignmentDialog>
    with PmsActions<WorkAssignmentDialog> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final day = TextEditingController(
    text: DateTime.now().toIso8601String().substring(0, 10),
  );
  late String assignee = text(widget.work ?? {}, 'assigned_to');
  late String property = widget.c.rows('properties').isEmpty
      ? ''
      : text(widget.c.rows('properties').first, 'id');
  @override
  void dispose() {
    title.dispose();
    day.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (widget.work == null && property.isEmpty) return;
    if (await perform(() async {
          final flow = OperationsWorkflows(widget.c);
          if (widget.work == null) {
            await flow.createCleaning({
              'property_id': property,
              'title': title.text.trim(),
              'scheduled_date': day.text,
              'assigned_to': assignee.isEmpty ? null : assignee,
            });
          } else {
            await flow.assign(widget.work!, assignee);
          }
        }) &&
        mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.work?['kind'] == 'maintenance'
        ? 'maintenance'
        : 'cleaner';
    final people = optionalRows(widget.c.object('team')['members']).where(
      (m) => m['role'] == role && (m['active'] == 1 || m['active'] == true),
    );
    final choices = {
      '': ui('Unassigned'),
      for (final m in people) text(m, 'id'): text(m, 'full_name'),
    };
    // A suspended/changed assignee is displayed but cannot be silently retained.
    final valid = choices.containsKey(assignee);
    return PmsModal(
      title: ui(widget.work == null ? 'Create cleaning task' : 'Assign work'),
      width: 600,
      canClose: !busy,
      actions: [
        PmsButton(
          ui('Cancel'),
          onPressed: busy ? null : () => Navigator.pop(context),
        ),
        PmsButton(
          ui('Save'),
          primary: true,
          onPressed: busy || !valid ? null : save,
        ),
      ],
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            errors(),
            if (widget.work == null) ...[
              PmsField(
                ui('Title'),
                controller: title,
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? ui('Required') : null,
              ),
              PmsField(
                ui('Date'),
                controller: day,
                hint: 'YYYY-MM-DD',
                validator: (v) {
                  final parsed = DateTime.tryParse(v ?? '');
                  return parsed == null ||
                          parsed.toIso8601String().substring(0, 10) != v
                      ? ui('Enter a valid date.')
                      : null;
                },
              ),
              PmsSelect(
                ui('Property'),
                value: property,
                items: {
                  for (final p in widget.c.rows('properties'))
                    text(p, 'id'): text(p, 'name'),
                },
                onChanged: busy ? null : (v) => setState(() => property = v),
              ),
            ],
            if (!valid) Text(ui('Select an active assignee.')),
            PmsSelect(
              ui('Assignee'),
              value: valid ? assignee : '',
              items: choices,
              onChanged: busy ? null : (v) => setState(() => assignee = v),
            ),
          ],
        ),
      ),
    );
  }
}
