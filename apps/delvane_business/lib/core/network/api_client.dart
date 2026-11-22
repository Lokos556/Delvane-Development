import 'dart:async';
import 'dart:convert';
import 'dart:io';

class ApiResponse {
  const ApiResponse(
    this.statusCode,
    this.body, {
    this.setCookies = const [],
    this.attempts = 1,
  });
  final int statusCode;
  final String body;
  final List<String> setCookies;
  final int attempts;
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
  IoApiTransport([this._securityContext]);

  final SecurityContext? _securityContext;
  HttpClient? _client;
  final Set<HttpClient> _retryClients = {};
  int _generation = 0;

  HttpClient _openClient() => HttpClient(context: _securityContext)
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 3)
    ..maxConnectionsPerHost = 6
    ..findProxy = (_) => 'DIRECT';

  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) => _requestWithDeadline(
    method,
    uri,
    headers,
    body,
    const Duration(seconds: 20),
  );

  Future<ApiResponse> _requestWithDeadline(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
    Duration timeout,
  ) async {
    final generation = _generation;
    final elapsed = Stopwatch()..start();
    try {
      return await _attempt(
        _client ??= _openClient(),
        method,
        uri,
        headers,
        body,
        timeout,
      );
    } on IOException catch (failure) {
      if (generation != _generation) {
        throw const ApiException(
          'The request was cancelled.',
          kind: ApiFailure.cancelled,
        );
      }
      final remaining = timeout - elapsed.elapsed;
      if (method != 'GET' ||
          remaining < const Duration(milliseconds: 300) ||
          (failure is! SocketException && failure is! HttpException)) {
        rethrow;
      }
      // A dropped idle connection can safely be retried for a read. Use a
      // fresh connection without closing the pool used by other requests.
      final fresh = _openClient();
      _retryClients.add(fresh);
      try {
        final result = await _attempt(
          fresh,
          method,
          uri,
          headers,
          body,
          remaining,
        );
        return ApiResponse(
          result.statusCode,
          result.body,
          setCookies: result.setCookies,
          attempts: 2,
        );
      } on IOException {
        if (generation != _generation) {
          throw const ApiException(
            'The request was cancelled.',
            kind: ApiFailure.cancelled,
          );
        }
        rethrow;
      } finally {
        _retryClients.remove(fresh);
        fresh.close(force: true);
      }
    }
  }

  Future<ApiResponse> _attempt(
    HttpClient client,
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
    Duration timeout,
  ) async {
    HttpClientRequest? pending;
    StreamIterator<List<int>>? reader;
    var timedOut = false;
    final future = () async {
      final request = pending = await client.openUrl(method, uri);
      if (timedOut) {
        request.abort();
        throw TimeoutException('Request deadline exceeded');
      }
      // Never forward a session or a password through an HTTP redirect.
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      // HttpClientRequest.write defaults to Latin-1 without a charset. JSON text
      // must reach FastAPI as UTF-8, including combining marks and non-Latin text.
      if (body != null) request.add(utf8.encode(jsonEncode(body)));
      final response = await request.close();
      final bytes = <int>[];
      final stream = reader = StreamIterator(response);
      try {
        while (!timedOut && await stream.moveNext()) {
          final chunk = stream.current;
          if (bytes.length + chunk.length > 8 * 1024 * 1024) {
            throw const ApiException('The server response is too large.');
          }
          bytes.addAll(chunk);
        }
      } finally {
        await stream.cancel();
      }
      return ApiResponse(
        response.statusCode,
        utf8.decode(bytes),
        setCookies: response.headers[HttpHeaders.setCookieHeader] ?? const [],
      );
    }();
    return future.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        if (reader case final stream?) {
          unawaited(stream.cancel());
        } else {
          pending?.abort();
        }
        throw TimeoutException('Request deadline exceeded');
      },
    );
  }

  @override
  void close() {
    _generation++;
    _client?.close(force: true);
    _client = null;
    for (final retry in _retryClients) {
      retry.close(force: true);
    }
    _retryClients.clear();
  }
}

