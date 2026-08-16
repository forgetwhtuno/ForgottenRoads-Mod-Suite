# Erenshor Mod Suite
Central development/orchestration repo for forgetwhtuno's Erenshor Lunaris mod suite. This repo
does **not** contain mod source or history — each mod's own repo remains authoritative. This repo
exists to give one folder, one setup command, and one build/install command across all of them.

## Suite members

The current release-facing state is conservative: the supplied live log proves startup for all 12 suite modules, with additional partial evidence for several modules, while deterministic/build/hash gates still need to run on the actual Windows project.

| Mod | Repo | Current release-facing state |
|---|---|---|
| Deep Sims | [DeepSim-erenshor](https://github.com/forgetwhtuno/DeepSim-erenshor) | startup proven; live smoke remains |
| Party Tools | [Erenshor-PartyTools](https://github.com/forgetwhtuno/Erenshor-PartyTools) | startup proven; panel smoke remains |
| Contracts | [ErenshorContracts](https://github.com/forgetwhtuno/ErenshorContracts) | startup/character scope proven; board/persistence remain |
| Journal | [ErenshorJournal](https://github.com/forgetwhtuno/ErenshorJournal) | startup + partial zone lifecycle proven |
| Guild Life | [ErenshorGuildLife](https://github.com/forgetwhtuno/ErenshorGuildLife) | startup + partial zone lifecycle proven |
| Campmaster | [Erenshor-Campmaster](https://github.com/forgetwhtuno/Erenshor-Campmaster) | 0.4.1 startup/config proven; `/relax` smoke remains |
| Nemesis | [Erenshor-Nemesis](https://github.com/forgetwhtuno/Erenshor-Nemesis) | startup/character scope proven; lifecycle persistence remains |
| Crafting Expanded | [Erenshor-Crafting-Expanded](https://github.com/forgetwhtuno/Erenshor-Crafting-Expanded) | 0.2.1 startup/native probe proven; UI/gather/persistence remain |
| Practice Duel | [Erenshor-Duel](https://github.com/forgetwhtuno/Erenshor-Duel) | startup + active/timeout cleanup partial live proof |
| PvP | [Erenshor-PvP](https://github.com/forgetwhtuno/Erenshor-PvP) | startup/match diagnostics proven; retained UI/full combat/natural ambush remain |
| Follow | [ErenshorFollow](https://github.com/forgetwhtuno/ErenshorFollow) | 0.6.1 startup proven; current expedition crossing remains |
| Suite Hub | [ErenshorSuiteHub](https://github.com/forgetwhtuno/ErenshorSuiteHub) | startup + zone reuse + pointer ownership partial proof |

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
```

## Development workflow

```
central suite repo
    -> one build/install command
    -> live game testing
    -> record evidence in docs/CURRENT_WORK.md and docs/LIVE_TEST_MATRIX.md
    -> deep architectural review when needed
    -> small targeted local fixes
    -> draft PR updates in the individual mod repo
    -> live validation
    -> merge only after a real pass
```

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
