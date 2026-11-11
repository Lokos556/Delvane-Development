import 'package:flutter/foundation.dart';
import '../../core/auth/auth_controller.dart';
import '../../core/network/api_client.dart';
import 'workspace_models.dart';
import 'workspace_repository.dart';

enum WorkspaceTab { today, reservations, properties, work, account }

enum WorkspacePhase { loading, ready, error }

List<WorkspaceTab> tabsFor(AuthUser user) => [
  WorkspaceTab.today,
  if (user.isOperator && user.permissions.contains('reservations.read'))
    WorkspaceTab.reservations,
  WorkspaceTab.properties,
  WorkspaceTab.work,
  WorkspaceTab.account,
];

class WorkspaceController extends ChangeNotifier {
  WorkspaceController(this.auth, this.repository);
  final AuthController auth;
  final WorkspaceRepository repository;
  OperationalWorkspace? workspace;
  WorkspacePhase phase = WorkspacePhase.loading;
  WorkspaceTab tab = WorkspaceTab.today;
  String? propertyId, error;
  bool _disposed = false;
  int _generation = 0;
  List<WorkspaceTab> get tabs => tabsFor(auth.user!);
  Future<void> load() async {
    final generation = ++_generation;
    phase = WorkspacePhase.loading;
    workspace = null; // Never present stale records as a successful refresh.
    error = null;
    notifyListeners();
    try {
      await auth.revalidate();
      if (auth.user == null || generation != _generation || _disposed) return;
      final result = await repository.load(auth.user!);
      if (auth.user == null || generation != _generation || _disposed) return;
      workspace = result;
      if (!result.properties.any((p) => p.id == propertyId)) propertyId = null;
      if (!tabs.contains(tab)) tab = WorkspaceTab.today;
      phase = WorkspacePhase.ready;
    } catch (e) {
      if (generation != _generation || _disposed) return;
      error = e is ApiException
          ? e.message
          : 'Operational data could not be read. Check the development server and retry.';
      phase = WorkspacePhase.error;
    }
    if (!_disposed) notifyListeners();
  }

  bool includes(String id) => propertyId == null || id == propertyId;
  List<OperationalItem> scoped(List<OperationalItem> items) =>
      items.where((i) => includes(i.propertyId)).toList();
  void navigate(WorkspaceTab value) {
    if (!tabs.contains(value)) return;
    tab = value;
    notifyListeners();
  }

  void selectProperty(String? value) {
    if (value != null &&
        !(workspace?.properties.any((p) => p.id == value) ?? false)) {
      return;
    }
    propertyId = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
