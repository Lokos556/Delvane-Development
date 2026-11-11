import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiResponse {
  const ApiResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

abstract interface class ApiTransport {
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  );
  void close();
}

/// Native-platform transport. No socket is opened until request() is called.
class IoApiTransport implements ApiTransport {
  HttpClient? _client;
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final request = await client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) request.write(jsonEncode(body));
    final response = await request.close();
    return ApiResponse(
      response.statusCode,
      await utf8.decoder.bind(response).join(),
    );
  }

  @override
  void close() {
    _client?.close(force: true);
    _client = null;
  }
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ApiException: $message';
}

/// Future integration seam, deliberately unused by the mock application.
/// Session/cookie and per-session CSRF headers must come from a future auth layer.
/// Never embed credentials in source, URLs, or compile-time defines.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    ApiTransport? transport,
    this.sessionHeaders,
    this.timeout = const Duration(seconds: 20),
    bool allowInsecureLoopback = false,
  }) : _transport = transport ?? IoApiTransport() {
    final local = {'localhost', '127.0.0.1', '::1'}.contains(baseUrl.host);
    if (baseUrl.host.isEmpty ||
        baseUrl.userInfo.isNotEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment ||
        (baseUrl.path.isNotEmpty && baseUrl.path != '/') ||
        (baseUrl.scheme != 'https' &&
            !(allowInsecureLoopback && local && baseUrl.scheme == 'http'))) {
      throw ArgumentError(
        'Use an HTTPS origin, or explicitly allow a local development origin.',
      );
    }
  }
  final Uri baseUrl;
  final ApiTransport _transport;
  final Map<String, String> Function()? sessionHeaders;
  final Duration timeout;

  Future<Object?> get(String path) => _request('GET', path);
  Future<Object?> post(String path, Object body) =>
      _request('POST', path, body);

  Future<Object?> _request(String method, String path, [Object? body]) async {
    // Uri.parse normalizes dot segments; validate the original path first too.
    final segments = Uri.decodeComponent(path.split('?').first).split('/');
    final relative = Uri.parse(path);
    if (!path.startsWith('/api/') ||
        relative.hasScheme ||
        relative.hasAuthority ||
        relative.hasFragment ||
        relative.pathSegments.any((s) => s == '..' || s == '.') ||
        segments.any((s) => s == '..' || s == '.')) {
      throw ArgumentError('Only same-origin /api/ paths are supported.');
    }
    try {
      final response = await _transport
          .request(method, baseUrl.resolveUri(relative), {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            ...?sessionHeaders?.call(),
          }, body)
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.statusCode == 401
              ? 'Authentication required.'
              : 'The server could not complete the request.',
          statusCode: response.statusCode,
        );
      }
      return response.body.isEmpty ? null : jsonDecode(response.body);
    } on TimeoutException {
      throw const ApiException('The request timed out.');
    } on FormatException {
      throw const ApiException('The server returned an invalid response.');
    } on IOException {
      throw const ApiException('The server could not be reached.');
    }
  }

  void close() => _transport.close();
}
