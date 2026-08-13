# Architecture

Status labels used in this document: **VERIFIED SOURCE**, **VERIFIED OFFLINE**, **LIVE VERIFIED**,
**NEEDS LIVE TEST**, **BLOCKED**.

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

`Erenshor-Mod-Suite` owns orchestration/docs only. `ErenshorSuiteHub` owns the optional Hub UI.
Every gameplay mod remains an independent repository and authoritative for its own state, config,
actions, persistence, and dedicated UI. No Hub feature may make a sibling mod require the Hub to
start or function.

## Why not junctions or git submodules

This workspace previously used NTFS junctions from `mods/<id>` to repos scattered individually
across the filesystem, back when those repos had grown up independently before this suite repo
existed. Once every repo was consolidated into one physical project root, the junctions became
pure overhead with no benefit — real directories are simpler, and the tooling doesn't need to
create or maintain any link. `SETUP_WORKSPACE.ps1` remains useful for a fresh machine (verifying
what's present, cloning what's missing directly into place; it also now surfaces a branch
mismatch or dirty worktree per mod so `BUILD_ALL.ps1 -AllowDirty` is a deliberate choice, not a
silent default), it just doesn't link anymore.

Submodules were considered and rejected for the same underlying reason: git submodules pin an
exact sibling commit and require an extra commit-and-push step in this repo every time a sibling
repo moves forward, plus the usual detached-HEAD/`.gitmodules` friction on Windows. This suite
doesn't need to pin versions — it just needs to find the sibling repos on disk and know their
target branch/DLL name, which `suite.json` already records.

## Build/install pipeline

Each mod repo owns its own `BUILD_AND_INSTALL.ps1` — the authoritative build logic for that mod,
including its own reference list and any bespoke build-time behavior (embedded build SHAs,
conditional compilation, etc.). `BUILD_ALL.ps1` in this repo does **not** reimplement any of that.
The central pipeline follows:

```text
validate game + reference hashes
validate exact manifest branch and clean worktree (unless -AllowDirty)
recreate private staging scaffold (Erenshor_Data junctioned, tiny Erenshor.exe stub, no framework DLL duplication)
build every selected module into staging via that module's own BUILD_AND_INSTALL.ps1
run every declared standalone test script (suite.json's per-mod testScripts)
if ANY selected build/test fails -> install nothing, write no reusable stage manifest
if all pass -> write fingerprinted suite-build.json (suite.json/Assembly-CSharp/Lunaris/Harmony hashes + per-mod source SHA/dirty flag/DLL hash)
if install requested -> refuse while Erenshor runs unless -AllowGameRunning is explicit
verify staged hashes -> snapshot all live destinations -> atomic same-directory replacement (temp-file + File.Replace, never a *.dll-suffixed partial write) -> roll back the whole selected DLL set if any replacement/hash check fails
```

`INSTALL_ALL.ps1` reuses the same fingerprinted staging manifest without rebuilding, and refuses to
install if `suite.json` or `Assembly-CSharp.dll` changed since the staging set was produced, or if
any staged DLL's hash no longer matches what was recorded. `SuiteBuild.Common.ps1` holds the shared
pure/safety helpers (`Install-SuiteSetTransactional`, `Get-SuiteRepoState`, `Get-Sha256`,
`Read-SuiteStageManifest`, `Assert-SafeRelativePath`) used by both scripts and covered directly by
`tests/RUN_TESTS.ps1`'s deterministic manifest/build-policy assertions — no live game or staging
directory is touched by that test.

A failed build or failed declared test for any *selected* module means nothing in that run is
installed — this is a whole-selected-set gate, not a per-mod best-effort copy. This is a real
change worth calling out: the previous pipeline would still copy a mod's DLL into the live plugins
folder even if that mod's own declared test suite failed, as long as the build itself succeeded.

## Suite Hub

The Hub (`ErenshorSuiteHub`, sibling of this repo, not under `mods/`) is the one permanent
player-facing launcher for the suite: a compact grip+button launcher (Journal's proven interaction
model) that opens one movable window with per-installed-mod navigation. See
`docs/HUB_INTEGRATION_CONTRACT.md` for the wire contract and `docs/UI_RUNTIME_CONTRACT.md` for the
shared geometry/pointer-capture/persistence rules the Hub already implements and that sibling mods
should converge on.

