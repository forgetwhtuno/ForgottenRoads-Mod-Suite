# Locates (or clones) every mod repo listed in suite.json as a sibling of this checkout, then
# creates an NTFS junction under mods/<id> pointing at it -- so `mods/` gives one unified folder
# view without duplicating a single source file or introducing git submodule fragility. Editing
# through mods/<id> edits the real sibling repo directly; it's the same files on disk.
#
# Usage: powershell -ExecutionPolicy Bypass -File SETUP_WORKSPACE.ps1 [-Clone]
#   -Clone   Clone any listed repo that isn't found as a sibling yet (uses gh, falls back to git).

param(
    [switch]$Clone
)

$ErrorActionPreference = "Stop"
$SuiteRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Manifest = Get-Content (Join-Path $SuiteRoot "suite.json") -Raw | ConvertFrom-Json
$WorkspaceRoot = (Resolve-Path (Join-Path $SuiteRoot $Manifest.workspaceRoot)).Path
$ModsDir = Join-Path $SuiteRoot "mods"
New-Item -ItemType Directory -Force -Path $ModsDir | Out-Null

Write-Host "Workspace root (sibling repos expected here): $WorkspaceRoot" -ForegroundColor Cyan

$results = @()

foreach ($mod in $Manifest.mods) {
    $siblingPath = Join-Path $WorkspaceRoot $mod.localDir
    $linkPath = Join-Path $ModsDir $mod.id

    if (-not (Test-Path $siblingPath)) {
        if ($Clone) {
            Write-Host "[$($mod.id)] Not found locally, cloning forgetwhtuno/$($mod.repo) into $($mod.localDir)..." -ForegroundColor Yellow
            try {
                & gh repo clone "$($Manifest.owner)/$($mod.repo)" $siblingPath -- -b $mod.branch
                if ($LASTEXITCODE -ne 0) { throw "gh repo clone exit code $LASTEXITCODE" }
            }
            catch {
                Write-Host "[$($mod.id)] FAILED to clone - $($_.Exception.Message)" -ForegroundColor Red
                $results += [PSCustomObject]@{ Mod = $mod.id; Result = "CLONE FAILED" }
                continue
            }
        }
        else {
            Write-Host "[$($mod.id)] MISSING at $siblingPath (pass -Clone to fetch it)" -ForegroundColor Red
            $results += [PSCustomObject]@{ Mod = $mod.id; Result = "MISSING (use -Clone)" }
            continue
        }
    }

    if (Test-Path $linkPath) {
        $existing = Get-Item $linkPath
        if ($existing.LinkType -eq "Junction" -and $existing.Target -contains (Resolve-Path $siblingPath).Path) {
            $results += [PSCustomObject]@{ Mod = $mod.id; Result = "OK (junction already correct)" }
            continue
        }
        Remove-Item $linkPath -Force -Recurse
    }

    New-Item -ItemType Junction -Path $linkPath -Target (Resolve-Path $siblingPath).Path | Out-Null
    $results += [PSCustomObject]@{ Mod = $mod.id; Result = "OK (junction created)" }
}

Write-Host "`n==== Workspace setup summary ====" -ForegroundColor Cyan
$results | Format-Table -AutoSize
Write-Host "Run BUILD_AND_INSTALL_ALL.bat next." -ForegroundColor Cyan
