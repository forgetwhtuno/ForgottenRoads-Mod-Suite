# UI Design — Suite Hub

## Compact launcher

Style matches the suite's existing dark-cyan launcher family (Journal/Contracts/Guild Life/PvP),
not a bright/purple reference. Approx 28-34px tall, 90-125px wide.

```
[::]  MODS  [o]
 |     |     |
 grip  label indicator/toggle
 18px  center right
```

- **Left (18px, fixed)**: dedicated grip. This is the *only* draggable area
  (`GUI.DragWindow(new Rect(0, 0, 18, Height))`), matching Journal's proven interaction model —
  never let the drag rect overlap the click area, that overlap is the confirmed root cause of the
  launcher click/drag bugs found and fixed in Contracts, Guild Life, and PvP this session.
- **Center/right**: "MODS" or "SUITE" label plus a small open/closed indicator. This whole
  remaining area is a single `GUI.Button` — the *only* click action, toggling the main window.
- Position persists (same pattern as every other suite launcher: two floats in that mod's native
  Lunaris config, clamped to screen bounds on every draw).
- Only visible once `IsLocalCharacterReady()` (or the Hub's own equivalent of that verified
  signal) is true. Never shown at title screen, character select, or any loading state.

## Main suite window

Opened by clicking the launcher's button area. One movable window, header-drag only (matches
Part 10's requirement for every dedicated panel across the suite, not just the Hub).

```
+----------------------------------------------------+
| Erenshor Suite                              [reset] [x] |
+--------+---------------------------------------------+
| Overview |                                            |
| Deep Sims|   (selected tab's content)                 |
| Party T. |                                            |
| Follow   |                                            |
| Campmst. |                                            |
| Duel     |                                            |
| PvP      |                                            |
| Nemesis  |                                            |
| Crafting |                                            |
| Contracts|                                            |
| Guild L. |                                            |
| Journal  |                                            |
+--------+---------------------------------------------+
```

- Left nav lists a tab only for mods actually detected/installed — never a tab for a mod that
  isn't present.
- Each mod tab follows the same section order: **STATUS**, **CONTROLS**, **SETTINGS**,
  **OPEN PANEL** (if that mod has a dedicated panel), **DIAGNOSTICS** (only where genuinely
  useful, not a dumping ground for every internal timestamp — put anything obscure/developer-only
  behind an **Advanced** foldout instead of the default view).
- Per-mod content spec: see `Erenshor-Mod-Suite`'s `docs/CURRENT_WORK.md` for phase status, and
  the suite-direction task's Part 9 for the exact field list intended for each mod's tab (Deep
  Sims: Ollama/model status, social mode, roleplay mode, party members, memory/session status;
  PvP: enabled indicator, protected/high-risk status, arranged/ambush toggles, pending-challenge
  state, score summary, Open Panel button; etc. — reproduced there rather than duplicated here to
  avoid the two docs drifting apart).

## Dedicated panels (Journal, Contracts, Guild Life, PvP, Crafting, and potentially Party
Tools/Follow/Duel)

One shared interaction model across all of them:

- Movable by title/header only — body/controls never drag.
- No world-camera passthrough, no world-target click passthrough while the pointer is over the
  panel (the click-through guard pattern already proven in Journal/Contracts/Guild Life/PvP).
- Position persists after a drag *finishes*, not continuously reconstructed mid-drag (PvP's
  current panel does this and it's implicated in its drag-into-camera bug — see
  `docs/CURRENT_WORK.md`).
- Runtime `Rect` is the source of truth while dragging; only written back to persisted config once
  the drag ends.
- Never gets stuck permanently off-screen — clamp to current screen bounds every draw, same as
  every launcher in the suite already does.
- A reset-position control, always reachable regardless of how badly the panel is currently
  positioned.

## Shared UI containment (Phase 2+, not yet built)

See `docs/ARCHITECTURE.md`'s "Shared UI containment" section. The target shape is a small
`SuiteUiInput.IsPointerCaptured` / `IsDragActive` surface that every mod's world-click/camera-look
Harmony guard can consult, replacing N slightly-different copies of the same containment logic —
but only once it's clear this doesn't force a hard Suite Hub runtime dependency onto mods that
should keep working standalone, and does not stack redundant Harmony patches on the same native
method from multiple mods where one shared patch would do.
