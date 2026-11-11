import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/core/auth/auth_controller.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'support/fake_pms.dart';

void main() {
  test(
    'login uses server cookie; stores no password/CSRF; /me supplies role and logout revokes',
    () async {
      final pms = FakePms();
      final store = MemorySessionStore();
      final auth = await signedIn(pms, store);
      addTearDown(auth.dispose);
      expect(auth.phase, AuthPhase.authenticated);
      expect(auth.user!.role, 'owner');
      final saved = store.values.values.single;
      expect(saved, contains(fakeCookie));
      expect(saved, isNot(contains('password')));
      expect(saved, isNot(contains(fakeCsrf)));
      expect(pms.requests.first.path, '/api/development/workspace');
      final login = pms.requests.singleWhere((r) => r.path == '/api/login');
      expect(login.headers.containsKey('Cookie'), false);
      expect((login.body as Map)['email'], 'synthetic@workspace.invalid');
      await auth.logout();
      expect(pms.requests.last.headers['X-Rosa-CSRF'], fakeCsrf);
      expect(pms.revoked, true);
      expect(auth.user, isNull);
      expect(store.values, isEmpty);
    },
  );
  test(
    'restoration binds origin/workspace and revalidates identity/CSRF with backend',
    () async {
      final pms = FakePms();
      final store = MemorySessionStore();
      final old = await signedIn(pms, store);
      old.dispose();
      final auth = makeAuth(pms, store);
      addTearDown(auth.dispose);
      await auth.restore();
      expect(auth.phase, AuthPhase.authenticated);
      await auth.logout();
      expect(pms.requests.last.headers['X-Rosa-CSRF'], fakeCsrf);
    },
  );
  test(
    'expired, foreign-origin and previous-workspace credentials are discarded before /me',
    () async {
      for (final change in [
        {'expires_at': '2030-01-01T00:00:00Z'},
        {'origin': 'https://different.invalid'},
        {'workspace_id': 'previous-run'},
        {'cookie': 'bad;token'},
      ]) {
        final pms = FakePms();
        final store = MemorySessionStore();
        final auth = makeAuth(pms, store);
        store.values[auth.storageKey] = jsonEncode({
          'cookie': fakeCookie,
          'expires_at': '2032-05-11T00:00:00Z',
          'origin': auth.api.baseUrl.origin,
          'workspace_id': pms.workspaceId,
          ...change,
        });
        await auth.restore();
        expect(auth.phase, AuthPhase.signedOut);
        expect(store.values, isEmpty);
        expect(pms.requests.map((r) => r.path), ['/api/development/workspace']);
        auth.dispose();
      }
    },
  );
  test(
    'workspace gate blocks credential submission to an unisolated server',
    () async {
      final pms = FakePms()..isolated = false;
      final auth = makeAuth(pms);
      addTearDown(auth.dispose);
      await auth.restore();
      await auth.signIn('synthetic@workspace.invalid', 'secret-not-sent');
      expect(auth.user, isNull);
      expect(pms.requests.any((r) => r.path == '/api/login'), false);
      expect(pms.requests.every((r) => !r.headers.containsKey('Cookie')), true);
    },
  );
  for (final status in [401, 429, 500]) {
    test(
      'login failure $status is safe and never establishes a session',
      () async {
        final pms = FakePms()..loginFailure = status;
        final store = MemorySessionStore();
        final auth = makeAuth(pms, store);
        addTearDown(auth.dispose);
        await auth.restore();
        await auth.signIn('synthetic@workspace.invalid', 'private-secret');
        expect(auth.phase, AuthPhase.signedOut);
        expect(store.values, isEmpty);
        expect(auth.error, isNot(contains('private')));
      },
    );
  }
  test('missing, insecure and malformed cookies fail closed', () async {
    for (final cookie in [
      null,
      'rosa_session=$fakeCookie; Path=/; Max-Age=604800',
      'rosa_session=$fakeCookie; HttpOnly; Secure; Path=/; Max-Age=604800',
      'rosa_session=$fakeCookie; HttpOnly; Path=/; Domain=other.invalid; Max-Age=604800',
    ]) {
      final pms = FakePms();
      pms.overrides['/api/login'] = ApiResponse(
        200,
        '{}',
        setCookies: cookie == null ? [] : [cookie],
      );
      final auth = makeAuth(pms);
      await auth.restore();
      await auth.signIn('synthetic@workspace.invalid', 'synthetic-password');
      expect(auth.phase, AuthPhase.signedOut);
      expect(auth.user, isNull);
      auth.dispose();
    }
  });
  test(
    'secure storage failure revokes issued session and never falls back to plaintext',
    () async {
      final pms = FakePms();
      final store = MemorySessionStore()..failWrites = true;
      final auth = await signedIn(pms, store);
      addTearDown(auth.dispose);
      expect(auth.phase, AuthPhase.signedOut);
      expect(store.values, isEmpty);
      expect(pms.revoked, true);
    },
  );
  test(
    'revocation clears authenticated state and persisted credentials on any protected 401',
    () async {
      final pms = FakePms();
      final store = MemorySessionStore();
      final auth = await signedIn(pms, store);
      addTearDown(auth.dispose);
      pms.revoked = true;
      await expectLater(auth.revalidate(), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);
      expect(auth.user, isNull);
      expect(auth.phase, AuthPhase.signedOut);
      expect(store.values, isEmpty);
    },
  );
  test('permission-denied response does not destroy a valid session', () async {
    final pms = FakePms();
    final auth = await signedIn(pms);
    addTearDown(auth.dispose);
    pms.overrides['/api/properties'] = const ApiResponse(403, 'sensitive-body');
    await expectLater(
      auth.api.get('/api/properties'),
      throwsA(isA<ApiException>()),
    );
    expect(auth.phase, AuthPhase.authenticated);
  });
  test(
    'unsupported roles are rejected instead of receiving an owner shell',
    () async {
      final pms = FakePms()..role = 'unknown';
      final auth = await signedIn(pms);
      addTearDown(auth.dispose);
      expect(auth.user, isNull);
      expect(auth.phase, AuthPhase.signedOut);
    },
  );
  test(
    'logout failure clears local session and reports unconfirmed server revocation',
    () async {
      final pms = FakePms();
      final store = MemorySessionStore();
      final auth = await signedIn(pms, store);
      addTearDown(auth.dispose);
      pms.overrides['/api/logout'] = const ApiResponse(503, 'private-body');
      await auth.logout();
      expect(auth.user, isNull);
      expect(store.values, isEmpty);
      expect(auth.error, contains('revocation was not confirmed'));
    },
  );
}
