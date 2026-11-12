import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../auth/session_store.dart';
import 'package:intl/intl.dart';

class WebStrings extends ChangeNotifier {
  static final current = WebStrings();
  static const preferenceKey = 'delvane.business.language.v1';
  SessionStore? _store;
  Future<void> _writes = Future.value();
  Map<String, String> nativeHu = {};
  Map<String, dynamic> data = {};
  String language = 'hu';
  final Map<String, Map<String, String>> _lookups = {};
  Future<void> load() async {
    final bytes = await rootBundle.load('assets/web-locales.json');
    data = jsonDecode(
      utf8.decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    nativeHu =
        (jsonDecode(await rootBundle.loadString('assets/native-hu.json'))
                as Map)
            .cast<String, String>();
    _lookups.clear();
    notifyListeners();
  }

  Future<void> initialize(SessionStore store) async {
    _store = store;
    if (data.isEmpty) await load();
    try {
      final saved = await store.read(preferenceKey);
      if (saved == 'hu' || saved == 'en') language = saved!;
    } catch (_) {
      /* A preferences failure never bypasses authentication. */
    }
    notifyListeners();
  }

  Future<void> select(String value) async {
    if (value != 'hu' && value != 'en') return;
    language = value;
    notifyListeners();
    final write = _writes.then(
      (_) async => _store?.write(preferenceKey, value),
    );
    _writes = write.catchError((Object _) {});
    await write;
  }

  List<List<String>> get languages => const [
    ['hu', 'Magyar'],
    ['en', 'English'],
  ];
  String t(String english) {
    if (language == 'en') return english;
    final lookup = _lookups.putIfAbsent(language, () {
      final out = <String, String>{};
      for (final entry in ((data['catalogs'] ?? {}) as Map).entries) {
        if (entry.value is! Map) continue;
        final catalog = entry.value as Map;
        final en = catalog['en'];
        final translated = catalog[language];
        if (entry.key == 'FULL_LOCALE' && translated is Map) {
          for (final item in translated.entries) {
            if (item.value is String) out[item.key.toString()] = item.value;
          }
        } else if (en is Map && translated is Map) {
          for (final item in en.entries) {
            if (item.value is String && translated[item.key] is String) {
              out[item.value] = translated[item.key];
            }
          }
        }
      }
      return out;
    });
    if (language == 'hu') {
      final direct = nativeHu[english];
      if (direct != null) return direct;
      // Explicit UI templates only. Captures are inserted verbatim and never
      // translated recursively, preserving names, identifiers and user content.
      for (final entry in nativeHu.entries.where((e) => e.key.contains('{'))) {
        final names = RegExp(r'\{(\d+)\}').allMatches(entry.key).toList();
        final pattern = StringBuffer('^');
        var position = 0;
        for (final name in names) {
          pattern.write(
            RegExp.escape(entry.key.substring(position, name.start)),
          );
          pattern.write('([\\s\\S]*?)');
          position = name.end;
        }
        pattern.write(RegExp.escape(entry.key.substring(position)));
        pattern.write(r'$');
        final match = RegExp(pattern.toString()).firstMatch(english);
        if (match != null) {
          var result = entry.value;
          for (var i = 0; i < names.length; i++) {
            result = result.replaceAll(
              '{${names[i].group(1)}}',
              match.group(i + 1)!,
            );
          }
          return result;
        }
      }
    }
    return lookup[english] ?? english;
  }
}

/// Only call for interface copy; never for arbitrary server/user content.
String ui(String value) => WebStrings.current.t(value);
String uiDate(String value) {
  final date = DateTime.tryParse(value);
  return date == null
      ? value
      : DateFormat.yMMMd(WebStrings.current.language).format(date);
}

String uiNumber(num value) =>
    NumberFormat.decimalPattern(WebStrings.current.language).format(value);
