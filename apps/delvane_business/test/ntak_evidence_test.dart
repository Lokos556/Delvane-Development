import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/ntak_evidence_dialog.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';

import 'support/fake_pms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await WebStrings.current.load();
  });
  for (final lang in ['en', 'hu']) {
    testWidgets(
      'owner evidence preparation is explicit and labelled in $lang',
      (tester) async {
        tester.view.physicalSize = Size(lang == 'hu' ? 390 : 1200, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fake = FakePms();
        final auth = await signedIn(fake);
        final c = PmsController(auth);
        addTearDown(() {
          c.dispose();
          auth.dispose();
          WebStrings.current.language = 'en';
        });
        WebStrings.current.language = lang;
        fake.requests.clear();
        const path =
            '/api/government/ntak/properties/p1/jobs/j1/evidence-export';
        fake.overrides[path] = ApiResponse(
          200,
          jsonEncode({
            'format': 'delvane.ntak.evidence',
            'official_acceptance_confirmed': false,
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: pmsTheme(),
            home: Scaffold(
              body: NtakEvidenceDialog(c: c, propertyId: 'p1', jobId: 'j1'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(fake.requests, isEmpty);
        final label = lang == 'hu'
            ? 'Bizony\u00edt\u00e9kcsomag elk\u00e9sz\u00edt\u00e9se'
            : 'Prepare evidence package';
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(fake.requests, isEmpty);
        await tester.enterText(
          find.byType(TextFormField).first,
          'Fictional local evidence review',
        );
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        final req = fake.requests.single;
        expect(req.path, path);
        expect(req.method, 'POST');
        expect(req.headers['X-Rosa-CSRF'], fakeCsrf);
        expect(
          find.textContaining('official_acceptance_confirmed'),
          findsOneWidget,
        );
        expect(find.textContaining('delvane.ntak.evidence'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
