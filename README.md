# ARCS Online

A Flutter web adaptation of the **ARCS base game** with Firebase multiplayer lobbies and a server-validated match engine. The first release is English base-game play for 2–4 players. Android, iPhone, Leaders & Lore and campaign content are deferred.

The web app is live at [arcs-online-jeremiah-2026.web.app](https://arcs-online-jeremiah-2026.web.app/). The production Firebase project is `arcs-online-jeremiah-2026` in `us-west1`.

Players can sign in as guests, link email/password accounts, discover public lobbies or join private invite codes, ready up, and start live or asynchronous games. A match uses the [official August 27, 2025 base rulebook](https://buriedgiant.com/arcs/Arcs_Base_Rulebook.pdf), [official rules and errata](https://rules.buriedgiant.com/), and [official card library](https://cards.buriedgiant.com/). The authoritative game state and hidden hands remain on the server. Firestore exposes only public match information and each player's own hand. Commands run in atomic transactions; turn history and saved games survive reconnects.

The web interface includes a zoomable Reach map, a turn prompt that jumps to the current decision, readable private action cards, illustrated Court cards, battle resolution, ambition scoring, recent moves, and timer-kick voting. Every setup names four active gate regions Vega, Sol, Canopus, and Orion, with any fifth gate named Andromeda or Sirius; each region keeps its planet names. The official numbered clusters and starting positions remain unchanged in saved games and rules logic. The map uses separate colored icons for ships, cities, and starports. Card and piece artwork from the user's offline Haunt Roll Fail reference is **not redistributed**; the app uses [original generated Court illustrations](docs/court-art.md), code-drawn UI visuals, and attributed card text. See the [UI research](docs/ui-research.md), [reference audit](docs/reference-audit.md), and [third-party notices](THIRD_PARTY_NOTICES.md).

## Run locally

Use Flutter, Node.js 22+, Java 21, and the Firebase CLI. From this directory:

```sh
flutter pub get
npm --prefix functions ci
npm --prefix functions run check
npx -y firebase-tools@latest emulators:start --only auth,firestore,functions
flutter run -d chrome --web-port=7357 --dart-define=USE_EMULATORS=true
```

The app uses local Auth, Firestore, and Functions when `USE_EMULATORS=true`; it does not change production data. [Deployment and local setup notes](docs/deployment.md) explain emulator checks and optional configuration.

Google sign-in and guest-account linking are included in the hosted web client. The Firebase project's Google provider and OAuth brand are enabled; a real Google popup still needs a live smoke test. Browser push is optional turn notification and remains deferred. It requires a Firebase Web Push VAPID key supplied as `FCM_VAPID_KEY`; the notification trigger is not deployed yet.

## Verification

`npm --prefix functions run check` compiles the backend and runs 82 rule and state tests, including exact placements for all 12 setups, each base Guild, all six Vox effects, hidden-information projections, timer votes, and scored and unscored full matches. Local emulator checks complete five-chapter matches with 2, 3, and 4 distinct players on two setup cards per count; they also exercise lobby concurrency, private hands, account recovery, and live/async timer votes. `flutter analyze --no-pub`, Flutter tests, and a local web release build pass. A prior disposable production match verified guest sign-in, lobby flow, private hands, one command, and termination; its Firestore documents were removed. Hands-on full-match UI playtesting remains in [next steps](docs/next-steps.md).
