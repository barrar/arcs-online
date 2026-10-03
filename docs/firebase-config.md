# Firebase configuration

The three Firebase client API keys have one source of truth: `.firebase.local.json` in the project root. This file is ignored by Git. Never commit actual values, including in test scripts or documentation.

For production access, copy `config/firebase.example.json` to `.firebase.local.json`, fill in the web, Android, and iOS keys for `arcs-online-jeremiah-2026`, and restrict the file to its owner:

```sh
cp config/firebase.example.json .firebase.local.json
chmod 600 .firebase.local.json
```

Use the project wrapper so Flutter receives the file without putting keys on the command line:

```sh
./scripts/flutter.sh run -d chrome
./scripts/flutter.sh build web --release
./scripts/flutter.sh build apk --release
./scripts/flutter.sh build ios --release --no-codesign
./scripts/flutter.sh test
```

The wrapper regenerates ignored `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`, and `web/firebase-config.js` from tracked templates and the local file. These are build inputs, not additional manually maintained key stores. The web notification worker imports the generated web configuration. A direct Flutter command requires both `node scripts/firebase-config.cjs` first and `--dart-define-from-file=.firebase.local.json` on the run/build/test command. `scripts/deploy-web.sh` already does both.

The local file may contain `FCM_VAPID_KEY` for optional browser push. Keep `USE_EMULATORS` out of that file so production builds cannot silently target local services. Emulator development does not require real API keys:

```sh
./scripts/flutter.sh run -d chrome --web-port=7357 --dart-define=USE_EMULATORS=true
./scripts/flutter.sh build web --release --dart-define=USE_EMULATORS=true
```

Manual production smoke scripts read this same local file. They create production test data and must be run intentionally. A browser-referrer-restricted key may reject their Node requests; use a separate appropriately restricted test key if needed rather than relaxing the production browser key.

Ignoring this file removes API-key values from source control. Firebase SDKs still need these values in deployed JavaScript and mobile binaries, and the worker configuration is served publicly. These Firebase identification keys are public by design. Their API restrictions, authentication, Firestore rules, and App Check protect the project; a local file does not make compiled client keys confidential.

For rotation, create replacement keys in the same Firebase project with the required Firebase API allowlist; exclude non-Firebase paid APIs such as Generative Language. Test application restrictions with replacement keys before tightening the live keys. Update the local file, rebuild, validate guest/email/Google sign-in, token refresh, Firestore access, callable Functions, and push if enabled, then deploy/release every affected client. Account for cached browser tabs and installed mobile clients before deleting the old keys. If there is active abuse, restrict or revoke the abused key immediately even if this interrupts old clients. Do not delete the Firebase project, registered apps, users, or database to rotate API keys.
