$ErrorActionPreference = "Stop"
$TestRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SuiteRoot = Split-Path -Parent $TestRoot
. (Join-Path $SuiteRoot "SuiteBuild.Common.ps1")
$manifestPath = Join-Path $SuiteRoot "suite.json"
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
$workspace = (Resolve-Path (Join-Path $SuiteRoot $manifest.workspaceRoot)).Path

$assertions = 0
function Assert-True([bool]$value, [string]$label) {
    if (-not $value) { throw "ASSERT FAILED: $label" }
    $script:assertions++
}
function Assert-Equal($expected, $actual, [string]$label) {
    if ($expected -ne $actual) { throw "ASSERT FAILED: $label expected='$expected' actual='$actual'" }
    $script:assertions++
}

Assert-True ($manifest.owner -eq "forgetwhtuno") "public owner remains forgetwhtuno"
Assert-True ($manifest.mods.Count -gt 0) "manifest contains modules"
$ids = @{}
$dlls = @{}
foreach ($m in $manifest.mods) {
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$m.id)) "module id present"
    Assert-True (-not $ids.ContainsKey([string]$m.id)) "module ids unique: $($m.id)"
    $ids[[string]$m.id] = $true
    Assert-True (-not $dlls.ContainsKey([string]$m.dll)) "DLL names unique: $($m.dll)"
    $dlls[[string]$m.dll] = $true
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$m.branch)) "branch declared: $($m.id)"
    Assert-True ($m.PSObject.Properties.Name -contains "testClass") "test class declared: $($m.id)"
    Assert-True ($m.PSObject.Properties.Name -contains "testScripts") "test scripts declared: $($m.id)"
    Assert-True ($m.PSObject.Properties.Name -contains "version") "version declared: $($m.id)"
    Assert-True ([string]$m.version -match '^\d+\.\d+\.\d+([-.+][0-9A-Za-z.-]+)?$') "version format: $($m.id)"

    $modDir = Get-SuiteModDirectory $manifest $workspace $m
    foreach ($relative in @(Get-SuiteTestScripts $m)) {
        Assert-SafeRelativePath $relative "testScripts entry for $($m.id)"
        Assert-True (Test-Path (Join-Path $modDir $relative)) "declared test exists: $($m.id)/$relative"
    }
    if ($m.testClass -eq "in_game_selftest") {
        Assert-True (-not [string]::IsNullOrWhiteSpace([string]$m.inGameSelfTest)) "in-game selftest command declared: $($m.id)"
    }
}

# Build-manifest parser rejects unsupported schema and accepts the current schema without touching
# a live game or staging directory.
$temp = Join-Path $env:TEMP ("ErenshorSuiteBuildManifestTest_" + [Guid]::NewGuid().ToString("N") + ".json")
try {
    @{schemaVersion=1; entries=@(@{id="SuiteHub";dll="ErenshorSuiteHub.dll"})} | ConvertTo-Json -Depth 4 | Set-Content $temp -Encoding UTF8
    $parsed = Read-SuiteStageManifest $temp
    Assert-Equal 1 $parsed.schemaVersion "stage manifest schema parses"
    Assert-Equal "SuiteHub" $parsed.entries[0].id "stage manifest entry parses"

    @{schemaVersion=99; entries=@()} | ConvertTo-Json | Set-Content $temp -Encoding UTF8
    $rejected = $false
    try { Read-SuiteStageManifest $temp | Out-Null } catch { $rejected = $true }
    Assert-True $rejected "unsupported stage manifest rejected"
}
finally { if (Test-Path $temp) { Remove-Item $temp -Force } }



