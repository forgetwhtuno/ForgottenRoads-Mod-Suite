# Suite Hub Integration Contract v1

Status: **VERIFIED SOURCE / BUILD VERIFIED (Hub side) / NEEDS SIBLING IMPLEMENTATION + LIVE TEST**.

This contract is deliberately small. The Hub is optional; the owning mod remains authoritative.
No shared contract DLL or load order is required.

## Layering

```text
Suite Hub UI
    |
    | Lunaris Aura v1 wire transport
    v
<Mod>SuiteAuraProvider  (inside each mod, optional transport adapter)
    |
    v
public <Mod>ControlApi  (authoritative mod-owned API)
    |
    v
mod controller/settings/state
```

No mod references `ErenshorSuiteHub.dll` at compile time.

## Module IDs

```text
deepsims
partytools
follow
campmaster
duel
pvp
nemesis
crafting
contracts
guildlife
journal
```

## Transport

Current carrier: Lunaris Aura (`LunarisPlugin.IPCAuraProvider<...>` on the mod side,
`LunarisPlugin.IPCAuraSubscriber<...>` on the Hub side), verified against the real installed
`Lunaris.dll`.

For module ID `<id>`:

```text
forgetwhtuno.erenshor.suite.<id>.v1.describe
forgetwhtuno.erenshor.suite.<id>.v1.settings.basic
forgetwhtuno.erenshor.suite.<id>.v1.settings.advanced
forgetwhtuno.erenshor.suite.<id>.v1.settings.developer
forgetwhtuno.erenshor.suite.<id>.v1.setting.set
forgetwhtuno.erenshor.suite.<id>.v1.action
```

Signatures (this is the canonical v1 shape — note `action` takes an argument, changed from an
earlier one-argument draft before any mod provider shipped):

```text
describe             Func<string>
settings.*           Func<string>
setting.set          Func<string settingId, string value, string result>
action               Func<string actionId, string argument, string result>
```

`describe` is required for a module to be runtime-connected. Every other endpoint is optional.
Simple actions that take no argument pass an empty string, e.g. `action("openPanel", "")`.

### Hub presence (optional, Hub -> mod direction)

The Hub also publishes its own tiny live-presence endpoint:

```text
forgetwhtuno.erenshor.suitehub.v1.describe     Func<string>
```

This is deliberately outside the per-module namespace (it describes the Hub, not a module) and
carries only `protocol`/`module=suitehub`/`display`/`version`/`status`. A sibling mod's own
standalone-launcher-suppression logic may subscribe to this to detect `HubLive` without scanning
the scene for Hub components — see "Standalone launcher visibility" below. Mod-side live-component
probing may remain as a temporary fallback until every fallback-capable mod adopts this.

## Descriptor wire format

UTF-8/BCL string, query-style fields, percent-escaped values, maximum 8192 characters. Unknown
fields may be ignored; duplicate fields are rejected.

Example:

```text
protocol=1&module=pvp&display=PvP&version=0.4.0&summary=Arranged%20and%20ambient%20PvP&status=Enabled&warning=&actions=openPanel,closePanel
```

Required:

- `protocol=1`
- `module=<catalog id>` and it must match the channel the Hub queried
- `display` 1..64 characters
- `version` 1..32 characters

Optional bounded fields: `summary`, `status`, `warning`, `actions`.

The Hub validates descriptors before registration and never treats DLL presence as runtime API
availability.

## Settings wire format

One query-style record per line. Example:

```text
id=enabled&label=Enabled&tier=basic&type=bool&value=true&mutable=true
id=mode&label=Social%20mode&tier=basic&type=choice&value=Auto&mutable=true&options=Auto,LLM,Templates,Off
```

Fields:

- `id`: stable key
- `label`: player-facing label
- `tier`: `basic`, `advanced`, or `developer`
- `type`: `bool`, `text`, `number`, or `choice`
- `value`: current mod-owned value
- `mutable`: `true` only when the provider accepts changes through `setting.set`
- `options`: comma-separated bounded list of allowed values, each percent-escaped using the same
  wire codec rules as every other field. **Required** for a mutable `choice` setting; the Hub
  rejects a mutable choice descriptor with no options, and rejects one whose current `value` is not
  itself one of the listed options. Optional (and ignored if present) for a read-only `choice`.

The Hub does not independently persist a change. `setting.set` must validate and save through the
owning mod's normal code path. Return strings beginning with `ok` for success; return a safe
short reason otherwise.

Phase 2 Hub editor support (implemented):

- mutable `bool` — rendered as a toggle.
- mutable `choice` — rendered as a `< value >` cycle control that steps through `options` and
  calls `setting.set` with the next value.

`text`/`number` remain read-only display until a specific safe editor is implemented; the wire
types already reserve the contract without forcing a raw config editor.

## Actions

An action may be invoked only if its ID was advertised in `describe.actions`.

Standard IDs reserved by the suite:

- `openPanel`
- `closePanel`

Module-specific actions should be ordinary explicit player controls, not autonomous gameplay, and
may take a single string argument for target-selection-style actions (roll sides, challenge
target, nemesis selection, etc. — see the per-module suggested list in
`CONTRACT_RECONCILIATION.md` from the integration handoff). The owning mod must revalidate all
state/eligibility/argument content when invoked. The Hub is not authorization.

## Load/unload contract

Provider requirements:

1. Create/register Aura provider handlers during the mod's normal load path.
2. Registration must not require the Hub to exist.
3. Keep provider objects so they can be cleaned up.
4. In `OnDestroy`, call `UnregisterFunc`/`UnregisterAction` for every provider handler.
5. Do not assume plugin load order.
6. Reload may register the same labels again after cleanup; it must not create duplicate logical
   module state.

Current Lunaris source does **not** automatically unregister Aura handlers when a plugin unloads,
so step 4 is correctness-critical. The Hub's own `AuraModuleBridge` (subscriber side) and its
presence provider (publisher side) both follow this rule as the reference implementation.

## Standalone launcher visibility

For fallback-launcher mods, hide the standalone launcher only when all of the following hold:

```text
visible = GameplayReady
          AND (
              ShowStandaloneLauncherWithHub
              OR !HubLive
              OR !ThisModuleSuiteBridgeRegistered
          )
```

Equivalently: hide only when `GameplayReady AND HubLive AND ThisModuleSuiteBridgeRegistered AND
!ShowStandaloneLauncherWithHub`. This prevents the Hub from hiding the only GUI when a module's
Aura provider failed to register even though the Hub itself is present — a player must never be
stranded without any way to reach a mod's controls. `HubLive` may be sourced from the Hub presence
endpoint above once implemented on the mod side; until then, a live-component scene probe is an
acceptable temporary fallback.

## Authority and privacy

Never send secrets, tokens, private file paths, prompts/memory dumps, or raw developer internals
through this UI contract. Descriptors are player-facing state only.

The Hub never calls private internals, edits `.lpcfg`, or directly controls Erenshor gameplay.
