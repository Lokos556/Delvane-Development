import '../../core/localization/web_strings.dart';

import 'package:material_ui/material_ui.dart';

import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

class CancellationDialog extends StatefulWidget {
  const CancellationDialog({super.key, required this.api, required this.id});
  final PmsWorkflows api;
  final String id;
  @override
  State<CancellationDialog> createState() => _CancellationDialogState();
}

class _CancellationDialogState extends State<CancellationDialog>
    with PmsActions<CancellationDialog> {
  final reason = TextEditingController();
  String initiator = 'unknown';
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('Cancel reservation'),
    width: 550,
    canClose: !busy,
    actions: [
      PmsButton(
        ui('Keep reservation'),
        onPressed: busy ? null : () => Navigator.pop(context, false),
      ),
      PmsButton(
        ui('Confirm'),
        danger: true,
        onPressed: busy
            ? null
            : () async {
                if (await perform(() async {
                      await widget.api.change(
                        'DELETE',
                        '/api/reservations/${Uri.encodeComponent(widget.id)}',
                        {'initiator': initiator, 'reason': reason.text.trim()},
                      );
                    }) &&
                    mounted) {
                  Navigator.of(this.context).pop(true);
                }
              },
      ),
    ],
    child: Column(
      children: [
        errors(),
        PmsSelect(
          ui('Cancellation initiator'),
          value: initiator,
          items: {
            for (final item in ['unknown', 'guest', 'host', 'platform_system'])
              item: ui(item),
          },
          onChanged: busy ? null : (v) => setState(() => initiator = v),
        ),
        PmsField(
          ui('Cancellation reason (optional)'),
          controller: reason,
          lines: 3,
          maxLength: 1000,
        ),
      ],
    ),
  );
}
