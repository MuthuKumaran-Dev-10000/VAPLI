import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:lubrication_indicator/core/services/env_config.dart';

class FirebaseEnvOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'Firebase options are not configured for linux.',
        );
      default:
        throw UnsupportedError(
          'Firebase options are not supported for this platform.',
        );
    }
  }

  static FirebaseOptions get web => FirebaseOptions(
    apiKey: EnvConfig.firebaseWebApiKey,
    appId: EnvConfig.firebaseWebAppId,
    messagingSenderId: EnvConfig.firebaseMessagingSenderId,
    projectId: EnvConfig.firebaseProjectId,
    authDomain: EnvConfig.firebaseAuthDomain,
    databaseURL: EnvConfig.firebaseDatabaseUrl,
    storageBucket: EnvConfig.firebaseStorageBucket,
    measurementId: EnvConfig.firebaseWebMeasurementId,
  );

  static FirebaseOptions get android => FirebaseOptions(
    apiKey: EnvConfig.firebaseAndroidApiKey,
    appId: EnvConfig.firebaseAndroidAppId,
    messagingSenderId: EnvConfig.firebaseMessagingSenderId,
    projectId: EnvConfig.firebaseProjectId,
    databaseURL: EnvConfig.firebaseDatabaseUrl,
    storageBucket: EnvConfig.firebaseStorageBucket,
  );

  static FirebaseOptions get ios => FirebaseOptions(
    apiKey: EnvConfig.firebaseIosApiKey,
    appId: EnvConfig.firebaseIosAppId,
    messagingSenderId: EnvConfig.firebaseMessagingSenderId,
    projectId: EnvConfig.firebaseProjectId,
    databaseURL: EnvConfig.firebaseDatabaseUrl,
    storageBucket: EnvConfig.firebaseStorageBucket,
    iosBundleId: EnvConfig.firebaseIosBundleId,
  );

  static FirebaseOptions get macos => ios;

  static FirebaseOptions get windows => FirebaseOptions(
    apiKey: EnvConfig.firebaseWebApiKey,
    appId: EnvConfig.firebaseWindowsAppId,
    messagingSenderId: EnvConfig.firebaseMessagingSenderId,
    projectId: EnvConfig.firebaseProjectId,
    authDomain: EnvConfig.firebaseAuthDomain,
    databaseURL: EnvConfig.firebaseDatabaseUrl,
    storageBucket: EnvConfig.firebaseStorageBucket,
    measurementId: EnvConfig.firebaseWindowsMeasurementId,
  );
}
