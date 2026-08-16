# Build/test the selected suite into a private staging game first. Installation is a separate
# final phase and occurs only if EVERY selected mod built and every declared offline test passed.
# Individual mod BUILD_AND_INSTALL.ps1 files remain authoritative for compilation/reference lists.
# No source checkout/reset/commit is performed here.

param(
    [switch]$BuildOnly,
    [switch]$Install = $true,
    [switch]$Clean,
    [string[]]$Mod = @(),
    [string[]]$Skip = @(),
    [bool]$RunTests = $true,
    [string]$GameDir = "",
    [string]$LunarisLibDir = "",
    [switch]$AllowDirty,
    [switch]$AllowGameRunning
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $SuiteRoot "SuiteBuild.Common.ps1")
$SuiteJson = Join-Path $SuiteRoot "suite.json"
$Manifest = Get-Content $SuiteJson -Raw | ConvertFrom-Json
$WorkspaceRoot = (Resolve-Path (Join-Path $SuiteRoot $Manifest.workspaceRoot)).Path
if ($BuildOnly) { $Install = $false }

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

Import-Module (Join-Path $WorkspaceRoot "build\ErenshorLocalBuildSupport.psm1") -Force
$buildEnv = Resolve-ErenshorBuildEnvironment -ProjectRoot $WorkspaceRoot -GameDir $GameDir -LunarisLibDir $LunarisLibDir
$RealGameDir = $buildEnv.GameDir
$RealManaged = $buildEnv.ManagedDir
$RealPlugins = $buildEnv.PluginsDir
$ModsDir = Join-Path $WorkspaceRoot $Manifest.modsSubdir
$LunarisLibDir = $buildEnv.LunarisLibDir

$assemblyCSharp = $buildEnv.AssemblyCSharp
$lunarisDll = $buildEnv.Lunaris
$harmonyDll = $buildEnv.Harmony

$selected = @($Manifest.mods | Where-Object { $_.enabled })
if ($Mod.Count -gt 0) { $selected = @($selected | Where-Object { $Mod -contains $_.id }) }
if ($Skip.Count -gt 0) { $selected = @($selected | Where-Object { $Skip -notcontains $_.id }) }
if ($selected.Count -eq 0) { throw "No enabled mods matched the requested selection." }

if ($RunTests) {
    Write-Host "`n==== Erenshor-Mod-Suite orchestration tests ====" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    & (Join-Path $SuiteRoot "RUN_TESTS.ps1")
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "Erenshor-Mod-Suite orchestration tests failed with exit code $LASTEXITCODE" }
}

Write-Host "Game:    $RealGameDir" -ForegroundColor Cyan
Write-Host "Managed: $RealManaged" -ForegroundColor Cyan
Write-Host "Lunaris: $LunarisLibDir" -ForegroundColor Cyan
Write-Host "Install: $Install (RunTests=$RunTests AllowDirty=$AllowDirty)" -ForegroundColor Cyan

