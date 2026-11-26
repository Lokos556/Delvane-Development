import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:delvane_business/core/network/api_configuration.dart';
import 'package:delvane_business/core/network/api_client.dart';
import 'package:delvane_business/core/auth/auth_controller.dart';

import 'support/fake_pms.dart';

FakePms remoteServer(
  String environment, {
  String id = 'isolated-stage-01',
  bool secure = true,
}) {
  final pms = FakePms();
  pms.overrides['/api/client/environment'] = pms.json({
    'environment': environment,
    'deployment_id': id,
    'secure_cookies': secure,
  });
  pms.overrides['/api/login'] = ApiResponse(
    200,
    '{}',
    setCookies: [
      'rosa_session=$fakeCookie; HttpOnly; ${secure ? 'Secure;' : ''} Max-Age=604800; Path=/; SameSite=lax',
    ],
  );
  return pms;
}

AuthController remoteAuth(
  FakePms pms,
  MemorySessionStore store, {
  ApiEnvironment environment = ApiEnvironment.staging,
}) => AuthController(
  origin: Uri.parse('https://pms.example.invalid'),
  environment: environment,
  store: store,
  transport: pms,
  clock: () => fakeNow,
);

class SwitchableNetwork extends FakePms {
  bool down = false;
  @override
  Future<ApiResponse> request(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) async {
    if (down) throw const SocketException('Synthetic disconnect');
    return super.request(method, uri, headers, body);
  }
}

