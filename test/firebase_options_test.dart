import 'package:arcs_online/firebase_options.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('Firebase configuration selects $platform and requires its key', () {
      debugDefaultTargetPlatformOverride = platform;
      final suppliedKey = platform == TargetPlatform.android
          ? const String.fromEnvironment('FIREBASE_ANDROID_API_KEY')
          : const String.fromEnvironment('FIREBASE_IOS_API_KEY');
      if (!const bool.fromEnvironment('USE_EMULATORS') && suppliedKey.isEmpty) {
        expect(() => ArcsFirebaseOptions.current, throwsStateError);
      } else {
        final options = ArcsFirebaseOptions.current;
        expect(options.projectId, 'arcs-online-jeremiah-2026');
        expect(
          options.apiKey,
          suppliedKey.isEmpty ? 'arcs-emulator-key' : suppliedKey,
        );
        expect(
          options.appId,
          contains(platform == TargetPlatform.android ? ':android:' : ':ios:'),
        );
        if (platform == TargetPlatform.iOS) {
          expect(options.iosBundleId, 'com.jeremiah.arcsOnline');
        }
      }
    });
  }

  test('unsupported platforms still fail explicitly', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(() => ArcsFirebaseOptions.current, throwsUnsupportedError);
  });
}
