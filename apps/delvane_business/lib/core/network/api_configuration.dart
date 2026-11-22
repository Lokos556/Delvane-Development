import 'dart:io';

enum ApiEnvironment { local, staging, production }

/// Public build configuration only. Never put credentials or API keys here.
class ApiConfiguration {
  ApiConfiguration({
    required this.environment,
    required Uri origin,
    this.uatTunnelCertificate,
  }) : origin = origin.replace(path: '') {
    final loopback =
        origin.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '') ==
            'localhost' ||
        (InternetAddress.tryParse(origin.host.replaceAll(RegExp(r'[\[\]]'), ''))
                ?.isLoopback ??
            false);
    final tunnel = uatTunnelCertificate != null;
    if ((tunnel &&
            (environment != ApiEnvironment.staging ||
                origin.scheme != 'https' ||
                origin.host != '127.0.0.1' ||
                uatTunnelCertificate!.isEmpty)) ||
        origin.host.isEmpty ||
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
            (origin.scheme != 'https' || (loopback && !tunnel)))) {
      throw ArgumentError('Invalid API origin for the selected environment.');
    }
  }

  factory ApiConfiguration.fromBuild({
    String environment = const String.fromEnvironment(
      'DELVANE_ENV',
      defaultValue: 'local',
    ),
    String origin = const String.fromEnvironment('DELVANE_API_ORIGIN'),
    bool enableUatTunnel = const bool.fromEnvironment('DELVANE_UAT_TUNNEL'),
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
    List<int>? certificate;
    if (enableUatTunnel) {
      final path = Platform.environment['DELVANE_UAT_TLS_CERTIFICATE'];
      if (!Platform.isWindows ||
          selected != ApiEnvironment.staging ||
          parsed.scheme != 'https' ||
          parsed.host != '127.0.0.1' ||
          path == null ||
          path.isEmpty) {
        throw ArgumentError(
          'The Windows UAT tunnel requires a trusted certificate.',
        );
      }
      try {
        certificate = File(path).readAsBytesSync();
      } on FileSystemException {
        throw ArgumentError(
          'The Windows UAT tunnel certificate is unavailable.',
        );
      }
    }
    return ApiConfiguration(
      environment: selected,
      origin: parsed,
      uatTunnelCertificate: certificate,
    );
  }

  final ApiEnvironment environment;
  final Uri origin;
  final List<int>? uatTunnelCertificate;
  bool get isLocal => environment == ApiEnvironment.local;
}
