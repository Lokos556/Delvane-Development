import 'dart:convert';

import 'session_store.dart';

/// Only approved operational fields are persisted by the platform secure store.
/// Never persist record details, message content, names, documents or contact data.
class OfflineOperations {
  OfflineOperations(this.store, this.namespace);
  final SessionStore store;
  final String namespace;
  static const retention = Duration(hours: 12);
  static const fields = <String, Set<String>>{
    '/api/properties': {'id', 'name', 'business_date'},
    '/api/operations/properties': {'id', 'name', 'business_date'},
    '/api/reservations': {
      'id',
      'property_id',
      'property_name',
      'arrival_date',
      'departure_date',
      'status',
      'stay_type',
    },
  };

  Object? project(String path, Object? value) {
    final allowed = fields[path];
    if (allowed != null && value is List) return _rows(value, allowed);
    if (path == '/api/owner/dashboard' &&
        value is Map &&
        value['properties'] is List) {
      return {
        'properties': _rows(value['properties'] as List, {
          'id',
          'name',
          'state',
        }),
      };
    }
    if (path == '/api/worker/dashboard' &&
        value is Map &&
        value['tasks'] is List) {
      return {
        'tasks': _rows(value['tasks'] as List, {
          'id',
          'property_name',
          'unit_label',
          'scheduled_date',
          'status',
        }),
      };
    }
    if (path == '/api/operations/today-command' && value is Map) {
      const sections = {
        'arrivals',
        'departures',
        'cleaning',
        'maintenance',
        'registration_risks',
      };
      return {
        if (value['date'] is String) 'date': value['date'],
        for (final section in sections)
          if (value[section] is List)
            section: _rows(value[section] as List, {
              'id',
              'property_id',
              'property_name',
              'arrival_time',
              'checkout_time',
              'deadline_time',
              'priority',
              'status',
              'severity',
            }),
      };
    }
    return null;
  }

  List<Map<String, Object?>> _rows(List values, Set<String> keys) => [
    for (final value in values.whereType<Map>())
      {
        for (final key in keys)
          if (value[key] is String || value[key] is bool || value[key] is num)
            key: value[key],
      },
  ];

  static const paths = [
    ...fieldsKeys,
    '/api/owner/dashboard',
    '/api/worker/dashboard',
    '/api/operations/today-command',
  ];
  static const fieldsKeys = [
    '/api/properties',
    '/api/operations/properties',
    '/api/reservations',
  ];
  String _key(String path) => '$namespace.offline.$path';

  Future<void> remember(
    String path,
    Object? value,
    String scope,
    DateTime now,
  ) async {
    final safe = project(path, value);
    if (safe == null) return;
    final encoded = jsonEncode({
      'scope': scope,
      'at': now.toIso8601String(),
      'value': safe,
    });
    // A single record must fit Windows Credential Manager as well as mobile.
    if (encoded.length > 1100 || utf8.encode(encoded).length > 2000) {
      await store.delete(_key(path));
    } else {
      await store.write(_key(path), encoded);
    }
  }

  Future<(Object, DateTime)?> read(
    String path,
    String scope,
    DateTime now,
  ) async {
    if (!paths.contains(path)) return null;
    try {
      final raw = await store.read(_key(path));
      if (raw == null) return null;
      final saved = jsonDecode(raw) as Map;
      final at = DateTime.parse(saved['at'] as String);
      if (saved['scope'] != scope ||
          at.isAfter(now) ||
          now.difference(at) >= retention) {
        return null;
      }
      final safe = project(path, saved['value']);
      return safe == null ? null : (safe, at);
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    for (final path in paths) {
      await store.delete(_key(path));
    }
  }
}