void main() {
  test('offline access restores only scoped projections and blocks writes until revalidated', () async {
    final network = SwitchableNetwork()
      ..overrides.addAll(remoteServer('staging').overrides);
    final store = MemorySessionStore();
    final first = remoteAuth(network, store);
    await first.restore();
    await first.signIn('fictional@workspace.invalid', 'fictional-password');
    final scope = first.cacheScope!;
    await first.rememberOperational('/api/reservations', [
      {
        'id': 'fake_booking',
        'property_id': 'fake_property',
        'guest_name': 'Sensitive Test Name',
        'document_number': 'Sensitive Test Number',
      },
    ]);
    expect(store.values.values.join(), isNot(contains('Sensitive Test')));
    first.dispose();
    network.down = true;
    final reopened = remoteAuth(network, store);
    addTearDown(reopened.dispose);
    await reopened.restore();
    expect(reopened.offline, isTrue);
    expect(reopened.phase, AuthPhase.authenticated);
    expect(
      await reopened.cache.read('/api/reservations', '${scope}other', fakeNow),
      isNull,
    );
    expect(
      await reopened.cache.read(
        '/api/reservations',
        scope,
        fakeNow.add(const Duration(hours: 12)),
      ),
      isNull,
    );
    expect(
      (await reopened.cache.read('/api/reservations', scope, fakeNow))!.$1,
      [
        {'id': 'fake_booking', 'property_id': 'fake_property'},
      ],
    );
    await expectLater(
      reopened.api.patch('/api/reservations/fake_booking', {}),
      throwsA(isA<ApiException>()),
    );
    network.down = false;
    await reopened.revalidate();
    expect(reopened.offline, isFalse);
    expect(
      await reopened.cache.read('/api/reservations', scope, fakeNow),
      isNull,
    );
    await reopened.logout();
    expect(store.values, isEmpty);
  });

  test(
    'a staging outage keeps the saved session and reconnect restores it',
    () async {
      final server = remoteServer('staging');
      final store = MemorySessionStore();
      final initial = remoteAuth(server, store);
      await initial.restore();
      await initial.signIn('synthetic@workspace.invalid', 'fictional-password');
      expect(initial.phase, AuthPhase.authenticated);
      initial.dispose();
      final saved = Map.of(store.values);
      final metadata = server.overrides['/api/client/environment']!;
      server.overrides['/api/client/environment'] = const ApiResponse(
        503,
        '{}',
      );
      final session = remoteAuth(server, store);
      addTearDown(session.dispose);
      await session.restore();
      expect(session.phase, AuthPhase.disconnected);
      expect(store.values, saved);
      server.overrides['/api/client/environment'] = metadata;
      await session.restore();
      expect(session.phase, AuthPhase.authenticated);
      expect(
        server.requests.where((r) => r.path == '/api/login'),
        hasLength(1),
      );
    },
  );

  test(
    'local defaults and existing URL override preserve localhost/ADB reverse',
    () {
      final config = ApiConfiguration.fromBuild(
        environment: 'local',
        origin: '',
      );
      expect(config.origin.toString(), 'http://127.0.0.1:8765');
      expect(config.environment, ApiEnvironment.local);
      expect(
        ApiConfiguration.fromBuild(
          environment: 'local',
          origin: 'http://localhost:9000/',
        ).origin.toString(),
        'http://localhost:9000',
      );
      final auth = makeAuth(FakePms());
      expect(
        auth.storageKey,
        'delvane.business.session.v1.http%3A%2F%2F127.0.0.1%3A8765',
      );
      auth.dispose();
    },
  );

  test('actual build-time values select the intended environment without any connection', () {
    const environment = String.fromEnvironment(
      'DELVANE_ENV',
      defaultValue: 'local',
    );
    const origin = String.fromEnvironment(
      'DELVANE_API_ORIGIN',
      defaultValue: 'http://127.0.0.1:8765',
    );
    final config = ApiConfiguration.fromBuild();
    expect(config.environment.name, environment);
    expect(config.origin.origin, Uri.parse(origin).origin);
  });

  test('the UAT tunnel trust is limited to HTTPS staging on IPv4 loopback', () {
    final tunnelOrigin = Uri.parse('https://127.0.0.1:18443');
    final configuration = ApiConfiguration(
      environment: ApiEnvironment.staging,
      origin: tunnelOrigin,
      uatTunnelCertificate: [1],
    );
    expect(configuration.origin, tunnelOrigin);
    for (final origin in [
      'http://127.0.0.1:18443',
      'https://pms.example.invalid',
      'https://[::1]:18443',
    ]) {
      expect(
        () => ApiConfiguration(
          environment: ApiEnvironment.staging,
          origin: Uri.parse(origin),
          uatTunnelCertificate: [1],
        ),
        throwsArgumentError,
      );
    }
    for (final environment in [
      ApiEnvironment.local,
      ApiEnvironment.production,
    ]) {
      expect(
        () => ApiConfiguration(
          environment: environment,
          origin: tunnelOrigin,
          uatTunnelCertificate: [1],
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => AuthController(
        origin: tunnelOrigin,
        environment: ApiEnvironment.staging,
        store: MemorySessionStore(),
        uatTunnelCertificate: [1],
      ),
      throwsArgumentError,
    );
  });

  test(
    'remote environments require explicit HTTPS origins and have no fallback',
    () {
      for (final environment in ['staging', 'production']) {
        for (final origin in [
          '',
          'http://pms.example.invalid',
          'http://127.0.0.1:8765',
          'https://localhost',
          'https://localhost.',
          'https://pms.example.invalid:0',
          'https://pms.example.invalid:65536',
          'https://127.0.0.1',
          'https://[::1]',
          'https://user:password@pms.example.invalid',
          'https://pms.example.invalid/api',
          'https://pms.example.invalid?token=secret',
          'https://pms.example.invalid#token',
          'not-a-url',
        ]) {
          expect(
            () => ApiConfiguration.fromBuild(
              environment: environment,
              origin: origin,
            ),
            throwsArgumentError,
            reason: '$environment invalid origin',
          );
        }
        final config = ApiConfiguration.fromBuild(
          environment: environment,
          origin: 'https://pms.example.invalid/',
        );
        expect(config.environment.name, environment);
        expect(config.origin.toString(), 'https://pms.example.invalid');
      }
      expect(
        () => ApiConfiguration.fromBuild(environment: 'prod', origin: ''),
        throwsArgumentError,
      );
      expect(
        () => ApiConfiguration.fromBuild(
          environment: 'local',
          origin: 'https://pms.example.invalid',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'checked-in build examples contain only public environment and URL values',
    () {
      for (final name in [
        'local.json',
        'staging.example.json',
        'production.example.json',
      ]) {
        final values = jsonDecode(
          File('config/$name').readAsStringSync(),
        ) as Map<String, dynamic>;
        expect(values.keys.toSet(), {'DELVANE_ENV', 'DELVANE_API_ORIGIN'});
        expect(
          ApiConfiguration.fromBuild(
            environment: values['DELVANE_ENV'],
            origin: values['DELVANE_API_ORIGIN'],
          ).origin.hasAuthority,
          true,
        );
      }
    },
  );

  for (final environment in [
    ApiEnvironment.staging,
    ApiEnvironment.production,
  ]) {
    test(
      '${environment.name} reuses cookie, CSRF, secure storage, restore and logout',
      () async {
        final pms = remoteServer(environment.name);
        final store = MemorySessionStore();
        final auth = remoteAuth(pms, store, environment: environment);
        await auth.restore();
        await auth.signIn(
          'synthetic@workspace.invalid',
          'synthetic-not-persisted',
        );
        expect(auth.phase, AuthPhase.authenticated);
        expect(auth.workspaceId, '${environment.name}:isolated-stage-01');
        final check = pms.requests.first;
        expect(check.path, '/api/client/environment');
        expect(check.headers.containsKey('Cookie'), false);
        expect(
          pms.requests.any((r) => r.path == '/api/development/workspace'),
          false,
        );
        expect(
          store.values.values.single,
          isNot(contains('synthetic-not-persisted')),
        );
        expect(store.values.values.single, isNot(contains(fakeCsrf)));
        auth.dispose();
        final restored = remoteAuth(pms, store, environment: environment);
        addTearDown(restored.dispose);
        await restored.restore();
        expect(restored.phase, AuthPhase.authenticated);
        await restored.logout();
        expect(pms.requests.last.headers['X-Rosa-CSRF'], fakeCsrf);
        expect(store.values, isEmpty);
      },
    );
  }

  for (final body in [
    <String, dynamic>{
      'environment': 'production',
      'deployment_id': 'public-prod-01',
      'secure_cookies': true,
    },
    {
      'environment': 'staging',
      'deployment_id': 'public-stage-01',
      'secure_cookies': false,
    },
    {'environment': 'staging', 'deployment_id': '', 'secure_cookies': true},
    {'isolated': true, 'workspace_id': 'not-a-staging-server'},
  ]) {
    test(
      'remote metadata mismatch blocks credential submission: ${body.keys.join(',')}/${body['environment']}',
      () async {
        final pms = remoteServer('staging');
        pms.overrides['/api/client/environment'] = pms.json(body);
        final auth = remoteAuth(pms, MemorySessionStore());
        addTearDown(auth.dispose);
        await auth.restore();
        await auth.signIn('synthetic@workspace.invalid', 'must-not-send');
        expect(auth.phase, isNot(AuthPhase.authenticated));
        expect(
          pms.requests.every((r) => r.path == '/api/client/environment'),
          true,
        );
        expect(
          pms.requests.every((r) => !r.headers.containsKey('Cookie')),
          true,
        );
      },
    );
  }

  test('staging rejects a non-Secure cookie even when metadata claims secure cookies', () async {
    final pms = remoteServer('staging');
    pms.overrides['/api/login'] = const ApiResponse(
      200,
      '{}',
      setCookies: [
        'rosa_session=$fakeCookie; HttpOnly; Max-Age=604800; Path=/',
      ],
    );
    final auth = remoteAuth(pms, MemorySessionStore());
    addTearDown(auth.dispose);
    await auth.restore();
    await auth.signIn('synthetic@workspace.invalid', 'synthetic');
    expect(auth.phase, AuthPhase.signedOut);
    expect(auth.user, isNull);
  });

  test(
    'same-origin staging/production use separate session namespaces',
    () async {
      final store = MemorySessionStore();
      final staging = remoteAuth(remoteServer('staging'), store);
      final productionServer = remoteServer('production');
      final production = remoteAuth(
        productionServer,
        store,
        environment: ApiEnvironment.production,
      );
      addTearDown(staging.dispose);
      addTearDown(production.dispose);
      await staging.restore();
      await staging.signIn('synthetic@workspace.invalid', 'synthetic');
      await production.restore();
      expect(production.storageKey, isNot(staging.storageKey));
      expect(production.phase, AuthPhase.signedOut);
      expect(productionServer.requests.map((r) => r.path), [
        '/api/client/environment',
      ]);
      expect(store.values.containsKey(staging.storageKey), true);
    },
  );

  test('changing deployment identity drops old credentials before identity requests', () async {
    final pms = remoteServer('staging');
    final store = MemorySessionStore();
    final first = remoteAuth(pms, store);
    await first.restore();
    await first.signIn('synthetic@workspace.invalid', 'synthetic');
    first.dispose();
    pms.requests.clear();
    pms.overrides['/api/client/environment'] = pms.json({
      'environment': 'staging',
      'deployment_id': 'replacement-stage',
      'secure_cookies': true,
    });
    final restored = remoteAuth(pms, store);
    addTearDown(restored.dispose);
    await restored.restore();
    expect(restored.phase, AuthPhase.signedOut);
    expect(store.values, isEmpty);
    expect(pms.requests.map((r) => r.path), ['/api/client/environment']);
  });
}
