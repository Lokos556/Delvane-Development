import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/intelligence_workspace.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_style.dart';

import 'support/fake_pms.dart';

class ChatPms extends FakePms {
  final history = <Map<String, dynamic>>[];
  final pending = <Completer<ApiResponse>>[];
  Completer<ApiResponse>? historyReply;
  ChatPms({int oldTurns = 12}) {
    for (var i = 0; i < oldTurns; i++) {
      history.addAll([
        {'id': 'u$i', 'role': 'user', 'content': 'Earlier question $i'},
        {
          'id': 'a$i',
          'role': 'rosa',
          'content': 'Earlier answer $i · Fictional PMS facts.',
        },
      ]);
    }
  }
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
      final completion = Completer<ApiResponse>();
      pending.add(completion);
      return completion.future;
    }
    if (uri.path == '/api/rosa/conversation') {
      if (historyReply != null) return historyReply!.future;
      overrides[uri.path] = snapshot();
    }
    if (uri.path == '/api/intelligence' || uri.path == '/api/rosa/provider') {
      overrides[uri.path] = json(<String, dynamic>{});
    }
    if (uri.path == '/api/organization') {
      overrides[uri.path] = json({'operating_mode': 'observe'});
    }
    if (uri.path == '/api/notifications') {
      overrides[uri.path] = json({'unread': 0});
    }
    return super.request(method, uri, headers, body);
  }

  ApiResponse snapshot() => json({
    'conversation': {'id': 'thread'},
    'messages': history,
  });
  void finish(String answer, {bool fail = false}) {
    if (fail) {
      pending.last.complete(json({}, 503));
      return;
    }
    final request =
        requests.lastWhere((r) => r.path == '/api/rosa/chat').body as Map;
    final id = request['client_request_id'];
    history.addAll([
      {
        'id': 'user-$id',
        'role': 'user',
        'content': request['message'],
        'metadata': {'client_request_id': id},
      },
      {
        'id': 'answer-$id',
        'role': 'rosa',
        'content': answer,
        'metadata': {'client_request_id': id, 'read_only': true},
      },
    ]);
    pending.last.complete(
      json({
        'answer': answer,
        'conversation_id': 'thread',
        'read_only': true,
        'user_message_id': 'user-$id',
        'assistant_message_id': 'answer-$id',
      }),
    );
  }
}

Future<void> host(
  WidgetTester t,
  ChatPms pms, {
  String language = 'en',
  bool reducedMotion = true,
}) async {
  t.view.physicalSize = const Size(393, 852);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final auth = await signedIn(pms);
  await WebStrings.current.load();
  WebStrings.current.language = language;
  addTearDown(() async {
    await t.pumpWidget(const SizedBox());
    auth.dispose();
    WebStrings.current.language = 'en';
  });
  await t.pumpWidget(
    MaterialApp(
      theme: pmsTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
        child: child!,
      ),
      home: PmsShell(auth: auth, initialPage: PmsPage.intelligence),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> submit(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const ValueKey('intelligence-composer')), text);
  await t.testTextInput.receiveAction(TextInputAction.send);
  await t.pumpAndSettle();
}

Finder list() => find.byKey(const PageStorageKey('delvane-conversation'));

