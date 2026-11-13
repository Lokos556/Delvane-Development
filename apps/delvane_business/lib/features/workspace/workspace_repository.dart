import '../../core/auth/auth_controller.dart';
import '../../core/localization/web_strings.dart';
import '../../core/network/api_client.dart';
import 'workspace_models.dart';

/// Read-oriented native workflows. Provider APIs and guest vaults are never called.
class WorkspaceRepository {
  WorkspaceRepository(this.api);
  final ApiClient api;
  final Map<String, OperationalItem> _authorizedTasks = {};

  OperationalItem _stay(
    Map<String, dynamic> row,
    String operation,
  ) => OperationalItem(
    ref: RecordRef(RecordKind.reservation, recordId(row)),
    propertyId: recordId(row, 'property_id'),
    title: text(row, 'guest_name', 'Guest'),
    detail:
        '$operation · ${text(row, 'arrival_time', text(row, operation == 'Departure' ? 'checkout_time' : 'checkin_time', 'Time not provided'))}',
    status: text(row, 'registration_status', operation),
    fields: {
      'Property': text(row, 'property_name'),
      'Operation': operation,
      if (row['arrival_date'] != null) 'Arrival': text(row, 'arrival_date'),
    },
  );
  OperationalItem _task(Map<String, dynamic> row) => OperationalItem(
    ref: RecordRef(RecordKind.cleaning, recordId(row)),
    propertyId: recordId(row, 'property_id'),
    title: 'Cleaning turnover',
    detail:
        '${text(row, 'scheduled_date')} · due ${text(row, 'deadline_time', 'not set')} · ${text(row, 'assigned_name', 'Unassigned')}',
    status: text(row, 'status'),
    urgent: row['priority'] == 'high' && row['status'] != 'complete',
    fields: {
      'Scheduled': text(row, 'scheduled_date'),
      'Earliest start': text(row, 'earliest_time'),
      'Deadline': text(row, 'deadline_time'),
      'Assigned to': text(row, 'assigned_name', 'Unassigned'),
      'Worker note': text(row, 'worker_note'),
      if (row['next_guest_count'] != null)
        'Next guests': text(row, 'next_guest_count'),
      if (row['next_arrival'] != null)
        'Next arrival':
            '${text(row, 'next_arrival')} ${text(row, 'next_arrival_time')}',
      if (row['special_requests'] is List)
        'Preparation': (row['special_requests'] as List).join(' · '),
    },
  );
  OperationalItem _maintenance(Map<String, dynamic> row) => OperationalItem(
    ref: RecordRef(RecordKind.maintenance, recordId(row)),
    propertyId: recordId(row, 'property_id'),
    title: text(row, 'title'),
    detail:
        '${text(row, 'severity')} severity · ${text(row, 'assigned_name', 'Unassigned')}',
    status: text(row, 'status'),
    urgent:
        row['severity'] == 'high' &&
        !{'resolved', 'verified'}.contains(row['status']),
    fields: {
      'Description': text(row, 'detail'),
      'Severity': text(row, 'severity'),
      'Assigned to': text(row, 'assigned_name', 'Unassigned'),
      'Due': text(row, 'due_at'),
      'Reported': text(row, 'created_at'),
      'Resolved': text(row, 'resolved_at'),
    },
  );

