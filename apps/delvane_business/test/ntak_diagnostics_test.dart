import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/ntak_reporting_dialog.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';

import 'support/fake_pms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await WebStrings.current.load();
  });
  for (final lang in ['en', 'hu']) {
    testWidgets('multiple persisted diagnostics and dated source link in $lang', (
      tester,
    ) async {
      tester.view.physicalSize = Size(lang == 'hu' ? 390 : 1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakePms();
      final auth = await signedIn(fake);
        fake.requests.clear();
      final c = PmsController(auth);
      addTearDown(() {
        c.dispose();
        auth.dispose();
        WebStrings.current.language = 'en';
      });
      WebStrings.current.language = lang;
      fake.overrides['/api/government/ntak/properties/p1/jobs/j1/diagnostics'] =
          ApiResponse(
            200,
            jsonEncode({
              'state': 'review_required',
              'source': {'kind': 'business_day', 'business_date': '2032-05-09'},
              'results': [
                {
                  'phase': 'receipt',
                  'created_at': '2032-05-10T09:00:00Z',
                  'diagnostics': [],
                },
                {
                  'phase': 'verification',
                  'created_at': '2032-05-10T09:06:00Z',
                  'diagnostics': [
                    {
                      'severity': 'warning',
                      'code': 'MasodlagosMax',
                      'field': 'napiFeltoltes.szobaAdatok.osszesSzoba',
                      'guidance': 'capacity',
                    },
                    {
                      'severity': 'error',
                      'code': 'Formatum',
                      'field': 'GLOBAL',
                      'guidance': 'format',
                    },
                  ],
                },
              ],
            }),
          );
      fake.overrides['/api/properties/p1/business-days/2032-05-09'] =
          ApiResponse(
            200,
            jsonEncode({
              'business_date': '2032-05-09',
              'day': {'operating': 1},
              'blockers': [],
              'snapshots': [],
              'settings': {},
              'totals': {},
              'correction_reasons': [],
            }),
          );
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: NtakDiagnosticsDialog(c: c, propertyId: 'p1', jobId: 'j1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('MasodlagosMax'), findsOneWidget);
      expect(find.textContaining('Formatum'), findsOneWidget);
      expect(find.text(ntakGuidance('capacity')), findsOneWidget);
      expect(
        find.textContaining('napiFeltoltes.szobaAdatok.osszesSzoba'),
        findsOneWidget,
      );
      final label = lang == 'hu'
          ? 'Forr\u00e1sfolyamat megnyit\u00e1sa'
          : 'Open source workflow';
      await tester.ensureVisible(find.text(label));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(
        fake.requests.any(
          (r) => r.path == '/api/properties/p1/business-days/2032-05-09',
        ),
        isTrue,
      );
      expect(
        fake.requests.where(
          (r) => r.method != 'GET' && !r.path.contains('auth'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
