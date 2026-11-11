import 'package:flutter/material.dart';
import '../../app/controller.dart';
import '../../app/theme.dart';
import '../../shared/components.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final BusinessController controller;
  @override
  Widget build(BuildContext context) => AdaptiveColumns(
    primary: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            'Make yourself at home',
            subtitle: 'Preview preferences · Reset when the app restarts',
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Demo notification preference'),
            subtitle: const Text(
              'Stores a preference only; delivery is not connected.',
            ),
            value: controller.notifications,
            onChanged: controller.setNotifications,
          ),
          const Divider(height: 30),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Compact task cards'),
            subtitle: const Text('A little more room in Operations.'),
            value: controller.compactCards,
            onChanged: controller.setCompact,
          ),
          const Divider(height: 30),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.language_rounded),
            title: Text('English'),
            subtitle: Text('Additional languages are planned.'),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.payments_outlined),
            title: Text('Hungarian forint · HUF'),
            subtitle: Text('Currency used by the sample dataset.'),
          ),
        ],
      ),
    ),
    secondary: const Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle('Built for a calmer business'),
          Tag(
            'EARLY PREVIEW',
            color: DelvaneColors.yellowSoft,
            foreground: DelvaneColors.ink,
          ),
          SizedBox(height: 20),
          Text(
            'Delvane Business',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text(
            'Version 0.1.0 · Mock workspace',
            style: TextStyle(color: DelvaneColors.muted),
          ),
          Divider(height: 36),
          Text(
            'Backend integration: not connected',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          Text(
            'The FastAPI backend is preserved. This preview does not read databases, send messages, submit reports, or change channel availability.',
            style: TextStyle(color: DelvaneColors.muted, height: 1.7),
          ),
        ],
      ),
    ),
  );
}
