import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/features/pms/section_picker.dart';

/// Follow either responsive presentation through the visible controls.
Future<void> selectSection(WidgetTester tester, String label) async {
  final picker = find
      .byWidgetPredicate(
        (w) => w is PmsSectionPicker && w.labels.contains(label),
      )
      .first;
  var target = find.descendant(of: picker, matching: find.text(label));
  if (target.evaluate().isEmpty) {
    final trigger = find
        .descendant(of: picker, matching: find.byType(InkWell))
        .first;
    await tester.ensureVisible(trigger);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    target = find.text(label).last;
  }
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}
