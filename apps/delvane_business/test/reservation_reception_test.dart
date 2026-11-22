import 'support/section_navigation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/app/app.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';
import 'package:delvane_business/features/pms/reservation_dialogs.dart';
import 'package:delvane_business/features/pms/reception_page.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_dialogs.dart';

import 'support/fake_pms.dart';
import 'support/workflow_pms.dart';

Future<void> enter(WidgetTester tester, String label, String value) async {
  final field = find.descendant(
    of: find.byWidgetPredicate((w) => w is PmsField && w.label == label),
    matching: find.byType(TextFormField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
}

void main() {
  testWidgets(
    'prepared invitations only expose a link after local simulation',
    (tester) async {
      final pms = WorkflowPms();
      pms.outbox.first
        ..['message_type'] = 'guest_checkin_invitation'
        ..['subject'] = 'Guest pre-check-in invitation';
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.inbox);
      await c.load();
      c.receptionTab = 1;
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
      await tester.pumpAndSettle();
      expect(find.text('Simulate send'), findsNothing);
      expect(find.byType(SelectableText), findsNothing);
      final approve = find.text('Approve');
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.pumpAndSettle();
      final simulate = find.text('Simulate send');
      await tester.ensureVisible(simulate);
      await tester.tap(simulate);
      await tester.pumpAndSettle();
      expect(
        find.text('Simulation only. Nothing was sent to a guest.'),
        findsOneWidget,
      );
      expect(
        find.text('https://example.invalid/guest/checkin/synthetic-only'),
        findsOneWidget,
      );
      await tester.tap(find.byTooltip('Close dialog'));
      await tester.pumpAndSettle();
      expect(
        find.text('https://example.invalid/guest/checkin/synthetic-only'),
        findsNothing,
      );
      expect(find.text('Simulate send'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );

  testWidgets('scheduled approval cannot be repeated when its refresh fails', (
    tester,
  ) async {
    final pms = WorkflowPms();
    final auth = await signedIn(pms);
    final c = PmsController(auth, initialPage: PmsPage.inbox);
    await c.load();
    c.receptionTab = 1;
    pms.failRefresh = true;
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
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Approve'));
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(pms.mutationCount, 1);
    expect(
      tester
          .widget<PmsButton>(find.widgetWithText(PmsButton, 'Approve'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<PmsButton>(find.widgetWithText(PmsButton, 'Simulate send'))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    auth.dispose();
  });
  testWidgets(
    'manual inbox dialog persists input and opens the newly created message',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms();
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.inbox);
      await c.load();
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
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('+ Paste message'));
      await tester.tap(find.text('+ Paste message'));
      await tester.pumpAndSettle();
      await enter(tester, 'Sender name', 'New synthetic sender');
      await enter(
        tester,
        'Message',
        'Synthetic inquiry, please prepare a cot.',
      );
      await tester.tap(find.text('Add to Inbox'));
      await tester.pumpAndSettle();
      expect(pms.messages.last['sender_name'], 'New synthetic sender');
      expect(find.text('New synthetic sender'), findsOneWidget);
      expect(
        pms.requests
            .singleWhere((r) => r.path == '/api/inbox' && r.method == 'POST')
            .headers['X-Rosa-CSRF'],
        fakeCsrf,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
  testWidgets(
    'reply and scheduled edits are saved through separate draft contracts',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms();
      pms.messages.first['status'] = 'analyzed';
      pms.messages.first['analysis'] = {'extracted': {}};
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.inbox);
      await c.load();
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
      await tester.pumpAndSettle();
      final editor = find.byType(TextField).last;
      await tester.ensureVisible(editor);
      await tester.enterText(editor, 'Edited local reply');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(pms.messages.first['draft_reply'], 'Edited local reply');
      await tester.ensureVisible(find.text('Scheduled 1'));
      await tester.tap(find.text('Scheduled 1'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Edited scheduled draft');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(pms.outbox.first['body'], 'Edited scheduled draft');
      expect(pms.outbox.first['status'], 'awaiting_approval');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
  testWidgets('date selector writes ISO dates back into the booking form', (
    tester,
  ) async {
    final pms = WorkflowPms();
    final auth = await signedIn(pms);
    final c = PmsController(auth);
    await tester.pumpWidget(
      MaterialApp(
        theme: pmsTheme(),
        home: Scaffold(
          body: ReservationEditor(
            api: PmsWorkflows(c),
            initialDate: '2032-05-20',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Choose Arrival'));
    await tester.tap(find.byTooltip('Choose Arrival'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('21'));
    await tester.tap(find.text('21'));
    await tester.pumpAndSettle();
    expect(find.text('2032-05-21'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    auth.dispose();
  });
  testWidgets(
    'booking conflict preserves entered fields and does not retry the mutation',
    (tester) async {
      final pms = WorkflowPms()
        ..failPath = '/api/reservations'
        ..failureStatus = 409;
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(body: ReservationEditor(api: PmsWorkflows(c))),
        ),
      );
      await tester.pumpAndSettle();
      await enter(tester, 'Guest name', 'Keep this input');
      await tester.ensureVisible(find.text('Create reservation'));
      await tester.tap(find.text('Create reservation'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('conflicts with the current record'),
        findsOneWidget,
      );
      expect(find.text('Keep this input'), findsOneWidget);
      expect(
        pms.requests
            .where((r) => r.path == '/api/reservations' && r.method == 'POST')
            .length,
        1,
      );
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
  testWidgets(
    'selected calendar day creates dated editor and overflow lists every stay',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms();
      final today = DateTime.now();
      final day = isoDate(DateTime(today.year, today.month, 15));
      pms.booking['arrival_date'] = day;
      pms.booking['departure_date'] = isoDate(
        DateTime(today.year, today.month, 18),
      );
      for (var i = 2; i <= 4; i++) {
        pms.extraBookings.add({
          ...pms.booking,
          'id': 'r$i',
          'guest_name': 'Overflow guest $i',
        });
      }
      final auth = await signedIn(pms);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: PmsShell(auth: auth, initialPage: PmsPage.reservations),
        ),
      );
      await tester.pumpAndSettle();
      final more = find.text('+3 more').first;
      await tester.ensureVisible(more);
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('Overflow guest 4'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close dialog'));
      await tester.pumpAndSettle();
      final cell = find.byKey(ValueKey('calendar-day-$day'));
      await tester.ensureVisible(cell);
      await tester.tapAt(tester.getTopLeft(cell) + const Offset(12, 10));
      await tester.pumpAndSettle();
      final details = find.byKey(const ValueKey('calendar-selected-day'));
      expect(
        find.descendant(of: details, matching: find.text(day)),
        findsOneWidget,
      );
      await tester.tap(
        find.descendant(of: details, matching: find.text('Add a stay')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReservationEditor), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
  testWidgets(
    'secure links require an explicit action and identity decisions include the review method',
    (tester) async {
      final pms = WorkflowPms();
      final auth = await signedIn(pms);
      final c = PmsController(auth);
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
      expect(
        pms.requests.any((r) => r.path.endsWith('/guest-checkin-links')),
        false,
      );
      await selectSection(tester, 'Preparation');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Send guest check-in link'));
      await tester.tap(find.text('Send guest check-in link'));
      await tester.pumpAndSettle();
      expect(find.text('Secure guest links'), findsOneWidget);
      expect(
        pms.requests
            .where((r) => r.path.endsWith('/guest-checkin-links'))
            .length,
        1,
      );
      await tester.tap(find.byTooltip('Close dialog').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review identity verification'));
      await tester.tap(find.text('Review identity verification'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Verify identity'));
      await tester.tap(find.text('Verify identity'));
      await tester.pumpAndSettle();
      final sent = pms.requests.singleWhere((r) => r.path.endsWith('/verify'));
      expect((sent.body as Map)['verification_method'], 'in_person');
      expect((sent.body as Map)['decision'], 'verify');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
  for (final size in [const Size(390, 844), const Size(844, 390)]) {
    testWidgets('Reception list, thread, drafts and automations fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms();
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.inbox);
      await c.load();
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
      await tester.pumpAndSettle();
      if (size.width <= 760) {
        await tester.ensureVisible(find.text('Synthetic Guest'));
        await tester.tap(find.text('Synthetic Guest'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.text('Analyze'));
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      final editor = find.byType(TextField).last;
      await tester.ensureVisible(editor);
      await tester.enterText(editor, 'Draft retained across tabs');
      await selectSection(tester, 'Automations 1');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(PmsToggle));
      await tester.tap(find.byType(PmsToggle));
      await tester.pumpAndSettle();
      expect(pms.rules.first['enabled'], false);
      await selectSection(tester, 'Inbox 0');
      await tester.pumpAndSettle();
      expect(find.text('Draft retained across tabs'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    });
  }
  test('date and time input checks match native form shape without doing availability validation', () {
    expect(validDate('2032-02-29'), true);
    expect(validDate('2031-02-29'), false);
    expect(validDate('0000-01-01'), false);
    expect(optionalTime('23:59'), isNull);
    expect(optionalTime('24:00'), isNotNull);
    expect(optionalTime(''), isNull);
  });
  testWidgets(
    'session revocation removes reservation dialogs from the protected navigator',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms();
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      await tester.pumpWidget(DelvaneBusinessApp(auth: auth));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pms-nav-today')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic Guest').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit booking'), findsOneWidget);
      pms.revoked = true;
      await expectLater(auth.revalidate(), throwsA(isA<ApiException>()));
      await tester.pumpAndSettle();
      expect(find.text('Edit booking'), findsNothing);
      expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    },
  );
  for (final role in ['cleaner', 'maintenance']) {
    test(
      '$role is denied reservation/reception mutations before transport',
      () async {
        final pms = WorkflowPms()..role = role;
        final auth = await signedIn(pms);
        addTearDown(auth.dispose);
        final controller = PmsController(auth);
        addTearDown(controller.dispose);
        final api = PmsWorkflows(controller);
        final before = pms.requests.length;
        await expectLater(
          Future.sync(() => api.save({'guest_name': 'Denied'})),
          throwsA(isA<ApiException>()),
        );
        await expectLater(api.detail('r1'), throwsA(isA<ApiException>()));
        await expectLater(
          Future.sync(() => api.messageAction('msg1', 'apply')),
          throwsA(isA<ApiException>()),
        );
        expect(pms.requests.length, before);
      },
    );
  }
  test(
    'booking contracts preserve exact integer HUF and canonical mutations',
    () async {
      final pms = WorkflowPms();
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      final controller = PmsController(auth);
      addTearDown(controller.dispose);
      final api = PmsWorkflows(controller);
      await api.save({'total_huf': 9007199254740993}, id: 'r1');
      expect(pms.booking['total_huf'], 9007199254740993);
      await api.confirm('r1');
      expect(pms.booking['status'], 'confirmed');
      await api.note('r1', 'Internal synthetic note');
      expect(pms.notes.single['body'], 'Internal synthetic note');
      await api.cancel('r1');
      expect(pms.booking['status'], 'cancelled');
      expect(
        pms.requests
            .where((r) => r.method == 'PATCH')
            .every((r) => r.headers['X-Rosa-CSRF'] == fakeCsrf),
        true,
      );
    },
  );
  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('reservation editor submits and workspace tabs fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms();
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      final api = PmsWorkflows(c);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => PmsButton(
                'Open editor',
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) =>
                      ReservationEditor(api: api, initialDate: '2032-05-20'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      expect(find.text('Add a stay'), findsOneWidget);
      await enter(tester, 'Guest name', 'Created synthetic guest');
      await enter(tester, 'Total reservation value (HUF)', '9007199254740993');
      await tester.tap(find.text('Create reservation'));
      await tester.pumpAndSettle();
      expect(pms.booking['guest_name'], 'Created synthetic guest');
      expect(pms.booking['total_huf'], 9007199254740993);
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: ReservationWorkspace(
              api: api,
              id: 'r1',
              openReception: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final name in [
        'Stay overview',
        'Preparation',
        'Communication',
        'Activity',
      ]) {
        await selectSection(tester, name);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    });
  }
  testWidgets('room-type failure does not enable a fake booking form', (
    tester,
  ) async {
    final pms = WorkflowPms()..failPath = '/api/properties/p1/room-types';
    final auth = await signedIn(pms);
    final c = PmsController(auth);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReservationEditor(api: PmsWorkflows(c))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    final button = tester.widget<PmsButton>(
      find.widgetWithText(PmsButton, 'Create reservation'),
    );
    expect(button.onPressed, isNull);
    expect(pms.mutationCount, 0);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    auth.dispose();
  });
  testWidgets(
    'reception analyze, draft, apply and simulation use distinct backend actions',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms();
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.inbox);
      await c.load();
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(find.text('ROSA UNDERSTOOD'), findsOneWidget);
      expect(find.textContaining('20:30'), findsWidgets);
      await tester.ensureVisible(find.text('Apply actions'));
      await tester.tap(find.text('Apply actions'));
      await tester.pumpAndSettle();
      expect(pms.booking['arrival_time'], '20:30');
      await tester.ensureVisible(find.text('Mark sent externally'));
      await tester.tap(find.text('Mark sent externally'));
      await tester.pumpAndSettle();
      expect(pms.messages.first['status'], 'replied');
      await tester.ensureVisible(find.text('Scheduled 1'));
      await tester.tap(find.text('Scheduled 1'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Approve'));
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(pms.outbox.first['status'], 'ready');
      await tester.ensureVisible(find.text('Simulate send'));
      await tester.tap(find.text('Simulate send'));
      await tester.pumpAndSettle();
      expect(pms.outbox.first['status'], 'simulated_sent');
      expect(find.text('No live external send'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
  testWidgets(
    'accepted mutation with failed refresh blocks repetition until refresh',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WorkflowPms();
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.inbox);
      await c.load();
      pms.failRefresh = true;
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
      await tester.pumpAndSettle();
      await tester.tap(find.text('Analyze'));
      await tester.pumpAndSettle();
      expect(pms.mutationCount, 1);
      expect(find.textContaining('server accepted'), findsOneWidget);
      expect(
        tester
            .widget<PmsButton>(find.widgetWithText(PmsButton, 'Analyze'))
            .onPressed,
        isNull,
      );
      pms.failRefresh = false;
      await tester.ensureVisible(find.text('Refresh data'));
      await tester.tap(find.text('Refresh data'));
      await tester.pumpAndSettle();
      expect(find.text('ROSA UNDERSTOOD'), findsOneWidget);
      expect(pms.mutationCount, 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
}
