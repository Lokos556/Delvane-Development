import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../network/api_client.dart';
import '../network/api_configuration.dart';
import 'session_store.dart';
import 'offline_operations.dart';

enum AuthPhase { restoring, signedOut, signingIn, authenticated, disconnected }

class AuthUser {
  const AuthUser(
    this.id,
    this.name,
    this.role,
    this.organization,
    this.organizationId,
    this.permissions,
  );
  final String id, name, role, organization, organizationId;
  final Set<String> permissions;
  bool get isOperator => role == 'owner' || role == 'manager';
  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final role = json['role'];
    if (!{'owner', 'manager', 'cleaner', 'maintenance'}.contains(role) ||
        json['id'] is! String ||
        json['organization_id'] is! String ||
        json['permissions'] is! List) {
      throw const ApiException(
        'Unsupported account or invalid identity response.',
      );
    }
    return AuthUser(
      json['id'],
      json['full_name'] as String,
      role as String,
      json['organization_name'] as String,
      json['organization_id'],
      (json['permissions'] as List).cast<String>().toSet(),
    );
  }
}

/// Reuses FastAPI's cookie and per-session CSRF contract. No bearer-token system.
class AuthController extends ChangeNotifier {
  AuthController({
    required Uri origin,
    required this.store,
    ApiTransport? transport,
    DateTime Function()? clock,
    this.environment = ApiEnvironment.local,
    List<int>? uatTunnelCertificate,
  }) : now = clock ?? DateTime.now {
    final configuration = ApiConfiguration(
      environment: environment,
      origin: origin,
      uatTunnelCertificate: uatTunnelCertificate,
    );
    SecurityContext? tunnelTrust;
    if (uatTunnelCertificate != null) {
      try {
        tunnelTrust = SecurityContext(withTrustedRoots: false)
          ..setTrustedCertificatesBytes(uatTunnelCertificate);
      } on TlsException {
        throw ArgumentError('The Windows UAT tunnel certificate is invalid.');
      }
    }
    api = ApiClient(
      baseUrl: configuration.origin,
      transport: transport ?? IoApiTransport(tunnelTrust),
      diagnosticsFile: tunnelTrust == null ? null : _tunnelDiagnostics(),
      allowInsecureLoopback: configuration.isLocal,
      sessionHeaders: () => {
        if (_cookie != null) 'Cookie': 'rosa_session=$_cookie',
        if (_csrf != null) 'X-Rosa-CSRF': _csrf!,
      },
    );
    api.onUnauthorized = _expired;
    api.onConnectionLost = _connectionLost;
    api.offline = () => offline;
    // Preserve existing local sessions; remote namespaces cannot reuse them.
    storageKey =
        'delvane.business.session.v1.'
        '${configuration.isLocal ? '' : '${environment.name}.'}'
        '${Uri.encodeComponent(configuration.origin.origin)}';
    cache = OfflineOperations(store, storageKey);
  }
  static File? _tunnelDiagnostics() {
    final path = Platform.environment['DELVANE_UAT_API_LOG'];
    return path == null || path.isEmpty ? null : File(path);
  }

  final ApiEnvironment environment;
  final SessionStore store;
  final DateTime Function() now;
  late final ApiClient api;
  late final String storageKey;
  late final OfflineOperations cache;
  AuthPhase phase = AuthPhase.restoring;
  AuthUser? user;
  String? error;
  String? workspaceId;
  String? _cookie, _csrf;
  DateTime? _expiresAt;
  DateTime? lastVerified;
  bool offline = false;
  String? _sessionEpoch;
  Timer? _expiryTimer;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _storageQueue = Future.value();
  bool get busy => phase == AuthPhase.restoring || phase == AuthPhase.signingIn;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _store(Future<void> Function() action) {
    final result = _storageQueue.then((_) => action());
    _storageQueue = result.catchError((Object _) {});
    return result;
  }

  void _clearMemory() {
    _cookie = _csrf = null;
    user = null;
    _expiresAt = null;
    lastVerified = null;
    _sessionEpoch = null;
    offline = false;
    _expiryTimer?.cancel();
  }

  Future<void> _deleteStored() => _store(() async {
    await store.delete(storageKey);
    await cache.clear();
  });

  String? get cacheScope {
    final identity = user;
    if (identity == null ||
        _sessionEpoch == null ||
        workspaceId == null ||
        environment == ApiEnvironment.local) {
      return null;
    }
    return jsonEncode([
      workspaceId,
      identity.id,
      identity.organizationId,
      identity.role,
      identity.permissions.toList()..sort(),
      _sessionEpoch,
    ]);
  }

  Future<void> rememberOperational(String path, Object? data) {
    final scope = cacheScope;
    if (scope == null || offline) return Future.value();
    return _store(() => cache.remember(path, data, scope, now()));
  }

