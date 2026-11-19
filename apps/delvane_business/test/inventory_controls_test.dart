import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/features/pms/inventory_controls.dart';
import 'package:delvane_business/features/pms/pms_style.dart';

import 'dart:convert';

import 'package:delvane_business/features/pms/booking_reporting_controls.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';
import 'package:delvane_business/core/network/api_client.dart';

import 'support/fake_pms.dart';

void main() {
  testWidgets(
    'property inventory creates an apartment through the normal API',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakePms();
      final auth = await signedIn(fake);
      final c = PmsController(auth);
      c.strings.language = 'en';
      fake.overrides['/api/properties/p1/physical-units/capacity'] =
          const ApiResponse(200, '{"units":[],"aggregate_comparison":[]}');
      fake.overrides['/api/properties/p1/physical-units'] = const ApiResponse(
        200,
        '{"units":[]}',
      );
      fake.overrides['/api/properties/p1/room-types'] = const ApiResponse(
        200,
        '{"room_types":[{"id":"t1","name":"Apartment type"}]}',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: PhysicalInventory(c: c, propertyId: 'p1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add unit'));
      await tester.pumpAndSettle();
      final inputs = find.descendant(
        of: find.byType(InventoryForm),
        matching: find.byType(TextFormField),
      );
      final values = [
        '2032-05-10',
        'Árvíztűrő ház',
        '104',
        '0',
        '1',
        '1',
        'Actual fictional inventory',
      ];
      for (var i = 0; i < values.length; i++) {
        await tester.ensureVisible(inputs.at(i));
        await tester.enterText(inputs.at(i), values[i]);
      }
      final selects = find.descendant(
        of: find.byType(InventoryForm),
        matching: find.byType(DropdownButtonFormField<String>),
      );
      await tester.ensureVisible(selects.at(0));
      await tester.tap(selects.at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apartment type').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(selects.at(1));
      await tester.tap(selects.at(1));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Apartment').last,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Apartment').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final sent =
          fake.requests
                  .where(
                    (r) =>
                        r.method == 'POST' &&
                        r.path == '/api/properties/p1/physical-units',
                  )
                  .single
                  .body
              as Map;
      expect(sent['double_beds'], 1);
      expect(sent['extra_beds'], 1);
      expect(sent['classification'], 'APARTMAN');
      expect(sent['building'], 'Árvíztűrő ház');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
  testWidgets(
    'normal booking controls select two planned units without extra bookings',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakePms();
      final auth = await signedIn(fake);
      final c = PmsController(auth);
      c.strings.language = 'en';
      final state = BookingReportingState();
      fake.overrides['/api/properties/p1/physical-units/capacity'] =
          ApiResponse(
            200,
            jsonEncode({
              'units': [
                {
                  'id': 'u103',
                  'building': 'House',
                  'unit_number': '103',
                  'operational_state': 'available',
                },
                {
                  'id': 'u104',
                  'building': 'House',
                  'unit_number': '104',
                  'operational_state': 'available',
                },
              ],
            }),
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BookingReportingControls(
                state: state,
                api: PmsWorkflows(c),
                propertyId: 'p1',
                arrival: '2032-05-11',
                departure: '2032-05-12',
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Booking details and planned units'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose planned units'));
      await tester.tap(find.text('Choose planned units'));
      await tester.pumpAndSettle();
      for (final label in ['House · 103', 'House · 104']) {
        await tester.ensureVisible(find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(state.allocations.length, 2);
      expect(state.allocationsChanged, true);
      expect(
        fake.requests.where(
          (r) => r.method == 'POST' && r.path == '/api/reservations',
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
      c.dispose();
      auth.dispose();
    },
  );
  for (final language in ['hu', 'en']) {
    testWidgets('normal inventory form validates required fields $language', (
      tester,
    ) async {
      WebStrings.current.language = language;
      var saved = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: InventoryForm(
              title: 'Physical accommodation unit',
              labels: const {
                'building': 'Building',
                'unit_number': 'Apartment / room identifier',
              },
              initial: const {},
              save: (values) async {
                saved = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(ui('Save')));
      await tester.pumpAndSettle();
      expect(saved, false);
      expect(find.byType(TextFormField), findsNWidgets(2));
      await tester.enterText(
        find.byType(TextFormField).first,
        'Árvíztűrő épület',
      );
      await tester.enterText(find.byType(TextFormField).last, '104');
      // Validator accepts Unicode; an API save failure remains inside the same form.
      expect(find.text('Árvíztűrő épület'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
