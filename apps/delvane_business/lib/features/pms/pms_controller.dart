import 'package:flutter/foundation.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/localization/web_strings.dart';
export '../../core/localization/web_strings.dart';
import '../../core/network/api_client.dart';
import '../workspace/workspace_models.dart';

typedef Json = Map<String, dynamic>;

enum PmsPage {
  today,
  intelligence,
  reservations,
  inbox,
  operations,
  schedule,
  team,
  train,
  simulation,
  maintenance,
  supplies,
  integrations,
  security,
}

class PmsController extends ChangeNotifier {
  PmsController(this.auth, {PmsPage? initialPage}) {
    page =
        initialPage ??
        (user.isOperator
            ? PmsPage.intelligence
            : user.role == 'maintenance'
            ? PmsPage.maintenance
            : PmsPage.today);
  }
  final AuthController auth;
  AuthUser get user => auth.user!;
  ApiClient get api => auth.api;
  late PmsPage page;
  final WebStrings strings = WebStrings.current;
  final Map<String, Object?> data = {};
  bool loading = true, saving = false, _disposed = false;
  int _generation = 0;
  String? error, actionError;
  int unread = 0;
  String mode = 'observe';
  int receptionTab = 0;
  String? receptionSelected;
  // Unsaved text stays in this authenticated session only; never written to disk.
  final Map<String, String> receptionDrafts = {};
  List<PmsPage> get primary => user.isOperator
      ? const [
          PmsPage.today,
          PmsPage.intelligence,
          PmsPage.reservations,
          PmsPage.inbox,
          PmsPage.operations,
        ]
      : user.role == 'cleaner'
      ? const [PmsPage.today, PmsPage.schedule, PmsPage.maintenance]
      : const [PmsPage.maintenance];
  List<PmsPage> get settings => user.isOperator
      ? const [
          PmsPage.team,
          PmsPage.train,
          PmsPage.simulation,
          PmsPage.maintenance,
          PmsPage.supplies,
          PmsPage.integrations,
          PmsPage.security,
        ]
      : const [];
  bool allows(PmsPage next) =>
      primary.contains(next) || settings.contains(next);
  String label(PmsPage value) => strings.t(switch (value) {
    PmsPage.today => user.isOperator ? 'Today' : 'My day',
    PmsPage.intelligence => 'Intelligence',
    PmsPage.reservations => 'Reservations',
    PmsPage.inbox => 'Reception',
    PmsPage.operations => 'Operations',
    PmsPage.schedule => 'Schedule',
    PmsPage.team => 'Team & Access',
    PmsPage.train => 'Train Delvane',
    PmsPage.simulation => 'Simulation / Operating mode',
    PmsPage.maintenance => 'Maintenance',
    PmsPage.supplies => 'Supplies',
    PmsPage.integrations => 'Integrations',
    PmsPage.security => 'Security Center',
  });
  String t(String value) => strings.t(value);
  Json object(String key) => jsonObject(data[key]);
  List<Json> rows(String key) => jsonRows(data[key]);
  void emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> language(String value) async {
    await strings.select(value);
    emit();
  }

  Future<void> navigate(PmsPage next) async {
    if (saving || !allows(next)) return;
    page = next;
    await load();
  }

