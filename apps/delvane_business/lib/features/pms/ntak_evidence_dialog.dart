import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';

class NtakEvidenceDialog extends StatefulWidget {
  const NtakEvidenceDialog({
    super.key,
    required this.c,
    required this.propertyId,
    required this.jobId,
  });
  final PmsController c;
  final String propertyId, jobId;
  @override
  State<NtakEvidenceDialog> createState() => _NtakEvidenceDialogState();
}

class _NtakEvidenceDialogState extends State<NtakEvidenceDialog>
    with PmsActions<NtakEvidenceDialog> {
  final reason = TextEditingController();
  String? package;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> prepare() async {
    if (reason.text.trim().length < 3) {
      setState(() => failure = 'Enter a reason for accessing the evidence.');
      return;
    }
    await perform(() async {
      final result = await widget.c.api.post(
        '/api/government/ntak/properties/${Uri.encodeComponent(widget.propertyId)}/jobs/${Uri.encodeComponent(widget.jobId)}/evidence-export',
        {'reason': reason.text.trim()},
      );
      if (mounted) {
        setState(
          () => package = const JsonEncoder.withIndent('  ').convert(result),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => PmsModal(
    title: ui('NTAK evidence package'),
    width: 850,
    actions: [
      if (widget.c.user.role == 'owner')
        PmsButton(
          ui('Prepare evidence package'),
          onPressed: busy ? null : prepare,
        ),
      if (package != null)
        PmsButton(
          ui('Copy redacted JSON'),
          onPressed: busy
              ? null
              : () => Clipboard.setData(ClipboardData(text: package!)),
        ),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        errors(),
        Text(
          ui(
            'Delvane diagnostic package. This is not an officially accepted NTAK report.',
          ),
        ),
        Text(
          ui(
            'Raw protocol evidence stays encrypted on the server. Guest identity details and secrets are omitted.',
          ),
        ),
        PmsField('Reason', controller: reason),
        if (package != null) SelectableText(package!),
      ],
    ),
  );
}
