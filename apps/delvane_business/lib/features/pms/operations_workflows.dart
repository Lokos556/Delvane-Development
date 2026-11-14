import '../workspace/workspace_models.dart';
import 'pms_controller.dart';

/// Native controls enforce the same role boundaries; the server remains authoritative.
class OperationsWorkflows {
  OperationsWorkflows(this.c);
  final PmsController c;
  void operatorOnly() {
    if (!c.user.isOperator) throw StateError('Operator access required');
  }

  void ownerOnly() {
    if (c.user.role != 'owner') throw StateError('Owner access required');
  }

  Future<Json> member(Json values, {String? id}) async {
    ownerOnly();
    return jsonObject(
      await c.mutate(
        id == null ? 'POST' : 'PATCH',
        '/api/team/members${id == null ? '' : '/${idPath(id)}'}',
        values,
      ),
    );
  }

  Future<Json> access(String id, {required bool reset}) async {
    ownerOnly();
    if (id == c.user.id) throw StateError('Use your own account controls');
    return jsonObject(
      await c.mutate(
        'POST',
        '/api/team/members/${idPath(id)}/${reset ? 'reset-access' : 'revoke-sessions'}',
      ),
    );
  }

  Future<void> maintenance(Json values) async {
    if (!['owner', 'manager', 'cleaner'].contains(c.user.role)) {
      throw StateError('Cannot report maintenance');
    }
    await c.mutate('POST', '/api/maintenance', values);
  }

  Future<void> maintenanceStatus(Json item, String status) async {
    if (!c.user.isOperator && c.user.role != 'maintenance') {
      throw StateError('Cannot change maintenance status');
    }
    if (!c.user.isOperator &&
        (status == 'verified' ||
            (item['assigned_to'] != null &&
                item['assigned_to'] != c.user.id))) {
      throw StateError('Cannot change this case');
    }
    await c.mutate(
      'PATCH',
      '/api/maintenance/${idPath(text(item, 'id'))}/status',
      {'status': status},
    );
  }

  Future<void> createCleaning(Json values) async {
    operatorOnly();
    await c.mutate('POST', '/api/work-tasks', values);
  }

  Future<void> assign(Json work, String assignee) async {
    operatorOnly();
    if (work['kind'] == 'maintenance') {
      await c.mutate(
        'PATCH',
        '/api/maintenance/${idPath(text(work, 'id'))}/status',
        {
          'status': ['reported', 'assigned', 'open'].contains(work['status'])
              ? (assignee.isEmpty ? 'reported' : 'assigned')
              : work['status'],
          'assigned_to': assignee,
        },
      );
    } else {
      await c.mutate(
        'PATCH',
        '/api/work-tasks/${idPath(text(work, 'id'))}/assignment',
        {'assigned_to': assignee.isEmpty ? null : assignee},
      );
    }
  }

  Future<void> stock(String id, num quantity) async {
    operatorOnly();
    await c.mutate('PATCH', '/api/inventory/${idPath(id)}', {
      'quantity': quantity,
    });
  }

  Future<void> finish(Json task, String note) async {
    if (!['cleaner', 'maintenance'].contains(c.user.role) ||
        task['assigned_to'] != c.user.id) {
      throw StateError('Assigned worker required');
    }
    await c.mutate(
      'POST',
      '/api/work-tasks/${idPath(text(task, 'id'))}/finish',
      {'note': note},
    );
  }
}
