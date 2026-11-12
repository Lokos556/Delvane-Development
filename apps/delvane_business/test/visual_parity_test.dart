import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'support/fake_pms.dart';
import 'support/visual_fonts.dart';

void main() {
  const phase = String.fromEnvironment('VISUAL_PHASE', defaultValue: 'after');
  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    for (final entry in {
      'today': PmsPage.today,
      'intelligence': PmsPage.intelligence,
      'desk-overview': PmsPage.intelligence,
      'desk-decisions': PmsPage.intelligence,
      'desk-exceptions': PmsPage.intelligence,
      'desk-next48': PmsPage.intelligence,
      'calendar': PmsPage.reservations,
      'reception': PmsPage.inbox,
      'operations': PmsPage.operations,
      'team': PmsPage.team,
      'maintenance': PmsPage.maintenance,
      'supplies': PmsPage.supplies,
      'knowledge': PmsPage.train,
      'simulation': PmsPage.simulation,
      'security': PmsPage.security,
      'integrations': PmsPage.integrations,
      'property': PmsPage.today,
      'settings': PmsPage.today,
      'worker': PmsPage.today,
    }.entries) {
      testWidgets(
        'visual ${entry.key} ${size.width.toInt()}x${size.height.toInt()}',
        (tester) async {
          final oldShadows = debugDisableShadows;
          debugDisableShadows = false;
          addTearDown(() => debugDisableShadows = oldShadows);
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final fixtures =
              jsonDecode(
                    File('test/fixtures/web_reference.json').readAsStringSync(),
                  )
                  as Map<String, dynamic>;
          final pms = FakePms();
          for (final e in fixtures.entries) {
            pms.overrides[e.key] = pms.json(e.value);
          }
          if (entry.key == 'worker') {
            pms.role = 'cleaner';
            pms.overrides['/api/me'] = pms.json({
              ...fixtures['/api/me'] as Map,
              'id': 'user-cleaner',
              'role': 'cleaner',
              'full_name': 'Development Cleaner',
            });
          }
          final auth = await signedIn(pms), key = GlobalKey();
          try {
            await tester.runAsync(loadVisualFonts);
            await tester.pumpWidget(
              RepaintBoundary(
                key: key,
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: pmsTheme(),
                  home: PmsShell(auth: auth, initialPage: entry.value),
                ),
              ),
            );
            await tester.pumpAndSettle();
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 40)),
            );
            if (entry.key.startsWith('desk-')) {
              final label = {
                'desk-overview': 'Delvane handling',
                'desk-decisions': 'Needs you',
                'desk-exceptions': 'Exceptions',
                'desk-next48': 'Next 48h',
              }[entry.key]!;
              await tester.ensureVisible(find.text(label).first);
              await tester.tap(find.text(label).first);
            } else if (entry.key == 'settings') {
              await tester.tap(
                find.byKey(
                  ValueKey(
                    size.width > 760 ? 'pms-account' : 'pms-mobile-settings',
                  ),
                ),
              );
            } else if (entry.key == 'property') {
              await tester.ensureVisible(find.text('Test House').last);
              await tester.tap(find.text('Test House').last);
            } else if (entry.key == 'calendar') {
              await tester.ensureVisible(find.text('Go to month'));
              await tester.tap(find.text('Go to month'));
              await tester.pumpAndSettle();
              await tester.enterText(
                find.byType(TextFormField).last,
                '2032-05',
              );
              await tester.tap(find.text('Go'));
            }
            await tester.pumpAndSettle();
            final main = find
                .descendant(
                  of: find.byKey(const ValueKey('pms-main-scroll')),
                  matching: find.byType(Scrollable),
                )
                .first;
            tester.state<ScrollableState>(main).position.jumpTo(0);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              Directory('build/visual-reference').createSync(recursive: true);
              final prefix =
                  'build/visual-reference/flutter-$phase-${entry.key}-${size.width.toInt()}x${size.height.toInt()}';
              File('$prefix.png').writeAsBytesSync(bytes!.buffer.asUint8List());
              final geometry = <String, Object?>{};
              for (final name in [
                'pms-sidebar',
                'today-header',
                'today-metrics',
                'registration-strip',
                'today-board',
                'properties-grid',
              ]) {
                final target = find.byKey(ValueKey(name));
                if (target.evaluate().isNotEmpty) {
                  final r = tester.getRect(target);
                  geometry[name] = {
                    'x': r.left,
                    'y': r.top,
                    'width': r.width,
                    'height': r.height,
                  };
                }
              }
              File(
                '$prefix.geometry.json',
              ).writeAsStringSync(jsonEncode(geometry));
              image.dispose();
            });
          } finally {
            await tester.pumpWidget(const SizedBox());
            auth.dispose();
            debugDisableShadows = oldShadows;
          }
        },
      );
    }
  }
}
