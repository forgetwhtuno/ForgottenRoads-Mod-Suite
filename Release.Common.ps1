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

function Get-LunarisScanRootLabel {
    return "<Erenshor>\plugins"
}

function Get-PluginRootRelativeLabel {
    param([string]$PluginsDir, [string]$Path)
    try {
        $root = [IO.Path]::GetFullPath($PluginsDir).TrimEnd('\','/')
        $full = [IO.Path]::GetFullPath($Path)
        if ($full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            $relative = $full.Substring($root.Length).TrimStart('\','/')
            return (Get-LunarisScanRootLabel) + $(if ($relative) { "\" + $relative } else { "" })
        }
    }
    catch { }
    return (Get-LunarisScanRootLabel) + "\<unresolved>"
}

function Test-LunarisConfigPath {
    param([string]$PluginsDir, [string]$Path)
    try {
        $root = [IO.Path]::GetFullPath($PluginsDir).TrimEnd('\','/')
        $full = [IO.Path]::GetFullPath($Path)
        if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $relative = $full.Substring($root.Length).TrimStart('\','/')
        $segments = @($relative -split '[\\/]')
        for ($i = 0; $i -lt [Math]::Max(0, $segments.Count - 1); $i++) {
            if ($segments[$i] -ieq 'config') { return $true }
        }
    }
    catch { }
    return $false
}

function Resolve-LunarisIdentityAssemblyPath {
    param([string]$GameDir, [string]$LunarisLibDir = "")
    $candidates = @()
    # Identity auditing follows the running installation first. Developer refs are only a fallback
    # when the current installation layout does not expose Lunaris.dll directly.
    if ($GameDir) {
        $candidates += Join-Path $GameDir "Lunaris.dll"
        $candidates += Join-Path (Join-Path $GameDir "plugins") "Lunaris.dll"
    }
    if ($LunarisLibDir) { $candidates += Join-Path $LunarisLibDir "Lunaris.dll" }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    throw "Current Lunaris.dll was not found. Pass -LunarisLibDir pointing at the installed/current Lunaris reference."
}

function New-LunarisIdentityResolver {
    param([string]$LunarisDll)
    try {
        if (-not (Test-Path -LiteralPath $LunarisDll)) { throw "Lunaris.dll missing" }
        $assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path -LiteralPath $LunarisDll).Path)
        $type = $assembly.GetType("Lunaris.PluginAssemblyUtils", $false)
        if ($null -eq $type) {
            try { $type = @($assembly.GetTypes() | Where-Object { $_.Name -eq "PluginAssemblyUtils" } | Select-Object -First 1)[0] } catch { $type = $null }
        }
        if ($null -eq $type) { throw "PluginAssemblyUtils type not found" }
        $flags = [Reflection.BindingFlags]::Static -bor [Reflection.BindingFlags]::Public -bor [Reflection.BindingFlags]::NonPublic
        $method = $type.GetMethod("GetGuid", $flags, $null, [Type[]]@([string]), $null)
        if ($null -eq $method) { throw "PluginAssemblyUtils.GetGuid(string) not found" }
        return [PSCustomObject]@{ Healthy=$true; Method=$method; Error="" }
    }
    catch {
        return [PSCustomObject]@{ Healthy=$false; Method=$null; Error=$_.Exception.GetType().Name }
    }
}

function Get-LunarisPluginIdentityRecord {
    param([string]$PluginsDir, [string]$Path, $Resolver)
    $name = [IO.Path]::GetFileName($Path)
    $record = [ordered]@{
        FullPath = $Path
        RelativePath = Get-PluginRootRelativeLabel -PluginsDir $PluginsDir -Path $Path
        FileName = $name
        Managed = $false
        AssemblyName = ""
        Identity = ""
        IdentityStatus = "unmanaged"
        Error = ""
    }
    try {
        $assemblyName = [Reflection.AssemblyName]::GetAssemblyName($Path)
        $record.Managed = $true
        $record.AssemblyName = [string]$assemblyName.Name
    }
    catch {
        return [PSCustomObject]$record
    }

    if ($null -eq $Resolver -or -not $Resolver.Healthy -or $null -eq $Resolver.Method) {
        $record.IdentityStatus = "ambiguous"
        $record.Error = if ($null -eq $Resolver) { "resolver unavailable" } else { [string]$Resolver.Error }
        return [PSCustomObject]$record
    }

    try {
        $identity = [string]$Resolver.Method.Invoke($null, @($Path))
        if ([string]::IsNullOrWhiteSpace($identity)) { throw "empty plugin identity" }
        $record.Identity = $identity
        $record.IdentityStatus = "exact"
    }
    catch {
        $record.IdentityStatus = "ambiguous"
        $record.Error = $_.Exception.GetType().Name
    }
    return [PSCustomObject]$record
}

function Get-SuiteIdentityRowsFromRecords {
    param($Manifest, $Records, [switch]$AllowMissing, [bool]$ResolverHealthy = $true)
    $rows = @()
    $managedAmbiguous = @($Records | Where-Object { $_.Managed -and $_.IdentityStatus -ne "exact" })
    foreach ($m in @($Manifest.mods)) {
        $expectedName = [string]$m.dll
        $expectedStem = [IO.Path]::GetFileNameWithoutExtension($expectedName)
        $expectedId = if ($m.PSObject.Properties.Name -contains "pluginId") { [string]$m.pluginId } else { "" }
        $identityMatches = @($Records | Where-Object { $_.IdentityStatus -eq "exact" -and $_.Identity -ceq $expectedId })
        $filenameCandidates = @($Records | Where-Object {
            $_.FileName -ieq $expectedName -or $_.FileName -match ("(?i)^" + [regex]::Escape($expectedStem) + '([ _\-\(\)\.\d]|old|backup|bak|copy|previous|disabled).*\.dll$')
        })
        $filenameIdentityMismatch = @($filenameCandidates | Where-Object { $_.IdentityStatus -eq "exact" -and $_.Identity -cne $expectedId })
        $filenameAmbiguous = @($filenameCandidates | Where-Object { $_.Managed -and $_.IdentityStatus -ne "exact" })
        $missingAllowed = $AllowMissing -and $identityMatches.Count -eq 0
        $healthy = $ResolverHealthy -and $managedAmbiguous.Count -eq 0 -and $filenameIdentityMismatch.Count -eq 0 -and $filenameAmbiguous.Count -eq 0 -and
            ($identityMatches.Count -eq 1 -or $missingAllowed)
        $status = if (-not $ResolverHealthy -or $managedAmbiguous.Count -gt 0 -or $filenameAmbiguous.Count -gt 0) { "AMBIGUOUS" }
            elseif ($filenameIdentityMismatch.Count -gt 0) { "IDENTITY_MISMATCH" }
            elseif ($identityMatches.Count -gt 1) { "DUPLICATE" }
            elseif ($identityMatches.Count -eq 0) { if ($AllowMissing) { "MISSING_ALLOWED" } else { "MISSING" } }
            else { "PASS" }
        $rows += [PSCustomObject]@{
            Id = [string]$m.id
            DisplayName = [string]$m.displayName
            Dll = $expectedName
            PluginId = $expectedId
            DiscoverableCount = $identityMatches.Count
            IdentityPaths = @($identityMatches | ForEach-Object { $_.RelativePath })
            IdentityFullPaths = @($identityMatches | ForEach-Object { $_.FullPath })
            FilenameMismatchPaths = @($filenameIdentityMismatch | ForEach-Object { $_.RelativePath })
            FilenameAmbiguousPaths = @($filenameAmbiguous | ForEach-Object { $_.RelativePath })
            Status = $status
            Healthy = $healthy
        }
    }
    return $rows
}

function Get-LunarisSuiteIdentityAudit {
    param(
        [string]$PluginsDir,
        $Manifest,
        [string]$LunarisDll,
        [switch]$AllowMissing
    )
    if (-not (Test-Path -LiteralPath $PluginsDir)) { New-Item -ItemType Directory -Force -Path $PluginsDir | Out-Null }
    $resolver = New-LunarisIdentityResolver -LunarisDll $LunarisDll
    $scanErrors = @()
    $paths = @()
    try {
        $paths = @([IO.Directory]::EnumerateFiles((Resolve-Path -LiteralPath $PluginsDir).Path, "*.dll", [IO.SearchOption]::AllDirectories) |
            Where-Object { -not (Test-LunarisConfigPath -PluginsDir $PluginsDir -Path $_) })
    }
    catch { $scanErrors += $_.Exception.GetType().Name }

    $records = @()
    foreach ($path in $paths) { $records += Get-LunarisPluginIdentityRecord -PluginsDir $PluginsDir -Path $path -Resolver $resolver }
    $rows = @(Get-SuiteIdentityRowsFromRecords -Manifest $Manifest -Records $records -AllowMissing:$AllowMissing -ResolverHealthy:$resolver.Healthy)
    $ambiguous = @($records | Where-Object { $_.Managed -and $_.IdentityStatus -ne "exact" })
    $healthy = $resolver.Healthy -and $scanErrors.Count -eq 0 -and $ambiguous.Count -eq 0 -and @($rows | Where-Object { -not $_.Healthy }).Count -eq 0
    return [PSCustomObject]@{
        ScanRootLabel = Get-LunarisScanRootLabel
        ResolverHealthy = [bool]$resolver.Healthy
        ResolverError = [string]$resolver.Error
        ScanErrors = @($scanErrors)
        Records = @($records)
        AmbiguousRecords = @($ambiguous)
        Rows = @($rows)
        Healthy = $healthy
    }
}

function Move-ConfirmedSuiteBackupDlls {
    param(
        $Audit,
        $Manifest,
        [string]$PluginsDir,
        [string]$QuarantineRoot
    )
    $moved = @()
    if ($null -eq $Audit -or -not $Audit.ResolverHealthy) { return $moved }
    $root = (Resolve-Path -LiteralPath $PluginsDir).Path
    foreach ($m in @($Manifest.mods)) {
        $expectedName = [string]$m.dll
        $expectedId = [string]$m.pluginId
        foreach ($record in @($Audit.Records | Where-Object { $_.IdentityStatus -eq "exact" -and $_.Identity -ceq $expectedId })) {
            if ($record.FileName -ieq $expectedName) { continue }
            if ($record.FileName -notmatch '(?i)(\(\d+\)|old|backup|bak|copy|previous)') { continue }
            $resolved = (Resolve-Path -LiteralPath $record.FullPath).Path
            if (-not $resolved.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { continue }
            New-Item -ItemType Directory -Force -Path $QuarantineRoot | Out-Null
            $targetName = ([IO.Path]::GetFileNameWithoutExtension($record.FileName)) + "-" + $m.id + ".dll"
            $target = Join-Path $QuarantineRoot $targetName
            if (Test-Path -LiteralPath $target) {
                $target = Join-Path $QuarantineRoot (([IO.Path]::GetFileNameWithoutExtension($targetName)) + "-" + [Guid]::NewGuid().ToString("N").Substring(0,8) + ".dll")
            }
            Move-Item -LiteralPath $resolved -Destination $target
            $moved += [PSCustomObject]@{
                Mod = [string]$m.id
                From = [string]$record.RelativePath
                To = "<Erenshor>\plugins-disabled\" + [IO.Path]::GetFileName($target)
            }
        }
    }
    return $moved
}

function Assert-LunarisSuiteIdentityForInstall {
    param($Audit, [string[]]$RequiredIds = @(), [switch]$AllowMissingOthers)
    if ($null -eq $Audit) { throw "Plugin identity audit did not run." }
    if (-not $Audit.ResolverHealthy) { throw "Lunaris plugin identity resolver unavailable; review required." }
    if (@($Audit.ScanErrors).Count -gt 0) { throw "Lunaris plugin scan failed; review required." }
    if (@($Audit.AmbiguousRecords).Count -gt 0) { throw "At least one managed plugin identity was unreadable/ambiguous; review required." }
    foreach ($row in @($Audit.Rows)) {
        if ($row.DiscoverableCount -gt 1) { throw "Duplicate discoverable plugin identity '$($row.PluginId)' for $($row.Id)." }
        if (@($row.FilenameMismatchPaths).Count -gt 0 -or @($row.FilenameAmbiguousPaths).Count -gt 0) {
            throw "Filename/identity ambiguity for $($row.Id); review required."
        }
        if ($RequiredIds -contains [string]$row.Id) {
            if ($row.DiscoverableCount -ne 1) { throw "Required installed plugin identity missing for $($row.Id)." }
        }
        elseif (-not $AllowMissingOthers -and $row.DiscoverableCount -ne 1) {
            throw "Expected installed plugin identity missing for $($row.Id)."
        }
    }
}

function Assert-LunarisSuiteIdentityPreInstall {
    param($Audit, $InstallItems)
    Assert-LunarisSuiteIdentityForInstall -Audit $Audit -AllowMissingOthers
    foreach ($item in @($InstallItems)) {
        $row = @($Audit.Rows | Where-Object { $_.Id -eq [string]$item.Id } | Select-Object -First 1)
        if ($row.Count -ne 1) { throw "No identity-audit manifest row for $($item.Id)." }
        $r = $row[0]
        if ($r.DiscoverableCount -eq 0) { continue }
        if ($r.DiscoverableCount -ne 1) { throw "Duplicate discoverable identity exists before install for $($item.Id)." }
        $existing = [IO.Path]::GetFullPath([string]$r.IdentityFullPaths[0])
        $destination = [IO.Path]::GetFullPath([string]$item.Destination)
        if (-not [string]::Equals($existing, $destination, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Plugin identity '$($r.PluginId)' is already discoverable from a non-canonical path; review/quarantine before installing $($item.Id)."
        }
    }
}

function Test-ReleaseCandidateFile {
    param(
        [string]$Path,
        [string]$RelativeName
    )
    $name = [IO.Path]::GetFileName($RelativeName)
    $lower = $RelativeName.ToLowerInvariant()

    $rejectNamePatterns = @(
        'ai-handoff', 'ai-export', 'assistant-handoff', 'assistant-export', 'patchpacket', 'patch-packet', 'patch-backup', '.patch-backups',
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
