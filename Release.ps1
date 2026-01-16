<#
.SYNOPSIS
    SimTreeNav Release Command - Prints version and builds release artifacts.

.DESCRIPTION
    One-command release utility that:
    1. Displays version information from manifest.json
    2. Runs quality checks (lint, tests)
    3. Builds release package
    4. Generates checksums

    This is the primary release entry point for SimTreeNav.

.PARAMETER SkipTests
    Skip running Pester tests. Not recommended for production releases.

.PARAMETER OutputPath
    Directory to output the release package. Default: ./dist

.PARAMETER Verbose
    Show detailed output during build process.

.EXAMPLE
    ./Release.ps1
    
    Builds a full release with all quality checks.

.EXAMPLE
    ./Release.ps1 -SkipTests
    
    Quick build without running tests.

.EXAMPLE
    ./Release.ps1 -OutputPath ./my-release
    
    Builds release to custom directory.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [switch]$SkipTests,
    
    [Parameter()]
    [string]$OutputPath = "./dist"
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# Banner
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "║   ███████╗██╗███╗   ███╗████████╗██████╗ ███████╗███████╗   ║" -ForegroundColor Cyan
Write-Host "║   ██╔════╝██║████╗ ████║╚══██╔══╝██╔══██╗██╔════╝██╔════╝   ║" -ForegroundColor Cyan
Write-Host "║   ███████╗██║██╔████╔██║   ██║   ██████╔╝█████╗  █████╗     ║" -ForegroundColor Cyan
Write-Host "║   ╚════██║██║██║╚██╔╝██║   ██║   ██╔══██╗██╔══╝  ██╔══╝     ║" -ForegroundColor Cyan
Write-Host "║   ███████║██║██║ ╚═╝ ██║   ██║   ██║  ██║███████╗███████╗   ║" -ForegroundColor Cyan
Write-Host "║   ╚══════╝╚═╝╚═╝     ╚═╝   ╚═╝   ╚═╝  ╚═╝╚══════╝╚══════╝   ║" -ForegroundColor Cyan
Write-Host "║                          NAV                                 ║" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Load and display version information
Write-Host "Loading version information..." -ForegroundColor Yellow
$manifestPath = Join-Path $ScriptRoot "manifest.json"

if (-not (Test-Path $manifestPath)) {
    Write-Error "manifest.json not found!"
    exit 1
}

$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

Write-Host ""
Write-Host "╭────────────────────────────────────────────────────────────────╮" -ForegroundColor White
Write-Host "│                     VERSION INFORMATION                        │" -ForegroundColor White
Write-Host "├────────────────────────────────────────────────────────────────┤" -ForegroundColor White
Write-Host "│  Application:     $($manifest.appName.PadRight(42))│" -ForegroundColor White
Write-Host "│  App Version:     $($manifest.appVersion.PadRight(42))│" -ForegroundColor White
Write-Host "│  Schema Version:  $($manifest.schemaVersion.PadRight(42))│" -ForegroundColor White
Write-Host "│  Release Date:    $($(Get-Date -Format 'yyyy-MM-dd').PadRight(42))│" -ForegroundColor White
Write-Host "╰────────────────────────────────────────────────────────────────╯" -ForegroundColor White
Write-Host ""

# Component versions
Write-Host "Components:" -ForegroundColor Yellow
foreach ($component in $manifest.components.PSObject.Properties) {
    Write-Host "  - $($component.Name): v$($component.Value.version)" -ForegroundColor Gray
}
Write-Host ""

# Dependencies
Write-Host "Runtime Dependencies:" -ForegroundColor Yellow
foreach ($dep in $manifest.dependencies.runtime) {
    Write-Host "  - $dep" -ForegroundColor Gray
}
Write-Host ""

# Check for development dependencies
Write-Host "Checking development dependencies..." -ForegroundColor Yellow
$missingDeps = @()

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    $missingDeps += "PSScriptAnalyzer"
    Write-Host "  ! PSScriptAnalyzer not installed" -ForegroundColor Yellow
}
else {
    Write-Host "  ✓ PSScriptAnalyzer installed" -ForegroundColor Green
}

if (-not (Get-Module -ListAvailable -Name Pester)) {
    $missingDeps += "Pester"
    Write-Host "  ! Pester not installed" -ForegroundColor Yellow
}
else {
    $pesterVersion = (Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1).Version
    Write-Host "  ✓ Pester v$pesterVersion installed" -ForegroundColor Green
}
Write-Host ""

if ($missingDeps.Count -gt 0 -and -not $SkipTests) {
    Write-Host "Installing missing dependencies..." -ForegroundColor Yellow
    foreach ($dep in $missingDeps) {
        try {
            Install-Module -Name $dep -Force -Scope CurrentUser -SkipPublisherCheck
            Write-Host "  ✓ Installed $dep" -ForegroundColor Green
        }
        catch {
            Write-Warning "  Failed to install $dep`: $_"
        }
    }
    Write-Host ""
}

# Build release
Write-Host "Building release package..." -ForegroundColor Yellow
Write-Host ""

$buildScript = Join-Path $ScriptRoot "scripts/Build-Release.ps1"
$buildParams = @{
    OutputPath = $OutputPath
}
if ($SkipTests) {
    $buildParams.SkipTests = $true
}

try {
    & $buildScript @buildParams
    
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                    RELEASE COMPLETE                          ║" -ForegroundColor Green
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "To publish this release:" -ForegroundColor White
    Write-Host "  1. Create a git tag: git tag v$($manifest.appVersion)" -ForegroundColor Gray
    Write-Host "  2. Push the tag: git push origin v$($manifest.appVersion)" -ForegroundColor Gray
    Write-Host "  3. Create GitHub release with artifacts from $OutputPath" -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Red
    Write-Host "║                    RELEASE FAILED                            ║" -ForegroundColor Red
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Red
    Write-Host ""
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
