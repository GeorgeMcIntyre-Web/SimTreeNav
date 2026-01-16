# PerformanceMetrics.ps1 - Performance tracking utilities for large tree operations
# Tracks: rowsScanned, queryDurationMs, memoryEstimateMb, outputSizes

<#
.SYNOPSIS
    Performance metrics tracking module for SimTreeNav large tree operations.
    
.DESCRIPTION
    Provides utilities to track and record performance metrics during
    extraction, snapshot, and diff operations. Writes metrics to meta.json
    and probe.json files.
#>

# Global metrics storage
$script:PerfMetrics = @{
    StartTime = $null
    QueryMetrics = @()
    MemorySnapshots = @()
    OutputSizes = @{}
    TotalRowsScanned = 0
    Phase = ""
}

function Start-PerfSession {
    <#
    .SYNOPSIS
        Start a new performance tracking session.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Phase
    )
    
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    
    $script:PerfMetrics = @{
        StartTime = Get-Date
        QueryMetrics = @()
        MemorySnapshots = @()
        OutputSizes = @{}
        TotalRowsScanned = 0
        Phase = $Phase
    }
    
    # Record initial memory snapshot
    Record-MemorySnapshot -Label "Session Start"
    
    Write-Host "[PERF] Started performance session: $Phase" -ForegroundColor Cyan
}

function Record-QueryMetrics {
    <#
    .SYNOPSIS
        Record metrics for a database query operation.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$QueryName,
        
        [Parameter(Mandatory=$true)]
        [int]$RowsScanned,
        
        [Parameter(Mandatory=$true)]
        [timespan]$Duration,
        
        [int]$PageNumber = 0,
        [int]$PageSize = 0
    )
    
    $metrics = @{
        QueryName = $QueryName
        RowsScanned = $RowsScanned
        DurationMs = [math]::Round($Duration.TotalMilliseconds, 2)
        Timestamp = (Get-Date).ToString("o")
        PageNumber = $PageNumber
        PageSize = $PageSize
    }
    
    $script:PerfMetrics.QueryMetrics += $metrics
    $script:PerfMetrics.TotalRowsScanned += $RowsScanned
    
    Write-Host "[PERF] Query '$QueryName': $RowsScanned rows in $([math]::Round($Duration.TotalMilliseconds, 0))ms" -ForegroundColor DarkCyan
}

function Record-MemorySnapshot {
    <#
    .SYNOPSIS
        Record current memory usage snapshot.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Label
    )
    
    $process = Get-Process -Id $PID
    $memMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
    $privateMB = [math]::Round($process.PrivateMemorySize64 / 1MB, 2)
    
    $snapshot = @{
        Label = $Label
        WorkingSetMB = $memMB
        PrivateMemoryMB = $privateMB
        Timestamp = (Get-Date).ToString("o")
    }
    
    $script:PerfMetrics.MemorySnapshots += $snapshot
    
    Write-Host "[PERF] Memory @ '$Label': ${memMB}MB working, ${privateMB}MB private" -ForegroundColor DarkCyan
}

function Record-OutputSize {
    <#
    .SYNOPSIS
        Record the size of an output file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$FileName,
        
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    
    if (Test-Path $FilePath) {
        $file = Get-Item $FilePath
        $sizeBytes = $file.Length
        $sizeMB = [math]::Round($sizeBytes / 1MB, 3)
        
        $script:PerfMetrics.OutputSizes[$FileName] = @{
            SizeBytes = $sizeBytes
            SizeMB = $sizeMB
            Path = $FilePath
        }
        
        Write-Host "[PERF] Output '$FileName': ${sizeMB}MB" -ForegroundColor DarkCyan
    }
}

