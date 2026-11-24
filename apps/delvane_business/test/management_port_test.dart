import 'support/section_navigation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/app/app.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/administration_pages.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/property_dialog.dart';
import 'package:delvane_business/features/pms/team_page.dart';
import 'package:delvane_business/features/pms/operations_pages.dart';
import 'package:delvane_business/features/pms/operations_workflows.dart';

import 'support/fake_pms.dart';
import 'support/management_pms.dart';

Future<void> field(WidgetTester tester, String label, String value) async {
  final finder = find.descendant(
    of: find.byWidgetPredicate((w) => w is PmsField && w.label == label),
    matching: find.byType(TextFormField),
  );
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
}

Widget host(Widget body) => MaterialApp(
  theme: pmsTheme(),
  home: Scaffold(body: SingleChildScrollView(child: body)),
);

void main() {
  testWidgets(
    'owner edit submits role and suspension, and reset confirms before revealing credentials',
    (tester) async {
      final pms = ManagementPms();
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      try {
        await tester.pumpWidget(
          host(
            TeamMemberEditor(
              c: c,
              roles: pms.groups,
              member: pms.members.first,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final roleSelect = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is PmsSelect && w.label == 'Delvane role',
          ),
          matching: find.byType(DropdownButtonFormField<String>),
        );
        await tester.ensureVisible(roleSelect);
        await tester.tap(roleSelect);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Maintenance').last);
        await tester.pumpAndSettle();
        final activeSelect = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is PmsSelect && w.label == 'Account status',
          ),
          matching: find.byType(DropdownButtonFormField<String>),
        );
        await tester.ensureVisible(activeSelect);
        await tester.tap(activeSelect);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Suspended').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save changes'));
        await tester.tap(find.text('Save changes'));
        await tester.pumpAndSettle();
        final patch = pms.requests.lastWhere((r) => r.method == 'PATCH');
        expect(patch.path, '/api/team/members/staff1');
        expect((patch.body as Map)['role'], 'maintenance');
        expect((patch.body as Map)['active'], false);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          host(
            TeamMemberEditor(
              c: c,
              roles: pms.groups,
              member: pms.members.first,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Reset access'));
        await tester.tap(find.text('Reset access'));
        await tester.pumpAndSettle();
        expect(
          pms.requests.where((r) => r.path.endsWith('/reset-access')),
          isEmpty,
        );
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();
        expect(pms.requests.last.path, '/api/team/members/staff1/reset-access');
        expect(find.text('Synthetic-ONE-TIME-123'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );
  testWidgets(
    'knowledge edits preserve scoped entries and use the authority API',
    (tester) async {
      final pms = ManagementPms()..role = 'manager';
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.train);
      try {
        await c.load();
        await tester.pumpWidget(host(KnowledgePage(c: c)));
        await tester.pumpAndSettle();
        await field(tester, 'Parking', 'Synthetic replacement');
        await tester.ensureVisible(find.text('Save knowledge'));
        await tester.tap(find.text('Save knowledge'));
        await tester.pumpAndSettle();
        expect(
          (pms.requests.lastWhere((r) => r.method == 'PUT').body
              as Map)['entries'],
          {'parking': 'Synthetic replacement'},
        );
        expect(find.text('Saved'), findsOneWidget);
        final dropdown = find.byType(DropdownButtonFormField<String>).last;
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Never without owner').last);
        await tester.pumpAndSettle();
        expect(
          pms.requests.lastWhere((r) => r.method == 'PATCH').path,
          '/api/authority/send_reply',
        );
        expect(pms.requests.lastWhere((r) => r.method == 'PATCH').body, {
          'mode': 'never',
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );
  testWidgets(
    'cleaner starts, checks off, and finishes with an empty optional note',
    (tester) async {
      final pms = ManagementPms()..role = 'cleaner';
      final auth = await signedIn(pms);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: pmsTheme(),
            home: PmsShell(auth: auth),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Start cleaning'));
        await tester.tap(find.text('Start cleaning'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Ready to finish'));
        await tester.tap(find.text('Ready to finish'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Mark ready'));
        await tester.pumpAndSettle();
        expect(pms.work['status'], 'complete');
        expect(pms.work['worker_note'], '');
        expect(pms.requests.lastWhere((r) => r.path.endsWith('/finish')).body, {
          'note': '',
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
      }
    },
  );
  testWidgets(
    'session revocation removes a one-time account credential dialog',
    (tester) async {
      final pms = ManagementPms();
      final auth = await signedIn(pms);
      try {
        await tester.pumpWidget(
          DelvaneBusinessApp(
            auth: auth,
            workspaceBuilder: (a) =>
                PmsShell(auth: a, initialPage: PmsPage.team),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('+ Add team member'));
        await tester.tap(find.text('+ Add team member'));
        await tester.pumpAndSettle();
        await field(tester, 'Full name', 'Synthetic New');
        await field(tester, 'Email', 'new@native.invalid');
        await tester.ensureVisible(find.text('Create account'));
        await tester.tap(find.text('Create account'));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic-ONE-TIME-123'), findsOneWidget);
        pms.revoked = true;
        await expectLater(auth.revalidate(), throwsA(isA<ApiException>()));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic-ONE-TIME-123'), findsNothing);
        expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
      }
    },
  );
  for (final role in ['manager', 'cleaner', 'maintenance']) {
    test(
      '$role cannot manage accounts through native workflow service',
      () async {
        final pms = ManagementPms()..role = role;
        final auth = await signedIn(pms);
        final c = PmsController(auth), before = pms.requests.length;
        try {
          final api = OperationsWorkflows(c);
          await expectLater(api.member({'role': 'owner'}), throwsStateError);
          await expectLater(
            api.access('staff1', reset: true),
            throwsStateError,
          );
          expect(pms.requests.length, before);
        } finally {
          c.dispose();
          auth.dispose();
        }
      },
    );
  }
  test('worker cannot verify maintenance, adjust stock, or finish another worker task', () async {
    final pms = ManagementPms()..role = 'maintenance';
    final auth = await signedIn(pms);
    final worker = PmsController(auth);
    try {
      final api = OperationsWorkflows(worker), before = pms.requests.length;
      await expectLater(
        api.maintenanceStatus(pms.maintenance, 'verified'),
        throwsStateError,
      );
      await expectLater(
        api.maintenanceStatus({
          ...pms.maintenance,
          'assigned_to': 'another',
        }, 'resolved'),
        throwsStateError,
      );
      await expectLater(api.stock('s1', 1), throwsStateError);
      await expectLater(api.finish(pms.task, ''), throwsStateError);
      expect(pms.requests.length, before);
    } finally {
      worker.dispose();
      auth.dispose();
    }
  });
  for (final width in [1440.0, 390.0]) {
    for (final page in [PmsPage.team, PmsPage.maintenance, PmsPage.supplies]) {
      testWidgets('${page.name} original controls fit width $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pms = ManagementPms();
        final signed = await signedIn(pms);
        final c = PmsController(signed, initialPage: page);
        try {
          await c.load();
          await tester.pumpWidget(
            host(switch (page) {
              PmsPage.team => TeamPage(c: c),
              PmsPage.maintenance => MaintenancePage(c: c),
              _ => SuppliesPage(c: c),
            }),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (page == PmsPage.team) {
            expect(find.text('Manage'), findsOneWidget);
            await selectSection(tester, 'Access & roles');
            await tester.pumpAndSettle();
            expect(
              find.text('People see only what their job requires.'),
              findsOneWidget,
            );
            await selectSection(tester, 'Workload');
            await tester.pumpAndSettle();
            expect(find.text('Synthetic Worker'), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          signed.dispose();
        }
      });
    }
  }
  testWidgets(
    'manager sees team and role evidence without privileged controls',
    (tester) async {
      final pms = ManagementPms()..role = 'manager';
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.team);
      try {
        await c.load();
        await tester.pumpWidget(host(TeamPage(c: c)));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic Worker'), findsOneWidget);
        expect(find.text('Manage'), findsNothing);
        expect(find.text('+ Add team member'), findsNothing);
        expect(find.text('Reset access'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );
  testWidgets(
    'team creation shows credentials once and never puts them in session storage',
    (tester) async {
      final pms = ManagementPms(), store = MemorySessionStore();
      final auth = await signedIn(pms, store);
      final c = PmsController(auth);
      try {
        await tester.pumpWidget(
          host(TeamMemberEditor(c: c, roles: pms.groups)),
        );
        await tester.pumpAndSettle();
        await field(tester, 'Full name', 'Synthetic New');
        await field(tester, 'Email', 'new@native.invalid');
        await tester.ensureVisible(find.text('Create account'));
        await tester.tap(find.text('Create account'));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic-ONE-TIME-123'), findsOneWidget);
        expect(find.text('Create account'), findsNothing);
        expect(pms.mutationCount, 1);
        expect(
          store.values.values.any((v) => v.contains('Synthetic-ONE-TIME')),
          isFalse,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );
  testWidgets('property room readiness labels update independently', (
    tester,
  ) async {
    final pms = FakePms();
    final auth = await signedIn(pms);
    final c = PmsController(auth);
    const path = '/api/properties/p1/overview';
    void rooms(String first) {
      pms.overrides[path] = pms.json({
        'property': pms.property,
        'unit_readiness': [
          {'unit_id': 'unit-101', 'label': 'Room 101', 'state': first},
          {'unit_id': 'unit-102', 'label': 'Room 102', 'state': 'occupied'},
        ],
      });
    }

    rooms('cleaning');
    try {
      await tester.pumpWidget(
        host(
          PropertyWorkspace(
            c: c,
            id: 'p1',
            openReservation: (_) {},
            openCalendar: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      Finder room(String name) => find.widgetWithText(ListTile, name);
      Finder status(String name, String state) =>
          find.descendant(of: room(name), matching: find.text(state));
      expect(status('Room 101', 'Cleaning pending'), findsOneWidget);
      expect(status('Room 102', 'Occupied'), findsOneWidget);
      rooms('ready');
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(status('Room 101', 'Ready'), findsOneWidget);
      expect(status('Room 102', 'Occupied'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    }
  });

  testWidgets(
    'room creation keeps exact whole inventory and empty property is supported',
    (tester) async {
      final pms = ManagementPms();
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      try {
        await tester.pumpWidget(
          host(
            PropertyWorkspace(
              c: c,
              id: 'p1',
              openReservation: (_) {},
              openCalendar: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('No cleaning scheduled'), findsOneWidget);
        await tester.ensureVisible(find.text('+ Add room type'));
        await tester.tap(find.text('+ Add room type'));
        await tester.pumpAndSettle();
        await field(tester, 'Name', 'Synthetic suite');
        await field(tester, 'Units', '12');
        await tester.ensureVisible(find.text('Create room type'));
        await tester.tap(find.text('Create room type'));
        await tester.pumpAndSettle();
        expect(pms.rooms.single['inventory_count'], 12);
        expect(find.text('Synthetic suite'), findsOneWidget);
        expect(
          pms.requests
              .lastWhere((r) => r.method == 'POST')
              .headers['X-Rosa-CSRF'],
          fakeCsrf,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );
  testWidgets('stock adjustment rejects NaN and saves a fractional quantity', (
    tester,
  ) async {
    final pms = ManagementPms();
    final auth = await signedIn(pms);
    final c = PmsController(auth);
    try {
      await tester.pumpWidget(host(StockEditor(c: c, item: pms.stocks.first)));
      await tester.pumpAndSettle();
      await field(tester, 'Current quantity', 'NaN');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a finite quantity'), findsOneWidget);
      expect(pms.mutationCount, 0);
      await field(tester, 'Current quantity', '12.5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(pms.stocks.first['quantity'], 12.5);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    }
  });
  testWidgets('failed maintenance request shows error and preserves inputs', (
    tester,
  ) async {
    final pms = ManagementPms();
    final auth = await signedIn(pms);
    final c = PmsController(auth);
    c.data['properties'] = [pms.property];
    try {
      await tester.pumpWidget(host(MaintenanceEditor(c: c)));
      await tester.pumpAndSettle();
      await field(tester, 'Issue', 'Synthetic tap');
      pms.failManagement = true;
      await tester.ensureVisible(find.text('Create case'));
      await tester.tap(find.text('Create case'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic tap'), findsOneWidget);
      expect(find.textContaining('synthetic private'), findsNothing);
      expect(pms.mutationCount, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    }
  });
  testWidgets(
    'cleaner maintenance shell uses safe property endpoint without owner controls',
    (tester) async {
      final pms = ManagementPms()..role = 'cleaner';
      final auth = await signedIn(pms);
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: pmsTheme(),
            home: PmsShell(auth: auth, initialPage: PmsPage.maintenance),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('+ Report issue'), findsOneWidget);
        expect(find.text('Verify'), findsNothing);
        expect(find.text('Start work'), findsNothing);
        expect(
          pms.requests.any((r) => r.path == '/api/operations/properties'),
          isTrue,
        );
        expect(pms.requests.any((r) => r.path == '/api/properties'), isFalse);
      } finally {
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
      }
    },
  );
}
