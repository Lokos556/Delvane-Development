import 'support/section_navigation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';
import 'package:delvane_business/features/pms/operations_workflows.dart';
import 'package:delvane_business/features/pms/reservation_dialogs.dart';
import 'package:delvane_business/features/pms/work_assignment_dialog.dart';

import 'support/fake_pms.dart';
import 'support/management_pms.dart';

Widget host(Widget child) => MaterialApp(
  theme: pmsTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  for (final role in ['cleaner', 'maintenance']) {
    test('worker $role cannot create or reassign work', () async {
      final pms = ManagementPms()..role = role;
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      addTearDown(() {
        c.dispose();
        auth.dispose();
      });
      final flow = OperationsWorkflows(c);
      await expectLater(flow.createCleaning({}), throwsStateError);
      await expectLater(
        flow.assign({'id': 'work'}, 'someone'),
        throwsStateError,
      );
      expect(
        pms.requests.where(
          (r) => r.path == '/api/work-tasks' || r.path.endsWith('/assignment'),
        ),
        isEmpty,
      );
    });
  }
  for (final role in ['owner', 'manager']) {
    test('operator $role uses exact assignment contracts', () async {
      final pms = ManagementPms()..role = role;
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      addTearDown(() {
        c.dispose();
        auth.dispose();
      });
      final flow = OperationsWorkflows(c);
      await flow.assign({'id': 't1', 'kind': 'cleaning'}, 'staff1');
      final request = pms.requests.last;
      expect(request.path, '/api/work-tasks/t1/assignment');
      expect(request.body, {'assigned_to': 'staff1'});
      expect(request.headers['X-Rosa-CSRF'], fakeCsrf);
      await flow.createCleaning({'title': 'Synthetic'});
      expect(pms.requests.last.path, '/api/work-tasks');
    });
  }
  testWidgets(
    'assignment form preserves input on failure and excludes inactive people',
    (tester) async {
      final pms = ManagementPms();
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      addTearDown(() {
        c.dispose();
        auth.dispose();
      });
      c.data['team'] = {
        'members': [
          ...pms.members,
          {
            'id': 'inactive',
            'full_name': 'Suspended Person',
            'role': 'cleaner',
            'active': 0,
          },
        ],
      };
      c.data['properties'] = [pms.property];
      pms.failManagement = true;
      await tester.pumpWidget(
        host(
          WorkAssignmentDialog(
            c: c,
            work: const {'id': 't1', 'kind': 'cleaning'},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unassigned').first);
      await tester.pumpAndSettle();
      expect(find.text('Suspended Person'), findsNothing);
      await tester.tap(find.text('Synthetic Worker').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic Worker'), findsOneWidget);
      expect(find.byType(WorkAssignmentDialog), findsOneWidget);
      expect(find.textContaining('synthetic private diagnostic'), findsNothing);
    },
  );
  testWidgets(
    'cancelled reservation cannot offer guest collection or identity review',
    (tester) async {
      final pms = ManagementPms()..booking['status'] = 'cancelled';
      final auth = await signedIn(pms);
      final c = PmsController(auth);
      addTearDown(() {
        c.dispose();
        auth.dispose();
      });
      await tester.pumpWidget(
        host(
          ReservationWorkspace(
            api: PmsWorkflows(c),
            id: 'r1',
            openReception: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await selectSection(tester, 'Preparation');
      await tester.pumpAndSettle();
      expect(find.text('Send guest check-in link'), findsNothing);
      final review = tester.widget<PmsButton>(
        find.widgetWithText(PmsButton, 'Review identity verification'),
      );
      expect(review.onPressed, isNull);
    },
  );
  testWidgets('registration is derived and verified state survives reopening', (
    tester,
  ) async {
    final pms = ManagementPms()
      ..verification = 'verified'
      ..booking['registration_status'] = 'complete';
    final auth = await signedIn(pms);
    final c = PmsController(auth);
    addTearDown(() {
      c.dispose();
      auth.dispose();
    });
    for (var i = 0; i < 2; i++) {
      await tester.pumpWidget(
        host(
          ReservationWorkspace(
            key: ValueKey(i),
            api: PmsWorkflows(c),
            id: 'r1',
            openReception: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Registration follows guest data and identity review.'),
        findsOneWidget,
      );
      final selects = tester.widgetList<PmsSelect>(find.byType(PmsSelect));
      expect(
        selects.any(
          (s) =>
              s.items.containsKey('complete') &&
              s.items.containsKey('incomplete'),
        ),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
  test('new work and identity captions have Hungarian translations', () async {
    final strings = WebStrings()..language = 'hu';
    await strings.load();
    for (final label in [
      'Create cleaning task',
      'Assign work',
      'Assignee',
      'Select an active assignee.',
      'Registration follows guest data and identity review.',
    ]) {
      expect(strings.t(label), isNot(label));
    }
  });
}
