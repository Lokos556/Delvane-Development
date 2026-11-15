import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/intelligence_workspace.dart';
import 'package:delvane_business/features/pms/pms_style.dart';

import 'support/fake_pms.dart';

class WaitingAssistant extends FakePms {
  final reply = Completer<ApiResponse>();
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    if (uri.path == '/api/rosa/chat') {
      requests.add((
        method: method,
        path: uri.path,
        headers: headers,
        body: body,
      ));
      return reply.future;
    }
    return super.request(method, uri, headers, body);
  }
}

void main() {
  testWidgets(
    'existing conversation, loading, safe failure and retained input',
    (tester) async {
      tester.view.physicalSize = const Size(393, 852);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pms = WaitingAssistant();
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.intelligence);
      final input = TextEditingController();
      c.strings.language = 'en';
      c.data['intelligence'] = <String, dynamic>{};
      c.data['provider'] = <String, dynamic>{};
      c.data['conversation'] = {
        'conversation': {'id': 'existing-conversation'},
        'messages': [
          {
            'role': 'rosa',
            'content': 'Confirmed arrivals: 2.',
            'metadata': {'read_only': true},
          },
        ],
        // Older stored proposals must never expose executable chat buttons.
        'proposals': [
          {
            'id': 'old',
            'status': 'awaiting_approval',
            'summary': 'Move cleaning',
          },
        ],
      };
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: pmsTheme(),
            home: Scaffold(
              body: AnimatedBuilder(
                animation: c,
                builder: (context, _) => IntelligenceWorkspace(
                  c: c,
                  input: input,
                  openSearch: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Source: accessible PMS records · Read-only'),
          findsOneWidget,
        );
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Decline'), findsNothing);
        final composer = find.byKey(const ValueKey('intelligence-composer'));
        await tester.enterText(composer, 'Who is arriving tomorrow?');
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();
        expect(find.text('Checking your PMS records…'), findsOneWidget);
        final request = pms.requests.singleWhere(
          (r) => r.path == '/api/rosa/chat',
        );
        expect(
          (request.body as Map)['conversation_id'],
          'existing-conversation',
        );
        expect((request.body as Map)['language'], 'en');
        expect(request.headers['X-Rosa-CSRF'], fakeCsrf);
        pms.reply.complete(pms.json({'detail': 'PRIVATE PROVIDER TRACE'}, 503));
        await tester.pumpAndSettle();
        expect(input.text, 'Who is arriving tomorrow?');
        expect(c.actionError, isNotNull);
        expect(c.actionError, isNot(contains('PRIVATE PROVIDER TRACE')));
        expect(find.text('Checking your PMS records…'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        input.dispose();
        c.dispose();
        auth.dispose();
      }
    },
  );
}
