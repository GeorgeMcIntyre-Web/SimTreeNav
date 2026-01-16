# PerfHarness.ps1 - Performance Test Harness for SimTreeNav
# Generates synthetic datasets and benchmarks snapshot/diff/export operations

<#
.SYNOPSIS
    Performance test harness for SimTreeNav large tree operations.
    
.DESCRIPTION
    Generates synthetic 50k/100k node datasets and runs benchmarks
    on snapshot, diff, and export operations. Reports timings and
    memory usage.

.PARAMETER NodeCount
    Number of nodes to generate (default: 50000)
    
.PARAMETER MaxDepth
    Maximum tree depth (default: 15)
    
.PARAMETER BranchingFactor
    Average children per node (default: 5)
    
.PARAMETER RunDiff
    Also benchmark diff operations (default: true)
    
.PARAMETER OutputDir
    Output directory for test files (default: perf-test-output)

.EXAMPLE
    .\PerfHarness.ps1 -NodeCount 50000
    
.EXAMPLE
    .\PerfHarness.ps1 -NodeCount 100000 -MaxDepth 20 -OutputDir "large-test"
#>

param(
    [int]$NodeCount = 50000,
    [int]$MaxDepth = 15,
    [int]$BranchingFactor = 5,
    [switch]$RunDiff = $true,
    [switch]$RunExport = $true,
    [string]$OutputDir = "perf-test-output",
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"

# Import utilities
$scriptRoot = $PSScriptRoot
$perfMetricsPath = Join-Path $scriptRoot "src\powershell\utilities\PerformanceMetrics.ps1"
$streamingPath = Join-Path $scriptRoot "src\powershell\utilities\StreamingJsonWriter.ps1"
$compressionPath = Join-Path $scriptRoot "src\powershell\utilities\CompressionUtils.ps1"

if (Test-Path $perfMetricsPath) { Import-Module $perfMetricsPath -Force }
if (Test-Path $streamingPath) { Import-Module $streamingPath -Force }
if (Test-Path $compressionPath) { Import-Module $compressionPath -Force }

# ============================================================================
# Configuration
# ============================================================================

$config = @{
    NodeCount = $NodeCount
    MaxDepth = $MaxDepth
    BranchingFactor = $BranchingFactor
    OutputDir = $OutputDir
    RunDiff = $RunDiff
    RunExport = $RunExport
}

# Sample class types for realistic data
$classTypes = @(
    @{ name = "class PmCollection"; niceName = "Collection"; typeId = 18 },
    @{ name = "class PmCompoundResource"; niceName = "CompoundResource"; typeId = 37 },
    @{ name = "class PmOperation"; niceName = "Operation"; typeId = 64 },
    @{ name = "class PmResource"; niceName = "Resource"; typeId = 66 },
    @{ name = "class PmCompoundPart"; niceName = "CompoundPart"; typeId = 21 },
    @{ name = "class PmPartPrototype"; niceName = "PartPrototype"; typeId = 65 },
    @{ name = "class PmProcess"; niceName = "Process"; typeId = 67 },
    @{ name = "class PmToolPrototype"; niceName = "ToolPrototype"; typeId = 68 },
    @{ name = "class PmStudyFolder"; niceName = "StudyFolder"; typeId = 69 },
    @{ name = "class RobcadStudy"; niceName = "RobcadStudy"; typeId = 177 }
)

# ============================================================================
# Synthetic Data Generation
# ============================================================================

function New-SyntheticTree {
    <#
    .SYNOPSIS
        Generate a synthetic tree with specified parameters.
    #>
    param(
        [int]$NodeCount,
        [int]$MaxDepth,
        [int]$BranchingFactor
    )
    
    Write-Host "`n[PERF HARNESS] Generating synthetic tree..." -ForegroundColor Cyan
    Write-Host "  Target nodes: $($NodeCount.ToString('N0'))" -ForegroundColor Gray
    Write-Host "  Max depth: $MaxDepth" -ForegroundColor Gray
    Write-Host "  Branching factor: $BranchingFactor" -ForegroundColor Gray
    
    $startTime = Get-Date
    [GC]::Collect()
    $startMemory = (Get-Process -Id $PID).WorkingSet64
    
    $nodes = [System.Collections.ArrayList]::new()
    $nodeId = 100000000  # Start with a large ID
    $currentLevel = @()
    $nextLevel = @()
    
    # Create root
    $rootId = $nodeId++
    $root = @{
        Id = $rootId
        ParentId = 0
        Level = 0
        Name = "SyntheticProject_$NodeCount"
        ClassName = "class PmProject"
        NiceName = "Project"
        TypeId = 122
        SeqNumber = 0
    }
    [void]$nodes.Add($root)
    $currentLevel = @($rootId)
    
    $nodesCreated = 1
    $currentDepth = 1
    
    # Generate tree level by level
    while ($nodesCreated -lt $NodeCount -and $currentDepth -le $MaxDepth) {
        $nextLevel = @()
        
        foreach ($parentId in $currentLevel) {
            if ($nodesCreated -ge $NodeCount) { break }
            
            # Randomize branching factor slightly
            $childCount = [Math]::Max(1, $BranchingFactor + (Get-Random -Minimum -2 -Maximum 3))
            
            for ($i = 0; $i -lt $childCount -and $nodesCreated -lt $NodeCount; $i++) {
                $classInfo = $classTypes | Get-Random
                
                $childId = $nodeId++
                $child = @{
                    Id = $childId
                    ParentId = $parentId
                    Level = $currentDepth
                    Name = "Node_${currentDepth}_$($nodesCreated)"
                    ClassName = $classInfo.name
                    NiceName = $classInfo.niceName
                    TypeId = $classInfo.typeId
                    SeqNumber = $i
                }
                [void]$nodes.Add($child)
                $nextLevel += $childId
                $nodesCreated++
                
                if ($nodesCreated % 10000 -eq 0) {
                    Write-Host "    Generated $($nodesCreated.ToString('N0')) nodes..." -ForegroundColor DarkGray
                }
            }
        }
        
        $currentLevel = $nextLevel
        $currentDepth++
    }
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $endMemory = (Get-Process -Id $PID).WorkingSet64
    $memoryUsedMB = [math]::Round(($endMemory - $startMemory) / 1MB, 2)
    
    Write-Host "  Generated $($nodes.Count.ToString('N0')) nodes in $([math]::Round($duration.TotalSeconds, 2))s" -ForegroundColor Green
    Write-Host "  Memory used: ${memoryUsedMB}MB" -ForegroundColor Green
    Write-Host "  Actual depth: $($currentDepth - 1) levels" -ForegroundColor Green
    
    return @{
        Nodes = $nodes
        GenerationTimeMs = [math]::Round($duration.TotalMilliseconds, 2)
        MemoryUsedMB = $memoryUsedMB
        ActualDepth = $currentDepth - 1
    }
}

function ConvertTo-TreeDataFormat {
    <#
    .SYNOPSIS
        Convert synthetic nodes to pipe-delimited format.
    #>
    param(
        [System.Collections.ArrayList]$Nodes
    )
    
    $lines = [System.Collections.ArrayList]::new()
    
    foreach ($node in $Nodes) {
        $line = "$($node.Level)|$($node.ParentId)|$($node.Id)|$($node.Name)|$($node.Name)||$($node.SeqNumber)|$($node.ClassName)|$($node.NiceName)|$($node.TypeId)"
        [void]$lines.Add($line)
    }
    
    return $lines
}

# ============================================================================
# Benchmark Functions
# ============================================================================

function Measure-SnapshotGeneration {
    <#
    .SYNOPSIS
        Benchmark snapshot/HTML generation.
    #>
    param(
        [string]$DataFile,
        [string]$OutputDir,
        [int]$NodeCount
    )
    
    Write-Host "`n[BENCHMARK] Snapshot Generation" -ForegroundColor Yellow
    
    $generateScript = Join-Path $scriptRoot "src\powershell\main\generate-virtualized-tree-html.ps1"
    
    if (-not (Test-Path $generateScript)) {
        Write-Warning "Virtualized tree generator not found: $generateScript"
        return $null
    }
    
    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
    $startMemory = (Get-Process -Id $PID).WorkingSet64
    $startTime = Get-Date
    
    $outputFile = Join-Path $OutputDir "benchmark-tree-${NodeCount}.html"
    
    & $generateScript `
        -DataFile $DataFile `
        -ProjectName "Benchmark_$NodeCount" `
        -ProjectId "100000000" `
        -Schema "BENCHMARK" `
        -OutputFile $outputFile `
        -MaxNodesInViewer 150000 `
        -GenerateJsonOutput
    
    $endTime = Get-Date
    $duration = $endTime - $startTime
    $endMemory = (Get-Process -Id $PID).WorkingSet64
    $peakMemoryMB = [math]::Round(($endMemory - $startMemory) / 1MB, 2)
    
    $outputSizeMB = if (Test-Path $outputFile) {
        [math]::Round((Get-Item $outputFile).Length / 1MB, 2)
    } else { 0 }
    
    $result = @{
        Operation = "SnapshotGeneration"
        NodeCount = $NodeCount
        DurationMs = [math]::Round($duration.TotalMilliseconds, 2)
        DurationSec = [math]::Round($duration.TotalSeconds, 2)
        PeakMemoryMB = $peakMemoryMB
        OutputSizeMB = $outputSizeMB
        OutputFile = $outputFile
        Status = if (Test-Path $outputFile) { "Success" } else { "Failed" }
    }
    
    Write-Host "  Duration: $($result.DurationSec)s" -ForegroundColor $(if ($result.DurationSec -lt 30) { "Green" } else { "Yellow" })
    Write-Host "  Peak Memory: $($result.PeakMemoryMB)MB" -ForegroundColor $(if ($result.PeakMemoryMB -lt 500) { "Green" } else { "Yellow" })
    Write-Host "  Output Size: $($result.OutputSizeMB)MB" -ForegroundColor Gray
    
    return $result
}

function Measure-JsonExport {
    <#
    .SYNOPSIS
        Benchmark JSON export (streaming vs standard).
    #>
    param(
        [System.Collections.ArrayList]$Nodes,
        [string]$OutputDir
    )
    
    Write-Host "`n[BENCHMARK] JSON Export" -ForegroundColor Yellow
    
    $results = @()
    
    # Standard JSON export
    Write-Host "  Testing standard ConvertTo-Json..." -ForegroundColor Gray
    [GC]::Collect()
    $startMemory = (Get-Process -Id $PID).WorkingSet64
    $startTime = Get-Date
    
    $jsonPath = Join-Path $OutputDir "nodes-standard.json"
    $jsonData = @{
        nodes = $Nodes
        meta = @{
            count = $Nodes.Count
            generatedAt = (Get-Date).ToString("o")
        }
    }
    $jsonData | ConvertTo-Json -Depth 5 -Compress | Out-File $jsonPath -Encoding UTF8
    
    $endTime = Get-Date
    $endMemory = (Get-Process -Id $PID).WorkingSet64
    
    $standardResult = @{
        Method = "Standard"
        DurationMs = [math]::Round(($endTime - $startTime).TotalMilliseconds, 2)
        PeakMemoryMB = [math]::Round(($endMemory - $startMemory) / 1MB, 2)
        OutputSizeMB = [math]::Round((Get-Item $jsonPath).Length / 1MB, 2)
    }
    $results += $standardResult
    Write-Host "    Standard: $($standardResult.DurationMs)ms, $($standardResult.PeakMemoryMB)MB memory" -ForegroundColor Gray
    
    # Streaming JSON export (if available)
    if (Get-Command New-StreamingJsonWriter -ErrorAction SilentlyContinue) {
        Write-Host "  Testing streaming JSON writer..." -ForegroundColor Gray
        [GC]::Collect()
        $startMemory = (Get-Process -Id $PID).WorkingSet64
        $startTime = Get-Date
        
        $streamPath = Join-Path $OutputDir "nodes-streaming.json"
        $writer = New-StreamingJsonWriter -Path $streamPath -ArrayName "nodes"
        $writer.Open()
        
        foreach ($node in $Nodes) {
            $writer.WriteNode($node)
        }
        
        $writer.Close(@{ streaming = $true })
        
        $endTime = Get-Date
        $endMemory = (Get-Process -Id $PID).WorkingSet64
        
        $streamResult = @{
            Method = "Streaming"
            DurationMs = [math]::Round(($endTime - $startTime).TotalMilliseconds, 2)
            PeakMemoryMB = [math]::Round(($endMemory - $startMemory) / 1MB, 2)
            OutputSizeMB = [math]::Round((Get-Item $streamPath).Length / 1MB, 2)
        }
        $results += $streamResult
        Write-Host "    Streaming: $($streamResult.DurationMs)ms, $($streamResult.PeakMemoryMB)MB memory" -ForegroundColor Gray
    }
    
    return $results
}

function Measure-Compression {
    <#
    .SYNOPSIS
        Benchmark gzip compression.
    #>
    param(
        [string]$InputFile,
        [string]$OutputDir
    )
    
    Write-Host "`n[BENCHMARK] Compression" -ForegroundColor Yellow
    
    if (-not (Test-Path $InputFile)) {
        Write-Warning "Input file not found: $InputFile"
        return $null
    }
    
    if (-not (Get-Command Compress-OutputFile -ErrorAction SilentlyContinue)) {
        Write-Warning "Compression utilities not available"
        return $null
    }
    
    $originalSize = (Get-Item $InputFile).Length
    $outputPath = Join-Path $OutputDir "compressed-test.json.gz"
    
    [GC]::Collect()
    $startTime = Get-Date
    
    $compressResult = Compress-OutputFile -InputPath $InputFile -OutputPath $outputPath
    
    $endTime = Get-Date
    
    $result = @{
        OriginalSizeMB = [math]::Round($originalSize / 1MB, 2)
        CompressedSizeMB = [math]::Round($compressResult.CompressedSizeBytes / 1MB, 2)
        CompressionRatio = $compressResult.CompressionRatio
        DurationMs = [math]::Round(($endTime - $startTime).TotalMilliseconds, 2)
    }
    
    Write-Host "  Original: $($result.OriginalSizeMB)MB -> Compressed: $($result.CompressedSizeMB)MB ($($result.CompressionRatio)%)" -ForegroundColor Green
    
    return $result
}

# ============================================================================
# Main Benchmark Runner
# ============================================================================

function Run-PerfHarness {
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "  SimTreeNav Performance Test Harness" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor White
    Write-Host "  Node Count: $($config.NodeCount.ToString('N0'))" -ForegroundColor Gray
    Write-Host "  Max Depth: $($config.MaxDepth)" -ForegroundColor Gray
    Write-Host "  Branching Factor: $($config.BranchingFactor)" -ForegroundColor Gray
    Write-Host "  Output Directory: $($config.OutputDir)" -ForegroundColor Gray
    Write-Host ""
    
    # Create output directory
    if (-not (Test-Path $config.OutputDir)) {
        New-Item -ItemType Directory -Path $config.OutputDir | Out-Null
    }
    
    $allResults = @{
        Config = $config
        StartTime = (Get-Date).ToString("o")
        Benchmarks = @{}
    }
    
    # Generate synthetic data
    $treeData = New-SyntheticTree `
        -NodeCount $config.NodeCount `
        -MaxDepth $config.MaxDepth `
        -BranchingFactor $config.BranchingFactor
    
    $allResults.Benchmarks["DataGeneration"] = @{
        NodeCount = $treeData.Nodes.Count
        DurationMs = $treeData.GenerationTimeMs
        MemoryUsedMB = $treeData.MemoryUsedMB
        ActualDepth = $treeData.ActualDepth
    }
    
    # Write synthetic data to file
    Write-Host "`n[PERF HARNESS] Writing synthetic data file..." -ForegroundColor Cyan
    $dataFile = Join-Path $config.OutputDir "synthetic-tree-data.txt"
    $lines = ConvertTo-TreeDataFormat -Nodes $treeData.Nodes
    $lines | Out-File $dataFile -Encoding UTF8
    $dataFileSizeMB = [math]::Round((Get-Item $dataFile).Length / 1MB, 2)
    Write-Host "  Data file: ${dataFileSizeMB}MB" -ForegroundColor Green
    
    # Benchmark snapshot generation
    $snapshotResult = Measure-SnapshotGeneration `
        -DataFile $dataFile `
        -OutputDir $config.OutputDir `
        -NodeCount $treeData.Nodes.Count
    
    if ($snapshotResult) {
        $allResults.Benchmarks["SnapshotGeneration"] = $snapshotResult
    }
    
    # Benchmark JSON export
    if ($config.RunExport) {
        $exportResults = Measure-JsonExport `
            -Nodes $treeData.Nodes `
            -OutputDir $config.OutputDir
        
        $allResults.Benchmarks["JsonExport"] = $exportResults
        
        # Benchmark compression
        $jsonFile = Join-Path $config.OutputDir "nodes-standard.json"
        if (Test-Path $jsonFile) {
            $compressionResult = Measure-Compression `
                -InputFile $jsonFile `
                -OutputDir $config.OutputDir
            
            if ($compressionResult) {
                $allResults.Benchmarks["Compression"] = $compressionResult
            }
        }
    }
    
    # Summary
    $allResults.EndTime = (Get-Date).ToString("o")
    $totalDuration = [math]::Round(((Get-Date) - [datetime]::Parse($allResults.StartTime)).TotalSeconds, 2)
    $allResults.TotalDurationSec = $totalDuration
    
    Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
    Write-Host "  BENCHMARK SUMMARY" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Node Count: $($treeData.Nodes.Count.ToString('N0'))" -ForegroundColor White
    Write-Host "Total Time: ${totalDuration}s" -ForegroundColor White
    Write-Host ""
    
    if ($snapshotResult) {
        $snapshotStatus = if ($snapshotResult.DurationSec -lt 30 -and $snapshotResult.PeakMemoryMB -lt 500) { 
            "PASS" 
        } else { 
            "WARN" 
        }
        $statusColor = if ($snapshotStatus -eq "PASS") { "Green" } else { "Yellow" }
        Write-Host "Snapshot Generation: [$snapshotStatus]" -ForegroundColor $statusColor
        Write-Host "  Time: $($snapshotResult.DurationSec)s (target: <30s)" -ForegroundColor Gray
        Write-Host "  Memory: $($snapshotResult.PeakMemoryMB)MB (target: <500MB)" -ForegroundColor Gray
    }
    
    # Write results to file
    $resultsFile = Join-Path $config.OutputDir "benchmark-results.json"
    $allResults | ConvertTo-Json -Depth 5 | Out-File $resultsFile -Encoding UTF8
    Write-Host "`nResults saved to: $resultsFile" -ForegroundColor Cyan
    
    # Check against budget
    Write-Host "`n" + ("-" * 60) -ForegroundColor Gray
    Write-Host "Budget Check (see docs/PERFORMANCE-BUDGET.md):" -ForegroundColor White
    
    $budgetChecks = @(
        @{ Name = "50k nodes snapshot"; Target = 30; Actual = $snapshotResult.DurationSec; Unit = "seconds"; Pass = $snapshotResult.DurationSec -lt 30 },
        @{ Name = "50k nodes memory"; Target = 500; Actual = $snapshotResult.PeakMemoryMB; Unit = "MB"; Pass = $snapshotResult.PeakMemoryMB -lt 500 }
    )
    
    foreach ($check in $budgetChecks) {
        $status = if ($check.Pass) { "[PASS]" } else { "[FAIL]" }
        $color = if ($check.Pass) { "Green" } else { "Red" }
        Write-Host "  $status $($check.Name): $($check.Actual)$($check.Unit) (target: <$($check.Target)$($check.Unit))" -ForegroundColor $color
    }
    
    return $allResults
}

# Run the harness
$results = Run-PerfHarness

Write-Host "`n[PERF HARNESS] Complete!" -ForegroundColor Green
