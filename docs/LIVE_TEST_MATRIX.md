# Forgotten Roads for Erenshor — live test matrix

This is the ordered checklist for the exact release candidate. A deterministic test, source review, or successful build does not mark a live row as passed.

Legend: `PASS` = confirmed on the exact candidate; `FAIL` = confirmed broken on the exact candidate; `PENDING` = not yet exercised; `N/A` = not applicable.

A live row can only be marked `PASS` against an artifact that was built from the current source and whose installed hash was verified. If source changes after a row passes, that row returns to `PENDING`.

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
| Journal | PENDING | Rebuild and reinstall first (recorded artifact predates current source), then launch, entry persistence, restart |
| Guild Life | PENDING | Rebuild and reinstall first (recorded artifact predates current source), then player-ready, UI, gesture ownership, camera containment, bulletin persistence |
| Campmaster | PENDING | Hunt Camp/Relax behavior, party transition, zone, restart |
| Nemesis | PENDING | Selection, lifecycle, duplicate prevention, zone, restart |
| Crafting Expanded | PENDING | Gather, icons, combat eligibility, preview scope |
| Practice Duel | PENDING | Duel starts; both sides deal virtual damage; with the opponent still targeted a legitimate SelfOnly/ApplyToCaster/InflictOnSelf heal applies to the caster and does not heal the opponent, with normal resource/cooldown behavior; duel continues; a second duel runs without restart; AoE and cleanup containment hold |
| PvP | PENDING | Exact current DLL with one canonical plugin identity; arranged 5v5 showing 3/2/1/GO, no pre-GO damage, attackers move and engage, damage lands in both directions, native combat/spell behavior occurs; one failed proxy does not destroy a viable match; reward only on a legitimate outcome; second consecutive 5v5 without restart; restart then smoke match |
| Follow | PENDING | One continuous multi-hop expedition |
| Suite Hub | PENDING | Launch, navigation, click/camera containment, routing |

## Evidence policy

Record a short, player-observable result for each completed row. Keep logs, private paths, machine data, and development-process notes out of public release documentation.
