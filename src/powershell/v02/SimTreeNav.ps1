# SimTreeNav.ps1
# Main entry point for SimTreeNav v0.2
# Supports: Tree (legacy), Snapshot, Diff, Watch modes

<#
.SYNOPSIS
    SimTreeNav v0.2 - Tree navigation and change tracking for Process Simulate databases.

.DESCRIPTION
    Modes:
    - Tree: Generate interactive HTML tree viewer (legacy behavior)
    - Snapshot: Create a point-in-time snapshot of the tree
    - Diff: Compare two snapshots and generate diff report
    - Watch: Continuous monitoring with automatic snapshots

.EXAMPLE
    # Generate HTML tree (legacy mode)
    .\SimTreeNav.ps1 -Mode Tree -TNSName "DB01" -Schema "DESIGN12" -ProjectId "18140190"

.EXAMPLE
    # Create a snapshot
    .\SimTreeNav.ps1 -Mode Snapshot -TNSName "DB01" -Schema "DESIGN12" -ProjectId "18140190" -Label "baseline"

.EXAMPLE
    # Compare two snapshots
    .\SimTreeNav.ps1 -Mode Diff -BaselinePath "./snapshots/20260115_100000_baseline" -CurrentPath "./snapshots/20260115_110000_current"

.EXAMPLE
    # Start watch mode
    .\SimTreeNav.ps1 -Mode Watch -TNSName "DB01" -Schema "DESIGN12" -ProjectId "18140190" -IntervalSeconds 300
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Tree', 'Snapshot', 'Diff', 'Watch', 'Interactive')]
    [string]$Mode,
    
    # Connection parameters (for Tree, Snapshot, Watch)
    [string]$TNSName = '',
    [string]$Schema = '',
    [string]$ProjectId = '',
    [string]$ProjectName = '',
    
    # Snapshot parameters
    [string]$OutDir = './snapshots',
    [string]$Label = 'snapshot',
    [switch]$IncludeEdges,
    
    # Diff parameters
    [string]$BaselinePath = '',
    [string]$CurrentPath = '',
    [string]$DiffOutputPath = '',
    [switch]$GenerateHtml,
    
    # Watch parameters
    [int]$IntervalSeconds = 300,
    [int]$MaxSnapshots = 100,
    
    # Common parameters
    [string]$ConfigFile = '',
    [switch]$Pretty
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# Banner
function Show-Banner {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "  ║                                                   ║" -ForegroundColor Cyan
    Write-Host "  ║   SimTreeNav v0.2                                 ║" -ForegroundColor Cyan
    Write-Host "  ║   Tree Navigation & Change Tracking               ║" -ForegroundColor Cyan
    Write-Host "  ║                                                   ║" -ForegroundColor Cyan
    Write-Host "  ╚═══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

# Load configuration
function Get-Config {
    param([string]$Path)
    
    if (-not $Path) {
        $Path = Join-Path $scriptRoot '..\..\..\config\simtreenav.config.json'
    }
    
    if (Test-Path $Path) {
        try {
            return Get-Content $Path -Raw | ConvertFrom-Json
        } catch {
            Write-Warning "Failed to load config: $_"
        }
    }
    
    return $null
}

# Mode: Tree (legacy HTML generation)
function Invoke-TreeMode {
    param($Config)
    
    if (-not $TNSName -or -not $Schema -or -not $ProjectId) {
        Write-Error "Tree mode requires -TNSName, -Schema, and -ProjectId parameters"
        return
    }
    
    Write-Host "  Mode: Tree (HTML Generation)" -ForegroundColor Yellow
    Write-Host ""
    
    # Call legacy generator
    $legacyScript = Join-Path $scriptRoot '..\main\generate-tree-html.ps1'
    if (-not (Test-Path $legacyScript)) {
        Write-Error "Legacy tree generator not found: $legacyScript"
        return
    }
    
    $outputFile = "navigation-tree-${Schema}-${ProjectId}.html"
    $name = if ($ProjectName) { $ProjectName } else { "Project_$ProjectId" }
    
    & $legacyScript -TNSName $TNSName -Schema $Schema -ProjectId $ProjectId -ProjectName $name -OutputFile $outputFile
    
    if (Test-Path $outputFile) {
        Write-Host ""
        Write-Host "  Tree generated: $outputFile" -ForegroundColor Green
        Start-Process $outputFile
    }
}

# Mode: Snapshot
function Invoke-SnapshotMode {
    param($Config)
    
    if (-not $TNSName -or -not $Schema -or -not $ProjectId) {
        Write-Error "Snapshot mode requires -TNSName, -Schema, and -ProjectId parameters"
        return
    }
    
    Write-Host "  Mode: Snapshot" -ForegroundColor Yellow
    Write-Host ""
    
    $snapshotScript = Join-Path $scriptRoot 'snapshot\New-Snapshot.ps1'
    if (-not (Test-Path $snapshotScript)) {
        Write-Error "Snapshot script not found: $snapshotScript"
        return
    }
    
    $params = @{
        TNSName     = $TNSName
        Schema      = $Schema
        ProjectId   = $ProjectId
        OutDir      = $OutDir
        Label       = $Label
    }
    
    if ($ProjectName) { $params['ProjectName'] = $ProjectName }
    if ($IncludeEdges) { $params['IncludeEdges'] = $true }
    if ($Pretty) { $params['Pretty'] = $true }
    if ($ConfigFile) { $params['ConfigFile'] = $ConfigFile }
    
    & $snapshotScript @params
}

# Mode: Diff
function Invoke-DiffMode {
    param($Config)
    
    if (-not $BaselinePath -or -not $CurrentPath) {
        Write-Error "Diff mode requires -BaselinePath and -CurrentPath parameters"
        return
    }
    
    Write-Host "  Mode: Diff" -ForegroundColor Yellow
    Write-Host ""
    
    $diffScript = Join-Path $scriptRoot 'diff\Compare-Snapshots.ps1'
    if (-not (Test-Path $diffScript)) {
        Write-Error "Diff script not found: $diffScript"
        return
    }
    
    $params = @{
        BaselinePath = $BaselinePath
        CurrentPath  = $CurrentPath
    }
    
    if ($DiffOutputPath) { $params['OutputPath'] = $DiffOutputPath }
    if ($GenerateHtml) { $params['GenerateHtml'] = $true }
    if ($Pretty) { $params['Pretty'] = $true }
    
    & $diffScript @params
}

# Mode: Watch (continuous monitoring)
function Invoke-WatchMode {
    param($Config)
    
    if (-not $TNSName -or -not $Schema -or -not $ProjectId) {
        Write-Error "Watch mode requires -TNSName, -Schema, and -ProjectId parameters"
        return
    }
    
    Write-Host "  Mode: Watch (Continuous Monitoring)" -ForegroundColor Yellow
    Write-Host "  Interval: $IntervalSeconds seconds" -ForegroundColor Gray
    Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
    Write-Host ""
    
    $snapshotScript = Join-Path $scriptRoot 'snapshot\New-Snapshot.ps1'
    $diffScript = Join-Path $scriptRoot 'diff\Compare-Snapshots.ps1'
    
    if (-not (Test-Path $snapshotScript)) {
        Write-Error "Snapshot script not found: $snapshotScript"
        return
    }
    
    # Create timeline index
    $timelineFile = Join-Path $OutDir 'timeline.json'
    $timeline = @{
        version = '0.2.0'
        projectId = $ProjectId
        schema = $Schema
        entries = @()
    }
    
    $previousSnapshot = $null
    $snapshotCount = 0
    
    try {
        while ($true) {
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Write-Host "[$timestamp] Taking snapshot..." -ForegroundColor Cyan
            
            # Take snapshot
            $snapshotParams = @{
                TNSName   = $TNSName
                Schema    = $Schema
                ProjectId = $ProjectId
                OutDir    = $OutDir
                Label     = "watch_$snapshotCount"
            }
            if ($Pretty) { $snapshotParams['Pretty'] = $true }
            
            $currentSnapshot = & $snapshotScript @snapshotParams
            
            if (-not $currentSnapshot) {
                Write-Warning "Snapshot failed, retrying in $IntervalSeconds seconds..."
                Start-Sleep -Seconds $IntervalSeconds
                continue
            }
            
            # Compare with previous if exists
            if ($previousSnapshot -and (Test-Path $diffScript)) {
                Write-Host "  Comparing with previous snapshot..." -ForegroundColor Gray
                
                $diffParams = @{
                    BaselinePath = $previousSnapshot.Path
                    CurrentPath  = $currentSnapshot.Path
                    OutputPath   = Join-Path $OutDir "diff_$snapshotCount"
                    GenerateHtml = $true
                }
                if ($Pretty) { $diffParams['Pretty'] = $true }
                
                $diff = & $diffScript @diffParams
                
                if ($diff -and $diff.summary.totalChanges -gt 0) {
                    Write-Host "  Changes detected: $($diff.summary.totalChanges)" -ForegroundColor Yellow
                }
            }
            
            # Update timeline
            $timeline.entries += @{
                timestamp = (Get-Date).ToUniversalTime().ToString('o')
                snapshotPath = $currentSnapshot.Path
                nodeCount = $currentSnapshot.NodeCount
                changeCount = if ($diff) { $diff.summary.totalChanges } else { 0 }
            }
            
            # Save timeline
            $timeline | ConvertTo-Json -Depth 10 | Set-Content -Path $timelineFile -Encoding UTF8
            
            # Cleanup old snapshots if exceeding max
            if ($MaxSnapshots -gt 0 -and $timeline.entries.Count -gt $MaxSnapshots) {
                $toRemove = $timeline.entries | Select-Object -First ($timeline.entries.Count - $MaxSnapshots)
                foreach ($entry in $toRemove) {
                    if (Test-Path $entry.snapshotPath) {
                        Write-Host "  Cleaning up old snapshot: $($entry.snapshotPath)" -ForegroundColor DarkGray
                        Remove-Item $entry.snapshotPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
                $timeline.entries = $timeline.entries | Select-Object -Last $MaxSnapshots
            }
            
            $previousSnapshot = $currentSnapshot
            $snapshotCount++
            
            Write-Host "  Waiting $IntervalSeconds seconds..." -ForegroundColor Gray
            Write-Host ""
            Start-Sleep -Seconds $IntervalSeconds
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
        Write-Host ""
        Write-Host "  Watch mode stopped by user." -ForegroundColor Yellow
    }
    finally {
        # Save final timeline
        $timeline | ConvertTo-Json -Depth 10 | Set-Content -Path $timelineFile -Encoding UTF8
        Write-Host "  Timeline saved: $timelineFile" -ForegroundColor Gray
    }
}

# Mode: Interactive (menu-driven)
function Invoke-InteractiveMode {
    param($Config)
    
    Write-Host "  Mode: Interactive" -ForegroundColor Yellow
    Write-Host ""
    
    # Check if v2 launcher exists
    $launcherV2 = Join-Path $scriptRoot '..\main\tree-viewer-launcher-v2.ps1'
    $launcher = Join-Path $scriptRoot '..\main\tree-viewer-launcher.ps1'
    
    if (Test-Path $launcherV2) {
        & $launcherV2
    } elseif (Test-Path $launcher) {
        & $launcher
    } else {
        Write-Host "  No interactive launcher found." -ForegroundColor Red
        Write-Host ""
        Write-Host "  Available modes:" -ForegroundColor Yellow
        Write-Host "    -Mode Tree      Generate HTML tree viewer" -ForegroundColor White
        Write-Host "    -Mode Snapshot  Create point-in-time snapshot" -ForegroundColor White
        Write-Host "    -Mode Diff      Compare two snapshots" -ForegroundColor White
        Write-Host "    -Mode Watch     Continuous monitoring" -ForegroundColor White
    }
}

# Main entry point
Show-Banner

$config = Get-Config -Path $ConfigFile

switch ($Mode) {
    'Tree'        { Invoke-TreeMode -Config $config }
    'Snapshot'    { Invoke-SnapshotMode -Config $config }
    'Diff'        { Invoke-DiffMode -Config $config }
    'Watch'       { Invoke-WatchMode -Config $config }
    'Interactive' { Invoke-InteractiveMode -Config $config }
}

Write-Host ""
