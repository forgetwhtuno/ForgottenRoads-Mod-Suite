# Architecture

## Repo relationship

```
<ProjectRoot>/                          -- one physical folder holding the whole workspace
    Erenshor-Mod-Suite/                 -- this repo: orchestration only (manifest, build/install, docs)
        suite.json                      -- authoritative list of mods, their local dirs, branches
    ErenshorSuiteHub/                   -- the Hub plugin's own repo, sibling of this one
    mods/
        <localDir>/                     -- one real git worktree per mod, per suite.json
```

No mod source or git history lives in this repo. Every entry under `mods/` (and
`ErenshorSuiteHub/`) is a genuine, independent git worktree with its own `.git`, remotes, and
history — editing there edits and commits to that mod's real repo directly. `suite.json`'s
`workspaceRoot`/`modsSubdir`/`underMods` fields are just how the tooling locates each one; they
are not an indirection layer.

## Why not junctions or git submodules

This workspace previously used NTFS junctions from `mods/<id>` to repos scattered individually
across the filesystem, back when those repos had grown up independently before this suite repo
existed. Once every repo was consolidated into one physical project root, the junctions became
pure overhead with no benefit — real directories are simpler, and the tooling doesn't need to
create or maintain any link. `SETUP_WORKSPACE.ps1` remains useful for a fresh machine (verifying
what's present, cloning what's missing directly into place), it just doesn't link anymore.

Submodules were considered and rejected for the same underlying reason: git submodules pin an
exact sibling commit and require an extra commit-and-push step in this repo every time a sibling
repo moves forward, plus the usual detached-HEAD/`.gitmodules` friction on Windows. This suite
doesn't need to pin versions — it just needs to find the sibling repos on disk and know their
target branch/DLL name, which `suite.json` already records.

## Build/install pipeline

Each mod repo owns its own `BUILD_AND_INSTALL.ps1` — the authoritative build logic for that mod,
including its own reference list and any bespoke build-time behavior (embedded build SHAs,
conditional compilation, etc.). `BUILD_ALL.ps1` in this repo does **not** reimplement any of that.
Instead it:

1. Locates the real Erenshor install and validates `Assembly-CSharp.dll`, `Lunaris.dll`,
   `0Harmony.dll` are present.
2. Builds a disposable **staging** folder (`%TEMP%\ErenshorSuiteBuildStaging`) that looks like a
   game folder to each mod's own build script: `Erenshor_Data` is an NTFS junction to the real
   one (zero framework-DLL duplication), plus a tiny copied `Erenshor.exe` stub so each script's
   own "is this really the game folder" check passes.
3. Runs every enabled mod's own `BUILD_AND_INSTALL.ps1` pointed at that staging folder, so each
   mod's DLL is written to a private `staging\plugins\<name>.dll` first.
4. Runs that mod's own `RUN_TESTS.ps1` if one exists.
5. Only if both steps succeeded, copies the staged DLL to the **real** `<Erenshor>\plugins\`.

A failed build or failed test suite for one mod never touches the live install for that mod, and
never blocks other mods in the same run — the final table reports every mod's outcome.

## Suite Hub (planned, Phase 2+)

A new, separate repo (`ErenshorSuiteHub`, not yet created as of Phase 1 unless noted otherwise in
`docs/CURRENT_WORK.md`) is the one permanent player-facing launcher for the suite: a compact
grip+button launcher (Journal's proven interaction model) that opens one movable window with a tab
per installed mod. It is linked into this workspace the same way every other mod is.

Hard constraint: **no suite mod may require the Hub to function.** Every mod keeps its own
commands and, where it has one, its own dedicated panel, working exactly as before. The Hub only
adds optional presentation on top. Registration between a mod and the Hub must be absent-safe in
both directions — a mod loaded without the Hub works fine; the Hub loaded without a given mod
just doesn't show that mod's tab; either one can load/unload/reload independently without the
other needing to know the order.

See `docs/UI_DESIGN.md` for the compact-launcher and window layout spec, and `AGENTS.md` for the
Aura-API caution.

## Shared UI containment (planned, Phase 2+)

Multiple mods have independently hit and fixed the same two classes of IMGUI bug this session:

1. `GUI.DragWindow`'s rect overlapping a launcher's clickable button (Journal never had this;
   Contracts, Guild Life, and PvP all did, all fixed to match Journal's grip+button model).
2. Mutating open/closed panel state directly inside `OnGUI` instead of deferring to `Update()`
   (desyncs Unity's Layout/Repaint passes; Contracts found this first, then PvP and Guild Life).

The plan is to extract the proven geometry/containment pattern into a small shared utility
(`SuiteUiInput.IsPointerCaptured` / `IsDragActive` or similar) that every mod's world-click and
camera-look Harmony guards can consult — but only once it's clear this can be done without forcing
a hard Suite Hub dependency on every mod for basic click protection, and without stacking multiple
Harmony patches on the same native method from different mods when one shared patch would do. Not
yet implemented; tracked as Phase 2+ work in `docs/CURRENT_WORK.md`.

## Known unresolved architectural question: duplicate Lunaris plugin instances

See `docs/CURRENT_WORK.md` for the full evidence. Short version: a real live log showed every
native `[LunarisPlugin]` mod's `Awake()` (and every other Awake-time log line) firing twice in one
process bootstrap, in two passes with a *different* plugin order, with no `OnDestroy` between
them — while two non-`[LunarisPlugin]` mods present in the same log never showed this. This looks
like Lunaris-host behavior, not any individual mod's bug, and is a plausible root cause for the
"click does nothing" launcher symptoms fixed elsewhere in this pass. `ErenshorContracts` now logs
an instance hash on `Awake`/periodic `Update`/`OnDestroy` to get a definitive answer on the next
live run. Do not build the shared UI containment layer (previous section) or any defensive
duplicate-instance guard until this is resolved — a second live coexisting instance would need a
different, more fundamental fix.
