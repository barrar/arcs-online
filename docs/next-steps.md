# ARCS web app: next steps

This list is for the English, official **2–4-player base game**. Continue using the local Firebase emulators. Do not deploy another build until the user explicitly asks for production deployment.

## 1. Prove full matches through hands-on play

- [x] Complete five-chapter matches through the local Firebase backend with 2, 3, and 4 distinct guest players on at least two setup cards at each count. The emulator script exercises the real lobby, hand, command, chapter, and victory paths.
- [ ] Play one complete local match at each supported player count (2, 3, and 4), using distinct guest accounts or browser profiles. Exercise more than one setup card at each count.
- [ ] For each match, check setup placements, every turn and action prompt, combat and raids, Court cards, chapter scoring, victory, and the final event history against the [official base rulebook](https://buriedgiant.com/arcs/Arcs_Base_Rulebook.pdf) and [rules and errata](https://rules.buriedgiant.com/).
- [ ] Record each discrepancy with the setup card, game state, command, expected rule, and actual result; fix confirmed rule or UI defects before release.

## 2. Close the remaining rules-test gaps

- [x] Add official-card-library-cited tests for each of the 25 base Guild effects, including their distinct behavior and shared card families.
- [x] Exercise all six Vox effects through Court security and pending-choice resolution, with chapter-boundary coverage in the rule suite.
- [x] Add regressions for the discovered Farseers and Call to Action bottom-of-discard behavior. Existing rule tests cover battle order, Outrage, ambition ties, and two-player phantom scoring.

## 3. Finish the in-game web interface

- [x] Replace raw card IDs in action and Court choice dialogs with readable card names and effect text; spell out action-card suits in hand labels.
- [ ] Check the two-player square map and the three-/four-player maps at desktop and narrow browser widths. The two- and four-player layouts and map accessibility labels have been inspected; the three-player layout and new zoom controls need a final visual check.
- [ ] Review keyboard navigation, screen-reader labels, color contrast, and loading/error states for lobbies and active matches.
- [ ] Verify that a page reload restores the correct hand, selected/pending decision, current actor, timer, and event history without losing a turn.

## 4. Exercise multiplayer and account flows

- [x] Test public discovery and private invite codes, ready-up, match start, simultaneous duplicate commands, and a player leaving and rejoining a lobby. Backend-driven full matches repeatedly reconnect to public and private game views.
- [x] Test guest-to-Google and guest-to-email/password linking and sign-in through fresh local client identities; confirm saved-game and own-hand access and deny other hands.
- [x] Test live and 24/48-hour asynchronous deadlines, including early-vote rejection, unanimous approval, no official winner, and unchanged pieces.
- [ ] Repeat the local Firestore access checks after any backend or rules change so a client cannot read another player's hand or write authoritative state directly.

## 5. Release gate, only when requested

- [ ] Re-run backend checks, Flutter analysis/tests, local emulator checks, and a production-mode web build.
- [x] On explicit instruction, publish the reviewed web build and verify the hosted home page, an existing saved game, and Court images.
- [ ] Smoke-test a disposable production match against the newly hosted client; remove only its disposable test data afterward.
- [x] Update the deployment notes with the release checks and remaining limitations.

**Deferred by request:** Android and iPhone builds, browser push, Leaders & Lore, and campaign content. Google Authentication and the newer sign-in UI are hosted; a real Google popup still needs a live smoke test. Five-player play is outside the official base game.
