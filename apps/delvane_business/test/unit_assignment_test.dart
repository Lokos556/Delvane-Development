import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/actual_stay_controls.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';
import 'package:delvane_business/features/pms/reservation_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'support/fake_pms.dart';
import 'support/workflow_pms.dart';

class AssignmentPms extends WorkflowPms {
  bool assigned = false;
  Object? assignment;

  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    if (uri.path.endsWith('/actual-stay') && method == 'GET') {
      return json({
        'reservation_status': 'confirmed',
        'stay_type': 'overnight',
        'actual_occupants': 0,
        'business_date': '2032-05-10',
        'guests': [
          {
            'id': 'g1',
            'full_name': 'Fictional guest',
            'actual_state': 'expected',
          },
        ],
        'planned_allocations': [
          if (assigned)
            {
              'unit_id': 'u102',
              'date_from': '2032-05-10',
              'date_to': '2032-05-11',
            },
        ],
        'unit_readiness': [
          {'unit_id': 'u102', 'label': 'House · 102', 'state': 'ready'},
        ],
      });
    }
    if (uri.path.endsWith('/allocations') && method == 'PUT') {
      assignment = body;
      assigned = true;
      return json({'ok': true, 'changed': true});
    }
    if (uri.queryParameters['include_options'] == 'true' ||
        uri.path.endsWith('/assignment-options')) {
      return json({
        'options': [
          {'unit_id': 'u102', 'label': 'House · 102'},
        ],
        'expected_active_ids': [],
      });
    }
    return super.request(method, uri, headers, body);
  }
}

void main() {
  Future<void> press(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets('Check-in can persist a missing room and then confirm arrival', (
    tester,
  ) async {
    final fake = AssignmentPms();
    final auth = await signedIn(fake);
    final c = PmsController(auth)..strings.language = 'en';
    await tester.pumpWidget(
      MaterialApp(
        theme: pmsTheme(),
        home: Scaffold(
          body: ActualStayDialog(api: PmsWorkflows(c), reservationId: 'r1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Assign a planned physical unit before confirming arrival.'),
      findsOneWidget,
    );
    await press(tester, 'Assign a room');
    await press(tester, 'Assign automatically');
    expect(fake.assignment, {'mode': 'automatic', 'expected_active_ids': []});
    expect(find.textContaining('House · 102'), findsWidgets);
    expect(
      find.text('Assign a planned physical unit before confirming arrival.'),
      findsNothing,
    );
    await press(tester, 'Fictional guest');
    expect(
      tester
          .widget<PmsButton>(
            find.widgetWithText(PmsButton, 'Check in selected guests'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    auth.dispose();
  });

  testWidgets(
    'Booking keeps automatic assignment as default and sends a deliberately chosen room',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = AssignmentPms();
      final auth = await signedIn(fake);
      final c = PmsController(auth)..strings.language = 'en';
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: ReservationEditor(
              api: PmsWorkflows(c),
              initialDate: '2032-05-10',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Automatic assignment'), findsOneWidget);
      await press(tester, 'Choose a room');
      await press(tester, 'House · 102');
      await press(tester, 'Confirm room');
      final guest = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is PmsField && w.label == 'Guest name',
        ),
        matching: find.byType(TextFormField),
      );
      await tester.ensureVisible(guest);
      await tester.enterText(guest, 'Fictional booking guest');
      await press(tester, 'Create reservation');
      final request = fake.requests.singleWhere(
        (it) => it.method == 'POST' && it.path == '/api/reservations',
      );
      expect((request.body as Map)['selected_unit_id'], 'u102');
      expect((request.body as Map).containsKey('allocations'), isFalse);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
}