  Future<OperationalWorkspace> load(AuthUser user) async {
    _authorizedTasks.clear();
    final command = jsonObject(
      await api.get(
        user.isOperator
            ? '/api/operations/today-command'
            : '/api/worker/dashboard',
      ),
    );
    final propertyRows = jsonRows(
      await api.get(
        user.isOperator ? '/api/properties' : '/api/operations/properties',
      ),
    );
    final cases = jsonRows(
      await api.get('/api/maintenance'),
    ).map(_maintenance).toList();
    final date = recordId(command, 'date');
    DateTime.parse(
      date,
    ); // Invalid server calendar data is an error, never "today".
    final readiness = user.isOperator
        ? jsonRows(
            jsonObject(await api.get('/api/owner/dashboard'))['properties'],
          )
        : <Map<String, dynamic>>[];
    final properties = propertyRows.map((row) {
      final id = recordId(row);
      final ready = readiness.where((r) => r['id'] == id).firstOrNull;
      return OperationalProperty(
        id,
        text(row, 'name'),
        text(row, 'checkin_time'),
        text(row, 'checkout_time'),
        state: ready?['state'] as String?,
        reasons: ready == null
            ? const []
            : (ready['reasons'] as List).cast<String>(),
      );
    }).toList();
    final cleaning = jsonRows(command[user.isOperator ? 'cleaning' : 'tasks'])
        .where((row) => user.isOperator || user.role == 'cleaner')
        .map(
          (row) => _task(
            user.isOperator
                ? row
                : {...row, 'assigned_name': row['assigned_name'] ?? user.name},
          ),
        )
        .toList();
    for (final task in cleaning) {
      _authorizedTasks[task.ref.id] = task;
    }
    final arrivals = user.isOperator
        ? jsonRows(command['arrivals']).map((r) => _stay(r, 'Arrival')).toList()
        : <OperationalItem>[];
    final departures = user.isOperator
        ? jsonRows(
            command['departures'],
          ).map((r) => _stay(r, 'Departure')).toList()
        : <OperationalItem>[];
    final registration = user.isOperator
        ? jsonRows(command['registration_risks'])
              .map(
                (r) => OperationalItem(
                  ref: RecordRef(RecordKind.reservation, recordId(r)),
                  propertyId: recordId(r, 'property_id'),
                  title: text(r, 'guest_name'),
                  detail:
                      'Arrives ${text(r, 'arrival_date')} · identity review may be required',
                  status: text(r, 'registration_status'),
                  urgent: true,
                ),
              )
              .toList()
        : <OperationalItem>[];
    final activeCases = cases
        .where((r) => !{'resolved', 'verified'}.contains(r.status))
        .toList();
    final priorities = [
      ...registration,
      ...cleaning.where((r) => r.urgent),
      ...activeCases.where((r) => r.urgent),
    ];
    return OperationalWorkspace(
      date: date,
      properties: properties,
      arrivals: arrivals,
      departures: departures,
      cleaning: cleaning,
      maintenance: activeCases,
      registration: registration,
      priorities: priorities,
    );
  }

  Future<List<OperationalItem>> reservations(AuthUser user) async {
    if (!user.isOperator || !user.permissions.contains('reservations.read')) {
      throw const ApiException(
        'Reservation access is restricted.',
        statusCode: 403,
      );
    }
    return jsonRows(await api.get('/api/reservations'))
        .map(
          (r) => OperationalItem(
            ref: RecordRef(RecordKind.reservation, recordId(r)),
            propertyId: recordId(r, 'property_id'),
            title: text(r, 'guest_name'),
            detail:
                '${text(r, 'arrival_date')} → ${text(r, 'departure_date')} · ${text(r, 'source')}',
            status: text(r, 'status'),
          ),
        )
        .toList();
  }

