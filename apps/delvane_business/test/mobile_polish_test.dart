import 'dart:io';
import 'dart:ui' as raster;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_icons.dart';
import 'package:delvane_business/features/pms/booking_calendar.dart';

import 'android_readiness_test.dart' show phone, androidFixture;
import 'support/fake_pms.dart';
import 'support/visual_fonts.dart';

Widget host(Widget child, {TargetPlatform platform = TargetPlatform.android}) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: pmsTheme().copyWith(platform: platform),
      locale: Locale(WebStrings.current.language),
      supportedLocales: const [Locale('hu'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: child,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await WebStrings.current.load();
    WebStrings.current.language = 'hu';
  });
  tearDown(() => WebStrings.current.language = 'en');

  test(
    'Hungarian templates preserve captures, braces and wire identifiers',
    () {
      expect(
        ui('Cancel Jane {1} Smith\'s reservation?'),
        'Lemondod a következő vendég foglalását: Jane {1} Smith?',
      );
      expect(ui('2 of 5 configured'), '5 közül 2 beállítva');
      expect(ui('Max 4 guests'), 'Legfeljebb 4 vendég');
      expect(
        uiDecimal('1234567890.012300'),
        '1\u00a0234\u00a0567\u00a0890,012300',
      );
      expect(ui('RATE PLAN'), 'DÍJCSOMAG');
      expect(ui('in_progress'), 'Folyamatban');
      expect(
        ui('The server could not be reached.'),
        'A szerver nem érhető el.',
      );
      expect(uiDate('2032-05-10'), contains('2032. máj. 10.'));
      expect(uiNumber(1234.5).replaceAll('\u00a0', ' '), '1 234,5');
      expect(ui('property_id'), 'property_id');
      expect(ui('Unknown Guest {0}'), 'Unknown Guest {0}');
      expect(uiFieldValue('Property', 'Ready'), 'Ready');
      expect(uiFieldValue('Assigned to', 'Owner'), 'Owner');
      expect(uiFieldValue('Status', 'confirmed'), 'Visszaigazolva');
    },
  );

  test('native catalog placeholders match source templates', () {
    final placeholder = RegExp(r'\{\d+\}');
    for (final entry in WebStrings.current.nativeHu.entries) {
      expect(
        placeholder.allMatches(entry.value).map((m) => m[0]).toSet(),
        placeholder.allMatches(entry.key).map((m) => m[0]).toSet(),
        reason: entry.key,
      );
      expect(entry.value.trim(), isNotEmpty, reason: entry.key);
    }
  });

  for (final page in PmsPage.values.where((p) => p != PmsPage.schedule)) {
    testWidgets('Hungarian Android layout and screenshot: ${page.name}', (
      t,
    ) async {
      phone(t);
      final auth = await signedIn(androidFixture());
      final key = GlobalKey();
      try {
        await t.runAsync(loadVisualFonts);
        await t.pumpWidget(
          host(
            RepaintBoundary(
              key: key,
              child: PmsShell(auth: auth, initialPage: page),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.byTooltip(ui('Open main menu')), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await t.pumpAndSettle();
        await t.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(
            format: raster.ImageByteFormat.png,
          );
          final directory = Directory('build/mobile-polish-hu')
            ..createSync(recursive: true);
          File('${directory.path}/${page.name}-393x852.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    });
  }

  testWidgets('mobile wordmark is centered independently of header controls', (
    t,
  ) async {
    phone(t);
    final auth = await signedIn(androidFixture());
    try {
      await t.pumpWidget(
        host(PmsShell(auth: auth, initialPage: PmsPage.today)),
      );
      await t.pumpAndSettle();
      final brand = find.byKey(const ValueKey('mobile-wordmark'));
      final menu = find.byTooltip(ui('Open main menu'));
      final settings = find.byKey(const ValueKey('pms-mobile-settings'));
      final brandCenter = t.getCenter(brand);
      expect(brandCenter.dx, closeTo(393 / 2, .1));
      expect(brandCenter.dy, closeTo(t.getCenter(menu).dy, .1));
      expect(
        t.getBottomRight(brand).dx,
        lessThan(t.getTopLeft(find.byTooltip(ui('Search Delvane'))).dx),
      );
      expect(t.getCenter(settings).dy, brandCenter.dy);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox());
      auth.dispose();
    }
  });

  testWidgets('Hungarian drawer groups all main routes and tracks selection', (
    t,
  ) async {
    phone(t);
    final auth = await signedIn(androidFixture());
    try {
      await t.pumpWidget(
        host(PmsShell(auth: auth, initialPage: PmsPage.today)),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip(ui('Open main menu')));
      await t.pumpAndSettle();
      for (final page in [
        PmsPage.today,
        PmsPage.intelligence,
        PmsPage.reservations,
        PmsPage.inbox,
        PmsPage.operations,
      ]) {
        final item = find.byKey(ValueKey('pms-nav-${page.name}'));
        expect(item, findsOneWidget);
        expect(t.widget<PmsNavItem>(item).selected, page == PmsPage.today);
      }
      await t.tap(find.byKey(const ValueKey('pms-nav-reservations')));
      await t.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('Naptár'), findsOneWidget);
      expect(t.takeException(), isNull);
    } finally {
      await t.pumpWidget(const SizedBox());
      auth.dispose();
    }
  });

  testWidgets(
    'settings language selector persists English for the next launch',
    (t) async {
      phone(t);
      final store = MemorySessionStore();
      await WebStrings.current.initialize(store);
      final auth = await signedIn(androidFixture());
      try {
        await t.pumpWidget(
          host(PmsShell(auth: auth, initialPage: PmsPage.today)),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('pms-mobile-settings')));
        await t.pumpAndSettle();
        final select = find.byType(DropdownButtonFormField<String>);
        await t.ensureVisible(select);
        await t.tap(select);
        await t.pumpAndSettle();
        await t.tap(find.text('English').last);
        await t.pumpAndSettle();
        expect(WebStrings.current.language, 'en');
        expect(store.values[WebStrings.preferenceKey], 'en');
        expect(find.text("Today's command center"), findsOneWidget);
        final restored = WebStrings();
        await restored.initialize(store);
        expect(restored.language, 'en');
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    },
  );

  test(
    'failed preference writes are reported and later writes can recover',
    () async {
      final store = MemorySessionStore();
      final strings = WebStrings();
      await strings.initialize(store);
      store.failWrites = true;
      await expectLater(strings.select('en'), throwsStateError);
      store.failWrites = false;
      await strings.select('hu');
      expect(store.values[WebStrings.preferenceKey], 'hu');
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    testWidgets('account and vector settings behavior: ${platform.name}', (
      t,
    ) async {
      phone(t);
      final auth = await signedIn(androidFixture());
      try {
        await t.pumpWidget(
          host(
            PmsShell(auth: auth, initialPage: PmsPage.today),
            platform: platform,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byTooltip(ui('Open main menu')));
        await t.pumpAndSettle();
        final account = t.widget<InkWell>(
          find.byKey(const ValueKey('pms-account')),
        );
        expect(account.onTap == null, platform == TargetPlatform.android);
        await t.tapAt(const Offset(380, 180));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const ValueKey('pms-mobile-settings')));
        await t.pumpAndSettle();
        expect(find.text(ui('Sign out')), findsOneWidget);
        expect(
          find.byWidgetPredicate((w) => w is PmsVectorIcon && w.name == '↔'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    });
  }

  testWidgets(
    'touch outside Intelligence composer dismisses keyboard and preserves draft',
    (t) async {
      phone(t);
      final auth = await signedIn(androidFixture());
      try {
        await t.pumpWidget(
          host(PmsShell(auth: auth, initialPage: PmsPage.intelligence)),
        );
        await t.pumpAndSettle();
        final composer = find.byKey(const ValueKey('intelligence-composer'));
        expect(t.getBottomRight(composer).dy, lessThanOrEqualTo(828));
        await t.enterText(composer, 'Saját üzenet');
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await t.pumpAndSettle();
        expect(t.widget<TextField>(composer).focusNode!.hasFocus, isTrue);
        await t.tapAt(
          const Offset(4, 200),
          kind: raster.PointerDeviceKind.touch,
        );
        await t.pumpAndSettle();
        expect(t.widget<TextField>(composer).focusNode!.hasFocus, isFalse);
        expect(t.testTextInput.isVisible, isFalse);
        t.view.viewInsets = const FakeViewPadding();
        await t.pumpAndSettle();
        expect(t.widget<TextField>(composer).controller!.text, 'Saját üzenet');
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    },
  );

  testWidgets(
    'mobile calendar keeps cells compact and opens every booking for the day',
    (t) async {
      phone(t);
      String? opened;
      String? created;
      final stays = [
        for (var i = 0; i < 6; i++)
          <String, dynamic>{
            'id': 'r$i',
            'status': 'confirmed',
            'guest_name': 'Guest $i',
            'property_name': 'Apartment $i',
            'arrival_date': '2032-05-10',
            'departure_date': '2032-05-12',
          },
      ];
      await t.pumpWidget(
        host(
          Scaffold(
            body: SingleChildScrollView(
              child: BookingCalendar(
                selection: CalendarSelection(DateTime(2032, 5, 1)),
                properties: const [],
                reservations: stays,
                propertyLabel: (name) => name,
                onOpen: (id) => opened = id,
                onCreate: (date) => created = date,
              ),
            ),
          ),
        ),
      );
      final cell = find.byKey(const ValueKey('calendar-day-2032-05-10'));
      expect(t.getSize(cell).height, lessThan(50));
      await t.ensureVisible(cell);
      await t.tap(cell);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Guest 5'));
      await t.tap(find.text('Guest 5'));
      await t.pumpAndSettle();
      expect(opened, 'r5');
      await t.ensureVisible(cell);
      await t.tap(cell);
      await t.pumpAndSettle();
      final create = find.descendant(
        of: find.byType(PmsModal),
        matching: find.text(ui('Add a stay')),
      );
      await t.tap(create);
      await t.pumpAndSettle();
      expect(created, '2032-05-10');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile calendar remains checkout-exclusive and preserves property mapping',
    (t) async {
      phone(t);
      final fake = androidFixture();
      final now = DateTime.now();
      final arrival = isoDate(DateTime(now.year, now.month, 10));
      final departure = isoDate(DateTime(now.year, now.month, 12));
      fake.overrides['/api/reservations'] = fake.json([
        {...fake.stay, 'arrival_date': arrival, 'departure_date': departure},
        {
          ...fake.stay,
          'id': 'inquiry',
          'status': 'inquiry',
          'arrival_date': arrival,
          'departure_date': departure,
        },
      ]);
      final auth = await signedIn(fake);
      try {
        await t.pumpWidget(
          host(PmsShell(auth: auth, initialPage: PmsPage.reservations)),
        );
        await t.pumpAndSettle();
        final arrivalCell = find.byKey(ValueKey('calendar-day-$arrival'));
        final departureCell = find.byKey(ValueKey('calendar-day-$departure'));
        await t.ensureVisible(arrivalCell);
        await t.tap(arrivalCell);
        await t.pumpAndSettle();
        final modal = find.byType(PmsModal);
        expect(
          find.descendant(
            of: modal,
            matching: find.textContaining(ui('Arrival')),
          ),
          findsOneWidget,
        );
        await t.tap(find.byTooltip(ui('Close dialog')));
        await t.pumpAndSettle();
        await t.ensureVisible(departureCell);
        await t.tap(departureCell);
        await t.pumpAndSettle();
        expect(
          find.descendant(
            of: modal,
            matching: find.textContaining(ui('Departure')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: modal,
            matching: find.textContaining(ui('Occupied night')),
          ),
          findsNothing,
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    },
  );
}
