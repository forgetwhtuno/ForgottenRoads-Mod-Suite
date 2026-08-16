# Shared pure/safety helpers for BUILD_ALL.ps1, INSTALL_ALL.ps1 and deterministic manifest tests.
# No helper here performs git writes, checkout/reset, or source mutation.

function Get-SuiteModDirectory($Manifest, [string]$WorkspaceRoot, $Mod) {
    $modsDir = Join-Path $WorkspaceRoot $Manifest.modsSubdir
    $underMods = $true
    if ($Mod.PSObject.Properties.Name -contains "underMods") { $underMods = [bool]$Mod.underMods }
    if ($underMods) { return Join-Path $modsDir $Mod.localDir }
    return Join-Path $WorkspaceRoot $Mod.localDir
}

function Get-SuiteTestScripts($Mod) {
    $result = @()
    if ($Mod.PSObject.Properties.Name -contains "testScripts" -and $null -ne $Mod.testScripts) {
        foreach ($s in @($Mod.testScripts)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$s)) { $result += [string]$s }
        }
    }
    return $result
}

function Assert-SafeRelativePath([string]$Path, [string]$Label) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Label is empty." }
    if ([IO.Path]::IsPathRooted($Path)) { throw "$Label must be relative: $Path" }
    $segments = $Path -split '[\\/]'
    if ($segments -contains '..') { throw "$Label may not traverse upward: $Path" }
}

function Get-SuiteRepoState([string]$ModDir, [string]$ExpectedBranch, [switch]$AllowDirty) {
    if (-not (Test-Path (Join-Path $ModDir ".git"))) { throw "not a git worktree: $ModDir" }
    # Per-command safe.directory keeps local development builds usable under sandbox/service
    # accounts without mutating global Git configuration or requiring a clean worktree.
    $branch = (& git -c "safe.directory=$ModDir" -c core.excludesFile= -C $ModDir branch --show-current 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) { throw "could not read git branch: $ModDir" }
    if ($branch -ne $ExpectedBranch -and -not $AllowDirty) { throw "branch mismatch: expected '$ExpectedBranch', found '$branch'" }
    $sha = (& git -c "safe.directory=$ModDir" -c core.excludesFile= -C $ModDir rev-parse HEAD 2>$null).Trim()
    if ($LASTEXITCODE -ne 0 -or $sha -notmatch '^[0-9a-fA-F]{40}$') { throw "could not read git HEAD: $ModDir" }
    $statusLines = @(& git -c "safe.directory=$ModDir" -c core.excludesFile= -C $ModDir status --porcelain --untracked-files=normal 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "could not read git status: $ModDir" }
    $dirty = $statusLines.Count -gt 0
    if ($dirty -and -not $AllowDirty) {
        throw "worktree is dirty; review it first or pass -AllowDirty intentionally"
    }
    return [PSCustomObject]@{ Branch = $branch; Sha = $sha.ToLowerInvariant(); Dirty = $dirty }
}

