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
        'VIZA source review and Unicode correction $width $language',
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
          const path = '/api/registration/records/g1/viza-identity';
          fake.overrides[path] = ApiResponse(
            200,
            jsonEncode({
              'effective': {'csaladnev': 'Before', 'utonev': 'Fictional'},
              'original': {'csaladnev': 'Original fictional'},
              'third_country_applicable': false,
              'readiness': {
                'blockers': ['owner_verification_required'],
              },
            }),
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: pmsTheme(),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        editVizaIdentity(context, PmsWorkflows(c), 'g1'),
                    child: const Text('Review'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Review'));
          await tester.pumpAndSettle();
          expect(find.textContaining('Original fictional'), findsOneWidget);
          expect(find.text(ui('VIZA identity review')), findsOneWidget);
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
          await tester.ensureVisible(find.text(ui('Save')));
          await tester.tap(find.text(ui('Save')));
          await tester.pumpAndSettle();
          final sent =
              fake.requests
                      .where((r) => r.method == 'PUT' && r.path == path)
                      .single
                      .body
                  as Map;
          expect((sent['manual'] as Map)['csaladnev'], '\u0150rfi');
          expect(sent.containsKey('original'), false);
          expect(sent.containsKey('actor_id'), false);
          expect(sent['third_country_applicable'], false);
          expect(sent['confirm_ambiguities'], false);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          auth.dispose();
        },
      );
    }
  }
}