  Future<RecordDetail> detail(
    AuthUser user,
    RecordRef ref,
    OperationalWorkspace workspace,
  ) async {
    final id = Uri.encodeComponent(ref.id);
    switch (ref.kind) {
      case RecordKind.reservation:
        if (!user.isOperator ||
            !user.permissions.contains('reservations.read')) {
          throw const ApiException(
            'Reservation access is restricted.',
            statusCode: 403,
          );
        }
        final response = jsonObject(
          await api.get('/api/reservations/$id/detail'),
        );
        final r = jsonObject(response['reservation']);
        for (final row in jsonRows(response['cleaning'])) {
          final task = _task(row);
          _authorizedTasks[task.ref.id] = task;
        }
        return RecordDetail(
          text(r, 'guest_name'),
          {
            'Reference': recordId(r),
            'Property': text(r, 'property_name'),
            'Arrival': '${text(r, 'arrival_date')} ${text(r, 'arrival_time')}',
            'Departure': text(r, 'departure_date'),
            'Status': text(r, 'status'),
            'Registration': text(r, 'registration_status'),
            'Guests': text(r, 'guest_count'),
            'Source': text(r, 'source'),
            'Reservation amount (HUF)': text(r, 'total_huf'),
            'Payment label': text(r, 'payment_status'),
            'Requests': r['special_requests'] is String
                ? text(r, 'special_requests')
                : '',
          },
          links: [
            (
              label: ui('Open property'),
              ref: RecordRef(RecordKind.property, recordId(r, 'property_id')),
            ),
            ...jsonRows(response['cleaning']).map(
              (t) => (
                label: ui('Cleaning · ${uiDate(text(t, 'scheduled_date'))}'),
                ref: RecordRef(RecordKind.cleaning, recordId(t)),
              ),
            ),
          ],
        );
      case RecordKind.property:
        final prop = workspace.properties
            .where((p) => p.id == ref.id)
            .firstOrNull;
        if (prop == null) {
          throw const ApiException(
            'This property is outside your workspace.',
            statusCode: 403,
          );
        }
        if (!user.isOperator) {
          return RecordDetail(prop.name, {
            'Check-in': prop.checkin,
            'Checkout': prop.checkout,
            'Access':
                'Operational context only. Guest and readiness details are restricted.',
          });
        }
        final body = jsonObject(await api.get('/api/properties/$id/overview'));
        final p = jsonObject(body['property']);
        if (body['cleaning'] is Map<String, dynamic>) {
          final task = _task(jsonObject(body['cleaning']));
          _authorizedTasks[task.ref.id] = task;
        }
        return RecordDetail(
          text(p, 'name'),
          {
            'Address': text(p, 'address'),
            'Check-in': text(p, 'checkin_time'),
            'Checkout': text(p, 'checkout_time'),
            'Guest capacity': text(p, 'max_guests'),
            'Readiness': prop.state ?? 'Not provided',
            'Reasons': prop.reasons.join(' · '),
            'Same-day turnover': body['same_day_turnover'] == true
                ? 'Yes'
                : 'No',
          },
          links: [
            for (final key in [
              'current',
              'arriving_today',
              'departing_today',
              'next',
            ])
              if (body[key] is Map<String, dynamic>)
                (
                  label: ui('${key.replaceAll('_', ' ')} stay'),
                  ref: RecordRef(
                    RecordKind.reservation,
                    recordId(jsonObject(body[key])),
                  ),
                ),
            if (body['cleaning'] is Map<String, dynamic>)
              (
                label: ui('Cleaning turnover'),
                ref: RecordRef(
                  RecordKind.cleaning,
                  recordId(jsonObject(body['cleaning'])),
                ),
              ),
          ],
        );
      case RecordKind.cleaning:
        if (user.role == 'maintenance') {
          throw const ApiException(
            'Cleaning access is restricted.',
            statusCode: 403,
          );
        }
        // Resolve from authorized lists, never arbitrary checklist IDs for workers.
        var task = _authorizedTasks[ref.id];
        List<Map<String, dynamic>>? workerChecklist;
        if (!user.isOperator) {
          final fresh = jsonObject(await api.get('/api/worker/dashboard'));
          final row = jsonRows(
            fresh['tasks'],
          ).where((r) => r['id'] == ref.id).firstOrNull;
          task = row == null
              ? null
              : _task({
                  ...row,
                  'assigned_name': row['assigned_name'] ?? user.name,
                });
          if (row != null) workerChecklist = jsonRows(row['checklist']);
        }
        if (task == null) {
          throw const ApiException(
            'Task is outside the loaded schedule. Refresh Today or use the web PMS.',
            statusCode: 404,
          );
        }
        final checklist =
            workerChecklist ??
            jsonRows(await api.get('/api/work-tasks/$id/checklist'));
        return RecordDetail(
          'Cleaning · ${workspace.propertyName(task.propertyId)}',
          {'Status': task.status, ...task.fields},
          checklist: checklist
              .map(
                (r) => (
                  label: text(r, 'label'),
                  completed: r['completed'] == true || r['completed'] == 1,
                ),
              )
              .toList(),
          links: [
            (
              label: ui('Open property'),
              ref: RecordRef(RecordKind.property, task.propertyId),
            ),
          ],
        );
      case RecordKind.maintenance:
        final rows = jsonRows(await api.get('/api/maintenance'));
        final match = rows.where((row) => row['id'] == ref.id).firstOrNull;
        if (match == null) {
          throw const ApiException(
            'Case is no longer in your workspace.',
            statusCode: 404,
          );
        }
        final item = _maintenance(match);
        return RecordDetail(
          item.title,
          {'Status': item.status, ...item.fields},
          links: [
            (
              label: ui('Open property'),
              ref: RecordRef(RecordKind.property, item.propertyId),
            ),
          ],
        );
    }
  }
}
