import 'dart:io';

/// Native builds have no browser metadata.
Future<Map<String, dynamic>?> webMeta() async => null;

/// True when running under `flutter test` (the tool sets FLUTTER_TEST in
/// the test process environment). The tracker stays completely silent
/// there: no network, no timers, nothing pending at test teardown.
bool get isTestEnv => Platform.environment['FLUTTER_TEST'] == 'true';
