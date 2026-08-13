# Current Work — Erenshor Mod Suite

Status vocabulary used throughout this doc and `LIVE_TEST_MATRIX.md`:

- **DONE** — live-verified, not just build/test-verified.
- **IN PROGRESS** — actively being worked on this session.
- **BLOCKED** — cannot proceed until something else resolves (named explicitly).
- **NEEDS LIVE TEST** — build/deterministic-test verified only; not yet confirmed in the running game.
- **NEEDS DEEP AUDIT** — works as far as tested, but the design/approach itself needs a harder look.

Nothing in this suite has a merged PR. All work below is on draft, unmerged branches.

---

## Duplicate Lunaris plugin instance — NOT REPRODUCED IN FRESH RUN / NOT CURRENT UI CAUSE (2026-08-13, post-integration live run)

A fresh `lunaris.log` taken after the 2026-08-13 integration pass shows exactly one instance for
both diagnosed plugins, start to finish:

- Contracts: `Awake instance=-1725027768`, every Update diagnostic line carries
  `instance=-1725027768`, `Shutdown: OnDestroy instance=-1725027768` — one id throughout.
- Deep Sims: `Awake serial=1 unityId=-458`, heartbeats `serial=1 unityId=-458 instanceMatches=True`,
  `OnDestroy serial=1 unityId=-458 instanceMatches=True`.

The double-`Awake` pattern recorded below is therefore **not reproduced** in the current build and
is **not** the cause of the live Suite Hub click/drag failure investigated next in this doc. Do not
re-open this investigation without new contradicting evidence. Contracts' per-tick
`[ContractsInstanceDiag] Update tick` diagnostic has served its purpose and is being
throttled/removed as noise; the `Awake`/`OnDestroy` instance lines are being kept since they're
cheap and still useful signal if this ever resurfaces.

### Historical investigation (superseded by the fresh single-instance run above)

A real Lunaris session log (`lunaris.log`) showed **every** native `[LunarisPlugin]` mod in this
suite — all 11 — running its full `Awake()` (the "loaded" message and every other Awake-time
side-effect log line) **twice** in one process bootstrap. Each pass was preceded by its own
`Plugin found: '<Name>'` debug line from the Lunaris host itself. The two passes discovered
plugins in a *different order*, ruling out a simple duplicated log line. Zero `OnDestroy` lines
appeared anywhere between the two passes. Two other mods present in the same log
(Adventure Guide, Auto Sort — not `[LunarisPlugin]`-attributed, evidently loaded via a different
path) showed **no** such duplication and never appeared under any `Plugin found:` line at all.

This points at Lunaris's own plugin discovery/load pipeline invoking every native-attributed
plugin's Awake twice, not a bug in any individual mod's code — and is a plausible root cause for
the "launcher click does nothing" symptoms independently diagnosed and fixed in Contracts/Guild
Life/PvP this session, since two live `GUI.Window` calls sharing one integer WindowId every frame
is undefined Unity IMGUI behavior.

**Status**: `ErenshorContracts` now logs `[ContractsInstanceDiag] Awake instance=<hash>`,
`OnDestroy instance=<hash>`, and a throttled (~5s) `[ContractsInstanceDiag] Update tick
instance=<hash>` for exactly this reason — the next live run will show definitively whether a
second instance is truly alive and ticking (two distinct hashes both appearing in the periodic
Update log) or orphaned/benign (only one hash ever appears in Update). No defensive
duplicate-instance guard has been added anywhere; per explicit instruction, none should be until
this is confirmed. **A fresh live run with this diagnostic has not yet occurred** — the log on
disk as of this writing predates the diagnostic-instrumented build.

## 2026-08-13 three-audit integration pass — SOURCE VERIFIED + OFFLINE TEST VERIFIED, INSTALLED FOR LIVE TEST

Reconciled three parallel overnight audit packages (Core/Suite+Hub, ten non-Deep mods, Deep Sims)
per `Erenshor-Three-Audit-Integration-Handoff` — semantically, not as blind patch application.
Highlights:

