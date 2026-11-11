import 'models.dart';

abstract interface class BusinessRepository {
  Future<BusinessSnapshot> load();
}
