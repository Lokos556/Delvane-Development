import 'support/section_navigation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/operational_desk.dart';
import 'package:delvane_business/features/pms/administration_pages.dart';

import 'support/fake_pms.dart';

void main() {
  testWidgets(
    'simulation shows reference counts, action labels and structured memory',
    (t) async {
      final pms = FakePms();
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      c.data.addAll({
        'organization': {'operating_mode': 'observe'},
        'preferences': <String, dynamic>{},
        'actions': [
          {
            'status': 'simulated',
            'payload': {'label': 'Synthetic action'},
            'operating_mode': 'observe',
          },
          {'status': 'awaiting_approval'},
          {'status': 'executed'},
        ],
        'memory': {
          'business': [
            {
              'memory_key': 'operational_fact',
              'value': {'quiet_hours': '22:00'},
              'subject_type': 'property',
              'confidence': .87,
            },
          ],
          'guest_preferences': [],
        },
      });
      try {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: OperatingModePage(c: c)),
            ),
          ),
        );
        expect(find.text('Simulated'), findsOneWidget);
        expect(find.text('Awaiting approval'), findsOneWidget);
        expect(find.text('Executed'), findsOneWidget);
        expect(find.text('1'), findsNWidgets(3));
        expect(find.text('Synthetic action'), findsOneWidget);
        expect(find.textContaining('"quiet_hours":"22:00"'), findsOneWidget);
        expect(find.textContaining('confidence 87%'), findsOneWidget);
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );
  for (final decision in ['Approve', 'Decline']) {
    testWidgets('$decision resolves the existing approval contract with CSRF', (
      t,
    ) async {
      final pms = FakePms();
      pms.overrides['/api/approvals/a1/resolve'] = pms.json({'ok': true});
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.intelligence);
      c.data['intelligence'] = {
        'approvals': [
          {
            'id': 'a1',
            'kind': 'decision',
            'title': 'Synthetic approval',
            'detail': 'Review the existing record.',
            'recommendation': 'Review',
          },
        ],
      };
      try {
        await t.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => openOperationalDesk(context, c, tab: 1),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await t.tap(find.text('Open'));
        await t.pumpAndSettle();
        await t.tap(find.text(decision));
        await t.pumpAndSettle();
        final request = pms.requests.singleWhere(
          (r) => r.path == '/api/approvals/a1/resolve',
        );
        expect(request.method, 'POST');
        expect(request.body, {
          'decision': decision == 'Approve' ? 'Approved' : 'Declined',
        });
        expect(request.headers['X-Rosa-CSRF'], fakeCsrf);
        expect(find.byType(OperationalDesk), findsNothing);
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    });
  }
  testWidgets(
    'failed decision retains the desk and errors without claiming resolution',
    (t) async {
      final pms = FakePms();
      pms.overrides['/api/approvals/a1/resolve'] = pms.json({
        'detail': 'conflict',
      }, 409);
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.intelligence);
      c.data['intelligence'] = {
        'approvals': [
          {'id': 'a1', 'title': 'Synthetic approval'},
        ],
      };
      try {
        await t.pumpWidget(MaterialApp(home: OperationalDesk(c: c, tab: 1)));
        await t.tap(find.text('Approve'));
        await t.pumpAndSettle();
        expect(find.byType(OperationalDesk), findsOneWidget);
        expect(find.textContaining('conflicts'), findsOneWidget);
        expect(find.text('Synthetic approval'), findsOneWidget);
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );
  testWidgets('worker cannot open operator desk', (t) async {
    final pms = FakePms()..role = 'cleaner';
    final auth = await signedIn(pms);
    final c = PmsController(auth);
    try {
      await t.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => openOperationalDesk(context, c),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open'));
      await t.pumpAndSettle();
      expect(find.byType(OperationalDesk), findsNothing);
      expect(
        pms.requests.where((r) => r.path.contains('/approvals/')),
        isEmpty,
      );
    } finally {
      await t.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    }
  });
  testWidgets('mobile desk switches tabs and scrolls next-48-hour arrivals', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final pms = FakePms();
    final auth = await signedIn(pms);
    final c = PmsController(auth);
    c.data['intelligence'] = {
      'arrivals': [pms.stay],
    };
    try {
      await t.pumpWidget(MaterialApp(home: OperationalDesk(c: c)));
      await selectSection(t, 'Next 48h  1');
      await t.pumpAndSettle();
      expect(find.text('Synthetic Guest'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    }
  });
  testWidgets(
    'security uses server runtime and permissions without exposing data path',
    (t) async {
      final pms = FakePms();
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      c.data['runtime'] = {
        'environment': 'isolated',
        'version': 'server-version',
        'schema_version': 42,
        'database_backend': 'sqlite',
        'data_path': 'PRIVATE-PATH',
      };
      c.data['security'] = {
        'permissions': {
          'manager': ['reservations.read'],
        },
        'password_scheme': 'scrypt',
      };
      c.data['audit'] = [];
      c.data['retention'] = [];
      try {
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: SecurityPage(c: c)),
            ),
          ),
        );
        expect(find.text('server-version'), findsOneWidget);
        expect(find.text('42'), findsOneWidget);
        expect(find.text('reservations.read'), findsOneWidget);
        expect(find.text('PRIVATE-PATH'), findsNothing);
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );
}
