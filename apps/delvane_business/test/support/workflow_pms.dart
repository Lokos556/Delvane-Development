import 'package:delvane_business/core/network/api_client.dart';

import 'fake_pms.dart';

/// Stateful contract double; live application code never imports test fixtures.
class WorkflowPms extends FakePms {
  late Map<String, dynamic> booking = Map.of(stay);
  final notes = <Map<String, dynamic>>[];
  final events = <Map<String, dynamic>>[];
  final messages = <Map<String, dynamic>>[
    {
      'id': 'msg1',
      'source': 'Direct email',
      'sender_name': 'Synthetic Guest',
      'subject': 'Arrival request',
      'body': 'We arrive at 20:30. Please prepare a high chair.',
      'status': 'new',
      'reservation_id': 'r1',
      'property_name': 'Test House',
      'draft_reply': '',
      'analysis': <String, dynamic>{},
    },
  ];
  final outbox = <Map<String, dynamic>>[
    {
      'id': 'out1',
      'subject': 'Arrival instructions',
      'guest_name': 'Synthetic Guest',
      'property_name': 'Test House',
      'status': 'awaiting_approval',
      'body': 'Synthetic prepared message',
      'channel': 'Rosa preview',
    },
  ];
  final rules = <Map<String, dynamic>>[
    {
      'id': 'rule1',
      'label': 'Arrival directions',
      'trigger_key': 'arrival_due',
      'description': 'Prepare a draft',
      'enabled': 1,
      'authority_mode': 'ask',
      'run_count': 0,
    },
  ];
  String? failPath;
  int failureStatus = 503;
  final extraBookings = <Map<String, dynamic>>[];
  String verification = 'needs_review';
  bool failRefresh = false;
  int mutationCount = 0;
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    final path = uri.path;
    final custom =
        path.startsWith('/api/properties/p1/room-types') ||
        path.startsWith('/api/reservations') ||
        path.startsWith('/api/inbox') ||
        path.startsWith('/api/reception') ||
        path.startsWith('/api/communications') ||
        path.startsWith('/api/automation') ||
        path.startsWith('/api/guests') ||
        path == '/api/organization';
    if (!custom) return super.request(method, uri, headers, body);
    requests.add((
      method: method,
      path: path,
      headers: Map.of(headers),
      body: body,
    ));
    if (headers['Cookie'] != 'rosa_session=$fakeCookie') return json({}, 401);
    if (!{'owner', 'manager'}.contains(role)) return json({}, 403);
    if (method != 'GET' && headers['X-Rosa-CSRF'] != fakeCsrf) {
      return json({}, 403);
    }
    if (path == failPath ||
        (failRefresh &&
            method == 'GET' &&
            path == '/api/reception/summary' &&
            mutationCount > 0)) {
      return json({}, failureStatus);
    }
    if (method != 'GET') mutationCount++;
    if (method == 'GET') {
      if (path == '/api/organization') {
        return json({'operating_mode': 'observe'});
      }
      if (path.endsWith('/room-types')) {
        return json({
          'room_types': [
            {
              'id': 'room1',
              'name': 'Test room',
              'inventory_count': 1,
              'max_guests': 4,
              'rate_plans': [
                {'id': 'rate1', 'name': 'Flexible', 'base_rate_huf': 20000},
              ],
            },
          ],
        });
      }
      if (path == '/api/reservations') return json([booking, ...extraBookings]);
      if (path.endsWith('/detail')) {
        return json({
          'reservation': booking,
          'notes': notes,
          'events': events,
          'messages': messages,
          'registration': [
            {
              'id': 'guest1',
              'full_name': 'Synthetic Guest',
              'nationality': 'HU',
              'completeness': 'complete',
              'verification_status': verification,
            },
          ],
          'cleaning': [task],
          'maintenance': [],
          'guest_profile': {
            'id': 'guest-profile',
            'full_name': 'Synthetic Guest',
            'stay_count': 2,
            'preferences': [],
          },
        });
      }
      if (path.endsWith('/channex-availability-delivery')) {
        return json({'delivered': [], 'pending': []});
      }
      if (path.endsWith('/guest-checkin-status')) {
        return json({
          'reservation_status': booking['status'],
          'registration_status': booking['registration_status'],
          'guests': [
            {
              'id': 'guest1',
              'full_name': 'Synthetic Guest',
              'completeness': 'complete',
              'verification_status': verification,
            },
          ],
        });
      }
      if (path == '/api/inbox') return json(messages);
      if (path.endsWith('/guest-checkin-links')) {
        return json({
          'links': [
            {
              'guest_name': 'Synthetic Guest',
              'completeness': 'complete',
              'url': 'http://127.0.0.1:8765/guest/checkin/synthetic-only',
            },
          ],
        });
      }
      if (path == '/api/reception/summary') {
        return json({
          'new': messages.where((m) => m['status'] == 'new').length,
          'waiting_approval': 1,
          'scheduled': outbox.length,
          'enabled_rules': rules.length,
        });
      }
      if (path == '/api/communications/outbox') return json(outbox);
      if (path == '/api/automation/rules') return json(rules);
      if (path.startsWith('/api/guests/')) {
        return json({
          'guest': {'full_name': 'Synthetic Guest'},
          'stays': [booking],
          'preferences': [],
        });
      }
    }
    final data = body is Map
        ? Map<String, dynamic>.from(body)
        : <String, dynamic>{};
    if (path.endsWith('/verify')) {
      verification = data['decision'] == 'verify' ? 'verified' : 'rejected';
      return json({'ok': true});
    }
    if (path == '/api/reservations' && method == 'POST') {
      booking = {
        ...data,
        'id': 'r2',
        'property_name': 'Test House',
        'status': 'confirmed',
      };
      return json({'id': 'r2', 'ok': true});
    }
    if (path == '/api/reservations/r1' && method == 'PATCH') {
      booking.addAll(data);
      return json({'ok': true});
    }
    if (path == '/api/reservations/r1' && method == 'DELETE') {
      booking['status'] = 'cancelled';
      return json({'ok': true});
    }
    if (path.endsWith('/operations')) {
      booking.addAll(data);
      return json({'ok': true});
    }
    if (path.endsWith('/notes')) {
      notes.add({'body': data['body'], 'author_name': 'Synthetic Owner'});
      return json({'ok': true});
    }
    if (path == '/api/inbox' && method == 'POST') {
      messages.add({
        ...data,
        'id': 'msg2',
        'status': 'new',
        'draft_reply': '',
        'analysis': {},
      });
      return json({'id': 'msg2'});
    }
    if (path.startsWith('/api/inbox/')) {
      final msg = messages.firstWhere((m) => m['id'] == uri.pathSegments[2]);
      final action = uri.pathSegments.last;
      if (action == 'analyze') {
        msg['status'] = 'analyzed';
        msg['analysis'] = {
          'extracted': {
            'arrival_time': '20:30',
            'special_requests': ['High chair'],
          },
          'unresolved': [],
        };
      }
      if (action == 'draft') {
        msg['draft_reply'] = data['draft_reply'] ?? 'Generated synthetic reply';
        msg['status'] = 'analyzed';
        return json({'draft_reply': msg['draft_reply'], 'provider': 'local'});
      }
      if (action == 'apply') {
        msg['status'] = 'actioned';
        booking['arrival_time'] = '20:30';
      }
      if (action == 'reply-sent') msg['status'] = 'replied';
      if (action == 'archive') messages.remove(msg);
      return json({'ok': true});
    }
    if (path.startsWith('/api/communications/outbox/')) {
      final entry = outbox.first;
      if (method == 'PATCH') entry.addAll(data);
      if (path.endsWith('/approve')) entry['status'] = 'ready';
      if (path.endsWith('/simulate-send')) entry['status'] = 'simulated_sent';
      return json({
        'ok': true,
        'status': entry['status'],
        'external_send': false,
      });
    }
    if (path == '/api/automation/run') return json({'created': 1});
    if (path.startsWith('/api/automation/rules/')) {
      rules.first.addAll(data);
      return json({'ok': true});
    }
    return json({}, 404);
  }
}
