# StructuredLogger.ps1
# Structured logging with JSON output and log rotation for Collector Agent
#
# Features:
# - JSON-formatted log entries for machine parsing
# - Console output for human readability
# - Automatic log rotation by size and age
# - Log retention policies
# - Thread-safe file writing

<#
.SYNOPSIS
    Provides structured logging capabilities for the Collector Agent.

.DESCRIPTION
    This module provides JSON-based structured logging with:
    - Multiple log levels (DEBUG, INFO, WARN, ERROR, FATAL)
    - Automatic log rotation by size (default 10MB)
    - Log retention by count and age
    - Correlation IDs for tracing
    - Machine-parseable JSON format

.EXAMPLE
    Initialize-CollectorLogger -LogPath "C:\logs\collector"
    Write-CollectorLog -Level INFO -Message "Snapshot started" -Data @{schema="DESIGN12"}
#>

# Module-level variables
$script:LoggerConfig = @{
    LogPath = $null
    MaxSizeMB = 10
    MaxFiles = 10
    MaxAgeDays = 30
    LogLevel = "INFO"
    CorrelationId = $null
    ConsoleOutput = $true
    Initialized = $false
}

$script:LogLevels = @{
    DEBUG = 0
    INFO = 1
    WARN = 2
    ERROR = 3
    FATAL = 4
}

# Initialize the logger
function Initialize-CollectorLogger {
    <#
    .SYNOPSIS
        Initializes the structured logger with configuration.
    .PARAMETER LogPath
        Directory where log files will be stored
    .PARAMETER MaxSizeMB
        Maximum size of a single log file before rotation (default 10MB)
    .PARAMETER MaxFiles
        Maximum number of rotated log files to keep (default 10)
    .PARAMETER MaxAgeDays
        Maximum age of log files in days before deletion (default 30)
    .PARAMETER LogLevel
        Minimum log level to record (DEBUG, INFO, WARN, ERROR, FATAL)
    .PARAMETER ConsoleOutput
        Whether to also output logs to console (default true)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$LogPath,

        [int]$MaxSizeMB = 10,
        [int]$MaxFiles = 10,
        [int]$MaxAgeDays = 30,
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "FATAL")]
        [string]$LogLevel = "INFO",
        [bool]$ConsoleOutput = $true
    )

    # Create log directory if it doesn't exist
    if (-not (Test-Path $LogPath)) {
        New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    }

    # Generate new correlation ID for this session
    $correlationId = [guid]::NewGuid().ToString("N").Substring(0, 8)

    $script:LoggerConfig = @{
        LogPath = $LogPath
        MaxSizeMB = $MaxSizeMB
        MaxFiles = $MaxFiles
        MaxAgeDays = $MaxAgeDays
        LogLevel = $LogLevel
        CorrelationId = $correlationId
        ConsoleOutput = $ConsoleOutput
        Initialized = $true
    }

    # Perform initial rotation check
    Invoke-LogRotation

    # Log initialization
    Write-CollectorLog -Level INFO -Message "Logger initialized" -Data @{
        logPath = $LogPath
        maxSizeMB = $MaxSizeMB
        maxFiles = $MaxFiles
        maxAgeDays = $MaxAgeDays
        logLevel = $LogLevel
        correlationId = $correlationId
    }

    return $correlationId
}

# Get current log file path
function Get-CurrentLogFile {
    <#
    .SYNOPSIS
        Returns the current log file path based on date.
    #>
    $date = Get-Date -Format "yyyy-MM-dd"
    return Join-Path $script:LoggerConfig.LogPath "collector-$date.json"
}

