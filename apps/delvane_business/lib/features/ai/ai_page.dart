import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/components.dart';

class AiPage extends StatefulWidget {
  const AiPage({super.key, required this.controller});
  final BusinessController controller;
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final input = TextEditingController();
  final List<(String, String)> messages = [];
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  void ask(String question) {
    if (question.trim().isEmpty) return;
    final data = widget.controller.snapshot!;
    final q = question.toLowerCase();
    final response = q.contains('task') || q.contains('team')
        ? 'The sample workspace has ${data.tasks.length - widget.controller.completedTasks.length} open tasks. Review Operations for assignments. I have not changed or assigned any work.'
        : q.contains('arrival') || q.contains('arriv')
        ? 'In the mock dataset, Alex Morgan and Jamie Taylor arrive on 11 November 2026. See Reservations for their synthetic stays. No live arrivals have been checked.'
        : 'This is a scripted preview, not a connected AI model. I can demonstrate an arrival summary or an open-task briefing using the mock dataset. No operational action will be executed.';
    setState(() {
      messages.add((question.trim(), response));
      input.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          'A thoughtful second pair of eyes',
          subtitle: 'Scripted demo · No AI provider, tools, or autonomous actions connected',
          action: Icon(Icons.auto_awesome_outlined),
        ),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: DelvaneColors.canvas,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            ui(
              'Less searching. More knowing.\nTry a sample briefing to see how Delvane could support your day.',
            ),
            style: TextStyle(
              fontSize: 18,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final prompt in [
              'Summarize demo arrivals',
              'What tasks are open?',
            ])
              ActionChip(
                label: Text(ui(prompt)),
                onPressed: () => ask(prompt),
                avatar: const Icon(Icons.north_east, size: 15),
              ),
          ],
        ),
        const SizedBox(height: 22),
        for (final message in messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.$1,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: DelvaneColors.yellowSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    ui(message.$2),
                    style: const TextStyle(height: 1.7),
                  ),
                ),
              ],
            ),
          ),
        TextField(
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          key: const ValueKey('ai-question'),
          controller: input,
          onSubmitted: ask,
          decoration: InputDecoration(
            hintText: ui('Ask a demo question…'),
            suffixIcon: IconButton(
              tooltip: 'Ask demo assistant',
              onPressed: () => ask(input.text),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        ),
      ],
    ),
  );
}
