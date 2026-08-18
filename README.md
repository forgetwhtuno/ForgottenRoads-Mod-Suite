# Forgotten Roads for Erenshor
Release coordination for the Forgotten Roads for Erenshor Lunaris mod collection. This repo
does **not** contain mod source or history — each mod's own repo remains authoritative. This repo
exists to give one folder, one setup command, and one build/install command across all of them.

## Collection members

Current release status is conservative: deterministic/build evidence is recorded separately from live certification. The live matrix remains authoritative for promotion beyond a candidate state.

| Mod | Canonical repository | Current source version | Current status |
|---|---|---|---|
| Deep Sims | [DeepSim-ForgottenRoads](https://github.com/forgetwhtuno/DeepSim-ForgottenRoads) | 0.7.6 | Standalone-runtime + single-model candidate; needs current live conversation/reload proof |
| Party Tools | [ForgottenRoads-PartyTools](https://github.com/forgetwhtuno/ForgottenRoads-PartyTools) | 0.1.6 | Needs integrated live UI validation |
| Contracts | [ForgottenRoadsContracts](https://github.com/forgetwhtuno/ForgottenRoadsContracts) | 0.4.4 | Needs locality, target, and claim live loop |
| Journal | [ForgottenRoadsJournal](https://github.com/forgetwhtuno/ForgottenRoadsJournal) | 0.1.8 | Needs integrated live UI and persistence validation |
| Guild Life | [ForgottenRoadsGuildLife](https://github.com/forgetwhtuno/ForgottenRoadsGuildLife) | 0.1.3 | Needs live retest |
| Campmaster | [ForgottenRoads-Campmaster](https://github.com/forgetwhtuno/ForgottenRoads-Campmaster) | 0.4.0 | Needs focused live workflow validation |
| Nemesis | [ForgottenRoads-Nemesis](https://github.com/forgetwhtuno/ForgottenRoads-Nemesis) | 0.3.0 | Automatic rival/two-way chat candidate; needs current live assignment/chat/persistence proof |
| Crafting Expanded | [ForgottenRoads-Crafting-Expanded](https://github.com/forgetwhtuno/ForgottenRoads-Crafting-Expanded) | 0.2.4 | Preview; live production-recipe evidence remains required |
| Practice Duel | [ForgottenRoads-Duel](https://github.com/forgetwhtuno/ForgottenRoads-Duel) | 0.4.3 | Combat-semantics candidate; needs current melee/self-heal/AoE/cleanup live proof |
| PvP | [ForgottenRoads-PvP](https://github.com/forgetwhtuno/ForgottenRoads-PvP) | 0.5.7 | Native-AI match-start candidate; needs two complete 5v5 plus restart proof |
| Follow | [ForgottenRoadsFollow](https://github.com/forgetwhtuno/ForgottenRoadsFollow) | 0.6.4 | Needs continuous multi-hop expedition proof |
| Suite Hub | [ForgottenRoadsSuiteHub](https://github.com/forgetwhtuno/ForgottenRoadsSuiteHub) | 0.5.3 | Needs integrated live Hub/UI validation |

Current release truth: [docs/SUITE_STATUS.md](docs/SUITE_STATUS.md), [docs/LIVE_TEST_MATRIX.md](docs/LIVE_TEST_MATRIX.md), [BUILD_REPORT.md](BUILD_REPORT.md), and `release-manifest.json`. `docs/CURRENT_WORK.md` is historical development context and may contain superseded status language.

## One-time setup

This repo expects to live inside one project root alongside its sibling repos, like:

```
<ProjectRoot>/
    Erenshor-Mod-Suite/     <- this repo
    ErenshorSuiteHub/
    mods/
        DeepSim-erenshor/
        Erenshor-PvP/
        ... (one real git worktree per mod, see suite.json)
```

Every entry under `mods/` (and `ErenshorSuiteHub/`, next to this repo) is a genuine git
worktree — clone it there directly, or move an existing checkout there. This repo does not use
junctions or any other indirection; `suite.json`'s `workspaceRoot`/`modsSubdir` fields just tell
the tooling where to look.

```powershell
powershell -ExecutionPolicy Bypass -File SETUP_WORKSPACE.ps1
```

checks that every repo listed in `suite.json` is physically present where expected, and (with
`-Clone`) `gh repo clone`s anything missing directly into place. It does not create any links.

The active workspace intentionally contains only authoritative build-target repositories. Historical
patch bundles, scratch checkouts, and local backups belong outside the workspace and are never build inputs.

## Build + install

```
BUILD_AND_INSTALL_ALL.bat
```

Default behavior: build every enabled mod, run each mod's own deterministic test suite where one
exists, and install only mods that both built and tested clean into the single canonical
`<Erenshor>\plugins\` folder. Nothing failed is ever installed; nothing partially-built ever
touches the live folder (each mod builds into a disposable staging copy of the game folder first,
then only a fully successful DLL is copied to the real plugins folder).

Useful switches (pass straight through the `.bat`, or call `BUILD_ALL.ps1` directly):

```powershell
BUILD_AND_INSTALL_ALL.bat -BuildOnly              # compile + test, never touch the live install
BUILD_AND_INSTALL_ALL.bat -Mod PvP -Mod DeepSims  # only these mods
BUILD_AND_INSTALL_ALL.bat -Skip CraftingExpanded  # everything except these
BUILD_AND_INSTALL_ALL.bat -RunTests:$false        # skip each mod's own test suite
BUILD_AND_INSTALL_ALL.bat -Clean                  # wipe the staging dir first
```

`INSTALL_ALL.ps1` re-installs whatever's already staged from the last `BUILD_ALL.ps1` run without
rebuilding — handy after a `-BuildOnly` pass once you're ready to test live.

## Why not git submodules

Submodules work, but on Windows with actively-edited sibling repos they add friction (detached
HEAD surprises, `.gitmodules` drift, an extra commit step just to point at a newer sibling
commit) for no benefit here — the suite repo doesn't need to pin exact sibling versions, it just
needs to find them. A manifest (`suite.json`) that simply records where each repo lives inside one
project root gets "one folder" with none of that fragility. If that tradeoff ever stops being
true, revisit.

## Repo layout

```
Erenshor-Mod-Suite/
    README.md, AGENTS.md, suite.json      -- this file, agent-facing rules, the mod manifest
    BUILD_AND_INSTALL_ALL.bat             -- one-click entry point
    BUILD_ALL.ps1 / INSTALL_ALL.ps1       -- the actual build/install logic
    SETUP_WORKSPACE.ps1                   -- one-time workspace verification/cloning
    docs/                                 -- architecture, status, live-test tracking
    shared/ErenshorSuite.UI/              -- retained-uGUI visual/runtime contract (no shared runtime DLL)
```

`mods/` and `ErenshorSuiteHub/` are siblings of this repo (see "One-time setup" above), not
inside it — this repo has no `mods/` directory of its own.

## Development workflow

```
feature branch in the individual mod repo
    -> source review + deterministic tests
    -> PR
    -> merge reviewed candidate source to canonical main
    -> build/install the exact canonical main set (BUILD_AND_INSTALL_ALL.bat)
    -> run the ordered live matrix in docs/LIVE_TEST_MATRIX.md
    -> record evidence, then release only after live certification
```

### Merged to main is not release certified

These are two separate gates, and the tooling enforces the second one, not the first:

- **Merge gate.** Reviewed candidate source may be merged to canonical `main` on source review and
  deterministic tests alone. Merging makes `main` the authoritative candidate; it claims nothing
  about live behavior.
- **Release gate.** `RELEASE_GATE.ps1` performs *no* Git writes and does not care whether anything
  was merged. It re-checks collection consistency, audits active plugin identities, rebuilds every
  module clean, re-runs each deterministic suite, and then packages against
  `release-whitelist.json`. `PACKAGE_RELEASE.ps1` refuses a FINAL package for any module that still
  has declared live blockers.

So a merge never certifies a release. After merging, the exact `main` candidate must be rebuilt and
installed, and the ordered live matrix run against *that* build — historical live results from an
earlier DLL do not carry forward.

`-AllowReleaseCandidateWithLiveBlockers` exists for interim testing only. It sets `packageMode` to
`RELEASE_CANDIDATE` and names the artifact `<module>-<version>-RC.zip`, and the gate prints that
artifacts are release candidates because live blockers were explicitly allowed. It is not a final
release certification and does not clear any live blocker.

Do not overstate testing. A build/test-verified fix is not the same as a live-verified fix — see
`docs/LIVE_TEST_MATRIX.md` for what has actually been confirmed in the running game versus what's
only been proven at compile/deterministic-test time.

## Shared UI standard

Production Suite UI uses retained Unity uGUI and the existing EventSystem/GraphicRaycaster path. The
visual family is based on Follow's existing SIM ACTIONS menu: dark translucent panels, thin cyan
framing, compact square controls, and restrained accent/secondary text. New production UI does not
use OnGUI, native `DragUI`, or `GameData.EditUIMode`.

The Hub separates structural refresh from dynamic values so selection/status/toggle polling does not
rebuild unrelated UI. Compact initial sizing treats configured dimensions as a maximum envelope and
lets nav/large pages scroll.

The optional quick-close contract (`ui.state` + `closePanel`) is documented but native Escape
consumption remains capability-gated. Until an exact current Assembly-CSharp Escape/menu boundary is
locally verified and bound, Hub presence reports `quickClose=0` and sibling mods retain standalone
Escape behavior.

## Local author build vs release gate

For everyday local work, use the project-root `BUILD_TEST_INSTALL_CURRENT_LOCAL_SUITE.bat`. It is
deliberately labeled **LOCAL DIRTY SOURCE BUILD**, accepts the current dirty worktrees without a
Git mutation, stages builds away from live plugins, backs up each successfully gated destination,
and installs successful selected mods independently with SHA-256 verification.

For release work, use `RELEASE_GATE.ps1`. The release path remains strict: clean manifest-listed
worktrees, suite + module deterministic tests, current installed game/Lunaris references, duplicate
DLL audit, and explicit whitelist packaging. Final packages are refused while declared live blockers
remain; `-AllowReleaseCandidateWithLiveBlockers` produces clearly labeled RC packages for live test.

Release tooling and policies:

- `INSTALL.md`
- `RELEASE_CHECKLIST.md`
- `BUILD_REPORT.md`
- `POST_BUILD_SMOKE.md`
- `release-whitelist.json`
- `release-manifest.json`
- `AUDIT_ACTIVE_PLUGINS.ps1`
- `PACKAGE_RELEASE.ps1`


## Lunaris plugin identity preflight

Release/install correctness is based on one discoverable Lunaris plugin identity across the recursive `<Erenshor>\plugins` scan tree, not one filename in one folder. See [docs/LUNARIS_PLUGIN_IDENTITY_AUDIT.md](docs/LUNARIS_PLUGIN_IDENTITY_AUDIT.md). `AUDIT_ACTIVE_PLUGINS.ps1` is evidence-only unless the narrow `-QuarantineConfirmedBackups` switch is explicitly requested.
