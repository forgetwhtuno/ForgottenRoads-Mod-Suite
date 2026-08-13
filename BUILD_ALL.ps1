# Builds (and by default installs) every enabled mod in suite.json.
#
# Each mod keeps its own authoritative BUILD_AND_INSTALL.ps1 (own reference list, own build
# quirks) rather than this script reimplementing csc invocation per mod -- that would duplicate
# and drift from each repo's real build logic. Instead this script points every mod's own build
# script at a disposable STAGING copy of the game folder (junctioned to the real
# Erenshor_Data\Managed so no framework DLL is ever duplicated, plus a tiny copied Erenshor.exe
# stub so each script's own "is this really the game folder" check passes), so every mod's DLL is
# written to a private temp plugins\ folder first. Only after that mod's build genuinely succeeds
# does this script copy its DLL into the REAL live plugins folder -- a failed or partial build
# never touches the live install.
#
# Usage:
#   powershell -File BUILD_ALL.ps1                        # build + test + install every enabled mod
#   powershell -File BUILD_ALL.ps1 -BuildOnly              # build (+test) only, never touch live plugins
#   powershell -File BUILD_ALL.ps1 -Mod PvP -Mod DeepSims  # only these mods
#   powershell -File BUILD_ALL.ps1 -Skip CraftingExpanded  # every enabled mod except these
#   powershell -File BUILD_ALL.ps1 -RunTests:$false        # skip each mod's RUN_TESTS.ps1
#   powershell -File BUILD_ALL.ps1 -Clean                  # wipe the staging dir first

