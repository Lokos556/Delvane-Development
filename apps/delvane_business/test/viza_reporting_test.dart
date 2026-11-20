import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/viza_reporting_dialog.dart';

import 'support/fake_pms.dart';

const path = '/api/government/viza/properties/p1';
Map<String, dynamic> model({bool mock = false, String state = 'uncertain'}) => {
  'official_transmission_enabled': false,
  'configuration': null,
  'security_blockers': [
    'official_transmission_disabled',
    'Q2_outer_ws_security_unresolved',
  ],
  'health': {
    'state': mock ? 'stale' : 'unknown',
    'mode': mock ? 'mock' : 'disabled',
    'primary': mock ? 'WARNING' : null,
    'flags': mock ? ['VIZA-OFFLINE', 'CERT-WARNING'] : [],
    'unsent': mock ? 4 : null,
    'rejected': mock ? 2 : null,
  },
  'jobs': [
    {
      'id': 'message-fictional',
      'event_id': 'event-fictional',
      'kind': 'arrival',
      'state': state,
      'mode': mock ? 'mock' : 'disabled',
      'attempts': state == 'blocked' ? 0 : 1,
      'blockers': ['official_transmission_disabled'],
      'can_refresh_identity': state == 'blocked',
      'can_retry_not_sent': state == 'retry',
      'error_code': state == 'uncertain' ? 'outcome_unknown' : null,
      'guests': [
        {
          'guest_id': 'g1',
          'arrival_uuid': '00000000-0000-0000-0000-000000000001',
          'state': state,
          'downstream_state': 'unknown',
          'errors': [
            {
              'code': 'EF0034',
              'message_en': 'Manual family name is missing.',
              'message_hu': 'A csal\u00e1dn\u00e9v hi\u00e1nyzik.',
            },
          ],
        },
      ],
    },
  ],
  'actions': [],
  'lists': {},
  'schedules': [],
};

class DelayedVizaPms extends FakePms {
  final pending = Completer<ApiResponse>();
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    if (uri.path.endsWith('/recover')) {
      requests.add((
        method: method,
        path: uri.path,
        headers: Map.of(headers),
        body: body,
      ));
      return pending.future;
    }
    return super.request(method, uri, headers, body);
  }
}

void main() {
  for (final width in [390.0, 1200.0]) {
    for (final lang in ['en', 'hu']) {
      for (final mock in [false, true]) {
        testWidgets('VIZA administration states $width $lang mock=$mock', (
          tester,
        ) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final fake = FakePms();
          final auth = await signedIn(fake);
          final c = PmsController(auth);
          await c.strings.load();
          c.strings.language = lang;
          fake.overrides[path] = ApiResponse(
            200,
            jsonEncode(model(mock: mock)),
          );
          fake.overrides['$path/observe'] = const ApiResponse(
            200,
            '{"state":"blocked","code":"official_transmission_disabled"}',
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: pmsTheme(),
              home: Scaffold(
                body: VizaReportingDialog(
                  c: c,
                  propertyId: 'p1',
                  propertyName: 'Fictional House',
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(ui('VIZA configuration is missing.')),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              ui(
                mock
                    ? 'Local mock observation; no official connection or acceptance'
                    : 'THF connection has not been verified',
              ),
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              '${ui('THF unsent messages')}: ${mock ? 4 : "—"}',
            ),
            findsOneWidget,
          );
          if (lang == 'hu') {
            expect(ui('VIZA reporting'), 'VIZA adatszolg\u00e1ltat\u00e1s');
          }
          final observe = find.text(ui('Request THF observation'));
          await tester.ensureVisible(observe);
          await tester.tap(observe);
          await tester.pumpAndSettle();
          expect(
            fake.requests.where(
              (r) => r.method == 'POST' && r.path == '$path/observe',
            ),
            hasLength(1),
          );
          expect(
            find.text(ui('Reschedule definitely-not-sent work')),
            findsNothing,
          );
          expect(
            find.text(ui('Refresh never-sent identity facts')),
            findsNothing,
          );
          expect(fake.requests.any((r) => r.path.contains('/recover')), false);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          auth.dispose();
        });
      }
    }
  }
  testWidgets(
    'VIZA recovery stays disabled during a request and errors do not trigger replay',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = DelayedVizaPms();
      final auth = await signedIn(fake);
      final c = PmsController(auth);
      c.strings.language = 'en';
      fake.overrides[path] = ApiResponse(
        200,
        jsonEncode(model(mock: true, state: 'retry')),
      );
      final pending = fake.pending;
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: Scaffold(
            body: VizaReportingDialog(
              c: c,
              propertyId: 'p1',
              propertyName: 'Fictional House',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.text(ui('Reschedule definitely-not-sent work'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pump();
      final button = tester.widget<PmsButton>(
        find.ancestor(of: action, matching: find.byType(PmsButton)),
      );
      expect(button.onPressed, isNull);
      expect(
        fake.requests.where((r) => r.path.endsWith('/recover')),
        hasLength(1),
      );
      pending.complete(const ApiResponse(409, '{"detail":"Outcome unknown"}'));
      await tester.pumpAndSettle();
      expect(
        fake.requests.where((r) => r.path.endsWith('/recover')),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      auth.dispose();
    },
  );
  testWidgets('stored-list paging resets to fresh observation on refresh', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fake = FakePms();
    final auth = await signedIn(fake);
    final c = PmsController(auth);
    c.strings.language = 'en';
    final initial = model(mock: true);
    initial['jobs'] = [];
    initial['lists'] = {
      'HIBAS': {
        'mode': 'mock',
        'offset': 0,
        'total': 200,
        'items': [
          {
            'message_id': 'Fictional first page',
            'correlation': 'matched',
            'codes': [],
          },
        ],
        'limit_reached': false,
      },
    };
    fake.overrides[path] = ApiResponse(200, jsonEncode(initial));
    fake.overrides['$path/lists/HIBAS'] = const ApiResponse(
      200,
      '{"mode":"mock","offset":100,"total":200,"items":[{"message_id":"Fictional second page","correlation":"matched","codes":[]}],"limit_reached":false}',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: pmsTheme(),
        home: Scaffold(
          body: VizaReportingDialog(
            c: c,
            propertyId: 'p1',
            propertyName: 'Fictional House',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final next = find.text(ui('Next list page'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.textContaining('Fictional second page'), findsOneWidget);
    final refresh = find.text(ui('Refresh'));
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(find.textContaining('Fictional first page'), findsOneWidget);
    expect(find.textContaining('Fictional second page'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    auth.dispose();
  });
}
