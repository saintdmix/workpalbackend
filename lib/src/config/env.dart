// Place in: lib/src/config/env.dart
import 'dart:io';

import 'package:dotenv/dotenv.dart';

class AppEnv {
  AppEnv._();

  static final DotEnv _dotenv = DotEnv(includePlatformEnvironment: true)
    ..load();

  static String get firebaseWebApiKey => _readRequired('FIREBASE_WEB_API_KEY');
  static String get firebaseProjectId => _readRequired('FIREBASE_PROJECT_ID');
  static String get firebaseStorageBucket {
    final raw = _dotenv['FIREBASE_STORAGE_BUCKET']?.trim();
    if (raw != null && raw.isNotEmpty) return raw;

    // Fallback: modern Firebase projects use .firebasestorage.app
    final projectId = _dotenv['FIREBASE_PROJECT_ID']?.trim();
    if (projectId != null && projectId.isNotEmpty) {
      final bucket = '$projectId.firebasestorage.app';
      stderr.writeln(
        '[env] FIREBASE_STORAGE_BUCKET not set — '
        'falling back to: $bucket',
      );
      return bucket;
    }

    throw StateError(
      'Missing env var: FIREBASE_STORAGE_BUCKET. '
      'Add it to .env or set it in the environment.',
    );
  }

  static String _readRequired(String key) {
    final value = _dotenv[key]?.trim();
    if (value == null || value.isEmpty) {
      throw StateError(
        'Missing env var: $key. Add it to .env or process environment.',
      );
    }
    return value;
  }
}
