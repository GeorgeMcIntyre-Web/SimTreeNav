# Collector.ps1
# Main entry point for Collector Agent Mode
#
# A safe "collector agent" mode for internal environments that:
# - Runs read-only database snapshots
# - Anonymizes sensitive data
# - Creates secure bundles for export
# - Publishes bundles to configured targets
#
# Usage:
#   .\Collector.ps1 -Config <collector.json> -Mode Watch
#   .\Collector.ps1 -Config <collector.json> -Mode Once
#   .\Collector.ps1 -Config <collector.json> -Mode Status

<#
.SYNOPSIS
    Collector Agent for safe, read-only database snapshots.

.DESCRIPTION
    The Collector Agent provides a secure way to:
    - Extract tree structure data from Oracle databases
    - Anonymize sensitive information
    - Bundle data for safe external sharing
    - Publish to local shares or cloud endpoints

    Key safety features:
    - Read-only database transactions
    - Data anonymization by default
    - Atomic bundle creation (no partial uploads)
    - Structured logging for audit trails
    - Health monitoring and reporting

.PARAMETER Config
    Path to the collector configuration JSON file.
    See config/collector-config.template.json for format.

.PARAMETER Mode
    Operating mode:
    - Once: Run a single snapshot and exit
    - Watch: Continuously run snapshots at configured intervals
    - Status: Display current health status and exit
    - Test: Validate configuration without running

.PARAMETER Label
    Optional label for bundle naming (default: "snapshot")

.PARAMETER Verbose
    Enable verbose logging output

.EXAMPLE
    # Run once
    .\Collector.ps1 -Config .\config\collector.json -Mode Once

.EXAMPLE
    # Watch mode (continuous)
    .\Collector.ps1 -Config .\config\collector.json -Mode Watch

.EXAMPLE
    # Check status
    .\Collector.ps1 -Config .\config\collector.json -Mode Status

.NOTES
    Author: SimTreeNav Team
    Version: 1.0.0
    Requires: PowerShell 5.1+, Oracle Instant Client
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$Config,

    [Parameter(Mandatory=$true)]
    [ValidateSet("Once", "Watch", "Status", "Test")]
    [string]$Mode,

    [string]$Label = "snapshot",

    [switch]$VerboseOutput
)

$ErrorActionPreference = "Stop"
$script:CollectorVersion = "1.0.0"

# ============================================================================
# MODULE IMPORTS
# ============================================================================

$scriptRoot = $PSScriptRoot

# Import collector modules
$modules = @(
    "StructuredLogger.ps1",
    "CollectorUtils.ps1",
    "HealthReporter.ps1",
    "PublishTargets.ps1"
)

foreach ($module in $modules) {
    $modulePath = Join-Path $scriptRoot $module
    if (Test-Path $modulePath) {
        . $modulePath
    }
    else {
        Write-Error "Required module not found: $module"
        exit 1
    }
}

# Import credential manager
$credManagerPath = Join-Path $scriptRoot "..\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    . $credManagerPath
}

# ============================================================================
# CONFIGURATION LOADING
# ============================================================================

function Read-CollectorConfig {
    <#
    .SYNOPSIS
        Loads and validates the collector configuration file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }

    try {
        $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json

        # Validate required fields
        $requiredFields = @("database", "output")
        foreach ($field in $requiredFields) {
            if (-not $config.$field) {
                throw "Missing required configuration field: $field"
            }
        }

        # Apply defaults
        if (-not $config.schedule) {
            $config | Add-Member -NotePropertyName "schedule" -NotePropertyValue @{
                intervalMinutes = 60
                enabled = $true
            }
        }

        if (-not $config.logging) {
            $config | Add-Member -NotePropertyName "logging" -NotePropertyValue @{
                path = "logs"
                level = "INFO"
                maxSizeMB = 10
                maxFiles = 10
                maxAgeDays = 30
            }
        }

        if (-not $config.anonymization) {
            $config | Add-Member -NotePropertyName "anonymization" -NotePropertyValue @{
                enabled = $true
                createMapping = $false
            }
        }

        if (-not $config.publishing) {
            $config | Add-Member -NotePropertyName "publishing" -NotePropertyValue @{
                targets = @(
                    @{
                        type = "local"
                        enabled = $true
                        path = "bundles"
                    }
                )
            }
        }

        return $config
    }
    catch {
        throw "Failed to parse configuration file: $_"
    }
}

