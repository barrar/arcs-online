# Web release and local development

The Flutter web release is live at [arcs.bendtrailmaps.com](https://arcs.bendtrailmaps.com). The Firebase project is `arcs-online-jeremiah-2026` in `us-west1` on Blaze. Anonymous, email/password, and Google Authentication providers are enabled. Firestore rules and indexes, and the lobby and game callables are deployed. The September 30, 2026 Hosting release includes Court-targeted Secure and Influence selection, colored per-player agent counts, full-art views for owned Guild cards, and the responsive map and scrolling title bar. It also includes the earlier account and map UI changes and all 31 original Court illustrations. The deployment script passed 82 backend tests, Flutter analysis and tests, and its live `index.html`, `flutter_bootstrap.js`, and `main.dart.js` matched the production build byte for byte. A game deep link returned HTTP 200. A prior production smoke test passed for guest sign-in, a private lobby, match start, hidden hands, command submission, and termination; its disposable documents were deleted afterward. A full match has not been repeated against this client release.

The latest phone-map update enlarges system labels and building icons, places a ship total just outside each system, and groups the pop-up's ships by owner with fresh and damaged counts. City and starport owners and damage labels remain visible. The deployed two-player game was checked at 390 × 844, including planet, city, starport, and gate details; the live web files matched the release build.

From the project root, use Node.js 22+, Java 21, Flutter, and a current Firebase CLI:

```sh
flutter pub get
npm --prefix functions ci
npm --prefix functions run check
npx -y firebase-tools@latest emulators:start --only auth,firestore,functions
./scripts/flutter.sh run -d chrome --web-port=7357 --dart-define=USE_EMULATORS=true
```

To serve a release build with Firebase Hosting's local rewrite behavior instead, run `./scripts/flutter.sh build web --release --dart-define=USE_EMULATORS=true`, then `npx -y firebase-tools@latest emulators:start --only hosting` in another terminal. Hosting defaults to `http://127.0.0.1:5000`.

The app uses local Authentication, Firestore and Functions when `USE_EMULATORS=true`. No production match data is changed. To verify emulator access, start the emulators and run:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node functions/security/check-firestore.cjs
node functions/security/check-lobbies.cjs
node functions/security/check-game.cjs
node functions/security/check-auth.cjs
node functions/security/check-timers.cjs
node functions/security/check-full-games.cjs
```

Google sign-in and guest linking are implemented in the hosted web client. The Google provider was enabled with display name **ARCS Online** and support email `jeremiah.barrar@gmail.com` through the Firebase CLI. Emulator tests cover linking and return sign-in, but a real Google popup has not been smoke-tested on the hosted build. Browser notifications require a Web Push key from Firebase Cloud Messaging settings, supplied with `--dart-define=FCM_VAPID_KEY=...`. The service worker and turn-notification trigger are in source, but the trigger is not deployed yet. Push remains deferred.

Production builds require the ignored `.firebase.local.json`; copy `config/firebase.example.json` and fill in the three keys. See [Firebase configuration](firebase-config.md). The build prepares the ignored native and notification-worker configuration from that file. For a production web release from any working directory, run:

```sh
./scripts/deploy-web.sh
```

The script checks backend and Flutter code, builds the Flutter web client without the emulator setting, and uses the current Firebase CLI to deploy **Hosting only** to `arcs-online-jeremiah-2026`. It verifies the configured project and Hosting output directory before starting. It uses `flutter` from your PATH; if needed, set `FLUTTER_BIN=/path/to/flutter`. A signed-in Firebase CLI account with access to the project is required.

When backend code or configuration changes, deploy the gameplay Functions, Auth configuration, and Firestore rules/indexes separately before running this script. A full Functions deploy will also attempt the deferred `notifyTurn` trigger; retry it only when configuring browser push. Android and iPhone are deferred.

## Firebase key rotation

All three original Firebase client API keys were revoked after deploying and verifying their replacements. API-key values remain in the ignored owner-only `.firebase.local.json`; no key values belong in source or history. The replacement web key allows the ARCS custom/Firebase domains and local development origins; the iOS key allows `com.jeremiah.arcsOnline`. Android retains API restrictions while mobile signing remains deferred. All replacements retain the existing Firebase API allowlist for compatibility, excluding Generative Language.

The replacement web release passed 29 Flutter tests and a production build. Both live domains matched the build. Live API checks passed for anonymous sign-in, token refresh, guest/email linking, email sign-in, private lobby operations, and Firestore access. Temporary test users and lobby documents were deleted. Google popup and browser-push checks remain deferred. Existing browser tabs may need a reload after revocation.

Hosting now revalidates bootstrap, bundle, and worker files to reduce stale-key caching. The game backend was not redeployed during the key rotation. Its existing `auto_turn.test.ts` resource-rearrangement assertion currently fails; the other 85 backend tests passed. Flutter analysis has 66 informational style diagnostics in existing app files.
