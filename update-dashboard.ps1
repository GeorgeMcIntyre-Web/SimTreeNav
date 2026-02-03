<#
.SYNOPSIS
    Unified dashboard update script with smart mode detection.

.DESCRIPTION
    Single script to update the management dashboard with automatic mode detection.
    Supports three modes:
    - Fast: Tree changes only (2-5 seconds)
    - Full: Complete database refresh + tree changes (30-60 seconds)
    - Instant: Regenerate dashboard from existing data (2 seconds)

.PARAMETER Mode
    Update mode: Fast, Full, or Instant. If not specified, auto-detects based on data freshness.

.PARAMETER TNSName
    Oracle TNS name to connect to. If not specified, uses default from config/servers.json.

.PARAMETER Schema
    Oracle schema name. If not specified, uses DESIGN12.

.PARAMETER ProjectId
    Project ID to query. If not specified, uses 18851221.

.PARAMETER StudyId
    Study ID for tree tracking. If not specified, auto-detects from Process Simulate.

.PARAMETER ForceRefresh
    Force full database refresh, bypassing cache.

.PARAMETER NoOpen
    Don't automatically open the dashboard in browser after generation.

.EXAMPLE
    .\update-dashboard.ps1
    Auto-detects mode and uses default settings

.EXAMPLE
    .\update-dashboard.ps1 -Mode Fast
    Quick tree-only update

.EXAMPLE
    .\update-dashboard.ps1 -Mode Full -TNSName PSPDV3
    Full refresh from PSPDV3 server

.EXAMPLE
    .\update-dashboard.ps1 -Mode Instant
    Just regenerate HTML from existing data

.NOTES
    File Name  : update-dashboard.ps1
    Author     : Management Dashboard
    Requires   : PowerShell 5.1+, Process Simulate COM API (for tree updates)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet('Fast', 'Full', 'Instant')]
    [string]$Mode,

    [Parameter(Mandatory=$false)]
    [string]$TNSName,

    [Parameter(Mandatory=$false)]
    [string]$Schema,

    [Parameter(Mandatory=$false)]
    [int]$ProjectId = 0,

    [Parameter(Mandatory=$false)]
    [int]$StudyId,

    [Parameter(Mandatory=$false)]
    [DateTime]$StartDate,

    [Parameter(Mandatory=$false)]
    [DateTime]$EndDate,

    [Parameter(Mandatory=$false)]
    [switch]$ForceRefresh,

    [Parameter(Mandatory=$false)]
    [switch]$SkipTreeSnapshots,

    [Parameter(Mandatory=$false)]
    [int]$TreeSnapshotLimit = 25,

    [Parameter(Mandatory=$false)]
    [int]$TreeSnapshotErrorLimit = 5,

    [Parameter(Mandatory=$false)]
    [switch]$NoOpen
)

# Oracle managed driver is reliable under Windows PowerShell (Full .NET).
# If launched from PowerShell 7+, re-run under Windows PowerShell automatically.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $windowsPs = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    if (Test-Path $windowsPs) {
        Write-Host "PowerShell 7 detected. Relaunching with Windows PowerShell for Oracle driver compatibility..." -ForegroundColor Yellow

        $forwardArgs = @()
        foreach ($key in $PSBoundParameters.Keys) {
            $value = $PSBoundParameters[$key]
            $paramName = "-$key"

            if ($value -is [System.Management.Automation.SwitchParameter]) {
                if ($value.IsPresent) {
                    $forwardArgs += $paramName
                }
            } elseif ($value -is [DateTime]) {
                $forwardArgs += @($paramName, $value.ToString("yyyy-MM-dd"))
            } else {
                $forwardArgs += @($paramName, $value)
            }
        }

        $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath) + $forwardArgs
        $proc = Start-Process -FilePath $windowsPs -ArgumentList $argList -NoNewWindow -Wait -PassThru
        exit $proc.ExitCode
    } else {
        Write-Warning "Windows PowerShell not found at expected path: $windowsPs"
    }
}

# Script root and paths
$ScriptRoot = $PSScriptRoot
$DataOutputDir = Join-Path $ScriptRoot "data\output"
$SnapshotDir = Join-Path $ScriptRoot "data\tree-snapshots"
$CacheDir = Join-Path $ScriptRoot "cache"
$ConfigDir = Join-Path $ScriptRoot "config"