# Write a structured log entry
function Write-CollectorLog {
    <#
    .SYNOPSIS
        Writes a structured log entry to file and optionally console.
    .PARAMETER Level
        Log level (DEBUG, INFO, WARN, ERROR, FATAL)
    .PARAMETER Message
        Human-readable log message
    .PARAMETER Data
        Optional hashtable of additional structured data
    .PARAMETER Exception
        Optional exception object for error logging
    #>
    param(
        [Parameter(Mandatory=$true)]
        [ValidateSet("DEBUG", "INFO", "WARN", "ERROR", "FATAL")]
        [string]$Level,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [hashtable]$Data = @{},

        [System.Exception]$Exception = $null
    )

    # Check if logger is initialized
    if (-not $script:LoggerConfig.Initialized) {
        Write-Warning "Logger not initialized. Call Initialize-CollectorLogger first."
        return
    }

    # Check log level threshold
    if ($script:LogLevels[$Level] -lt $script:LogLevels[$script:LoggerConfig.LogLevel]) {
        return
    }

    # Build log entry
    $timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ss.fffzzz"
    $logEntry = [ordered]@{
        timestamp = $timestamp
        level = $Level
        correlationId = $script:LoggerConfig.CorrelationId
        message = $Message
        host = $env:COMPUTERNAME
        user = $env:USERNAME
        pid = $PID
    }

    # Add custom data
    if ($Data.Count -gt 0) {
        $logEntry.data = $Data
    }

    # Add exception details if present
    if ($Exception) {
        $logEntry.exception = @{
            type = $Exception.GetType().FullName
            message = $Exception.Message
            stackTrace = $Exception.StackTrace
        }
        if ($Exception.InnerException) {
            $logEntry.exception.innerException = @{
                type = $Exception.InnerException.GetType().FullName
                message = $Exception.InnerException.Message
            }
        }
    }

    # Convert to JSON
    $jsonLine = $logEntry | ConvertTo-Json -Compress -Depth 10

    # Write to file (thread-safe with mutex)
    $logFile = Get-CurrentLogFile
    $mutexName = "Global\CollectorLogger_" + ($logFile -replace '[\\/:*?"<>|]', '_')
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)

    try {
        $mutex.WaitOne() | Out-Null
        Add-Content -Path $logFile -Value $jsonLine -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write log: $_"
    }
    finally {
        $mutex.ReleaseMutex()
        $mutex.Dispose()
    }

    # Console output
    if ($script:LoggerConfig.ConsoleOutput) {
        $color = switch ($Level) {
            "DEBUG" { "Gray" }
            "INFO" { "White" }
            "WARN" { "Yellow" }
            "ERROR" { "Red" }
            "FATAL" { "Magenta" }
        }
        $consoleTime = Get-Date -Format "HH:mm:ss"
        $prefix = "[$consoleTime] [$Level]"
        Write-Host "$prefix $Message" -ForegroundColor $color

        if ($Data.Count -gt 0) {
            $dataStr = ($Data.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", "
            Write-Host "  $dataStr" -ForegroundColor DarkGray
        }
    }

    # Check if rotation needed after write
    Invoke-LogRotation
}

# Perform log rotation
function Invoke-LogRotation {
    <#
    .SYNOPSIS
        Rotates and cleans up old log files based on size, count, and age policies.
    #>
    if (-not $script:LoggerConfig.Initialized) {
        return
    }

    $logPath = $script:LoggerConfig.LogPath
    $maxSizeBytes = $script:LoggerConfig.MaxSizeMB * 1MB
    $maxFiles = $script:LoggerConfig.MaxFiles
    $maxAgeDays = $script:LoggerConfig.MaxAgeDays

    # Get all collector log files
    $logFiles = Get-ChildItem -Path $logPath -Filter "collector-*.json" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending

    # Check current file size for rotation
    $currentFile = Get-CurrentLogFile
    if (Test-Path $currentFile) {
        $fileInfo = Get-Item $currentFile
        if ($fileInfo.Length -ge $maxSizeBytes) {
            # Rotate: rename with timestamp
            $rotatedName = $currentFile -replace '\.json$', "-$(Get-Date -Format 'HHmmss').json"
            try {
                Rename-Item -Path $currentFile -NewName (Split-Path $rotatedName -Leaf) -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to rotate log file: $_"
            }
        }
    }

    # Clean up by file count
    $logFiles = Get-ChildItem -Path $logPath -Filter "collector-*.json" -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending

    if ($logFiles.Count -gt $maxFiles) {
        $filesToDelete = $logFiles | Select-Object -Skip $maxFiles
        foreach ($file in $filesToDelete) {
            try {
                Remove-Item $file.FullName -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to delete old log file $($file.Name): $_"
            }
        }
    }

    # Clean up by age
    $cutoffDate = (Get-Date).AddDays(-$maxAgeDays)
    $logFiles = Get-ChildItem -Path $logPath -Filter "collector-*.json" -ErrorAction SilentlyContinue

    foreach ($file in $logFiles) {
        if ($file.LastWriteTime -lt $cutoffDate) {
            try {
                Remove-Item $file.FullName -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to delete aged log file $($file.Name): $_"
            }
        }
    }
}

# Get log statistics
function Get-CollectorLogStats {
    <#
    .SYNOPSIS
        Returns statistics about current log files.
    #>
    if (-not $script:LoggerConfig.Initialized) {
        return $null
    }

    $logPath = $script:LoggerConfig.LogPath
    $logFiles = Get-ChildItem -Path $logPath -Filter "collector-*.json" -ErrorAction SilentlyContinue

    $stats = @{
        logPath = $logPath
        fileCount = $logFiles.Count
        totalSizeMB = [math]::Round(($logFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        oldestFile = if ($logFiles.Count -gt 0) { ($logFiles | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
        newestFile = if ($logFiles.Count -gt 0) { ($logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
        currentCorrelationId = $script:LoggerConfig.CorrelationId
    }

    return $stats
}

# Close logger (flush any remaining data)
function Close-CollectorLogger {
    <#
    .SYNOPSIS
        Closes the logger and performs cleanup.
    #>
    if ($script:LoggerConfig.Initialized) {
        Write-CollectorLog -Level INFO -Message "Logger closing"
        $script:LoggerConfig.Initialized = $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-CollectorLogger',
    'Write-CollectorLog',
    'Invoke-LogRotation',
    'Get-CollectorLogStats',
    'Close-CollectorLogger'
)
