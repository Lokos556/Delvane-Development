import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/actual_stay_controls.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/reservation_dialogs.dart';

import 'support/fake_pms.dart';

void main() {
  testWidgets(
    'normal reservation form saves truthful same-day dates and two units',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakePms();
      final auth = await signedIn(fake);
      final c = PmsController(auth);
      c.strings.language = 'en';
      fake.overrides['/api/reservations/r1/reporting-details'] =
          const ApiResponse(200, '{"values":{},"missing_fields":[]}');
      fake.overrides['/api/reservations/r1/allocations'] = const ApiResponse(
        200,
        '{"active":[]}',
      );
      fake.overrides['/api/properties/p1/room-types'] = const ApiResponse(
        200,
        '{"room_types":[{"id":"t1","name":"Fictional type","max_guests":4}]}',
      );
      fake.overrides['/api/properties/p1/physical-units/capacity'] =
          const ApiResponse(
            200,
            '{"units":[{"id":"u103","building":"House","unit_number":"103","operational_state":"available"},{"id":"u104","building":"House","unit_number":"104","operational_state":"available"}]}',
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: ReservationEditor(
              api: PmsWorkflows(c),
              reservation: const {
                'id': 'r1',
                'property_id': 'p1',
                'room_type_id': 't1',
                'guest_name': 'Fictional day guest',
                'guest_count': 2,
                'source': 'Direct',
                'arrival_date': '2032-05-11',
                'departure_date': '2032-05-12',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final type = find.byWidgetPredicate(
        (w) => w is PmsSelect && w.label == 'Stay type',
      );
      await tester.ensureVisible(type);
      await tester.tap(
        find.descendant(
          of: type,
          matching: find.byType(DropdownButtonFormField<String>),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Day use — no overnight stay').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Booking details and planned units'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose planned units'));
      await tester.tap(find.text('Choose planned units'));
      await tester.pumpAndSettle();
      for (final name in ['House · 103', 'House · 104']) {
        await tester.ensureVisible(find.text(name));
        await tester.tap(find.text(name));
        await tester.pumpAndSettle();
      }
      final save = find.text('Save changes');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      final request =
          fake.requests
                  .where(
                    (r) =>
                        r.method == 'PATCH' && r.path == '/api/reservations/r1',
                  )
                  .single
                  .body
              as Map;
      expect(request['stay_type'], 'day_use');
      expect(request['arrival_date'], request['departure_date']);
      expect(request['allocations'], hasLength(2));
      expect(request['planned_arrival_time'], '10:00');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
  for (final size in [const Size(393, 852), const Size(1400, 1000)]) {
    testWidgets('explicit actual arrival with single-unit shortcut $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakePms();
      final auth = await signedIn(fake);
      final c = PmsController(auth);
      c.strings.language = size.width < 500 ? 'hu' : 'en';
      fake.overrides['/api/reservations/r1/actual-stay'] = ApiResponse(
        200,
        jsonEncode({
          'actual_occupants': 0,
          'guests': [
            {
              'id': 'g1',
              'full_name': 'Fictional Guest',
              'actual_state': 'expected',
              'completeness': 'complete',
              'history': [],
            },
          ],
          'events': [],
          'planned_allocations': [
            {'unit_id': 'u1'},
          ],
        }),
      );
      fake.overrides['/api/properties/p1/physical-units'] = const ApiResponse(
        200,
        '{"units":[{"id":"u1","building":"House","unit_number":"101"}]}',
      );
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
        find.text('Expected; not arrived · Registration: complete'),
        findsOneWidget,
      );
      expect(
        fake.requests.where(
          (r) => r.method == 'POST' && r.path.endsWith('actual-stay'),
        ),
        isEmpty,
      );
      await tester.ensureVisible(find.text('Fictional Guest'));
      await tester.tap(find.text('Fictional Guest'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(ui('Check in selected guests')));
      await tester.tap(find.text(ui('Check in selected guests')));
      await tester.pumpAndSettle();
      final input = find.byType(TextFormField);
      await tester.ensureVisible(input.last);
      await tester.enterText(input.last, 'Owner observed arrival');
      await tester.ensureVisible(find.text(ui('Save')));
      await tester.tap(find.text(ui('Save')));
      await tester.pumpAndSettle();
      final sent =
          fake.requests
                  .where(
                    (r) => r.method == 'POST' && r.path.endsWith('actual-stay'),
                  )
                  .single
                  .body
              as Map;
      expect(sent['guest_ids'], ['g1']);
      expect(sent['unit_id'], 'u1');
      expect(sent.containsKey('source'), false);
      expect(sent['kind'], 'arrive');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    });
  }
}