# Start overall timer
$overallTimer = [System.Diagnostics.Stopwatch]::StartNew()

# Display banner
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  DASHBOARD UPDATE" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Load enterprise configuration for defaults
$enterpriseConfigPath = Join-Path $ConfigDir "enterprise-config.json"
if (Test-Path $enterpriseConfigPath) {
    $enterpriseConfig = Get-Content $enterpriseConfigPath -Raw | ConvertFrom-Json

    # Apply defaults if not specified
    if ([string]::IsNullOrWhiteSpace($TNSName)) {
        $TNSName = $enterpriseConfig.defaults.tnsName
    }

    if ([string]::IsNullOrWhiteSpace($Schema)) {
        $Schema = $enterpriseConfig.defaults.schema
    }

    if ($ProjectId -eq 0) {
        $ProjectId = $enterpriseConfig.defaults.projectId
    }

    if ($StudyId -eq 0 -and $enterpriseConfig.defaults.PSObject.Properties.Name -contains 'studyId') {
        $StudyId = $enterpriseConfig.defaults.studyId
    }
} else {
    # Fallback hardcoded defaults if config not found
    if ([string]::IsNullOrWhiteSpace($TNSName)) { $TNSName = "PSPDV3" }
    if ([string]::IsNullOrWhiteSpace($Schema)) { $Schema = "DESIGN12" }
    if ($ProjectId -eq 0) { $ProjectId = 18851221 }
    if ($StudyId -eq 0) { $StudyId = 18879453 }
}

# Load server configuration
try {
    $serverConfigPath = Join-Path $ConfigDir "servers.json"
    if (-not (Test-Path $serverConfigPath)) {
        Write-Warning "Server configuration not found: $serverConfigPath"
        Write-Host "Using default TNS name: $TNSName"
    } else {
        $serverConfig = Get-Content $serverConfigPath -Raw | ConvertFrom-Json

        if ([string]::IsNullOrWhiteSpace($TNSName)) {
            $TNSName = $serverConfig.defaultServer
            Write-Host "Using default server: $TNSName" -ForegroundColor Gray
        }

        # Get server details
        $selectedServer = $serverConfig.servers | Where-Object { $_.name -eq $TNSName -or $_.tns -eq $TNSName }
        if ($selectedServer) {
            Write-Host "Server: $($selectedServer.description)" -ForegroundColor Gray
        }
    }
} catch {
    Write-Warning "Failed to load server configuration: $_"
}

# Validate TNS name is set
if ([string]::IsNullOrWhiteSpace($TNSName)) {
    Write-Error "TNS name not specified and no default found in configuration."
    Write-Host "`nPlease specify -TNSName parameter or configure default in config/servers.json`n" -ForegroundColor Yellow
    exit 1
}

Write-Host "Schema:     $Schema" -ForegroundColor Gray
Write-Host "Project ID: $ProjectId" -ForegroundColor Gray

# Determine mode if not specified
if ([string]::IsNullOrWhiteSpace($Mode)) {
    Write-Host "`n[Auto-Detecting Mode]" -ForegroundColor Cyan

    # Check if baseline exists
    $hasBaseline = $false
    if (Test-Path $SnapshotDir) {
        $baselineFiles = Get-ChildItem -Path $SnapshotDir -Filter "*-baseline.json"
        $hasBaseline = $baselineFiles.Count -gt 0
    }

    # Check data freshness
    $dataFile = Join-Path $DataOutputDir "management-data-${Schema}-${ProjectId}.json"
    $dataAge = if (Test-Path $dataFile) {
        $lastModified = (Get-Item $dataFile).LastWriteTime
        $age = (Get-Date) - $lastModified
        $age.TotalHours
    } else {
        999  # Very old if doesn't exist
    }

    # Decision logic
    if (-not $hasBaseline) {
        Write-Host "No baseline found - run setup-baseline.ps1 first" -ForegroundColor Yellow
        Write-Host "`nTo create a baseline, run:" -ForegroundColor White
        Write-Host "  .\setup-baseline.ps1`n" -ForegroundColor Cyan
        exit 1
    } elseif ($dataAge -gt 24) {
        $Mode = "Full"
        Write-Host "Data is stale ($([math]::Round($dataAge, 1)) hours old) - using Full mode" -ForegroundColor Yellow
    } elseif ($dataAge -lt 0.1) {
        $Mode = "Instant"
        Write-Host "Data is very fresh - using Instant mode" -ForegroundColor Green
    } else {
        $Mode = "Fast"
        Write-Host "Data is recent ($([math]::Round($dataAge, 1)) hours old) - using Fast mode" -ForegroundColor Green
    }
}

