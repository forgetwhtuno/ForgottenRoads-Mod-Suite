# Verifies every mod repo listed in suite.json is physically present at its expected location
# inside this single-project workspace, and optionally clones anything missing directly there.
#
# This workspace uses REAL directories, not junctions: mods/<localDir> and (for underMods=false
# entries like the Suite Hub) <workspaceRoot>/<localDir> are expected to be genuine git worktrees
# you can open, edit, and commit in directly. This script does not create any links -- it only
# checks what's there and, if asked, clones what's missing straight into place.
#
# Usage: powershell -ExecutionPolicy Bypass -File SETUP_WORKSPACE.ps1 [-Clone]
#   -Clone   Clone any listed repo that isn't present yet, directly into its final location.

param(
    [switch]$Clone
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Manifest = Get-Content (Join-Path $SuiteRoot "suite.json") -Raw | ConvertFrom-Json
$WorkspaceRoot = (Resolve-Path (Join-Path $SuiteRoot $Manifest.workspaceRoot)).Path
$ModsDir = Join-Path $WorkspaceRoot $Manifest.modsSubdir
New-Item -ItemType Directory -Force -Path $ModsDir | Out-Null

Write-Host "Workspace root: $WorkspaceRoot" -ForegroundColor Cyan
Write-Host "Mods subdir:    $ModsDir" -ForegroundColor Cyan

$results = @()

foreach ($mod in $Manifest.mods) {
    $underMods = $true
    if ($mod.PSObject.Properties.Name -contains "underMods") { $underMods = $mod.underMods }
    $targetPath = if ($underMods) { Join-Path $ModsDir $mod.localDir } else { Join-Path $WorkspaceRoot $mod.localDir }

    if (Test-Path (Join-Path $targetPath ".git")) {
        Push-Location $targetPath
        $branch = git branch --show-current 2>$null
        $sha = git rev-parse --short HEAD 2>$null
        Pop-Location
        $results += [PSCustomObject]@{ Mod = $mod.id; Path = $targetPath; Result = "OK (branch=$branch head=$sha)" }
        continue
    }

    if (Test-Path $targetPath) {
        $results += [PSCustomObject]@{ Mod = $mod.id; Path = $targetPath; Result = "PRESENT BUT NOT A GIT REPO -- check manually" }
        continue
    }

    if ($Clone) {
        Write-Host "[$($mod.id)] Not found, cloning forgetwhtuno/$($mod.repo) into $targetPath..." -ForegroundColor Yellow
        try {
            & gh repo clone "$($Manifest.owner)/$($mod.repo)" $targetPath -- -b $mod.branch
            if ($LASTEXITCODE -ne 0) { throw "gh repo clone exit code $LASTEXITCODE" }
            Push-Location $targetPath
            git config core.longpaths true
            Pop-Location
            $results += [PSCustomObject]@{ Mod = $mod.id; Path = $targetPath; Result = "OK (cloned)" }
        }
        catch {
            $results += [PSCustomObject]@{ Mod = $mod.id; Path = $targetPath; Result = "CLONE FAILED: $($_.Exception.Message)" }
        }
    }
    else {
        $results += [PSCustomObject]@{ Mod = $mod.id; Path = $targetPath; Result = "MISSING (pass -Clone to fetch it)" }
    }
}

Write-Host "`n==== Workspace check summary ====" -ForegroundColor Cyan
$results | Format-Table -AutoSize
