import 'dart:io';

import 'package:flutter/services.dart';

/// Read installed host fonts in screenshot tests; no OS font is redistributed.
Future<void> loadVisualFonts() async {
  final brand = FontLoader('Inter')
    ..addFont(rootBundle.load('assets/fonts/Inter-Variable.ttf'));
  await brand.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  for (final entry in {
    'Segoe UI': ['segoeui.ttf', 'segoeuib.ttf', 'seguisb.ttf'],
    'Georgia': ['georgia.ttf', 'georgiab.ttf'],
    'Arial': ['arial.ttf', 'arialbd.ttf'],
    'Segoe UI Symbol': ['seguisym.ttf'],
  }.entries) {
    final loader = FontLoader(entry.key);
    for (final name in entry.value) {
      final macName = switch (name) {
        'segoeui.ttf' => 'Arial.ttf',
        'segoeuib.ttf' || 'seguisb.ttf' => 'Arial Bold.ttf',
        'georgia.ttf' => 'Georgia.ttf',
        'georgiab.ttf' => 'Georgia Bold.ttf',
        'arial.ttf' => 'Arial.ttf',
        'arialbd.ttf' => 'Arial Bold.ttf',
        _ => 'Arial Unicode.ttf',
      };
      final file = File(
        Platform.isMacOS
            ? '/System/Library/Fonts/Supplemental/$macName'
            : 'C:/Windows/Fonts/$name',
      );
      if (await file.exists()) {
        loader.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await loader.load();
  }
}
