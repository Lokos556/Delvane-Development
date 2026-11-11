import '../../core/network/api_client.dart';

Map<String, dynamic> jsonObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const ApiException('The server returned an invalid record.');
  }
  return value;
}

List<Map<String, dynamic>> jsonRows(Object? value) {
  if (value is! List) {
    throw const ApiException('The server returned an invalid list.');
  }
  return value.map(jsonObject).toList();
}

String text(Map<String, dynamic> row, String key, [String fallback = '']) =>
    row[key] == null ? fallback : row[key].toString();
String recordId(Map<String, dynamic> row, [String key = 'id']) {
  final value = row[key];
  if (value is! String || value.isEmpty) {
    throw const ApiException(
      'The server returned a record without an identifier.',
    );
  }
  return value;
}

enum RecordKind { reservation, property, cleaning, maintenance }

class RecordRef {
  const RecordRef(this.kind, this.id);
  final RecordKind kind;
  final String id;
}

class OperationalItem {
  const OperationalItem({
    required this.ref,
    required this.propertyId,
    required this.title,
    required this.detail,
    required this.status,
    this.urgent = false,
    this.fields = const {},
  });
  final RecordRef ref;
  final String propertyId, title, detail, status;
  final bool urgent;
  final Map<String, String> fields;
}

class OperationalProperty {
  const OperationalProperty(
    this.id,
    this.name,
    this.checkin,
    this.checkout, {
    this.state,
    this.reasons = const [],
  });
  final String id, name, checkin, checkout;
  final String? state;
  final List<String> reasons;
}

class OperationalWorkspace {
  const OperationalWorkspace({
    required this.date,
    required this.properties,
    this.arrivals = const [],
    this.departures = const [],
    this.cleaning = const [],
    this.maintenance = const [],
    this.registration = const [],
    this.priorities = const [],
  });
  final String date;
  final List<OperationalProperty> properties;
  final List<OperationalItem> arrivals,
      departures,
      cleaning,
      maintenance,
      registration,
      priorities;
  String propertyName(String id) =>
      properties.where((p) => p.id == id).map((p) => p.name).firstOrNull ??
      'Property unavailable';
}

class RecordDetail {
  const RecordDetail(
    this.title,
    this.fields, {
    this.links = const [],
    this.checklist = const [],
  });
  final String title;
  final Map<String, String> fields;
  final List<({String label, RecordRef ref})> links;
  final List<({String label, bool completed})> checklist;
}