param(
    [switch]$BuildOnly,
    [switch]$Install = $true,
    [switch]$Clean,
    [string[]]$Mod = @(),
    [string[]]$Skip = @(),
    [bool]$RunTests = $true,
    [string]$GameDir = ""
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Manifest = Get-Content (Join-Path $SuiteRoot "suite.json") -Raw | ConvertFrom-Json
$WorkspaceRoot = (Resolve-Path (Join-Path $SuiteRoot $Manifest.workspaceRoot)).Path
if ($BuildOnly) { $Install = $false }

function Find-Game([string]$Explicit) {
    if ($Explicit -and (Test-Path (Join-Path $Explicit "Erenshor.exe"))) { return (Resolve-Path $Explicit).Path }
    $candidates = @()
    foreach ($pf in @(${env:ProgramFiles(x86)}, $env:ProgramFiles)) {
        if ($pf) { $candidates += (Join-Path $pf "Steam\steamapps\common\Erenshor") }
    }
    foreach ($root in @((Join-Path ${env:ProgramFiles(x86)} "Steam"), (Join-Path $env:ProgramFiles "Steam"))) {
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
$RealManaged = Join-Path $RealGameDir "Erenshor_Data\Managed"
$RealPlugins = Join-Path $RealGameDir "plugins"
$ModsDir = Join-Path $WorkspaceRoot $Manifest.modsSubdir
# DeepSim-erenshor's checkout carries the dev-reference copy of Lunaris.dll/0Harmony.dll that the
# game install itself doesn't have anywhere under it; every mod's own build script needs it.
$LunarisLibDir = Join-Path $ModsDir "DeepSim-erenshor\LunarisLibs"

foreach ($required in @(
        (Join-Path $RealManaged "Assembly-CSharp.dll"),
        (Join-Path $LunarisLibDir "Lunaris.dll"),
        (Join-Path $LunarisLibDir "0Harmony.dll"),
        (Join-Path $RealGameDir "Erenshor.exe")
    )) {
    if (-not (Test-Path $required)) { throw "Required file missing: $required" }
}

Write-Host "Game:    $RealGameDir" -ForegroundColor Cyan
Write-Host "Managed: $RealManaged" -ForegroundColor Cyan
Write-Host "Lunaris: $LunarisLibDir" -ForegroundColor Cyan
Write-Host "Install: $Install (RunTests=$RunTests)" -ForegroundColor Cyan

# --- Staging area: a disposable stand-in game folder so every mod's own BUILD_AND_INSTALL.ps1
# writes its DLL to a private plugins\ folder instead of the live one, with zero framework-DLL
# duplication (junction, not copy) and zero interference between mods building in the same run.
$Staging = Join-Path $env:TEMP "ErenshorSuiteBuildStaging"
if ($Clean -and (Test-Path $Staging)) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Staging | Out-Null
$StagingData = Join-Path $Staging "Erenshor_Data"
if (-not (Test-Path $StagingData)) {
    New-Item -ItemType Junction -Path $StagingData -Target (Join-Path $RealGameDir "Erenshor_Data") | Out-Null
}
$StagingExe = Join-Path $Staging "Erenshor.exe"
if (-not (Test-Path $StagingExe)) { Copy-Item (Join-Path $RealGameDir "Erenshor.exe") $StagingExe -Force }
$StagingPlugins = Join-Path $Staging "plugins"
if (Test-Path $StagingPlugins) { Remove-Item $StagingPlugins -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StagingPlugins | Out-Null

# --- Select mods ---
$selected = $Manifest.mods | Where-Object { $_.enabled }
if ($Mod.Count -gt 0) { $selected = $selected | Where-Object { $Mod -contains $_.id } }
if ($Skip.Count -gt 0) { $selected = $selected | Where-Object { $Skip -notcontains $_.id } }

$results = @()

foreach ($m in $selected) {
    $underMods = $true
    if ($m.PSObject.Properties.Name -contains "underMods") { $underMods = $m.underMods }
    $modDir = if ($underMods) { Join-Path $ModsDir $m.localDir } else { Join-Path $WorkspaceRoot $m.localDir }
    $buildScript = Join-Path $modDir "BUILD_AND_INSTALL.ps1"
    $row = [PSCustomObject]@{
        Mod       = $m.displayName
        Build     = "SKIPPED"
        Tests     = "-"
        Installed = "-"
        Sha256    = "-"
    }

    if (-not (Test-Path $modDir)) {
        $row.Build = "FAILED (mod dir not found: $modDir; run SETUP_WORKSPACE.ps1)"
        $results += $row
        continue
    }
    if (-not (Test-Path $buildScript)) {
        $row.Build = "FAILED (no BUILD_AND_INSTALL.ps1 in $modDir)"
        $results += $row
        continue
    }

    Write-Host "`n==== $($m.displayName) ====" -ForegroundColor Cyan
    $stagedDll = Join-Path $StagingPlugins $m.dll
    if (Test-Path $stagedDll) { Remove-Item $stagedDll -Force }

    try {
        & $buildScript -GameDir $Staging -LunarisLibDir $LunarisLibDir
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "build script exit code $LASTEXITCODE" }
        if (-not (Test-Path $stagedDll)) { throw "build script reported success but $($m.dll) was not produced" }
        $row.Build = "OK"
    }
    catch {
        $row.Build = "FAILED: $($_.Exception.Message)"
        Write-Host "[$($m.displayName)] BUILD FAILED - $($_.Exception.Message)" -ForegroundColor Red
        $results += $row
        continue
    }

    if ($RunTests) {
        $testScript = Join-Path $modDir "RUN_TESTS.ps1"
        if (Test-Path $testScript) {
            try {
                Push-Location $modDir
                & $testScript
                if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "test script exit code $LASTEXITCODE" }
                $row.Tests = "PASS"
            }
            catch {
                $row.Tests = "FAIL: $($_.Exception.Message)"
                Write-Host "[$($m.displayName)] TESTS FAILED - $($_.Exception.Message)" -ForegroundColor Red
            }
            finally { Pop-Location }
        }
        else {
            $row.Tests = "none"
        }
    }
    else {
        $row.Tests = "skipped"
    }

    $hash = (Get-FileHash $stagedDll -Algorithm SHA256).Hash.ToLowerInvariant()
    $row.Sha256 = $hash.Substring(0, 16) + "..."

    if ($Install) {
        $liveDll = Join-Path $RealPlugins $m.dll
        # Atomic-enough final step: the fully-built, already-verified staged DLL is the only thing
        # ever written to the live path, and only after everything above succeeded.
        Copy-Item $stagedDll $liveDll -Force
        $row.Installed = "yes"
        Write-Host "[$($m.displayName)] installed -> $liveDll" -ForegroundColor Green
    }
    else {
        $row.Installed = "no (BuildOnly)"
    }

    $results += $row
}

Write-Host "`n==== Suite build summary ====" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$failed = $results | Where-Object { $_.Build -like "FAILED*" -or $_.Tests -like "FAIL:*" }
if ($failed.Count -gt 0) {
    Write-Host "$($failed.Count) mod(s) failed. Nothing failed was installed." -ForegroundColor Yellow
    exit 1
}
exit 0