enum ApiFailure { http, connection, tls, timeout, cancelled, response }

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.code,
    this.field,
    this.kind,
  });
  final String? code, field;
  final String message;
  final int? statusCode;
  final ApiFailure? kind;
  @override
  String toString() => 'ApiException: $message';
}

/// One fixed origin per client. Credentials never appear in URLs or diagnostics.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    ApiTransport? transport,
    this.sessionHeaders,
    this.diagnosticsFile,
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
  final File? diagnosticsFile;
  Future<void> _diagnosticWrites = Future.value();
  static const _diagnosticPaths = {
    '/api/client/environment',
    '/api/me',
    '/api/operations/today-command',
    '/api/owner/dashboard',
    '/api/worker/dashboard',
    '/api/intelligence',
    '/api/rosa/provider',
    '/api/rosa/conversation',
    '/api/reservations',
    '/api/properties',
    '/api/reception/summary',
    '/api/inbox',
    '/api/communications/outbox',
    '/api/automation/rules',
    '/api/operations/timeline',
    '/api/guest-journeys',
    '/api/organization',
    '/api/notifications',
  };

  void _record(
    String method,
    String route,
    String outcome,
    int? status,
    int? attempts,
    Stopwatch watch,
  ) {
    final file = diagnosticsFile;
    if (file == null) return;
    final entry = jsonEncode({
      'at': DateTime.now().toUtc().toIso8601String(),
      'method': method,
      'route': _diagnosticPaths.contains(route) ? route : 'other',
      'outcome': outcome,
      'status': status,
      'attempts': attempts,
      'elapsed_ms': watch.elapsedMilliseconds,
    });
    _diagnosticWrites = _diagnosticWrites.then((_) async {
      try {
        await file.writeAsString('$entry\n', mode: FileMode.append);
      } on FileSystemException {
        // Opt-in local diagnostics cannot affect the operator request.
      }
    });
  }

  void Function()? onUnauthorized;
  void Function()? onMutation;

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
    final watch = Stopwatch()..start();
    String outcome = 'response';
    int? statusCode;
    int? attempts;
    try {
      final requestHeaders = {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
        ...?sessionHeaders?.call(),
      };
      final uri = baseUrl.resolveUri(relative);
      final transport = _transport;
      final response = await (transport is IoApiTransport
          ? transport._requestWithDeadline(
              method,
              uri,
              requestHeaders,
              body,
              timeout,
            )
          : transport
                .request(method, uri, requestHeaders, body)
                .timeout(timeout));
      statusCode = response.statusCode;
      attempts = response.attempts;
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
              : response.statusCode == 503
              ? 'The backend reported temporary unavailability.'
              : response.statusCode >= 500
              ? 'This request failed on the backend.'
              : 'The server could not complete the request.',
          statusCode: response.statusCode,
          code: code,
          field: field,
          kind: ApiFailure.http,
        );
      }
      if (method != 'GET') onMutation?.call();
      outcome = 'success';
      return response;
    } on ApiException catch (failure) {
      outcome = failure.kind?.name ?? 'response';
      rethrow;
    } on TimeoutException {
      outcome = 'timeout';
      throw const ApiException(
        'The request timed out.',
        kind: ApiFailure.timeout,
      );
    } on TlsException {
      outcome = 'tls';
      throw const ApiException(
        'The secure connection could not be verified.',
        kind: ApiFailure.tls,
      );
    } on FormatException {
      outcome = 'response';
      throw const ApiException(
        'The server returned an invalid response.',
        kind: ApiFailure.response,
      );
    } on IOException {
      outcome = 'connection';
      throw const ApiException(
        'The connection was interrupted.',
        kind: ApiFailure.connection,
      );
    } finally {
      _record(method, relative.path, outcome, statusCode, attempts, watch);
    }
  }

  void close() => _transport.close();
}
