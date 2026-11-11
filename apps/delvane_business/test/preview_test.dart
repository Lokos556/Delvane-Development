import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/app/app.dart';

void main() {
  for (final entry in {
    'desktop': const Size(1440, 1000),
    'mobile': const Size(390, 844),
  }.entries) {
    testWidgets('rasterizes ${entry.key} dashboard preview', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(() async {
        final icons = FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
        await icons.load();
        final systemRoot = Platform.environment['SystemRoot'];
        if (Platform.isWindows && systemRoot != null) {
          final font = File('$systemRoot/Fonts/segoeui.ttf');
          if (await font.exists()) {
            final loader = FontLoader('Segoe UI')
              ..addFont(font.readAsBytes().then(ByteData.sublistView));
            await loader.load();
          }
        }
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: key, child: const DelvaneBusinessApp()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        expect(image.width, entry.value.width.toInt());
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = await Directory(
          'build/previews',
        ).create(recursive: true);
        await File(
          '${directory.path}/${entry.key}.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
