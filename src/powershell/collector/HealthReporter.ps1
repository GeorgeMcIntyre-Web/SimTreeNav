# HealthReporter.ps1
# Health reporting and status monitoring for Collector Agent
#
# Features:
# - JSON-based health reports
# - Bundle statistics tracking
# - Error rate monitoring
# - Resource usage tracking
# - Configurable thresholds

<#
.SYNOPSIS
    Provides health reporting capabilities for the Collector Agent.

.DESCRIPTION
    This module provides:
    - Real-time health status reporting
    - Historical statistics tracking
    - Configurable health thresholds
    - JSON export for monitoring systems

.EXAMPLE
    Initialize-HealthReporter -ReportPath "C:\collector\health"
    Update-HealthMetrics -BundleCreated $true -Duration 45
    $report = Get-HealthReport
#>

# Module-level state
$script:HealthState = @{
    Initialized = $false
    ReportPath = $null
    StartTime = $null
    Metrics = @{
        bundlesCreated = 0
        bundlesFailed = 0
        totalBundleSize = 0
        lastBundleTime = $null
        lastBundleDuration = 0
        snapshotsCreated = 0
        snapshotsFailed = 0
        publishSuccesses = 0
        publishFailures = 0
        errors = @()
        warnings = @()
    }
    Thresholds = @{
        maxErrorRate = 0.1           # 10% error rate
        maxBundleDurationSeconds = 300  # 5 minutes
        maxBundleSizeMB = 100        # 100MB per bundle
        minDiskSpaceMB = 500         # 500MB minimum disk space
        maxConsecutiveFailures = 3   # Max failures before unhealthy
    }
    ConsecutiveFailures = 0
    Status = "Unknown"
}

# Initialize health reporter
function Initialize-HealthReporter {
    <#
    .SYNOPSIS
        Initializes the health reporter with configuration.
    .PARAMETER ReportPath
        Directory where health reports will be stored
    .PARAMETER Thresholds
        Optional hashtable of custom threshold values
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ReportPath,

        [hashtable]$Thresholds = @{}
    )

    # Create report directory if it doesn't exist
    if (-not (Test-Path $ReportPath)) {
        New-Item -ItemType Directory -Path $ReportPath -Force | Out-Null
    }

    # Merge custom thresholds
    foreach ($key in $Thresholds.Keys) {
        if ($script:HealthState.Thresholds.ContainsKey($key)) {
            $script:HealthState.Thresholds[$key] = $Thresholds[$key]
        }
    }

    $script:HealthState.Initialized = $true
    $script:HealthState.ReportPath = $ReportPath
    $script:HealthState.StartTime = Get-Date
    $script:HealthState.Status = "Healthy"
    $script:HealthState.ConsecutiveFailures = 0

    # Reset metrics
    $script:HealthState.Metrics = @{
        bundlesCreated = 0
        bundlesFailed = 0
        totalBundleSize = 0
        lastBundleTime = $null
        lastBundleDuration = 0
        snapshotsCreated = 0
        snapshotsFailed = 0
        publishSuccesses = 0
        publishFailures = 0
        errors = @()
        warnings = @()
    }

    Write-HealthReport

    return $true
}

# Update metrics for bundle operations
function Update-BundleMetrics {
    <#
    .SYNOPSIS
        Updates health metrics after a bundle operation.
    .PARAMETER Success
        Whether the bundle operation succeeded
    .PARAMETER Duration
        Duration of the operation in seconds
    .PARAMETER SizeBytes
        Size of the bundle in bytes (if successful)
    .PARAMETER ErrorMessage
        Error message if operation failed
    #>
    param(
        [bool]$Success,
        [double]$Duration = 0,
        [long]$SizeBytes = 0,
        [string]$ErrorMessage = $null
    )

    if (-not $script:HealthState.Initialized) {
        Write-Warning "Health reporter not initialized"
        return
    }

    if ($Success) {
        $script:HealthState.Metrics.bundlesCreated++
        $script:HealthState.Metrics.totalBundleSize += $SizeBytes
        $script:HealthState.Metrics.lastBundleTime = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        $script:HealthState.Metrics.lastBundleDuration = $Duration
        $script:HealthState.ConsecutiveFailures = 0
    }
    else {
        $script:HealthState.Metrics.bundlesFailed++
        $script:HealthState.ConsecutiveFailures++

        if ($ErrorMessage) {
            $script:HealthState.Metrics.errors += @{
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                operation = "bundle"
                message = $ErrorMessage
            }

            # Keep only last 50 errors
            if ($script:HealthState.Metrics.errors.Count -gt 50) {
                $script:HealthState.Metrics.errors = $script:HealthState.Metrics.errors | Select-Object -Last 50
            }
        }
    }

    # Update overall status
    Update-HealthStatus

    # Write updated report
    Write-HealthReport
}

