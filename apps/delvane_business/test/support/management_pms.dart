import 'package:delvane_business/core/network/api_client.dart';

import 'workflow_pms.dart';
import 'fake_pms.dart';

class ManagementPms extends WorkflowPms {
  final rooms = <Map<String, dynamic>>[];
  late final members = <Map<String, dynamic>>[
    {
      'id': 'staff1',
      'full_name': 'Synthetic Worker',
      'email': 'worker@native.invalid',
      'role': 'cleaner',
      'active': 1,
      'upcoming_cleaning': 2,
      'open_maintenance': 0,
      'in_progress': 1,
      'completed_30d': 3,
      'email_verified': 0,
      'mfa_enabled': 0,
    },
  ];
  late final cases = <Map<String, dynamic>>[maintenance];
  final stocks = <Map<String, dynamic>>[
    {
      'id': 's1',
      'name': 'Coffee',
      'quantity': 2.5,
      'unit': 'packs',
      'par_level': 10,
      'estimated_need': 7,
      'low': true,
    },
  ];
  final groups = <String, dynamic>{
    for (final role in ['owner', 'manager', 'cleaner', 'maintenance'])
      role: {
        'groups': [
          {'label': 'Operations', 'enabled': true},
        ],
      },
  };
  bool failManagement = false;
  late final work = Map<String, dynamic>.of(task)..['status'] = 'open';
  final knowledge = <String, dynamic>{
    'properties': [],
    'fields': [
      {'key': 'parking', 'label': 'Parking', 'category': 'Arrival'},
    ],
    'scopes': {
      'shared': {'parking': 'Synthetic parking'},
    },
    'authority': {
      'send_reply': {
        'label': 'Guest replies',
        'mode': 'ask',
        'category': 'Guest communication',
      },
    },
  };
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    final path = uri.path;
    final custom =
        path.startsWith('/api/team/') ||
        path.startsWith('/api/maintenance') ||
        path.startsWith('/api/inventory') ||
        path.startsWith('/api/knowledge') ||
        path.startsWith('/api/authority/') ||
        path == '/api/worker/dashboard' ||
        path.startsWith('/api/work-tasks/') ||
        path == '/api/work-tasks' ||
        path == '/api/properties/p1/overview' ||
        path == '/api/properties/p1/room-types';
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
    if (method != 'GET' && headers['X-Rosa-CSRF'] != fakeCsrf) {
      return json({}, 403);
    }
    if (failManagement) {
      return json({'detail': 'synthetic private diagnostic'}, 503);
    }
    final operator = role == 'owner' || role == 'manager';
    if (path == '/api/work-tasks' || path.endsWith('/assignment')) {
      if (!operator) return json({}, 403);
      return json({'ok': true, 'id': 'created-work'});
    }
    if (path == '/api/worker/dashboard') {
      return json({
        'date': '2032-05-10',
        'tasks': [work],
      });
    }
    if (path.startsWith('/api/work-tasks/')) {
      if (role != 'cleaner') return json({}, 403);
      mutationCount++;
      if (path.endsWith('/start')) work['status'] = 'in_progress';
      if (path.endsWith('/finish')) {
        work['status'] = 'complete';
        work['worker_note'] = (body as Map)['note'];
      }
      if (path.contains('/checklist/')) {
        (work['checklist'] as List).first['completed'] =
            (body as Map)['completed'];
      }
      return json({'ok': true});
    }
    if (path == '/api/knowledge' && method == 'GET') return json(knowledge);
    if (path.startsWith('/api/knowledge/') ||
        path.startsWith('/api/authority/')) {
      if (!operator) return json({}, 403);
      mutationCount++;
      return json({'ok': true});
    }
    if ((path.startsWith('/api/team/') ||
            path.startsWith('/api/inventory') ||
            path.startsWith('/api/properties/')) &&
        !operator) {
      return json({}, 403);
    }
    if (path == '/api/team/overview') {
      return json({
        'members': members,
        'roles': groups,
        'stats': {
          'active': 1,
          'cleaners': 1,
          'maintenance': 0,
          'unverified': 1,
        },
        'can_manage': role == 'owner',
        'workload': [],
      });
    }
    if (path.startsWith('/api/team/members')) {
      if (role != 'owner') return json({}, 403);
      mutationCount++;
      if (path.endsWith('/reset-access') ||
          method == 'POST' && path == '/api/team/members') {
        return json({
          'member_id': 'made',
          'setup_password': 'Synthetic-ONE-TIME-123',
        });
      }
      return json({'ok': true});
    }
    if (path == '/api/properties/p1/overview') {
      return json({
        'property': property,
        'room_types': rooms,
        'cleaning': null,
        'current': null,
        'arriving_today': null,
        'departing_today': null,
        'next': null,
        'same_day_turnover': false,
      });
    }
    if (path == '/api/properties/p1/room-types') {
      if (method == 'GET') return json({'room_types': rooms});
      mutationCount++;
      rooms.add({'id': 'made', ...body as Map<String, dynamic>, 'active': 1});
      return json({'ok': true});
    }
    if (path == '/api/inventory' && method == 'GET') {
      return json({'upcoming_stays': 3, 'items': stocks});
    }
    if (path.startsWith('/api/inventory/') && method == 'PATCH') {
      mutationCount++;
      stocks.first['quantity'] = (body as Map)['quantity'];
      return json({'ok': true});
    }
    if (path == '/api/maintenance' && method == 'GET') return json(cases);
    if (path == '/api/maintenance' && method == 'POST') {
      mutationCount++;
      return json({'ok': true, 'id': 'new'});
    }
    if (path.endsWith('/status')) {
      mutationCount++;
      cases.first['status'] = (body as Map)['status'];
      return json({'ok': true});
    }
    return json({}, 404);
  }
}
