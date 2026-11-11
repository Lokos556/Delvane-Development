import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../shared/components.dart';

class ReceptionPage extends StatefulWidget {
  const ReceptionPage({super.key, required this.controller});
  final BusinessController controller;
  @override
  State<ReceptionPage> createState() => _ReceptionPageState();
}

class _ReceptionPageState extends State<ReceptionPage> {
  String? selectedId;
  final draft = TextEditingController();
  @override
  void dispose() {
    draft.dispose();
    super.dispose();
  }

  void select(GuestMessage message) {
    setState(() {
      selectedId = message.id;
      draft.text = widget.controller.drafts[message.id] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.controller.snapshot!;
    final messages = data.messages
        .where((m) => widget.controller.includes(m.propertyId))
        .toList();
    final selected = messages.where((m) => m.id == selectedId).firstOrNull;
    return AdaptiveColumns(
      breakpoint: 900,
      primary: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionTitle(
              'Your inbox',
              subtitle: 'Sample guest conversations · No channel connection',
            ),
            for (final message in messages)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Material(
                  color: selectedId == message.id
                      ? DelvaneColors.yellowSoft
                      : DelvaneColors.canvas,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => select(message),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Initials(message.sender),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    Text(
                                      message.sender,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    Text(
                                      message.time,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: DelvaneColors.muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  message.subject,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  data.propertyName(message.propertyId),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: DelvaneColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (message.unread)
                            const Icon(
                              Icons.circle,
                              size: 7,
                              color: DelvaneColors.green,
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
      secondary: Panel(
        child: selected == null
            ? const EmptyState(
                'A conversation starts here',
                'Select a sample message to read it and save a local reply draft.',
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(selected.sender, subtitle: selected.subject),
                  Text(selected.body),
                  const Divider(height: 36),
                  const Tag(
                    'LOCAL DRAFT',
                    color: DelvaneColors.yellowSoft,
                    foreground: DelvaneColors.ink,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: draft,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText: 'Write a demo reply…',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      widget.controller.saveDraft(selected.id, draft.text);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Demo draft saved in memory. Nothing was sent.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Save demo draft'),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sending is not connected. Drafts are cleared when the app restarts.',
                    style: TextStyle(color: DelvaneColors.muted, fontSize: 11),
                  ),
                ],
              ),
      ),
    );
  }
}
