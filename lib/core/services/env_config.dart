import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  static String get cloudinaryCloudName =>
      _required('CLOUDINARY_CLOUD_NAME');
  static String get cloudinaryApiKey => _required('CLOUDINARY_API_KEY');
  static String get cloudinaryApiSecret =>
      _required('CLOUDINARY_API_SECRET');

  static String get firebaseWebApiKey => _required('FIREBASE_WEB_API_KEY');
  static String get firebaseWebAppId => _required('FIREBASE_WEB_APP_ID');
  static String get firebaseWebMeasurementId =>
      _required('FIREBASE_WEB_MEASUREMENT_ID');
  static String get firebaseWindowsAppId =>
      _optional('FIREBASE_WINDOWS_APP_ID', fallback: firebaseWebAppId);
  static String get firebaseWindowsMeasurementId => _optional(
    'FIREBASE_WINDOWS_MEASUREMENT_ID',
    fallback: firebaseWebMeasurementId,
  );

  static String get firebaseAndroidApiKey =>
      _required('FIREBASE_ANDROID_API_KEY');
  static String get firebaseAndroidAppId =>
      _required('FIREBASE_ANDROID_APP_ID');

  static String get firebaseIosApiKey => _required('FIREBASE_IOS_API_KEY');
  static String get firebaseIosAppId => _required('FIREBASE_IOS_APP_ID');
  static String get firebaseIosBundleId =>
      _required('FIREBASE_IOS_BUNDLE_ID');

  static String get firebaseProjectId => _required('FIREBASE_PROJECT_ID');
  static String get firebaseMessagingSenderId =>
      _required('FIREBASE_MESSAGING_SENDER_ID');
  static String get firebaseAuthDomain => _required('FIREBASE_AUTH_DOMAIN');
  static String get firebaseDatabaseUrl => _required('FIREBASE_DATABASE_URL');
  static String get firebaseStorageBucket =>
      _required('FIREBASE_STORAGE_BUCKET');

  static String _required(String key) {
    final value = dotenv.env[key]?.trim() ?? '';
    if (value.isEmpty) {
      throw StateError('Missing required env key: $key');
    }
    return value;
  }

  static String _optional(String key, {required String fallback}) {
    final value = dotenv.env[key]?.trim() ?? '';
    return value.isEmpty ? fallback : value;
  }
}
