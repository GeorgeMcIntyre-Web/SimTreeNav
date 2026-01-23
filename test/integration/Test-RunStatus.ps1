<#
.SYNOPSIS
    Unit tests for RunStatus.ps1 library functions.

.DESCRIPTION
    Tests the RunStatus library in isolation to verify:
    - New-RunStatus creates valid run-status.json
    - Set-RunStatusStep adds and updates steps correctly
    - Complete-RunStatus finalizes with proper fields
    - Duration calculations work correctly
    - Error handling functions as expected

.PARAMETER TempDir
    Temporary directory for test artifacts (default: temp with GUID).

.PARAMETER OutputReport
    Path to test results JSON file.

.EXAMPLE
    pwsh ./test/integration/Test-RunStatus.ps1
#>
[CmdletBinding()]
param(
    [string]$TempDir = "$env:TEMP\test-runstatus-$(New-Guid)",
    [string]$OutputReport = "test/integration/results/test-runstatus.json"
)

$ErrorActionPreference = "Stop"

function Add-Issue {
    param([string]$Message)
    $script:results.issues += $Message
    $script:results.status = "fail"
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

$results = [ordered]@{
    test = "test-runstatus"
    startedAt = (Get-Date).ToString("s")
    status = "pass"
    issues = @()
}

Write-Host "=== RunStatus Library Unit Tests ===" -ForegroundColor Cyan
Write-Host "Temp directory: $TempDir" -ForegroundColor Gray

# Setup
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
. ".\scripts\lib\RunStatus.ps1"

$statusPath = $null

# TEST 1: New-RunStatus creates file
Write-Host "`nTest 1: New-RunStatus creates file..." -ForegroundColor Yellow
try {
    $statusPath = New-RunStatus -OutDir $TempDir -ScriptName "test-script.ps1" -SchemaVersion "1.0.0"
    if (-not (Test-Path $statusPath)) {
        Add-Issue "New-RunStatus did not create file at $statusPath"
    } else {
        Write-Host "PASS: File created at $statusPath" -ForegroundColor Green
    }
} catch {
    Add-Issue "New-RunStatus failed: $_"
}

# TEST 2: New-RunStatus has valid schema
Write-Host "`nTest 2: Validate initial schema..." -ForegroundColor Yellow
try {
    $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
    $requiredFields = @("schemaVersion", "scriptName", "startedAt", "host", "steps", "durations", "status", "exitCode", "topError", "logFile", "completedAt")

    foreach ($field in $requiredFields) {
        if ($null -eq $status.PSObject.Properties[$field]) {
            Add-Issue "Schema missing required field: $field"
        }
    }

    if ($status.schemaVersion -ne "1.0.0") {
        Add-Issue "Schema version mismatch: expected '1.0.0', got '$($status.schemaVersion)'"
    }

    if ($status.scriptName -ne "test-script.ps1") {
        Add-Issue "Script name mismatch: expected 'test-script.ps1', got '$($status.scriptName)'"
    }

    if (-not $status.startedAt) {
        Add-Issue "Missing startedAt timestamp"
    }

    if (-not $status.host.machineName) {
        Add-Issue "Missing host.machineName"
    }

    if ($results.status -eq "pass") {
        Write-Host "PASS: Schema valid" -ForegroundColor Green
    }
} catch {
    Add-Issue "Schema validation failed: $_"
}

# TEST 3: Set-RunStatusStep adds step
Write-Host "`nTest 3: Set-RunStatusStep adds step..." -ForegroundColor Yellow
try {
    Set-RunStatusStep -StatusPath $statusPath -StepName "TestStep1" -Status "running"
    $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
    $step = $status.steps | Where-Object { $_.name -eq "TestStep1" }

    if (-not $step) {
        Add-Issue "Step 'TestStep1' not added"
    } elseif ($step.status -ne "running") {
        Add-Issue "Step status incorrect: expected 'running', got '$($step.status)'"
    } elseif (-not $step.startedAt) {
        Add-Issue "Step missing startedAt timestamp"
    } else {
        Write-Host "PASS: Step added with status 'running'" -ForegroundColor Green
    }
} catch {
    Add-Issue "Set-RunStatusStep (add) failed: $_"
}

# TEST 4: Set-RunStatusStep updates to completed with duration
Write-Host "`nTest 4: Set-RunStatusStep updates to completed..." -ForegroundColor Yellow
try {
    Start-Sleep -Milliseconds 100  # Ensure duration > 0
    Set-RunStatusStep -StatusPath $statusPath -StepName "TestStep1" -Status "completed"
    $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
    $step = $status.steps | Where-Object { $_.name -eq "TestStep1" }

    if ($step.status -ne "completed") {
        Add-Issue "Step status not updated: expected 'completed', got '$($step.status)'"
    }

    if (-not $step.completedAt) {
        Add-Issue "Missing completedAt timestamp"
    }

    if (-not $step.durationMs -or $step.durationMs -le 0) {
        Add-Issue "Duration not calculated or invalid: $($step.durationMs)"
    }

    if (-not $status.durations.testStep1Ms) {
        Add-Issue "Duration not added to durations map"
    }

    if ($results.status -eq "pass") {
        Write-Host "PASS: Step completed with durationMs=$($step.durationMs)" -ForegroundColor Green
    }
} catch {
    Add-Issue "Set-RunStatusStep (update) failed: $_"
}

# TEST 5: Set-RunStatusStep handles errors
Write-Host "`nTest 5: Set-RunStatusStep with error..." -ForegroundColor Yellow
try {
    Set-RunStatusStep -StatusPath $statusPath -StepName "TestStep2" -Status "failed" -Error "Test error message"
    $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
    $step = $status.steps | Where-Object { $_.name -eq "TestStep2" }

    if (-not $step) {
        Add-Issue "Step 'TestStep2' not added"
    } elseif ($step.status -ne "failed") {
        Add-Issue "Step status incorrect: expected 'failed', got '$($step.status)'"
    } elseif ($step.error -ne "Test error message") {
        Add-Issue "Error message not set correctly: expected 'Test error message', got '$($step.error)'"
    } else {
        Write-Host "PASS: Step added with error message" -ForegroundColor Green
    }
} catch {
    Add-Issue "Set-RunStatusStep (error) failed: $_"
}

# TEST 6: Complete-RunStatus finalizes
Write-Host "`nTest 6: Complete-RunStatus finalizes..." -ForegroundColor Yellow
try {
    Complete-RunStatus -StatusPath $statusPath -Status "failed" -ExitCode 1 -TopError "Test top error" -LogFile "test.log"
    $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json

    if ($status.status -ne "failed") {
        Add-Issue "Final status not set: expected 'failed', got '$($status.status)'"
    }

    if ($status.exitCode -ne 1) {
        Add-Issue "Exit code not set: expected 1, got $($status.exitCode)"
    }

    if ($status.topError -ne "Test top error") {
        Add-Issue "Top error not set: expected 'Test top error', got '$($status.topError)'"
    }

    if ($status.logFile -ne "test.log") {
        Add-Issue "Log file not set: expected 'test.log', got '$($status.logFile)'"
    }

    if (-not $status.completedAt) {
        Add-Issue "Missing completedAt timestamp"
    }

    if ($null -eq $status.durations.totalMs -or $status.durations.totalMs -lt 0) {
        Add-Issue "Total duration not calculated or invalid: $($status.durations.totalMs)"
    }

    if ($results.status -eq "pass") {
        Write-Host "PASS: Run status finalized with all fields" -ForegroundColor Green
    }
} catch {
    Add-Issue "Complete-RunStatus failed: $_"
}

# Cleanup
Write-Host "`nCleaning up test directory..." -ForegroundColor Gray
Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

$results.endedAt = (Get-Date).ToString("s")

# Write report
$reportDir = Split-Path $OutputReport
if ($reportDir -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
}
$results | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $OutputReport

# Summary
Write-Host "`n=== Test Summary ===" -ForegroundColor Cyan
Write-Host "Status: $($results.status.ToUpper())" -ForegroundColor $(if ($results.status -eq "pass") { "Green" } else { "Red" })
Write-Host "Report: $OutputReport" -ForegroundColor Gray

if ($results.issues.Count -gt 0) {
    Write-Host "`nIssues found:" -ForegroundColor Red
    foreach ($issue in $results.issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
}

if ($results.status -eq "fail") {
    exit 1
}

Write-Host "`nAll tests passed!" -ForegroundColor Green
exit 0
