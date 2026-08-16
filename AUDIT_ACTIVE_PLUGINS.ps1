param(
    [string]$GameDir = "",
    [switch]$QuarantineConfirmedBackups
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $SuiteRoot
Import-Module (Join-Path $ProjectRoot "build\ErenshorLocalBuildSupport.psm1") -Force
. (Join-Path $SuiteRoot "Release.Common.ps1")

$manifest = Get-ReleaseSuiteManifest $SuiteRoot
$envInfo = Resolve-ErenshorBuildEnvironment -ProjectRoot $ProjectRoot -GameDir $GameDir
$rows = @(Get-SuspiciousSuiteDlls -PluginsDir $envInfo.PluginsDir -Manifest $manifest)

Write-Host "==== Active suite DLL audit ====" -ForegroundColor Cyan
Write-Host "Plugins: $($envInfo.PluginsDir)"
$display = foreach ($r in $rows) {
    [PSCustomObject]@{
        Mod = $r.Id
        DLL = $r.Dll
        Canonical = $r.CanonicalCount
        SuspiciousCopies = @($r.SuspiciousPaths).Count
        Status = if ($r.Healthy) { "PASS" } else { "REVIEW" }
    }
}
$display | Format-Table -AutoSize

foreach ($r in $rows | Where-Object { -not $_.Healthy }) {
    foreach ($p in @($r.CanonicalPaths)) { Write-Host "  canonical: $p" -ForegroundColor Yellow }
    foreach ($p in @($r.SuspiciousPaths)) { Write-Host "  suspicious: $p" -ForegroundColor Yellow }
}

if ($QuarantineConfirmedBackups) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $quarantine = Join-Path (Split-Path -Parent $envInfo.PluginsDir) ("plugins-disabled\ErenshorSuiteBackups-" + $stamp)
    $moved = @(Move-ConfirmedBackupDlls -AuditRows $rows -PluginsDir $envInfo.PluginsDir -QuarantineRoot $quarantine)
    if ($moved.Count -gt 0) {
        Write-Host "`nMoved confirmed backup-style DLL names outside active plugins:" -ForegroundColor Yellow
        $moved | Format-Table -AutoSize
        $rows = @(Get-SuspiciousSuiteDlls -PluginsDir $envInfo.PluginsDir -Manifest $manifest)
    }
    else {
        Write-Host "`nNo confirmed backup-style suite DLLs were moved." -ForegroundColor DarkGray
    }
}

$bad = @($rows | Where-Object { -not $_.Healthy })
if ($bad.Count -gt 0) {
    Write-Host "`nAUDIT RESULT: REVIEW REQUIRED - active plugin directory is not clean for every suite DLL." -ForegroundColor Yellow
    exit 2
}
Write-Host "`nAUDIT RESULT: PASS - exactly one canonical active DLL per suite mod and no suspicious backup-style copies were found." -ForegroundColor Green
exit 0
