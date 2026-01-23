<#
.SYNOPSIS
    Release smoke test for SimTreeNav dashboard task.

.DESCRIPTION
    Validates that dashboard-task.ps1 orchestrator:
    - Passes smoke test mode
    - Passes environment checks
    - Produces run-status.json with valid schema
    - Produces expected artifacts (logs, manifests)

    NOTE: Full run test (Test 3) requires actual config file.
    Set -SkipFullRun to skip the full dashboard generation test.

.PARAMETER OutDir
    Output directory for test artifacts.

.PARAMETER MaxRuntimeSeconds
    Maximum acceptable runtime for full dashboard task (default: 120).

.PARAMETER SkipFullRun
    Skip the full dashboard-task run (Test 3). Use when Oracle/config not available.

.PARAMETER OutputReport
    Path to test results JSON file.

.EXAMPLE
    pwsh ./test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out
    pwsh ./test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out -SkipFullRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$OutDir,

    [int]$MaxRuntimeSeconds = 120,

    [switch]$SkipFullRun,

    [string]$OutputReport = "test/integration/results/test-release-smoke.json"
)

$ErrorActionPreference = "Stop"

function Add-Issue {
    param([string]$Message)
    $script:results.issues += $Message
    $script:results.status = "fail"
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

$results = [ordered]@{
    test = "test-release-smoke"
    startedAt = (Get-Date).ToString("s")
    status = "pass"
    metrics = [ordered]@{}
    issues = @()
    samples = @{}
}

Write-Host "=== SimTreeNav Release Smoke Test ===" -ForegroundColor Cyan
Write-Host "Output directory: $OutDir" -ForegroundColor Gray
if ($SkipFullRun) {
    Write-Host "Skipping full run test (Test 3)" -ForegroundColor Yellow
}

# TEST 1: Run dashboard-task.ps1 with -Smoke
Write-Host "`nTest 1: Smoke test mode..." -ForegroundColor Yellow
try {
    $smokeOutput = & ".\scripts\ops\dashboard-task.ps1" -OutDir $OutDir -Smoke 2>&1
    $smokeExitCode = $LASTEXITCODE

    if ($smokeExitCode -ne 0) {
        Add-Issue "Smoke test failed with exit code $smokeExitCode"
        Write-Host "Smoke output: $smokeOutput" -ForegroundColor Gray
    } else {
        Write-Host "PASS: Smoke test passed (exit 0)" -ForegroundColor Green
    }

    $results.metrics.smokeExitCode = $smokeExitCode
} catch {
    Add-Issue "Smoke test execution failed: $_"
}

# TEST 2: Environment checks pass
Write-Host "`nTest 2: Environment checks..." -ForegroundColor Yellow
try {
    . ".\scripts\lib\EnvChecks.ps1"

    $psCheck = Test-PowerShellVersion -MinMajorVersion 7
    if (-not $psCheck.Sufficient) {
        Add-Issue "PowerShell version check failed: $($psCheck.Error)"
    } else {
        Write-Host "  PASS: PowerShell version $($psCheck.Current)" -ForegroundColor Green
    }

    $outCheck = Test-OutDirWritable -OutDir $OutDir
    if (-not $outCheck.Writable) {
        Add-Issue "Output directory not writable: $($outCheck.Error)"
    } else {
        Write-Host "  PASS: Output directory writable" -ForegroundColor Green
    }

    $sqlCheck = Test-SqlPlusAvailable
    if (-not $sqlCheck.Available) {
        Write-Host "  WARN: SQL*Plus not available: $($sqlCheck.Error)" -ForegroundColor Yellow
        Write-Host "  This is expected if Oracle Client is not installed." -ForegroundColor Gray
    } else {
        Write-Host "  PASS: SQL*Plus available (version: $($sqlCheck.Version))" -ForegroundColor Green
    }

    $results.samples.environmentChecks = @{
        psVersion = $psCheck.Current
        psSufficient = $psCheck.Sufficient
        outDirWritable = $outCheck.Writable
        sqlPlusAvailable = $sqlCheck.Available
    }
} catch {
    Add-Issue "Environment checks failed: $_"
}

# TEST 3: Full dashboard-task run (optional, requires config)
if (-not $SkipFullRun) {
    Write-Host "`nTest 3: Full dashboard task run..." -ForegroundColor Yellow
    Write-Host "NOTE: This test requires actual Oracle config and may take time." -ForegroundColor Gray

    $configPath = ".\config\test-config.json"
    if (Test-Path $configPath) {
        try {
            $runStart = Get-Date
            $runOutput = & ".\scripts\ops\dashboard-task.ps1" -OutDir $OutDir -Config $configPath 2>&1
            $runExitCode = $LASTEXITCODE
            $runDuration = ((Get-Date) - $runStart).TotalSeconds

            $results.metrics.runDurationSeconds = [math]::Round($runDuration, 2)
            $results.metrics.runExitCode = $runExitCode

            if ($runExitCode -ne 0) {
                Add-Issue "Dashboard task exited with code $runExitCode"
                Write-Host "Last 10 lines of output:" -ForegroundColor Gray
                $runOutput | Select-Object -Last 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
            } else {
                Write-Host "  PASS: Dashboard task completed (exit 0)" -ForegroundColor Green
            }

            if ($runDuration -gt $MaxRuntimeSeconds) {
                Add-Issue "Run duration $([math]::Round($runDuration,2))s exceeds max $MaxRuntimeSeconds s"
            } else {
                Write-Host "  PASS: Runtime $([math]::Round($runDuration,2))s within limit" -ForegroundColor Green
            }
        } catch {
            Add-Issue "Dashboard task execution failed: $_"
        }
    } else {
        Write-Host "  SKIP: Config file not found at $configPath" -ForegroundColor Yellow
        Write-Host "  Create test-config.json or use -SkipFullRun flag." -ForegroundColor Gray
    }
} else {
    Write-Host "`nTest 3: Full dashboard task run... SKIPPED" -ForegroundColor Yellow
}

# TEST 4: Verify run-status.json exists and is valid
Write-Host "`nTest 4: Validate run-status.json..." -ForegroundColor Yellow

if ($SkipFullRun) {
    Write-Host "  SKIPPED (full run not executed)" -ForegroundColor Gray
} else {
    $statusPath = Join-Path $OutDir "json\run-status.json"

    if (-not (Test-Path $statusPath)) {
        Add-Issue "run-status.json not found at $statusPath"
        Write-Host "  Available files in json/:" -ForegroundColor Gray
        $jsonDir = Join-Path $OutDir "json"
        if (Test-Path $jsonDir) {
            Get-ChildItem $jsonDir | ForEach-Object { Write-Host "    $_" -ForegroundColor Gray }
        }
    } else {
    try {
        $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json

        # Validate required fields
        $requiredFields = @("schemaVersion", "scriptName", "startedAt", "host", "steps", "durations", "status", "exitCode", "completedAt")
        $missingFields = @()
        foreach ($field in $requiredFields) {
            if ($null -eq $status.PSObject.Properties[$field]) {
                $missingFields += $field
            }
        }

        if ($missingFields.Count -gt 0) {
            Add-Issue "run-status.json missing required fields: $($missingFields -join ', ')"
        } else {
            Write-Host "  PASS: All required fields present" -ForegroundColor Green
        }

        # Validate expected steps (only if full run was executed)
        if (-not $SkipFullRun -and $status.status -eq "success") {
            $expectedSteps = @("Initialize", "EnvironmentChecks", "ValidateConfig", "GenerateDashboard")
            $missingSteps = @()
            foreach ($stepName in $expectedSteps) {
                $step = $status.steps | Where-Object { $_.name -eq $stepName }
                if (-not $step) {
                    $missingSteps += $stepName
                }
            }

            if ($missingSteps.Count -gt 0) {
                Add-Issue "run-status.json missing expected steps: $($missingSteps -join ', ')"
            } else {
                Write-Host "  PASS: All expected steps present" -ForegroundColor Green
            }
        } else {
            Write-Host "  INFO: Skipping step validation (full run not executed or failed)" -ForegroundColor Gray
        }

        # Sample run-status data
        $results.samples.runStatusSample = @{
            schemaVersion = $status.schemaVersion
            scriptName = $status.scriptName
            status = $status.status
            exitCode = $status.exitCode
            totalMs = $status.durations.totalMs
            stepCount = $status.steps.Count
            topError = $status.topError
        }

        Write-Host "  Status: $($status.status), Exit: $($status.exitCode), Duration: $($status.durations.totalMs)ms" -ForegroundColor Gray
    } catch {
        Add-Issue "Failed to parse or validate run-status.json: $_"
    }
    }
}

# TEST 5: Verify other expected artifacts
Write-Host "`nTest 5: Verify artifacts..." -ForegroundColor Yellow
$expectedArtifacts = @(
    "logs\dashboard-task.log"
)

foreach ($artifact in $expectedArtifacts) {
    $artifactPath = Join-Path $OutDir $artifact
    if (-not (Test-Path $artifactPath)) {
        Add-Issue "Expected artifact not found: $artifact"
    } else {
        Write-Host "  PASS: Found $artifact" -ForegroundColor Green
    }
}

# Optional: Check for run-manifest.json (may not exist if full run skipped)
$manifestPath = Join-Path $OutDir "json\run-manifest.json"
if (Test-Path $manifestPath) {
    Write-Host "  PASS: Found json\run-manifest.json" -ForegroundColor Green
} else {
    Write-Host "  INFO: json\run-manifest.json not found (expected if full run skipped)" -ForegroundColor Gray
}

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
