# Web release and local development

The Flutter web release is live at [arcs-online-jeremiah-2026.web.app](https://arcs-online-jeremiah-2026.web.app/). The Firebase project is `arcs-online-jeremiah-2026` in `us-west1` on Blaze. Anonymous, email/password, and Google Authentication providers are enabled. Firestore rules and indexes, and the lobby and game callables are deployed. The current local web build has newer account and map UI changes; it has **not** been deployed to Hosting. A prior production smoke test passed for guest sign-in, a private lobby, match start, hidden hands, command submission, and termination. The disposable match, lobby, and invite-code documents were deleted afterward.

From the project root, use Node.js 22+, Java 21, Flutter, and a current Firebase CLI:

```sh
flutter pub get
npm --prefix functions ci
npm --prefix functions run check
npx -y firebase-tools@latest emulators:start --only auth,firestore,functions
flutter run -d chrome --web-port=7357 --dart-define=USE_EMULATORS=true
```

To serve a release build with Firebase Hosting's local rewrite behavior instead, run `flutter build web --release --dart-define=USE_EMULATORS=true`, then `npx -y firebase-tools@latest emulators:start --only hosting` in another terminal. Hosting defaults to `http://127.0.0.1:5000`.

The app uses local Authentication, Firestore and Functions when `USE_EMULATORS=true`. No production match data is changed. To verify emulator access, start the emulators and run:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node functions/security/check-firestore.cjs
node functions/security/check-lobbies.cjs
node functions/security/check-game.cjs
node functions/security/check-auth.cjs
node functions/security/check-timers.cjs
node functions/security/check-full-games.cjs
```

Google sign-in and guest linking are implemented in the local web client. The Google provider was enabled with display name **ARCS Online** and support email `jeremiah.barrar@gmail.com` through the Firebase CLI. Emulator tests cover linking and return sign-in, but a real Google popup has not been smoke-tested on the hosted build because the newer client has not been deployed. Browser notifications require a Web Push key from Firebase Cloud Messaging settings, supplied with `--dart-define=FCM_VAPID_KEY=...`. The service worker and turn-notification trigger are in source, but the trigger is not deployed yet. Push remains deferred.

For later web releases, run `npm --prefix functions run check` and `flutter build web --release` **without** `USE_EMULATORS=true`. Deploy the gameplay Functions, Auth configuration and Firestore rules/indexes before `npx -y firebase-tools@latest deploy --only hosting --project arcs-online-jeremiah-2026`. A full Functions deploy will also attempt the deferred `notifyTurn` trigger; retry it only when configuring browser push. Android and iPhone are deferred.