# ============================================================================
# MAIN COLLECTOR LOGIC
# ============================================================================

function Initialize-Collector {
    <#
    .SYNOPSIS
        Initializes the collector with configuration.
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Config
    )

    # Resolve paths relative to config file location
    $configDir = Split-Path $script:ConfigPath -Parent
    if (-not $configDir) { $configDir = "." }

    # Initialize logging
    $logPath = if ([System.IO.Path]::IsPathRooted($Config.logging.path)) {
        $Config.logging.path
    }
    else {
        Join-Path $configDir $Config.logging.path
    }

    $correlationId = Initialize-CollectorLogger `
        -LogPath $logPath `
        -MaxSizeMB $Config.logging.maxSizeMB `
        -MaxFiles $Config.logging.maxFiles `
        -MaxAgeDays $Config.logging.maxAgeDays `
        -LogLevel $Config.logging.level `
        -ConsoleOutput $true

    Write-CollectorLog -Level INFO -Message "Collector initializing" -Data @{
        version = $script:CollectorVersion
        mode = $Mode
        configFile = $script:ConfigPath
    }

    # Initialize health reporter
    $healthPath = if ([System.IO.Path]::IsPathRooted($Config.output.healthPath)) {
        $Config.output.healthPath
    }
    else {
        Join-Path $configDir ($Config.output.healthPath ?? "health")
    }

    Initialize-HealthReporter -ReportPath $healthPath

    # Resolve output paths
    $script:BundlePath = if ([System.IO.Path]::IsPathRooted($Config.output.bundlePath)) {
        $Config.output.bundlePath
    }
    else {
        Join-Path $configDir ($Config.output.bundlePath ?? "bundles")
    }

    $script:MappingPath = if ($Config.anonymization.createMapping) {
        if ([System.IO.Path]::IsPathRooted($Config.output.mappingPath)) {
            $Config.output.mappingPath
        }
        else {
            Join-Path $configDir ($Config.output.mappingPath ?? "mapping")
        }
    }
    else {
        $null
    }

    # Ensure directories exist
    if (-not (Test-Path $script:BundlePath)) {
        New-Item -ItemType Directory -Path $script:BundlePath -Force | Out-Null
    }

    if ($script:MappingPath -and -not (Test-Path $script:MappingPath)) {
        New-Item -ItemType Directory -Path $script:MappingPath -Force | Out-Null
    }

    Write-CollectorLog -Level INFO -Message "Collector initialized" -Data @{
        bundlePath = $script:BundlePath
        mappingPath = $script:MappingPath
        healthPath = $healthPath
        logPath = $logPath
    }

    return $correlationId
}

