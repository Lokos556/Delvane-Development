import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/core/network/api_client.dart';

class FakeTransport implements ApiTransport {
  FakeTransport(this.response);
  final Future<ApiResponse> Function() response;
  Uri? uri;
  Map<String, String>? headers;
  Object? body;
  bool closed = false;
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) {
    this.uri = uri;
    this.headers = headers;
    this.body = body;
    return response();
  }

  @override
  void close() => closed = true;
}

void main() {
  test(
    'decodes collection responses and forwards injected session/CSRF headers',
    () async {
      final transport = FakeTransport(
        () async => const ApiResponse(200, '[{"id":"DEMO"}]'),
      );
      final client = ApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        transport: transport,
        sessionHeaders: () => {'X-Rosa-CSRF': 'synthetic-only'},
      );
      expect(await client.get('/api/reservations'), [
        {'id': 'DEMO'},
      ]);
      expect(
        transport.uri.toString(),
        'https://example.invalid/api/reservations',
      );
      expect(transport.headers!['X-Rosa-CSRF'], 'synthetic-only');
      client.close();
      expect(transport.closed, isTrue);
    },
  );
  test('rejects insecure remote origins and cross-origin paths without transport calls', () async {
    expect(
      () => ApiClient(baseUrl: Uri.parse('http://example.invalid')),
      throwsArgumentError,
    );
    final transport = FakeTransport(() async => const ApiResponse(200, '{}'));
    final client = ApiClient(
      baseUrl: Uri.parse('https://example.invalid'),
      transport: transport,
    );
    for (final path in [
      'https://other.invalid/api/me',
      '//other.invalid/api/me',
      '/api/../secrets',
      '/api/%2e%2e/secrets',
    ]) {
      await expectLater(client.get(path), throwsArgumentError);
    }
    expect(transport.uri, isNull);
  });
  test('local development HTTP is an explicit opt-in', () {
    expect(
      () => ApiClient(baseUrl: Uri.parse('http://127.0.0.1:8080')),
      throwsArgumentError,
    );
    final client = ApiClient(
      baseUrl: Uri.parse('http://127.0.0.1:8080'),
      allowInsecureLoopback: true,
    );
    client.close();
  });

  test(
    'request diagnostics keep only allowlisted route and outcome metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'delvane-diagnostics-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final log = File('${directory.path}/requests.jsonl');
      final client = ApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        transport: FakeTransport(
          () async => const ApiResponse(429, '{"detail":"private body"}'),
        ),
        sessionHeaders: () => {
          'Cookie': 'private-cookie',
          'X-Rosa-CSRF': 'private-csrf',
        },
        diagnosticsFile: log,
      );
      await expectLater(
        client.get('/api/reservations/private-id?guest=private-name'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            429,
          ),
        ),
      );
      for (var i = 0; i < 50 && !await log.exists(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final payload = await log.readAsString();
      expect(payload, contains('"route":"other"'));
      expect(payload, contains('"outcome":"http","status":429'));
      expect(payload, isNot(contains('private')));
    },
  );
  test(
    'status and malformed-response errors do not expose response bodies',
    () async {
      final unauthorized = ApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        transport: FakeTransport(
          () async => const ApiResponse(401, 'private-response'),
        ),
      );
      await expectLater(
        unauthorized.get('/api/me'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 401)
              .having(
                (e) => e.toString(),
                'safe error',
                isNot(contains('private-response')),
              ),
        ),
      );
      final malformed = ApiClient(
        baseUrl: Uri.parse('https://example.invalid'),
        transport: FakeTransport(
          () async => const ApiResponse(200, 'not-json'),
        ),
      );
      await expectLater(malformed.get('/api/me'), throwsA(isA<ApiException>()));
    },
  );
  test('enforces timeout and preserves integer JSON values', () async {
    final slow = ApiClient(
      baseUrl: Uri.parse('https://example.invalid'),
      timeout: Duration.zero,
      transport: FakeTransport(() => Completer<ApiResponse>().future),
    );
    await expectLater(slow.get('/api/me'), throwsA(isA<ApiException>()));
    final transport = FakeTransport(() async => const ApiResponse(200, '{}'));
    final client = ApiClient(
      baseUrl: Uri.parse('https://example.invalid'),
      transport: transport,
    );
    await client.post('/api/example', {'total_huf': 9007199254740993});
    expect((transport.body as Map)['total_huf'], 9007199254740993);
  });

  test('isolates a deadline from another request on the same client', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final slowArrived = Completer<void>();
    final siblingArrived = Completer<void>();
    HttpResponse? pendingSibling;
    server.listen((request) {
      if (request.uri.path == '/api/slow') {
        slowArrived.complete();
      } else {
        pendingSibling = request.response;
        siblingArrived.complete();
      }
    });
    final client = ApiClient(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      allowInsecureLoopback: true,
      timeout: const Duration(milliseconds: 450),
    );
    addTearDown(() {
      client.close();
      return server.close(force: true);
    });
    final timedOut = expectLater(
      client.get('/api/slow'),
      throwsA(
        isA<ApiException>().having((e) => e.kind, 'kind', ApiFailure.timeout),
      ),
    );
    await slowArrived.future;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final sibling = client.get('/api/sibling');
    await siblingArrived.future;
    await timedOut;
    pendingSibling!.write('{"ok":true}');
    await pendingSibling!.close();
    expect(await sibling, {'ok': true});
  });

  test('recovers a dropped GET without duplicating a POST', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    int reads = 0, writes = 0;
    server.listen((request) async {
      if (request.method == 'GET' && ++reads > 1) {
        request.response.write('{}');
        await request.response.close();
        return;
      }
      if (request.method == 'POST') ++writes;
      final connection = await request.response.detachSocket(
        writeHeaders: false,
      );
      connection.destroy();
    });
    final client = ApiClient(
      baseUrl: Uri.parse('http://127.0.0.1:${server.port}'),
      allowInsecureLoopback: true,
    );
    addTearDown(() {
      client.close();
      return server.close(force: true);
    });
    expect(await client.get('/api/me'), {});
    expect(reads, 2);
    await expectLater(client.post('/api/me', {}), throwsA(isA<ApiException>()));
    expect(writes, 1);
  });
}
