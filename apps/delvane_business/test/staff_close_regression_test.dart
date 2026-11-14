import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/app/app.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';

import 'support/fake_pms.dart';
import 'support/management_pms.dart';

void main() {
  testWidgets('staff account close survives route reverse and parent refresh', (
    tester,
  ) async {
    final pms = ManagementPms();
    final auth = await signedIn(pms);
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      DelvaneBusinessApp(
        auth: auth,
        workspaceBuilder: (a) => PmsShell(auth: a, initialPage: PmsPage.team),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Manage').first);
    await tester.tap(find.text('Manage').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextFormField).first);
    await tester.pump();
    await tester.tap(find.byTooltip('Close dialog'));
    for (final delay in [1, 16, 50, 200, 500]) {
      await tester.pump(Duration(milliseconds: delay));
      expect(tester.takeException(), isNull);
    }
    await tester.pumpAndSettle();
    expect(find.text('Synthetic Worker'), findsWidgets);
  });
}
