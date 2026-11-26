import 'package:delvane_business/core/localization/web_strings.dart';
import 'package:delvane_business/features/pms/operational_visuals.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> show(WidgetTester tester, Widget child, double width) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
  }

  testWidgets('metrics wrap on phones and share a baseline on desktop', (
    tester,
  ) async {
    const rail = MetricRail(
      metrics: [
        ('Arrivals', '12'),
        ('Departures', '5'),
        ('Turnovers', '21'),
        ('Registration issues', '—'),
      ],
    );
    await show(tester, rail, 320);
    expect(
      tester.getTopLeft(find.text('12')).dy,
      tester.getTopLeft(find.text('5')).dy,
    );
    expect(
      tester.getTopLeft(find.text('21')).dy,
      greaterThan(tester.getTopLeft(find.text('12')).dy),
    );
    expect(find.text('—'), findsOneWidget);
    await show(tester, rail, 720);
    expect(
      tester.getTopLeft(find.text('21')).dy,
      tester.getTopLeft(find.text('12')).dy,
    );
  });

  testWidgets(
    'checklist progress updates from counts and translates to Hungarian',
    (tester) async {
      final strings = WebStrings.current;
      final language = strings.language;
      await strings.load();
      strings.language = 'hu';
      addTearDown(() => strings.language = language);
      await show(tester, const WorkProgress(completed: 1, total: 3), 320);
      expect(find.text('1 / 3 kész'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        closeTo(1 / 3, .001),
      );
      await show(tester, const WorkProgress(completed: 0, total: 0), 320);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    },
  );

  testWidgets('room strip counts only supplied rooms and explains each state', (
    tester,
  ) async {
    final strings = WebStrings.current;
    final language = strings.language;
    strings.language = 'en';
    addTearDown(() => strings.language = language);
    await show(
      tester,
      const ReadinessStrip(
        states: [
          'ready',
          'ready',
          'occupied',
          'waiting_for_checkout',
          'cleaning',
          'unknown',
        ],
      ),
      320,
    );
    expect(find.text('2 · Ready'), findsOneWidget);
    expect(find.text('1 · Occupied'), findsOneWidget);
    expect(find.text('1 · Waiting for actual checkout'), findsOneWidget);
    expect(find.text('1 · Room unavailable'), findsOneWidget);
    expect(find.text('1 · Cleaning pending'), findsOneWidget);
    expect(
      ReadinessStrip.mark('cleaning').$2,
      isNot(ReadinessStrip.mark('waiting_for_checkout').$2),
    );
    await show(tester, const ReadinessStrip(states: []), 320);
    expect(find.textContaining('Ready'), findsNothing);
  });

  testWidgets(
    'timeline keeps the corresponding action accessible from its row',
    (tester) async {
      var opened = false;
      await show(
        tester,
        TimelineEntry(
          time: '14:00',
          title: 'Room 104',
          detail: 'Arrival',
          onTap: () => opened = true,
        ),
        320,
      );
      await tester.tap(find.text('Room 104'));
      expect(opened, isTrue);
    },
  );
}
