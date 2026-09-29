# Game UI research and ARCS changes

Reviewed September 29, 2026. These are design references, not additional ARCS rules.

| Online game reference | Useful interaction pattern | ARCS implementation |
| --- | --- | --- |
| [Board Game Arena UX guidelines](https://en.doc.boardgamearena.com/images/5/57/Guidelines_UX_new_compressed.pdf) | State the current decision prominently; keep the primary action ahead of secondary information; make logs easy to scan after a player returns. | A turn banner names the next decision and jumps to it. The hand or pending action appears before the Court and other reference panels. The move log uses readable card names, starts with six recent entries, and expands on request. |
| [Tabletopia hand and camera controls](https://help.tabletopia.com/knowledge-base/actions-with-game-objects/) | Keep private cards visible only to their owner and provide a way to inspect dense card information and navigate a large table. | The server keeps hands private; the hand now uses larger, suit-colored cards with rank, pips, and available suit actions. The map has fit and zoom controls while preserving selectable locations. |
| [Root Digital UI updates](https://news.direwolfdigital.com/root-patch-1-32-a-fresh-start/) | Selection highlights, readable mobile cards, and unobstructed controls matter on complex maps. | Selected cards have a stronger outline; narrow layouts show the complete map overview and expose the hand and action controls through one page scroll. |

The app retains its own visual style and does not reuse another game's artwork or rules. The remaining manual checks are listed in [next steps](next-steps.md).