- Canonical v1 Hub contract implemented: two-argument `action(actionId, argument)`, mutable
  choice-setting descriptor (`options=`), Follow `HasDedicatedPanel=false`, canonical
  1.0s+`CanMove`-latch readiness policy used identically across Hub and all 10 fallback-capable
  mods (replacing several mods' original flat 2.5s policy), and a Hub self-presence Aura endpoint
  (`forgetwhtuno.erenshor.suitehub.v1.describe`) so mods can detect `HubLive`.
- Every one of the 10 non-Deep mods got a thin `<Mod>SuiteAuraProvider` wrapping its own
  `<Mod>ControlApi` — no mod references `ErenshorSuiteHub.dll`, every provider explicitly
  unregisters in `OnDestroy()`.
- The real Lunaris Aura transport shape (`LunarisPlugin.IPCAuraProvider<...>` /
  `IAuraProvider<...>.RegisterFunc/UnregisterFunc/RegisterAction/UnregisterAction`) was not
  documented by any of the three audits — it was derived from .NET reflection against the actual
  installed `Lunaris.dll` and used consistently across every provider.
- `BUILD_ALL.ps1`/`INSTALL_ALL.ps1` hardened with the Core worker's transactional
  install/rollback, staging-manifest fingerprinting, and (real bug fix) a
  whole-selected-set install gate — previously a failing declared test for one mod did not block
  that mod's DLL from installing.
- Real bugs found and fixed during reconciliation (not just ported): Journal's patch called a
  nonexistent `ResolveInitialWindowRect()` (fixed to the real `ResolveInitialRect()`); Campmaster's
  standalone `RUN_CONTROL_API_TESTS.ps1` harness stubs were already stale against the patch's own
  additions; Deep Sims' `RoleplayPerspective.cs` had a `Regex.Escape`-ordering bug that silently
  disabled every multi-word reject phrase in the final Roleplay guard; Deep Sims' `SocialFoundation.cs`
  identity-fact regex misclassified "what is a windblade?"-style questions.
- Central pipeline run for real: **12/12 plugins build, 12/12 pass their declared offline tests**
  (PvP's self-test is in-game-only by design), zero BepInEx references in any compiled plugin,
  `git diff --check` and a personal-data/secret/token privacy scan came back clean across all 13
  repos. All 12 DLLs installed to the live game's `plugins\` folder with the game closed.
- Nothing was committed, pushed, or merged. All 13 repos remain on their existing
  `agent/lunaris-native*` / `main` branches with uncommitted working-tree changes only.
- **NEEDS LIVE TEST**: everything UI/Hub/Aura/readiness-timing related — see
  `docs/LIVE_TEST_MATRIX.md` and the ordered live-test plan handed back to the user alongside this
  integration.

Do not build further shared UI containment infrastructure (`docs/ARCHITECTURE.md`'s
"Shared UI containment" section) until this is resolved.

---

## Per-mod status

### Deep Sims — NEEDS LIVE TEST
Native Lunaris migration confirmed working (Ollama connectivity, group responses, PvP/Follow
optional integration all observed live and functioning). Roleplay-mode fix landed this session in
three stages:
1. Fixed `/dsroleplay` not visibly changing dialogue — root cause was a post-generation template
   fallback (`SocialTemplates.RenderUnknownFactReply`) bypassing the roleplay-aware LLM prompt
   path entirely on grounding rejection.
2. Live evidence then showed `roleplayGuardApplied=False` on clearly-bad accepted output ("nice to
   see you online again", "heh yooo Brinon! aloha", etc.) even with the prompt fix in place —
   root cause: only the narrow autonomous/`/dstalk` path ever ran a roleplay content check; group
   replies, whispers, and event-thread reactions ran none. Added one central
   `RoleplayOutputGuard.Enforce` wired into every emission path.
3. Same pass: fixed a Sim-identity/subjective-question routing bug where "what do you think about
   being a windblade?" was misclassified as a factual lookup (needing external grounding an
   opinion can never satisfy) instead of a subjective question about a verified identity fact,
   plus added an explicit verified-class-vs-asked-class cross-reference to the prompt.

**None of this has been live-retested yet.** See `DeepSim-erenshor/docs/CURRENT_WORK.md` for full
detail, exact live evidence, and exact next test commands.

### Party Tools — NEEDS LIVE TEST
Lunaris migration only. Not touched this session beyond the migration itself.

### Contracts — NEEDS LIVE TEST
Player-ready gate (replaced scene-name `IsUsableScene` heuristic with the verified
`IsLocalCharacterReady()` signal), per-character data storage with one-time legacy-claim
migration, launcher grip/button-overlap fix (matches Journal), open-state deferred out of
`OnGUI`, and the instance-identity diagnostic described above. All build/test verified across
three rounds of fixes; awaiting a live run.

### Journal — NEEDS LIVE TEST
The known-good launcher interaction reference for the rest of the suite (narrow grip strip for
`GUI.DragWindow`, separate pure-click button — never overlapping). Player-ready gate and
per-character notebook storage with non-destructive legacy migration landed. The
click-to-open chain was traced end-to-end and found to have no logic defect; diagnostics were
added rather than a blind rewrite. Has not been proven live since that round of changes.

### Guild Life — NEEDS LIVE TEST
Same fix set as Contracts: player-ready gate, per-character bulletin storage with legacy-claim
migration, launcher grip/button-overlap fix, open-state deferred out of `OnGUI` (this last one
was *not* present in the first round — Contracts found it first, Guild Life had not yet had it
applied and needed the same fix in a later round).

### Campmaster — NEEDS LIVE TEST
Lunaris migration only. Not touched this session beyond the migration itself.

### Nemesis — NEEDS LIVE TEST
Lunaris migration only. Source of the verified player-ready-signal (`Ready()`) and
character-key/legacy-migration pattern (`ResolveCharacterKey`/`SafeKey`/
`MigrateLegacyCharacterSection`) that Journal, Contracts, and Guild Life all adopted this session.

### Crafting Expanded — BLOCKED
Still WIP per an earlier audit: missing LICENSE/NOTICE/CHANGELOG/SECURITY.md, intentionally
excluded from the public-repo publish pass that shipped the other ten mods. Builds and installs
fine through the suite pipeline; not yet treated as a finished suite member for anything beyond
that.

### Practice Duel — NEEDS LIVE TEST
Lunaris migration, plus a real bug fix ported from an old pre-migration checkout: party members
were incorrectly rejected with `wrong_scene` because they were subjected to the same
nearby-non-party-Sim locality gate. Fixed so party membership itself satisfies the locality
check (nearby non-party Sims and remote COOP humans keep their existing requirements
unchanged). Regression tests added; not yet live-retested.

### PvP — NEEDS LIVE TEST (combat itself: DONE)
**Encounter/combat already had a good live result this session — do not touch it.** UI-only work:
the quick-toggle was rebuilt from a bare `GUI.Toggle` (invisible under any other mod's window,
since Unity always renders windows after non-window controls) into a proper `GUI.Window`-based
launcher, twice — first for visibility, then again for the grip/button-overlap bug found across
the whole launcher family. Open-state mutation deferred out of `OnGUI`. **The full `PvpPanel`
drag-into-camera bug is still unresolved** (dragging the full panel can jump/stick at top-left and
move the world camera) — this is separate from the launcher fixes and needs its own investigation
(`PvpPanel.HandleDrag`/`PvpPanelPositionState`/`GUIUtility.hotControl`). Natural PvP ambush has not
yet been observed live — this is untested, not failed; current ambush timing/chance defaults
should be checked before drawing any conclusion once it is tested.

### Follow — NEEDS LIVE TEST
Lunaris migration. A reconciliation pass compared an old pre-migration checkout's ~591 lines of
uncommitted work against the shipped 0.4.1/0.4.2 route-reliability release: almost all of it had
already shipped in evolved form. Two genuinely unique, still-missing pieces were identified but
**not yet ported**: (1) a false-near-approach bug where crossing proximity is measured against a
collider's world-space bounding box instead of its true shape, and (2) a bounded re-sample
recovery path for when every pre-built route candidate has failed. See the old checkout's
diff/analysis for exact code if this gets picked up.

---

## Suite-level work (this repo)

### Central repo, manifest, build/install pipeline — DONE (build/test verified)
`suite.json` manifest, `SETUP_WORKSPACE.ps1` (originally junction-based workspace linking, since
replaced by a single consolidated project root with every mod as a real worktree — see
`docs/ARCHITECTURE.md`), `BUILD_ALL.ps1` /
`INSTALL_ALL.ps1` / `BUILD_AND_INSTALL_ALL.bat` (staging-then-atomic build/install). Ran
end-to-end against all 11 mods: every mod built, every mod with a test suite passed, every mod
installed to the live plugins folder with a reported SHA256. This is genuinely verified — it's
build/install tooling, not gameplay, so "live game test" doesn't apply the same way; verification
here means "the pipeline itself ran correctly," which it did.

### Suite Hub — see `docs/SUITE_STATUS.md` for current phase and exact scope delivered this session.

### Shared UI containment utility — NOT STARTED
Blocked on the duplicate-instance question above, per explicit instruction.

---

## Next live tests (exact commands)

**Duplicate-instance diagnostic**: launch the game, load a character, wait ~15-20s, check
`lunaris.log` for `[ContractsInstanceDiag]` lines. If only one hash ever appears in `Update tick`
lines, the second Awake was orphaned/benign. If two distinct hashes both keep appearing in
`Update tick` lines over time, two live instances are genuinely coexisting.

**Contracts / Guild Life / PvP launchers**: load a character, confirm no launcher shows before
that point, confirm the launcher appears after, drag it by the grip only, click the action area
and confirm it opens/closes the panel reliably.

**Deep Sims roleplay**: `/dsroleplay on` → `/dsroleplay status` (confirms "Roleplay") → group chat
"dancer what do you think about being a windblade?" (should get an in-world, class-grounded
opinion, not "no idea, honestly" or MMO-flavored filler) → `/dstalk Dancer` → `/dsroleplay off` and
repeat to confirm reversion. Watch the log for `RoleplayDiag`/guard lines.

**PvP**: stand in an allowed ambush zone with PvP and ambush enabled, wait for a natural ambush
(check configured ambush timing/chance defaults first — this has not failed, it just hasn't
happened yet in a session). Separately: drag the full PvP panel and confirm it doesn't jump/stick
or move the world camera (currently expected to still fail — this is the known open PvP panel bug).

## Next deep audit questions

- Is the Lunaris duplicate-Awake behavior expected/documented Lunaris behavior, a Lunaris bug, or
  something about how this suite's build/install process registers plugins that could be
  corrected on our side?
- Does the `RoleplayOutputGuard` word/phrase reject list need tuning after a real live pass, or is
  it too aggressive/too lax in practice?
- Full architectural review of `PvpPanel`'s drag implementation vs. simplifying to ordinary
  `GUI.Window` + dedicated header `GUI.DragWindow`, per the suite-direction task's Part 12.
