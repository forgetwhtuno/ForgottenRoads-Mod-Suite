# Lunaris Plugin Identity Audit

## Release rule

Forgotten Roads release tooling treats a module as healthy only when its **Lunaris plugin identity** is discoverable exactly once across the current Lunaris plugin scan boundary.

For the current Lunaris runtime, the proven native discovery boundary is:

```text
<Erenshor>\plugins\**\*.dll
```

The scan is recursive. Directory segments named `config` are excluded. The hot-reload cache is a load/cache implementation detail, not a second discovery root. Legacy BepInEx compatibility changes how a DLL is interpreted; it does not establish another Forgotten Roads plugin root in the current loader source.

## Identity mechanism

The audit deliberately invokes the installed/current Lunaris implementation of:

```text
PluginAssemblyUtils.GetGuid(string assemblyPath)
```

rather than guessing identity from the filename.

Current Lunaris resolves identity in this order:

1. assembly metadata key `LunarisPluginId`, when present;
2. legacy BepInEx plugin GUID for a BepInEx plugin;
3. managed assembly name as the native fallback.

The current Forgotten Roads modules do not declare a `LunarisPluginId` assembly override or a BepInEx plugin attribute, so their expected native plugin IDs match their assembly names. Those IDs are recorded explicitly in `suite.json`.

## PASS / REVIEW

PASS requires one discoverable identity for each required module and no unreadable managed identity in the active scan tree.

REVIEW is required for any of these cases:

- the same plugin ID appears more than once, even under different filenames or nested directories;
- a canonical Forgotten Roads filename declares the wrong identity;
- a managed DLL identity cannot be resolved by current Lunaris;
- an expected required identity is missing;
- a selected install would place a canonical DLL while that same identity is already active at another path.

## Quarantine

`AUDIT_ACTIVE_PLUGINS.ps1 -QuarantineConfirmedBackups` is intentionally narrow. It moves only a DLL that:

- resolves exactly to a known Forgotten Roads plugin ID;
- is not the canonical filename for that module; and
- has an obvious backup/copy marker such as `old`, `backup`, `bak`, `copy`, `previous`, or `(2)`.

The destination is a sibling `plugins-disabled` tree outside `<Erenshor>\plugins`, so current recursive Lunaris scanning cannot rediscover it.

Canonical duplicates, unexplained renamed assemblies, ambiguous identities, and unrelated third-party plugins are **never** moved automatically.

## Install integration

Both `BUILD_ALL.ps1` installation and `INSTALL_ALL.ps1` now perform:

```text
identity preflight
  -> transactional DLL replacement
  -> identity postflight
```

The postflight runs inside the transaction's validation boundary. If it fails, prior Forgotten Roads DLLs are restored by the same rollback path used for file/hash failures.

The scripts continue to SHA-256 verify staged and installed DLLs. Identity verification supplements hashes; it does not replace them.
