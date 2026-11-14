import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/app/app.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/channel_api.dart';
import 'package:delvane_business/features/pms/channex_mapping_dialog.dart';
import 'package:delvane_business/features/pms/distribution_dialog.dart';
import 'package:delvane_business/features/pms/integrations_page.dart';
import 'package:delvane_business/features/pms/sandbox_dialog.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/property_rates_dialog.dart';
import 'package:delvane_business/features/pms/guest_history_dialog.dart';
import 'package:delvane_business/features/pms/pms_workflows.dart';

import 'support/fake_pms.dart';
import 'support/channel_pms.dart';

Widget host(Widget child) => MaterialApp(
  theme: pmsTheme(),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
Future<void> enter(
  WidgetTester t,
  String label,
  String value, {
  bool first = false,
}) async {
  var field = find.descendant(
    of: find.byWidgetPredicate((w) => w is PmsField && w.label == label),
    matching: find.byType(TextFormField),
  );
  if (first) field = field.first;
  await t.ensureVisible(field);
  await t.enterText(field, value);
}

Future<void> press(WidgetTester t, String label) async {
  await t.ensureVisible(find.text(label));
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'base calendar and 500-day sync use distinct existing operations',
    (t) async {
      final pms = ChannelPms();
      final a = await signedIn(pms), c = PmsController(a);
      try {
        await t.pumpWidget(
          host(
            DistributionDialog(
              api: ChannelApi(c, 'i1'),
              propertyName: 'Test House',
              today: DateTime(2032, 5, 10),
            ),
          ),
        );
        await t.pumpAndSettle();
        await enter(t, 'USD per night', '42000');
        await press(t, 'Set & publish 365 days');
        expect(
          pms.requests.last.path,
          '/api/integrations/i1/channex/base-rate',
        );
        expect(pms.requests.last.body, {
          'base_rate_huf': 42000,
          'horizon_days': 365,
        });
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(
          host(
            DistributionDialog(
              api: ChannelApi(c, 'i1'),
              propertyName: 'Test House',
              today: DateTime(2032, 5, 10),
            ),
          ),
        );
        await t.pumpAndSettle();
        await press(t, 'Run 500-day full sync');
        expect(pms.requests.last.method, 'POST');
        expect(
          pms.requests.last.path,
          '/api/integrations/i1/channex/full-sync',
        );
        expect(find.textContaining('500 days'), findsOneWidget);
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        a.dispose();
      }
    },
  );
  testWidgets('duplicate bulk rate plan is rejected before a mutation', (
    t,
  ) async {
    final pms = ChannelPms();
    final a = await signedIn(pms), c = PmsController(a);
    try {
      await t.pumpWidget(
        host(
          DistributionDialog(
            api: ChannelApi(c, 'i1'),
            propertyName: 'Test House',
            today: DateTime(2032, 5, 10),
          ),
        ),
      );
      await t.pumpAndSettle();
      await press(t, '+ Add rate plan');
      await press(t, 'Save & send bulk updates');
      expect(find.text('Each rate plan can appear only once.'), findsOneWidget);
      expect(pms.mutationCount, 0);
    } finally {
      await t.pumpWidget(const SizedBox());
      c.dispose();
      a.dispose();
    }
  });
  testWidgets('failed ARI save keeps form values and does not claim success', (
    t,
  ) async {
    final pms = ChannelPms();
    final a = await signedIn(pms), c = PmsController(a);
    try {
      await t.pumpWidget(
        host(
          DistributionDialog(
            api: ChannelApi(c, 'i1'),
            propertyName: 'Test House',
            today: DateTime(2032, 5, 10),
          ),
        ),
      );
      await t.pumpAndSettle();
      await enter(t, 'Nightly price · USD', '100.29', first: true);
      pms.failWrite = true;
      await press(t, 'Save & send');
      expect(find.text('100.29'), findsOneWidget);
      expect(find.text('Save & send'), findsOneWidget);
      expect(find.text('Update submitted'), findsNothing);
      expect(pms.mutationCount, 0);
      expect(find.textContaining('private diagnostic'), findsNothing);
    } finally {
      await t.pumpWidget(const SizedBox());
      c.dispose();
      a.dispose();
    }
  });
  testWidgets('session revocation removes an open distribution form', (
    t,
  ) async {
    final pms = ChannelPms();
    final a = await signedIn(pms);
    try {
      await t.pumpWidget(
        DelvaneBusinessApp(
          auth: a,
          workspaceBuilder: (auth) =>
              PmsShell(auth: auth, initialPage: PmsPage.integrations),
        ),
      );
      await t.pumpAndSettle();
      await press(t, 'Rates & availability');
      expect(find.text('Save & send'), findsOneWidget);
      pms.revoked = true;
      await expectLater(a.revalidate(), throwsA(isA<ApiException>()));
      await t.pumpAndSettle();
      expect(find.text('Save & send'), findsNothing);
      expect(find.byKey(const ValueKey('sign-in')), findsOneWidget);
    } finally {
      await t.pumpWidget(const SizedBox());
      a.dispose();
    }
  });
  test('prices retain decimal strings and integer precision; delivery states are truthful', () {
    expect(channelPrice('9007199254740993'), 9007199254740993);
    expect(channelPrice('100.29'), '100.29');
    expect(channelPrice(''), isNull);
    expect(() => channelPrice('NaN'), throwsFormatException);
    expect(deliveryTitle({'no_change': true}), 'No update sent');
    expect(
      deliveryTitle({
        'delivery': {'delivered': [], 'failed': []},
      }),
      'Update queued',
    );
    expect(
      deliveryTitle({
        'delivery': {
          'delivered': [],
          'failed': [
            {'error': 'test'},
          ],
        },
      }),
      'Saved; delivery will retry',
    );
  });
  for (final role in ['cleaner', 'maintenance']) {
    test(
      '$role is denied channel reads and mutations before transport',
      () async {
        final pms = ChannelPms()..role = role;
        final a = await signedIn(pms);
        final controller = PmsController(a), before = pms.requests.length;
        try {
          final api = ChannelApi(controller, 'i1');
          await expectLater(
            api.get('/channex/outbox'),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 403),
            ),
          );
          await expectLater(
            api.change('PUT', '/channex/ari', {}),
            throwsA(
              isA<ApiException>().having((e) => e.statusCode, 'status', 403),
            ),
          );
          expect(pms.requests.length, before);
        } finally {
          controller.dispose();
          a.dispose();
        }
      },
    );
  }
  testWidgets(
    'single ARI saves exact price, false restrictions and unchanged nulls once',
    (t) async {
      final pms = ChannelPms();
      final auth = await signedIn(pms);
      final controller = PmsController(auth);
      try {
        await t.pumpWidget(
          host(
            DistributionDialog(
              api: ChannelApi(controller, 'i1'),
              propertyName: 'Test House',
              today: DateTime(2032, 5, 10),
            ),
          ),
        );
        await t.pumpAndSettle();
        await enter(t, 'Nightly price · USD', '100.29', first: true);
        final stop = find.descendant(
          of: find
              .byWidgetPredicate(
                (w) => w is PmsSelect && w.label == 'Stop sell',
              )
              .first,
          matching: find.byType(DropdownButtonFormField<String>),
        );
        await t.ensureVisible(stop);
        await t.tap(stop);
        await t.pumpAndSettle();
        await t.tap(find.text('No').last);
        await t.pumpAndSettle();
        await press(t, 'Save & send');
        final r = pms.requests.singleWhere(
          (r) => r.method == 'PUT' && r.path.endsWith('/ari'),
        );
        expect((r.body as Map)['rate_huf'], '100.29');
        expect((r.body as Map)['availability'], isNull);
        expect((r.body as Map)['stop_sell'], false);
        expect((r.body as Map)['force_availability'], true);
        expect((r.body as Map)['date_from'], '2032-05-17');
        expect(find.text('Saved; delivery will retry'), findsOneWidget);
        expect(find.text('Save & send'), findsNothing);
        expect(pms.mutationCount, 1);
      } finally {
        await t.pumpWidget(const SizedBox());
        controller.dispose();
        auth.dispose();
      }
    },
  );
  testWidgets('bulk update preserves field ownership and sends one batch', (
    t,
  ) async {
    final pms = ChannelPms();
    final a = await signedIn(pms), c = PmsController(a);
    try {
      await t.pumpWidget(
        host(
          DistributionDialog(
            api: ChannelApi(c, 'i1'),
            propertyName: 'Test House',
            today: DateTime(2032, 5, 10),
          ),
        ),
      );
      await t.pumpAndSettle();
      final fields = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is PmsField && w.label == 'Nightly price · USD',
        ),
        matching: find.byType(TextFormField),
      );
      await t.ensureVisible(fields.last);
      await t.enterText(fields.last, '99.01');
      await press(t, 'Save & send bulk updates');
      final body =
          pms.requests.singleWhere((r) => r.path.endsWith('/ari/batch')).body
              as Map;
      final update = (body['updates'] as List).single as Map;
      expect(update['rate_huf'], '99.01');
      expect(update['rate_plan_id'], 'plan1');
      expect(update.containsKey('availability'), isFalse);
      expect(pms.mutationCount, 1);
    } finally {
      await t.pumpWidget(const SizedBox());
      c.dispose();
      a.dispose();
    }
  });
  testWidgets(
    'mapping read failure removes stale inventory and disables saving',
    (t) async {
      final pms = ChannelPms();
      final a = await signedIn(pms), c = PmsController(a);
      try {
        await t.pumpWidget(
          host(ChannexMappingDialog(api: ChannelApi(c, 'i1'))),
        );
        await t.pumpAndSettle();
        pms.failInventory = true;
        await t.tap(find.byType(DropdownButtonFormField<String>).first);
        await t.pumpAndSettle();
        await t.tap(find.text('Other staging').last);
        await t.pumpAndSettle();
        expect(find.text('Twin'), findsNothing);
        expect(
          t
              .widget<PmsButton>(find.widgetWithText(PmsButton, 'Save mapping'))
              .onPressed,
          isNull,
        );
        expect(pms.mutationCount, 0);
        expect(find.text('Retry inventory read'), findsOneWidget);
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        a.dispose();
      }
    },
  );
  testWidgets(
    'mapping sends complete local and remote room/rate associations',
    (t) async {
      final pms = ChannelPms();
      final a = await signedIn(pms), c = PmsController(a);
      try {
        await t.pumpWidget(
          host(ChannexMappingDialog(api: ChannelApi(c, 'i1'))),
        );
        await t.pumpAndSettle();
        await press(t, 'Save mapping');
        final body = pms.requests.last.body as Map;
        expect(body['channex_property_id'], 'remote-property');
        expect(body['room_mappings'], [
          {'room_type_id': 'room1', 'channex_room_type_id': 'remote-room'},
        ]);
        expect(body['rate_mappings'], [
          {
            'rate_plan_id': 'plan1',
            'channex_room_type_id': 'remote-room',
            'channex_rate_plan_id': 'remote-rate',
          },
        ]);
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        a.dispose();
      }
    },
  );
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'integration status and ARI controls fit $width without implying production',
      (t) async {
        t.view.physicalSize = Size(width, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final pms = ChannelPms();
        final a = await signedIn(pms),
            c = PmsController(a, initialPage: PmsPage.integrations);
        try {
          await c.load();
          await t.pumpWidget(host(IntegrationsPage(c: c)));
          await t.pumpAndSettle();
          expect(
            find.textContaining('transmission remains locked'),
            findsOneWidget,
          );
          expect(
            t
                .widget<PmsButton>(
                  find.widgetWithText(PmsButton, 'Check bookings'),
                )
                .onPressed,
            isNull,
          );
          await t.pumpWidget(
            host(
              DistributionDialog(
                api: ChannelApi(c, 'i1'),
                propertyName: 'Test House',
                today: DateTime(2032, 5, 10),
              ),
            ),
          );
          await t.pumpAndSettle();
          await press(t, 'Refresh queue');
          await press(t, 'Retry pending now');
          expect(pms.mutationCount, 1);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          c.dispose();
          a.dispose();
        }
      },
    );
  }
  testWidgets(
    'sandbox accepted mutation followed by failed read locks further writes',
    (t) async {
      final pms = ChannelPms();
      final a = await signedIn(pms), c = PmsController(a);
      try {
        await t.pumpWidget(
          host(
            SandboxDialog(
              api: ChannelApi(c, 'i1'),
              today: DateTime(2032, 5, 10),
            ),
          ),
        );
        await t.pumpAndSettle();
        pms.failFeed = true;
        await press(t, 'Simulate outage');
        expect(pms.mutationCount, 1);
        expect(find.textContaining('server accepted'), findsOneWidget);
        expect(
          t
              .widget<PmsButton>(
                find.widgetWithText(PmsButton, 'Simulate outage'),
              )
              .onPressed,
          isNull,
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        a.dispose();
      }
    },
  );
  testWidgets('preview does not import until Apply import is selected', (
    t,
  ) async {
    final pms = ChannelPms();
    final a = await signedIn(pms), c = PmsController(a);
    try {
      await t.pumpWidget(host(SyncPreviewDialog(api: ChannelApi(c, 'i1'))));
      await t.pumpAndSettle();
      expect(pms.mutationCount, 0);
      await press(t, 'Apply import');
      expect(pms.mutationCount, 1);
      expect(find.text('Import complete'), findsOneWidget);
      expect(find.text('Apply import'), findsNothing);
    } finally {
      await t.pumpWidget(const SizedBox());
      c.dispose();
      a.dispose();
    }
  });
  testWidgets(
    'rate creation preserves room ownership and integer HUF; guest preference is persisted',
    (t) async {
      final pms = ChannelPms();
      final a = await signedIn(pms), c = PmsController(a);
      try {
        await t.pumpWidget(
          host(RatePlanEditor(c: c, propertyId: 'p1', rooms: pms.roomTypes)),
        );
        await t.pumpAndSettle();
        await enter(t, 'Name', 'Synthetic plan');
        await enter(t, 'Base rate · HUF', '9007199254740993');
        await press(t, 'Create rate plan');
        final body = pms.requests.last.body as Map;
        expect(body['room_type_id'], 'room1');
        expect(body['base_rate_huf'], 9007199254740993);
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(
          host(GuestPreferenceDialog(api: PmsWorkflows(c), id: 'g1')),
        );
        await t.pumpAndSettle();
        await enter(t, 'Key', 'pillow_preference');
        await enter(t, 'Preferences', 'Extra pillow');
        await press(t, 'Save');
        expect(pms.requests.last.path, '/api/guests/g1/preferences');
        expect(
          (pms.requests.last.body as Map)['preference_value'],
          'Extra pillow',
        );
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        a.dispose();
      }
    },
  );
  testWidgets(
    'Ctrl K opens existing search without resetting the operational page',
    (t) async {
      final pms = ChannelPms();
      final a = await signedIn(pms);
      try {
        await t.pumpWidget(
          MaterialApp(
            home: PmsShell(auth: a, initialPage: PmsPage.today),
          ),
        );
        await t.pumpAndSettle();
        await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await t.sendKeyEvent(LogicalKeyboardKey.keyK);
        await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsOneWidget);
      } finally {
        await t.pumpWidget(const SizedBox());
        a.dispose();
      }
    },
  );
}
