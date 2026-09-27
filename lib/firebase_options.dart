import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Registered Firebase apps for the dedicated ARCS project.
class ArcsFirebaseOptions {
  static FirebaseOptions get current {
    if (kIsWeb) {
      return const FirebaseOptions(
        apiKey: 'REMOVED_FIREBASE_API_KEY',
        appId: '1:451692891873:web:a7adc5706e454f0f0d31a0',
        messagingSenderId: '451692891873',
        projectId: 'arcs-online-jeremiah-2026',
        authDomain: 'arcs-online-jeremiah-2026.firebaseapp.com',
        storageBucket: 'arcs-online-jeremiah-2026.firebasestorage.app',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const FirebaseOptions(
          apiKey: 'REMOVED_FIREBASE_API_KEY',
          appId: '1:451692891873:android:5d31fb3e85df63c90d31a0',
          messagingSenderId: '451692891873',
          projectId: 'arcs-online-jeremiah-2026',
          storageBucket: 'arcs-online-jeremiah-2026.firebasestorage.app',
        );
      case TargetPlatform.iOS:
        return const FirebaseOptions(
          apiKey: 'REMOVED_FIREBASE_API_KEY',
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
