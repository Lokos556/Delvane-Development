import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:flutter/material.dart';
import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_dialogs.dart';
import 'pms_style.dart';
import 'pms_workflows.dart';

/// The reference rosaBar/ask control, using its existing local-answer endpoint.
class PmsAskBar extends StatefulWidget {
  const PmsAskBar({super.key, required this.c});
  final PmsController c;
  @override
  State<PmsAskBar> createState() => _PmsAskBarState();
}

class _PmsAskBarState extends State<PmsAskBar> with PmsActions<PmsAskBar> {
  final input = TextEditingController();
  String? answer;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> ask() async {
    if (busy || input.text.trim().isEmpty) return;
    await perform(() async {
      final reply = jsonObject(
        await PmsWorkflows(
          widget.c,
        ).change('POST', '/api/rosa/ask', {'message': input.text}),
      );
      if (mounted) {
        setState(() {
          answer = text(reply, 'answer');
          input.clear();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width <= 760;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (answer != null || failure != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PmsCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (answer != null)
                    SelectableText(answer!, key: const ValueKey('ask-answer')),
                  errors(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PmsIconButton(
                      '×',
                      label: ui('Close answer'),
                      size: 28,
                      onPressed: () => setState(() {
                        answer = null;
                        failure = null;
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
        SizedBox(
          height: mobile ? 74 : 84,
          child: PmsCard(
            radius: 24,
            color: const Color(0xCFFFFFFF),
            padding: const EdgeInsets.all(9),
            child: Row(
              children: [
                Image.asset(
                  PmsStyle.logo,
                  width: mobile ? 44 : 64,
                  height: mobile ? 44 : 64,
                ),
                Expanded(
                  child: TextField(
                    controller: input,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => ask(),
                    style: const TextStyle(fontSize: 14),
                    decoration: InputDecoration(
                      hintText: ui('Ask Delvane anything…'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Color(0x66FFFFFF),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  height: 64,
                  child: PmsButton(ui('Ask'), onPressed: busy ? null : ask),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
