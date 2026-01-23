<#
.SYNOPSIS
    Launches SimTreeNav Enterprise Portal with real-time monitoring data.

.DESCRIPTION
    Unified launcher that orchestrates the entire enterprise portal workflow:
    1. Gathers server health from all configured databases
    2. Aggregates user activity across servers
    3. Checks scheduled job status
    4. Generates interactive HTML portal
    5. Opens portal in default browser

    Supports auto-refresh mode for continuous monitoring.

.PARAMETER AutoRefresh
    Enable 5-minute auto-refresh loop (keeps portal up to date)

.PARAMETER RefreshInterval
    Auto-refresh interval in minutes (default: 5)

.PARAMETER OutputPath
    Custom output path for portal HTML (default: data/output/enterprise-portal.html)

.PARAMETER AutoLaunch
    Automatically open portal in browser (default: true)

.EXAMPLE
    .\enterprise-portal-launcher.ps1

    Generates portal once and opens in browser

.EXAMPLE
    .\enterprise-portal-launcher.ps1 -AutoRefresh

    Generates portal and auto-refreshes every 5 minutes

.EXAMPLE
    .\enterprise-portal-launcher.ps1 -AutoRefresh -RefreshInterval 15

    Auto-refresh every 15 minutes

.NOTES
    Requires: Oracle Instant Client, configured PC profiles, valid credentials
    All monitoring data is generated fresh on each run.
#>

param(
    [switch]$AutoRefresh,
    [int]$RefreshInterval = 5,
    [string]$OutputPath = "data\output\enterprise-portal.html",
    [switch]$AutoLaunch = $true
)

$ErrorActionPreference = "Continue"

$scriptRoot = $PSScriptRoot

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "                                                                " -ForegroundColor Cyan
Write-Host "          SimTreeNav Enterprise Portal Launcher                 " -ForegroundColor Cyan
Write-Host "                                                                " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Helper function to run portal generation
function Invoke-PortalGeneration {
    param(
        [bool]$OpenBrowser = $true
    )

    $startTime = Get-Date

    # Step 1: Gather server health
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[1/4] Gathering Server Health..." -ForegroundColor Cyan
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    try {
        $serverHealthPath = & "$scriptRoot\src\powershell\monitoring\Get-ServerHealth.ps1"
        if (-not $serverHealthPath) {
            throw "Server health script did not return a file path"
        }
        Write-Host ""
        Write-Host "  [OK] Server health data collected" -ForegroundColor Green
        Write-Host "    Path: $serverHealthPath" -ForegroundColor Gray
    } catch {
        Write-Host ""
        Write-Host "  [X] Failed to gather server health: $_" -ForegroundColor Red
        Write-Host ""
        return $false
    }

    # Step 2: Aggregate user activity
    Write-Host ""
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[2/4] Aggregating User Activity..." -ForegroundColor Cyan
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    try {
        $userActivityPath = & "$scriptRoot\src\powershell\monitoring\Get-UserActivitySummary.ps1"
        if (-not $userActivityPath) {
            throw "User activity script did not return a file path"
        }
        Write-Host ""
        Write-Host "  [OK] User activity data collected" -ForegroundColor Green
        Write-Host "    Path: $userActivityPath" -ForegroundColor Gray
    } catch {
        Write-Host ""
        Write-Host "  [X] Failed to aggregate user activity: $_" -ForegroundColor Red
        Write-Host ""
        return $false
    }

    # Step 3: Check scheduled jobs
    Write-Host ""
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[3/4] Checking Scheduled Jobs..." -ForegroundColor Cyan
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    try {
        $scheduledJobsPath = & "$scriptRoot\src\powershell\monitoring\Get-ScheduledJobStatus.ps1"
        if (-not $scheduledJobsPath) {
            throw "Scheduled jobs script did not return a file path"
        }
        Write-Host ""
        Write-Host "  [OK] Scheduled job data collected" -ForegroundColor Green
        Write-Host "    Path: $scheduledJobsPath" -ForegroundColor Gray
    } catch {
        Write-Host ""
        Write-Host "  [X] Failed to check scheduled jobs: $_" -ForegroundColor Red
        Write-Host ""
        return $false
    }

    # Step 4: Generate enterprise portal HTML
    Write-Host ""
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "[4/4] Generating Enterprise Portal..." -ForegroundColor Cyan
    Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    try {
        $portalPath = & "$scriptRoot\scripts\generate-enterprise-portal.ps1" `
            -ServerHealthPath $serverHealthPath `
            -UserActivityPath $userActivityPath `
            -ScheduledJobsPath $scheduledJobsPath `
            -OutputPath $OutputPath

        if (-not $portalPath) {
            throw "Portal generator did not return a file path"
        }
    } catch {
        Write-Host ""
        Write-Host "  [X] Failed to generate portal: $_" -ForegroundColor Red
        Write-Host ""
        return $false
    }

    $endTime = Get-Date
    $duration = ($endTime - $startTime).TotalSeconds

    # Display success summary
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "                                                                " -ForegroundColor Green
    Write-Host "                 Portal Generated Successfully!                 " -ForegroundColor Green
    Write-Host "                                                                " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Output File: $OutputPath" -ForegroundColor Cyan
    Write-Host "  Duration:    $([math]::Round($duration, 1)) seconds" -ForegroundColor Cyan
    Write-Host ""

    # Load portal data to display summary
    try {
        $serverHealthData = Get-Content $serverHealthPath -Raw | ConvertFrom-Json
        $userActivityData = Get-Content $userActivityPath -Raw | ConvertFrom-Json

        Write-Host "  Portal Summary:" -ForegroundColor Yellow
        Write-Host "    - Servers:   $($serverHealthData.summary.onlineServers)/$($serverHealthData.summary.totalServers) online" -ForegroundColor White
        Write-Host "    - Schemas:   $($serverHealthData.summary.totalSchemas)" -ForegroundColor White
        Write-Host "    - Projects:  $($serverHealthData.summary.totalProjects)" -ForegroundColor White
        Write-Host "    - Users:     $($userActivityData.summary.activeUsers) active" -ForegroundColor White
        $checkoutColor = if ($userActivityData.summary.staleCheckouts -gt 0) { "Yellow" } else { "White" }
        Write-Host ("    - Checkouts: {0} ({1} stale)" -f $userActivityData.summary.totalCheckouts, $userActivityData.summary.staleCheckouts) -ForegroundColor $checkoutColor
        Write-Host ""
    } catch {
        # Ignore summary errors
    }

    # Open in browser
    if ($OpenBrowser -and (Test-Path $OutputPath)) {
        Write-Host "  Opening portal in browser..." -ForegroundColor Yellow
        Start-Process $OutputPath
        Write-Host "  [OK] Portal opened" -ForegroundColor Green
        Write-Host ""
    }

    return $true
}

