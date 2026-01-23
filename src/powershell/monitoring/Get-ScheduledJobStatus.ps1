<#
.SYNOPSIS
    Monitors status of SimTreeNav scheduled tasks.

.DESCRIPTION
    Queries Windows Task Scheduler for SimTreeNav-related tasks and reports:
    - Task status (success/failed/running/disabled)
    - Last run time and duration
    - Next scheduled run time
    - Error messages from failed runs

    Outputs JSON with scheduled job status for enterprise portal.

.PARAMETER TaskNameFilter
    Filter for task names (default: "SimTreeNav")

.PARAMETER OutputPath
    Path to save JSON output (default: data/output/scheduled-jobs-{timestamp}.json)

.EXAMPLE
    .\Get-ScheduledJobStatus.ps1

    Checks all SimTreeNav scheduled tasks

.EXAMPLE
    .\Get-ScheduledJobStatus.ps1 -TaskNameFilter "Enterprise Portal"

    Checks only Enterprise Portal tasks

.NOTES
    Requires: Windows Task Scheduler, appropriate permissions
#>

param(
    [string]$TaskNameFilter = "SimTreeNav",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Continue"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Scheduled Job Status Monitor" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Initialize job data structure
$jobData = [PSCustomObject]@{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    hostname = $env:COMPUTERNAME
    jobs = @()
    summary = [PSCustomObject]@{
        totalJobs = 0
        successfulJobs = 0
        failedJobs = 0
        runningJobs = 0
        disabledJobs = 0
        neverRunJobs = 0
    }
}

# Get all scheduled tasks matching filter
Write-Host "Querying Windows Task Scheduler..." -ForegroundColor Cyan
Write-Host "Filter: *$TaskNameFilter*" -ForegroundColor Gray
Write-Host ""

try {
    $tasks = Get-ScheduledTask | Where-Object {
        $_.TaskName -like "*$TaskNameFilter*" -or
        $_.TaskPath -like "*$TaskNameFilter*"
    }

    if ($tasks.Count -eq 0) {
        Write-Host "No scheduled tasks found matching filter: $TaskNameFilter" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Hint: Create scheduled tasks using:" -ForegroundColor Gray
        Write-Host "  .\scripts\Setup-EnterprisePortalScheduledTask.ps1" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "Found $($tasks.Count) scheduled task(s)" -ForegroundColor Green
        Write-Host ""

        foreach ($task in $tasks) {
            $jobData.summary.totalJobs++

            $taskName = $task.TaskName
            $taskPath = $task.TaskPath
            $state = $task.State

            Write-Host "Task: $taskName" -ForegroundColor Cyan
            Write-Host "  Path: $taskPath" -ForegroundColor Gray
            Write-Host "  State: $state" -ForegroundColor $(
                switch ($state) {
                    "Ready" { "Green" }
                    "Running" { "Yellow" }
                    "Disabled" { "Red" }
                    default { "White" }
                }
            )

            # Get task info
            try {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -TaskPath $taskPath

                $lastRunTime = $taskInfo.LastRunTime
                $lastTaskResult = $taskInfo.LastTaskResult
                $nextRunTime = $taskInfo.NextRunTime
                $numberOfMissedRuns = $taskInfo.NumberOfMissedRuns

                # Determine status based on last result
                $status = "unknown"
                if ($state -eq "Disabled") {
                    $status = "disabled"
                    $jobData.summary.disabledJobs++
                } elseif ($state -eq "Running") {
                    $status = "running"
                    $jobData.summary.runningJobs++
                } elseif ($lastRunTime -eq $null -or $lastRunTime -eq [DateTime]::MinValue) {
                    $status = "never_run"
                    $jobData.summary.neverRunJobs++
                } elseif ($lastTaskResult -eq 0) {
                    $status = "success"
                    $jobData.summary.successfulJobs++
                } else {
                    $status = "failed"
                    $jobData.summary.failedJobs++
                }

                # Calculate duration (if available from task history)
                $duration = 0
                try {
                    $events = Get-WinEvent -FilterHashtable @{
                        LogName = 'Microsoft-Windows-TaskScheduler/Operational'
                        ID = 102  # Task completed event
                    } -MaxEvents 1 -ErrorAction SilentlyContinue | Where-Object {
                        $_.Message -like "*$taskName*"
                    }

                    if ($events) {
                        # Parse duration from event (if available)
                        # This is a simplified approach
                        $duration = 0  # Default to 0 if can't determine
                    }
                } catch {
                    # Ignore errors getting event log
                }

                # Format timestamps
                $lastRunStr = if ($lastRunTime -and $lastRunTime -ne [DateTime]::MinValue) {
                    $lastRunTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                } else {
                    $null
                }

                $nextRunStr = if ($nextRunTime -and $nextRunTime -ne [DateTime]::MinValue) {
                    $nextRunTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
                } else {
                    $null
                }

                # Get error message if failed
                $errorMessage = ""
                if ($status -eq "failed") {
                    $errorMessage = "Exit code: 0x$($lastTaskResult.ToString('X8'))"

                    # Try to get more details from event log
                    try {
                        $errorEvents = Get-WinEvent -FilterHashtable @{
                            LogName = 'Microsoft-Windows-TaskScheduler/Operational'
                            ID = 103  # Task failure event
                        } -MaxEvents 1 -ErrorAction SilentlyContinue | Where-Object {
                            $_.Message -like "*$taskName*"
                        }

                        if ($errorEvents) {
                            $errorMessage += " - " + $errorEvents[0].Message
                        }
                    } catch {
                        # Ignore errors
                    }
                }

                Write-Host "  Last Run: $(if ($lastRunStr) { $lastRunStr } else { 'Never' })" -ForegroundColor Gray
                Write-Host "  Next Run: $(if ($nextRunStr) { $nextRunStr } else { 'Not scheduled' })" -ForegroundColor Gray
                Write-Host "  Status: $status" -ForegroundColor $(
                    switch ($status) {
                        "success" { "Green" }
                        "running" { "Yellow" }
                        "failed" { "Red" }
                        "disabled" { "Red" }
                        "never_run" { "Gray" }
                        default { "White" }
                    }
                )

                if ($status -eq "failed") {
                    Write-Host "  Error: $errorMessage" -ForegroundColor Red
                }

                if ($numberOfMissedRuns -gt 0) {
                    Write-Host "  Missed Runs: $numberOfMissedRuns" -ForegroundColor Yellow
                }

                # Create job data
                $jobObj = [PSCustomObject]@{
                    name = $taskName
                    path = $taskPath
                    status = $status
                    lastRun = $lastRunStr
                    nextRun = $nextRunStr
                    duration = $duration
                    result = if ($status -eq "success") { "Success" } elseif ($status -eq "failed") { "Failed" } else { $status }
                    errorMessage = $errorMessage
                    missedRuns = $numberOfMissedRuns
                    state = $state
                }

                $jobData.jobs += $jobObj

            } catch {
                Write-Host "  Warning: Could not get task info: $_" -ForegroundColor Yellow

                # Add minimal job data
                $jobObj = [PSCustomObject]@{
                    name = $taskName
                    path = $taskPath
                    status = "unknown"
                    lastRun = $null
                    nextRun = $null
                    duration = 0
                    result = "Unknown"
                    errorMessage = "Could not retrieve task info"
                    missedRuns = 0
                    state = $state
                }

                $jobData.jobs += $jobObj
            }

            Write-Host ""
        }
    }

} catch {
    Write-Host "ERROR: Failed to query scheduled tasks: $_" -ForegroundColor Red
    Write-Host ""
}

# Output results
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Jobs:       $($jobData.summary.totalJobs)" -ForegroundColor White
Write-Host "Successful:       $($jobData.summary.successfulJobs)" -ForegroundColor Green
Write-Host "Failed:           $($jobData.summary.failedJobs)" -ForegroundColor $(if ($jobData.summary.failedJobs -gt 0) { "Red" } else { "Green" })
Write-Host "Running:          $($jobData.summary.runningJobs)" -ForegroundColor $(if ($jobData.summary.runningJobs -gt 0) { "Yellow" } else { "White" })
Write-Host "Disabled:         $($jobData.summary.disabledJobs)" -ForegroundColor $(if ($jobData.summary.disabledJobs -gt 0) { "Red" } else { "White" })
Write-Host "Never Run:        $($jobData.summary.neverRunJobs)" -ForegroundColor Gray
Write-Host ""

# Save JSON output
if (-not $OutputPath) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $PSScriptRoot "..\..\..\data\output\scheduled-jobs-$timestamp.json"
}

# Ensure output directory exists
$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Convert to JSON and save
$json = $jobData | ConvertTo-Json -Depth 10
$json | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

Write-Host "Scheduled job data saved to:" -ForegroundColor Green
Write-Host "  $OutputPath" -ForegroundColor Cyan
Write-Host ""

return $OutputPath