function Complete-PerfSession {
    <#
    .SYNOPSIS
        Complete performance session and return metrics summary.
    #>
    param(
        [string]$OutputDir = "."
    )
    
    $endTime = Get-Date
    $totalDuration = $endTime - $script:PerfMetrics.StartTime
    
    # Final memory snapshot
    Record-MemorySnapshot -Label "Session End"
    
    # Calculate peak memory
    $peakWorkingSet = ($script:PerfMetrics.MemorySnapshots | Measure-Object -Property WorkingSetMB -Maximum).Maximum
    $peakPrivate = ($script:PerfMetrics.MemorySnapshots | Measure-Object -Property PrivateMemoryMB -Maximum).Maximum
    
    # Build summary
    $summary = @{
        phase = $script:PerfMetrics.Phase
        startTime = $script:PerfMetrics.StartTime.ToString("o")
        endTime = $endTime.ToString("o")
        totalDurationMs = [math]::Round($totalDuration.TotalMilliseconds, 2)
        totalDurationSec = [math]::Round($totalDuration.TotalSeconds, 2)
        totalRowsScanned = $script:PerfMetrics.TotalRowsScanned
        queryCount = $script:PerfMetrics.QueryMetrics.Count
        peakWorkingSetMB = $peakWorkingSet
        peakPrivateMemoryMB = $peakPrivate
        queries = $script:PerfMetrics.QueryMetrics
        memorySnapshots = $script:PerfMetrics.MemorySnapshots
        outputSizes = $script:PerfMetrics.OutputSizes
    }
    
    Write-Host "`n[PERF] ====== Session Complete ======" -ForegroundColor Green
    Write-Host "[PERF] Phase: $($script:PerfMetrics.Phase)" -ForegroundColor Green
    Write-Host "[PERF] Duration: $([math]::Round($totalDuration.TotalSeconds, 1))s" -ForegroundColor Green
    Write-Host "[PERF] Total Rows: $($script:PerfMetrics.TotalRowsScanned)" -ForegroundColor Green
    Write-Host "[PERF] Peak Memory: ${peakWorkingSet}MB" -ForegroundColor Green
    Write-Host "[PERF] =================================" -ForegroundColor Green
    
    return $summary
}

function Write-MetaJson {
    <#
    .SYNOPSIS
        Write performance metrics to meta.json file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Metrics,
        
        [string]$OutputPath = "meta.json",
        
        [hashtable]$AdditionalData = @{}
    )
    
    $metaData = @{
        version = "1.0"
        generator = "SimTreeNav"
        generatedAt = (Get-Date).ToString("o")
        performance = $Metrics
    }
    
    # Merge additional data
    foreach ($key in $AdditionalData.Keys) {
        $metaData[$key] = $AdditionalData[$key]
    }
    
    $json = $metaData | ConvertTo-Json -Depth 10 -Compress:$false
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutputPath, $json, $utf8NoBom)
    
    Write-Host "[PERF] Wrote metrics to: $OutputPath" -ForegroundColor Cyan
}

function Write-ProbeJson {
    <#
    .SYNOPSIS
        Write lightweight probe data for quick status checks.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Metrics,
        
        [string]$OutputPath = "probe.json",
        
        [int]$NodeCount = 0,
        [string]$Status = "complete"
    )
    
    $probeData = @{
        status = $Status
        nodeCount = $NodeCount
        totalDurationMs = $Metrics.totalDurationMs
        totalRowsScanned = $Metrics.totalRowsScanned
        peakMemoryMB = $Metrics.peakWorkingSetMB
        timestamp = (Get-Date).ToString("o")
    }
    
    $json = $probeData | ConvertTo-Json -Compress
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutputPath, $json, $utf8NoBom)
    
    Write-Host "[PERF] Wrote probe to: $OutputPath" -ForegroundColor Cyan
}

# Export functions
Export-ModuleMember -Function @(
    'Start-PerfSession',
    'Record-QueryMetrics',
    'Record-MemorySnapshot',
    'Record-OutputSize',
    'Complete-PerfSession',
    'Write-MetaJson',
    'Write-ProbeJson'
)
