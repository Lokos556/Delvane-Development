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
    const messages = {
      "guest_records_review_required": "Review the registered guests before reducing the guest count. Submitted identity records cannot be removed automatically.",
      "registration_review_required": "Complete the guest data and identity review first. Registration status cannot be set manually.",

      'availability_conflict': 'The selected room has no availability for these dates. Choose another room or change the dates.',
      'invalid_dates': 'Enter valid arrival and departure dates.',
      'departure_not_after_arrival': 'Departure must be later than arrival.',
      'guest_name_required': 'Enter the guest name.',
      'invalid_guest_count': 'Enter a positive whole guest count.',
      'capacity_exceeded': 'The guest count exceeds this room’s capacity. Choose a larger room or reduce the guest count.',
      'property_unavailable':
          'This property is unavailable. Refresh and select another property.',
      'room_unavailable': 'This room is unavailable for the selected property. Refresh and select a room.',
      'reservation_not_found': 'This reservation no longer exists or you cannot access it. Refresh the reservation list.',
      'invalid_fields': 'Check the required fields and their formats.',
      'guest_profile_unavailable': 'This guest profile is unavailable. Refresh and choose another profile.',
    };
    if (messages.containsKey(error.code)) return messages[error.code]!;
    if ((error.statusCode ?? 0) >= 500) {
      return 'The server could not complete the request. Refresh before trying again.';
    }
    return switch (error.statusCode) {
      400 => 'The server rejected these values. Check dates, capacity and required fields.',
      409 => 'This change conflicts with the current record or availability. Refresh and review before retrying.',
      422 => 'Some fields have invalid values. Check the form and try again.',
      _ => error.message,
    };
  }
  return safeError(error);
}
