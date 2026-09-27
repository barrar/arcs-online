# ARCS implementation reference audit

The user supplied `hrf--arcs--0.8.160--offline.html`, an offline build of [Haunt Roll Fail's ARCS game](https://github.com/haunt-roll-fail/haunt-roll-fail/tree/main/haunt-roll-fail/arcs). It is a useful implementation and visual reference, not the rules authority. Resolve rule questions against the [official base rulebook](https://buriedgiant.com/arcs/Arcs_Base_Rulebook.pdf), [official rules and errata](https://rules.buriedgiant.com/), and [official card library](https://cards.buriedgiant.com/).

The 101 MB bundle contains 1,049 embedded images and an approximately 3.4 MB compiled script. The images include all 28 numbered action cards, six faces for each of the three battle dice, ship/city/starport pieces, map layers, and all 12 base setup-card diagrams. It also contains Leaders & Lore and campaign assets, which remain outside this release.

| Players | Setup diagrams present in the bundle |
| --- | --- |
| 2 | Frontiers; Mix Up 1; Homelands; Mix Up 2 |
| 3 | Mix Up; Frontiers; Homelands; Core Conflict |
| 4 | Mix Up 1; Mix Up 2; Frontiers; Mix Up 3 |

The readable source at commit `d157b02` defines only five of those setups: three-player Mix Up, Frontiers, and Core Conflict; four-player Mix Up 1 and Mix Up 2. The presence of an image does **not** mean that a setup or rule is implemented in that engine. Our project still needs independently encoded and verified setup data for all 12 diagrams, especially every two-player layout.

The source code has an MIT license, which is recorded in [third-party notices](../THIRD_PARTY_NOTICES.md). The embedded card art and piece images depict the publisher's game artwork and are not included in this repository or web build. They are retained only in the user's original local file and temporary inspection files. The app uses its own UI artwork and a text catalog attributed to the official card library until image redistribution rights are clear.
