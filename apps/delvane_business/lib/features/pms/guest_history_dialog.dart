import 'package:material_ui/material_ui.dart';

import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

class GuestHistoryDialog extends StatefulWidget {
  const GuestHistoryDialog({super.key, required this.api, required this.id});
  final PmsWorkflows api;
  final String id;
  @override
  State<GuestHistoryDialog> createState() => _GuestHistoryDialogState();
}

class _GuestHistoryDialogState extends State<GuestHistoryDialog>
    with PmsActions<GuestHistoryDialog> {
  Json? data;
  Future<void> preference() async {
    final changed = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => GuestPreferenceDialog(api: widget.api, id: widget.id),
    );
    if (changed == true && mounted) await load();
  }

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await perform(() async {
      data = await widget.api.object('/api/guests/${idPath(widget.id)}');
    });
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: data == null
        ? ui('Guest history')
        : text(jsonObject(data!['guest']), 'full_name'),
    width: 760,
    canClose: !busy,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        if (data == null && !busy) PmsButton(ui('Retry'), onPressed: load),
        if (data != null) ...[
          PmsEyebrow(ui('GUEST HISTORY')),
          for (final stay in optionalRows(data!['stays']))
            ListTile(
              title: Text(
                '${text(stay, 'property_name')} · ${text(stay, 'arrival_date')} → ${text(stay, 'departure_date')}',
              ),
              subtitle: Text(
                '${text(stay, 'source')} · ${ui(text(stay, 'status'))}',
              ),
            ),
          PmsEyebrow(ui('PREFERENCES')),
          Text(text(jsonObject(data!['guest']), 'preferred_language', '—')),
          for (final pref in optionalRows(data!['preferences']))
            PmsKeyValues({
              text(pref, 'preference_key'): text(pref, 'preference_value'),
            }),
          if (optionalRows(data!['preferences']).isEmpty)
            PmsEmpty(ui('No operational preferences recorded.')),
          Align(
            alignment: Alignment.centerRight,
            child: PmsButton(
              ui('+ Add preference'),
              onPressed: busy ? null : preference,
            ),
          ),
        ],
      ],
    ),
  );
}

class GuestPreferenceDialog extends StatefulWidget {
  const GuestPreferenceDialog({super.key, required this.api, required this.id});
  final PmsWorkflows api;
  final String id;
  @override
  State<GuestPreferenceDialog> createState() => _GuestPreferenceDialogState();
}

class _GuestPreferenceDialogState extends State<GuestPreferenceDialog>
    with PmsActions<GuestPreferenceDialog> {
  final keyInput = TextEditingController(), value = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    keyInput.dispose();
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Add preference'),
    width: 500,
    canClose: !busy,
    actions: [
      PmsButton(
        ui('Close'),
        onPressed: busy ? null : () => Navigator.pop(context),
      ),
      PmsButton(
        ui('Save'),
        primary: true,
        onPressed: busy
            ? null
            : () async {
                if (!form.currentState!.validate()) return;
                final ok = await perform(() async {
                  await widget.api.change(
                    'POST',
                    '/api/guests/${idPath(widget.id)}/preferences',
                    {
                      'preference_key': keyInput.text,
                      'preference_value': value.text,
                    },
                  );
                });
                if (ok && context.mounted) Navigator.pop(context, true);
              },
      ),
    ],
    child: Form(
      key: form,
      child: Column(
        children: [
          errors(),
          PmsField(
            ui('Key'),
            controller: keyInput,
            required: true,
            hint: ui('e.g. pillow_preference'),
          ),
          PmsField(
            ui('Preferences'),
            controller: value,
            required: true,
            hint: ui('e.g. prefers an extra pillow'),
          ),
        ],
      ),
    ),
  );
}
