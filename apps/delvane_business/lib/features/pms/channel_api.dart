import '../workspace/workspace_models.dart';
import 'pms_controller.dart';
import 'pms_workflows.dart';

class ChannelApi {
  ChannelApi(this.c, this.id);
  final PmsController c;
  final String id;
  String get path => '/api/integrations/${idPath(id)}';
  Future<Json> get(String suffix) => PmsWorkflows(c).object('$path$suffix');
  Future<List<Json>> rows(String suffix) =>
      PmsWorkflows(c).rows('$path$suffix');
  Future<Json> change(String method, String suffix, [Json? body]) async =>
      jsonObject(await PmsWorkflows(c).change(method, '$path$suffix', body));
}

bool enabled(Object? value) => value == true || value == 1;

/// Decimal strings go directly to Pydantic Decimal, never through a double.
Object? channelPrice(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
    throw const FormatException('Enter a decimal price.');
  }
  return value.contains('.') ? value : int.parse(value);
}

String deliveryTitle(Json result) {
  if (result['no_change'] == true) return 'No update sent';
  final delivery = optionalObject(result['delivery']);
  if (optionalRows(delivery['failed']).isNotEmpty) {
    return 'Saved; delivery will retry';
  }
  if (optionalRows(delivery['delivered']).isEmpty) return 'Update queued';
  return 'Update submitted';
}
