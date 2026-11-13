import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/app/app.dart';
import 'package:delvane_business/app/controller.dart';
import 'package:delvane_business/app/destination.dart';
import 'package:delvane_business/data/mock_business_repository.dart';
import 'package:delvane_business/shared/app_shell.dart';

void main() {
  for (final size in [
    const Size(320, 780),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(844, 390),
    const Size(1024, 500),
    const Size(1440, 1000),
  ]) {
    testWidgets(
      'all seven screens fit ${size.width.toInt()}x${size.height.toInt()} without layout exceptions',
      (tester) async {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(const DelvaneBusinessApp(demoMode: true));
        await tester.pumpAndSettle();
        final controller = tester
            .widget<AppShell>(find.byType(AppShell))
            .controller;
        for (final destination in Destination.values) {
          controller.navigate(destination);
          await tester.pumpAndSettle();
          expect(find.textContaining('Mock data only'), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '${destination.name} at $size',
          );
        }
      },
    );
  }
  testWidgets(
    'desktop navigation and reservation search work with synthetic data',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const DelvaneBusinessApp(demoMode: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-reservations')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('reservation-search')),
        'Robin',
      );
      await tester.pumpAndSettle();
      expect(find.text('Robin Lee'), findsOneWidget);
      expect(find.text('Alex Morgan'), findsOneWidget); // sidebar profile only
      await tester.tap(find.text('Robin Lee'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Read-only preview'), findsOneWidget);
    },
  );
  testWidgets('mobile menu reaches settings', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DelvaneBusinessApp(demoMode: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Make yourself at home'), findsOneWidget);
  });
  testWidgets('reception saves a local draft without sending', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const DelvaneBusinessApp(demoMode: true));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<AppShell>(find.byType(AppShell))
        .controller;
    controller.navigate(Destination.reception);
    await tester.pumpAndSettle();
    await tester.tap(find.text('A little earlier than planned'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Synthetic draft only');
    await tester.ensureVisible(find.text('Save demo draft'));
    await tester.tap(find.text('Save demo draft'));
    await tester.pumpAndSettle();
    expect(controller.drafts['m1'], 'Synthetic draft only');
    expect(find.textContaining('Nothing was sent'), findsOneWidget);
  });
  testWidgets(
    'AI suggestions disclose scripted answers and settings stay local',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const DelvaneBusinessApp(demoMode: true));
      await tester.pumpAndSettle();
      final controller = tester
          .widget<AppShell>(find.byType(AppShell))
          .controller;
      controller.navigate(Destination.ai);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summarize demo arrivals'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No live arrivals have been checked.'),
        findsOneWidget,
      );
      controller.navigate(Destination.settings);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compact task cards'));
      await tester.pumpAndSettle();
      expect(controller.compactCards, isTrue);
    },
  );
  test('demo task state and drafts are local controller state', () async {
    final controller = BusinessController(MockBusinessRepository());
    await controller.load();
    controller.toggleTask('t1');
    controller.saveDraft('m1', 'Synthetic reply');
    expect(controller.completedTasks, contains('t1'));
    expect(controller.drafts['m1'], 'Synthetic reply');
    final fresh = BusinessController(MockBusinessRepository());
    await fresh.load();
    expect(fresh.completedTasks, isEmpty);
    expect(fresh.drafts, isEmpty);
    controller.dispose();
    fresh.dispose();
  });
}
