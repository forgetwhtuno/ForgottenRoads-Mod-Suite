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

# Reads the version a module actually ships, from source rather than from prose. Both current
# declaration styles are accepted: a `const string PluginVersion/Version = "x.y.z"` referenced by
# the attribute, and a version supplied inline as the second [LunarisPlugin(...)] argument.
# Deliberately NOT parsed here: README/CHANGELOG prose. Matching cosmetic heading text is brittle
# and would fail on wording changes that are not real drift.
function Get-SourceVersion([string]$SourceDir) {
    if (-not (Test-Path $SourceDir)) { return $null }

    # The [LunarisPlugin] declaration is the anchor. Scanning every .cs for the first matching const
    # is not safe: an unrelated or historical `const string Version` elsewhere in src would win purely
    # on enumeration order and silently certify the wrong number. So resolve the declaring file first
    # and only then read the version it actually ships.
    $declaring = @()
    foreach ($file in (Get-ChildItem $SourceDir -Filter "*.cs" -Recurse)) {
        $text = Get-Content $file.FullName -Raw
        if ($text -match '\[LunarisPlugin\(') { $declaring += ,@($file.FullName, $text) }
    }
    foreach ($entry in $declaring) {
        $text = $entry[1]
        # Inline: [LunarisPlugin("id", "x.y.z", ...)]
        $attr = [regex]::Match($text, '\[LunarisPlugin\(\s*"[^"]+"\s*,\s*"(\d+\.\d+\.\d+)"')
        if ($attr.Success) { return $attr.Groups[1].Value }
        # By constant: [LunarisPlugin(PluginGuid, PluginVersion, ...)] with the const in the same file.
        $const = [regex]::Match($text, 'const\s+string\s+(?:PluginVersion|Version)\s*=\s*"(\d+\.\d+\.\d+)"')
        if ($const.Success) { return $const.Groups[1].Value }
    }
    # Last resort only: a plugin-version constant anywhere in src.
    foreach ($file in (Get-ChildItem $SourceDir -Filter "*.cs" -Recurse)) {
        $const = [regex]::Match((Get-Content $file.FullName -Raw), 'const\s+string\s+PluginVersion\s*=\s*"(\d+\.\d+\.\d+)"')
        if ($const.Success) { return $const.Groups[1].Value }
    }
    return $null
}

# An artifact hash is either a real SHA-256 or one of the repo's explicit pending tokens. Anything
# else is unreadable provenance and must fail rather than be trusted.
function Test-ArtifactHashField([string]$Value) {
    if ($null -eq $Value) { return $false }
    if ($Value -match '^[0-9a-fA-F]{64}$') { return $true }
    return ($Value -match '^(PENDING|NOT_RUN|REQUIRES)_')
}
function Test-IsConcreteHash([string]$Value) { return ($Value -match '^[0-9a-fA-F]{64}$') }

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

    # Source is the technical truth. This catches the drift class where a module ships one version
    # while the manifests still advertise another.
    $sourceVersion = Get-SourceVersion (Join-Path $localRoot "src")
    Require ($null -ne $sourceVersion) "$($mod.id) has no discoverable declared plugin version in src"
    if ($sourceVersion) {
        Require ($sourceVersion -eq $mod.version) "$($mod.id) source version $sourceVersion differs from suite.json $($mod.version)"
    }

    # Shipped identity parity: the DLL filename must agree across suite.json, the release manifest,
    # and the whitelist, so a packaged artifact can never be named from stale metadata.
    Require ($releaseEntry.Count -eq 1 -and $releaseEntry[0].dllFilename -eq $mod.dll) "$($mod.id) release-manifest dllFilename differs from suite.json dll"
    Require ($white.Count -eq 1 -and $white[0].dll -eq $mod.dll) "$($mod.id) whitelist dll differs from suite.json dll"

    # Gate separation. SOURCE/TEST, BUILD, INSTALLED HASH and LIVE are distinct; a later gate must
    # never report success while the gate it depends on is still pending. This is what stops a stale
    # DLL hash from continuing to certify source that has since moved.
    if ($releaseEntry.Count -eq 1) {
        $entry = $releaseEntry[0]
        Require (Test-ArtifactHashField $entry.sha256) "$($mod.id) release-manifest sha256 is neither a SHA-256 nor a pending token"
        Require (Test-ArtifactHashField $entry.installedSha256) "$($mod.id) release-manifest installedSha256 is neither a SHA-256 nor a pending token"
        if (-not (Test-IsConcreteHash $entry.sha256)) {
            Require ($entry.compile -notmatch '^PASS') "$($mod.id) claims a compile pass with no recorded build hash"
        }
        if (-not (Test-IsConcreteHash $entry.installedSha256)) {
            Require ($entry.install -notmatch '^PASS') "$($mod.id) claims an install pass with no recorded installed hash"
        }
        if ($entry.liveTestStatus.exactCandidate -match '^PASS') {
            Require (Test-IsConcreteHash $entry.installedSha256) "$($mod.id) claims an exact-candidate live pass with no verified installed artifact"
        }
    }
    if (-not $SkipRemote) {
        & git ls-remote --exit-code --heads "https://github.com/$($manifest.owner)/$($mod.repo).git" $mod.branch *> $null
        Require ($LASTEXITCODE -eq 0) "$($mod.id) canonical remote or branch is unreachable"
    }
}

Require ($release.buildEnvironmentStatus -notmatch 'FAIL|BLOCKED') "release-manifest contains an obsolete environment failure"

# The aggregate cannot claim certification while any module row is still unproven.
$unproven = @($release.mods | Where-Object { $_.liveTestStatus.exactCandidate -notmatch '^PASS' })
if ($unproven.Count -gt 0) {
    Require ($release.liveCertification -notmatch 'PASS|CERTIFIED|COMPLETE|READY') "release-manifest claims live certification while $($unproven.Count) module(s) are not live-proven"
}
if ($failures.Count -gt 0) {
    # Deliberately not Write-Error: this script runs with $ErrorActionPreference = "Stop", so the
    # first Write-Error terminated the run and reported only one mismatch. Every failure must be
    # visible in a single pass.
    Write-Host "FAIL Forgotten Roads collection consistency ($($failures.Count) problem(s))" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  FAIL: $_" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS Forgotten Roads collection consistency ($($manifest.mods.Count) modules)"
