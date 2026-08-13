# Agent instructions — Erenshor Mod Suite

This repo orchestrates, it does not own. Read this before touching anything here.

## Hard rules

- **Never duplicate mod source into this repo.** Each mod repo (see `suite.json`) is
  authoritative for its own code and git history. Change mod behavior in the mod's own real
  worktree under `mods/<localDir>` (or `ErenshorSuiteHub/` for the Hub) and commit there.
- **Never merge a mod's Lunaris-migration PR from here or anywhere else** unless the user
  explicitly asks for that specific merge in that specific conversation. All suite mods are
  currently on draft, unmerged `agent/lunaris-native[-deepsims]` branches.
- **Some mods have an older, unreconciled checkout kept outside this workspace's build path**
  (e.g. under a `legacy-worktrees/` folder) because it has uncommitted local work not yet ported
  to the current migration branch. These are never build targets. See `suite.json`'s `excluded`
  list and `docs/CURRENT_WORK.md` for exactly which mods and why.
- **Before any GitHub write** (push, PR update, new repo, etc.), verify identity:
  ```
  gh auth status
  gh api user
  ```
  Must show `forgetwhtuno` as the active account. Do not change global git identity. Local repo
  identity for commits: `forgetwhtuno <314876526+forgetwhtuno@users.noreply.github.com>`.
- **No private paths, personal email, legal name, tokens, or secrets** in anything committed here
  — docs, code comments, commit messages, everything. This repo is public.
- **Do not overstate testing.** A build succeeding or a deterministic test suite passing is not
  the same as a live-game pass. Use the exact status vocabulary in `docs/CURRENT_WORK.md` and
  `docs/LIVE_TEST_MATRIX.md` (`NEEDS_LIVE_TEST`, `BLOCKED`, etc.) rather than declaring something
  fixed/working from static evidence alone.

## Before building large shared infrastructure

The apparent Lunaris duplicate-plugin-instance behavior (every native `[LunarisPlugin]` mod's
`Awake()` firing twice per bootstrap with no `OnDestroy` between passes, seen in a real live log)
is **not yet resolved**. `ErenshorContracts` has temporary instance-identity diagnostics
(`[ContractsInstanceDiag]`) waiting on the next live run. See `docs/CURRENT_WORK.md` for the full
evidence and reasoning. Do not add a permanent singleton-guard "fix" for this anywhere until it's
confirmed via a fresh live log — and if it turns out two real instances do coexist, treat that as
higher priority than any further IMGUI/UI work, since it can invalidate UI test results suite-wide.

## Build system

`BUILD_ALL.ps1` calls each mod's own `BUILD_AND_INSTALL.ps1` (its own authoritative reference
list and build quirks) rather than reimplementing per-mod compilation here — don't "fix" that by
inlining `csc` calls into this repo; if a mod's build script needs a change, change it in that
mod's repo. The staging-then-atomic-copy behavior is achieved by pointing each mod's script at a
disposable staging copy of the game folder (an NTFS junction to the real `Erenshor_Data`, so no
framework DLL is ever duplicated — this is the only junction usage left anywhere in this repo, and
it's build-time scaffolding, not a workspace-layout mechanism), not by changing what the mod
scripts do.

## Suite Hub (Phase 2+)

`shared/ErenshorSuite.UI/` holds the shared UI contract every dedicated mod page implements. The
actual `ErenshorSuiteHub` plugin lives in its own repo (see `docs/ARCHITECTURE.md`), linked here
the same way as every other mod. The Hub must never become a hard runtime dependency — every mod
must keep working standalone if the Hub is absent or not yet loaded. No invented Lunaris Aura
APIs — if Aura isn't verified suitable for mod registration, use a narrow, documented,
absent-safe reflection/interface bridge instead.
