import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/app/app.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/ask_bar.dart';

import 'support/fake_pms.dart';

FakePms visualPms() {
  final pms = FakePms();
  final fixture = jsonDecode(
    File('test/fixtures/web_reference.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  for (final e in fixture.entries) {
    pms.overrides[e.key] = pms.json(e.value);
  }
  return pms;
}

void main() {
  testWidgets(
    'reference Ask bar keeps its local-answer endpoint and session safeguards',
    (t) async {
      final pms = visualPms();
      pms.overrides['/api/rosa/ask'] = pms.json({
        'answer': 'Synthetic operational answer',
      });
      final a = await signedIn(pms);
      try {
        await t.pumpWidget(
          MaterialApp(
            home: PmsShell(auth: a, initialPage: PmsPage.team),
          ),
        );
        await t.pumpAndSettle();
        final input = find.descendant(
          of: find.byType(PmsAskBar),
          matching: find.byType(TextField),
        );
        await t.enterText(input, 'What needs attention?');
        await t.testTextInput.receiveAction(TextInputAction.send);
        await t.pumpAndSettle();
        expect(find.text('Synthetic operational answer'), findsOneWidget);
        final r = pms.requests.singleWhere((r) => r.path == '/api/rosa/ask');
        expect((r.body as Map)['message'], 'What needs attention?');
        expect(r.headers['X-Rosa-CSRF'], fakeCsrf);
        expect(t.widget<TextField>(input).controller!.text, isEmpty);
      } finally {
        await t.pumpWidget(const SizedBox());
        a.dispose();
      }
    },
  );
  testWidgets(
    'desktop navigation retains source 235px rail and 54px selected rows',
    (t) async {
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final pms = visualPms();
      final auth = await signedIn(pms);
      try {
        await t.pumpWidget(
          MaterialApp(
            home: PmsShell(auth: auth, initialPage: PmsPage.today),
          ),
        );
        await t.pumpAndSettle();
        expect(t.getSize(find.byKey(const ValueKey('pms-sidebar'))).width, 235);
        expect(
          t.getSize(find.byKey(const ValueKey('pms-nav-today'))).height,
          54,
        );
        await t.tap(find.byKey(const ValueKey('pms-nav-operations')));
        await t.pumpAndSettle();
        expect(
          t
              .widget<PmsNavItem>(
                find.byKey(const ValueKey('pms-nav-operations')),
              )
              .selected,
          isTrue,
        );
        expect(
          t
              .widget<PmsNavItem>(find.byKey(const ValueKey('pms-nav-today')))
              .selected,
          isFalse,
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    },
  );
  testWidgets('mobile navigation loads the selected authorized workspace', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final pms = visualPms();
    final a = await signedIn(pms);
    try {
      await t.pumpWidget(
        MaterialApp(
          home: PmsShell(auth: a, initialPage: PmsPage.today),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('android-tab-inbox')));
      await t.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(find.byTooltip('Search in mail'), findsOneWidget);
      expect(
        pms.requests.any((r) => r.path == '/api/reception/summary'),
        isTrue,
      );
    } finally {
      await t.pumpWidget(const SizedBox());
      a.dispose();
    }
  });
  testWidgets(
    'settings uses the right-side sheet and is removed on session revocation',
    (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      t.view.physicalSize = const Size(1440, 1000);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final pms = visualPms();
      final a = await signedIn(pms);
      try {
        await t.pumpWidget(
          DelvaneBusinessApp(
            auth: a,
            workspaceBuilder: (auth) =>
                PmsShell(auth: auth, initialPage: PmsPage.today),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('pms-account')));
        await t.pumpAndSettle();
        expect(find.byType(PmsSideSheet), findsOneWidget);
        expect(find.text('Security Center'), findsOneWidget);
        expect(t.getTopLeft(find.text('Settings')).dx, greaterThan(900));
        pms.revoked = true;
        pms.overrides.remove('/api/me');
        await expectLater(a.revalidate(), throwsA(isA<ApiException>()));
        await t.pumpAndSettle();
        expect(find.byType(PmsSideSheet), findsNothing);
        expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
      } finally {
        await t.pumpWidget(const SizedBox());
        a.dispose();
      }
    },
  );
  testWidgets(
    'chat submit still uses existing session/CSRF and clears only an accepted message',
    (t) async {
      final pms = visualPms();
      pms.overrides['/api/rosa/chat'] = pms.json({
        'answer': 'PMS reply',
        'conversation_id': 'unicode-thread',
        'read_only': true,
      });
      final a = await signedIn(pms);
      try {
        await t.pumpWidget(
          MaterialApp(
            home: PmsShell(auth: a, initialPage: PmsPage.intelligence),
          ),
        );
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const ValueKey('intelligence-composer')),
          'Who still needs registration?',
        );
        await t.testTextInput.receiveAction(TextInputAction.send);
        await t.pumpAndSettle();
        final r = pms.requests.singleWhere((r) => r.path == '/api/rosa/chat');
        expect(r.method, 'POST');
        expect((r.body as Map)['message'], 'Who still needs registration?');
        expect(r.headers['X-Rosa-CSRF'], fakeCsrf);
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('intelligence-composer')),
              )
              .controller!
              .text,
          isEmpty,
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        a.dispose();
      }
    },
  );
}
