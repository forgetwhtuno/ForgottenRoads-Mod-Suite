Set-StrictMode -Version 2.0

function Get-ReleaseSuiteManifest {
    param([string]$SuiteRoot)
    $path = Join-Path $SuiteRoot "suite.json"
    if (-not (Test-Path $path)) { throw "suite.json not found: $path" }
    return Get-Content $path -Raw | ConvertFrom-Json
}

function Get-ReleaseModDirectory {
    param($Manifest, [string]$ProjectRoot, $Mod)
    $underMods = $true
    if ($Mod.PSObject.Properties.Name -contains "underMods") { $underMods = [bool]$Mod.underMods }
    if ($underMods) { return Join-Path (Join-Path $ProjectRoot $Manifest.modsSubdir) $Mod.localDir }
    return Join-Path $ProjectRoot $Mod.localDir
}

function Get-DeclaredOfflineTestScripts {
    param($Mod)
    $result = @()
    if ($Mod.PSObject.Properties.Name -contains "testScripts" -and $null -ne $Mod.testScripts) {
        foreach ($script in @($Mod.testScripts)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$script)) { $result += [string]$script }
        }
    }
    return $result
}

function Test-ErenshorProcessRunning {
    try { return $null -ne (Get-Process -Name "Erenshor" -ErrorAction SilentlyContinue | Select-Object -First 1) }
    catch { return $false }
}

