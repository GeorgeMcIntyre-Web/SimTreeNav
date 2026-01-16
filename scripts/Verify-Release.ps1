<#
.SYNOPSIS
    Verifies a release package for SimTreeNav.

.DESCRIPTION
    Validates that a release package contains all required files
    and passes integrity checks.

.PARAMETER PackagePath
    Path to the directory containing release artifacts.

.EXAMPLE
    ./scripts/Verify-Release.ps1 -PackagePath ./dist
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackagePath
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SimTreeNav Release Verifier" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$passed = $true

# Find ZIP file
Write-Host "[1/4] Locating release package..." -ForegroundColor Yellow
$zipFiles = Get-ChildItem -Path $PackagePath -Filter "*.zip"
if ($zipFiles.Count -eq 0) {
    Write-Error "No ZIP files found in $PackagePath"
    exit 1
}
$zipFile = $zipFiles[0]
Write-Host "  Found: $($zipFile.Name)" -ForegroundColor Gray
Write-Host ""

# Verify checksum
Write-Host "[2/4] Verifying checksum..." -ForegroundColor Yellow
$checksumFile = Join-Path $PackagePath "checksums.sha256"
if (Test-Path $checksumFile) {
    $expectedHash = (Get-Content $checksumFile -Raw).Split(" ")[0].Trim()
    $actualHash = (Get-FileHash -Path $zipFile.FullName -Algorithm SHA256).Hash
    
    if ($expectedHash -eq $actualHash) {
        Write-Host "  ✓ Checksum verified" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ Checksum mismatch!" -ForegroundColor Red
        Write-Host "    Expected: $expectedHash" -ForegroundColor Gray
        Write-Host "    Actual:   $actualHash" -ForegroundColor Gray
        $passed = $false
    }
}
else {
    Write-Warning "  Checksum file not found"
}
Write-Host ""

# Extract and verify contents
Write-Host "[3/4] Verifying package contents..." -ForegroundColor Yellow
$extractPath = Join-Path $PackagePath "verify-extract"
if (Test-Path $extractPath) {
    Remove-Item $extractPath -Recurse -Force
}
Expand-Archive -Path $zipFile.FullName -DestinationPath $extractPath

# Find the package directory
$packageDir = Get-ChildItem -Path $extractPath -Directory | Select-Object -First 1

$requiredFiles = @(
    "manifest.json",
    "README.md",
    "CHANGELOG.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "src/powershell/main/tree-viewer-launcher.ps1",
    "src/powershell/utilities/CredentialManager.ps1",
    "src/powershell/utilities/PCProfileManager.ps1",
    "src/powershell/database/connect-db.ps1"
)

$missingFiles = @()
foreach ($file in $requiredFiles) {
    $filePath = Join-Path $packageDir.FullName $file
    if (Test-Path $filePath) {
        Write-Host "  ✓ $file" -ForegroundColor Green
    }
    else {
        Write-Host "  ✗ $file (missing)" -ForegroundColor Red
        $missingFiles += $file
        $passed = $false
    }
}

if ($missingFiles.Count -gt 0) {
    Write-Warning "  Missing $($missingFiles.Count) required file(s)"
}
Write-Host ""

# Verify manifest
Write-Host "[4/4] Verifying manifest..." -ForegroundColor Yellow
$manifestPath = Join-Path $packageDir.FullName "manifest.json"
try {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    
    $requiredFields = @("schemaVersion", "appVersion", "appName", "description")
    foreach ($field in $requiredFields) {
        if ($manifest.$field) {
            Write-Host "  ✓ $field`: $($manifest.$field)" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ $field missing" -ForegroundColor Red
            $passed = $false
        }
    }
}
catch {
    Write-Host "  ✗ Invalid manifest.json" -ForegroundColor Red
    $passed = $false
}
Write-Host ""

# Cleanup
Remove-Item $extractPath -Recurse -Force

# Summary
Write-Host "========================================" -ForegroundColor $(if ($passed) { "Green" } else { "Red" })
if ($passed) {
    Write-Host "  Verification Passed!" -ForegroundColor Green
}
else {
    Write-Host "  Verification Failed!" -ForegroundColor Red
    exit 1
}
Write-Host "========================================" -ForegroundColor $(if ($passed) { "Green" } else { "Red" })
