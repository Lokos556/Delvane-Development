import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io';

import 'package:delvane_business/core/auth/auth_controller.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/core/network/api_configuration.dart';
import 'package:delvane_business/features/pms/booking_calendar.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';
import 'package:delvane_business/features/pms/reception_page.dart';
import 'package:delvane_business/features/pms/reservation_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_pms.dart';
import 'support/workflow_pms.dart';

class BookingStore {
  final bookings = <Json>[];
}

class DeviceSession extends FakePms {
  DeviceSession(this.store, this.device);
  final BookingStore store;
  final String device;
  String get session => '${fakeCookie}_$device';
  bool disconnected = false;
  Future<ApiResponse>? lateReservations;

  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    if (disconnected) throw const SocketException('Fictional network outage');
    if (uri.path == '/api/client/environment') {
      return json({
        'environment': 'staging',
        'secure_cookies': true,
        'deployment_id': 'delvane-uat-fixture',
      });
    }
    if (uri.path == '/api/login') {
      return ApiResponse(
        200,
        '{"ok":true}',
        setCookies: [
          'rosa_session=$session; Secure; HttpOnly; Path=/; Max-Age=604800',
        ],
      );
    }
    if (headers['Cookie'] != 'rosa_session=$session') return json({}, 401);
    if (uri.path == '/api/reservations' && method == 'GET') {
      if (lateReservations case final pending?) return pending;
      return json(store.bookings);
    }
    if (uri.path.startsWith('/api/reservations') && method != 'GET') {
      if (headers['X-Rosa-CSRF'] != fakeCsrf) return json({}, 403);
      final values = Map<String, dynamic>.from(body as Map);
      if (method == 'POST') {
        store.bookings.add({...stay, ...values});
      } else if (method == 'PATCH') {
        store.bookings.single.addAll(values);
      }
      return json({'id': 'r1'});
    }
    return super.request(method, uri, {
      ...headers,
      'Cookie': 'rosa_session=$fakeCookie',
    }, body);
  }
}

Future<AuthController> connect(DeviceSession pms) async {
  final auth = AuthController(
    origin: Uri.parse('https://uat.example.invalid'),
    environment: ApiEnvironment.staging,
    transport: pms,
    store: MemorySessionStore(),
    clock: () => fakeNow,
  );
  await auth.restore();
  await auth.signIn('fictional@example.invalid', 'synthetic-only');
  expect(auth.phase, AuthPhase.authenticated);
  return auth;
}

class SlowReception extends WorkflowPms {
  final incoming = Completer<ApiResponse>();
  final scheduled = Completer<ApiResponse>();
  bool hold = true;
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) {
    if (hold && method == 'GET') {
      if (uri.path == '/api/inbox') return incoming.future;
      if (uri.path == '/api/communications/outbox') return scheduled.future;
    }
    return super.request(method, uri, headers, body);
  }
}

