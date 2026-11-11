import 'dart:convert';
import 'package:delvane_business/core/auth/auth_controller.dart';
import 'package:delvane_business/core/auth/session_store.dart';
import 'package:delvane_business/core/network/api_client.dart';

class MemorySessionStore implements SessionStore {
  final values = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

const fakeCookie = 'synthetic_session_01234567890123456789';
const fakeCsrf = 'synthetic_csrf_0123456789';
final fakeNow = DateTime.utc(2032, 5, 10, 9);

class FakePms implements ApiTransport {
  String role = 'owner';
  String workspaceId = 'disposable-workspace-1';
  bool isolated = true, revoked = false, empty = false, closed = false;
  int? loginFailure;
  final overrides = <String, ApiResponse>{};
  Future<ApiResponse>? delayedCommand;
  final requests =
      <
        ({
          String method,
          String path,
          Map<String, String> headers,
          Object? body,
        })
      >[];
  Map<String, dynamic> get identity => {
    'id': 'user-$role',
    'full_name': 'Synthetic ${role.toUpperCase()}',
    'role': role,
    'organization_id': 'org-test',
    'organization_name': 'Test hospitality',
    'csrf_token': fakeCsrf,
    'permissions': [
      if (role == 'owner' || role == 'manager') 'reservations.read',
      'maintenance.read',
    ],
  };
  Map<String, dynamic> get property => {
    'id': 'p1',
    'name': 'Test House',
    'address': 'Synthetic address',
    'checkin_time': '15:00',
    'checkout_time': '10:00',
    'max_guests': 4,
  };
  Map<String, dynamic> get stay => {
    'id': 'r1',
    'property_id': 'p1',
    'property_name': 'Test House',
    'guest_name': 'Synthetic Guest',
    'arrival_date': '2032-05-10',
    'departure_date': '2032-05-12',
    'arrival_time': '16:00',
    'checkin_time': '15:00',
    'checkout_time': '10:00',
    'status': 'confirmed',
    'registration_status': 'incomplete',
    'guest_count': 2,
    'source': 'Direct',
    'total_huf': 9007199254740993,
    'payment_status': 'unpaid',
    'special_requests': '[]',
  };
  Map<String, dynamic> get task => {
    'id': 't1',
    'property_id': 'p1',
    'property_name': 'Test House',
    'scheduled_date': '2032-05-10',
    'deadline_time': '14:00',
    'earliest_time': '10:00',
    'priority': 'high',
    'status': 'pending',
    'assigned_name': 'Synthetic Cleaner',
    'assigned_to': 'user-cleaner',
    'worker_note': '',
    'next_reservation_id': 'r1',
    'checklist': [checkItem],
    'next_guest_count': 2,
    'next_arrival': '2032-05-10',
    'special_requests': ['Prepare cot'],
  };
  Map<String, dynamic> get checkItem => {
    'id': 'check1',
    'label': 'Inspect linen',
    'completed': 0,
  };
  Map<String, dynamic> get maintenance => {
    'id': 'm1',
    'property_id': 'p1',
    'property_name': 'Test House',
    'title': 'Synthetic tap repair',
    'detail': 'Replace washer',
    'severity': 'high',
    'status': 'assigned',
    'assigned_name': 'Synthetic Maintenance',
    'assigned_to': 'user-maintenance',
  };
  ApiResponse json(Object value, [int code = 200]) =>
      ApiResponse(code, jsonEncode(value));

  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    final path = uri.path;
    requests.add((
      method: method,
      path: path,
      headers: Map.of(headers),
      body: body,
    ));
    if (overrides.containsKey(path)) return overrides[path]!;
    if (path == '/api/development/workspace') {
      return json({'isolated': isolated, 'workspace_id': workspaceId});
    }
    if (path == '/api/login') {
      if (loginFailure != null) {
        return json({'detail': 'private failure'}, loginFailure!);
      }
      return ApiResponse(
        200,
        '{"ok":true,"csrf_token":"$fakeCsrf"}',
        setCookies: [
          'rosa_session=$fakeCookie; HttpOnly; Max-Age=604800; Path=/; SameSite=lax',
        ],
      );
    }
    if (revoked || headers['Cookie'] != 'rosa_session=$fakeCookie') {
      return json({}, 401);
    }
    if (path == '/api/me') return json(identity);
    if (path == '/api/logout') {
      if (headers['X-Rosa-CSRF'] != fakeCsrf) return json({}, 403);
      revoked = true;
      return json({'ok': true});
    }
    final operator = role == 'owner' || role == 'manager';
    if (!operator &&
        (path.startsWith('/api/reservations') ||
            path == '/api/owner/dashboard' ||
            path == '/api/properties' ||
            path == '/api/operations/today-command')) {
      return json({}, 403);
    }
    if (path == '/api/operations/today-command') {
      if (delayedCommand != null) return delayedCommand!;
      return json({
        'date': '2032-05-10',
        'arrivals': empty ? [] : [stay],
        'departures': [],
        'cleaning': empty ? [] : [task],
        'maintenance': empty ? [] : [maintenance],
        'registration_risks': empty ? [] : [stay],
      });
    }
    if (path == '/api/worker/dashboard') {
      return json({
        'date': '2032-05-10',
        'tasks': empty || role == 'maintenance' ? [] : [task],
      });
    }
    if (path == '/api/maintenance') return json(empty ? [] : [maintenance]);
    if (path == '/api/properties' || path == '/api/operations/properties') {
      return json(empty ? [] : [property]);
    }
    if (path == '/api/owner/dashboard') {
      return json({
        'properties': empty
            ? []
            : [
                {
                  'id': 'p1',
                  'name': 'Test House',
                  'state': 'attention',
                  'reasons': ['Guest registration incomplete'],
                },
              ],
        'worker_tasks': [task],
      });
    }
    if (path == '/api/reservations') return json(empty ? [] : [stay]);
    if (path == '/api/reservations/r1/detail') {
      return json({
        'reservation': stay,
        'cleaning': [task],
      });
    }
    if (path == '/api/properties/p1/overview') {
      return json({
        'property': property,
        'cleaning': task,
        'current': stay,
        'next': stay,
        'same_day_turnover': true,
      });
    }
    if (path == '/api/work-tasks/t1/checklist') return json([checkItem]);
    return json({}, 404);
  }

  @override
  void close() {
    closed = true;
  }
}

AuthController makeAuth(
  FakePms pms, [
  MemorySessionStore? store,
  DateTime Function()? clock,
]) => AuthController(
  origin: Uri.parse('http://127.0.0.1:8765'),
  transport: pms,
  store: store ?? MemorySessionStore(),
  clock: clock ?? () => fakeNow,
);
Future<AuthController> signedIn(
  FakePms pms, [
  MemorySessionStore? store,
]) async {
  final auth = makeAuth(pms, store);
  await auth.restore();
  await auth.signIn('synthetic@workspace.invalid', 'synthetic-test-password');
  return auth;
}
