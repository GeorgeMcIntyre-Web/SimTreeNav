<#
.SYNOPSIS
    Generates demo data and opens the WS2C viewer.
    
.DESCRIPTION
    Creates demo data using New-DemoStory and opens the viewer HTML
    with instructions to load the bundle.
    
.PARAMETER OutDir
    Output directory for demo files (default: ./demo-output)
    
.EXAMPLE
    ./Open-DemoViewer.ps1
#>

param(
    [string]$OutDir = (Join-Path $PSScriptRoot "demo-output")
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WS2C Demo Viewer Setup" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Import functions
. "$PSScriptRoot\New-DemoStory.ps1"

# Generate demo data
Write-Host "Generating demo data..." -ForegroundColor Yellow
New-DemoStory -OutDir $OutDir -Seed 42

Write-Host ""
Write-Host "Demo files created in: $OutDir" -ForegroundColor Green
Write-Host "  - nodes.json" -ForegroundColor Gray
Write-Host "  - timeline.json" -ForegroundColor Gray
Write-Host "  - compliance.json" -ForegroundColor Gray
Write-Host "  - similar.json" -ForegroundColor Gray
Write-Host "  - anomalies.json" -ForegroundColor Gray
Write-Host "  - bundle.json" -ForegroundColor Gray
Write-Host ""

# Copy viewer HTML to output directory
$viewerSource = Join-Path $PSScriptRoot "ws2c-viewer.html"
$viewerDest = Join-Path $OutDir "viewer.html"

if (Test-Path $viewerSource) {
    Copy-Item $viewerSource $viewerDest -Force
    Write-Host "Viewer copied to: $viewerDest" -ForegroundColor Green
}

# Open viewer in browser
Write-Host ""
Write-Host "Opening viewer in browser..." -ForegroundColor Yellow

if (Test-Path $viewerDest) {
    Start-Process $viewerDest
} else {
    Start-Process $viewerSource
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Instructions:" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Click 'Select bundle.json' in the viewer" -ForegroundColor White
Write-Host "2. Navigate to: $OutDir" -ForegroundColor White
Write-Host "3. Select 'bundle.json'" -ForegroundColor White
Write-Host ""
Write-Host "The demo includes:" -ForegroundColor Cyan
Write-Host "  - Compliance failures (naming violations, extras)" -ForegroundColor Gray
Write-Host "  - Similar stations to explore" -ForegroundColor Gray
Write-Host "  - Critical anomalies (mass delete, oscillation)" -ForegroundColor Gray
Write-Host ""
