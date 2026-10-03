import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Registered Firebase apps for the dedicated ARCS project.
class ArcsFirebaseOptions {
  static String _apiKey(String name, String value) {
    if (value.isNotEmpty) {
      return value;
    }
    if (const bool.fromEnvironment('USE_EMULATORS')) {
      return 'arcs-emulator-key';
    }
    throw StateError(
      'Missing $name. Use scripts/flutter.sh or pass '
      '--dart-define-from-file=.firebase.local.json.',
    );
  }

  static FirebaseOptions get current {
    if (kIsWeb) {
      return FirebaseOptions(
        apiKey: _apiKey(
          'FIREBASE_WEB_API_KEY',
          const String.fromEnvironment('FIREBASE_WEB_API_KEY'),
        ),
        appId: '1:451692891873:web:a7adc5706e454f0f0d31a0',
        messagingSenderId: '451692891873',
        projectId: 'arcs-online-jeremiah-2026',
        authDomain: 'arcs-online-jeremiah-2026.firebaseapp.com',
        storageBucket: 'arcs-online-jeremiah-2026.firebasestorage.app',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return FirebaseOptions(
          apiKey: _apiKey(
            'FIREBASE_ANDROID_API_KEY',
            const String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
          ),
          appId: '1:451692891873:android:5d31fb3e85df63c90d31a0',
          messagingSenderId: '451692891873',
          projectId: 'arcs-online-jeremiah-2026',
          storageBucket: 'arcs-online-jeremiah-2026.firebasestorage.app',
        );
      case TargetPlatform.iOS:
        return FirebaseOptions(
          apiKey: _apiKey(
            'FIREBASE_IOS_API_KEY',
            const String.fromEnvironment('FIREBASE_IOS_API_KEY'),
          ),
          appId: '1:451692891873:ios:d55ebc010c0c63bc0d31a0',
          messagingSenderId: '451692891873',
          projectId: 'arcs-online-jeremiah-2026',
          storageBucket: 'arcs-online-jeremiah-2026.firebasestorage.app',
          iosBundleId: 'com.jeremiah.arcsOnline',
        );
      default:
        throw UnsupportedError(
          'ARCS Online supports web, Android, and iPhone.',
        );
    }
  }
}
