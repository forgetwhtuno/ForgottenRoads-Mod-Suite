# Forgotten Roads for Erenshor — current status

This document describes the current public release posture. Individual module repositories are authoritative for their source and tests. The ordered live matrix remains the authority for gameplay certification.

## Collection status

- Deterministic suites: passing for the current local candidate set.
- Native build/install and active-plugin identity: blocked in this session because the current Lunaris identity resolver is unavailable; no fresh DLL certification is claimed.
- Exact-candidate live certification: pending; do not infer live success from static/build evidence.
- Green RC Ready: none until the relevant exact-candidate live matrix is completed.
- Runtime compatibility identities: preserved. Public repository branding does not rename DLLs, plugin GUIDs, save keys, config paths, Harmony IDs, or protocol identifiers.

| Module | Version | Current evidence | Live requirement |
|---|---:|---|---|
| Deep Sims | 0.7.4 | Source and deterministic tests | Relevant direct conversation, party thread, session-memory, Wiki/news routing, and party-state checks |
| Party Tools | 0.1.6 | Source and deterministic tests | Hub/UI, drag, camera, and restart validation |
| Contracts | 0.4.4 | Source and deterministic tests | Locality, target quality, accept/complete, exactly-once claim, restart persistence, and raid-claim safety |
| Journal | 0.1.8 | Source and deterministic tests | Journal UI and persistence validation |
| Guild Life | 0.1.3 | Source and deterministic tests | Focused live UI and player-ready validation |
| Campmaster | 0.4.0 | Source/test evidence | Focused camp/relax workflow, party transitions, zoning, and restart validation |
| Nemesis | 0.2.0 | Source/test evidence | Rival selection, lifecycle, duplicate prevention, zoning, and persistence validation |
| Crafting Expanded | 0.2.4 | Source and deterministic tests | Foraging/crafting preview matrix; native production recipe proof remains blocked |
| Practice Duel | 0.4.1 | Source, deterministic tests, and candidate build evidence | Complete local-party duel lifecycle validation |
| PvP | 0.5.4 | Source, deterministic tests, and candidate build evidence | Complete match, cleanup, reward, zoning, and restart validation |
| Follow | 0.6.4 | Source, deterministic tests, and candidate build evidence | One continuous multi-hop expedition on the exact candidate DLL |
| Suite Hub | 0.5.3 | Source, deterministic tests, and candidate build evidence | Hub launch, dock/UI arrows, camera containment, and module routing validation |

## Historical development notes

Earlier phase descriptions, pre-retained-uGUI architecture notes, and checkpoint-branch references are historical context only. They must not be read as a statement of current release readiness or current module integration.