void main() {
  testWidgets(
    'an open Android calendar sees a second session create and edit a booking',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = BookingStore();
      final windows = DeviceSession(store, 'windows');
      final android = DeviceSession(store, 'android');
      final a = await connect(windows);
      final b = await connect(android);
      expect(windows.session, isNot(android.session));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme().copyWith(platform: TargetPlatform.android),
          home: PmsShell(auth: b, initialPage: PmsPage.reservations),
        ),
      );
      await tester.pumpAndSettle();
      List<Json> bookings() => tester
          .widget<BookingCalendar>(find.byType(BookingCalendar))
          .reservations;
      expect(bookings(), isEmpty);
      await a.api.post('/api/reservations', {
        'guest_name': 'Created on Windows',
      });
      expect(bookings(), isEmpty);
      await tester.pump(PmsController.syncInterval);
      await tester.pumpAndSettle();
      expect(bookings().single['guest_name'], 'Created on Windows');
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await a.api.patch('/api/reservations/r1', {
        'guest_name': 'Edited on Windows',
      });
      await tester.pump(PmsController.syncInterval);
      expect(bookings().single['guest_name'], 'Created on Windows');
      for (final state in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(bookings().single['guest_name'], 'Edited on Windows');
      expect(find.byType(RefreshIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      a.dispose();
      b.dispose();
    },
  );

  test('an old read cannot roll back a mutation and a reconnect reloads the server', () async {
    final store = BookingStore();
    final device = DeviceSession(store, 'android');
    final auth = await connect(device);
    final c = PmsController(auth, initialPage: PmsPage.reservations);
    addTearDown(() {
      c.dispose();
      auth.dispose();
    });
    await auth.api.post('/api/reservations', {'guest_name': 'Before'});
    await c.load();
    final old = device.json(store.bookings);
    final slow = Completer<ApiResponse>();
    device.lateReservations = slow.future;
    final fetching = c.synchronize();
    await Future<void>.delayed(Duration.zero);
    await auth.api.patch('/api/reservations/r1', {'guest_name': 'After'});
    device.lateReservations = null;
    await c.load();
    slow.complete(old);
    await fetching;
    expect(c.rows('reservations').single['guest_name'], 'After');
    device.disconnected = true;
    await c.synchronize();
    expect(auth.offline, isTrue);
    expect(
      (await auth.cache.read(
        '/api/reservations',
        auth.cacheScope!,
        auth.now(),
      ))?.$1,
      isNotNull,
    );
    store.bookings.single['guest_name'] = 'After reconnect';
    device.disconnected = false;
    await c.synchronize();
    expect(auth.offline, isFalse);
    expect(c.rows('reservations').single['guest_name'], 'After reconnect');
  });

  testWidgets(
    'Reception displays loading and shows inbox before a slow outbox',
    (tester) async {
      final pms = SlowReception();
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.inbox);
      c.strings.language = 'en';
      final loading = c.load();
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ReceptionPage(controller: c, openStay: (_) {}),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Loading conversations…'), findsOneWidget);
      expect(find.textContaining('Your inbox is clear'), findsNothing);
      pms.incoming.complete(pms.json(pms.messages));
      await tester.pump();
      await tester.pump();
      expect(find.text('Arrival request'), findsWidgets);
      expect(c.hasSection('outbox'), isFalse);
      expect(find.text('Loading conversations…'), findsNothing);
      pms.scheduled.complete(pms.json(pms.outbox));
      await loading;
      pms.hold = false;
      pms.failPath = '/api/inbox';
      await c.refreshReception();
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Your inbox is clear'), findsNothing);
      pms.failPath = null;
      pms.messages.clear();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your inbox is clear'), findsOneWidget);
      expect(find.text('Inbox 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'saved invitation email reopens and unrelated edits omit the contact',
    (tester) async {
      final pms = WorkflowPms();
      pms.overrides['/api/reservations/r1/reporting-details'] = pms.json({
        'values': {},
        'missing_fields': [],
      });
      pms.overrides['/api/reservations/r1/allocations'] = pms.json({
        'active': [],
      });
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      c.strings.language = 'en';
      final api = PmsWorkflows(c);
      final contact = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is PmsField && w.label == 'Invitation email (optional)',
        ),
        matching: find.byType(TextFormField),
      );
      Future<void> editor() async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: pmsTheme(),
            home: Scaffold(
              body: ReservationEditor(
                key: UniqueKey(),
                api: api,
                reservation: Map.of(pms.booking),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(contact);
      }

      await editor();
      await tester.enterText(contact, 'saved@example.invalid');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(pms.booking['invitation_email'], 'saved@example.invalid');
      await editor();
      expect(
        tester.widget<TextFormField>(contact).initialValue,
        'saved@example.invalid',
      );
      final guest = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is PmsField && w.label == 'Guest name',
        ),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(guest);
      await tester.enterText(guest, 'Updated synthetic guest');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final request = pms.requests.lastWhere(
        (request) => request.method == 'PATCH',
      );
      expect(request.body, {'guest_name': 'Updated synthetic guest'});
      expect(pms.booking['invitation_email'], 'saved@example.invalid');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );

  testWidgets(
    'Ma and booking details expose check-in and checkout, including blockers',
    (tester) async {
      final pms = FakePms();
      final auth = await signedIn(pms);
      WebStrings.current.language = 'en';
      pms.delayedCommand = Future.value(
        pms.json({
          'date': '2032-05-10',
          'arrivals': [pms.stay],
          'departures': [pms.stay],
        }),
      );
      pms.overrides['/api/reservations/r1/actual-stay'] = ApiResponse(
        200,
        jsonEncode({
          'reservation_status': 'confirmed',
          'registration_status': 'incomplete',
          'actual_occupants': 0,
          'business_date': '2032-05-10',
          'planned_allocations': [],
          'unit_readiness': [],
          'events': [],
          'guests': [
            {
              'id': 'g1',
              'full_name': 'Fictional guest',
              'actual_state': 'expected',
            },
          ],
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: PmsShell(auth: auth),
        ),
      );
      await tester.pumpAndSettle();
      final dashboard = find.byKey(const ValueKey('today-board'));
      final checkIn = find.descendant(
        of: dashboard,
        matching: find.text('Check in'),
      );
      final checkOut = find.descendant(
        of: dashboard,
        matching: find.text('Check out'),
      );
      await tester.ensureVisible(checkIn);
      await tester.tap(checkIn);
      await tester.pumpAndSettle();
      expect(
        find.text('Assign a planned physical unit before confirming arrival.'),
        findsOneWidget,
      );
      expect(find.text('Review booking'), findsOneWidget);
      await tester.tap(find.text('Review booking'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(PmsButton, 'Check in'), findsOneWidget);
      expect(find.widgetWithText(PmsButton, 'Check out'), findsOneWidget);
      await tester.tap(find.widgetWithText(PmsButton, 'Check out'));
      await tester.pumpAndSettle();
      expect(find.text('No guests are currently checked in.'), findsOneWidget);
      expect(
        pms.requests.where(
          (r) => r.method == 'POST' && r.path.endsWith('/actual-stay'),
        ),
        isEmpty,
      );
      expect(checkOut, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
}