  Future<void> load() async {
    final generation = ++_generation;
    final selected = page;
    loading = true;
    error = null;
    data.clear();
    emit();
    try {
      if (strings.data.isEmpty) await strings.load();
      await auth.revalidate();
      if (_disposed || generation != _generation || auth.user == null) return;
      final paths = <String, String>{};
      switch (selected) {
        case PmsPage.today:
          if (user.isOperator) {
            paths.addAll({
              'command': '/api/operations/today-command',
              'dashboard': '/api/owner/dashboard',
            });
          } else {
            paths['worker'] = '/api/worker/dashboard';
          }
        case PmsPage.schedule:
          paths['worker'] = '/api/worker/dashboard';
        case PmsPage.intelligence:
          paths.addAll({
            'intelligence': '/api/intelligence',
            'provider': '/api/rosa/provider',
            'conversation': '/api/rosa/conversation',
          });
        case PmsPage.reservations:
          paths.addAll({
            'reservations': '/api/reservations',
            'properties': '/api/properties',
          });
        case PmsPage.inbox:
          paths.addAll({
            'summary': '/api/reception/summary',
            'inbox': '/api/inbox',
            'outbox': '/api/communications/outbox',
            'rules': '/api/automation/rules',
          });
        case PmsPage.operations:
          paths.addAll({
            'timeline': '/api/operations/timeline',
            'journeys': '/api/guest-journeys',
            'intelligence': '/api/intelligence',
          });
        case PmsPage.maintenance:
          paths.addAll({
            'maintenance': '/api/maintenance',
            'properties': user.isOperator
                ? '/api/properties'
                : '/api/operations/properties',
          });
        case PmsPage.supplies:
          paths['inventory'] = '/api/inventory';
        case PmsPage.team:
          paths['team'] = '/api/team/overview';
          paths['properties'] = '/api/properties';
        case PmsPage.train:
          paths['knowledge'] = '/api/knowledge';
        case PmsPage.simulation:
          paths.addAll({
            'organization': '/api/organization',
            'actions': '/api/rosa/actions',
            'memory': '/api/memory',
            'preferences': '/api/notifications/preferences',
          });
        case PmsPage.integrations:
          paths.addAll({
            'integrations': '/api/integrations',
            'sync': '/api/integration-sync/summary',
            'government': '/api/government/status',
            'properties': '/api/properties',
            'integrationEvents': '/api/integration-events',
          });
        case PmsPage.security:
          paths.addAll({
            'security': '/api/security',
            'audit': '/api/audit',
            'retention': '/api/retention',
            'runtime': '/api/system/runtime',
          });
      }
      final result = <String, Object?>{};
      for (final entry in paths.entries) {
        result[entry.key] = await api.get(entry.value);
        if (_disposed || generation != _generation || auth.user == null) return;
      }
      // Notifications are an independent shell utility, not a reason to fabricate a page.
      if (user.isOperator) {
        mode = text(
          jsonObject(await api.get('/api/organization')),
          'operating_mode',
        );
        try {
          final notifications = jsonObject(await api.get('/api/notifications'));
          unread = (notifications['unread'] as num?)?.toInt() ?? 0;
        } on ApiException {
          /* Notification drawer exposes its own retry state. */
        }
      }
      if (_disposed || generation != _generation || auth.user == null) return;
      data.addAll(result);
      loading = false;
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = safeError(e);
      loading = false;
    }
    emit();
  }

  Future<Object?> mutate(String method, String path, [Object? body]) async {
    // The backend remains authoritative for permissions, CSRF, modes and state.
    return switch (method) {
      'POST' => api.post(path, body ?? const {}),
      'PATCH' => api.patch(path, body ?? const {}),
      'PUT' => api.put(path, body ?? const {}),
      'DELETE' => api.delete(path),
      _ => throw ArgumentError('Unsupported mutation'),
    };
  }

  Future<bool> act(Future<void> Function() action, {bool reload = true}) async {
    if (saving) return false;
    saving = true;
    actionError = null;
    emit();
    try {
      await action();
      if (_disposed || auth.user == null) return false;
      if (reload) await load();
      return true;
    } catch (e) {
      if (!_disposed) actionError = safeError(e);
      return false;
    } finally {
      saving = false;
      emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}

String safeError(Object error) => error is ApiException
    ? error.message
    : 'The request could not be completed. Please retry.';
List<Json> optionalRows(Object? value) => value == null ? [] : jsonRows(value);
Json optionalObject(Object? value) =>
    value == null ? <String, dynamic>{} : jsonObject(value);
String idPath(String id) => Uri.encodeComponent(id);
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String displayDate(String? value) {
  if (value == null || value.isEmpty) return '—';
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  if (WebStrings.current.language == 'hu') return uiDate(value);
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
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
  return '${days[date.weekday - 1]} ${date.day} ${months[date.month - 1]}';
}
