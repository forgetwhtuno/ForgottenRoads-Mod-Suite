# Install a previously COMPLETE BUILD_ALL.ps1 staging set without rebuilding. The staging
# manifest fingerprints suite.json, Assembly-CSharp.dll and every staged DLL so stale/mixed output
# is refused instead of silently copied.

param(
    [string[]]$Mod = @(),
    [string]$GameDir = "",
    [switch]$AllowGameRunning
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $SuiteRoot "SuiteBuild.Common.ps1")
. (Join-Path $SuiteRoot "Release.Common.ps1")
$SuiteJson = Join-Path $SuiteRoot "suite.json"
$Manifest = Get-Content $SuiteJson -Raw | ConvertFrom-Json

function Find-Game([string]$Explicit) {
    if ($Explicit -and (Test-Path (Join-Path $Explicit "Erenshor.exe"))) { return (Resolve-Path $Explicit).Path }
    $candidates = @()
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($pf) { $candidates += (Join-Path $pf "Steam\steamapps\common\Erenshor") }
    }
    foreach ($root in @((Join-Path ${env:ProgramFiles(x86)} "Steam"), (Join-Path $env:ProgramFiles "Steam"))) {
        if (-not $root) { continue }
        $vdf = Join-Path $root "steamapps\libraryfolders.vdf"
        if (Test-Path $vdf) {
            [regex]::Matches((Get-Content $vdf -Raw), '"path"\s+"([^"]+)"') | ForEach-Object {
                $library = $_.Groups[1].Value -replace '\\\\', '\'
                $candidates += [IO.Path]::Combine($library, "steamapps", "common", "Erenshor")
            }
        }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path (Join-Path $candidate "Erenshor.exe"))) { return (Resolve-Path $candidate).Path }
    }
    throw "Erenshor installation not found. Pass -GameDir 'C:\path\to\Erenshor'."
}

$RealGameDir = Find-Game $GameDir
$RealPlugins = Join-Path $RealGameDir "plugins"
$assemblyCSharp = Join-Path $RealGameDir "Erenshor_Data\Managed\Assembly-CSharp.dll"
$Staging = Join-Path $env:TEMP "ErenshorSuiteBuildStaging"
$StagingPlugins = Join-Path $Staging "plugins"
$StageManifestPath = Join-Path $Staging "suite-build.json"
$stage = Read-SuiteStageManifest $StageManifestPath

if ((Get-Sha256 $SuiteJson) -ne [string]$stage.suiteJsonSha256) {
    throw "suite.json changed since this staging set was built. Re-run BUILD_ALL.ps1."
}
if ((Get-Sha256 $assemblyCSharp) -ne [string]$stage.assemblyCSharpSha256) {
    throw "Assembly-CSharp.dll changed since this staging set was built. Rebuild against the current game."
}
if ((Test-ErenshorRunning) -and -not $AllowGameRunning) {
    throw "Erenshor is running. Close it before installing, or pass -AllowGameRunning only when intentional Lunaris hot reload is safe."
}

$entries = @($stage.entries)
if ($Mod.Count -gt 0) {
    foreach ($requested in $Mod) {
        if ($null -eq ($entries | Where-Object { $_.id -eq $requested } | Select-Object -First 1)) {
            throw "Requested mod '$requested' is not part of this complete staging set. Re-run BUILD_ALL.ps1 with the desired selection."
        }
    }
    $entries = @($entries | Where-Object { $Mod -contains $_.id })
}
if ($entries.Count -eq 0) { throw "No staged modules selected." }

$installItems = @()
foreach ($entry in $entries) {
    $staged = Join-Path $StagingPlugins $entry.dll
    if (-not (Test-Path $staged)) { throw "Staged DLL is missing: $($entry.dll)" }
    $actualHash = Get-Sha256 $staged
    if ($actualHash -ne [string]$entry.sha256) { throw "Staged DLL hash mismatch: $($entry.dll). Rebuild." }
    $installItems += [PSCustomObject]@{
        Id=$entry.id; DisplayName=$entry.displayName; Source=$staged; Destination=(Join-Path $RealPlugins $entry.dll); ExpectedSha256=$actualHash; Entry=$entry
    }
}

$lunarisIdentityDll = Resolve-LunarisIdentityAssemblyPath -GameDir $RealGameDir
$preIdentityAudit = Get-LunarisSuiteIdentityAudit -PluginsDir $RealPlugins -Manifest $Manifest -LunarisDll $lunarisIdentityDll -AllowMissing
Assert-LunarisSuiteIdentityPreInstall -Audit $preIdentityAudit -InstallItems $installItems

$requiredInstallIds = @($installItems | ForEach-Object { $_.Id })
$postValidation = {
    $post = Get-LunarisSuiteIdentityAudit -PluginsDir $RealPlugins -Manifest $Manifest -LunarisDll $lunarisIdentityDll -AllowMissing
    Assert-LunarisSuiteIdentityForInstall -Audit $post -RequiredIds $requiredInstallIds -AllowMissingOthers
}
Install-SuiteSetTransactional $installItems -PostInstallValidation $postValidation

$postIdentityAudit = Get-LunarisSuiteIdentityAudit -PluginsDir $RealPlugins -Manifest $Manifest -LunarisDll $lunarisIdentityDll -AllowMissing
Assert-LunarisSuiteIdentityForInstall -Audit $postIdentityAudit -RequiredIds $requiredInstallIds -AllowMissingOthers

$results = @()
foreach ($item in $installItems) {
    $liveHash = Get-Sha256 $item.Destination
    $entry = $item.Entry
    $results += [PSCustomObject]@{
        Mod = $entry.displayName
        Source = $entry.branch + "@" + ([string]$entry.sourceSha).Substring(0, 12)
        Installed = "yes"
        Sha256 = $liveHash.Substring(0, 16) + "..."
    }
}

Write-Host "`n==== Install summary ====" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "Lunaris identity audit: PASS - one discoverable identity for every installed module selected in this transaction." -ForegroundColor Green
