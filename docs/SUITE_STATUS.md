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
- `SETUP_WORKSPACE.ps1` — junction-based workspace linking, run and verified against all 11 mods.
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

Status: see the most recent entry below for exactly what exists, what it's verified to do
(build/compile only, vs. actually run and show the compact launcher live), and what's explicitly
deferred to Phase 2 (per-mod tabs, dedicated-panel integration, the shared UI containment
utility, and the Aura-vs-reflection-bridge decision for mod registration).
