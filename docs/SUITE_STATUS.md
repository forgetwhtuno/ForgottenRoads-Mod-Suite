# Forgotten Roads for Erenshor — current status

This document describes the current public release posture. Individual module repositories are authoritative for their source and tests. The ordered live matrix remains the authority for gameplay certification.

## Collection status

- Deterministic suites: passing for the current local candidate set.
- Native build/install and active-plugin identity: blocked in this session because the current Lunaris identity resolver is unavailable; no fresh DLL certification is claimed.
- Exact-candidate live certification: pending; do not infer live success from static/build evidence.
- Green RC Ready: none until the relevant exact-candidate live matrix is completed.
- No module currently carries a build, installed-hash, or live result for its current source. Merging a candidate to `main` satisfies the merge gate only; it is not release certification.

## Gate separation

These are separate gates and must never be reported as one status:

| Gate | Satisfied by |
|---|---|
| MERGE | Reviewed source plus the module's deterministic suites, on an acceptable candidate merged to canonical `main` |
| BUILD | The exact canonical source rebuilt, producing a recorded artifact hash |
| INSTALLED HASH | The installed artifact hash verified equal to the built artifact |
| LIVE CANDIDATE | The ordered live matrix passed against that exact installed artifact |
| RESTART/PERSISTENCE | Restart and persistence proof where the module claims it |
- Runtime compatibility identities: preserved. Public repository branding does not rename DLLs, plugin GUIDs, save keys, config paths, Harmony IDs, or protocol identifiers.

| Module | Version | Current evidence | Live requirement |
|---|---:|---|---|
| Deep Sims | 0.7.6 | Source/static evidence; current build/live pending | Single-model grounded social pipeline plus fail-closed runtime hooks and standalone Follow ownership |
| Party Tools | 0.1.6 | Source and deterministic tests | Hub/UI, drag, camera, and restart validation |
| Contracts | 0.4.5 | Source and deterministic tests | Mob-only generated targets, locality, target quality, accept/complete, exactly-once claim, restart persistence, and raid-claim safety |
| Journal | 0.1.8 | Source only; prior build/install evidence retired because source changed | Journal UI and persistence validation |
| Guild Life | 0.1.3 | Source only; prior build/install evidence retired because source changed | Focused live UI, gesture ownership, camera containment, and player-ready validation |
| Campmaster | 0.4.0 | Source/test evidence | Focused camp/relax workflow, party transitions, zoning, and restart validation |
| Nemesis | 0.3.0 | Source/static evidence; current build/live pending | Automatic persistent rival, two-way chat, optional Deep Sims voice, native chat presentation |
| Crafting Expanded | 0.2.4 | Source and deterministic tests | Foraging/crafting preview matrix; native production recipe proof remains blocked |
| Practice Duel | 0.4.6 | Source/static evidence; current build/live pending | Bidirectional virtual damage, targeted self-heal with the opponent still selected, actor-aware AoE containment, repeat duel, cleanup |
| PvP | 0.5.10 | Source/static evidence; current build/live pending | Live unproven: native proxy lifecycle/nav, per-proxy Start fault isolation, countdown/GO containment, inactive-AI reward safety, two consecutive 5v5 plus restart |
| Follow | 0.6.4 | Source, deterministic tests, and candidate build evidence | One continuous multi-hop expedition on the exact candidate DLL |
| Suite Hub | 0.5.3 | Source, deterministic tests, and candidate build evidence | Hub launch, dock/UI arrows, camera containment, and module routing validation |

## Historical development notes

Earlier phase descriptions, pre-retained-uGUI architecture notes, and checkpoint-branch references are historical context only. They must not be read as a statement of current release readiness or current module integration.
