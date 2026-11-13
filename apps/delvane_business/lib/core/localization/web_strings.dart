import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../auth/session_store.dart';

import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

class WebStrings extends ChangeNotifier {
  static final current = WebStrings();
  static const preferenceKey = 'delvane.business.language.v1';
  SessionStore? _store;
  Future<void>? _writes;
  Map<String, String> nativeHu = {};
  Map<String, dynamic> data = {};
  String language = 'hu';
  final Map<String, Map<String, String>> _lookups = {};
  final Map<String, String> _folded = {};
  final List<
    ({RegExp pattern, List<String> names, String translation, int specificity})
  >
  _templates = [];
  Future<void> load() async {
    await initializeDateFormatting('hu');
    final bytes = await rootBundle.load('assets/web-locales.json');
    data = jsonDecode(
      utf8.decode(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
    final nativeBytes = await rootBundle.load('assets/native-hu.json');
    nativeHu = (jsonDecode(
      utf8.decode(
        nativeBytes.buffer.asUint8List(
          nativeBytes.offsetInBytes,
          nativeBytes.lengthInBytes,
        ),
      ),
    ) as Map).cast<String, String>();
    _lookups.clear();
    _folded.clear();
    _templates.clear();
    for (final entry in nativeHu.entries) {
      _folded[entry.key.toLowerCase()] = entry.value;
      final names = RegExp(r'\{(\d+)\}').allMatches(entry.key).toList();
      if (names.isEmpty) continue;
      final pattern = StringBuffer('^');
      var position = 0;
      for (final name in names) {
        pattern.write(RegExp.escape(entry.key.substring(position, name.start)));
        pattern.write('([\\s\\S]*?)');
        position = name.end;
      }
      pattern.write(RegExp.escape(entry.key.substring(position)));
      pattern.write(r'$');
      _templates.add((
        pattern: RegExp(pattern.toString()),
        names: names.map((n) => n.group(1)!).toList(),
        translation: entry.value,
        specificity: entry.key.replaceAll(RegExp(r'\{\d+\}'), '').length,
      ));
    }
    // "Max {0} guests" must win over the more general "{0} guests".
    _templates.sort((a, b) => b.specificity.compareTo(a.specificity));
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
    final previous = _writes;
    final store = _store;
    final write = () async {
      if (previous != null) await previous;
      await store?.write(preferenceKey, value);
    }();
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
      final folded = _folded[english.toLowerCase()];
      if (folded != null) {
        return english == english.toUpperCase() ? folded.toUpperCase() : folded;
      }
      // Explicit UI templates only. Captures are inserted verbatim and never
      // translated recursively, preserving names, identifiers and user content.
      for (final template in _templates) {
        final match = template.pattern.firstMatch(english);
        if (match != null) {
          // Substitute in one pass: a guest name containing "{1}" is data,
          // never another placeholder to expand.
          return template.translation.replaceAllMapped(RegExp(r'\{(\d+)\}'), (
            m,
          ) {
            final index = template.names.indexOf(m.group(1)!);
            return index < 0 ? m.group(0)! : match.group(index + 1)!;
          });
        }
      }
    }
    return lookup[english] ?? english;
  }
}

/// Only call for interface copy; never for arbitrary server/user content.
String ui(String value) => WebStrings.current.t(value);
String uiDate(String value) {
  // Preserve the existing English wire-date captions in record navigation.
  if (WebStrings.current.language == 'en') return value;
  final date = DateTime.tryParse(value);
  return date == null
      ? value
      : DateFormat.yMMMd(WebStrings.current.language).format(date);
}

String uiNumber(num value) =>
    NumberFormat.decimalPattern(WebStrings.current.language).format(value);

/// Formats decimal wire strings without converting money through a double.
String uiDecimal(String value) {
  if (WebStrings.current.language != 'hu') return value;
  final match = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$').firstMatch(value);
  if (match == null) return value;
  final integer = match
      .group(2)!
      .replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]}\u00a0',
      );
  final fraction = match.group(3);
  return '${match.group(1)}$integer${fraction == null ? '' : ',$fraction'}';
}

String uiDateTime(String value) {
  if (WebStrings.current.language == 'en') return value;
  final date = DateTime.tryParse(value);
  return date == null
      ? value
      : DateFormat.yMMMd('hu').add_Hm().format(date.toLocal());
}

/// Translate only fields with a known presentation contract. Personal names,
/// addresses, free text and record identifiers always pass through unchanged.
String uiFieldValue(String label, String value) {
  if (WebStrings.current.language == 'en') return value;
  bool isField(Set<String> labels) =>
      labels.any((key) => label == key || label == ui(key));
  if (isField({
    'Status',
    'Registration',
    'Payment',
    'Payment label',
    'Readiness',
    'Severity',
    'Role',
    'Same-day turnover',
  })) {
    return ui(value);
  }
  if (isField({
    'Due',
    'Reported',
    'Resolved',
    'Verified',
    'Departure',
    'Arrival',
  })) {
    return value.length == 10 ? uiDate(value) : uiDateTime(value);
  }
  if (isField({'Reservation amount (HUF)', 'Guests', 'Guest capacity'})) {
    return uiDecimal(value);
  }
  return value;
}
