# ErenshorSuite.UI — shared contract, not a hard dependency

This directory documents the small UI contract shared across independently loadable suite mods. It
is **not** a runtime framework DLL and must not make sibling mods depend on `ErenshorSuiteHub.dll`.
Each mod keeps its own retained-uGUI implementation/fallback while following the same behavior.

## Production contract

- retained Unity uGUI (`Canvas`, `CanvasScaler`, `GraphicRaycaster`, `RectTransform`, `CanvasGroup`,
  TMP, `Button`, scroll/layout components);
- reuse the game's existing EventSystem;
- mod-owned Suite drag handler;
- `GameData.DraggingUIElement` claimed only during owned drag and released on every cleanup path;
- normalized position persistence and screen clamping;
- visible `X` and Reset Position where a movable dedicated panel exists;
- no new production OnGUI/GUILayout/GUI.Window/GUI.DragWindow;
- no native `DragUI` / no `GameData.EditUIMode` dependency;
- no required global hotkey for normal access.

## Shared visual family

Use the canonical Sim Actions-derived tokens in `docs/UI_DESIGN.md`: dark translucent panel,
cyan/soft-cyan framing, compact square controls, restrained hover/pressed states, primary/accent/
secondary/warning text.

Disclosure uses a right/down chevron with a full-row hit target. Boolean state uses explicit ON/OFF
(or an equally clear checkbox/switch) and never reuses the disclosure mark.

## Refresh contract

Keep structure and values separate:

- nav structure = ordered rendered rows; selection updates retained row visuals in place;
- page structure = page identity, capability/action/setting schema, disclosure/global developer
  availability;
- dynamic state = status/warning/current values/action result; mutate retained controls in place.

Current setting values are not part of a structural signature.

## Optional Hub transport

The Hub integration remains Lunaris Aura string/primitive IPC, documented in
`docs/HUB_INTEGRATION_CONTRACT.md`. No shared contract assembly is required.

Dedicated closeable panels may expose `ui.state` and standard `closePanel` for centralized quick
close. A module keeps its own local Escape fallback until Hub presence explicitly reports
`quickClose=1` **and that module's own `ui.state` + `closePanel` provider registered successfully**;
`quickClose=0` means the contract exists but native Escape consumption is not bound.

## Launcher fallback

A module must remain reachable without the Hub. If the Hub is missing/unusable or the module's own
bridge is not registered, its standalone launcher remains available. A Hub `showLauncher` setting
can add visibility; it never removes the only entry point.
