# ARCS Online

**A multiplayer adaptation of the ARCS base game, built for the web with Flutter, Firebase, and TypeScript.**

[Play the hosted app](https://arcs.bendtrailmaps.com) · [Rules coverage](docs/rules-coverage.md) · [Court artwork](docs/court-art.md)

ARCS Online brings a 2–4-player tabletop game into a browser without reducing it to a local hot-seat app. Players can create public or private lobbies, join by invite code, play live or asynchronously, and return to a saved match. The game engine validates actions on the server; each player sees the shared board and their own hand while other hands stay private.

The project implements the English **base game**. The rules baseline is the [official base rulebook](https://buriedgiant.com/arcs/Arcs_Base_Rulebook.pdf), [rules and errata](https://rules.buriedgiant.com/), and [card library](https://cards.buriedgiant.com/). Every match records its rules version.

## What is in the app

- **Multiplayer sessions:** guest accounts, email/password and Google account linking, public lobby discovery, private invite codes, ready status, reconnects, and saved games.
- **Match flow:** 2–4-player starting setups, action-card rounds, Prelude and resource actions, movement, building, taxing, Court influence and security, combat and raids, ambitions, chapter scoring, and victory.
- **Readable game UI:** a zoomable map, distinct ship/city/starport markers, per-player ship counts in crowded systems, illustrated Court cards, contextual action menus, battle dice results, and event history.
- **Flexible pace:** short live turn timers or 24/48-hour asynchronous turns. An overdue-player removal requires unanimous approval from the other seated players and ends the match without an official winner.

The interface uses original Court illustrations and code-drawn pieces and resources. The board's creative place names are presentation labels; saved games and rules logic retain the official system IDs. See [art provenance](docs/court-art.md), the [reference audit](docs/reference-audit.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

## Architecture

~~~mermaid
flowchart LR
    P[Flutter web client] --> A[Firebase Authentication]
    P --> V[Firestore public game and lobby views]
    P --> H[Firestore: player's private hand]
    P --> C[Callable game commands]
    C --> R[TypeScript rules engine]
    R --> S[Private authoritative game state]
    R --> V
    R --> H
~~~

The client submits an intention, such as *move these ships* or *influence this Court card*. A callable Function checks the current turn and rule constraints, applies the command in a Firestore transaction, and updates the views players are allowed to read. The server owns hidden hands and authoritative state. Command IDs make retries idempotent, and an event stream records the resulting moves. Firestore rules prevent clients from writing game state directly or reading another player's hand.

The rules engine is separate from Flutter widgets, so setup, actions, combat, Court effects, scoring, and multiplayer access can be checked independently. [Rules coverage](docs/rules-coverage.md) maps each major rule family to its official source and describes the verification already performed.

## Run locally

You need a recent Flutter SDK, Node.js 22+, Java 21 for the Firestore emulator, and the Firebase CLI. Chrome is used for the Flutter web development target.

~~~sh
git clone https://github.com/barrar/arcs-online.git
cd arcs-online
flutter pub get
npm --prefix functions ci
npm --prefix functions run build
~~~

Start Firebase's local Auth, Firestore, and Functions emulators in one terminal:

~~~sh
npx -y firebase-tools@latest emulators:start --only auth,firestore,functions
~~~

Then start the web client in another terminal:

~~~sh
./scripts/flutter.sh run -d chrome --web-port=7357 --dart-define=USE_EMULATORS=true
~~~

The emulator flag routes app traffic to local services. Leave it off only when you intend to connect to the configured Firebase project. For a local release build, use the following command and serve build/web with the Firebase Hosting emulator. See [local and deployment notes](docs/deployment.md).

~~~sh
./scripts/flutter.sh build web --release --dart-define=USE_EMULATORS=true
~~~

## Deploy

The checked-in Firebase configuration and deployment script target **arcs-online-jeremiah-2026**. You need access to that project and a signed-in Firebase CLI account. Its Authentication providers must include Anonymous, Email/Password, and Google. Cloud Functions require a billing-enabled Firebase project.

Deploy rules and gameplay Functions when backend code changes:

~~~sh
npx -y firebase-tools@latest login
npm --prefix functions ci
npm --prefix functions run build
npx -y firebase-tools@latest deploy --only firestore --project arcs-online-jeremiah-2026
npx -y firebase-tools@latest deploy --only functions:createLobby,functions:joinLobby,functions:leaveLobby,functions:setReady,functions:startGame,functions:submitGameCommand --project arcs-online-jeremiah-2026
~~~

Create your private local Firebase configuration as described in [Firebase configuration](docs/firebase-config.md), then publish the web client with the repository script:

~~~sh
./scripts/deploy-web.sh
~~~

The script verifies the target project, runs the backend and Flutter checks, builds a production web bundle, and deploys **Hosting only**. Set FLUTTER_BIN=/path/to/flutter if Flutter is not on your PATH. It does not publish changed Functions or Firestore rules. The optional browser-push notification Function is outside this release path.

Firebase API-key values are kept in the ignored `.firebase.local.json`, never in tracked source. See [Firebase configuration](docs/firebase-config.md) for setup and rotation. For another Firebase project, update the public app identifiers in `lib/firebase_options.dart`, `scripts/firebase-config.cjs`, and the native templates, plus `.firebaserc` and the deployment script project guard. Keep that project's keys in your own local file.

## Project map and status

| Path | Purpose |
| --- | --- |
| lib/ | Flutter screens, board layout, cards, and Firebase client |
| functions/src/ | Typed game state, rules, validated commands, and callable Functions |
| functions/security/ | Emulator integration and access checks |
| assets/ | Court card catalog and original illustrations |
| docs/ | Rule coverage, art provenance, research, and deployment notes |

The repository includes rule and integration checks; npm --prefix functions run check runs the backend suite, and flutter analyze plus flutter test check the client. A complete hands-on browser playthrough at each player count and a live Google sign-in popup check remain on the [next-steps list](docs/next-steps.md). Android and iPhone builds, browser push, Leaders & Lore, and campaign content are deferred.

ARCS Online is an unofficial fan project and is not affiliated with the publisher. ARCS names and rules belong to their respective owners; third-party source attribution is collected in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
