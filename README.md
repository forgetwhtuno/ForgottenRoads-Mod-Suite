# Erenshor Mod Suite

Central development/orchestration repo for forgetwhtuno's Erenshor Lunaris mod suite. This repo
does **not** contain mod source or history — each mod's own repo remains authoritative. This repo
exists to give one folder, one setup command, and one build/install command across all of them.

## Suite members

| Mod | Repo | Status |
|---|---|---|
| Deep Sims | [DeepSim-erenshor](https://github.com/forgetwhtuno/DeepSim-erenshor) | needs live test |
| Party Tools | [Erenshor-PartyTools](https://github.com/forgetwhtuno/Erenshor-PartyTools) | needs live test |
| Contracts | [ErenshorContracts](https://github.com/forgetwhtuno/ErenshorContracts) | needs live test |
| Journal | [ErenshorJournal](https://github.com/forgetwhtuno/ErenshorJournal) | needs live test (known-good launcher reference) |
| Guild Life | [ErenshorGuildLife](https://github.com/forgetwhtuno/ErenshorGuildLife) | needs live test |
| Campmaster | [Erenshor-Campmaster](https://github.com/forgetwhtuno/Erenshor-Campmaster) | needs live test |
| Nemesis | [Erenshor-Nemesis](https://github.com/forgetwhtuno/Erenshor-Nemesis) | needs live test |
| Crafting Expanded | [Erenshor-Crafting-Expanded](https://github.com/forgetwhtuno/Erenshor-Crafting-Expanded) | blocked (still WIP, missing standard repo docs) |
| Practice Duel | [Erenshor-Duel](https://github.com/forgetwhtuno/Erenshor-Duel) | needs live test |
| PvP | [Erenshor-PvP](https://github.com/forgetwhtuno/Erenshor-PvP) | needs live test (combat itself already had a good live result) |
| Follow | [ErenshorFollow](https://github.com/forgetwhtuno/ErenshorFollow) | needs live test |
| Suite Hub | [ErenshorSuiteHub](https://github.com/forgetwhtuno/ErenshorSuiteHub) | needs live test (Phase 1 skeleton: launcher + Overview tab + mod discovery only) |

Full detail: [docs/SUITE_STATUS.md](docs/SUITE_STATUS.md). Working notes: [docs/CURRENT_WORK.md](docs/CURRENT_WORK.md).

None of these mods' Lunaris-migration PRs are merged yet. This suite repo does not change that.

## One-time setup

Clone (or already have) every mod repo as a **sibling** of this checkout, i.e. `C:\Users\<you>\<RepoName>`
next to `C:\Users\<you>\Erenshor-Mod-Suite`. Then:

```powershell
powershell -ExecutionPolicy Bypass -File SETUP_WORKSPACE.ps1
```

This creates an NTFS junction under `mods\<id>` pointing at each sibling repo — a unified
workspace view with **zero file duplication**; editing through `mods\<id>` edits the real repo.
Pass `-Clone` to have it `gh repo clone` anything missing.

Two mods are intentionally excluded from this workspace: `Erenshor-Duel` and `ErenshorFollow`
(the plain-named checkouts) have older unreconciled local work on `main` and are not build
targets — see `suite.json`'s `excluded` list and `docs/CURRENT_WORK.md` for why. The clean,
buildable Lunaris checkouts live at `Erenshor-Duel-migration` and `ErenshorFollow-migration`.

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
needs to find them. A manifest (`suite.json`) plus junctions gets "one folder" with none of that
fragility. If that tradeoff ever stops being true, revisit.

## Repo layout

```
Erenshor-Mod-Suite/
    README.md, AGENTS.md, suite.json      -- this file, agent-facing rules, the mod manifest
    BUILD_AND_INSTALL_ALL.bat             -- one-click entry point
    BUILD_ALL.ps1 / INSTALL_ALL.ps1       -- the actual build/install logic
    SETUP_WORKSPACE.ps1                   -- one-time workspace linking
    docs/                                 -- architecture, status, live-test tracking
    shared/ErenshorSuite.UI/              -- shared UI contract for the Suite Hub (Phase 2+)
    mods/                                 -- junctions into sibling repos (created by setup, gitignored)
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
