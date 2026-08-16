# Forgotten Roads for Erenshor — live test matrix

This is the ordered checklist for the exact release candidate. A deterministic test, source review, or successful build does not mark a live row as passed.

Legend: `PASS` = confirmed on the exact candidate; `FAIL` = confirmed broken on the exact candidate; `PENDING` = not yet exercised; `N/A` = not applicable.

## Ordered session

1. Start the game and record loaded versions for all enabled modules.
2. Verify Hub launch, navigation arrows, UI click containment, and camera containment.
3. Verify Journal launch, entry persistence, and restart behavior.
4. Verify Party Tools launch, controls, and camera containment.
5. Verify one complete Practice Duel lifecycle.
6. Verify a continuous Follow multi-hop expedition.
7. Verify Deep Sims direct conversation, party back-and-forth, session reference, Wiki routing, and news routing.
8. Verify Crafting gather interaction, custom icons, and combat eligibility.
9. Verify Contracts accept, complete, exactly-once gold/XP claim, raid deferral, and restart persistence.
10. Verify one complete PvP match, cleanup, reward, zone behavior, and restart behavior.
11. Verify Campmaster Hunt Camp/Relax party transitions, zoning, and restart behavior.
12. Verify Nemesis selection, lifecycle, duplicate prevention, zoning, and persistence.

## Current exact-candidate status

| Module | Exact-candidate live status | Required proof |
|---|---|---|
| Deep Sims | PENDING | Direct relevance, party thread, session reference, Wiki/news route, and no party-state contradiction |
| Party Tools | PENDING | Launch, control flow, drag/camera containment, restart |
| Contracts | PENDING | Accept → complete → one gold/XP claim → no duplicate → restart; safe raid deferral |
| Journal | PENDING | Launch, entry persistence, restart |
| Guild Life | PENDING | Player-ready, UI, bulletin persistence |
| Campmaster | PENDING | Hunt Camp/Relax behavior, party transition, zone, restart |
| Nemesis | PENDING | Selection, lifecycle, duplicate prevention, zone, restart |
| Crafting Expanded | PENDING | Gather, icons, combat eligibility, preview scope |
| Practice Duel | PENDING | Full match lifecycle and cleanup |
| PvP | PENDING | Full match, cleanup, reward, zone, restart |
| Follow | PENDING | One continuous multi-hop expedition |
| Suite Hub | PENDING | Launch, navigation, click/camera containment, routing |

## Evidence policy

Record a short, player-observable result for each completed row. Keep logs, private paths, machine data, and development-process notes out of public release documentation.
