param(
    [string[]]$Mod = @(),
    [string]$GameDir = "",
    [string]$StageRoot = "",
    [string]$OutputDir = "",
    [switch]$AllowReleaseCandidateWithLiveBlockers
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $SuiteRoot
. (Join-Path $SuiteRoot "Release.Common.ps1")

$manifest = Get-ReleaseSuiteManifest $SuiteRoot
$whitelistPath = Join-Path $SuiteRoot "release-whitelist.json"
$readinessPath = Join-Path $SuiteRoot "release-manifest.json"
if (-not (Test-Path $whitelistPath)) { throw "release-whitelist.json missing." }
if (-not (Test-Path $readinessPath)) { throw "release-manifest.json missing." }
$whitelist = Get-Content $whitelistPath -Raw | ConvertFrom-Json
$readiness = Get-Content $readinessPath -Raw | ConvertFrom-Json

if (-not $StageRoot) { $StageRoot = Join-Path $env:TEMP "ErenshorSuiteBuildStaging" }
$stageManifestPath = Join-Path $StageRoot "suite-build.json"
$stageManifest = Get-Content $stageManifestPath -Raw | ConvertFrom-Json
if ($stageManifest.schemaVersion -ne 1) { throw "Unsupported staging manifest schema." }

if (-not $OutputDir) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputDir = Join-Path $ProjectRoot ("release-output\" + $stamp)
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$selectedEntries = @($stageManifest.entries)
if ($Mod.Count -gt 0) {
    foreach ($id in $Mod) {
        if ($null -eq ($selectedEntries | Where-Object { $_.id -eq $id } | Select-Object -First 1)) {
            throw "Requested mod '$id' is not in the staged build set."
        }
    }
    $selectedEntries = @($selectedEntries | Where-Object { $Mod -contains $_.id })
}
if ($selectedEntries.Count -eq 0) { throw "No staged mods selected for packaging." }

$generated = [ordered]@{
    schemaVersion = 1
    generatedUtc = [DateTime]::UtcNow.ToString("o")
    packageMode = if ($AllowReleaseCandidateWithLiveBlockers) { "RELEASE_CANDIDATE" } else { "FINAL_RELEASE_GATE" }
    publicIdentity = $whitelist.publicIdentity
    packages = @()
}

foreach ($entry in $selectedEntries) {
    $id = [string]$entry.id
    $modMeta = $manifest.mods | Where-Object { $_.id -eq $id } | Select-Object -First 1
    $white = $whitelist.mods | Where-Object { $_.id -eq $id } | Select-Object -First 1
    $live = $readiness.mods | Where-Object { $_.modId -eq $id } | Select-Object -First 1
    if ($null -eq $modMeta -or $null -eq $white -or $null -eq $live) { throw "Release metadata incomplete for $id." }

    if ([bool]$entry.dirty) { throw "Refusing release package for dirty staged source: $id" }
    if ([string]$entry.testStatus -ne "PASS") {
        throw "Refusing release package for $id because deterministic tests are not PASS in staging (status=$($entry.testStatus))."
    }
    if ([string]$entry.version -ne [string]$modMeta.version) {
        throw "Version mismatch for ${id}: staged=$($entry.version) manifest=$($modMeta.version)"
    }

    $blockers = @($live.knownBlockers)
    if (-not $AllowReleaseCandidateWithLiveBlockers -and $blockers.Count -gt 0) {
        throw "Refusing FINAL package for $id while live blockers remain. Use -AllowReleaseCandidateWithLiveBlockers only for clearly labeled RC artifacts."
    }

    $modDir = Get-ReleaseModDirectory -Manifest $manifest -ProjectRoot $ProjectRoot -Mod $modMeta
    $stagedDll = Join-Path (Join-Path $StageRoot "plugins") $entry.dll
    if (-not (Test-Path $stagedDll)) { throw "Staged DLL missing: $stagedDll" }
    $dllHash = (Get-FileHash $stagedDll -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($dllHash -ne ([string]$entry.sha256).ToLowerInvariant()) { throw "Staged DLL hash mismatch for $id." }

    $packageRoot = Join-Path $OutputDir ("_package-" + $id)
    if (Test-Path $packageRoot) { Remove-Item $packageRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

    $candidateFiles = @()
    $dllTarget = Join-Path $packageRoot $entry.dll
    Copy-Item $stagedDll $dllTarget -Force
    $candidateFiles += $dllTarget

    foreach ($required in @($white.requiredFiles)) {
        $src = Join-Path $modDir $required
        if (-not (Test-Path $src -PathType Leaf)) { throw "Required release document missing for ${id}: $required" }
        $dst = Join-Path $packageRoot $required
        Copy-Item $src $dst -Force
        $candidateFiles += $dst
    }
    foreach ($optional in @($white.optionalFiles)) {
        $src = Join-Path $modDir $optional
        if (Test-Path $src -PathType Leaf) {
            $dst = Join-Path $packageRoot $optional
            Copy-Item $src $dst -Force
            $candidateFiles += $dst
        }
    }

    $entryPointText = (@($white.entryPoints) | ForEach-Object { "- $_" }) -join "`n"
    $experimentalText = if (@($white.experimental).Count -gt 0) {
        (@($white.experimental) | ForEach-Object { "- $_" }) -join "`n"
    } else {
        "- No extra release-engineering caveat is declared here; see README.md for gameplay-specific status."
    }
    $installText = @"
# Install $($modMeta.displayName) $($modMeta.version)

1. Install and update **Lunaris** separately. Lunaris and game/framework DLLs are not bundled here.
2. Close Erenshor for a normal install.
3. Copy **$($entry.dll)** into Erenshor's active `plugins` directory.
4. Launch Erenshor and verify the plugin startup line before using the feature.
5. Mod configuration is stored through Lunaris/mod-owned config. Do not copy another player's live `.lpcfg`.
6. To uninstall, close Erenshor and remove only **$($entry.dll)** plus mod-owned config/data you intentionally want to discard.

## Entry points

$entryPointText

## Compatibility

- Current Erenshor build and current Lunaris are required.
- Suite Hub is optional unless the mod's README explicitly says otherwise; standalone behavior remains authoritative.
- See README.md for mod-specific optional integrations.

## Experimental / live-test caveats

$experimentalText
"@
    $installPath = Join-Path $packageRoot "INSTALL.md"
    Set-Content $installPath $installText -Encoding UTF8
    $candidateFiles += $installPath

    $privacyIssues = @(Invoke-PrivacyScan -Files $candidateFiles -BaseDir $packageRoot)
    if ($privacyIssues.Count -gt 0) {
        throw "Privacy/package scan failed for ${id}: $($privacyIssues -join ' | ')"
    }

    # Final whitelist assertion: the package temp directory may contain only the DLL, generated INSTALL,
    # and the explicitly named required/optional docs copied above.
    $allowedNames = @([string]$entry.dll, "INSTALL.md") + @($white.requiredFiles) + @($white.optionalFiles)
    $unexpected = @(Get-ChildItem -LiteralPath $packageRoot -File -Recurse | Where-Object { $allowedNames -notcontains $_.Name })
    if ($unexpected.Count -gt 0) { throw "Unexpected non-whitelisted package files for ${id}: $($unexpected.Name -join ', ')" }

    $zipName = "{0}-{1}.zip" -f $id,$modMeta.version
    if ($AllowReleaseCandidateWithLiveBlockers) { $zipName = "{0}-{1}-RC.zip" -f $id,$modMeta.version }
    $zipPath = Join-Path $OutputDir $zipName
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -CompressionLevel Optimal
    $zipHash = (Get-FileHash $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $generated.packages += [ordered]@{
        modId = $id
        version = [string]$modMeta.version
        dllFilename = [string]$entry.dll
        dllSha256 = $dllHash
        packageFilename = $zipName
        packageSha256 = $zipHash
        sourceRevisionBuildMarker = $(if ($entry.PSObject.Properties.Name -contains "sourceMarker" -and $entry.sourceMarker) { [string]$entry.sourceMarker } else { [string]$entry.branch + "@" + [string]$entry.sourceSha })
        deterministicTestStatus = [string]$entry.testStatus
        liveTestStatus = $live.liveTestStatus
        knownBlockers = $blockers
        privacyScan = "PASS"
    }

    Remove-Item $packageRoot -Recurse -Force
    Write-Host "PACKAGED $id -> $zipPath" -ForegroundColor Green
}

$manifestOut = Join-Path $OutputDir "release-manifest.generated.json"
$generated | ConvertTo-Json -Depth 12 | Set-Content $manifestOut -Encoding UTF8
Write-Host "`nRelease manifest: $manifestOut" -ForegroundColor Cyan
Write-Host "No source tree, handoff archive, game DLL, Lunaris.dll, Harmony DLL, logs, configs, PDBs, or intermediates were included." -ForegroundColor Green
