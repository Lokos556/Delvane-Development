import 'pms_controller.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../workspace/workspace_models.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

Future<void> showGuestCheckinLinks(
  BuildContext context,
  List<Json> links, {
  bool simulated = false,
}) => showDialog<void>(
  context: context,
  useRootNavigator: false,
  builder: (_) => PmsModal(
    title: ui('Secure guest links'),
    eyebrow: ui('GUEST PRE-CHECK-IN'),
    width: 600,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          ui(
            simulated ? 'Simulation only. Nothing was sent to a guest.' : 'Send each guest their own link. Generating/copying a link does not send a message.',
          ),
        ),
        for (final link in links)
          PmsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text(link, 'guest_name')),
                Text(ui(text(link, 'completeness'))),
                SelectableText(text(link, 'url')),
                PmsButton(
                  ui('Copy link'),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: text(link, 'url'))),
                ),
              ],
            ),
          ),
      ],
    ),
  ),
);

class GuestLinkPicker extends StatefulWidget {
  const GuestLinkPicker({super.key, required this.api});
  final PmsWorkflows api;
  @override
  State<GuestLinkPicker> createState() => _GuestLinkPickerState();
}

class _GuestLinkPickerState extends State<GuestLinkPicker>
    with PmsActions<GuestLinkPicker> {
  List<Json> guests = [];
  String query = '';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() => perform(() async {
    guests = await widget.api.rows('/api/guests');
  }).then((_) {});
  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Choose a known guest profile'),
    width: 650,
    canClose: !busy,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        Text(
          ui(
            'Link only when you know this is the same person. A shared name is not proof of identity.',
          ),
        ),
        TextField(
          onChanged: (value) => setState(() => query = value.toLowerCase()),
          decoration: InputDecoration(labelText: ui('Search')),
        ),
        for (final g in guests.where(
          (g) => '${g['full_name']} ${g['email']} ${g['id']}'
              .toLowerCase()
              .contains(query),
        ))
          ListTile(
            title: Text(text(g, 'full_name')),
            subtitle: Text('${text(g, 'email')} · ${text(g, 'id')}'),
            onTap: busy ? null : () => Navigator.pop(context, g),
          ),
        if (!busy && guests.isEmpty) PmsButton(ui('Retry'), onPressed: load),
      ],
    ),
  );
}