void main() {
  testWidgets(
    'optimistic insertion keeps the same chat and scrolls question/indicator into view',
    (t) async {
      final pms = ChatPms();
      await host(t, pms);
      final before = t.state(find.byType(IntelligenceWorkspace));
      final gets = pms.requests
          .where((r) => r.path == '/api/rosa/conversation')
          .length;
      await submit(t, 'Melyik apartmanok nem állnak készen?');
      final chat = t
          .widget<IntelligenceWorkspace>(find.byType(IntelligenceWorkspace))
          .c
          .chat;
      expect(chat.messages.length, 25);
      expect(
        t
            .widget<TextField>(
              find.byKey(const ValueKey('intelligence-composer')),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(chat.messages.first.content, 'Earlier question 0');
      expect(find.text('Melyik apartmanok nem állnak készen?'), findsOneWidget);
      expect(find.text('Delvane is responding…'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Delvane is responding…')).dy,
        lessThan(
          t.getTopLeft(find.byKey(const ValueKey('intelligence-composer'))).dy,
        ),
      );
      expect(
        identical(before, t.state(find.byType(IntelligenceWorkspace))),
        isTrue,
      );
      expect(
        pms.requests.where((r) => r.path == '/api/rosa/conversation').length,
        gets,
      );
      // Send is disabled while one request is outstanding.
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pump();
      expect(pms.pending.length, 1);
      pms.finish('Current PMS answer.');
      await t.pumpAndSettle();
      expect(find.text('Current PMS answer.'), findsOneWidget);
      expect(find.byType(ChatThinkingIndicator), findsNothing);
      expect(
        identical(before, t.state(find.byType(IntelligenceWorkspace))),
        isTrue,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('long answer is positioned at its beginning rather than its end', (
    t,
  ) async {
    final pms = ChatPms();
    await host(t, pms);
    await submit(t, 'Summarize upcoming reservations.');
    final answer =
        'BEGINNING OF ANSWER\n${List.generate(70, (i) => 'Fictional detail $i').join('\n')}\nEND OF ANSWER';
    pms.finish(answer);
    await t.pumpAndSettle();
    final top = t.getTopLeft(find.text(answer)).dy;
    expect(top, greaterThanOrEqualTo(t.getTopLeft(list()).dy));
    expect(top, lessThan(t.getTopLeft(list()).dy + 80));
    final scroll = t.widget<CustomScrollView>(list()).controller!;
    expect(scroll.position.extentAfter, greaterThan(300));
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'reading older messages suppresses response scroll until Jump to latest',
    (t) async {
      final pms = ChatPms();
      await host(t, pms);
      await submit(t, 'Who arrives tomorrow?');
      await t.drag(list(), const Offset(0, 240));
      await t.pumpAndSettle();
      final c = t
          .widget<IntelligenceWorkspace>(find.byType(IntelligenceWorkspace))
          .c;
      expect(c.chat.followLatest, isFalse);
      final scroll = t.widget<CustomScrollView>(list()).controller!;
      final offset = scroll.offset;
      pms.finish('A newly retrieved answer.');
      await t.pumpAndSettle();
      expect(scroll.offset, closeTo(offset, .5));
      expect(find.byKey(const ValueKey('chat-jump-latest')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('chat-jump-latest')));
      await t.pumpAndSettle();
      expect(c.chat.followLatest, isTrue);
      expect(find.text('A newly retrieved answer.'), findsOneWidget);
    },
  );

  for (final language in ['en', 'hu']) {
    testWidgets(
      '$language localized failure/retry retains one turn and its retry ID',
      (t) async {
        final pms = ChatPms(oldTurns: 0);
        await host(t, pms, language: language);
        await submit(t, 'Hány foglalásom van?');
        expect(find.text(ui('Delvane is responding…')), findsOneWidget);
        pms.finish('', fail: true);
        await t.pumpAndSettle();
        expect(find.text(ui("Couldn't send. Try again.")), findsOneWidget);
        expect(find.text('Hány foglalásom van?'), findsWidgets);
        await t.tap(find.byKey(const ValueKey('chat-retry')));
        await t.pumpAndSettle();
        final sent = pms.requests
            .where((r) => r.path == '/api/rosa/chat')
            .toList();
        expect(
          (sent[0].body as Map)['client_request_id'],
          (sent[1].body as Map)['client_request_id'],
        );
        final c = t
            .widget<IntelligenceWorkspace>(find.byType(IntelligenceWorkspace))
            .c;
        expect(c.chat.messages.where((m) => m.role == 'user').length, 1);
        pms.finish('Visszaigazolt PMS-adatok.');
        await t.pumpAndSettle();
        expect(c.chat.messages.length, 2);
        final viewport = find
            .ancestor(of: list(), matching: find.byType(Stack))
            .first;
        expect(
          t.getBottomRight(list()).dy,
          closeTo(t.getBottomRight(viewport).dy, 1),
        );
        expect(t.getTopLeft(list()).dy, greaterThan(t.getTopLeft(viewport).dy));
        expect(find.byKey(const ValueKey('chat-retry')), findsNothing);
        expect(
          t
              .widget<TextField>(
                find.byKey(const ValueKey('intelligence-composer')),
              )
              .controller!
              .text,
          isEmpty,
        );
      },
    );
  }

  testWidgets(
    'background history refresh retains the widget and messages, including on failure',
    (t) async {
      final pms = ChatPms(oldTurns: 1);
      await host(t, pms);
      final widgetBefore = t.state(find.byType(IntelligenceWorkspace));
      final c = t
          .widget<IntelligenceWorkspace>(find.byType(IntelligenceWorkspace))
          .c;
      pms.historyReply = Completer<ApiResponse>();
      final refresh = c.load();
      await t.pump();
      expect(c.loading, isFalse);
      expect(find.text('Earlier question 0'), findsOneWidget);
      expect(
        identical(widgetBefore, t.state(find.byType(IntelligenceWorkspace))),
        isTrue,
      );
      pms.historyReply!.complete(pms.json({}, 503));
      await refresh;
      await t.pumpAndSettle();
      expect(find.text('Earlier question 0'), findsOneWidget);
      expect(
        identical(widgetBefore, t.state(find.byType(IntelligenceWorkspace))),
        isTrue,
      );
      expect(c.error, isNull);
      expect(c.chatRefreshError, isNotNull);
    },
  );

  testWidgets(
    'IME/safe-area layout keeps composer visible during a pending turn',
    (t) async {
      final pms = ChatPms(oldTurns: 1);
      await host(t, pms);
      await submit(t, 'Árvíztűrő kérdés');
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await t.pumpAndSettle();
      expect(
        t
            .getBottomRight(find.byKey(const ValueKey('intelligence-composer')))
            .dy,
        lessThanOrEqualTo(552),
      );
      expect(find.text('Delvane is responding…'), findsOneWidget);
      pms.finish('Őrzött Unicode-válasz.');
      await t.pumpAndSettle();
      t.view.viewInsets = const FakeViewPadding();
      await t.pumpAndSettle();
      expect(find.text('Őrzött Unicode-válasz.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'an actual pending indicator animates and disappears on completion',
    (t) async {
      final pms = ChatPms(oldTurns: 0);
      await host(t, pms, reducedMotion: false);
      await t.enterText(
        find.byKey(const ValueKey('intelligence-composer')),
        'Question',
      );
      await t.testTextInput.receiveAction(TextInputAction.send);
      await t.pump();
      final fade = find.descendant(
        of: find.byType(ChatThinkingIndicator),
        matching: find.byType(FadeTransition),
      );
      final before = t.widget<FadeTransition>(fade).opacity.value;
      await t.pump(const Duration(milliseconds: 250));
      expect(t.widget<FadeTransition>(fade).opacity.value, isNot(before));
      pms.finish('Complete response, shown at once.');
      await t.pumpAndSettle();
      expect(find.byType(ChatThinkingIndicator), findsNothing);
      expect(find.text('Complete response, shown at once.'), findsOneWidget);
    },
  );

  testWidgets(
    'navigation during a request keeps its result and stable message IDs',
    (t) async {
      final pms = ChatPms(oldTurns: 0);
      await host(t, pms);
      await submit(t, 'Who arrives tomorrow?');
      final c = t
          .widget<IntelligenceWorkspace>(find.byType(IntelligenceWorkspace))
          .c;
      final userId = c.chat.messages.single.id;
      await c.navigate(PmsPage.today);
      await t.pumpAndSettle();
      expect(find.byType(IntelligenceWorkspace), findsNothing);
      pms.finish('Saved while away.');
      await t.pumpAndSettle();
      await c.navigate(PmsPage.intelligence);
      await t.pumpAndSettle();
      expect(c.chat.messages.length, 2);
      expect(c.chat.messages.first.id, userId);
      expect(find.text('Saved while away.'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'permission loss clears cached private chat instead of retaining it',
    (t) async {
      final pms = ChatPms(oldTurns: 1);
      await host(t, pms);
      final c = t
          .widget<IntelligenceWorkspace>(find.byType(IntelligenceWorkspace))
          .c;
      pms.role = 'cleaner';
      await c.load();
      await t.pumpAndSettle();
      expect(c.chat.messages, isEmpty);
      expect(find.byType(IntelligenceWorkspace), findsNothing);
      expect(find.text('Earlier question 0'), findsNothing);
    },
  );
  testWidgets('an immediate long response never jumps past its beginning', (
    t,
  ) async {
    final pms = ChatPms(oldTurns: 40);
    await host(t, pms);
    await t.enterText(
      find.byKey(const ValueKey('intelligence-composer')),
      'Question',
    );
    await t.testTextInput.receiveAction(TextInputAction.send);
    final answer =
        'BEGIN\n${List.generate(80, (i) => 'Fictional line $i').join('\n')}\nEND';
    pms.finish(answer);
    for (var frame = 0; frame < 10; frame++) {
      await t.pump(const Duration(milliseconds: 20));
      if (find.text(answer).evaluate().isNotEmpty) {
        final viewport = find
            .ancestor(of: list(), matching: find.byType(Stack))
            .first;
        expect(
          t.getTopLeft(find.text(answer)).dy,
          greaterThanOrEqualTo(t.getTopLeft(viewport).dy),
        );
      }
    }
    await t.pumpAndSettle();
    expect(
      t.getTopLeft(find.text(answer)).dy,
      lessThan(t.getTopLeft(list()).dy + 80),
    );
  });
}