  Future<void> _saveSession(AuthUser identity) async {
    lastVerified = now();
    _sessionEpoch ??= lastVerified!.toIso8601String();
    final encoded = jsonEncode({
      'cookie': _cookie,
      'expires_at': _expiresAt!.toIso8601String(),
      'origin': api.baseUrl.origin,
      'workspace_id': workspaceId,
      if (environment != ApiEnvironment.local) ...{
        'verified_at': lastVerified!.toIso8601String(),
        'epoch': _sessionEpoch,
        'offline_identity': {
          'id': identity.id,
          'role': identity.role,
          'organization_id': identity.organizationId,
          'organization_name': identity.organization,
          'full_name': '',
          'permissions': identity.permissions.toList(),
        },
      },
    });
    await _store(() => store.write(storageKey, encoded));
  }

  DateTime? get _offlineUntil => lastVerified?.add(OfflineOperations.retention);

  void _connectionLost() {
    if (environment == ApiEnvironment.local ||
        user == null ||
        offline ||
        _disposed) {
      return;
    }
    if (_offlineUntil?.isAfter(now()) != true) {
      _expired();
      return;
    }
    _activate(user!, cached: true);
  }

  Future<void> _checkWorkspace() async {
    if (environment != ApiEnvironment.local) {
      final body = await api.get('/api/client/environment');
      if (body is! Map<String, dynamic> ||
          body['environment'] != environment.name ||
          body['secure_cookies'] != true ||
          body['deployment_id'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{8,128}$')
              .hasMatch(body['deployment_id'] as String)) {
        throw const ApiException(
          'The server does not match the selected API environment.',
        );
      }
      workspaceId = '${environment.name}:${body['deployment_id']}';
      return;
    }
    final body = await api.get('/api/development/workspace');
    if (body is! Map<String, dynamic> ||
        body['isolated'] != true ||
        body['workspace_id'] is! String ||
        (body['workspace_id'] as String).isEmpty) {
      throw const ApiException(
        'This client requires the isolated development launcher.',
      );
    }
    workspaceId = body['workspace_id'];
  }

  Future<AuthUser> _loadIdentity() async {
    final body = await api.get('/api/me');
    if (body is! Map<String, dynamic> ||
        body['csrf_token'] is! String ||
        (body['csrf_token'] as String).isEmpty) {
      throw const ApiException('The server returned an invalid session.');
    }
    final identity = AuthUser.fromJson(body);
    _csrf = body['csrf_token'];
    return identity;
  }

  void _activate(AuthUser identity, {bool cached = false}) {
    user = identity;
    phase = AuthPhase.authenticated;
    error = null;
    offline = cached;
    _expiryTimer?.cancel();
    final expires = cached && _offlineUntil!.isBefore(_expiresAt!)
        ? _offlineUntil!
        : _expiresAt!;
    final remaining = expires.difference(now());
    if (remaining <= Duration.zero) {
      _expired();
      return;
    }
    _expiryTimer = Timer(remaining, _expired);
    _emit();
  }

  Future<void> restore() async {
    final generation = ++_generation;
    phase = AuthPhase.restoring;
    error = null;
    _clearMemory();
    _emit();
    Map<String, dynamic>? stored;
    try {
      await _checkWorkspace(); // Never send a credential before this gate.
      final saved = await store.read(storageKey);
      if (generation != _generation || _disposed) return;
      if (saved == null) {
        phase = AuthPhase.signedOut;
        _emit();
        return;
      }
      final value = jsonDecode(saved) as Map<String, dynamic>;
      stored = value;
      final expires = DateTime.parse(value['expires_at'] as String);
      if (value['workspace_id'] != workspaceId ||
          value['origin'] != api.baseUrl.origin ||
          !expires.isAfter(now()) ||
          !_validCookie(value['cookie'])) {
        await _deleteStored();
        phase = AuthPhase.signedOut;
        _emit();
        return;
      }
      _cookie = value['cookie'];
      _expiresAt = expires;
      _sessionEpoch = value['epoch'] as String?;
      final identity = await _loadIdentity();
      if (generation != _generation || _disposed) return;
      if (environment != ApiEnvironment.local) await _saveSession(identity);
      if (generation == _generation && !_disposed) _activate(identity);
    } catch (e) {
      if (generation != _generation || _disposed) return;
      if (environment != ApiEnvironment.local &&
          e is ApiException &&
          e.isConnectionLoss) {
        try {
          stored ??= jsonDecode(
            await store.read(storageKey) ?? '{}',
          ) as Map<String, dynamic>;
          if (generation != _generation || _disposed) return;
          final saved = stored;
          final verified = DateTime.parse(saved['verified_at'] as String);
          final expires = DateTime.parse(saved['expires_at'] as String);
          if (saved['origin'] == api.baseUrl.origin &&
              _validCookie(saved['cookie']) &&
              (saved['workspace_id'] as String).startsWith(
                '${environment.name}:',
              ) &&
              (workspaceId == null || workspaceId == saved['workspace_id']) &&
              !verified.isAfter(now()) &&
              verified.add(OfflineOperations.retention).isAfter(now()) &&
              expires.isAfter(now())) {
            final identity = AuthUser.fromJson(
              Map<String, dynamic>.from(saved['offline_identity'] as Map),
            );
            _sessionEpoch = saved['epoch'] as String;
            lastVerified = verified;
            _expiresAt = expires;
            _cookie = saved['cookie'];
            workspaceId = saved['workspace_id'];
            _activate(identity, cached: true);
            return;
          }
        } catch (_) {
          /* An invalid or expired local lease cannot unlock the app. */
        }
      }
      _clearMemory();
      error = e is ApiException
          ? e.message
          : 'Secure session storage is unavailable or invalid.';
      phase = AuthPhase.disconnected;
      _emit();
    }
  }

  static bool _validCookie(Object? value) =>
      value is String && RegExp(r'^[A-Za-z0-9_-]{20,512}$').hasMatch(value);

  Future<void> signIn(String email, String password) async {
    if (busy) return;
    final generation = ++_generation;
    _clearMemory();
    phase = AuthPhase.signingIn;
    error = null;
    _emit();
    try {
      await _checkWorkspace();
      // Delete any previous session before attempting to persist a replacement.
      await _deleteStored();
      final response = await api.exchange('POST', '/api/login', {
        'email': email.trim(),
        'password': password,
      });
      final matches = response.setCookies
          .map(Cookie.fromSetCookieValue)
          .where((cookie) => cookie.name == 'rosa_session')
          .toList();
      if (matches.length != 1) {
        throw const ApiException('No valid session cookie was returned.');
      }
      final cookie = matches.single;
      if (!_validCookie(cookie.value) ||
          !cookie.httpOnly ||
          cookie.path != '/' ||
          (cookie.domain != null && cookie.domain != api.baseUrl.host) ||
          (cookie.secure && api.baseUrl.scheme != 'https') ||
          (environment != ApiEnvironment.local && !cookie.secure) ||
          cookie.maxAge == null ||
          cookie.maxAge! <= 0 ||
          cookie.maxAge! > 604800) {
        throw const ApiException(
          'The server returned an unsafe session cookie.',
        );
      }
      _cookie = cookie.value;
      _expiresAt = now().add(Duration(seconds: cookie.maxAge!));
      final identity = await _loadIdentity();
      if (generation != _generation || _disposed) return;
      await _saveSession(identity);
      if (generation == _generation && !_disposed) _activate(identity);
    } catch (e) {
      if (generation != _generation || _disposed) return;
      // Best effort revoke if login succeeded but secure persistence failed.
      if (_cookie != null && _csrf != null) {
        try {
          await api.post('/api/logout', const {});
        } catch (_) {
          /* no retry */
        }
      }
      _clearMemory();
      phase = AuthPhase.signedOut;
      error = e is ApiException
          ? (e.statusCode == 401 ? 'Incorrect email or password.' : e.message)
          : 'Secure sign-in could not be completed. No password was saved.';
      _emit();
    }
  }

  Future<void> revalidate() async {
    if (phase != AuthPhase.authenticated) return;
    final generation = _generation;
    final wasOffline = offline;
    final expected = workspaceId;
    try {
      if (wasOffline) {
        await _checkWorkspace();
        if (expected != workspaceId) {
          _expired();
          throw const ApiException(
            'The server environment changed. Sign in again.',
          );
        }
      }
      final identity = await _loadIdentity();
      if (generation != _generation || _disposed) return;
      final previousScope = cacheScope;
      user = identity;
      if (wasOffline || previousScope != cacheScope) await _store(cache.clear);
      if (generation != _generation || _disposed) return;
      if (environment != ApiEnvironment.local &&
          (wasOffline ||
              lastVerified == null ||
              now().difference(lastVerified!) >= const Duration(minutes: 5))) {
        await _saveSession(identity);
      }
      if (generation == _generation && !_disposed) _activate(identity);
    } on ApiException catch (failure) {
      if (generation == _generation && failure.statusCode == 403) _expired();
      rethrow;
    }
  }

  void _expired() {
    if (_disposed) return;
    ++_generation;
    _clearMemory();
    phase = AuthPhase.signedOut;
    error = 'Your session expired or was revoked. Sign in again.';
    unawaited(
      _deleteStored().catchError((Object _) {
        error = 'Session ended. Secure storage could not be cleared; retry before signing in.';
        _emit();
      }),
    );
    _emit();
  }

  Future<void> logout() async {
    if (phase != AuthPhase.authenticated) return;
    ++_generation;
    String? warning;
    try {
      if (offline) throw const ApiException('Offline');
      await api.post('/api/logout', const {});
    } catch (_) {
      warning = 'Signed out locally. Server revocation was not confirmed; the server session may remain until expiry.';
    }
    _clearMemory();
    try {
      await _deleteStored();
    } catch (_) {
      warning = 'Secure storage could not be cleared. Retry sign-in/sign-out before leaving this device.';
    }
    phase = AuthPhase.signedOut;
    error = warning;
    _emit();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _clearMemory();
    api.onUnauthorized = null;
    api.onConnectionLost = null;
    api.close();
    super.dispose();
  }
}
