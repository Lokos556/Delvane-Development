import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:material_ui/material_ui.dart';

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
            title: Text(ui('Demo notification preference')),
            subtitle: Text(
              ui('Stores a preference only; delivery is not connected.'),
            ),
            value: controller.notifications,
            onChanged: controller.setNotifications,
          ),
          const Divider(height: 30),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(ui('Compact task cards')),
            subtitle: Text(ui('A little more room in Operations.')),
            value: controller.compactCards,
            onChanged: controller.setCompact,
          ),
          const Divider(height: 30),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.language_rounded),
            title: Text(ui('Language')),
            trailing: DropdownButton<String>(
              value: WebStrings.current.language,
              items: [
                for (final item in WebStrings.current.languages)
                  DropdownMenuItem(value: item[0], child: Text(item[1])),
              ],
              onChanged: (value) async {
                if (value == null) return;
                try {
                  await WebStrings.current.select(value);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ui('Language preference could not be saved.'),
                        ),
                      ),
                    );
                  }
                }
              },
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.payments_outlined),
            title: Text(ui('Hungarian forint · HUF')),
            subtitle: Text(ui('Currency used by the sample dataset.')),
          ),
        ],
      ),
    ),
    secondary: Panel(
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
            ui('Delvane Business'),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 8),
          Text(
            ui('Version 0.1.0 · Mock workspace'),
            style: TextStyle(color: DelvaneColors.muted),
          ),
          Divider(height: 36),
          Text(
            ui('Backend integration: not connected'),
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 10),
          Text(
            ui(
              'The FastAPI backend is preserved. This preview does not read databases, send messages, submit reports, or change channel availability.',
            ),
            style: TextStyle(color: DelvaneColors.muted, height: 1.7),
          ),
        ],
      ),
    ),
  );
}
