<#
.SYNOPSIS
    Runs all WS2C engine Pester tests.
    
.DESCRIPTION
    Executes all Pester test files in the tests directory
    and provides a summary of results.
    
.EXAMPLE
    ./Run-AllTests.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  WS2C Engine Tests" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check for Pester
$pesterModule = Get-Module -ListAvailable -Name Pester | Sort-Object Version -Descending | Select-Object -First 1

if (-not $pesterModule) {
    Write-Host "Installing Pester..." -ForegroundColor Yellow
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
    Import-Module Pester
} else {
    Write-Host "Using Pester v$($pesterModule.Version)" -ForegroundColor Gray
    Import-Module Pester -Force
}

# Run all tests
$testPath = $PSScriptRoot

Write-Host ""
Write-Host "Running tests in: $testPath" -ForegroundColor Cyan
Write-Host ""

$config = New-PesterConfiguration
$config.Run.Path = $testPath
$config.Run.PassThru = $true
$config.Output.Verbosity = 'Detailed'
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = Join-Path $testPath "test-results.xml"

$results = Invoke-Pester -Configuration $config

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total:   $($results.TotalCount)" -ForegroundColor White
Write-Host "  Passed:  $($results.PassedCount)" -ForegroundColor Green
Write-Host "  Failed:  $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { "Red" } else { "Gray" })
Write-Host "  Skipped: $($results.SkippedCount)" -ForegroundColor Gray
Write-Host ""

if ($results.FailedCount -gt 0) {
    Write-Host "FAILED TESTS:" -ForegroundColor Red
    $results.Failed | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Red
        Write-Host "    $($_.ErrorRecord.Exception.Message)" -ForegroundColor DarkRed
    }
    exit 1
} else {
    Write-Host "All tests passed!" -ForegroundColor Green
    exit 0
}
