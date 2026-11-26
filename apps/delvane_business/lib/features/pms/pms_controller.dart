import 'dart:async';

import 'chat_session.dart';

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
  PmsController(this.auth, {PmsPage? initialPage, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _scope = _authScope;
    _wasOffline = auth.offline;
    _invalidateOnMutation = _invalidateReads;
    api.onMutation = _invalidateOnMutation;
    auth.addListener(_authChanged);
    page =
        initialPage ??
        (user.isOperator
            ? PmsPage.today
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
  late final chat = PmsChatSession(
    api,
    emit,
    canRead: () => auth.user?.isOperator == true,
  );
  String? chatRefreshError;
  static const _freshFor = Duration(seconds: 25);
  static const syncInterval = Duration(seconds: 20);
  static const _identityFreshFor = Duration(minutes: 1);
  final DateTime Function() _clock;
  final Map<String, (Object?, DateTime)> _reads = {};
  final Map<String, Future<Object?>> _pending = {};
  late final VoidCallback _invalidateOnMutation;
  late (String, String, String, String)? _scope;
  bool _wasOffline = false;
  bool _foregroundRefreshDue = false;
  Map<String, (Object, DateTime)> offlineData = {};
  int _readGeneration = 0;
  Future<void>? _identityRequest;
  DateTime? _identityChecked;
  bool refreshing = false;
  final Map<String, String> sectionErrors = {};
  ApiFailure? connectionIssue;

  bool get isUat =>
      auth.workspaceId?.startsWith('staging:delvane-uat-') == true;
  bool hasSection(String key) => data.containsKey(key);
  int get readRevision => _readGeneration;
  (String, String, String, String)? get _authScope => switch (auth.user) {
    final identity? => (
      identity.id,
      identity.organizationId,
      identity.role,
      (identity.permissions.toList()..sort()).join(','),
    ),
    null => null,
  };

  String propertyLabel(String name) => !isUat
      ? name
      : switch (name) {
          'prop_uat_a' => t('Reporting apartment'),
          'prop_uat_sibling' => t('Second apartment'),
          _ => name,
        };

  String get roleLabel => t(switch (user.role) {
    'owner' => 'Owner',
    'manager' => 'Manager',
    'cleaner' => 'Cleaner',
    'maintenance' => 'Maintenance',
    _ => user.role,
  });

  String get modeLabel => t(mode == 'observe' ? 'Observer mode' : mode);

  String activityLabel(Json event) {
    final message = text(event, 'message');
    final actor = text(event, 'actor');
    final prefix = '$actor added ';
    if (!isUat || actor.isEmpty || !message.startsWith(prefix)) return message;
    final booking = RegExp(
      r'^(.+) to (prop_uat_a|prop_uat_sibling) \((\d{4}-\d{2}-\d{2})–(\d{4}-\d{2}-\d{2})\)\.$',
    ).firstMatch(message.substring(prefix.length));
    if (booking == null) return message;
    return t(
      '$actor added ${booking[1]} to ${propertyLabel(booking[2]!)} '
      '(${uiDate(booking[3]!)}–${uiDate(booking[4]!)}).',
    );
  }

  List<Json> get activity => rows('timeline').where((event) {
    // The backend appends these demo-only rows to every timeline response.
    return !const {'sys1', 'sys2', 'sys3'}.contains(event['id']);
  }).toList();

  void _authChanged() {
    final scope = _authScope;
    if (_scope == scope) {
      if (auth.offline && !_wasOffline) {
        _invalidateReads();
        for (final key in ['inbox', 'summary', 'outbox', 'rules']) {
          data.remove(key);
        }
        unawaited(_loadOffline());
      }
      _wasOffline = auth.offline;
      emit();
      return;
    }
    _scope = scope;
    _foregroundRefreshDue = false;
    _wasOffline = auth.offline;
    _identityChecked = null;
    _invalidateReads();
    data.clear();
    offlineData.clear();
    receptionDrafts.clear();
    receptionSelected = null;
    receptionQuery = '';
    chat.invalidateAccess();
    ++_generation;
    if (scope != null) {
      if (!allows(page)) page = primary.first;
      unawaited(load());
    }
  }

  Future<void> _loadOffline() async {
    final scope = auth.cacheScope;
    if (scope == null) return;
    final paths = switch (page) {
      PmsPage.today when user.isOperator => [
        '/api/operations/today-command',
        '/api/owner/dashboard',
      ],
      PmsPage.today || PmsPage.schedule => ['/api/worker/dashboard'],
      PmsPage.reservations => ['/api/reservations', '/api/properties'],
      PmsPage.operations => [
        '/api/properties',
        '/api/operations/today-command',
      ],
      _ => <String>[],
    };
    final selected = page;
    final snapshots = <String, (Object, DateTime)>{};
    for (final path in paths) {
      final value = await auth.cache.read(path, scope, auth.now());
      if (value != null) snapshots[path] = value;
    }
    if (!_disposed &&
        auth.offline &&
        auth.cacheScope == scope &&
        selected == page) {
      offlineData = snapshots;
      emit();
    }
  }

  void _invalidateReads() {
    ++_readGeneration;
    _reads.clear();
    _pending.clear();
  }

  Future<Object?> _read(String path, {required bool force}) {
    final cached = _reads[path];
    if (!force &&
        cached != null &&
        _clock().difference(cached.$2) < _freshFor) {
      return Future.value(cached.$1);
    }
    return _pending.putIfAbsent(path, () {
      final generation = _readGeneration;
      return api
          .get(path)
          .then((value) {
            if (!_disposed && generation == _readGeneration) {
              _reads[path] = (value, _clock());
              unawaited(
                auth.rememberOperational(path, value).catchError((Object _) {}),
              );
            }
            return value;
          })
          .whenComplete(() {
            if (generation == _readGeneration) _pending.remove(path);
          });
    });
  }

  Future<void> _checkIdentity({required bool force}) {
    final lastChecked = _identityChecked;
    if (!auth.offline &&
        !force &&
        lastChecked != null &&
        _clock().difference(lastChecked) < _identityFreshFor) {
      return Future.value();
    }
    final scope = _scope;
    return _identityRequest ??= auth
        .revalidate()
        .then((_) {
          if (_scope == scope) _identityChecked = _clock();
        })
        .whenComplete(() => _identityRequest = null);
  }

  bool loading = true, saving = false, _disposed = false;
  int _generation = 0;
  String? error, actionError;
  int unread = 0;
  String mode = 'observe';
  int receptionTab = 0;
  String? receptionSelected;
  String receptionQuery = '';
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
  Json object(String key) => optionalObject(data[key]);
  List<Json> rows(String key) => optionalRows(data[key]);
  void emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> language(String value) async {
    await strings.select(value);
    emit();
  }

  Future<void> navigate(PmsPage next) async {
    if (saving || auth.user == null || !allows(next)) return;
    await _load(next, force: false);
  }

  Future<void> refreshIfStale() => navigate(page);
  Future<void> load() => _load(page, force: true, verifyIdentity: true);

  bool get liveWorkspace => const {
    PmsPage.today,
    PmsPage.schedule,
    PmsPage.reservations,
    PmsPage.operations,
    PmsPage.maintenance,
    PmsPage.supplies,
    PmsPage.inbox,
    PmsPage.intelligence,
  }.contains(page);

  Future<void> synchronize({bool foreground = false}) async {
    if (_disposed || auth.user == null) return;
    if (refreshing || saving) {
      _foregroundRefreshDue |= foreground;
      return;
    }
    _foregroundRefreshDue = false;
    if (auth.offline || foreground || liveWorkspace) {
      await _load(
        page,
        force: true,
        verifyIdentity: foreground,
        background: !foreground,
      );
    }
  }

  void _finishLoad() {
    loading = refreshing = false;
    emit();
    if (_foregroundRefreshDue && !saving) {
      unawaited(synchronize(foreground: true));
    }
  }

  static const receptionSections = ['inbox', 'outbox', 'rules'];
  static const _receptionRoutes = [
    '/api/inbox',
    '/api/communications/outbox',
    '/api/automation/rules',
  ];

  Future<void> refreshReception() => _load(
    PmsPage.inbox,
    force: true,
    background: true,
    verifyIdentity: auth.offline,
  );

  Future<void> selectReception(int tab) async {
    receptionTab = tab;
    if (page == PmsPage.inbox) {
      await _load(page, force: false, background: true);
    } else {
      emit();
    }
  }

  Map<String, String> _routes(PmsPage selected, {required bool activeOnly}) {
    final paths = <String, String>{};
    switch (selected) {
      case PmsPage.today:
        if (user.isOperator) {
          paths.addAll({
            'command': '/api/operations/today-command',
            'dashboard': '/api/owner/dashboard',
            'reception': '/api/reception/summary',
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
        paths[receptionSections[receptionTab]] = _receptionRoutes[receptionTab];
        paths['summary'] = '/api/reception/summary';
        if (!activeOnly) {
          for (var i = 0; i < receptionSections.length; i++) {
            paths[receptionSections[i]] = _receptionRoutes[i];
          }
        }
      case PmsPage.operations:
        paths.addAll({
          'timeline': '/api/operations/timeline',
          'journeys': '/api/guest-journeys',
          'properties': '/api/properties',
          'team': '/api/team/overview',
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
    return paths;
  }

  Future<void> _load(
    PmsPage selected, {
    required bool force,
    bool verifyIdentity = false,
    bool background = false,
  }) async {
    if (_disposed || auth.user == null) return;
    force = force || auth.offline;
    final generation = ++_generation;
    final chatRevision = chat.revision;
    final samePage = selected == page;
    page = selected;
    if (auth.offline) {
      if (!samePage) offlineData = {};
      unawaited(_loadOffline());
    }
    final paths = _routes(selected, activeOnly: background);
    if (!samePage) data.clear();
    for (final entry in paths.entries) {
      if (_reads[entry.value] case (final value, _)) {
        data[entry.key] = value;
      }
    }
    if (!samePage) sectionErrors.clear();
    if (!background || !samePage) {
      error = null;
      for (final key in paths.keys) {
        sectionErrors.remove(key);
      }
      chatRefreshError = null;
    }
    final needsFetch =
        force ||
        paths.values.any((path) {
          final cached = _reads[path];
          return cached == null || _clock().difference(cached.$2) >= _freshFor;
        });
    loading = data.isEmpty;
    refreshing = needsFetch;
    emit();

    bool current() =>
        !_disposed && generation == _generation && auth.user != null;
    try {
      if (strings.data.isEmpty) await strings.load();
      await _checkIdentity(force: verifyIdentity);
      if (!current()) return;
    } on ApiException catch (failure) {
      if (!current()) return;
      if (failure.statusCode == 401 || failure.statusCode == 403) {
        _invalidateReads();
        data.clear();
        chat.invalidateAccess();
      }
      connectionIssue = failure.kind;
      error = safeError(failure);
      _finishLoad();
      return;
    }
    final readGeneration = _readGeneration;

    Future<void> loadSection(MapEntry<String, String> entry) async {
      try {
        final result = await _read(entry.value, force: force);
        if (!current() || readGeneration != _readGeneration) return;
        data[entry.key] = result;
        sectionErrors.remove(entry.key);
        if (entry.key == 'conversation' &&
            result != null &&
            chat.revision == chatRevision) {
          chat.syncHistory(jsonObject(result), notify: false);
        }
        loading = false;
      } on ApiException catch (failure) {
        if (!current() || readGeneration != _readGeneration) return;
        if (failure.statusCode == 403) {
          data.remove(entry.key);
          _reads.remove(entry.value);
          if (entry.key == 'conversation') chat.invalidateAccess();
        }
        if (failure.kind != ApiFailure.cancelled) {
          sectionErrors[entry.key] = safeError(failure);
          if (entry.key == 'conversation') {
            chatRefreshError = safeError(failure);
          }
          connectionIssue = failure.kind;
        }
      }
      if (current()) emit();
    }

    if (user.isOperator && !background) {
      Future<void> loadUtility(
        String path,
        void Function(Json value) update,
      ) async {
        try {
          final result = await _read(path, force: false);
          if (current() && readGeneration == _readGeneration) {
            update(jsonObject(result));
          }
        } on ApiException {
          // Page content and the drawer each report their own request status.
        }
      }

      unawaited(
        loadUtility('/api/organization', (value) {
          mode = text(value, 'operating_mode', mode);
          emit();
        }),
      );
      unawaited(
        loadUtility('/api/notifications', (value) {
          unread = (value['unread'] as num?)?.toInt() ?? 0;
          emit();
        }),
      );
    }

    await Future.wait(paths.entries.map(loadSection));
    if (!current()) return;
    if (readGeneration == _readGeneration) {
      error = data.isEmpty && sectionErrors.isNotEmpty
          ? sectionErrors.values.first
          : null;
      if (sectionErrors.isEmpty) connectionIssue = null;
    }
    _finishLoad();
  }

  Future<Object?> mutate(String method, String path, [Object? body]) async {
    // The backend remains authoritative for permissions, CSRF, modes and state.
    return switch (method) {
      'POST' => api.post(path, body ?? const {}),
      'PATCH' => api.patch(path, body ?? const {}),
      'PUT' => api.put(path, body ?? const {}),
      'DELETE' => api.delete(path, body),
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
      if (_foregroundRefreshDue) unawaited(synchronize(foreground: true));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    auth.removeListener(_authChanged);
    if (api.onMutation == _invalidateOnMutation) api.onMutation = null;
    _invalidateReads();
    chat.dispose();
    super.dispose();
  }
}

String intelligenceBrief(Json data) {
  if (!data.containsKey('arrivals')) return '';
  final arrivals = optionalRows(data['arrivals']).length;
  final departures = optionalRows(data['departures']).length;
  final tasks = optionalRows(data['tasks']).length;
  final approvals = optionalRows(data['approvals']).length;
  return ui(
    'Arrivals: $arrivals. Departures: $departures. '
    'Operational tasks: $tasks. Decisions needed: $approvals.',
  );
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
