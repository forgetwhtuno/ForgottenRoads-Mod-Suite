# Installs already-built mod DLLs from the last BUILD_ALL.ps1 staging run into the live plugins
# folder, without rebuilding anything. Useful after a -BuildOnly pass once you're ready to test,
# or to reinstall without recompiling. Run BUILD_ALL.ps1 first if the staging folder is empty or
# stale for a mod you want.
#
# Usage: powershell -File INSTALL_ALL.ps1 [-Mod PvP] [-GameDir "D:\...\Erenshor"]

param(
    [string[]]$Mod = @(),
    [string]$GameDir = ""
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Manifest = Get-Content (Join-Path $SuiteRoot "suite.json") -Raw | ConvertFrom-Json

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
$RealPlugins = Join-Path $RealGameDir "plugins"
$StagingPlugins = Join-Path $env:TEMP "ErenshorSuiteBuildStaging\plugins"

if (-not (Test-Path $StagingPlugins)) {
    throw "No staged build found at $StagingPlugins. Run BUILD_ALL.ps1 first."
}

$selected = $Manifest.mods | Where-Object { $_.enabled }
if ($Mod.Count -gt 0) { $selected = $selected | Where-Object { $Mod -contains $_.id } }

$results = @()
foreach ($m in $selected) {
    $staged = Join-Path $StagingPlugins $m.dll
    $row = [PSCustomObject]@{ Mod = $m.displayName; Installed = "-"; Sha256 = "-" }
    if (-not (Test-Path $staged)) {
        $row.Installed = "no staged build found"
        $results += $row
        continue
    }
    $live = Join-Path $RealPlugins $m.dll
    Copy-Item $staged $live -Force
    $row.Installed = "yes"
    $row.Sha256 = (Get-FileHash $live -Algorithm SHA256).Hash.ToLowerInvariant().Substring(0, 16) + "..."
    $results += $row
}

Write-Host "`n==== Install summary ====" -ForegroundColor Cyan
$results | Format-Table -AutoSize
