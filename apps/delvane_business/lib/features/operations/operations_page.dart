import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/components.dart';

class OperationsPage extends StatelessWidget {
  const OperationsPage({super.key, required this.controller});
  final BusinessController controller;
  @override
  Widget build(BuildContext context) {
    final data = controller.snapshot!;
    final tasks = data.tasks
        .where((t) => controller.includes(t.propertyId))
        .toList();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            'A good day, together',
            subtitle:
                '${tasks.where((t) => controller.completedTasks.contains(t.id)).length} of ${tasks.length} sample tasks complete',
          ),
          for (final task in tasks)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: EdgeInsets.all(controller.compactCards ? 8 : 16),
              decoration: BoxDecoration(
                color: DelvaneColors.canvas,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: controller.completedTasks.contains(task.id),
                    onChanged: (_) => controller.toggleTask(task.id),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration:
                                controller.completedTasks.contains(task.id)
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${data.propertyName(task.propertyId)} · ${task.assignee}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: DelvaneColors.muted,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            Tag(
                              controller.completedTasks.contains(task.id)
                                  ? 'Completed'
                                  : task.urgent
                                  ? 'Priority'
                                  : 'Scheduled',
                              color:
                                  task.urgent &&
                                      !controller.completedTasks.contains(
                                        task.id,
                                      )
                                  ? DelvaneColors.yellowSoft
                                  : DelvaneColors.greenSoft,
                            ),
                            Text(
                              task.due,
                              style: const TextStyle(
                                fontSize: 11,
                                color: DelvaneColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Demo task updates stay on this device for this session only.',
            style: TextStyle(fontSize: 11, color: DelvaneColors.muted),
          ),
        ],
      ),
    );
  }
}
