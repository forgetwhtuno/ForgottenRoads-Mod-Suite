# Suite Status

Central status is intentionally conservative. Individual repos/draft branches remain authoritative.

| Mod | Central status | Test classification in `suite.json` | Player-facing UI observed in source |
|---|---|---|---|
| Deep Sims | NEEDS LIVE TEST | standalone deterministic | command/status driven |
| Party Tools | NEEDS LIVE TEST | standalone deterministic | Party Tools panel |
| Contracts | NEEDS LIVE TEST | standalone deterministic | launcher + contract board |
| Journal | NEEDS LIVE TEST | standalone deterministic | launcher + journal window |
| Guild Life | NEEDS LIVE TEST | standalone deterministic | launcher + guild window |
| Campmaster | NEEDS LIVE TEST | standalone deterministic + control API suite | command/control API |
| Nemesis | NEEDS LIVE TEST | standalone deterministic + in-game selftest | command driven |
| Crafting Expanded | BLOCKED for release polish | standalone deterministic | crafting window |
| Practice Duel | NEEDS LIVE TEST | standalone deterministic + in-game selftest | command driven |
| PvP | NEEDS LIVE TEST overall; combat LIVE VERIFIED | **in-game selftest** (`/epvp selftest`) | dedicated PvP panel |
| Follow | NEEDS LIVE TEST | standalone deterministic | contextual Sim menu / travel overlay (no dedicated general panel) |
| Suite Hub | NEEDS LIVE TEST | standalone deterministic | launcher + central window |

`BUILD_ALL.ps1` consumes the declared `testScripts` arrays rather than equating "no root
RUN_TESTS.ps1" with "no tests." PvP is correctly classified as an in-game selftest rather than an
offline deterministic runner.

## Phase plan

**Phase 1** (delivered): central repo, manifest/setup/build/install, docs and the live-test
matrix, Suite Hub skeleton, an Overview page, installed-mod discovery, a working compact launcher,
and the duplicate-instance investigation.

**Phase 2** (delivered this pass, Hub side only — see below): versioned Aura wire bridge
(`describe`/`settings.*`/`setting.set`/`action`), the canonical readiness state machine, mutable
bool/choice setting editors, two-argument actions, and a Hub self-presence endpoint. **No sibling
mod implements the `SuiteAuraProvider` adapter yet** — that is the next phase of work, tracked per
mod in `docs/CURRENT_WORK.md`.

**Phase 3** (not started): per-mod `SuiteAuraProvider` adapters wired to each mod's own
`ControlApi`, dedicated-panel `openPanel` integration for Journal/Contracts/Guild Life/PvP/
Crafting, and canonical-readiness-based fallback-launcher suppression on the mod side.

Each phase gets its own build/test/PR/live-test cycle before the next one starts. Nothing gets
merged automatically at a phase boundary.

## Suite Hub — exact current scope

