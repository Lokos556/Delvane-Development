import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/features/pms/pms_shell.dart';
import 'package:delvane_business/features/pms/pms_style.dart';
import 'package:delvane_business/features/pms/pms_controller.dart';
import 'support/fake_pms.dart';

void main() {
  for (final size in [const Size(1440, 1000), const Size(390, 844)]) {
    testWidgets('reference Today at $size', (tester) async {
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
      final auth = await signedIn(pms);
      final key = GlobalKey();
      await tester.runAsync(() async {
        final loader = FontLoader('Segoe UI')
          ..addFont(
            File(
              'C:/Windows/Fonts/segoeui.ttf',
            ).readAsBytes().then(ByteData.sublistView),
          );
        await loader.load();
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: pmsTheme(),
          home: RepaintBoundary(
            key: key,
            child: PmsShell(auth: auth, initialPage: PmsPage.today),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("Today's command center"), findsOneWidget);
      expect(find.text('Registration needs attention'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final image =
            await (key.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/visual-reference').createSync(recursive: true);
        File(
          'build/visual-reference/flutter-today-${size.width.toInt()}x${size.height.toInt()}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
      if (size.width > 760) {
        await tester.tap(find.byKey(const ValueKey('pms-nav-reservations')));
        await tester.pumpAndSettle();
        expect(find.text('Calendar'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
    });
  }
}
