import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/features/pms/assistant_prompts.dart';
import 'package:delvane_business/features/pms/intelligence_workspace.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/section_picker.dart';

import 'support/fake_pms.dart';

const samples = [
  'Melyik apartmanok nem állnak készen?',
  'Hány foglalásom van összesen?',
  'Mikor érkezik a következő vendég?',
  'Ősszel hány vendégünk érkezett?',
  'Árvíztűrő tükörfúrógép',
  'áéíóöőúüű ÁÉÍÓÖŐÚÜŰ · Straße français Łódź · e\u0301 · 👩‍💻',
];

void main() {
  for (final language in ['hu', 'en']) {
    testWidgets(
      '$language suggestions insert and submit their displayed text',
      (tester) async {
        final pms = FakePms();
        pms.overrides['/api/organization'] = pms.json({
          'operating_mode': 'observe',
        });
        pms.overrides['/api/notifications'] = pms.json({'unread': 0});
        final auth = await signedIn(pms);
        final c = PmsController(auth, initialPage: PmsPage.intelligence);
        final input = TextEditingController();
        await c.strings.load();
        c.strings.language = language;
        final conversation = <String, dynamic>{
          'conversation': {'id': 'unicode-thread'},
          'messages': [],
        };
        pms.overrides['/api/rosa/chat'] = pms.json({
          'answer': 'PMS reply',
          'conversation_id': 'unicode-thread',
          'read_only': true,
        });
        pms.overrides['/api/rosa/conversation'] = pms.json(conversation);
        pms.overrides['/api/intelligence'] = pms.json({});
        pms.overrides['/api/rosa/provider'] = pms.json({});
        c.data.addAll({
          'conversation': conversation,
          'intelligence': <String, dynamic>{},
          'provider': <String, dynamic>{},
        });
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: pmsTheme(),
              home: Scaffold(
                body: AnimatedBuilder(
                  animation: c,
                  builder: (context, _) => !c.data.containsKey('intelligence')
                      ? const CircularProgressIndicator()
                      : IntelligenceWorkspace(
                          c: c,
                          input: input,
                          openSearch: () {},
                        ),
                ),
              ),
            ),
          );
          for (final prompt in ownerAssistantPrompts) {
            final localized = prompt.text(c.strings);
            if (language == 'hu') expect(localized, isNot(prompt.english));
            await tester.tap(find.text(c.t('TRY ASKING')));
            await tester.pumpAndSettle();
            expect(find.text(localized), findsOneWidget);
            await tester.tap(find.text(localized));
            await tester.pumpAndSettle();
            expect(input.text, localized);
            expect(input.selection.baseOffset, localized.length);
            await tester.testTextInput.receiveAction(TextInputAction.send);
            await tester.pumpAndSettle();
            final request = pms.requests
                .where((r) => r.path == '/api/rosa/chat')
                .last;
            expect((request.body as Map)['message'], localized);
            expect((request.body as Map)['language'], language);
          }
          // Rebuild the same screen with a new language without altering the draft.
          input.text = samples.first;
          c.strings.language = language == 'hu' ? 'en' : 'hu';
          c.emit();
          await tester.pumpAndSettle();
          expect(input.text, samples.first);
          final picker = tester.widget<PmsSectionPicker>(
            find.byType(PmsSectionPicker),
          );
          expect(picker.labels, [
            for (final p in ownerAssistantPrompts) p.text(c.strings),
          ]);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          input.dispose();
          c.dispose();
          auth.dispose();
          WebStrings.current.language = 'en';
        }
      },
    );
  }

  testWidgets(
    'IME composition, typing and clipboard paste preserve all Unicode',
    (tester) async {
      final pms = FakePms();
      pms.overrides['/api/organization'] = pms.json({
        'operating_mode': 'observe',
      });
      pms.overrides['/api/notifications'] = pms.json({'unread': 0});
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.intelligence);
      final input = TextEditingController();
      c.data.addAll({
        'conversation': {'messages': []},
        'intelligence': <String, dynamic>{},
        'provider': <String, dynamic>{},
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IntelligenceWorkspace(
                c: c,
                input: input,
                openSearch: () {},
              ),
            ),
          ),
        );
        final composer = find.byKey(const ValueKey('intelligence-composer'));
        await tester.tap(composer);
        for (final sample in samples) {
          await tester.enterText(composer, '');
          var typed = '';
          for (final rune in sample.runes) {
            typed += String.fromCharCode(rune);
            tester.testTextInput.updateEditingValue(
              TextEditingValue(
                text: typed,
                selection: TextSelection.collapsed(offset: typed.length),
              ),
            );
            await tester.pump();
            expect(input.text, typed);
          }
        }
        const composing = TextEditingValue(
          text: 'Árvíztűrő',
          selection: TextSelection.collapsed(offset: 9),
          composing: TextRange(start: 0, end: 9),
        );
        tester.testTextInput.updateEditingValue(composing);
        await tester.pump();
        expect(input.value, composing);
        tester.testTextInput.updateEditingValue(
          composing.copyWith(composing: TextRange.empty),
        );
        await tester.pump();
        expect(input.text, composing.text);
        const pasted = 'Ősszel ÁÉÍÓÖŐÚÜŰ · Łódź français e\u0301 👩‍💻';
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async =>
              call.method == 'Clipboard.getData' ? {'text': pasted} : null,
        );
        try {
          await tester.enterText(composer, '');
          final editable = tester.state<EditableTextState>(
            find.byType(EditableText),
          );
          await editable.pasteText(SelectionChangedCause.toolbar);
          await tester.pump();
          expect(input.text, pasted);
        } finally {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        }
        pms.overrides['/api/rosa/chat'] = pms.json({
          'answer': 'PMS reply',
          'conversation_id': 'unicode-thread',
          'read_only': true,
        });
        pms.overrides['/api/intelligence'] = pms.json(<String, dynamic>{});
        pms.overrides['/api/rosa/provider'] = pms.json(<String, dynamic>{});
        pms.overrides['/api/rosa/conversation'] = pms.json({
          'conversation': {'id': 'restored-unicode'},
          'messages': [
            {'role': 'user', 'content': pasted},
          ],
        });
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
        expect(
          (pms.requests.lastWhere((r) => r.path == '/api/rosa/chat').body
              as Map)['message'],
          pasted,
        );
        // Reopening renders the exact Unicode content returned by history.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: IntelligenceWorkspace(
                c: c,
                input: input,
                openSearch: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(pasted), findsOneWidget);
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