**Repo:** [ErenshorSuiteHub](https://github.com/forgetwhtuno/ErenshorSuiteHub), public, `main`
branch, GUID `forgetwhtuno.erenshor.suitehub`, version `0.2.0`.

**What exists (Phase 1 + Phase 2 Hub-side work):**

- `src/HubLauncher.cs` — compact grip+button launcher (drag-only grip strip, non-overlapping
  `GUI.Button` action surface).
- `src/GameplayReadinessPolicy.cs` — the canonical positive-state-plus-`CanMove`-acquisition-plus-
  ~1s-debounce readiness state machine (`CharacterSelect -> PlayerObjectCreating ->
  ZoneTransition -> WorldInitializing -> Stabilizing -> Ready`). Every native member it reads
  (`GameData.InCharSelect`, `GameData.Zoning`, `GameData.PlayerControl`, `PlayerControl.Myself`,
  `PlayerControl.CanMove`, `Character.MyStats`, `GameData.SimMngr`, `GameData.SimPlayerGrouping`)
  was confirmed present via reflection against the real installed `Assembly-CSharp.dll` during this
  integration pass.
- `src/HubWindow.cs` — one movable window, header-drag only, installed-only left navigation, an
  Overview page, and a per-module page with common controls (dedicated-panel open button when
  advertised), common settings (mutable bool toggle, mutable choice `< value >` cycle control,
  read-only text/number), and Basic/Advanced/Developer tiers.
- `src/ErenshorSuiteHubPlugin.cs` — plugin entry point; readiness/toggle/close mutation deferred
  out of `OnGUI` into `Update()`; click-through guard via `[HarmonyPatch(typeof(PlayerControl),
  "LeftClick")]` and a `csMouseOrbit.LateUpdate` camera-look mute; also registers the Hub's own
  live-presence Aura provider (`forgetwhtuno.erenshor.suitehub.v1.describe`) and unregisters it in
  `OnDestroy`.
- `src/AuraModuleBridge.cs` — per-module Aura subscriber bridge implementing the full v1 wire
  contract: `describe`, `settings.basic/advanced/developer`, `setting.set`, and **two-argument**
  `action(actionId, argument)`. A bridge object exists for every catalog module ID even when that
  module is entirely absent, so Hub-first/mod-first/unload/late-reload all work without a load-
  order dependency.
- `src/SuiteWireCodec.cs` / `src/SuiteModuleRegistry.cs` — pure, unit-tested wire parsing and
  registration policy, including bounded `choice` `options` parsing/validation (a mutable choice
  setting must declare non-empty options and a value drawn from them).
- `src/SuiteModuleCatalog.cs` — the 11-module catalog; `follow` is `HasDedicatedPanel = false` per
  the canonical contract (Follow remains a contextual Sim menu/travel overlay, not a general Hub
  panel).
- `src/ModDiscovery.cs` — file-presence-only installed-mod discovery, unchanged in spirit from
  Phase 1.

**Verified vs. not verified:**

- Compile-verified: builds cleanly with `csc.exe` against the real installed
  `Assembly-CSharp.dll`/Lunaris/Unity assemblies (net48, C# 5-safe legacy-compiler style). Compiled
  output references only `mscorlib`, `Lunaris`, `0Harmony` (vendored Lunaris dependency, not
  BepInEx), `UnityEngine.*`, `Assembly-CSharp`, `System`/`System.Core` — zero BepInEx references.
- Deterministic-test-verified: `RUN_TESTS.ps1` runs the full `tests/` suite (readiness policy, mod
  discovery, module registry including the Follow/PartyTools catalog assertions, wire codec
  including the new choice-options coverage, UI geometry) — 92 assertions, all passing.
- Installed: staged and built successfully through the central `BUILD_ALL.ps1` pipeline
  (`-Mod SuiteHub -BuildOnly`) against the real game/Lunaris references; not copied to the live
  `plugins` folder during this integration pass (no install requested).
- **Not live-verified.** The game has not been launched with this build installed. The launcher's
  on-screen appearance, the drag/click interaction, the readiness gate's actual timing, the
  mutable-choice cycle control, and the Hub presence endpoint being consumed by any sibling mod
  have not been observed running.

**Explicitly deferred to Phase 3 (not built in this repo or `ErenshorSuiteHub` during this pass):**

- Every sibling mod's own `SuiteAuraProvider` adapter over its `ControlApi` — none exists yet, so
  every module page currently shows "installed; bridge unavailable" even after a correct Hub
  install.
- Dedicated-panel `openPanel` wiring on the mod side for Journal/Contracts/Guild Life/PvP/Crafting.
- Mod-side consumption of the Hub presence endpoint for canonical fallback-launcher suppression
  (`GameplayReady AND HubLive AND ThisModuleSuiteBridgeRegistered`) — the Hub now publishes the
  presence endpoint this requires, but no mod subscribes to it yet.
- Any config read/write bridge into another mod's settings beyond the advertised `setting.set`
  endpoint.