# Run portal generation
$success = Invoke-PortalGeneration -OpenBrowser $AutoLaunch

if (-not $success) {
    Write-Host "Portal generation failed. Please check the errors above." -ForegroundColor Red
    exit 1
}

# Auto-refresh loop (if enabled)
if ($AutoRefresh) {
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host "                                                                " -ForegroundColor Yellow
    Write-Host "              Auto-Refresh Mode Enabled                         " -ForegroundColor Yellow
    Write-Host "                                                                " -ForegroundColor Yellow
    Write-Host "================================================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Portal will refresh every $RefreshInterval minute(s)" -ForegroundColor Yellow
    Write-Host "  Press Ctrl+C to stop" -ForegroundColor Yellow
    Write-Host ""

    while ($true) {
        $nextRefresh = (Get-Date).AddMinutes($RefreshInterval)
        Write-Host "  Next refresh: $($nextRefresh.ToString('HH:mm:ss'))" -ForegroundColor Gray

        Start-Sleep -Seconds ($RefreshInterval * 60)

        Write-Host ""
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host "  Auto-Refresh at $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
        Write-Host "----------------------------------------------------------------" -ForegroundColor DarkCyan
        Write-Host ""

        $success = Invoke-PortalGeneration -OpenBrowser $false

        if (-not $success) {
            Write-Host ""
            Write-Host "  [!] Refresh failed. Will retry at next interval." -ForegroundColor Yellow
        } else {
            Write-Host ""
            Write-Host "  [OK] Portal refreshed successfully" -ForegroundColor Green
        }

        Write-Host ""
    }
}

Write-Host "Done!" -ForegroundColor Green
Write-Host ""
