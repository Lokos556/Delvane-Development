import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/section_picker.dart';

void main() {
  tearDown(() => WebStrings.current.language = 'en');

  testWidgets(
    'required labels, optional validation and conditional indicators',
    (tester) async {
      WebStrings.current.language = 'en';
      final controller = TextEditingController();
      final form = GlobalKey<FormState>();
      addTearDown(controller.dispose);
      Future<void> show(bool required) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PmsForm(
              formKey: form,
              showRequiredNote: required,
              child: Column(
                children: [
                  PmsField('Name', controller: controller, required: required),
                  PmsSelect(
                    'Property',
                    value: 'p',
                    items: const {'p': 'Fictional property'},
                    required: required,
                    onChanged: (_) {},
                  ),
                  PmsField('Email', controller: controller),
                ],
              ),
            ),
          ),
        ),
      );
      await show(true);
      expect(find.text('Name *'), findsOneWidget);
      expect(find.text('Property *'), findsOneWidget);
      expect(find.text('Email *'), findsNothing);
      expect(find.text('Fields marked with * are required.'), findsOneWidget);
      expect(form.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.text('Required'), findsOneWidget);
      await show(false);
      await tester.pump();
      expect(find.text('Name *'), findsNothing);
      expect(find.text('Property *'), findsNothing);
      expect(find.byType(PmsRequiredNote), findsNothing);
      expect(form.currentState!.validate(), isTrue);
    },
  );

  testWidgets('Hungarian and English required explanation', (tester) async {
    await WebStrings.current.load();
    WebStrings.current.language = 'hu';
    await tester.pumpWidget(const MaterialApp(home: PmsRequiredNote()));
    expect(
      find.text('A *-gal jelölt mezők kitöltése kötelező.'),
      findsOneWidget,
    );
    WebStrings.current.language = 'en';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PmsRequiredNote())),
    );
    expect(find.text('Fields marked with * are required.'), findsOneWidget);
  });

  for (final width in [280.0, 320.0, 393.0, 1440.0]) {
    testWidgets('section selection survives dismissal and resize at $width', (
      tester,
    ) async {
      var selected = 0;
      late StateSetter update;

      await tester.binding.setSurfaceSize(Size(width, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return PmsTabs(
                  labels: const [
                    'Stay Overview',
                    'Preparation',
                    'Communication',
                    'Activity',
                  ],
                  selected: selected,
                  onChanged: (i) => setState(() => selected = i),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (find.text('Activity').evaluate().isEmpty) {
        await tester.tap(find.text('Stay Overview'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Activity').last);
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.selected == true,
        ),
        findsWidgets,
      );
      expect(find.text('Activity'), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(320, 800));
      update(() {});
      await tester.pumpAndSettle();
      expect(find.text('Activity'), findsOneWidget);
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Communication'), findsOneWidget);
      // Escape dismisses without changing the current section.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(selected, 3);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byTooltip('Scroll forward'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('large text wraps picker and all destinations stay reachable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PmsSectionPicker(
              labels: const [
                'A long localized section name',
                'Another destination',
              ],
              selected: selected,
              onChanged: (i) => setState(() => selected = i),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('A long localized section name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Another destination'));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });
}
