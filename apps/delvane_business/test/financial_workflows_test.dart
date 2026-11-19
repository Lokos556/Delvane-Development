import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/financial_controls.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';

import 'support/fake_pms.dart';

const catalog = {
  'categories': {
    'SZALLASDIJ': [],
    'IFA': [],
    'ETEL': ['FOETEL'],
  },
  'vat_rates': ['0', '5', '18', '27'],
  'payment_methods': ['KESZPENZ', 'BANKKARTYA'],
};
Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is PmsField && w.label == label),
  matching: find.byType(TextFormField),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await WebStrings.current.load();
  });
  for (final lang in ['en', 'hu']) {
    testWidgets(
      'decimal charge form on ${lang == 'hu' ? 'mobile' : 'desktop'} in $lang',
      (tester) async {
        tester.view.physicalSize = Size(lang == 'hu' ? 390 : 1200, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final fake = FakePms();
        final auth = await signedIn(fake);
        final c = PmsController(auth);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          auth.dispose();
          WebStrings.current.language = "en";
        });
        c.strings.language = lang;
        WebStrings.current.language = lang;
        fake.overrides['/api/reservations/r1/actual-stay'] = const ApiResponse(
          200,
          '{"planned_allocations":[],"guests":[]}',
        );
        fake.overrides['/api/reservations/r1/folio'] = const ApiResponse(
          200,
          '{"ok":true}',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: pmsTheme(),
            home: Scaffold(
              body: FinancialEntryDialog(
                api: PmsWorkflows(c),
                path: '/api/reservations/r1/folio',
                kind: 'charge',
                catalog: catalog,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final entry in {
          'Description': 'Fictional accommodation',
          'Unit price': '28000.00',
          'Reason': 'Fictional reviewed charge',
        }.entries) {
          await tester.ensureVisible(field(entry.key));
          await tester.enterText(field(entry.key), entry.value);
        }
        final save = find.text(
          lang == 'en' ? 'Save entry' : 'T\u00e9tel ment\u00e9se',
        );
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        final request = fake.requests
            .where((r) => r.method == 'POST' && r.path.endsWith('/folio'))
            .single;
        final body = request.body as Map;
        expect(body['unit_price'], '28000.00');
        expect(body['category'], 'SZALLASDIJ');
        expect(body['in_package'], true);
        expect(body.containsKey('actor_id'), false);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'closed-day charge correction preserves original link and audit reason',
    (tester) async {
      final fake = FakePms();
      final auth = await signedIn(fake);
      final c = PmsController(auth);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
        WebStrings.current.language = "en";
      });
      c.strings.language = 'en';
      WebStrings.current.language = 'en';
      fake.overrides['/api/reservations/r1/actual-stay'] = const ApiResponse(
        200,
        '{"planned_allocations":[],"guests":[]}',
      );
      fake.overrides['/api/reservations/r1/folio'] = const ApiResponse(
        200,
        '{"ok":true}',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: FinancialEntryDialog(
              api: PmsWorkflows(c),
              path: '/api/reservations/r1/folio',
              kind: 'charge',
              catalog: catalog,
              entry: const {
                'id': 'original',
                'description': 'Fictional accommodation',
                'unit_price': '28000',
                'quantity': '1',
                'business_date': '2032-05-09',
                'category': 'SZALLASDIJ',
                'vat': '5',
                'in_package': 1,
                'reason': 'Original reason',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('Unit price'));
      await tester.enterText(field('Unit price'), '27000');
      await tester.ensureVisible(field('Reason'));
      await tester.enterText(field('Reason'), 'Correct mistaken price');
      await tester.ensureVisible(find.text('Save entry'));
      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      final body =
          fake.requests
                  .where((r) => r.method == 'POST' && r.path.endsWith('/folio'))
                  .single
                  .body
              as Map;
      expect(body['supersedes'], 'original');
      expect(body['reason'], 'Correct mistaken price');
      expect(body['unit_price'], '27000');
    },
  );
  testWidgets(
    'daily closing displays readiness and uses normal business close',
    (tester) async {
      final fake = FakePms();
      final auth = await signedIn(fake);
      final c = PmsController(auth);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
        WebStrings.current.language = "en";
      });
      c.strings.language = 'en';
      WebStrings.current.language = 'en';
      final day = DateTime.now()
          .subtract(const Duration(days: 1))
          .toIso8601String()
          .substring(0, 10);
      final path = '/api/properties/p1/business-days/$day';
      fake.overrides[path] = ApiResponse(
        200,
        jsonEncode({
          'business_date': day,
          'settings': {
            'start_date': day,
            'timezone': 'Europe/Budapest',
            'closing_hour': 10,
            'automatic': 0,
          },
          'day': {'operating': 1},
          'guest_nights': 3,
          'sold_units': 2,
          'totals': {
            'charges': '28467.00',
            'payments': '28467.00',
            'refunds': '0.00',
            'balance': '0.00',
          },
          'blockers': [],
          'snapshots': [],
          'correction_reasons': ['TERHELES_VAGY_KOLTES_JAV'],
        }),
      );
      fake.overrides['$path/close'] = const ApiResponse(200, '{"revision":1}');
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: BusinessDayDialog(api: PmsWorkflows(c), propertyId: 'p1'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('Reason'));
      await tester.enterText(
        field('Reason'),
        'Reviewed fictional operational day',
      );
      await tester.ensureVisible(find.text('Close or revise business day'));
      await tester.tap(find.text('Close or revise business day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      final request = fake.requests
          .where((r) => r.method == 'POST' && r.path == '$path/close')
          .single;
      final body = request.body as Map;
      expect(body['reason'], 'Reviewed fictional operational day');
      expect(body.containsKey('napiFeltoltes'), false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'property charge correction keeps its history and source endpoint',
    (tester) async {
      final fake = FakePms();
      final auth = await signedIn(fake);
      final c = PmsController(auth);
      WebStrings.current.language = 'en';
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
        WebStrings.current.language = 'en';
      });
      final entry = {
        'id': 'e1',
        'kind': 'charge',
        'description': 'Fictional other charge',
        'unit_price': '100',
        'quantity': '1',
        'business_date': '2032-05-09',
        'category': 'ETEL',
        'subcategory': 'FOETEL',
        'vat': '27',
        'in_package': 0,
        'total_huf': '100.00',
        'reason': 'Original posting',
      };
      fake.overrides['/api/properties/p1/financial-entries'] = ApiResponse(
        200,
        jsonEncode({
          ...catalog,
          'business_date': '2032-05-09',
          'entries': [entry],
          'history': [entry],
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: PropertyFinanceDialog(
              api: PmsWorkflows(c),
              propertyId: 'p1',
              businessDate: '2032-05-09',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Correct entry'));
      await tester.tap(find.text('Correct entry'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(field('Unit price'));
      await tester.enterText(field('Unit price'), '80');
      await tester.ensureVisible(field('Reason'));
      await tester.enterText(
        field('Reason'),
        'Fictional corrected other charge',
      );
      await tester.ensureVisible(find.text('Save entry'));
      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      final body =
          fake.requests
                  .where(
                    (r) =>
                        r.method == 'POST' &&
                        r.path == '/api/properties/p1/financial-entries',
                  )
                  .single
                  .body
              as Map;
      expect(body['supersedes'], 'e1');
      expect(body['unit_price'], '80');
      expect(body['business_date'], '2032-05-09');
      expect(tester.takeException(), isNull);
    },
  );
}
