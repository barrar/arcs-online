# ARCS base-game rules coverage

Rules baseline: [official ARCS Base Rulebook, August 27, 2025](https://buriedgiant.com/arcs/Arcs_Base_Rulebook.pdf), [official rules and errata](https://rules.buriedgiant.com/), and [official card library](https://cards.buriedgiant.com/). Every new match stores `arcs-base-2025-08-27` as its rules version. The first playable release is the English base game; Leaders & Lore and the campaign are excluded.

| Rule family | Source | Implementation |
| --- | --- | --- |
| Setup for 2–4 players | Rulebook pp. 4–5 | All 12 printed setup cards, active clusters, exact A/B/C placements, two starting resources, initial Court row, action hands, two-player phantom resources and mulligan. |
| Map, control and piece limits | Rulebook pp. 6–7, 22 | Active planet/gate adjacency, path markers, building slots, fresh-ship control, damage, supplies, trophies, captives, Outrage, and end-of-turn ship recovery. |
| Action-card rounds | Rulebook pp. 8–11 | Server-owned private hands; lead, declaration, surpass, copy, pivot, seizure, pass, initiative, pips, Prelude, and chapter transition. |
| Standard actions | Rulebook pp. 12–13 | Tax, Build, Move/Catapult, Repair, Influence, Secure, including action limits and ownership/control conditions. |
| Battle and raids | Rulebook pp. 14–16 | All printed die faces; dice and raid limits; ordered self, intercept, ship and building hits; damage/destruction; Outrage, Ransack, raid-key costs, and Skirmishers reroll. |
| Resources and Court | Rulebook pp. 17, 20; official card library | Resource slots, spending/conversion, supply and score icons; all 25 base Guilds and 6 Vox effects, including card-specific actions, modifiers, theft, burial, and Court refill. |
| Scoring and victory | Rulebook pp. 18–19 | Ambition markers, ties, qualifying, city bonuses, two-player phantom scorer, cleanup, card redraw, threshold or fifth-chapter victory. |
| Hidden information and commands | Rulebook p. 22; product specification | Authoritative state in a server-only document; per-seat hands; public projections; Firestore read restrictions; validated, atomic, idempotent callable commands. |
| Session timer | Product specification | Configurable live and asynchronous deadlines; unanimous vote from every other seated player to end an overdue match with no official winner. |

## Verification record

The backend suite has 82 passing rule and state tests. It covers all setup cards, round play, standard actions, battle, every base Guild's distinct behavior, all six Vox effects, hidden-information projection, scored and unscored full matches at 2, 3 and 4 players, and unanimous timer votes. Local Firebase emulator checks pass for Firestore access, public/private lobbies, match start, private hands, denied reads and writes, concurrent duplicate commands, event history, Google/email account recovery, and live/async timer votes. Six complete callable-driven five-chapter matches use distinct players and two setup cards at each supported player count. These automated matches select legal cards and end turns; they do not substitute for hands-on use of every action, battle, and Court prompt in the browser.

The six integration matches used `2p-homelands`, `2p-frontiers`, `3p-core-conflict`, `3p-frontiers`, `4p-mix-up-2`, and `4p-mix-up-3`. The callable run took 125, 180, and 240 commands per match at 2, 3, and 4 players respectively. The timer integration check covered a 2-minute live match and 24- and 48-hour asynchronous matches. The local web build, Flutter analysis, and five map/name tests pass; the 2- and 4-player boards were visually inspected at desktop and narrow widths. A complete browser playthrough and real Google popup smoke test are still required before a release claim.

The earlier production web build, Authentication configuration, Firestore rules/indexes, and gameplay callables are deployed. A disposable production two-player match verified guest authentication, private lobby flow, match start, restricted hands, command submission, and termination; its Firestore documents were removed afterward. The Google provider and OAuth brand are now enabled, but the newer Google sign-in UI is local only until the next authorized Hosting deployment. Android and iPhone builds remain deferred by request. Browser push requires a Firebase Web Push VAPID key passed as `FCM_VAPID_KEY`; its turn-notification trigger is not deployed. Push is optional and does not block gameplay.
