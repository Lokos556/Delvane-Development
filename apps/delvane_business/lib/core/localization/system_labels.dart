import 'web_strings.dart';

/// Read-only presentation metadata from app.py KNOWLEDGE_FIELDS and
/// AUTHORITY_DEFAULTS. Matching both key and canonical label preserves custom
/// and future provider labels. No identifiers or submitted values are changed.
const knowledgeLabels = <String, String>{
  'parking': 'Parking',
  'wifi': 'Wi-Fi',
  'keys': 'Key collection',
  'late_arrival': 'Late arrival',
  'check_in': 'Check-in',
  'check_out': 'Checkout',
  'high_chair': 'High chair',
  'baby_cot': 'Baby cot',
  'luggage': 'Luggage',
  'pets': 'Pets',
  'smoking': 'Smoking',
  'directions': 'Directions',
  'emergency': 'Emergency / urgent help',
  'climate': 'Heating / air conditioning',
  'appliances': 'Appliances',
  'cleaning': 'Cleaning requirements',
  'consumables': 'Standard consumables',
};
const authorityLabels = <String, String>{
  'answer_property_question': 'Answer routine property questions',
  'update_arrival_time': 'Update guest arrival time',
  'add_special_request': 'Add preparation requests',
  'create_inquiry': 'Create unconfirmed inquiry',
  'late_checkout': 'Offer late checkout',
  'discount': 'Offer a discount',
  'refund': 'Issue / promise a refund',
  'financial_promise': 'Promise or quote an unconfirmed monetary term',
  'reassign_cleaning': 'Reassign cleaning work',
  'assign_maintenance': 'Assign maintenance work',
  'update_registration_status': 'Change registration status',
  'send_guest_message': 'Send routine guest messages',
};
String knowledgeLabel(String key, String value) =>
    knowledgeLabels[key] == value ? ui(value) : value;
String authorityLabel(String key, String value) =>
    authorityLabels[key] == value ? ui(value) : value;
String knowledgeCategory(String value) =>
    const {
      'Arrival',
      'Stay',
      'Departure',
      'Families',
      'House rules',
      'Safety',
      'Operations',
    }.contains(value)
    ? ui(value)
    : value;

// These are database seed records, not an arbitrary dictionary of product names.
// A renamed seed record or an unrelated item with the same English name remains
// verbatim. Quantities, API IDs and editable values always remain unchanged.
const _inventory = <String, (String, String)>{
  'inv_tp': ('Toilet paper', 'rolls'),
  'inv_coffee': ('Coffee capsules', 'capsules'),
  'inv_shampoo': ('Shampoo refills', 'refills'),
  'inv_water': ('Welcome water', 'bottles'),
};
String inventoryName(Map<String, dynamic> item) {
  final name = item['name']?.toString() ?? '';
  return _inventory[item['id']]?.$1 == name ? ui(name) : name;
}

String inventoryUnit(Map<String, dynamic> item) {
  final unit = item['unit']?.toString() ?? '';
  final seed = _inventory[item['id']];
  return seed != null && seed.$1 == item['name'] && seed.$2 == unit
      ? ui(unit)
      : unit;
}

/// Housekeeper is the existing standard cleaner occupation; custom job titles
/// and all personal names remain data. This never changes the editable field.
String staffJobTitle(Map<String, dynamic> member) {
  final title = member['job_title']?.toString() ?? '';
  final role = member['role']?.toString() ?? '';
  if (title.isEmpty) return ui(role);
  return role == 'cleaner' && title == 'Housekeeper' ? ui(title) : title;
}

const automationLabels = <String, (String, String)>{
  'booking_confirmation': (
    'Booking confirmation',
    'Prepare a confirmation when a booking appears.',
  ),
  'pre_arrival_48h': (
    '48-hour arrival guide',
    'Prepare arrival details two days before check-in.',
  ),
  'registration_reminder': (
    'Registration reminder',
    'Prepare a reminder when arrival is close and registration is incomplete.',
  ),
  'arrival_day': (
    'Arrival-day welcome',
    'Prepare a short arrival-day message.',
  ),
  'checkout_eve': (
    'Checkout reminder',
    'Prepare checkout instructions the evening before departure.',
  ),
};
String automationText(Map<String, dynamic> rule, String field) {
  final value = rule[field]?.toString() ?? '';
  final canonical = automationLabels[rule['rule_key']];
  final expected = field == 'description' ? canonical?.$2 : canonical?.$1;
  return value == expected ? ui(value) : value;
}

String permissionGroup(String value) =>
    const {
      'Business & people',
      'Reservations & guests',
      'Guest communication',
      'Operations',
      'Maintenance',
      'Supplies',
      'Rosa knowledge',
      'Security & integrations',
    }.contains(value)
    ? ui(value)
    : value;

String automationTrigger(String value) =>
    const {
      'booking_created': 'Booking created',
      'arrival_minus_48h': '48 hours before arrival',
      'registration_incomplete': 'Registration incomplete',
      'arrival_day': 'Arrival day',
      'checkout_minus_12h': '12 hours before checkout',
    }.containsKey(value)
    ? ui(
        const {
          'booking_created': 'Booking created',
          'arrival_minus_48h': '48 hours before arrival',
          'registration_incomplete': 'Registration incomplete',
          'arrival_day': 'Arrival day',
          'checkout_minus_12h': '12 hours before checkout',
        }[value]!,
      )
    : value;

const _retention = <String, (String, String)>{
  'operational_reservation': (
    'Reservation records',
    'Placeholder policy for pilot; confirm with legal review before production.',
  ),
  'identity_document': (
    'Identity documents',
    'No identity-document retention configured in V2.2. Do not store passport scans in the pilot.',
  ),
  'audit_log': (
    'Audit logs',
    'Security/operational audit retention placeholder.',
  ),
};
String retentionLabel(String key) =>
    _retention.containsKey(key) ? ui(_retention[key]!.$1) : key;
String retentionDescription(String key, String value) =>
    _retention[key]?.$2 == value ? ui(value) : value;