function Invoke-CollectorRun {
    <#
    .SYNOPSIS
        Executes a single collector run (snapshot + bundle + publish).
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Config,

        [string]$Label = "snapshot"
    )

    $startTime = Get-Date
    $success = $false

    Write-CollectorLog -Level INFO -Message "Starting collector run" -Data @{
        label = $Label
        database = $Config.database.tnsName
        schema = $Config.database.schema
    }

    try {
        # Step 1: Create snapshot
        Write-CollectorLog -Level INFO -Message "Creating database snapshot"

        $snapshot = New-CollectorSnapshot `
            -TNSName $Config.database.tnsName `
            -Schema $Config.database.schema `
            -ProjectId $Config.database.projectId `
            -MaxRows ($Config.database.maxRows ?? 10000)

        Update-SnapshotMetrics -Success $true

        # Step 2: Anonymize if enabled
        $dataToBundle = $snapshot
        $mappingData = $null

        if ($Config.anonymization.enabled) {
            Write-CollectorLog -Level INFO -Message "Anonymizing data"

            if ($Config.anonymization.createMapping) {
                $result = ConvertTo-AnonymizedData `
                    -Snapshot $snapshot `
                    -CreateMapping $true

                $dataToBundle = $result.data
                $mappingData = $result.mapping
            }
            else {
                $dataToBundle = ConvertTo-AnonymizedData -Snapshot $snapshot
            }
        }

        # Step 3: Create bundle
        Write-CollectorLog -Level INFO -Message "Creating bundle"

        $bundleResult = New-CollectorBundle `
            -Data $dataToBundle `
            -OutputPath $script:BundlePath `
            -Label $Label `
            -Mapping $mappingData `
            -MappingPath $script:MappingPath

        $duration = ((Get-Date) - $startTime).TotalSeconds
        $bundleSize = (Get-Item $bundleResult.bundleFile).Length

        Update-BundleMetrics -Success $true -Duration $duration -SizeBytes $bundleSize

        # Step 4: Publish to targets
        if ($Config.publishing.targets -and $Config.publishing.targets.Count -gt 0) {
            Write-CollectorLog -Level INFO -Message "Publishing bundle"

            # Resolve relative paths in targets
            $resolvedTargets = @()
            foreach ($target in $Config.publishing.targets) {
                $resolvedTarget = $target.PSObject.Copy()
                if ($target.type -eq "local" -and $target.path) {
                    if (-not [System.IO.Path]::IsPathRooted($target.path)) {
                        $configDir = Split-Path $script:ConfigPath -Parent
                        $resolvedTarget.path = Join-Path $configDir $target.path
                    }
                }
                $resolvedTargets += $resolvedTarget
            }

            $publishResult = Publish-Bundle `
                -BundlePath $bundleResult.bundleFile `
                -Targets $resolvedTargets
        }

        $success = $true

        Write-CollectorLog -Level INFO -Message "Collector run completed successfully" -Data @{
            duration = [math]::Round($duration, 2)
            bundleFile = $bundleResult.bundleFile
            bundleSize = $bundleSize
            snapshotRows = $snapshot.statistics.totalRows
        }
    }
    catch {
        $duration = ((Get-Date) - $startTime).TotalSeconds

        Update-BundleMetrics -Success $false -Duration $duration -ErrorMessage $_.Exception.Message
        Update-SnapshotMetrics -Success $false -ErrorMessage $_.Exception.Message

        Write-CollectorLog -Level ERROR -Message "Collector run failed" -Exception $_.Exception

        throw
    }

    return @{
        success = $success
        duration = $duration
        bundleFile = $bundleResult.bundleFile
    }
}

function Start-WatchMode {
    <#
    .SYNOPSIS
        Starts the collector in watch mode (continuous operation).
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Config,

        [string]$Label = "snapshot"
    )

    $intervalMinutes = $Config.schedule.intervalMinutes ?? 60
    $intervalSeconds = $intervalMinutes * 60

    Write-CollectorLog -Level INFO -Message "Starting watch mode" -Data @{
        intervalMinutes = $intervalMinutes
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Collector Agent - Watch Mode" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Interval: $intervalMinutes minutes" -ForegroundColor White
    Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
    Write-Host ""

    $runCount = 0
    $errorCount = 0

    # Register Ctrl+C handler
    $continueWatching = $true
    [Console]::TreatControlCAsInput = $false

    try {
        while ($continueWatching) {
            $runCount++

            Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Run #$runCount starting..." -ForegroundColor Cyan

            try {
                $result = Invoke-CollectorRun -Config $Config -Label "$Label-$runCount"

                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Run #$runCount completed ($([math]::Round($result.duration, 1))s)" -ForegroundColor Green
            }
            catch {
                $errorCount++
                Write-Host "[$((Get-Date).ToString('HH:mm:ss'))] Run #$runCount failed: $($_.Exception.Message)" -ForegroundColor Red

                # Check health status
                if (-not (Test-CollectorHealth)) {
                    Write-Host ""
                    Write-Host "WARNING: Collector is unhealthy. Consider stopping and investigating." -ForegroundColor Yellow
                    Add-HealthWarning -Message "Multiple consecutive failures detected" -Component "watchMode"
                }
            }

            # Calculate next run time
            $nextRun = (Get-Date).AddSeconds($intervalSeconds)
            Write-Host "  Next run at: $($nextRun.ToString('HH:mm:ss'))" -ForegroundColor Gray
            Write-Host ""

            # Wait for next interval
            $waitEnd = $nextRun
            while ((Get-Date) -lt $waitEnd) {
                Start-Sleep -Seconds 10

                # Check for stop signal (simplified - in production use proper signal handling)
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq [ConsoleKey]::C -and $key.Modifiers -eq [ConsoleModifiers]::Control) {
                        $continueWatching = $false
                        break
                    }
                }
            }
        }
    }
    finally {
        Write-Host ""
        Write-Host "Watch mode stopped." -ForegroundColor Yellow
        Write-Host "  Total runs: $runCount" -ForegroundColor Gray
        Write-Host "  Errors: $errorCount" -ForegroundColor Gray

        Write-CollectorLog -Level INFO -Message "Watch mode stopped" -Data @{
            totalRuns = $runCount
            errors = $errorCount
        }
    }
}

function Show-CollectorStatus {
    <#
    .SYNOPSIS
        Displays current collector status and health.
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Config
    )

    # Initialize just for status display
    $configDir = Split-Path $script:ConfigPath -Parent
    if (-not $configDir) { $configDir = "." }

    $healthPath = if ([System.IO.Path]::IsPathRooted($Config.output.healthPath)) {
        $Config.output.healthPath
    }
    else {
        Join-Path $configDir ($Config.output.healthPath ?? "health")
    }

    $healthFile = Join-Path $healthPath "health.json"

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Collector Agent Status" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    if (Test-Path $healthFile) {
        try {
            $health = Get-Content $healthFile -Raw | ConvertFrom-Json

            $statusColor = switch ($health.status) {
                "Healthy" { "Green" }
                "Degraded" { "Yellow" }
                "Unhealthy" { "Red" }
                default { "Gray" }
            }

            Write-Host "  Status: $($health.status)" -ForegroundColor $statusColor
            Write-Host ""
            Write-Host "  Uptime: $($health.uptime.days)d $($health.uptime.hours)h $($health.uptime.minutes)m" -ForegroundColor White
            Write-Host "  Last updated: $($health.timestamp)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "  Bundles:" -ForegroundColor Cyan
            Write-Host "    Created: $($health.metrics.bundles.created)" -ForegroundColor White
            Write-Host "    Failed:  $($health.metrics.bundles.failed)" -ForegroundColor White
            Write-Host "    Success Rate: $($health.metrics.bundles.successRate)%" -ForegroundColor White
            Write-Host "    Total Size: $($health.metrics.bundles.totalSizeMB) MB" -ForegroundColor White
            Write-Host ""
            Write-Host "  Publishing:" -ForegroundColor Cyan
            Write-Host "    Successes: $($health.metrics.publishing.successes)" -ForegroundColor White
            Write-Host "    Failures:  $($health.metrics.publishing.failures)" -ForegroundColor White
            Write-Host ""

            if ($health.issues -and $health.issues.Count -gt 0) {
                Write-Host "  Issues:" -ForegroundColor Yellow
                foreach ($issue in $health.issues) {
                    Write-Host "    - $issue" -ForegroundColor Yellow
                }
                Write-Host ""
            }

            if ($health.metrics.errors.recent -and $health.metrics.errors.recent.Count -gt 0) {
                Write-Host "  Recent Errors:" -ForegroundColor Red
                foreach ($error in $health.metrics.errors.recent) {
                    Write-Host "    [$($error.timestamp)] $($error.message)" -ForegroundColor Red
                }
                Write-Host ""
            }
        }
        catch {
            Write-Host "  Error reading health file: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "  No health data found." -ForegroundColor Gray
        Write-Host "  The collector has not been run yet." -ForegroundColor Gray
        Write-Host ""
    }

    # Show configuration summary
    Write-Host "  Configuration:" -ForegroundColor Cyan
    Write-Host "    Database: $($Config.database.tnsName)" -ForegroundColor White
    Write-Host "    Schema:   $($Config.database.schema)" -ForegroundColor White
    Write-Host "    Interval: $($Config.schedule.intervalMinutes ?? 60) minutes" -ForegroundColor White
    Write-Host ""
}

function Test-CollectorConfiguration {
    <#
    .SYNOPSIS
        Validates collector configuration without running.
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Config
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Configuration Validation" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $errors = @()
    $warnings = @()

    # Validate database settings
    Write-Host "  [Database]" -ForegroundColor Cyan
    if ($Config.database.tnsName) {
        Write-Host "    TNS Name: $($Config.database.tnsName)" -ForegroundColor Green
    }
    else {
        $errors += "Missing database.tnsName"
        Write-Host "    TNS Name: MISSING" -ForegroundColor Red
    }

    if ($Config.database.schema) {
        Write-Host "    Schema: $($Config.database.schema)" -ForegroundColor Green
    }
    else {
        $errors += "Missing database.schema"
        Write-Host "    Schema: MISSING" -ForegroundColor Red
    }

    # Validate output paths
    Write-Host ""
    Write-Host "  [Output]" -ForegroundColor Cyan
    $configDir = Split-Path $script:ConfigPath -Parent

    $bundlePath = if ([System.IO.Path]::IsPathRooted($Config.output.bundlePath)) {
        $Config.output.bundlePath
    }
    else {
        Join-Path $configDir ($Config.output.bundlePath ?? "bundles")
    }

    if (Test-Path $bundlePath) {
        Write-Host "    Bundle Path: $bundlePath (exists)" -ForegroundColor Green
    }
    else {
        Write-Host "    Bundle Path: $bundlePath (will be created)" -ForegroundColor Yellow
    }

    # Validate publishing targets
    Write-Host ""
    Write-Host "  [Publishing Targets]" -ForegroundColor Cyan

    if ($Config.publishing.targets -and $Config.publishing.targets.Count -gt 0) {
        foreach ($target in $Config.publishing.targets) {
            $status = if ($target.enabled) { "enabled" } else { "disabled" }
            $color = if ($target.enabled) { "Green" } else { "Gray" }

            Write-Host "    - $($target.type): $status" -ForegroundColor $color

            if ($target.type -eq "local" -and $target.path) {
                $targetPath = if ([System.IO.Path]::IsPathRooted($target.path)) {
                    $target.path
                }
                else {
                    Join-Path $configDir $target.path
                }
                Write-Host "      Path: $targetPath" -ForegroundColor Gray
            }
            elseif ($target.type -eq "http" -and $target.endpoint) {
                Write-Host "      Endpoint: $($target.endpoint)" -ForegroundColor Gray
                $warnings += "HTTP publishing is a stub implementation"
            }
            elseif ($target.type -eq "r2") {
                Write-Host "      Bucket: $($target.bucket)" -ForegroundColor Gray
                $warnings += "R2 publishing is design-only (not implemented)"
            }
        }
    }
    else {
        $warnings += "No publishing targets configured"
        Write-Host "    (none configured)" -ForegroundColor Yellow
    }

    # Validate anonymization
    Write-Host ""
    Write-Host "  [Anonymization]" -ForegroundColor Cyan
    if ($Config.anonymization.enabled) {
        Write-Host "    Enabled: Yes" -ForegroundColor Green
        Write-Host "    Create Mapping: $($Config.anonymization.createMapping)" -ForegroundColor White
    }
    else {
        $warnings += "Anonymization is disabled - data may contain sensitive information"
        Write-Host "    Enabled: No (WARNING)" -ForegroundColor Yellow
    }

    # Summary
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan

    if ($errors.Count -eq 0) {
        Write-Host "  Configuration is VALID" -ForegroundColor Green
    }
    else {
        Write-Host "  Configuration has ERRORS" -ForegroundColor Red
        foreach ($error in $errors) {
            Write-Host "    - $error" -ForegroundColor Red
        }
    }

    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "  Warnings:" -ForegroundColor Yellow
        foreach ($warning in $warnings) {
            Write-Host "    - $warning" -ForegroundColor Yellow
        }
    }

    Write-Host ""

    return $errors.Count -eq 0
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

try {
    # Store config path for relative path resolution
    $script:ConfigPath = $Config
    if (-not [System.IO.Path]::IsPathRooted($Config)) {
        $script:ConfigPath = Join-Path $PWD $Config
    }

    # Load configuration
    $collectorConfig = Read-CollectorConfig -ConfigPath $script:ConfigPath

    # Execute based on mode
    switch ($Mode) {
        "Test" {
            $valid = Test-CollectorConfiguration -Config $collectorConfig
            exit $(if ($valid) { 0 } else { 1 })
        }
        "Status" {
            Show-CollectorStatus -Config $collectorConfig
            exit 0
        }
        "Once" {
            Initialize-Collector -Config $collectorConfig | Out-Null
            $result = Invoke-CollectorRun -Config $collectorConfig -Label $Label
            Close-CollectorLogger
            exit $(if ($result.success) { 0 } else { 1 })
        }
        "Watch" {
            Initialize-Collector -Config $collectorConfig | Out-Null
            Start-WatchMode -Config $collectorConfig -Label $Label
            Close-CollectorLogger
            exit 0
        }
    }
}
catch {
    Write-Host "FATAL: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray

    if ($script:LoggerConfig -and $script:LoggerConfig.Initialized) {
        Write-CollectorLog -Level FATAL -Message "Collector crashed" -Exception $_.Exception
        Close-CollectorLogger
    }

    exit 1
}