$Staging = Join-Path $env:TEMP "ErenshorSuiteBuildStaging"
$StageManifestPath = Join-Path $Staging "suite-build.json"
if ($Clean -and (Test-Path $Staging)) { Remove-Item $Staging -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Staging | Out-Null
if (Test-Path $StageManifestPath) { Remove-Item $StageManifestPath -Force }

# Always recreate the game-data junction and exe stub so a prior run against another game install
# cannot silently keep stale staging scaffolding.
$StagingData = Join-Path $Staging "Erenshor_Data"
if (Test-Path $StagingData) {
    $item = Get-Item $StagingData -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { Remove-Item $StagingData -Force }
    else { Remove-Item $StagingData -Recurse -Force }
}
New-Item -ItemType Junction -Path $StagingData -Target (Join-Path $RealGameDir "Erenshor_Data") | Out-Null
Copy-Item (Join-Path $RealGameDir "Erenshor.exe") (Join-Path $Staging "Erenshor.exe") -Force
$StagingPlugins = Join-Path $Staging "plugins"
if (Test-Path $StagingPlugins) { Remove-Item $StagingPlugins -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StagingPlugins | Out-Null

$results = @()
$stageEntries = @()

foreach ($m in $selected) {
    $modDir = Get-SuiteModDirectory $Manifest $WorkspaceRoot $m
    $buildScript = Join-Path $modDir "BUILD_AND_INSTALL.ps1"
    $row = [PSCustomObject]@{ Mod=$m.displayName; Source="-"; Build="SKIPPED"; Tests="-"; Installed="-"; Sha256="-" }

    try {
        if (-not (Test-Path $modDir)) { throw "mod dir not found: $modDir; run SETUP_WORKSPACE.ps1" }
        if (-not (Test-Path $buildScript)) { throw "no BUILD_AND_INSTALL.ps1 in $modDir" }
        $repo = Get-SuiteRepoState $modDir $m.branch -AllowDirty:$AllowDirty
        $row.Source = $repo.Branch + "@" + $repo.Sha.Substring(0, 12) + $(if ($repo.Dirty) { " (dirty)" } else { "" })

        Write-Host "`n==== $($m.displayName) ====" -ForegroundColor Cyan
        $stagedDll = Join-Path $StagingPlugins $m.dll
        if (Test-Path $stagedDll) { Remove-Item $stagedDll -Force }

        $global:LASTEXITCODE = 0
        & $buildScript -GameDir $Staging -LunarisLibDir $LunarisLibDir
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "build script exit code $LASTEXITCODE" }
        if (-not (Test-Path $stagedDll)) { throw "build reported success but $($m.dll) was not produced" }
        $row.Build = "OK"

        $declaredTests = @(Get-SuiteTestScripts $m)
        if ($RunTests -and $declaredTests.Count -gt 0) {
            $passed = @()
            foreach ($relative in $declaredTests) {
                Assert-SafeRelativePath $relative "testScripts entry for $($m.id)"
                $testPath = Join-Path $modDir $relative
                if (-not (Test-Path $testPath)) { throw "declared test script missing: $relative" }
                Push-Location $modDir
                try {
                    $global:LASTEXITCODE = 0
                    & $testPath
                    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "test script '$relative' exit code $LASTEXITCODE" }
                }
                finally { Pop-Location }
                $passed += $relative
            }
            $row.Tests = "PASS (" + $passed.Count + " script" + $(if ($passed.Count -eq 1) { "" } else { "s" }) + ")"
        }
        elseif ($RunTests -and $m.testClass -eq "in_game_selftest") {
            $row.Tests = "IN-GAME ONLY: " + $m.inGameSelfTest
        }
        elseif ($RunTests) { $row.Tests = "none declared" }
        else { $row.Tests = "skipped" }

        $hash = Get-Sha256 $stagedDll
        $row.Sha256 = $hash.Substring(0, 16) + "..."
        if ($Install) { $row.Installed = "pending suite pass" } else { $row.Installed = "no (BuildOnly)" }
        $stageEntries += [PSCustomObject]@{
            id=$m.id; displayName=$m.displayName; version=$m.version; dll=$m.dll; branch=$repo.Branch; sourceSha=$repo.Sha;
            dirty=[bool]$repo.Dirty; sha256=$hash; testClass=$m.testClass; testStatus=$(if ($RunTests -and $declaredTests.Count -gt 0) { "PASS" } elseif ($RunTests) { "NONE_OFFLINE" } else { "SKIPPED" }); tests=@($declaredTests);
            liveSelfTest=$(if ($m.PSObject.Properties.Name -contains "inGameSelfTest") { [string]$m.inGameSelfTest } else { $null })
        }
    }
    catch {
        $row.Build = if ($row.Build -eq "OK") { "FAILED AFTER BUILD" } else { "FAILED" }
        $row.Tests = "FAIL: " + $_.Exception.Message
        $candidate = Join-Path $StagingPlugins $m.dll
        if (Test-Path $candidate) { Remove-Item $candidate -Force }
        Write-Host "[$($m.displayName)] FAILED - $($_.Exception.Message)" -ForegroundColor Red
    }
    $results += $row
}

$failed = @($results | Where-Object { $_.Build -like "FAILED*" -or $_.Tests -like "FAIL:*" })
if ($failed.Count -gt 0 -or $stageEntries.Count -ne $selected.Count) {
    Write-Host "`n==== Suite build summary ====" -ForegroundColor Cyan
    $results | Format-Table -AutoSize
    Write-Host "Selected suite did not pass as a complete set. No DLL from this run was installed and no reusable staging manifest was written." -ForegroundColor Yellow
    exit 1
}

$stageManifest = [ordered]@{
    schemaVersion = 1
    builtUtc = [DateTime]::UtcNow.ToString("o")
    suiteJsonSha256 = Get-Sha256 $SuiteJson
    assemblyCSharpSha256 = Get-Sha256 $assemblyCSharp
    lunarisSha256 = Get-Sha256 $lunarisDll
    harmonySha256 = Get-Sha256 $harmonyDll
    selectedIds = @($selected | ForEach-Object { $_.id })
    entries = @($stageEntries)
}
$stageManifest | ConvertTo-Json -Depth 8 | Set-Content $StageManifestPath -Encoding UTF8

if ($Install) {
    if ((Test-ErenshorRunning) -and -not $AllowGameRunning) {
        Write-Host "`nBuild/test passed and staging is reusable, but Erenshor is running. Nothing was installed." -ForegroundColor Yellow
        Write-Host "Close the game and run INSTALL_ALL.ps1, or explicitly pass -AllowGameRunning if intentional hot reload is safe for this test." -ForegroundColor Yellow
        $results | ForEach-Object { $_.Installed = "blocked: game running" }
        $results | Format-Table -AutoSize
        exit 2
    }
    $installItems = @()
    foreach ($m in $selected) {
        $entry = $stageEntries | Where-Object { $_.id -eq $m.id } | Select-Object -First 1
        $source = Join-Path $StagingPlugins $m.dll
        if ((Get-Sha256 $source) -ne $entry.sha256) { throw "staged hash changed before install: $($m.dll)" }
        $installItems += [PSCustomObject]@{
            Id=$m.id; DisplayName=$m.displayName; Source=$source; Destination=(Join-Path $RealPlugins $m.dll); ExpectedSha256=$entry.sha256
        }
    }
    Install-SuiteSetTransactional $installItems
    foreach ($item in $installItems) {
        $row = $results | Where-Object { $_.Mod -eq $item.DisplayName } | Select-Object -First 1
        $row.Installed = "yes"
        Write-Host "[$($item.DisplayName)] installed -> $($item.Destination)" -ForegroundColor Green
    }
}

Write-Host "`n==== Suite build summary ====" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "Staging manifest: $StageManifestPath" -ForegroundColor Cyan
exit 0
