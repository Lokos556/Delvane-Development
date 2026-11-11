import '../../core/network/api_client.dart';
import '../workspace/workspace_models.dart';
import 'pms_controller.dart';

/// Existing PMS API contracts only. No client inventory engine or send adapter.
class PmsWorkflows {
  PmsWorkflows(this.controller);
  final PmsController controller;
  void authorize() {
    if (controller.auth.user?.isOperator != true) {
      throw const ApiException(
        'You do not have access to this area.',
        statusCode: 403,
      );
    }
  }

  Future<Object?> get(String path) {
    authorize();
    return controller.api.get(path);
  }

  Future<Json> object(String path) async => jsonObject(await get(path));
  Future<List<Json>> rows(String path) async => jsonRows(await get(path));
  Future<Object?> change(String method, String path, [Object? body]) {
    authorize();
    return controller.mutate(method, path, body);
  }

  Future<Json> detail(String id) =>
      object('/api/reservations/${idPath(id)}/detail');
  Future<List<Json>> rooms(String id) async => optionalRows(
    (await object('/api/properties/${idPath(id)}/room-types'))['room_types'],
  );
  Future<Object?> save(Json body, {String? id}) => change(
    id == null ? 'POST' : 'PATCH',
    id == null ? '/api/reservations' : '/api/reservations/${idPath(id)}',
    body,
  );
  Future<Object?> cancel(String id) =>
      change('DELETE', '/api/reservations/${idPath(id)}');
  Future<Object?> confirm(String id) => change(
    'PATCH',
    '/api/reservations/${idPath(id)}',
    {'status': 'confirmed'},
  );
  Future<Object?> operations(String id, Json body) =>
      change('PATCH', '/api/reservations/${idPath(id)}/operations', body);
  Future<Object?> note(String id, String body) =>
      change('POST', '/api/reservations/${idPath(id)}/notes', {'body': body});
  Future<Object?> messageAction(String id, String action, [Json? body]) =>
      change(
        action == 'save-draft' ? 'PATCH' : 'POST',
        '/api/inbox/${idPath(id)}/${action == 'save-draft' ? 'draft' : action}',
        body,
      );
}

String workflowError(Object error) {
  if (error is ApiException) {
    return switch (error.statusCode) {
      400 =>
        'The server rejected these values. Check dates, capacity and required fields.',
      409 =>
        'This change conflicts with the current record or availability. Refresh and review before retrying.',
      422 => 'Some fields have invalid values. Check the form and try again.',
      _ => error.message,
    };
  }
  return safeError(error);
}
