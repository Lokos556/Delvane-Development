import 'dart:io';

enum ApiEnvironment { local, staging, production }

/// Public build configuration only. Never put credentials or API keys here.
class ApiConfiguration {
  ApiConfiguration({required this.environment, required Uri origin})
    : origin = origin.replace(path: '') {
    final loopback =
        origin.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '') ==
            'localhost' ||
        (InternetAddress.tryParse(origin.host.replaceAll(RegExp(r'[\[\]]'), ''))
                ?.isLoopback ??
            false);
    if (origin.host.isEmpty ||
        origin.port < 1 ||
        origin.port > 65535 ||
        RegExp(r'\s').hasMatch(origin.host) ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/') ||
        !{'http', 'https'}.contains(origin.scheme) ||
        (environment == ApiEnvironment.local &&
            (!loopback ||
                (origin.scheme == 'http' &&
                    !{
                      'localhost',
                      '127.0.0.1',
                      '::1',
                      '[::1]',
                    }.contains(origin.host)))) ||
        (environment != ApiEnvironment.local &&
            (origin.scheme != 'https' || loopback))) {
      throw ArgumentError('Invalid API origin for the selected environment.');
    }
  }

  factory ApiConfiguration.fromBuild({
    String environment = const String.fromEnvironment(
      'DELVANE_ENV',
      defaultValue: 'local',
    ),
    String origin = const String.fromEnvironment('DELVANE_API_ORIGIN'),
  }) {
    final selected = switch (environment) {
      'local' => ApiEnvironment.local,
      'staging' => ApiEnvironment.staging,
      'production' => ApiEnvironment.production,
      _ => throw ArgumentError(
        'DELVANE_ENV must be local, staging or production.',
      ),
    };
    if (origin.isEmpty && selected != ApiEnvironment.local) {
      throw ArgumentError('A remote API origin must be explicitly configured.');
    }
    final parsed = Uri.tryParse(
      origin.isEmpty ? 'http://127.0.0.1:8765' : origin,
    );
    if (parsed == null) throw ArgumentError('Invalid API origin.');
    return ApiConfiguration(environment: selected, origin: parsed);
  }

  final ApiEnvironment environment;
  final Uri origin;
  bool get isLocal => environment == ApiEnvironment.local;
}
