import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiResponse {
  const ApiResponse(this.statusCode, this.body, {this.setCookies = const []});
  final int statusCode;
  final String body;
  final List<String> setCookies;
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
      ..connectionTimeout = const Duration(seconds: 15)
      ..findProxy = (_) => 'DIRECT';
    final request = await client.openUrl(method, uri);
    // Never forward a session or a password through an HTTP redirect.
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    // HttpClientRequest.write defaults to Latin-1 without a charset. JSON text
    // must reach FastAPI as UTF-8, including combining marks and non-Latin text.
    if (body != null) request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close();
    final bytes = <int>[];
    await for (final chunk in response) {
      if (bytes.length + chunk.length > 8 * 1024 * 1024) {
        throw const ApiException('The server response is too large.');
      }
      bytes.addAll(chunk);
    }
    return ApiResponse(
      response.statusCode,
      utf8.decode(bytes),
      setCookies: response.headers[HttpHeaders.setCookieHeader] ?? const [],
    );
  }

  @override
  void close() {
    _client?.close(force: true);
    _client = null;
  }
}

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code, this.field});
  final String? code, field;
  final String message;
  final int? statusCode;
  @override
  String toString() => 'ApiException: $message';
}

/// One fixed origin per client. Credentials never appear in URLs or diagnostics.
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
  void Function()? onUnauthorized;

  Future<Object?> get(String path) => _request('GET', path);
  Future<Object?> post(String path, Object body) =>
      _request('POST', path, body);
  Future<Object?> patch(String path, Object body) =>
      _request('PATCH', path, body);
  Future<Object?> put(String path, Object body) => _request('PUT', path, body);
  Future<Object?> delete(String path, [Object? body]) =>
      _request('DELETE', path, body);

  Future<Object?> _request(String method, String path, [Object? body]) async {
    final response = await exchange(method, path, body);
    try {
      return response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      throw const ApiException('The server returned an invalid response.');
    }
  }

  Future<ApiResponse> exchange(
    String method,
    String path, [
    Object? body,
  ]) async {
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
            'Content-Type': 'application/json; charset=utf-8',
            ...?sessionHeaders?.call(),
          }, body)
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 401 && path != '/api/login') {
          onUnauthorized?.call();
        }
        String? code, field;
        try {
          final decoded = jsonDecode(response.body);
          final detail = decoded is Map ? decoded['detail'] : null;
          if (detail is Map) {
            if (detail['code'] is String) code = detail['code'];
            if (detail['field'] is String &&
                RegExp(r'^[a-z_]+$').hasMatch(detail['field'])) {
              field = detail['field'];
            }
          }
        } catch (_) {
          /* Never expose raw server messages. */
        }
        throw ApiException(
          response.statusCode == 401
              ? 'Authentication required.'
              : response.statusCode == 403
              ? 'Access denied or security token expired. Sign in again if needed.'
              : response.statusCode == 429
              ? 'Too many attempts. Wait before trying again.'
              : 'The server could not complete the request.',
          statusCode: response.statusCode,
          code: code,
          field: field,
        );
      }
      return response;
    } on TimeoutException {
      _transport.close();
      throw const ApiException('The request timed out.');
    } on FormatException {
      throw const ApiException('The server returned an invalid response.');
    } on IOException {
      throw const ApiException('The server could not be reached.');
    }
  }

  void close() => _transport.close();
}
