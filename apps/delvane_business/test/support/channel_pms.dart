import 'package:delvane_business/core/network/api_client.dart';
import 'fake_pms.dart';
import 'management_pms.dart';

/// No sockets; every channel/provider record here is synthetic test data.
class ChannelPms extends ManagementPms {
  bool failInventory = false, failFeed = false, failWrite = false;
  bool outage = false;
  String remoteProperty = 'remote-property';
  late final roomTypes = <Map<String, dynamic>>[
    {
      'id': 'room1',
      'name': 'Twin',
      'active': 1,
      'inventory_count': 2,
      'max_guests': 2,
    },
  ];
  late final plans = <Map<String, dynamic>>[
    {'id': 'plan1', 'room_type_id': 'room1', 'name': 'Standard', 'active': 1},
  ];
  final queueItems = <Map<String, dynamic>>[
    {
      'id': 'q1',
      'status': 'retry',
      'attempts': 1,
      'endpoint_label': 'Availability',
      'retry_due': true,
      'last_error': 'Synthetic throttle',
    },
  ];
  late final integrations = <Map<String, dynamic>>[
    {
      'id': 'i1',
      'property_id': 'p1',
      'property_name': 'Test House',
      'provider': 'Booking.com',
      'connection_stage': 'channex_ready',
      'receiver_state': 'setup_required',
      'distribution_state': 'setup_required',
      'public_config': {
        'channex_environment': 'staging',
        'certification_workspace': true,
      },
    },
  ];
  final feed = <Map<String, dynamic>>[];
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    final path = uri.path;
    final custom =
        path.startsWith('/api/integrations') ||
        path == '/api/integration-events' ||
        path == '/api/integration-sync/summary' ||
        path == '/api/government/status' ||
        path == '/api/properties/p1/rate-plans' ||
        path == '/api/guests/g1/preferences';
    if (!custom) return super.request(method, uri, headers, body);
    requests.add((
      method: method,
      path: path,
      headers: Map.of(headers),
      body: body,
    ));
    if (revoked || headers['Cookie'] != 'rosa_session=$fakeCookie') {
      return json({}, 401);
    }
    if (!['owner', 'manager'].contains(role)) return json({}, 403);
    if (method != 'GET' && headers['X-Rosa-CSRF'] != fakeCsrf) {
      return json({}, 403);
    }
    if (method != 'GET' && failWrite) {
      return json({'detail': 'private diagnostic'}, 503);
    }
    if (path == '/api/government/status') {
      return json({
        'rosa_mtu_certified': false,
        'queue': [
          {'system': 'VIZA', 'status': 'awaiting_certification', 'count': 1},
        ],
      });
    }
    if (path == '/api/integration-sync/summary') return json({});
    if (path == '/api/integration-events') return json([]);
    if (path == '/api/integrations') {
      if (method == 'GET') return json(integrations);
      if (role != 'owner') return json({}, 403);
      mutationCount++;
      return json({'id': 'new'});
    }
    if (path == '/api/properties/p1/rate-plans') {
      if (method == 'GET') return json({'rate_plans': plans});
      mutationCount++;
      return json({'rate_plan_id': 'created', 'ok': true});
    }
    if (path == '/api/guests/g1/preferences') {
      mutationCount++;
      return json({'ok': true});
    }
    final suffix = path.replaceFirst('/api/integrations/i1', '');
    if (suffix == '/channex/inventory-mapping') {
      if (method == 'PUT') {
        mutationCount++;
        return json({'room_count': 1, 'rate_count': 1});
      }
      if (failInventory) return json({}, 503);
      final selected =
          uri.queryParameters['channex_property_id'] ?? remoteProperty;
      return json({
        'selected_channex_property_id': selected,
        'properties': [
          {'id': 'remote-property', 'title': 'Synthetic staging'},
          {'id': 'other-property', 'title': 'Other staging'},
        ],
        'local_room_types': roomTypes,
        'local_rate_plans': plans,
        'remote_room_types': [
          {'id': 'remote-room', 'title': 'Remote twin', 'count_of_rooms': 2},
          {'id': 'other-room', 'title': 'Other room', 'count_of_rooms': 2},
        ],
        'remote_rate_plans': [
          {
            'id': 'remote-rate',
            'title': 'Remote standard',
            'room_type_id': 'remote-room',
          },
          {
            'id': 'other-rate',
            'title': 'Other standard',
            'room_type_id': 'other-room',
          },
        ],
        'room_mappings': [
          {'room_type_id': 'room1', 'channex_room_type_id': 'remote-room'},
        ],
        'rate_mappings': [
          {
            'rate_plan_id': 'plan1',
            'channex_room_type_id': 'remote-room',
            'channex_rate_plan_id': 'remote-rate',
          },
        ],
      });
    }
    if (suffix == '/channex/ari' && method == 'GET') {
      return json({
        'currency': 'USD',
        'certification_workspace': true,
        'room_types': roomTypes,
        'values': [],
        'outbox': {'retry': 1},
        'base_rate': null,
      });
    }
    if (suffix == '/channex/rate-mappings') {
      return json([
        {
          'rate_plan_id': 'plan1',
          'rate_plan_name': 'Standard',
          'room_type_name': 'Twin',
          'channex_rate_plan_id': 'remote-rate',
        },
      ]);
    }
    if (suffix == '/channex/outbox') return json({'items': queueItems});
    if (suffix == '/channex/outbox/retry') {
      mutationCount++;
      return json({
        'queue': {'items': queueItems},
        'delivery': {
          'delivered': [],
          'failed': [
            {'error': 'Synthetic throttle'},
          ],
        },
      });
    }
    if (suffix.startsWith('/channex/') && method != 'GET') {
      mutationCount++;
      return json({
        'ok': false,
        'days': suffix.endsWith('full-sync') ? 500 : 7,
        'queued': 2,
        'delivery': {
          'delivered': [],
          'failed': [
            {'error': 'Synthetic throttle'},
          ],
        },
      });
    }
    if (suffix == '/feed') {
      if (failFeed) return json({}, 503);
      return json({
        'integration': {
          ...integrations.first,
          'public_config': {'sandbox_outage': outage},
        },
        'items': feed,
      });
    }
    if (suffix == '/sync/preview') {
      return json({
        'counts': {
          'new': 1,
          'changed': 0,
          'cancelled': 0,
          'conflict': 0,
          'unchanged': 0,
        },
        'changes': [
          {
            'kind': 'new',
            'guest_name': 'Synthetic feed',
            'property_name': 'Test House',
          },
        ],
      });
    }
    if (suffix == '/sync/apply') {
      mutationCount++;
      return json({
        'counts': {'applied': 1, 'skipped': 0},
      });
    }
    if (suffix.startsWith('/sandbox/')) {
      mutationCount++;
      if (suffix.endsWith('/outage')) outage = true;
      if (suffix.endsWith('/recover')) outage = false;
      return json({'ok': true});
    }
    return json({}, 404);
  }
}