# A failure on a later destination must roll back earlier DLL replacements. This exercises the
# suite-set transaction without touching Erenshor.
$txnRoot = Join-Path $env:TEMP ("ErenshorSuiteInstallTxnTest_" + [Guid]::NewGuid().ToString("N"))
try {
    New-Item -ItemType Directory -Force -Path $txnRoot | Out-Null
    $source1 = Join-Path $txnRoot "source1.dll"
    $source2 = Join-Path $txnRoot "source2.dll"
    $dest1 = Join-Path $txnRoot "live1.dll"
    Set-Content $source1 "new-one" -Encoding ASCII
    Set-Content $source2 "new-two" -Encoding ASCII
    Set-Content $dest1 "old-one" -Encoding ASCII

    # A file where the second destination's parent directory should be forces an I/O failure only
    # after the first destination has already been replaced.
    $blockedParent = Join-Path $txnRoot "blocked-parent"
    Set-Content $blockedParent "not-a-directory" -Encoding ASCII
    $dest2 = Join-Path $blockedParent "live2.dll"
    $items = @(
        [PSCustomObject]@{Source=$source1;Destination=$dest1;ExpectedSha256=(Get-Sha256 $source1)},
        [PSCustomObject]@{Source=$source2;Destination=$dest2;ExpectedSha256=(Get-Sha256 $source2)}
    )
    $failedTxn = $false
    try { Install-SuiteSetTransactional $items } catch { $failedTxn = $true }
    Assert-True $failedTxn "transaction reports later install failure"
    Assert-Equal "old-one" ((Get-Content $dest1 -Raw).Trim()) "earlier destination rolled back"
}
finally { if (Test-Path $txnRoot) { Remove-Item $txnRoot -Recurse -Force } }


# Release whitelist must cover every suite module exactly once and may only name documentation
# artifacts. Final DLLs come from the staged build manifest, never from a recursively copied tree.
$releaseWhitelistPath = Join-Path $SuiteRoot "release-whitelist.json"
Assert-True (Test-Path $releaseWhitelistPath) "release whitelist exists"
$releaseWhitelist = Get-Content $releaseWhitelistPath -Raw | ConvertFrom-Json
Assert-Equal 1 $releaseWhitelist.schemaVersion "release whitelist schema"
Assert-Equal $manifest.mods.Count $releaseWhitelist.mods.Count "release whitelist covers all suite modules"
$releaseIds = @{}
foreach ($entry in @($releaseWhitelist.mods)) {
    Assert-True (-not $releaseIds.ContainsKey([string]$entry.id)) "release whitelist ids unique: $($entry.id)"
    $releaseIds[[string]$entry.id] = $true
    $sourceMod = $manifest.mods | Where-Object { $_.id -eq $entry.id } | Select-Object -First 1
    Assert-True ($null -ne $sourceMod) "release whitelist id is in suite manifest: $($entry.id)"
    Assert-Equal ([string]$sourceMod.dll) ([string]$entry.dll) "release DLL matches manifest: $($entry.id)"
    Assert-Equal ([string]$sourceMod.version) ([string]$entry.version) "release version matches manifest: $($entry.id)"
    foreach ($name in @($entry.requiredFiles) + @($entry.optionalFiles)) {
        Assert-SafeRelativePath ([string]$name) "release file entry for $($entry.id)"
        Assert-True ([string]$name -notmatch '(?i)(Lunaris|0Harmony|Assembly-CSharp|UnityEngine).*\\.dll$') "game/framework DLL excluded: $($entry.id)/$name"
        Assert-True ([IO.Path]::GetExtension([string]$name) -ne ".pdb") "PDB excluded: $($entry.id)/$name"
    }
}

$projectRoot = Split-Path -Parent $SuiteRoot
Assert-True (Test-Path (Join-Path $projectRoot "build\ErenshorLocalBuildSupport.psm1")) "root local build support module exists"
Assert-True (Test-Path (Join-Path $projectRoot "BUILD_TEST_INSTALL_CURRENT_LOCAL_SUITE.ps1")) "root local dirty build wrapper exists"
Assert-True (Test-Path (Join-Path $SuiteRoot "PACKAGE_RELEASE.ps1")) "release packager exists"
Assert-True (Test-Path (Join-Path $SuiteRoot "RELEASE_GATE.ps1")) "release gate exists"

Write-Host "PASS Erenshor-Mod-Suite manifest/build-policy tests - $assertions assertions" -ForegroundColor Green
