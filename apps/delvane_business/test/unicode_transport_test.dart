import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/core/network/api_client.dart';

void main() {
  test('native JSON wire preserves Unicode as UTF-8, not Latin-1', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? received;
    String? contentType;
    server.listen((request) async {
      final bytes = await request.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      contentType = request.headers.value(HttpHeaders.contentTypeHeader);
      try {
        received = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        request.response.headers.contentType = ContentType.json;
        request.response.add(utf8.encode(jsonEncode(received)));
      } catch (_) {
        request.response.statusCode = 400;
        request.response.write('{}');
      }
      await request.response.close();
    });
    final client = ApiClient(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      allowInsecureLoopback: true,
      timeout: const Duration(seconds: 5),
    );
    const message =
        'áéíóöőúüű ÁÉÍÓÖŐÚÜŰ · Árvíztűrő tükörfúrógép · Straße Łódź français e\u0301 👩‍💻';
    try {
      final reply = await client.post('/api/rosa/chat', {'message': message});
      expect(received?['message'], message);
      expect((reply as Map)['message'], message);
      expect(contentType, contains('charset=utf-8'));
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
}
