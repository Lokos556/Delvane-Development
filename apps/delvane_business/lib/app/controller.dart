import 'package:flutter/foundation.dart';
import '../domain/business_repository.dart';
import '../domain/models.dart';
import 'destination.dart';

class BusinessController extends ChangeNotifier {
  BusinessController(this.repository);
  final BusinessRepository repository;
  BusinessSnapshot? snapshot;
  String? loadError;
  Destination destination = Destination.dashboard;
  String? propertyId;
  String search = '';
  StayStatus? status;
  final Set<String> completedTasks = {};
  final Map<String, String> drafts = {};
  bool notifications = true;
  bool compactCards = false;
  bool _disposed = false;

  Future<void> load() async {
    loadError = null;
    try {
      snapshot = await repository.load();
    } catch (_) {
      loadError = 'The demo workspace could not be loaded. Please try again.';
    }
    if (!_disposed) notifyListeners();
  }

  void navigate(Destination next) {
    destination = next;
    notifyListeners();
  }

  void selectProperty(String? value) {
    propertyId = value;
    notifyListeners();
  }

  void filterSearch(String value) {
    search = value;
    notifyListeners();
  }

  void filterStatus(StayStatus? value) {
    status = value;
    notifyListeners();
  }

  void toggleTask(String id) {
    completedTasks.contains(id)
        ? completedTasks.remove(id)
        : completedTasks.add(id);
    notifyListeners();
  }

  void saveDraft(String id, String value) {
    drafts[id] = value;
    notifyListeners();
  }

  void setNotifications(bool value) {
    notifications = value;
    notifyListeners();
  }

  void setCompact(bool value) {
    compactCards = value;
    notifyListeners();
  }

  bool includes(String id) => propertyId == null || propertyId == id;
  List<Stay> get filteredStays => snapshot!.stays
      .where(
        (s) =>
            includes(s.propertyId) &&
            (status == null || s.status == status) &&
            '${s.guest} ${s.id} ${snapshot!.propertyName(s.propertyId)}'
                .toLowerCase()
                .contains(search.toLowerCase()),
      )
      .toList();
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
