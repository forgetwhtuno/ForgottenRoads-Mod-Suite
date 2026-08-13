# UI Runtime Contract

Status: Hub implementation **VERIFIED SOURCE**; sibling migration **NEEDS LIVE TEST**.

## Geometry

Launcher:

- height 28-34px (Hub: 30px);
- narrow drag-only grip (Hub: 20px);
- button starts at/after the grip boundary and never overlaps it;
- compact open/closed indicator;
- clamp every runtime rect to current screen bounds.

Main/dedicated windows:

- title/header is the only drag surface;
- header buttons are excluded from the drag rect;
- body, lists, toggles, text controls, and scroll views never drag the window;
- Reset Position restores a known on-screen default.

## Pointer capture

Pure hover is insufficient. Required behavior:

```text
left mouse down over owned mod UI -> capture=true
while button remains down         -> capture remains true even outside rect
mouse up / unload / UI hidden     -> capture=false
```

World-click and camera-look suppression should consult `capture || pointerOverUi`.

This prevents the PvP-style failure in which a drag exits the panel and begins rotating the game
camera or changing the world target.

## Persistence

- Runtime `Rect` is authoritative while dragging.
- Do not continuously reconstruct the runtime rect from config during a drag.
- Mark the rect dirty when it changes; save after a bounded debounce, close, and unload.
- Recover NaN/infinite/off-screen/oversized persisted values by clamping.

## IMGUI lifecycle

Do not flip open/closed state during a `GUILayout`/`GUI.Window` event pass. Convert UI clicks into
pending requests and apply lifecycle mutation in `Update` so Layout/Repaint see a stable tree.

## Harmony coexistence

Standalone mods retain their own guards while the Hub is optional. Do not make a sibling mod call
into Hub static state to decide whether a world click is safe. If a future independent shared
runtime centralizes guards, capability detection and standalone fallback must be explicit so only
one guard owns the shared path at a time.

## Cleanup

On Lunaris unload:

- clear pointer/drag capture;
- restore any temporarily muted camera state;
- release cursor ownership;
- destroy owned textures/GameObjects;
- remove event/Aura subscriptions/providers;
- unpatch Harmony owned by that plugin;
- clear static instance references.