Hard constraint: **no suite mod may require the Hub to function.** Every mod keeps its own
commands and, where it has one, its own dedicated panel, working exactly as before. The Hub only
adds optional presentation on top. Registration between a mod and the Hub is absent-safe in both
directions via Lunaris Aura polling (see below) — a mod loaded without the Hub works fine; the Hub
loaded without a given mod just shows that mod's page as "installed; bridge unavailable"; either
one can load/unload/reload independently without the other needing to know the order.

## Gameplay-ready lifecycle gate

### Why the old gate is rejected

**LIVE VERIFIED:** launchers using only:

```text
!GameData.InCharSelect
PlayerControl != null
PlayerControl.Myself != null
MyStats != null
player GameObject active
```

can appear after Enter World while the character is still visibly loading. Those facts prove that
a player runtime object exists; they do **not** prove that gameplay is usable.

### Native evidence, verified against the real installed Assembly-CSharp.dll

Every member below was confirmed present via reflection against the actual installed
`Erenshor_Data\Managed\Assembly-CSharp.dll` (SHA256 recorded in the integration session notes),
not merely inferred from sibling source:

- `GameData.InCharSelect` (bool, static)
- `GameData.Zoning` (bool, static)
- `GameData.PlayerControl` (PlayerControl, static)
- `PlayerControl.Myself` (Character, instance)
- `PlayerControl.CanMove` (bool, instance)
- `Character.MyStats` (Stats, instance)
- `GameData.SimMngr` (SimPlayerMngr, static)
- `GameData.SimPlayerGrouping` (SimPlayerGrouping, static)
- `GameData.GroupMembers` (SimPlayerTracking[], static) — present and available as additional
  post-load evidence if a future readiness revision needs it; not currently required by the
  canonical policy below.

### Hub candidate state machine

Implemented in `ErenshorSuiteHub/src/GameplayReadinessPolicy.cs`:

```text
CharacterSelect
  -> PlayerObjectCreating
  -> ZoneTransition              when GameData.Zoning
  -> WorldInitializing           managers/grouping/input not ready
  -> Stabilizing                 positive candidate held continuously
  -> Ready
```

Candidate inputs:

- `GameData.InCharSelect == false`
- `GameData.PlayerControl != null`
- `GameData.PlayerControl.Myself != null`
- `Myself.MyStats != null`
- player GameObject active in hierarchy
- `GameData.Zoning == false`
- `GameData.SimMngr != null`
- `GameData.SimPlayerGrouping != null`
- `GameData.PlayerControl.CanMove == true` observed during acquisition

`CanMove` is intentionally an **acquisition signal**. Once the same settled world has reached
Ready, a normal native window temporarily making `CanMove=false` does not hide the Hub. Character
select, zoning, or losing the required world graph revokes the latch and requires a fresh
acquisition.

The one-second unscaled stability window is defensive debounce only; it is not a substitute for
state detection. **NEEDS LIVE TEST:** trace each state from character select -> Enter World ->
first usable movement, and on zoning/disconnect/reconnect. Adjust the debounce only from observed
lifecycle evidence.

This is the one canonical readiness policy for the suite (see `docs/CURRENT_WORK.md` for the
per-mod fallback-UI status); sibling mods converging on the same semantics (rather than an
independently-tuned interval) is part of the integration contract.

## Suite Hub authority boundary

The Hub may:

- discover installed suite DLLs;
- display mod-owned status/config descriptors;
- invoke actions explicitly advertised by that mod, with an optional argument (e.g. `roll`/`100`,
  `challenge`/`"Dancer"`) — see `docs/HUB_INTEGRATION_CONTRACT.md`;
- edit a mutable `bool` or `choice` setting through the mod's own `setting.set` endpoint;
- open/close a dedicated panel through the mod-owned endpoint;
- persist only Hub-owned UI/config state.

The Hub must not independently attack, heal, move Sims, loot, equip, choose targets, change
faction, mutate native saves, or make gameplay decisions. It also never edits another mod's
`.lpcfg`.

## Optional module registration contract

**VERIFIED SOURCE:** Lunaris exposes typed Aura providers/subscribers through
`LunarisPlugin.IPCAuraProvider<...>` / `IPCAuraSubscriber<...>`. Subscribers expose
`HasFunction`; invoking a missing function returns default. Current Lunaris does not
support load ordering.

The Hub therefore creates subscriber objects for all known module IDs and polls them. This is
load-order independent:

```text
Hub first -> endpoint absent -> installed/standalone page
mod registers later -> next poll validates descriptor -> Connected
mod unregisters on unload -> next poll removes module runtime registration
mod reloads -> descriptor appears exactly once again
Hub unloads -> subscriber objects disappear; mods keep working
```