# Update metrics for snapshot operations
function Update-SnapshotMetrics {
    <#
    .SYNOPSIS
        Updates health metrics after a snapshot operation.
    #>
    param(
        [bool]$Success,
        [string]$ErrorMessage = $null
    )

    if (-not $script:HealthState.Initialized) {
        return
    }

    if ($Success) {
        $script:HealthState.Metrics.snapshotsCreated++
    }
    else {
        $script:HealthState.Metrics.snapshotsFailed++

        if ($ErrorMessage) {
            $script:HealthState.Metrics.errors += @{
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                operation = "snapshot"
                message = $ErrorMessage
            }
        }
    }

    Update-HealthStatus
    Write-HealthReport
}

# Update metrics for publish operations
function Update-PublishMetrics {
    <#
    .SYNOPSIS
        Updates health metrics after a publish operation.
    #>
    param(
        [bool]$Success,
        [string]$Target,
        [string]$ErrorMessage = $null
    )

    if (-not $script:HealthState.Initialized) {
        return
    }

    if ($Success) {
        $script:HealthState.Metrics.publishSuccesses++
        $script:HealthState.ConsecutiveFailures = 0
    }
    else {
        $script:HealthState.Metrics.publishFailures++
        $script:HealthState.ConsecutiveFailures++

        if ($ErrorMessage) {
            $script:HealthState.Metrics.errors += @{
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                operation = "publish"
                target = $Target
                message = $ErrorMessage
            }
        }
    }

    Update-HealthStatus
    Write-HealthReport
}

# Add a warning
function Add-HealthWarning {
    <#
    .SYNOPSIS
        Adds a warning to the health report.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,

        [string]$Component = "general"
    )

    if (-not $script:HealthState.Initialized) {
        return
    }

    $script:HealthState.Metrics.warnings += @{
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        component = $Component
        message = $Message
    }

    # Keep only last 50 warnings
    if ($script:HealthState.Metrics.warnings.Count -gt 50) {
        $script:HealthState.Metrics.warnings = $script:HealthState.Metrics.warnings | Select-Object -Last 50
    }

    Write-HealthReport
}

