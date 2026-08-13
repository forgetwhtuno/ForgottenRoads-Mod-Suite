# Suite Status

## Phase plan

**Phase 1** (this pass): central repo, manifest/setup/build/install, docs and the live-test
matrix, Suite Hub skeleton, an Overview page, installed-mod discovery, a working compact
launcher, and the duplicate-instance investigation.

**Phase 2** (not started): Deep Sims/PvP/Journal/Contracts/Guild Life Hub tabs, dedicated-panel
integration, PvP panel drag repair.

**Phase 3** (not started): Party Tools, Follow, Campmaster, Duel, Nemesis, Crafting tabs.

Each phase gets its own build/test/PR/live-test cycle before the next one starts. Nothing gets
merged automatically at a phase boundary.

## Phase 1 delivered this session

- `Erenshor-Mod-Suite` repo created under `forgetwhtuno`, public, no source/history duplicated
  from any mod repo.
- `suite.json` manifest listing all 11 mods, their local directories (including the two
  `-migration` exceptions), branches, DLL names, and honestly-labeled status.
- `SETUP_WORKSPACE.ps1` — originally junction-based workspace linking, run and verified against
  all 11 mods; since replaced by a single consolidated project root with every mod as a real
  worktree (`SETUP_WORKSPACE.ps1` now just verifies presence / clones what's missing directly into
  place). See `docs/ARCHITECTURE.md`.
- `BUILD_ALL.ps1` / `INSTALL_ALL.ps1` / `BUILD_AND_INSTALL_ALL.bat` — staging-then-atomic
  build/install pipeline, run end-to-end: all 11 mods built, every mod with a test suite passed,
  all 11 installed to the live plugins folder with reported SHA256 hashes.
- `docs/ARCHITECTURE.md`, `docs/CURRENT_WORK.md`, `docs/LIVE_TEST_MATRIX.md`,
  `docs/UI_DESIGN.md`, this file.
- Duplicate-Lunaris-plugin-instance investigation: strong circumstantial evidence gathered and
  documented (see `docs/CURRENT_WORK.md`); `ErenshorContracts` instrumented with instance-hash
  diagnostics; **still unresolved pending a fresh live run** — no defensive fix applied anywhere.
- Suite Hub skeleton, Overview page, compact launcher, installed-mod discovery: see the next
  section for exactly what was and wasn't delivered.

## Suite Hub — exact current scope

<!-- Fill in precisely once the Hub skeleton work lands. Do not let this section drift ahead of
     what's actually built and verified — if the Hub isn't built yet, say so plainly rather than
     describing the intended design as if it exists. -->

**Repo:** [ErenshorSuiteHub](https://github.com/forgetwhtuno/ErenshorSuiteHub), public, `main`
branch, GUID `forgetwhtuno.erenshor.suitehub`, version `0.1.0`.

**What exists (Phase 1 skeleton, built this session):**

- `src/HubLauncher.cs` — compact grip+button launcher (18px drag-only grip strip, non-overlapping
  `GUI.Button` action surface), dark-cyan palette matching Journal/Contracts/Guild Life/PvP. Only
  drawn once `IsLocalCharacterReady()` is true (same exact verified signal already used by those
  mods), recomputed every frame, never cached across scene loads.
- `src/HubWindow.cs` — one movable window, header-drag only, with exactly one working tab:
  Overview. Shows the Hub's own version and the detected-mod list. No other mod's tab exists yet.
- `src/ErenshorSuiteHubPlugin.cs` — plugin entry point. Toggle/close requests observed in `OnGUI`
  are only ever applied in `Update()` via `_pendingToggle`/`_pendingClose` (the same deferred-
  mutation pattern Contracts introduced this session), never mutated mid-`OnGUI`. Click-through
  guard via `[HarmonyPatch(typeof(PlayerControl), "LeftClick")]` and a `csMouseOrbit.LateUpdate`
  camera-look mute, matching the rest of the suite.
- `src/ModDiscovery.cs` — installed-mod discovery, deliberately simple: checks whether each of the
  other ten suite mods' known plugin DLL file names exist in the same `plugins` folder this Hub's
  own DLL loaded from (`AppContext.BaseDirectory` + `"plugins"`, following the same directory
  convention ErenshorContracts's `Awake()` already relies on). No reflection into those DLLs, no
  type loading, no calls into them, no Aura API usage, no code added to any of the other ten mod
  repos. Pure and Unity-free, so it is directly unit tested (see below).

**Verified vs. not verified:**

- Compile-verified: builds cleanly with `csc.exe` against the installed Lunaris/Assembly-CSharp/
  Unity assemblies (net48, C# 5-safe legacy-compiler style, zero BepInEx references).
- Deterministic-test-verified: `RUN_TESTS.ps1` runs `tests/ModDiscoveryTests.cs` against the real
  `ModDiscovery.Scan()` logic (missing directory, empty directory, mixed present/absent DLLs,
  null/empty path input) — 82 assertions, all passing.
- Installed: built and copied to `<Erenshor>\plugins\ErenshorSuiteHub.dll` via the mod's own
  `BUILD_AND_INSTALL.ps1`, confirmed as a genuinely new file (nothing previously existed at that
  path).
- **Not live-verified.** The game has not been launched with this DLL installed. The launcher's
  on-screen appearance, the drag/click interaction, the deferred-toggle fix, the click-through
  guard, and the Overview tab's actual detected-mod list have not been observed running. Status is
  correctly `NEEDS_LIVE_TEST` in `suite.json`, not a claim of working behavior.

**Explicitly deferred to Phase 2+ (not built in this repo):**

- Per-mod tabs beyond Overview.
- Dedicated-panel integration for any other mod (opening/embedding another mod's own window).
- Live mod registration or any other-mod interaction beyond the file-presence check above.
- Any Lunaris Aura investigation or usage — not evaluated, not touched.
- The shared UI containment utility (`SuiteUiInput.IsPointerCaptured`/`IsDragActive`) described in
  `docs/ARCHITECTURE.md` — the Hub still has its own independent click-through/camera-mute Harmony
  patches, not a shared one.
- Any config read/write bridge into another mod's settings.
