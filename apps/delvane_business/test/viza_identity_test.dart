import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/guest_reporting_controls.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';
import 'package:delvane_business/features/pms/pms_style.dart';

import 'support/fake_pms.dart';

void main() {
  for (final width in [390.0, 1200.0]) {
    for (final language in ['en', 'hu']) {
      testWidgets(
        'unified profile retains provenance and supports country and name review $width $language',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final fake = FakePms();
          final auth = await signedIn(fake);
          final c = PmsController(auth);
          await c.strings.load();
          c.strings.language = language;
          const path = '/api/registration/records/g1/workspace';
          fake.overrides['/api/reservations/r1/guest-checkin-status'] =
              ApiResponse(
                200,
                jsonEncode({
                  'guests': [
                    {
                      'id': 'g1',
                      'full_name': 'Fictional Family Guest',
                      'registration_stage': 'submitted',
                    },
                    {
                      'id': 'g2',
                      'full_name': 'Second fictional guest',
                      'registration_stage': 'awaiting_registration',
                    },
                  ],
                }),
              );
          fake.overrides[path] = ApiResponse(
            200,
            jsonEncode({
              'id': 'g1',
              'reservation_id': 'r1',
              'full_name': 'Fictional Family Guest',
              'identity': {
                'csaladnev': 'Before',
                'utonev': 'Fictional',
                'szuletesiDatum': '1988-02-29',
                'okmanyTipus': 'UTLEVEL',
                'okmanyAzonositoSzam': 'FAKE-XYZ',
              },
              'original': {'csaladnev': 'Original fictional'},
              'submitted': {
                'full_name': 'Fictional Family Guest',
                'nationality': 'Dutch',
              },
              'submitted_snapshot': true,
              'registration_stage': 'submitted',
              'can_verify': true,
              'revision': [1, 0],
              'business_date': '2026-11-25',
              'reference_date': '2026-11-25',
              'viza_countries': ['HU', 'NL', 'DE'],
              'ntak_countries': ['HU', 'NL', 'DE'],
              'raw_nationality': 'NLD',
              'third_country_applicable': false,
              'readiness': {
                'viza_blockers': [
                  'owner_verification_required',
                  'country_mapping_requires_review',
                ],
                'ntak_blockers': ['identity_normalization_unresolved'],
              },
            }),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: pmsTheme(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => openGuestRegistration(
                      context,
                      PmsWorkflows(c),
                      guestId: 'g1',
                    ),
                    child: const Text('Review'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Review'));
          await tester.pumpAndSettle();
          expect(find.text(ui('Guest registration')), findsOneWidget);
          expect(find.text(ui('Registration submitted')), findsWidgets);
          expect(find.text(ui('Awaiting registration')), findsOneWidget);
          expect(find.text(ui('Identity verified')), findsNothing);
          expect(find.text('country_mapping_requires_review'), findsNothing);
          expect(
            find.byKey(const ValueKey('guest-field-vizumEngedelySzam')),
            findsNothing,
          );
          final source = find.text(ui('Submitted and scanned information'));
          await tester.ensureVisible(source);
          await tester.tap(source);
          await tester.pumpAndSettle();
          expect(find.textContaining('Original fictional'), findsOneWidget);
          expect(find.textContaining('Dutch'), findsOneWidget);
          for (final e in {
            'szuletesiDatum': '1988-02-29',
            'okmanyAzonositoSzam': 'FAKE-XYZ',
          }.entries) {
            expect(
              tester
                  .widget<PmsField>(
                    find.byKey(ValueKey('guest-field-${e.key}')),
                  )
                  .controller
                  .text,
              e.value,
            );
          }
          final nationality = find.descendant(
            of: find.byKey(const ValueKey('g1-allampolgarsagKod-')),
            matching: find.widgetWithText(PmsButton, ui('Select country')),
          );
          await tester.ensureVisible(nationality);
          await tester.tap(nationality);
          await tester.pumpAndSettle();
          final search = find.byWidgetPredicate(
            (w) =>
                w is TextField &&
                w.decoration?.labelText == ui('Search countries'),
          );
          await tester.ensureVisible(search);
          await tester.enterText(
            search,
            language == 'hu' ? 'magyarorszag' : 'Hungary',
          );
          await tester.pumpAndSettle();
          final country = find.widgetWithText(
            ListTile,
            language == 'hu' ? 'Magyarország' : 'Hungary',
          );
          await tester.ensureVisible(country);
          await tester.tap(country);
          await tester.pumpAndSettle();
          final family = find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is PmsField && w.label == 'Family name',
            ),
            matching: find.byType(TextFormField),
          );
          await tester.ensureVisible(family);
          await tester.enterText(family, '\u0150rfi');
          final reason = find.descendant(
            of: find.byWidgetPredicate(
              (w) => w is PmsField && w.label == 'Reason',
            ),
            matching: find.byType(TextFormField),
          );
          await tester.ensureVisible(reason);
          await tester.enterText(reason, 'Fictional reviewed correction');
          await tester.ensureVisible(find.text(ui('Save guest profile')));
          await tester.tap(find.text(ui('Save guest profile')));
          await tester.pumpAndSettle();
          final sent =
              fake.requests
                      .where((r) => r.method == 'PUT' && r.path == path)
                      .single
                      .body
                  as Map;
          final identity = sent['identity'] as Map;
          expect((identity['manual'] as Map)['csaladnev'], '\u0150rfi');
          expect((identity['manual'] as Map)['allampolgarsagKod'], 'HU');
          expect(sent.containsKey('original'), false);
          expect(sent.containsKey('actor_id'), false);
          expect(identity['third_country_applicable'], false);
          expect(identity['confirm_ambiguities'], false);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          auth.dispose();
        },
      );
    }
  }
}
