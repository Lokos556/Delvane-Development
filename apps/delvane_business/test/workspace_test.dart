import 'package:delvane_business/features/workspace/workspace_page.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/app/app.dart';
import 'package:delvane_business/core/auth/auth_controller.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/workspace/workspace_controller.dart';
import 'package:delvane_business/features/workspace/workspace_models.dart';
import 'package:delvane_business/features/workspace/workspace_repository.dart';
import 'support/fake_pms.dart';

void main() {
  test(
    'property scope uses stable IDs even when property display names match',
    () async {
      final pms = FakePms();
      pms.overrides['/api/properties'] = pms.json([
        pms.property,
        {...pms.property, 'id': 'p2'},
      ]);
      pms.overrides['/api/operations/today-command'] = pms.json({
        'date': '2032-05-10',
        'arrivals': [
          pms.stay,
          {...pms.stay, 'id': 'r2', 'property_id': 'p2'},
        ],
        'departures': [pms.stay],
        'cleaning': [],
        'registration_risks': [],
      });
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      final controller = WorkspaceController(
        auth,
        WorkspaceRepository(auth.api),
      );
      addTearDown(controller.dispose);
      await controller.load();
      expect(controller.workspace!.departures.single.ref.id, 'r1');
      controller.selectProperty('p2');
      expect(
        controller.scoped(controller.workspace!.arrivals).single.ref.id,
        'r2',
      );
      expect(controller.scoped(controller.workspace!.departures), isEmpty);
    },
  );
  test(
    'cleaner API without an assigned display name identifies the signed-in worker',
    () async {
      final pms = FakePms()..role = 'cleaner';
      final task = pms.task..remove('assigned_name');
      pms.overrides['/api/worker/dashboard'] = pms.json({
        'date': '2032-05-10',
        'tasks': [task],
      });
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      final data = await WorkspaceRepository(auth.api).load(auth.user!);
      expect(data.cleaning.single.fields['Assigned to'], auth.user!.name);
    },
  );
  test(
    'owner operational mapping uses server date, stable IDs and independent registration/readiness states',
    () async {
      final pms = FakePms();
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      final repository = WorkspaceRepository(auth.api);
      final result = await repository.load(auth.user!);
      expect(result.date, '2032-05-10');
      expect(result.arrivals.single.propertyId, 'p1');
      expect(result.departures, isEmpty);
      expect(result.cleaning.single.ref.kind, RecordKind.cleaning);
      expect(result.maintenance.single.ref.kind, RecordKind.maintenance);
      expect(result.registration.single.status, 'incomplete');
      expect(result.priorities.length, 3);
      expect(result.properties.single.state, 'attention');
      final detail = await repository.detail(
        auth.user!,
        const RecordRef(RecordKind.reservation, 'r1'),
        result,
      );
      expect(detail.fields['Reservation amount (HUF)'], '9007199254740993');
      expect(detail.links.any((l) => l.ref.kind == RecordKind.cleaning), true);
      final property = await repository.detail(
        auth.user!,
        const RecordRef(RecordKind.property, 'p1'),
        result,
      );
      expect(property.fields['Same-day turnover'], 'Yes');
      final task = await repository.detail(
        auth.user!,
        const RecordRef(RecordKind.cleaning, 't1'),
        result,
      );
      expect(task.checklist.single.completed, false);
    },
  );
  for (final role in ['owner', 'manager', 'cleaner', 'maintenance']) {
    test('$role loads only authorized endpoints and navigation', () async {
      final pms = FakePms()..role = role;
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      final repo = WorkspaceRepository(auth.api);
      final data = await repo.load(auth.user!);
      final operator = role == 'owner' || role == 'manager';
      expect(tabsFor(auth.user!).contains(WorkspaceTab.reservations), operator);
      if (!operator) {
        expect(data.arrivals, isEmpty);
        expect(data.registration, isEmpty);
        expect(data.properties.single.state, isNull);
        expect(
          pms.requests.any(
            (r) =>
                r.path == '/api/properties' ||
                r.path.startsWith('/api/owner/') ||
                r.path.startsWith('/api/reservations'),
          ),
          false,
        );
        final before = pms.requests.length;
        await expectLater(
          repo.reservations(auth.user!),
          throwsA(isA<ApiException>()),
        );
        await expectLater(
          repo.detail(
            auth.user!,
            const RecordRef(RecordKind.reservation, 'r1'),
            data,
          ),
          throwsA(isA<ApiException>()),
        );
        expect(pms.requests.length, before);
      }
      if (role == 'cleaner') {
        final detail = await repo.detail(
          auth.user!,
          const RecordRef(RecordKind.cleaning, 't1'),
          data,
        );
        expect(detail.fields['Preparation'], 'Prepare cot');
        expect(
          pms.requests.any((r) => r.path.startsWith('/api/work-tasks/')),
          false,
        );
        pms.empty = true; // Task reassigned/removed after the home snapshot.
        await expectLater(
          repo.detail(
            auth.user!,
            const RecordRef(RecordKind.cleaning, 't1'),
            data,
          ),
          throwsA(isA<ApiException>()),
        );
      }
    });
  }
  test(
    'malformed data fails instead of fabricating counts, IDs or mock records',
    () async {
      final pms = FakePms();
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      pms.overrides['/api/operations/today-command'] = pms.json({
        'date': '2032-05-10',
        'arrivals': [
          {'guest_name': 'No ID'},
        ],
        'departures': [],
        'cleaning': [],
        'registration_risks': [],
      });
      await expectLater(
        WorkspaceRepository(auth.api).load(auth.user!),
        throwsA(isA<ApiException>()),
      );
    },
  );
  test(
    'refresh discards old records on failure; selected property is validated',
    () async {
      final pms = FakePms();
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      final controller = WorkspaceController(
        auth,
        WorkspaceRepository(auth.api),
      );
      addTearDown(controller.dispose);
      await controller.load();
      controller.selectProperty('p1');
      expect(controller.scoped(controller.workspace!.arrivals).length, 1);
      controller.selectProperty('unknown');
      expect(controller.propertyId, 'p1');
      pms.overrides['/api/maintenance'] = const ApiResponse(503, 'private');
      await controller.load();
      expect(controller.phase, WorkspacePhase.error);
      expect(controller.workspace, isNull);
      expect(controller.error, isNot(contains('private')));
    },
  );
  for (final size in [
    const Size(320, 780),
    const Size(390, 844),
    const Size(844, 390),
    const Size(768, 1024),
    const Size(1440, 1000),
  ]) {
    testWidgets('connected role screens and record navigation fit $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final role in ['owner', 'manager', 'cleaner', 'maintenance']) {
        final pms = FakePms()..role = role;
        final auth = await signedIn(pms);
        await tester.pumpWidget(
          DelvaneBusinessApp(
            key: ValueKey(role),
            auth: auth,
            workspaceBuilder: (auth) => WorkspacePage(auth: auth),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Connected · isolated data'),
          findsOneWidget,
        );
        expect(find.textContaining('Mock data only'), findsNothing);
        for (final tab in tabsFor(auth.user!)) {
          final key = find.byKey(ValueKey('live-nav-${tab.name}'));
          // Medium rail has labeled destinations instead of sidebar keys.
          if (key.evaluate().isNotEmpty) {
            await tester.tap(key);
          } else {
            final label = switch (tab) {
              WorkspaceTab.today =>
                role == 'cleaner'
                    ? 'My day'
                    : role == 'maintenance'
                    ? 'My cases'
                    : 'Today',
              WorkspaceTab.reservations => 'Stays',
              WorkspaceTab.properties => 'Properties',
              WorkspaceTab.work => 'Work',
              WorkspaceTab.account => 'Account',
            };
            await tester.tap(
              find.descendant(
                of: find.byType(NavigationRail),
                matching: find.text(label),
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$role/$tab/$size');
        }
        await tester.pumpWidget(const SizedBox());
        auth.dispose();
      }
    });
  }
  testWidgets(
    'login submits backend credentials then revocation removes protected record routes',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = FakePms();
      final auth = makeAuth(pms);
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        DelvaneBusinessApp(
          auth: auth,
          workspaceBuilder: (auth) => WorkspacePage(auth: auth),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('login-email')),
        'owner@workspace.invalid',
      );
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        'synthetic-password',
      );
      await tester.tap(find.byKey(const ValueKey('sign-in')));
      await tester.pumpAndSettle();
      expect(find.text('Operational priorities · 3'), findsOneWidget);
      await tester.tap(find.text('Synthetic Guest').first);
      await tester.pumpAndSettle();
      expect(find.text('Reservation amount (HUF)'), findsOneWidget);
      pms.revoked = true;
      await tester.tap(find.byTooltip('Refresh record'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
      expect(find.text('Reservation amount (HUF)'), findsNothing);
      expect(find.textContaining('expired or was revoked'), findsOneWidget);
    },
  );
  testWidgets(
    'property scope, record links and back navigation operate on backend IDs',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = FakePms();
      final auth = await signedIn(pms);
      await tester.pumpWidget(
        DelvaneBusinessApp(
          auth: auth,
          workspaceBuilder: (auth) => WorkspacePage(auth: auth),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('All accessible properties'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test House').last);
      await tester.pumpAndSettle();
      expect(find.text('All accessible properties'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('live-nav-reservations')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('live-reservation-search')),
        'r1',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic Guest'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Open property'));
      await tester.tap(find.text('Open property'));
      await tester.pumpAndSettle();
      expect(find.text('Same-day turnover'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Reservation amount (HUF)'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('live-reservation-search')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('logout')));
      await tester.pumpAndSettle();
      expect(pms.revoked, true);
      expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
      auth.dispose();
    },
  );
  testWidgets('role changes discard owner routes and load a worker workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final pms = FakePms();
    final auth = await signedIn(pms);
    await tester.pumpWidget(
      DelvaneBusinessApp(
        auth: auth,
        workspaceBuilder: (auth) => WorkspacePage(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-nav-reservations')));
    await tester.pumpAndSettle();
    pms.role = 'cleaner';
    await auth.revalidate();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-nav-reservations')), findsNothing);
    expect(find.text('Registration issues · 1'), findsNothing);
    expect(find.text('My cleaning schedule · 1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    auth.dispose();
  });
  testWidgets(
    'loading, disconnected error, retry and empty states never display fixtures',
    (tester) async {
      final pms = FakePms();
      final auth = await signedIn(pms);
      final pending = Completer<ApiResponse>();
      pms.delayedCommand = pending.future;
      await tester.pumpWidget(
        DelvaneBusinessApp(
          auth: auth,
          workspaceBuilder: (auth) => WorkspacePage(auth: auth),
        ),
      );
      await tester.pump();
      expect(find.text('Loading operational workspace…'), findsOneWidget);
      pending.complete(const ApiResponse(503, 'private-response'));
      await tester.pumpAndSettle();
      expect(find.text('Workspace unavailable'), findsOneWidget);
      expect(find.text('No demo data has been substituted.'), findsOneWidget);
      pms.delayedCommand = null;
      pms.empty = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('No items in this scope.'), findsWidgets);
      expect(find.text('No accessible properties.'), findsOneWidget);
      expect(find.text('Synthetic Guest'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    },
  );
  testWidgets('session expiry timer removes data and returns to sign-in', (
    tester,
  ) async {
    final auth = await signedIn(FakePms());
    addTearDown(auth.dispose);
    await tester.pumpWidget(
      DelvaneBusinessApp(
        auth: auth,
        workspaceBuilder: (auth) => WorkspacePage(auth: auth),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(days: 8));
    await tester.pumpAndSettle();
    expect(auth.phase, AuthPhase.signedOut);
    expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
  });
  testWidgets(
    'offline demo requires explicit selection and can return to sign-in',
    (tester) async {
      final auth = makeAuth(FakePms());
      addTearDown(auth.dispose);
      await tester.pumpWidget(
        DelvaneBusinessApp(
          auth: auth,
          workspaceBuilder: (auth) => WorkspacePage(auth: auth),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Mock data only'), findsNothing);
      await tester.ensureVisible(find.text('Explore offline demo'));
      await tester.tap(find.text('Explore offline demo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mock data only'), findsOneWidget);
      await tester.tap(find.text('Exit demo'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    },
  );
}
