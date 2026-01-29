<#
.SYNOPSIS
    Runs Pester tests with code coverage for PowerShell library layer.

.DESCRIPTION
    Executes Pester unit tests and generates code coverage metrics for scripts/lib/*.ps1.
    Measures line coverage and outputs a summary report.

.PARAMETER OutputDir
    Directory for coverage reports (default: test/unit/results).

.PARAMETER CoverageThreshold
    Minimum coverage percentage required (default: 0 for baseline).

.PARAMETER CI
    Run in CI mode with stricter settings and exit codes.

.EXAMPLE
    pwsh ./test/unit/Invoke-CoverageTests.ps1

.EXAMPLE
    pwsh ./test/unit/Invoke-CoverageTests.ps1 -CI -CoverageThreshold 70
#>
[CmdletBinding()]
param(
    [string]$OutputDir = "test/unit/results",
    [int]$CoverageThreshold = 0,
    [switch]$CI
)

$ErrorActionPreference = "Stop"

Write-Host "=== PowerShell Library Code Coverage ===" -ForegroundColor Cyan

# Find repository root (walk up from script location until .git or scripts/lib found)
$repoRoot = $PSScriptRoot
while ($repoRoot) {
    if ((Test-Path (Join-Path $repoRoot ".git")) -or
        (Test-Path (Join-Path $repoRoot "scripts/lib"))) {
        break
    }
    $parent = Split-Path $repoRoot -Parent
    if ($parent -eq $repoRoot) {
        Write-Host "❌ Could not find repository root from $PSScriptRoot" -ForegroundColor Red
        exit 1
    }
    $repoRoot = $parent
}

Write-Host "Repository root: $repoRoot" -ForegroundColor Gray

# Resolve output directory relative to repo root
$OutputDir = Join-Path $repoRoot $OutputDir
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Define coverage scope - scripts/lib/*.ps1 only (absolute paths)
$coverageFiles = @(
    (Join-Path $repoRoot "scripts/lib/RunStatus.ps1")
    (Join-Path $repoRoot "scripts/lib/EnvChecks.ps1")
    (Join-Path $repoRoot "scripts/lib/RunManifest.ps1")
    (Join-Path $repoRoot "scripts/lib/EvidenceClassifier.ps1")
    (Join-Path $repoRoot "scripts/lib/SnapshotManager.ps1")
)

Write-Host "`nCoverage Boundary:" -ForegroundColor Yellow
foreach ($file in $coverageFiles) {
    if (Test-Path $file) {
        $relativePath = $file.Replace("$repoRoot\", "").Replace("$repoRoot/", "")
        Write-Host "  ✓ $relativePath" -ForegroundColor Gray
    } else {
        $relativePath = $file.Replace("$repoRoot\", "").Replace("$repoRoot/", "")
        Write-Host "  ✗ $relativePath (not found)" -ForegroundColor Red
    }
}

# Check if Pester is available
try {
    $pesterModule = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if ($null -eq $pesterModule) {
        Write-Host "`nInstalling Pester module..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
        Import-Module Pester -Force
    } elseif ($pesterModule.Version.Major -lt 5) {
        Write-Host "`nPester version $($pesterModule.Version) found. Installing Pester 5..." -ForegroundColor Yellow
        Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
        Import-Module Pester -Force
    } else {
        Write-Host "`nPester version: $($pesterModule.Version)" -ForegroundColor Gray
        Import-Module Pester -Force
    }
} catch {
    Write-Host "Failed to load Pester: $_" -ForegroundColor Red
    exit 1
}

# Configure Pester
$configuration = New-PesterConfiguration

# Test discovery (absolute path to test directory)
$testPath = Join-Path $repoRoot "test/unit"
if (-not (Test-Path $testPath)) {
    Write-Host "❌ Test directory not found: $testPath" -ForegroundColor Red
    exit 1
}
$configuration.Run.Path = $testPath
$configuration.Run.Exit = $false
$configuration.Run.PassThru = $true

# Code coverage configuration
$configuration.CodeCoverage.Enabled = $true
$configuration.CodeCoverage.Path = $coverageFiles
$configuration.CodeCoverage.OutputPath = Join-Path $OutputDir "coverage.xml"
$configuration.CodeCoverage.OutputFormat = "JaCoCo"

# Output configuration
$configuration.Output.Verbosity = if ($CI) { "Detailed" } else { "Normal" }
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputPath = Join-Path $OutputDir "test-results.xml"
$configuration.TestResult.OutputFormat = "NUnitXml"

Write-Host "`nRunning Pester tests with coverage..." -ForegroundColor Yellow

# Run Pester
$result = Invoke-Pester -Configuration $configuration

# Calculate coverage summary
$coverageSummary = @{
    totalFiles = $coverageFiles.Count
    coveredFiles = 0
    totalLines = 0
    coveredLines = 0
    percentCoverage = 0
    fileDetails = @()
}

if ($result.CodeCoverage) {
    # Pester 5.x uses CommandsAnalyzedCount/CommandsExecutedCount
    $coverageSummary.totalLines = $result.CodeCoverage.CommandsAnalyzedCount
    $coverageSummary.coveredLines = $result.CodeCoverage.CommandsExecutedCount

    if ($coverageSummary.totalLines -gt 0) {
        $coverageSummary.percentCoverage = [math]::Round(($coverageSummary.coveredLines / $coverageSummary.totalLines) * 100, 2)
    }

    # Count covered files from FilesAnalyzed
    if ($result.CodeCoverage.FilesAnalyzedCount) {
        $coverageSummary.coveredFiles = $result.CodeCoverage.FilesAnalyzedCount
    }
}

# Display results
Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
Write-Host "Tests Passed:  $($result.PassedCount)" -ForegroundColor Green
Write-Host "Tests Failed:  $($result.FailedCount)" -ForegroundColor $(if ($result.FailedCount -gt 0) { "Red" } else { "Gray" })
Write-Host "Tests Skipped: $($result.SkippedCount)" -ForegroundColor Gray
Write-Host "Total Tests:   $($result.TotalCount)" -ForegroundColor Gray

Write-Host "`n=== Coverage Summary ===" -ForegroundColor Cyan
Write-Host "Coverage Boundary: scripts/lib/*.ps1 (library layer only)" -ForegroundColor Gray
Write-Host "Coverage Metric: Line Coverage" -ForegroundColor Gray
Write-Host ""
Write-Host "Overall Coverage: $($coverageSummary.percentCoverage)%" -ForegroundColor $(
    if ($coverageSummary.percentCoverage -ge 80) { "Green" }
    elseif ($coverageSummary.percentCoverage -ge 60) { "Yellow" }
    else { "Red" }
)
Write-Host "Lines Covered: $($coverageSummary.coveredLines) / $($coverageSummary.totalLines)" -ForegroundColor Gray
Write-Host "Files Covered: $($coverageSummary.coveredFiles) / $($coverageSummary.totalFiles)" -ForegroundColor Gray

# Save coverage summary as JSON
$summaryPath = Join-Path $OutputDir "coverage-summary.json"
$coverageSummary | ConvertTo-Json -Depth 5 | Set-Content -Path $summaryPath -Encoding UTF8
Write-Host "`nCoverage summary saved: $summaryPath" -ForegroundColor Gray

# Exit code logic
$exitCode = 0

if ($result.FailedCount -gt 0) {
    Write-Host "`n❌ Tests failed" -ForegroundColor Red
    $exitCode = 1
}

if ($CoverageThreshold -gt 0 -and $coverageSummary.percentCoverage -lt $CoverageThreshold) {
    Write-Host "❌ Coverage ($($coverageSummary.percentCoverage)%) below threshold ($CoverageThreshold%)" -ForegroundColor Red
    $exitCode = 1
}

if ($exitCode -eq 0) {
    Write-Host "`n✅ All checks passed" -ForegroundColor Green
}

exit $exitCode