function Get-Sha256([string]$Path) {
    if (-not (Test-Path $Path)) { throw "file not found for hashing: $Path" }
    return (Get-FileHash $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Read-SuiteStageManifest([string]$Path) {
    if (-not (Test-Path $Path)) { throw "staging manifest not found: $Path" }
    $m = Get-Content $Path -Raw | ConvertFrom-Json
    if ($null -eq $m -or $m.schemaVersion -ne 1) { throw "unsupported or invalid staging manifest" }
    if ($null -eq $m.entries) { throw "staging manifest has no entries" }
    return $m
}

function Test-ErenshorRunning {
    try { return $null -ne (Get-Process -Name "Erenshor" -ErrorAction SilentlyContinue | Select-Object -First 1) }
    catch { return $false }
}

function Install-SuiteDllAtomic([string]$Source, [string]$Destination) {
    if (-not (Test-Path $Source)) { throw "staged DLL missing: $Source" }
    $parent = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    # The temporary names do NOT end in .dll so Lunaris's *.dll watcher only observes the final
    # replacement, not the copy-in-progress.
    $token = [Guid]::NewGuid().ToString("N")
    $temp = Join-Path $parent ("." + [IO.Path]::GetFileName($Destination) + "." + $token + ".suite-tmp")
    $backup = Join-Path $parent ("." + [IO.Path]::GetFileName($Destination) + "." + $token + ".suite-backup")
    try {
        Copy-Item $Source $temp -Force
        if (Test-Path $Destination) {
            [IO.File]::Replace($temp, $Destination, $backup, $true)
            if (Test-Path $backup) { Remove-Item $backup -Force }
        }
        else {
            [IO.File]::Move($temp, $Destination)
        }
    }
    finally {
        if (Test-Path $temp) { Remove-Item $temp -Force }
        if (Test-Path $backup) { Remove-Item $backup -Force }
    }
}

function Install-SuiteSetTransactional($Items, [scriptblock]$PostInstallValidation = $null) {
    $itemsArray = @($Items)
    if ($itemsArray.Count -eq 0) { throw "No install items supplied." }

    # Validate the complete set before touching a live DLL.
    foreach ($item in $itemsArray) {
        if ($null -eq $item -or [string]::IsNullOrWhiteSpace([string]$item.Source) -or
            [string]::IsNullOrWhiteSpace([string]$item.Destination)) {
            throw "Invalid install-set entry."
        }
        if (-not (Test-Path $item.Source)) { throw "Staged DLL missing: $($item.Source)" }
        if (-not [string]::IsNullOrWhiteSpace([string]$item.ExpectedSha256)) {
            if ((Get-Sha256 $item.Source) -ne ([string]$item.ExpectedSha256).ToLowerInvariant()) {
                throw "Staged DLL hash mismatch before install: $($item.Source)"
            }
        }
    }

    $rollbackRoot = Join-Path $env:TEMP ("ErenshorSuiteRollback-" + [Guid]::NewGuid().ToString("N"))
    $persistentBackupRoot = Join-Path (Split-Path -Parent $PSScriptRoot) ("local-build-backups\discoverability-preinstall-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Force -Path $rollbackRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $persistentBackupRoot | Out-Null
    $records = @()
    try {
        # Snapshot every destination before the first mutation so a later file-lock/I/O error can
        # roll the entire selected set back instead of leaving a mixed suite version installed.
        for ($i = 0; $i -lt $itemsArray.Count; $i++) {
            $item = $itemsArray[$i]
            $hadPrior = Test-Path $item.Destination
            $backup = Join-Path $rollbackRoot (("{0:D3}-" -f $i) + [IO.Path]::GetFileName($item.Destination))
            if ($hadPrior) {
                Copy-Item $item.Destination $backup -Force
                Copy-Item $item.Destination (Join-Path $persistentBackupRoot ([IO.Path]::GetFileName($item.Destination))) -Force
            }
            $records += [PSCustomObject]@{ Item=$item; HadPrior=$hadPrior; Backup=$backup }
        }

        foreach ($record in $records) {
            Install-SuiteDllAtomic $record.Item.Source $record.Item.Destination
            if (-not [string]::IsNullOrWhiteSpace([string]$record.Item.ExpectedSha256)) {
                if ((Get-Sha256 $record.Item.Destination) -ne ([string]$record.Item.ExpectedSha256).ToLowerInvariant()) {
                    throw "Installed DLL hash mismatch: $($record.Item.Destination)"
                }
            }
        }
        if ($null -ne $PostInstallValidation) { & $PostInstallValidation }
        Write-Host "Persistent pre-install backup: $persistentBackupRoot" -ForegroundColor Cyan
    }
    catch {
        $installError = $_.Exception.Message
        $rollbackErrors = @()
        for ($i = $records.Count - 1; $i -ge 0; $i--) {
            $record = $records[$i]
            try {
                if ($record.HadPrior) {
                    Install-SuiteDllAtomic $record.Backup $record.Item.Destination
                }
                elseif (Test-Path $record.Item.Destination) {
                    Remove-Item $record.Item.Destination -Force
                }
            }
            catch { $rollbackErrors += $_.Exception.Message }
        }
        if ($rollbackErrors.Count -gt 0) {
            throw "Suite install failed: $installError. Rollback also had errors: $($rollbackErrors -join ' | ')"
        }
        throw "Suite install failed and all touched DLLs were rolled back: $installError"
    }
    finally {
        if (Test-Path $rollbackRoot) { Remove-Item $rollbackRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
}
