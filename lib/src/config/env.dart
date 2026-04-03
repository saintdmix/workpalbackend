// Place in: lib/src/config/env.dart
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

    // Fallback to the default Firebase bucket naming convention.
    final projectId = _dotenv['FIREBASE_PROJECT_ID']?.trim();
    if (projectId != null && projectId.isNotEmpty) {
      return '$projectId.appspot.com';
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
