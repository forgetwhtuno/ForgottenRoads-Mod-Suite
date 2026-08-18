param(
    [string]$GameDir = "",
    [string]$LunarisLibDir = "",
    [switch]$QuarantineConfirmedBackups,
    [switch]$AllowMissing
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $SuiteRoot "Release.Common.ps1")

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
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path (Join-Path $candidate "Erenshor.exe"))) { return (Resolve-Path $candidate).Path }
    }
    throw "Erenshor installation not found. Pass -GameDir explicitly."
}

$manifest = Get-ReleaseSuiteManifest $SuiteRoot
$realGame = Find-Game $GameDir
$pluginsDir = Join-Path $realGame "plugins"
$lunarisDll = Resolve-LunarisIdentityAssemblyPath -GameDir $realGame -LunarisLibDir $LunarisLibDir
$audit = Get-LunarisSuiteIdentityAudit -PluginsDir $pluginsDir -Manifest $manifest -LunarisDll $lunarisDll -AllowMissing:$AllowMissing

Write-Host "==== Forgotten Roads / Lunaris plugin identity audit ====" -ForegroundColor Cyan
Write-Host "Scan root: $($audit.ScanRootLabel) (recursive; config subtrees excluded)"
Write-Host "Identity resolver: " -NoNewline
if ($audit.ResolverHealthy) { Write-Host "PASS - current Lunaris PluginAssemblyUtils.GetGuid" -ForegroundColor Green }
else { Write-Host "REVIEW - unavailable ($($audit.ResolverError))" -ForegroundColor Yellow }

$display = foreach ($r in @($audit.Rows)) {
    [PSCustomObject]@{
        Mod = $r.Id
        PluginId = $r.PluginId
        Discoverable = $r.DiscoverableCount
        Status = $r.Status
    }
}
$display | Format-Table -AutoSize

foreach ($r in @($audit.Rows | Where-Object { $_.Status -ne "PASS" -and $_.Status -ne "MISSING_ALLOWED" })) {
    foreach ($p in @($r.IdentityPaths)) { Write-Host "  $($r.Id) identity: $p" -ForegroundColor Yellow }
    foreach ($p in @($r.FilenameMismatchPaths)) { Write-Host "  $($r.Id) filename/identity mismatch: $p" -ForegroundColor Yellow }
    foreach ($p in @($r.FilenameAmbiguousPaths)) { Write-Host "  $($r.Id) ambiguous candidate: $p" -ForegroundColor Yellow }
}
foreach ($r in @($audit.AmbiguousRecords)) {
    Write-Host "  unreadable/ambiguous managed identity: $($r.RelativePath)" -ForegroundColor Yellow
}

if ($QuarantineConfirmedBackups) {
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $quarantine = Join-Path (Split-Path -Parent $pluginsDir) ("plugins-disabled\ForgottenRoadsBackups-" + $stamp)
    $moved = @(Move-ConfirmedSuiteBackupDlls -Audit $audit -Manifest $manifest -PluginsDir $pluginsDir -QuarantineRoot $quarantine)
    if ($moved.Count -gt 0) {
        Write-Host "`nMoved only positively identified Forgotten Roads backup-style duplicates outside the Lunaris scan root:" -ForegroundColor Yellow
        $moved | Format-Table -AutoSize
        $audit = Get-LunarisSuiteIdentityAudit -PluginsDir $pluginsDir -Manifest $manifest -LunarisDll $lunarisDll -AllowMissing:$AllowMissing
    }
    else {
        Write-Host "`nNo positively identified Forgotten Roads backup-style duplicates were quarantined." -ForegroundColor DarkGray
    }
}

if (-not $audit.Healthy) {
    Write-Host "`nAUDIT RESULT: REVIEW REQUIRED - discoverable Forgotten Roads plugin identity is duplicate, missing, or ambiguous." -ForegroundColor Yellow
    exit 2
}
Write-Host "`nAUDIT RESULT: PASS - exactly one discoverable Lunaris plugin identity per required Forgotten Roads module." -ForegroundColor Green
exit 0
