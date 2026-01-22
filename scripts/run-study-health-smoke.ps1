# Smoke test for Robcad Study Health Report

param(
    [string[]]$Input = @("navigation-tree.html"),
    [string]$OutDir = "out"
)

$ErrorActionPreference = "Stop"

$inputPaths = @()
if ($PSBoundParameters.ContainsKey('Input')) {
    $inputPaths = @($PSBoundParameters['Input'])
}

if (-not $inputPaths -and $Input) {
    $inputPaths = @($Input)
}

if (-not $inputPaths -or $inputPaths.Count -eq 0) {
    Write-Error "Input is required. Provide one or more files with -Input."
    exit 1
}

$scriptPath = Join-Path $PSScriptRoot "robcad-study-health.ps1"
if (-not (Test-Path $scriptPath)) {
    Write-Error "Health report script not found: $scriptPath"
    exit 1
}

foreach ($path in $inputPaths) {
    if (-not (Test-Path $path)) {
        Write-Error "Input file not found: $path"
        exit 1
    }
}

& $scriptPath -Input $inputPaths -OutDir $OutDir
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$expected = @(
    "robcad-study-health-report.md",
    "robcad-study-health-issues.csv",
    "robcad-study-health-suspicious.csv"
)

foreach ($file in $expected) {
    $path = Join-Path $OutDir $file
    if (-not (Test-Path $path)) {
        Write-Error "Expected output missing: $path"
        exit 1
    }
}

Write-Host "Study health smoke test passed." -ForegroundColor Green