Write-Host "Mode:       $Mode" -ForegroundColor Cyan
Write-Host ""

# Step tracking
$steps = @{
    "Instant" = @("Regenerate Dashboard")
    "Fast" = @("Export Tree Snapshot", "Compare with Baseline", "Update Management Data", "Regenerate Dashboard", "Cleanup Old Files")
    "Full" = @("Query Database", "Export Tree Snapshot", "Compare with Baseline", "Regenerate Dashboard", "Cleanup Old Files")
}

$currentStep = 0
$totalSteps = $steps[$Mode].Count

function Show-Progress {
    param([string]$StepName, [string]$Status = "In Progress")

    $script:currentStep++
    $percent = [math]::Round(($script:currentStep / $script:totalSteps) * 100)

    Write-Host "[$script:currentStep/$script:totalSteps] $StepName... " -NoNewline -ForegroundColor White
    if ($Status -eq "In Progress") {
        Write-Host "" # Newline for in-progress messages
    }
}

function Show-StepResult {
    param([string]$Message, [string]$Status = "Success")

    $color = switch ($Status) {
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        default { "White" }
    }

    Write-Host "$Message" -ForegroundColor $color
}

# Execute based on mode
try {
    switch ($Mode) {
        "Instant" {
            # Just regenerate dashboard from existing data
            Show-Progress "Regenerate Dashboard"

            $dataFile = Join-Path $DataOutputDir "management-data-${Schema}-${ProjectId}.json"
            if (-not (Test-Path $dataFile)) {
                throw "Data file not found: $dataFile. Run with -Mode Full first."
            }

            $dashboardScript = Join-Path $ScriptRoot "scripts\generate-management-dashboard.ps1"
            & $dashboardScript -DataFile $dataFile

            if ($LASTEXITCODE -ne 0) {
                throw "Dashboard generation failed"
            }

            Show-StepResult "Dashboard regenerated" "Success"
        }

        "Fast" {
            # Tree changes only
            Show-Progress "Export Tree Snapshot"

            $exportScript = Join-Path $ScriptRoot "scripts\debug\export-study-tree-snapshot.ps1"
            if ($StudyId) {
                & $exportScript -TNSName $TNSName -Schema $Schema -ProjectId $ProjectId -StudyId $StudyId
            } else {
                & $exportScript -TNSName $TNSName -Schema $Schema -ProjectId $ProjectId
            }

            if ($LASTEXITCODE -ne 0) {
                throw "Tree snapshot export failed"
            }

            # Copy latest snapshot to current.json
            $latestSnapshot = Get-ChildItem -Path (Join-Path $ScriptRoot "data\output") -Filter "study-tree-snapshot-$Schema-$StudyId-*.json" |
                              Sort-Object LastWriteTime -Descending | Select-Object -First 1

            if ($latestSnapshot) {
                $currentFile = Join-Path $SnapshotDir "study-$StudyId-current.json"
                Copy-Item $latestSnapshot.FullName $currentFile -Force
            }

            Show-StepResult "Snapshot exported" "Success"

            # Compare with baseline
            Show-Progress "Compare with Baseline"

            $compareScript = Join-Path $ScriptRoot "scripts\debug\compare-study-tree-snapshots.ps1"
            $baselineFile = Join-Path $SnapshotDir "study-$StudyId-baseline.json"
            $currentFile = Join-Path $SnapshotDir "study-$StudyId-current.json"
            $diffFile = Join-Path $SnapshotDir "study-$StudyId-diff.json"

            & $compareScript -BaselineSnapshot $baselineFile -CurrentSnapshot $currentFile -OutputFile $diffFile

            if ($LASTEXITCODE -ne 0) {
                throw "Tree comparison failed"
            }

            Show-StepResult "Changes detected" "Success"

            # Update management data with tree changes (quick update)
            Show-Progress "Update Management Data"

            $dataFile = Join-Path $DataOutputDir "management-data-${Schema}-${ProjectId}.json"

            # Read existing data
            if (Test-Path $dataFile) {
                $data = Get-Content $dataFile -Raw | ConvertFrom-Json

                # Find latest diff file
                $diffFiles = Get-ChildItem -Path $SnapshotDir -Filter "*-diff.json" | Sort-Object LastWriteTime -Descending
                if ($diffFiles.Count -gt 0) {
                    $diffData = Get-Content $diffFiles[0].FullName -Raw | ConvertFrom-Json

                    # Update tree changes in management data
                    $data.treeChanges = $diffData.changes.moved + $diffData.changes.renamed + `
                                        $diffData.changes.structuralChanges + $diffData.changes.nodesAdded + `
                                        $diffData.changes.nodesRemoved

                    # Update metadata (using Add-Member to add properties if they don't exist)
                    $data.metadata | Add-Member -NotePropertyName "lastTreeUpdate" -NotePropertyValue (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') -Force
                    $data.metadata | Add-Member -NotePropertyName "treeChangeCount" -NotePropertyValue $diffData.meta.totalChanges -Force
                    $data.metadata | Add-Member -NotePropertyName "tnsName" -NotePropertyValue $TNSName -Force
                    $data.metadata | Add-Member -NotePropertyName "serverDescription" -NotePropertyValue $(if ($selectedServer) { $selectedServer.description } else { $TNSName }) -Force

                    # Save updated data
                    $data | ConvertTo-Json -Depth 10 | Set-Content $dataFile -Encoding UTF8

                    Show-StepResult "Management data updated ($($diffData.meta.totalChanges) changes)" "Success"
                } else {
                    Show-StepResult "No diff file found - skipping update" "Warning"
                }
            } else {
                Show-StepResult "No existing data file - use Full mode" "Warning"
            }

            # Regenerate dashboard
            Show-Progress "Regenerate Dashboard"

            $dashboardScript = Join-Path $ScriptRoot "scripts\generate-management-dashboard.ps1"
            & $dashboardScript -DataFile $dataFile

            if ($LASTEXITCODE -ne 0) {
                throw "Dashboard generation failed"
            }

            Show-StepResult "Dashboard regenerated" "Success"

            # Cleanup old files
            Show-Progress "Cleanup Old Files"

            # Keep only last 5 timestamped snapshots
            $timestampedSnapshots = Get-ChildItem -Path $SnapshotDir -Filter "*-202*.json" |
                                    Where-Object { $_.Name -notmatch "(baseline|current|diff)\.json$" } |
                                    Sort-Object LastWriteTime -Descending

            if ($timestampedSnapshots.Count -gt 5) {
                $toDelete = $timestampedSnapshots | Select-Object -Skip 5
                $toDelete | Remove-Item -Force
                Show-StepResult "Cleaned up $($toDelete.Count) old snapshots" "Success"
            } else {
                Show-StepResult "No cleanup needed" "Success"
            }
        }

        "Full" {
            # Complete database refresh
            Show-Progress "Query Database"

            $getDataScript = Join-Path $ScriptRoot "src\powershell\main\get-management-data.ps1"
            $dataFile = Join-Path $DataOutputDir "management-data-${Schema}-${ProjectId}.json"

            # Run get-management-data script (handles credentials internally)
            $dataParams = @{
                TNSName = $TNSName
                Schema = $Schema
                ProjectId = $ProjectId
                OutputFile = $dataFile
            }

            if ($PSBoundParameters.ContainsKey('StartDate')) {
                $dataParams.StartDate = $StartDate
            }
            if ($PSBoundParameters.ContainsKey('EndDate')) {
                $dataParams.EndDate = $EndDate
            }
            if ($ForceRefresh) {
                $dataParams.ForceRefresh = $true
            }
            if ($PSBoundParameters.ContainsKey('SkipTreeSnapshots')) {
                $dataParams.SkipTreeSnapshots = $true
            }
            if ($PSBoundParameters.ContainsKey('TreeSnapshotLimit')) {
                $dataParams.TreeSnapshotLimit = $TreeSnapshotLimit
            }
            if ($PSBoundParameters.ContainsKey('TreeSnapshotErrorLimit')) {
                $dataParams.TreeSnapshotErrorLimit = $TreeSnapshotErrorLimit
            }

            & $getDataScript @dataParams

            if ($LASTEXITCODE -ne 0) {
                throw "Database query failed"
            }

            Show-StepResult "Database queried successfully" "Success"

            # Export tree snapshot
            Show-Progress "Export Tree Snapshot"

            $exportScript = Join-Path $ScriptRoot "scripts\debug\export-study-tree-snapshot.ps1"
            if ($StudyId) {
                & $exportScript -TNSName $TNSName -Schema $Schema -ProjectId $ProjectId -StudyId $StudyId
            } else {
                & $exportScript -TNSName $TNSName -Schema $Schema -ProjectId $ProjectId
            }

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "Tree snapshot export failed - continuing without tree data"
            } else {
                # Copy latest snapshot to current.json
                $latestSnapshot = Get-ChildItem -Path (Join-Path $ScriptRoot "data\output") -Filter "study-tree-snapshot-$Schema-$StudyId-*.json" |
                                  Sort-Object LastWriteTime -Descending | Select-Object -First 1

                if ($latestSnapshot) {
                    $currentFile = Join-Path $SnapshotDir "study-$StudyId-current.json"
                    Copy-Item $latestSnapshot.FullName $currentFile -Force
                }

                Show-StepResult "Snapshot exported" "Success"

                # Compare with baseline
                Show-Progress "Compare with Baseline"

                $compareScript = Join-Path $ScriptRoot "scripts\debug\compare-study-tree-snapshots.ps1"
                $baselineFile = Join-Path $SnapshotDir "study-$StudyId-baseline.json"
                $currentFile = Join-Path $SnapshotDir "study-$StudyId-current.json"
                $diffFile = Join-Path $SnapshotDir "study-$StudyId-diff.json"

                & $compareScript -BaselineSnapshot $baselineFile -CurrentSnapshot $currentFile -OutputFile $diffFile

                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "Tree comparison failed - continuing without diff"
                } else {
                    Show-StepResult "Changes detected" "Success"
                }
            }

            # Regenerate dashboard
            Show-Progress "Regenerate Dashboard"

            $dashboardScript = Join-Path $ScriptRoot "scripts\generate-management-dashboard.ps1"
            & $dashboardScript -DataFile $dataFile

            if ($LASTEXITCODE -ne 0) {
                throw "Dashboard generation failed"
            }

            Show-StepResult "Dashboard generated" "Success"

            # Cleanup old files
            Show-Progress "Cleanup Old Files"

            # Keep only last 5 timestamped snapshots
            if (Test-Path $SnapshotDir) {
                $timestampedSnapshots = Get-ChildItem -Path $SnapshotDir -Filter "*-202*.json" |
                                        Where-Object { $_.Name -notmatch "(baseline|current|diff)\.json$" } |
                                        Sort-Object LastWriteTime -Descending

                if ($timestampedSnapshots.Count -gt 5) {
                    $toDelete = $timestampedSnapshots | Select-Object -Skip 5
                    $toDelete | Remove-Item -Force
                    Show-StepResult "Cleaned up $($toDelete.Count) old snapshots" "Success"
                } else {
                    Show-StepResult "No cleanup needed" "Success"
                }
            }
        }
    }

    # Stop timer
    $overallTimer.Stop()

    # Summary
    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  UPDATE COMPLETE!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Mode:     $Mode" -ForegroundColor White
    Write-Host "Duration: $([math]::Round($overallTimer.Elapsed.TotalSeconds, 1))s" -ForegroundColor White
    Write-Host ""

    # Open dashboard
    if (-not $NoOpen) {
        $dashboardFile = Join-Path $ScriptRoot "management-dashboard-${Schema}-${ProjectId}.html"
        if (Test-Path $dashboardFile) {
            Write-Host "Opening dashboard in browser..." -ForegroundColor Cyan
            Start-Process $dashboardFile
        } else {
            Write-Warning "Dashboard file not found: $dashboardFile"
        }
    }

    Write-Host ""
    exit 0

} catch {
    $overallTimer.Stop()

    Write-Host "`n========================================" -ForegroundColor Red
    Write-Host "  UPDATE FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Duration: $([math]::Round($overallTimer.Elapsed.TotalSeconds, 1))s" -ForegroundColor Gray
    Write-Host ""

    exit 1
}