The pure `SuiteModuleRegistry` rejects two different owners for the same module ID and lets the
same owner refresh its descriptor in place.

The Hub also publishes its own tiny live-presence endpoint,
`forgetwhtuno.erenshor.suitehub.v1.describe` (deliberately outside the per-module
`forgetwhtuno.erenshor.suite.<id>.v1.*` namespace, since it describes the Hub itself, not a
module), so that a sibling mod's own launcher-suppression logic can ask "is Hub actually alive" via
Aura instead of scanning the scene for Hub components. This is intentionally minimal —
protocol/module/display/version/status only, no actions or settings.

### Important Aura unload requirement

**VERIFIED SOURCE:** Lunaris's plugin unload path does not itself remove Aura handlers. Aura's
registry removes a handler only when the owning provider calls `UnregisterFunc` / `UnregisterAction`.

Therefore every sibling implementation of the Suite provider contract must retain its provider
objects and explicitly unregister them in `OnDestroy`. Otherwise a stale delegate can survive
unload and can also prevent a new plugin instance from taking ownership of the label. The Hub's own
`AuraModuleBridge`/presence provider follow this rule; see `HUB_INTEGRATION_CONTRACT.md`.

## Known unresolved architectural question: duplicate Lunaris plugin instances

See `docs/CURRENT_WORK.md` for the full live evidence (a real session log showed every native
`[LunarisPlugin]` mod's `Awake()` firing twice in one process bootstrap, in two passes with a
*different* plugin order, with no `OnDestroy` between them). Current Lunaris source establishes
that a normal full load creates exactly one GameObject/component and that hot reload always
destroys the old instance before the replacement is loaded — so two simultaneously-live native
instances are **not an intended normal lifecycle in current source**, but that does not prove what
happened in the historical session. Do not add a per-mod singleton workaround.

Required live classification on the next fresh run (`ErenshorContracts`'s
`[ContractsInstanceDiag] Awake/Update/OnDestroy` instance-hash logging exists for exactly this):

1. Capture process start marker/time and the installed Lunaris version/hash.
2. Group every `[ContractsInstanceDiag] Awake/Update/OnDestroy` line by instance hash.
3. If two hashes both emit overlapping periodic Update ticks before either OnDestroy -> two live
   objects, escalate as a loader/runtime defect; do not add a mod-local singleton hack.
4. If the old hash's OnDestroy precedes the new hash's Awake -> normal hot reload/file-watcher
   lifecycle.
5. If only one hash ever emits Update despite two Awake-time log blocks -> discovery/log/session
   artifact, not two live runtime objects.
6. Check for log append/process-boundary markers before treating repeated startup blocks as one
   bootstrap.

Do not build the shared UI containment layer below, or any defensive duplicate-instance guard,
until this is resolved — a second live coexisting instance would need a different, more
fundamental fix.

## Shared UI interaction design

The Hub implements the target semantics locally (see `docs/UI_RUNTIME_CONTRACT.md` for the full
spec):

- dedicated launcher grip;
- dedicated main-window header drag;
- pointer capture begins on mouse-down over Hub UI;
- capture remains owned through physical mouse-up even if the pointer leaves the rect;
- world click and camera-look guards consult ownership, not only hover;
- runtime rect remains authoritative while dragging;
- position is persisted after debounce/close/unload;
- invalid/off-screen rects recover and Reset Position is reachable.

Multiple mods have independently hit and fixed the same two classes of IMGUI bug this session:

1. `GUI.DragWindow`'s rect overlapping a launcher's clickable button (Journal never had this;
   Contracts, Guild Life, and PvP all did, all fixed to match Journal's grip+button model).
2. Mutating open/closed panel state directly inside `OnGUI` instead of deferring to `Update()`
   (desyncs Unity's Layout/Repaint passes; Contracts found this first, then PvP and Guild Life).

### Staged migration for sibling mods

Do **not** make the optional Hub a dependency merely to share Harmony patches.

1. **Now:** each standalone mod keeps its own fallback guards; sibling mods should port the same
   pointer-capture/header/grip semantics into their own owned code (blocked on the duplicate-
   instance question above before any *shared* utility is extracted).
2. **After live stability:** extract only pure geometry/input-state policy where code reuse is
   useful. Avoid passing Unity UI objects across assemblies.
3. **Only if justified later:** consider a tiny independent optional UI-capture runtime that owns
   the shared native Harmony guards. A mod must detect that capability and retain a standalone
   fallback when it is absent. The Hub itself should not become that mandatory runtime.
