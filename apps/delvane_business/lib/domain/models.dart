enum StayStatus { confirmed, arriving, inHouse, departing }

extension StayStatusLabel on StayStatus {
  String get label => switch (this) {
    StayStatus.confirmed => 'Confirmed',
    StayStatus.arriving => 'Arriving',
    StayStatus.inHouse => 'In house',
    StayStatus.departing => 'Departing',
  };
}

class Stay {
  const Stay({
    required this.id,
    required this.guest,
    required this.propertyId,
    required this.arrival,
    required this.departure,
    required this.guests,
    required this.totalHuf,
    required this.channel,
    required this.status,
  });
  final String id, guest, propertyId, channel;
  final DateTime arrival, departure;
  final int guests, totalHuf;
  final StayStatus status;
}

class Property {
  const Property(
    this.id,
    this.name,
    this.location,
    this.units,
    this.occupied,
    this.ready,
  );
  final String id, name, location;
  final int units, occupied;
  final bool ready;
}

class GuestMessage {
  const GuestMessage(
    this.id,
    this.sender,
    this.propertyId,
    this.subject,
    this.body,
    this.time, {
    this.unread = false,
  });
  final String id, sender, propertyId, subject, body, time;
  final bool unread;
}

class WorkItem {
  const WorkItem(
    this.id,
    this.title,
    this.propertyId,
    this.assignee,
    this.due, {
    this.urgent = false,
  });
  final String id, title, propertyId, assignee, due;
  final bool urgent;
}

class BusinessSnapshot {
  const BusinessSnapshot({
    required this.properties,
    required this.stays,
    required this.messages,
    required this.tasks,
    required this.date,
  });
  final List<Property> properties;
  final List<Stay> stays;
  final List<GuestMessage> messages;
  final List<WorkItem> tasks;
  final DateTime date;
  String propertyName(String id) =>
      properties.firstWhere((p) => p.id == id).name;
}

String shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${date.day} ${months[date.month - 1]}';
}

String money(int huf) {
  final digits = huf.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '$digits Ft';
}
