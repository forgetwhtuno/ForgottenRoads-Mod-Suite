param(
    [switch]$SkipRemote
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifest = Get-Content (Join-Path $root "suite.json") -Raw | ConvertFrom-Json
$whitelist = Get-Content (Join-Path $root "release-whitelist.json") -Raw | ConvertFrom-Json
$release = Get-Content (Join-Path $root "release-manifest.json") -Raw | ConvertFrom-Json
$failures = New-Object System.Collections.Generic.List[string]

function Require($condition, $message) {
    if (-not $condition) { $script:failures.Add($message) }
}

Require ($manifest.displayName -eq "Forgotten Roads for Erenshor") "suite.json collection branding is incorrect"
Require ((Get-Content (Join-Path $root "README.md") -Raw).Contains("Forgotten Roads for Erenshor")) "central README is not branded"

$oldRemoteNames = @("DeepSim-erenshor", "Erenshor-PartyTools", "ErenshorContracts", "ErenshorJournal", "ErenshorGuildLife", "Erenshor-Campmaster", "Erenshor-Nemesis", "Erenshor-Crafting-Expanded", "Erenshor-Duel", "Erenshor-PvP", "ErenshorFollow", "ErenshorSuiteHub", "Erenshor-Mod-Suite")
$publicFiles = @("README.md", "docs/SUITE_STATUS.md", "docs/LIVE_TEST_MATRIX.md")
foreach ($file in $publicFiles) {
    $text = Get-Content (Join-Path $root $file) -Raw
    foreach ($oldName in $oldRemoteNames) { Require (-not $text.Contains("https://github.com/forgetwhtuno/$oldName")) "$file contains stale remote URL $oldName" }
    Require ($text -notmatch 'C:[\\/]+Users[\\/]|/Users/|/home/') "$file contains an absolute personal path"
    Require ($text -notmatch 'ChatGPT|AI handoff|AI-generated') "$file contains development-process metadata"
}

foreach ($mod in $manifest.mods) {
    Require ($mod.branch -eq "main") "$($mod.id) active branch is not main"
    $localRoot = if ($mod.underMods) { Join-Path (Split-Path -Parent $root) (Join-Path $manifest.modsSubdir $mod.localDir) } else { Join-Path (Split-Path -Parent $root) $mod.localDir }
    Require (Test-Path (Join-Path $localRoot "README.md")) "$($mod.id) README is missing"
    Require (Test-Path (Join-Path $localRoot "LICENSE")) "$($mod.id) LICENSE is missing"
    $white = @($whitelist.mods | Where-Object { $_.id -eq $mod.id })
    $releaseEntry = @($release.mods | Where-Object { $_.modId -eq $mod.id })
    Require ($white.Count -eq 1 -and $white[0].version -eq $mod.version) "$($mod.id) whitelist version differs from suite.json"
    Require ($releaseEntry.Count -eq 1 -and $releaseEntry[0].version -eq $mod.version) "$($mod.id) release-manifest version differs from suite.json"
    if (-not $SkipRemote) {
        & git ls-remote --exit-code --heads "https://github.com/$($manifest.owner)/$($mod.repo).git" $mod.branch *> $null
        Require ($LASTEXITCODE -eq 0) "$($mod.id) canonical remote or branch is unreachable"
    }
}

Require ($release.buildEnvironmentStatus -notmatch 'FAIL|BLOCKED') "release-manifest contains an obsolete environment failure"
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error "FAIL: $_" }
    exit 1
}

Write-Host "PASS Forgotten Roads collection consistency ($($manifest.mods.Count) modules)"
