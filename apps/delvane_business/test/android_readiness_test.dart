import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'support/fake_pms.dart';

FakePms androidFixture() {
  final pms = FakePms();
  final fixtures =
      jsonDecode(File('test/fixtures/web_reference.json').readAsStringSync())
          as Map;
  for (final e in fixtures.entries) {
    pms.overrides[e.key as String] = pms.json(e.value);
  }
  return pms;
}

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(393, 852);
  t.view.devicePixelRatio = 1;
  t.view.padding = const FakeViewPadding(top: 28, bottom: 24);
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  addTearDown(t.view.resetPadding);
  addTearDown(t.view.resetViewInsets);
}

void main() {
  for (final page in [
    PmsPage.today,
    PmsPage.reservations,
    PmsPage.inbox,
    PmsPage.intelligence,
    PmsPage.operations,
    PmsPage.team,
    PmsPage.security,
  ]) {
    testWidgets('Android phone insets and touch layout: ${page.name}', (
      t,
    ) async {
      phone(t);
      final pms = androidFixture();
      final auth = await signedIn(pms);
      try {
        await t.pumpWidget(
          MaterialApp(
            theme: pmsTheme().copyWith(platform: TargetPlatform.android),
            home: PmsShell(auth: auth, initialPage: page),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byTooltip('Open main menu'), findsOneWidget);
        expect(find.text('No demo data has been substituted.'), findsNothing);
        await t.tap(find.byTooltip('Open main menu'));
        await t.pumpAndSettle();
        expect(find.byType(Drawer), findsOneWidget);
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    });
  }
  testWidgets(
    'Android IME resizes Intelligence and keeps composer above keyboard',
    (t) async {
      phone(t);
      final pms = androidFixture();
      final auth = await signedIn(pms);
      try {
        await t.pumpWidget(
          MaterialApp(
            theme: pmsTheme().copyWith(platform: TargetPlatform.android),
            home: PmsShell(auth: auth, initialPage: PmsPage.intelligence),
          ),
        );
        await t.pumpAndSettle();
        final composer = find.byKey(const ValueKey('intelligence-composer'));
        await t.tap(composer);
        await t.pumpAndSettle();
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pumpAndSettle();
        expect(t.getBottomRight(composer).dy, lessThanOrEqualTo(552));
        await t.enterText(composer, 'Who still needs registration?');
        expect(
          t.widget<TextField>(composer).controller!.text,
          'Who still needs registration?',
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    },
  );
}
