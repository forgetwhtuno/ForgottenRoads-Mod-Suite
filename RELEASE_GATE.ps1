param(
    [string[]]$Mod = @(),
    [string[]]$Skip = @(),
    [string]$GameDir = "",
    [string]$LunarisLibDir = "",
    [string]$OutputDir = "",
    [switch]$AllowReleaseCandidateWithLiveBlockers
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $SuiteRoot

Write-Host "====================================================================" -ForegroundColor Cyan
Write-Host "ERENSHOR MOD SUITE RELEASE GATE" -ForegroundColor Cyan
Write-Host "Clean-source build + deterministic tests + whitelist packaging" -ForegroundColor Cyan
Write-Host "Dirty worktrees are refused. This script performs NO Git writes." -ForegroundColor Yellow
Write-Host "====================================================================" -ForegroundColor Cyan

# Filesystem audit is evidence-only by default. It never deletes or moves anything in release mode.
$global:LASTEXITCODE = 0
& (Join-Path $SuiteRoot "AUDIT_ACTIVE_PLUGINS.ps1") -GameDir $GameDir
if ($LASTEXITCODE -eq 2) {
    throw "Active plugins contain duplicate/missing/suspicious suite DLLs. Resolve or quarantine them before a final release gate."
}
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Active plugin audit failed with exit code $LASTEXITCODE." }

$buildArgs = @{
    BuildOnly = $true
    Clean = $true
    RunTests = $true
    GameDir = $GameDir
    LunarisLibDir = $LunarisLibDir
}
if ($Mod.Count -gt 0) { $buildArgs.Mod = $Mod }
if ($Skip.Count -gt 0) { $buildArgs.Skip = $Skip }

$global:LASTEXITCODE = 0
& (Join-Path $SuiteRoot "BUILD_ALL.ps1") @buildArgs
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Full suite release build/test gate failed with exit code $LASTEXITCODE." }

$packageArgs = @{ GameDir=$GameDir }
if ($Mod.Count -gt 0) { $packageArgs.Mod = $Mod }
if ($OutputDir) { $packageArgs.OutputDir = $OutputDir }
if ($AllowReleaseCandidateWithLiveBlockers) { $packageArgs.AllowReleaseCandidateWithLiveBlockers = $true }

$global:LASTEXITCODE = 0
& (Join-Path $SuiteRoot "PACKAGE_RELEASE.ps1") @packageArgs
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Whitelist packaging failed with exit code $LASTEXITCODE." }

Write-Host "`nRELEASE GATE PASS" -ForegroundColor Green
if ($AllowReleaseCandidateWithLiveBlockers) {
    Write-Host "Artifacts are RELEASE CANDIDATES because live blockers were explicitly allowed." -ForegroundColor Yellow
}
else {
    Write-Host "Final packaging was allowed only for modules with no declared live blockers." -ForegroundColor Green
}