# Calculate and update overall health status
function Update-HealthStatus {
    <#
    .SYNOPSIS
        Calculates overall health status based on metrics and thresholds.
    #>
    $status = "Healthy"
    $issues = @()

    # Check error rate
    $totalOps = $script:HealthState.Metrics.bundlesCreated + $script:HealthState.Metrics.bundlesFailed
    if ($totalOps -gt 0) {
        $errorRate = $script:HealthState.Metrics.bundlesFailed / $totalOps
        if ($errorRate -gt $script:HealthState.Thresholds.maxErrorRate) {
            $status = "Degraded"
            $issues += "Error rate ($([math]::Round($errorRate * 100, 1))%) exceeds threshold"
        }
    }

    # Check consecutive failures
    if ($script:HealthState.ConsecutiveFailures -ge $script:HealthState.Thresholds.maxConsecutiveFailures) {
        $status = "Unhealthy"
        $issues += "Consecutive failures ($($script:HealthState.ConsecutiveFailures)) exceed threshold"
    }

    # Check disk space
    $reportDrive = (Split-Path $script:HealthState.ReportPath -Qualifier) + "\"
    if (Test-Path $reportDrive) {
        try {
            $drive = Get-PSDrive -Name ($reportDrive.TrimEnd(':\'))
            $freeSpaceMB = [math]::Round($drive.Free / 1MB, 2)
            if ($freeSpaceMB -lt $script:HealthState.Thresholds.minDiskSpaceMB) {
                if ($status -ne "Unhealthy") { $status = "Degraded" }
                $issues += "Low disk space (${freeSpaceMB}MB free)"
            }
        }
        catch {
            # Ignore disk check errors
        }
    }

    $script:HealthState.Status = $status
    $script:HealthState.StatusIssues = $issues
}

# Generate health report
function Get-HealthReport {
    <#
    .SYNOPSIS
        Generates a comprehensive health report.
    #>
    if (-not $script:HealthState.Initialized) {
        return @{
            status = "Not Initialized"
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    }

    $uptime = if ($script:HealthState.StartTime) {
        (Get-Date) - $script:HealthState.StartTime
    }
    else {
        [TimeSpan]::Zero
    }

    $totalBundles = $script:HealthState.Metrics.bundlesCreated + $script:HealthState.Metrics.bundlesFailed
    $successRate = if ($totalBundles -gt 0) {
        [math]::Round(($script:HealthState.Metrics.bundlesCreated / $totalBundles) * 100, 1)
    }
    else {
        100
    }

    $report = @{
        status = $script:HealthState.Status
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        uptime = @{
            days = [math]::Floor($uptime.TotalDays)
            hours = $uptime.Hours
            minutes = $uptime.Minutes
            totalSeconds = [math]::Round($uptime.TotalSeconds, 0)
        }
        metrics = @{
            bundles = @{
                created = $script:HealthState.Metrics.bundlesCreated
                failed = $script:HealthState.Metrics.bundlesFailed
                successRate = $successRate
                totalSizeMB = [math]::Round($script:HealthState.Metrics.totalBundleSize / 1MB, 2)
                lastBundle = $script:HealthState.Metrics.lastBundleTime
                lastDurationSeconds = $script:HealthState.Metrics.lastBundleDuration
            }
            snapshots = @{
                created = $script:HealthState.Metrics.snapshotsCreated
                failed = $script:HealthState.Metrics.snapshotsFailed
            }
            publishing = @{
                successes = $script:HealthState.Metrics.publishSuccesses
                failures = $script:HealthState.Metrics.publishFailures
            }
            errors = @{
                total = $script:HealthState.Metrics.errors.Count
                recent = $script:HealthState.Metrics.errors | Select-Object -Last 5
            }
            warnings = @{
                total = $script:HealthState.Metrics.warnings.Count
                recent = $script:HealthState.Metrics.warnings | Select-Object -Last 5
            }
        }
        thresholds = $script:HealthState.Thresholds
        issues = if ($script:HealthState.StatusIssues) { $script:HealthState.StatusIssues } else { @() }
        system = @{
            hostname = $env:COMPUTERNAME
            user = $env:USERNAME
            pid = $PID
            startTime = if ($script:HealthState.StartTime) { $script:HealthState.StartTime.ToString("yyyy-MM-ddTHH:mm:ssZ") } else { $null }
        }
    }

    return $report
}

# Write health report to file
function Write-HealthReport {
    <#
    .SYNOPSIS
        Writes current health report to JSON file.
    #>
    if (-not $script:HealthState.Initialized) {
        return
    }

    $report = Get-HealthReport
    $reportFile = Join-Path $script:HealthState.ReportPath "health.json"

    try {
        $report | ConvertTo-Json -Depth 10 | Out-File $reportFile -Encoding UTF8 -Force
    }
    catch {
        Write-Warning "Failed to write health report: $_"
    }
}

# Check if collector is healthy
function Test-CollectorHealth {
    <#
    .SYNOPSIS
        Returns whether the collector is in a healthy state.
    #>
    if (-not $script:HealthState.Initialized) {
        return $false
    }

    return $script:HealthState.Status -eq "Healthy"
}

# Reset health metrics
function Reset-HealthMetrics {
    <#
    .SYNOPSIS
        Resets all health metrics while preserving configuration.
    #>
    if (-not $script:HealthState.Initialized) {
        return
    }

    $script:HealthState.StartTime = Get-Date
    $script:HealthState.ConsecutiveFailures = 0
    $script:HealthState.Status = "Healthy"

    $script:HealthState.Metrics = @{
        bundlesCreated = 0
        bundlesFailed = 0
        totalBundleSize = 0
        lastBundleTime = $null
        lastBundleDuration = 0
        snapshotsCreated = 0
        snapshotsFailed = 0
        publishSuccesses = 0
        publishFailures = 0
        errors = @()
        warnings = @()
    }

    Write-HealthReport
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-HealthReporter',
    'Update-BundleMetrics',
    'Update-SnapshotMetrics',
    'Update-PublishMetrics',
    'Add-HealthWarning',
    'Get-HealthReport',
    'Test-CollectorHealth',
    'Reset-HealthMetrics'
)