function New-SuiteBuildStagingGame {
    param(
        [string]$RealGameDir,
        [string]$StagingRoot
    )
    if (Test-Path $StagingRoot) { Remove-Item -LiteralPath $StagingRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $StagingRoot | Out-Null

    $stagingData = Join-Path $StagingRoot "Erenshor_Data"
    New-Item -ItemType Junction -Path $stagingData -Target (Join-Path $RealGameDir "Erenshor_Data") | Out-Null
    Copy-Item (Join-Path $RealGameDir "Erenshor.exe") (Join-Path $StagingRoot "Erenshor.exe") -Force
    $plugins = Join-Path $StagingRoot "plugins"
    New-Item -ItemType Directory -Force -Path $plugins | Out-Null
    return $plugins
}

function Invoke-OfflineTestScript {
    param(
        [string]$ModDir,
        [string]$RelativeScript
    )
    $testPath = Join-Path $ModDir $RelativeScript
    if (-not (Test-Path $testPath)) { throw "Declared deterministic test script missing: $RelativeScript" }
    Push-Location $ModDir
    try {
        $global:LASTEXITCODE = 0
        & $testPath
        $code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        if ($code -ne 0) { throw "deterministic test '$RelativeScript' exited $code" }
    }
    finally { Pop-Location }
}

function Invoke-ModBuildToStaging {
    param(
        [string]$ModDir,
        [string]$StagingGameDir,
        [string]$LunarisLibDir,
        [string]$DllName
    )
    $build = Join-Path $ModDir "BUILD_AND_INSTALL.ps1"
    if (-not (Test-Path $build)) { throw "Build script missing: $build" }
    $stagedDll = Join-Path (Join-Path $StagingGameDir "plugins") $DllName
    if (Test-Path $stagedDll) { Remove-Item $stagedDll -Force }

    Push-Location $ModDir
    try {
        $global:LASTEXITCODE = 0
        # Keep child build output visible without allowing compiler warnings/status lines to
        # become this function's return value (the caller expects only the staged DLL path).
        & $build -GameDir $StagingGameDir -LunarisLibDir $LunarisLibDir *>&1 | Out-Host
        $code = if ($null -eq $LASTEXITCODE) { 0 } else { [int]$LASTEXITCODE }
        if ($code -ne 0) { throw "build script exited $code" }
    }
    finally { Pop-Location }

    if (-not (Test-Path $stagedDll)) { throw "Build reported success but did not produce $DllName" }
    return $stagedDll
}

function Backup-ActiveSuiteDll {
    param(
        [string]$Destination,
        [string]$BackupRoot
    )
    if (-not (Test-Path $Destination)) { return $null }
    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    $backup = Join-Path $BackupRoot ([IO.Path]::GetFileName($Destination))
    Copy-Item -LiteralPath $Destination -Destination $backup -Force
    return $backup
}

function Install-SuiteDllVerified {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$ExpectedSha256
    )
    if (-not (Test-Path $Source)) { throw "Built DLL missing: $Source" }
    $sourceHash = (Get-FileHash $Source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sourceHash -ne $ExpectedSha256.ToLowerInvariant()) { throw "Source hash changed before install: $Source" }

    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $token = [Guid]::NewGuid().ToString("N")
    $temp = Join-Path $parent ("." + [IO.Path]::GetFileName($Destination) + "." + $token + ".local-build-tmp")
    try {
        Copy-Item -LiteralPath $Source -Destination $temp -Force
        if (Test-Path $Destination) {
            $replaceBackup = Join-Path $parent ("." + [IO.Path]::GetFileName($Destination) + "." + $token + ".replace-backup")
            try { [IO.File]::Replace($temp, $Destination, $replaceBackup, $true) }
            finally { if (Test-Path $replaceBackup) { Remove-Item $replaceBackup -Force } }
        }
        else {
            [IO.File]::Move($temp, $Destination)
        }
    }
    finally { if (Test-Path $temp) { Remove-Item $temp -Force } }

    $installedHash = (Get-FileHash $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($installedHash -ne $sourceHash) { throw "Installed hash does not match built hash: $Destination" }
    return $installedHash
}

function Get-SuspiciousSuiteDlls {
    param(
        [string]$PluginsDir,
        $Manifest
    )
    $rows = @()
    $allDlls = @(Get-ChildItem -LiteralPath $PluginsDir -Filter "*.dll" -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($m in @($Manifest.mods)) {
        $expectedName = [string]$m.dll
        $expectedStem = [IO.Path]::GetFileNameWithoutExtension($expectedName)
        $canonical = @($allDlls | Where-Object { $_.Name -ieq $expectedName })
        $lookalikes = @($allDlls | Where-Object {
            $_.Name -ine $expectedName -and
            $_.BaseName -match ("(?i)^" + [regex]::Escape($expectedStem) + '([ _\-\(\)\.\d]|old|backup|bak|copy|previous|disabled)')
        })
        $rows += [PSCustomObject]@{
            Id = [string]$m.id
            Dll = $expectedName
            CanonicalCount = $canonical.Count
            CanonicalPaths = @($canonical | ForEach-Object { $_.FullName })
            SuspiciousPaths = @($lookalikes | ForEach-Object { $_.FullName })
            Healthy = ($canonical.Count -eq 1 -and $lookalikes.Count -eq 0)
        }
    }
    return $rows
}

function Move-ConfirmedBackupDlls {
    param(
        $AuditRows,
        [string]$PluginsDir,
        [string]$QuarantineRoot
    )
    $moved = @()
    foreach ($row in @($AuditRows)) {
        foreach ($path in @($row.SuspiciousPaths)) {
            $name = [IO.Path]::GetFileName($path)
            if ($name -notmatch '(?i)(\(\d+\)|old|backup|bak|copy|previous)') { continue }
            $resolved = (Resolve-Path $path).Path
            if (-not $resolved.StartsWith((Resolve-Path $PluginsDir).Path, [StringComparison]::OrdinalIgnoreCase)) { continue }
            New-Item -ItemType Directory -Force -Path $QuarantineRoot | Out-Null
            $target = Join-Path $QuarantineRoot $name
            if (Test-Path $target) { $target = Join-Path $QuarantineRoot (([IO.Path]::GetFileNameWithoutExtension($name)) + "-" + [Guid]::NewGuid().ToString("N").Substring(0,8) + ".dll") }
            Move-Item -LiteralPath $resolved -Destination $target
            $moved += [PSCustomObject]@{ From=$resolved; To=$target }
        }
    }
    return $moved
}

function Test-ReleaseCandidateFile {
    param(
        [string]$Path,
        [string]$RelativeName
    )
    $name = [IO.Path]::GetFileName($RelativeName)
    $lower = $RelativeName.ToLowerInvariant()

    $rejectNamePatterns = @(
        'ai-handoff', 'chatgpt', 'patchpacket', 'patch-packet', 'patch-backup', '.patch-backups',
        '\blogs?\b', '\.lpcfg$', '\.pdb$', '\.tmp$', '\.bak$', '\.old$', '\.orig$',
        'assembly-csharp\.dll$', 'unityengine.*\.dll$', '^lunaris\.dll$', '^0harmony\.dll$'
    )
    foreach ($pattern in $rejectNamePatterns) {
        if ($lower -match $pattern) { return "rejected filename/path pattern '$pattern'" }
    }
    if ($lower -match '(^|[\\/])(bin|obj|\.git|memory|save|saves)([\\/]|$)') { return "rejected private/intermediate directory" }

    $textExt = @(".md",".txt",".json",".xml",".yml",".yaml",".ini",".cfg",".example")
    if ($textExt -contains ([IO.Path]::GetExtension($Path).ToLowerInvariant())) {
        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
        if ($text -match '(?i)[A-Z]:\\Users\\[^\\\r\n]+') { return "personal absolute Windows path detected" }
        if ($text -match '(?i)/(Users|home)/[^/\r\n]+') { return "personal absolute Unix/macOS path detected" }
        if ($text -match '(?i)(api[_-]?key|secret|token|password)\s*[:=]\s*["'']?[A-Za-z0-9_\-]{12,}') { return "possible secret assignment detected" }
        $emails = [regex]::Matches($text, '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b')
        foreach ($match in $emails) {
            $email = $match.Value.ToLowerInvariant()
            if ($email -ne "314876526+forgetwhtuno@users.noreply.github.com") {
                return "non-public email address detected: $($match.Value)"
            }
        }
    }
    return $null
}

function Invoke-PrivacyScan {
    param(
        [string[]]$Files,
        [string]$BaseDir
    )
    $issues = @()
    foreach ($file in @($Files)) {
        if (-not (Test-Path $file)) { $issues += "missing: $file"; continue }
        $relative = if ($BaseDir -and $file.StartsWith($BaseDir,[StringComparison]::OrdinalIgnoreCase)) {
            $file.Substring($BaseDir.Length).TrimStart('\','/')
        } else { [IO.Path]::GetFileName($file) }
        $reason = Test-ReleaseCandidateFile -Path $file -RelativeName $relative
        if ($reason) { $issues += "$relative -> $reason" }
    }
    return $issues
}
