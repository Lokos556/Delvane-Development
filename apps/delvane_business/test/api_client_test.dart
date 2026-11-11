import 'dart:async';
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
  test(
    'rejects insecure remote origins and cross-origin paths without transport calls',
    () async {
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
    },
  );
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
}
