# ARCS base-game rules coverage

Rules baseline: [official ARCS Base Rulebook, August 27, 2025](https://buriedgiant.com/arcs/Arcs_Base_Rulebook.pdf), with [official rules/errata](https://rules.buriedgiant.com/) and [official card library](https://cards.buriedgiant.com/). The baseline must be pinned to each game document once games can start. No match can start in the current build.

| Rule family | Source | Current implementation | Remaining work |
| --- | --- | --- | --- |
| 2–4-player lobby and timer choice | Product specification | Transactional lobby functions and pure unanimous overdue vote rule | Connect vote to actual game documents and notify players |
| Setup, map, starting pieces and hands | Rulebook pp. 4–6 | Pure base map topology, planet resource types and building slots; all 12 layout names and active clusters encoded from the user-provided diagrams | Encode each setup card's starting-piece labels, initial placement, private dealing, two-player mulligan, and integrate map data with game state; see [reference audit](reference-audit.md) |
| Core control and damage | Rulebook pp. 6–7 | Pure control function counts fresh ships and ties | Integrate with server board state, damage/destruction and piece limits |
| Action card rounds | Rulebook pp. 8–11 | Pinned 28-card pip table and pure reducer for lead, declaration, surpass, copy, pivot, seize, pips, pass and initiative; eight tests | Integrate with authoritative hands, action execution and chapter lifecycle |
| Standard actions | Rulebook pp. 12–16 | None | Implement tax, build, move/catapult, repair, influence, secure and all combat/raiding choices |
| Resources and Guild cards | Rulebook pp. 17, 20 | Official 31-card base Court snapshot and browser | Implement prelude spending, resource limits/raid costs, every Guild and Vox effect, modifier priority |
| Chapter end and victory | Rulebook pp. 18–19 | Pure ambition strength/scoring, two-player phantom scorer, thresholds and initiative tiebreak; six tests | Integrate markers/flip, cleanup, new hands and endgame with game state; test full games at 2, 3 and 4 players |
| Fine print and errata | Rulebook pp. 22–23; official errata | Source links documented | Apply hierarchy, piece limits, concessions, replacement and all relevant errata |
| Hidden information | Rulebook p. 22 | Firestore rules and emulator test for per-player hands, private lobbies and server-only writes | Wire actual games to the schema and test command concurrency/reconnects |

## Verification record

As of 2026-09-27, `npm --prefix functions run check` passes 28 pure backend tests, the Firestore emulator authorization test passes, and a local Auth/Functions/Firestore integration test passes for concurrent lobby joins and other lifecycle events. `flutter analyze` and `flutter build web --release` pass. Firebase Hosting, Firestore rules, Anonymous and email/password Authentication, and five callable lobby Functions are deployed. A production private lobby test passed with two anonymous guests, permitted Firestore reads, ready status, and departures; public async lobby discovery also passed. The game cannot start; no full-game, mobile-device, notification, account-linking, or timer-vote integration test has passed.
