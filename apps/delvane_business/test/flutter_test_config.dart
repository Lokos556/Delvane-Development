import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:delvane_business/core/localization/web_strings.dart';

/// Existing workflow tests assert English copy explicitly. Production still
/// defaults to Hungarian; localization tests use fresh instances for both locales.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Preferences and session tests must never read the host credential vault.
  FlutterSecureStorage.setMockInitialValues({});
  WebStrings.current.language = 'en';
  await testMain();
}
