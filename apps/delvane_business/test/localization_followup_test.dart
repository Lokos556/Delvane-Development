import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/core/localization/system_labels.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_icons.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/ask_bar.dart';
import 'package:delvane_business/features/pms/administration_pages.dart';
import 'package:delvane_business/features/pms/operations_pages.dart';

import 'android_readiness_test.dart' show androidFixture;
import 'mobile_polish_test.dart' show host;
import 'support/fake_pms.dart';
import 'support/management_pms.dart';
import 'support/visual_fonts.dart';

class DelayedAsk extends FakePms {
  final reply = Completer<ApiResponse>();
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    if (method == 'POST' && uri.path == '/api/rosa/ask') {
      requests.add((
        method: method,
        path: uri.path,
        headers: Map.of(headers),
        body: body,
      ));
      if (headers['X-Rosa-CSRF'] != fakeCsrf ||
          headers['Cookie'] != 'rosa_session=$fakeCookie') {
        return json({}, 403);
      }
      return reply.future;
    }
    return super.request(method, uri, headers, body);
  }
}

void viewport(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 852);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await WebStrings.current.load();
    WebStrings.current.language = 'hu';
  });
  tearDown(() => WebStrings.current.language = 'en');

  test('reported UI labels have natural Hungarian and preserve English', () {
    const labels = {
      'New Messages': 'Új üzenetek',
      'Live external sending': 'Aktív külső üzenetküldés',
      'Prepared touchpoints': 'Előkészített üzenetek',
      'Checkout': 'Kijelentkezés',
      'Stay': 'Tartózkodás',
      'Check-in': 'Bejelentkezés',
      'Team & Access': 'Csapat és hozzáférések',
      'Team and Access': 'Csapat és hozzáférések',
      'Active people': 'Aktív munkatársak',
      'Cleaners': 'Takarítók',
      'Maintenance': 'Karbantartás',
      'Access attention': 'Hozzáférési figyelmeztetések',
      'Housekeeper': 'Takarító',
      'Never': 'Soha',
      'Parking': 'Parkolás',
      'Arrival': 'Érkezés',
      'Configured': 'Beállítva',
      'Active distribution': 'Aktív értékesítési csatornák',
      'Outgoing queue': 'Kimenő feldolgozási sor',
      'Unacknowledged bookings': 'Visszaigazolatlan foglalások',
      'Disconnected': 'Nincs csatlakoztatva',
      'Security Center': 'Biztonsági központ',
    };
    for (final label in labels.entries) {
      expect(ui(label.key), label.value, reason: label.key);
    }
    WebStrings.current.language = 'en';
    for (final label in labels.keys) {
      expect(ui(label), label);
    }
  });

  test(
    'all reviewed knowledge, authority and automation metadata translate',
    () {
      for (final entry in knowledgeLabels.entries) {
        final result = knowledgeLabel(entry.key, entry.value);
        if (entry.value != 'Wi-Fi') {
          expect(result, isNot(entry.value), reason: entry.key);
        }
        expect(
          knowledgeLabel(entry.key, 'Custom English label'),
          'Custom English label',
        );
      }
      for (final entry in authorityLabels.entries) {
        expect(authorityLabel(entry.key, entry.value), isNot(entry.value));
      }
      for (final entry in automationLabels.entries) {
        final rule = {
          'rule_key': entry.key,
          'label': entry.value.$1,
          'description': entry.value.$2,
        };
        expect(automationText(rule, 'label'), isNot(entry.value.$1));
        expect(automationText(rule, 'description'), isNot(entry.value.$2));
        expect(rule['label'], entry.value.$1);
      }
      expect(knowledgeLabel('custom', 'Parking'), 'Parking');
      expect(knowledgeCategory('Custom category'), 'Custom category');
      expect(
        automationText({'rule_key': 'custom', 'label': 'Parking'}, 'label'),
        'Parking',
      );
      expect(authorityLabel('custom', 'Parking'), 'Parking');
      expect(
        staffJobTitle({'role': 'cleaner', 'job_title': 'Housekeeper'}),
        'Takarító',
      );
      expect(
        staffJobTitle({'role': 'cleaner', 'job_title': 'Custom Housekeeper'}),
        'Custom Housekeeper',
      );
    },
  );

  test('built-in inventory uses ID and unchanged name; arbitrary records are untouched', () {
    const seeds = {
      'inv_coffee': ('Coffee capsules', 'Kávékapszulák', 'capsules'),
      'inv_shampoo': ('Shampoo refills', 'Samponutántöltők', 'refills'),
      'inv_tp': ('Toilet paper', 'WC-papír', 'rolls'),
      'inv_water': ('Welcome water', 'Bekészített ásványvíz', 'bottles'),
    };
    for (final seed in seeds.entries) {
      final item = {
        'id': seed.key,
        'name': seed.value.$1,
        'unit': seed.value.$3,
      };
      expect(inventoryName(item), seed.value.$2);
      expect(inventoryUnit(item), isNot(seed.value.$3));
      expect(item['name'], seed.value.$1);
      expect(inventoryName({...item, 'id': 'custom'}), seed.value.$1);
      expect(
        inventoryName({...item, 'name': 'Custom Coffee'}),
        'Custom Coffee',
      );
      expect(inventoryUnit({...item, 'unit': 'Custom units'}), 'Custom units');
      WebStrings.current.language = 'en';
      expect(inventoryName(item), seed.value.$1);
      expect(inventoryUnit(item), seed.value.$3);
      WebStrings.current.language = 'hu';
    }
  });

  for (final width in [320.0, 393.0, 1440.0]) {
    testWidgets('Settings icons remain square at $width', (t) async {
      viewport(t, width);
      final auth = await signedIn(androidFixture());
      try {
        await t.runAsync(loadVisualFonts);
        await t.pumpWidget(
          host(
            PmsShell(auth: auth, initialPage: PmsPage.today),
            platform: width > 760
                ? TargetPlatform.windows
                : TargetPlatform.android,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(
          find.byKey(
            ValueKey(width > 760 ? 'pms-account' : 'pms-mobile-settings'),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Csapat és hozzáférések'), findsOneWidget);
        expect(find.text('Biztonsági központ'), findsOneWidget);
        for (final name in ['♙', '◎', '◇', '▦', '↔', '⌾']) {
          final icon = find.byWidgetPredicate(
            (w) => w is PmsVectorIcon && w.name == name,
          );
          final paint = find.descendant(
            of: icon,
            matching: find.byType(CustomPaint),
          );
          final size = t.getSize(paint.first);
          expect(size.width, closeTo(size.height, .01), reason: name);
          expect(size.shortestSide, 20);
        }
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    });

    testWidgets(
      'vector Ask send preserves payload, CSRF and busy state at $width',
      (t) async {
        viewport(t, width);
        final pms = DelayedAsk();
        final auth = await signedIn(pms);
        final c = PmsController(auth);
        try {
          await t.pumpWidget(
            host(Scaffold(bottomNavigationBar: PmsAskBar(c: c))),
          );
          await t.pumpAndSettle();
          final input = find.byType(TextField);
          await t.enterText(input, 'Kinek hiányzik a regisztrációja?');
          final send = find.byKey(const ValueKey('pms-ask-send'));
          expect(t.getSize(send), Size.square(width <= 760 ? 44 : 48));
          expect(find.text(ui('Ask')), findsNothing);
          expect(
            find.byWidgetPredicate(
              (w) => w is PmsVectorIcon && w.name == 'send',
            ),
            findsOneWidget,
          );
          await t.tap(send);
          await t.pump();
          expect(t.widget<PmsIconButton>(send).onPressed, isNull);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
          final request = pms.requests.singleWhere(
            (r) => r.path == '/api/rosa/ask',
          );
          expect(request.headers['X-Rosa-CSRF'], fakeCsrf);
          expect(
            (request.body as Map)['message'],
            'Kinek hiányzik a regisztrációja?',
          );
          pms.reply.complete(
            pms.json({'answer': 'Untranslated server answer with guest text'}),
          );
          await t.pumpAndSettle();
          expect(t.widget<PmsIconButton>(send).onPressed, isNotNull);
          expect(
            find.text('Untranslated server answer with guest text'),
            findsOneWidget,
          );
          expect(t.widget<TextField>(input).controller!.text, isEmpty);
          expect(t.takeException(), isNull);
        } finally {
          await t.pumpWidget(const SizedBox());
          c.dispose();
          auth.dispose();
        }
      },
    );
  }

  for (final entry in {
    PmsPage.inbox: [
      'ÚJ ÜZENETEK',
      'ELŐKÉSZÍTETT ÜZENETEK',
      'AKTÍV KÜLSŐ ÜZENETKÜLDÉS',
    ],
    PmsPage.team: [
      'AKTÍV MUNKATÁRSAK',
      'TAKARÍTÓK',
      'HOZZÁFÉRÉSI FIGYELMEZTETÉSEK',
    ],
    PmsPage.integrations: [
      'AKTÍV ÉRTÉKESÍTÉSI CSATORNÁK',
      'KIMENŐ FELDOLGOZÁSI SOR',
      'VISSZAIGAZOLATLAN FOGLALÁSOK',
    ],
    PmsPage.security: ['Biztonsági központ', 'Szerepkörök jogosultságai'],
  }.entries) {
    testWidgets('actual ${entry.key.name} labels render Hungarian', (t) async {
      viewport(t, 393);
      final auth = await signedIn(androidFixture());
      try {
        await t.runAsync(loadVisualFonts);
        await t.pumpWidget(host(PmsShell(auth: auth, initialPage: entry.key)));
        await t.pumpAndSettle();
        for (final label in entry.value) {
          expect(find.text(label), findsWidgets);
        }
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        auth.dispose();
      }
    });
  }

  testWidgets(
    'knowledge metadata localizes without changing content or property names',
    (t) async {
      viewport(t, 393);
      final pms = ManagementPms();
      pms.knowledge['properties'] = [
        {'id': 'parking-property', 'name': 'Parking'},
      ];
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.train);
      try {
        await c.load();
        await t.pumpWidget(
          host(
            Scaffold(
              body: SingleChildScrollView(child: KnowledgePage(c: c)),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Érkezés'), findsOneWidget);
        expect(find.text('Parkolás'), findsOneWidget);
        expect(find.text('Beállítva'), findsOneWidget);
        expect(
          find.text('Parking'),
          findsOneWidget,
        ); // Property name, not UI copy.
        final field = find.byType(TextFormField);
        expect(
          t.widget<TextFormField>(field).controller!.text,
          'Synthetic parking',
        );
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );

  testWidgets(
    'inventory cards, shopping list and dialog use the same localized name',
    (t) async {
      viewport(t, 393);
      final pms = ManagementPms();
      pms.stocks[0].addAll({
        'id': 'inv_coffee',
        'name': 'Coffee capsules',
        'unit': 'capsules',
      });
      final auth = await signedIn(pms);
      final c = PmsController(auth, initialPage: PmsPage.supplies);
      try {
        await c.load();
        await t.pumpWidget(
          host(
            Scaffold(
              body: SingleChildScrollView(child: SuppliesPage(c: c)),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Kávékapszulák'), findsOneWidget);
        expect(find.textContaining('Kávékapszulák ·'), findsOneWidget);
        final adjust = find.text(ui('Adjust stock'));
        await t.ensureVisible(adjust);
        await t.tap(adjust);
        await t.pumpAndSettle();
        expect(find.text('Kávékapszulák'), findsNWidgets(2));
        expect(pms.stocks[0]['name'], 'Coffee capsules');
        expect(t.takeException(), isNull);
      } finally {
        await t.pumpWidget(const SizedBox());
        c.dispose();
        auth.dispose();
      }
    },
  );
}
