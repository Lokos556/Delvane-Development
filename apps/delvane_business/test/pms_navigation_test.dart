import 'dart:async';

import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_pms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'cold sections resolve independently and warm navigation reuses reads',
    () async {
      final pms = FakePms();
      pms.overrides['/api/organization'] = pms.json({
        'operating_mode': 'observe',
      });
      pms.overrides['/api/notifications'] = pms.json({'unread': 0});
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      final controller = PmsController(auth, initialPage: PmsPage.today);
      addTearDown(controller.dispose);

      final command = Completer<ApiResponse>();
      final dashboardVisible = Completer<void>();
      pms.delayedCommand = command.future;
      controller.addListener(() {
        if (controller.hasSection('dashboard') &&
            !dashboardVisible.isCompleted) {
          dashboardVisible.complete();
        }
      });
      final today = controller.load();
      await dashboardVisible.future.timeout(const Duration(seconds: 5));
      expect(controller.hasSection('command'), isFalse);
      expect(controller.loading, isFalse);
      expect(controller.refreshing, isTrue);
      command.complete(pms.json({'date': '2032-05-10'}));
      await today;
      await controller.navigate(PmsPage.reservations);
      final calls = pms.requests.length;
      final warm = controller.navigate(PmsPage.today);
      expect(controller.hasSection('dashboard'), isTrue);
      expect(controller.loading, isFalse);
      await warm;
      expect(pms.requests.length, calls);
    },
  );

  test(
    'a transient section error preserves data and a 403 erases its section',
    () async {
      final pms = FakePms();
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      final controller = PmsController(auth, initialPage: PmsPage.reservations);
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.rows('reservations'), isNotEmpty);

      pms.overrides['/api/reservations'] = const ApiResponse(503, '{}');
      await controller.load();
      expect(controller.rows('reservations'), isNotEmpty);
      expect(controller.hasSection('properties'), isTrue);
      expect(controller.sectionErrors, contains('reservations'));
      expect(controller.connectionIssue, ApiFailure.http);

      pms.overrides['/api/reservations'] = const ApiResponse(403, '{}');
      await controller.load();
      expect(controller.hasSection('reservations'), isFalse);
      expect(controller.hasSection('properties'), isTrue);

      pms.revoked = true;
      await controller.load();
      expect(auth.user, isNull);
      expect(controller.data, isEmpty);
    },
  );

  test('successful mutations invalidate a previously fetched page', () async {
    final pms = FakePms();
    final auth = await signedIn(pms);
    addTearDown(auth.dispose);
    final controller = PmsController(auth, initialPage: PmsPage.reservations);
    addTearDown(controller.dispose);
    await controller.load();
    await controller.navigate(PmsPage.today);
    pms.overrides['/api/reservations'] = pms.json([]);
    await auth.api.post('/api/reservations', {});
    await controller.navigate(PmsPage.reservations);
    expect(controller.rows('reservations'), isEmpty);
    expect(
      pms.requests
          .where(
            (request) =>
                request.method == 'GET' && request.path == '/api/reservations',
          )
          .length,
      2,
    );
  });

  testWidgets(
    'operations filter scopes work and opens the existing assignment form',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = FakePms();
      pms.overrides['/api/properties'] = pms.json([
        pms.property,
        {...pms.property, 'id': 'p2', 'name': 'Second House'},
      ]);
      pms.overrides['/api/intelligence'] = pms.json({
        'tasks': [
          pms.task,
          {
            ...pms.task,
            'id': 't2',
            'property_id': 'p2',
            'property_name': 'Second House',
          },
        ],
        'maintenance': [pms.maintenance],
      });
      pms.overrides['/api/team/overview'] = pms.json({
        'members': [
          {
            'active': true,
            'role': 'cleaner',
            'id': 'user-cleaner',
            'full_name': 'Synthetic Cleaner',
          },
        ],
      });
      pms.overrides['/api/guest-journeys'] = pms.json([
        {...pms.stay, 'current_stage': 'registration'},
      ]);
      pms.overrides['/api/operations/timeline'] = pms.json([]);
      final auth = await signedIn(pms);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: PmsShell(auth: auth, initialPage: PmsPage.operations),
        ),
      );
      await tester.pumpAndSettle();
      final filter = find.byKey(const ValueKey('operations-property'));
      await tester.tap(filter);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(DropdownMenuItem<String>),
              matching: find.text('Second House'),
            )
            .last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Synthetic Guest'), findsNothing);
      expect(find.text('Synthetic tap repair'), findsNothing);
      final task = find.widgetWithText(ListTile, 'Second House');
      await tester.tap(task);
      await tester.pumpAndSettle();
      expect(find.text('Assign work'), findsOneWidget);
      expect(find.text('Synthetic Cleaner'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );

  testWidgets(
    'month and year keep the selected day and property without refetching',
    (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = FakePms();
      final auth = await signedIn(pms);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: PmsShell(auth: auth, initialPage: PmsPage.reservations),
        ),
      );
      await tester.pumpAndSettle();
      int reservationReads() =>
          pms.requests.where((r) => r.path == '/api/reservations').length;
      final initialReads = reservationReads();
      final now = DateTime.now();
      final date = isoDate(DateTime(now.year, now.month, 3));
      final day = find.byKey(ValueKey('calendar-day-$date'));
      await tester.tap(day);
      await tester.pumpAndSettle();
      final panel = find.byKey(const ValueKey('calendar-selected-day'));
      expect(
        find.descendant(of: panel, matching: find.text(date)),
        findsOneWidget,
      );
      final property = find.byKey(const ValueKey('calendar-property'));
      await tester.tap(property);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test House').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('calendar-month-${now.year}-12')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Next year'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('calendar-month-${now.year + 1}-1')),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Previous year'));
      await tester.pumpAndSettle();
      final month = find.byKey(
        ValueKey('calendar-month-${now.year}-${now.month}'),
      );
      await tester.ensureVisible(month);
      await tester.tap(month);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: panel, matching: find.text(date)),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('pms-nav-today')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('today-header'))).dy,
        lessThan(tester.getTopLeft(find.text('Stay and closing tools')).dy),
      );
      await tester.tap(find.byKey(const ValueKey('pms-nav-reservations')));
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<String>>(property).value, 'p1');
      expect(
        find.descendant(of: panel, matching: find.text(date)),
        findsOneWidget,
      );
      expect(reservationReads(), initialReads);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );

  for (final dpr in [1.0, 1.25, 1.5]) {
    testWidgets('Hungarian page header wraps at ${(dpr * 100).round()}% DPI', (
      tester,
    ) async {
      tester.view.devicePixelRatio = dpr;
      tester.view.physicalSize = const Size(1440, 900);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.only(left: 235),
              child: PmsPageHeader(
                eyebrow: 'MŰVELETEK',
                title: 'Tényleges foglaltság és vendégtartózkodás',
                actions: [Text('Szálláshely kiválasztása és frissítése')],
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('Tényleges foglaltság és vendégtartózkodás'),
        findsOneWidget,
      );
    });
  }
}
