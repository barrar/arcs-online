# ARCS Online

Flutter and Firebase groundwork for a multiplayer adaptation of the **ARCS base game**. The project targets web, Android, and iOS. This repository is **not yet a playable rules-complete game**: the host cannot start a match until the authoritative game engine, setup maps, battle, and all Court effects are implemented and verified. The UI keeps match start disabled for that reason.

## What works locally

- Responsive Flutter lobby UI with an original space theme, public listing, private invite codes and links, ready status, and a visual board preview.
- Guest sign-in and client flows for linking an email/password or Google credential. Cloud provider activation and mobile OAuth configuration are still required.
- Firebase callable functions for creating, joining, leaving, and readying lobbies. Mutations are validated and transactional. Hosts can choose a 2–10-minute live timer or a 24/48-hour asynchronous timer.
- Pure rules modules for the 12 base setup layout choices, map topology, action-card/round flow, and ambition scoring, with unit tests. Starting-piece placement is not encoded yet. A unanimous overdue kick rule is implemented as a pure reducer but is not connected to live games yet.
- A dated snapshot of the official 25 Guild and 6 Vox base Court cards, available in the in-app card browser. Card effects are not yet executable.
- Firestore rules limiting access to lobbies, games, and each player's hand. The emulator authorization test covers private data and denied client writes.

See [rules coverage](docs/rules-coverage.md) for the exact implemented and missing rule families.

## Project configuration

Production Firebase project: `arcs-online-jeremiah-2026` (`us-west1`). The web, Android, and iOS apps are registered, and the default Firestore database exists. Local development uses Firebase emulators and the Flutter `USE_EMULATORS` define; it does not use production data. No server credentials belong in this repository.

The [hosted web preview](https://arcs-online-jeremiah-2026.web.app) is live. Guest sign-in, public/private lobbies, invite codes, ready status, the card library, and the board preview work in production. A two-guest private lobby flow passed a production smoke test on 2026-09-27. The local Auth, Functions, and Firestore emulator flow also passed a multiplayer lobby integration test. Matches remain disabled because the complete ARCS rules engine is unfinished.

The public Firebase app identifiers are in `lib/firebase_options.dart`, `android/app/google-services.json`, and `ios/Runner/GoogleService-Info.plist`. Anonymous and email/password sign-in are enabled through `firebase.json`; Google linking still needs a support email and provider configuration. The project is on Blaze and the five lobby Functions are deployed. The hosted preview explicitly does not claim to be a playable game. See [deployment steps](docs/deployment.md).

## Toolchain and local run

Install Flutter, Node.js 22, Java 21, Firebase CLI, Android SDK for Android builds, and a complete Xcode iOS platform for iPhone builds. A temporary Flutter SDK and JDK were used during initial development and are not part of the repository.

```sh
flutter pub get
npm --prefix functions ci
npm --prefix functions run check
firebase emulators:start --only auth,firestore,functions
flutter run -d chrome --dart-define=USE_EMULATORS=true
```

Run the Firestore authorization test while the Firestore emulator is active:

```sh
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 node functions/security/check-firestore.cjs
node functions/security/check-lobbies.cjs
```

Build targets:

```sh
flutter build web --release
flutter build apk --release
flutter build ios --release --no-codesign
```

The web release build and Flutter analyzer passed on 2026-09-25. Mobile builds are deferred at the user's request. The local Xcode installation lacks the iOS 26.4 platform, and the Android SDK is not installed. These are build-environment issues, separate from the incomplete gameplay implementation.

## Source of game rules

The implementation is based on the [official base rulebook, August 27, 2025](https://buriedgiant.com/arcs/Arcs_Base_Rulebook.pdf), [publisher rules and errata](https://rules.buriedgiant.com/), and [publisher card library](https://cards.buriedgiant.com/). The Court catalog was captured on 2026-09-25. Leaders & Lore and campaign content are outside the planned first release.

The [haunt-roll-fail ARCS source](https://github.com/haunt-roll-fail/haunt-roll-fail/tree/main/haunt-roll-fail/arcs) is a useful MIT-licensed implementation reference. Its action-card pip and map data were cross-checked against the rulebook and credited in [third-party notices](THIRD_PARTY_NOTICES.md). It does not contain every base setup, so it is not treated as a substitute for the official rules.

The user also supplied a complete offline build of that game. The [reference audit](docs/reference-audit.md) records its asset inventory, the 12 setup diagrams it exposes, the five setups present in the readable source, and why the embedded artwork is not copied into this project.
