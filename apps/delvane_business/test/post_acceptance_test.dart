import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/reservation_dialogs.dart';
import 'package:delvane_business/features/pms/overflow_row.dart';
import 'package:delvane_business/features/pms/guest_history_dialog.dart';

import 'support/fake_pms.dart';
import 'support/workflow_pms.dart';
import 'api_client_test.dart' show FakeTransport;

void main() {
  testWidgets('scroll cues remain operable with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: SizedBox(
              width: 220,
              child: PmsOverflowRow(
                child: Row(
                  children: List.generate(
                    8,
                    (i) => SizedBox(width: 100, height: 48, child: Text('$i')),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Scroll forward'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Scroll backward'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final code in [
    'availability_conflict',
    'guest_records_review_required',
    'registration_review_required',
    'invalid_dates',
    'departure_not_after_arrival',
    'guest_name_required',
    'invalid_guest_count',
    'capacity_exceeded',
    'property_unavailable',
    'room_unavailable',
    'reservation_not_found',
    'invalid_fields',
  ]) {
    test(
      'structured error $code survives transport without raw diagnostics',
      () async {
        final transport = FakeTransport(
          () async => ApiResponse(
            409,
            jsonEncode({
              'detail': {
                'code': code,
                'field': 'guest_count',
                'debug': 'PRIVATE TRACE',
              },
            }),
          ),
        );
        final client = ApiClient(
          baseUrl: Uri.parse('https://synthetic.invalid'),
          transport: transport,
        );
        addTearDown(client.close);
        try {
          await client.post('/api/reservations', {});
          fail('Expected an API error');
        } on ApiException catch (error) {
          expect(error.code, code);
          expect(error.field, 'guest_count');
          expect(workflowError(error), isNot(contains('PRIVATE')));
          final strings = WebStrings()..language = 'hu';
          await strings.load();
          expect(strings.t(workflowError(error)), isNot(workflowError(error)));
        }
      },
    );
  }
  testWidgets('horizontal cues reflect overflow and disappear at the end', (
    tester,
  ) async {
    final items = Row(
      children: List.generate(
        8,
        (i) => SizedBox(width: 100, height: 48, child: Text('Item $i')),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 250, child: PmsOverflowRow(child: items)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Scroll forward'), findsOneWidget);
    expect(find.byTooltip('Scroll backward'), findsNothing);
    for (
      var i = 0;
      i < 8 && find.byTooltip('Scroll forward').evaluate().isNotEmpty;
      i++
    ) {
      await tester.tap(find.byTooltip('Scroll forward'));
      await tester.pumpAndSettle();
    }
    expect(find.byTooltip('Scroll forward'), findsNothing);
    expect(find.byTooltip('Scroll backward'), findsOneWidget);
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(width: 500, child: PmsOverflowRow(child: Text('Short'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Scroll forward'), findsNothing);
  });
  for (final size in [
    const Size(320, 780),
    const Size(393, 852),
    const Size(1440, 1000),
  ]) {
    testWidgets('date-first reservation layout fits $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms()
        ..booking['guest_name'] =
            'Fictional guest with a deliberately very long name for layout';
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      addTearDown(() {
        c.dispose();
        auth.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: ReservationWorkspace(
              api: PmsWorkflows(c),
              id: 'r1',
              openReception: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dates = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (text) =>
                (text.style?.fontWeight == FontWeight.w800) &&
                (text.style?.fontSize ?? 0) >= 22,
          );
      expect(dates.length, greaterThanOrEqualTo(2));
    });
  }
  testWidgets(
    'mobile reservation creation and cleaner sign-out have full touch targets',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms();
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: PmsShell(auth: auth, initialPage: PmsPage.reservations),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.byWidgetPredicate(
        (w) =>
            w is PmsButton && w.label.toLowerCase().contains('new reservation'),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.pumpWidget(const SizedBox());
      final worker = FakePms()..role = 'cleaner';
      final workerAuth = await signedIn(worker);
      addTearDown(workerAuth.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: PmsShell(auth: workerAuth),
        ),
      );
      await tester.pumpAndSettle();
      // Settings sign-out is available to workers and retains the same auth controller.
      await tester.tap(find.byKey(const ValueKey('pms-mobile-settings')));
      await tester.pumpAndSettle();
      final signOut = find.widgetWithText(PmsButton, 'Sign out');
      await tester.ensureVisible(signOut);
      expect(tester.getSize(signOut).height, greaterThanOrEqualTo(48));
      await tester.tap(signOut);
      await tester.pumpAndSettle();
      expect(workerAuth.user, isNull);
    },
  );
  testWidgets('history counts distinguish host and guest cancellations', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GuestHistorySummary(
            summary: {
              'previous_reservations': 3,
              'past_confirmed_reservations': 1,
              'guest_cancellations': 1,
              'host_cancellations': 1,
            },
          ),
        ),
      ),
    );
    expect(find.text('1 guest cancellations'), findsOneWidget);
    expect(find.text('1 host cancellations'), findsOneWidget);
    expect(find.textContaining('score'), findsNothing);
  });
}
