# Live Test Matrix

The authoritative checklist for what has actually been confirmed in the running game, as opposed
to what's only been confirmed at compile/deterministic-test time. Update this whenever a live
session actually exercises a row for a mod — do not mark anything PASS from static reasoning
alone.

Legend: `PASS` (live-confirmed working) · `FAIL` (live-confirmed broken, see notes) · `-`
(not yet tested) · `N/A` (doesn't apply to this mod).

## Suite-wide rows

| Row | DeepSims | PartyTools | Contracts | Journal | GuildLife | Campmaster | Nemesis | Crafting | Duel | PvP | Follow |
|---|---|---|---|---|---|---|---|---|---|---|---|
| load | - | - | - | - | - | - | - | - | - | - | - |
| menu visibility (no launcher/panel before character ready) | N/A | - | - | PASS (before this session's changes) | - | N/A | N/A | - | - | - | N/A |
| central tab (Suite Hub) | - | - | - | - | - | - | - | - | - | - | - |
| dedicated panel | N/A | - | - | PASS | - | N/A | N/A | - | - | FAIL (see notes) | - |
| drag | N/A | - | - | PASS | - | N/A | N/A | - | - | FAIL (see notes) | - |
| camera containment | N/A | - | - | - | - | N/A | N/A | - | - | - | - |
| target containment | N/A | - | - | - | - | N/A | N/A | - | - | - | - |
| zone (survives zone transition) | - | - | - | - | - | - | - | - | - | - | - |
| character swap (per-character data correct) | N/A | N/A | - | - | - | N/A | - | N/A | N/A | N/A | N/A |
| unload | - | - | - | - | - | - | - | - | - | - | - |
| reload | - | - | - | - | - | - | - | - | - | - | - |
| repeat reload | - | - | - | - | - | - | - | - | - | - | - |
| core feature | PASS (Ollama/group chat) | - | - | - | - | - | - | - | - | PASS (encounter/combat) | - |

## Notes

- **PvP / drag / dedicated panel = FAIL**: dragging the full `PvpPanel` can jump/stick at
  top-left and move the world camera. Known, unresolved, tracked in `docs/CURRENT_WORK.md`. The
  launcher fix (grip/button separation) does not touch this — it's a separate bug in the panel's
  own drag handling.
- **PvP / core feature = PASS**: encounter/combat itself had a good live result this session. Do
  not disturb it while working on anything else PvP-related.
- **Journal**: rows marked PASS reflect the live state *before* this session's player-ready-gate /
  per-character-storage / diagnostic changes. Those changes have build/test verification only —
  re-confirm these rows on the next live pass rather than assuming they still hold.
- **Duplicate Lunaris plugin instance** is not a row here because it's not mod-specific — see
  `docs/CURRENT_WORK.md`'s dedicated section. It should be checked before trusting any "drag" or
  "central tab" result across the whole suite, since two coexisting `GUI.Window` instances with
  the same ID is a plausible explanation for flaky results in either row.
- **Natural PvP ambush** has not been observed. This is untested, not a failure — check the
  configured ambush timing/chance defaults and confirm the player is standing in an allowed
  ambush zone with PvP/ambush enabled before drawing any conclusion.
