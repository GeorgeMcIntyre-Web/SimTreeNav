# Demo.ps1
# SimTreeNav v0.3+ Demo - Full feature demonstration without database
# Demonstrates: All analysis engines, identity resolution, offline bundle

<#
.SYNOPSIS
    Demonstrates all SimTreeNav v0.3+ features without requiring a database.

.DESCRIPTION
    This script:
    1. Generates an anonymized baseline snapshot with realistic structure
    2. Applies mutations (renames, moves, adds, deletes, rekeys, transforms)
    3. Runs identity-aware diff engine
    4. Groups changes into work sessions
    5. Detects intents (retouching, restructure, bulk paste, etc.)
    6. Computes impact/blast radius
    7. Measures drift between pairs
    8. Checks compliance against golden template
    9. Detects anomalies
    10. Creates offline viewer bundle
    11. Opens HTML reports in browser

.EXAMPLE
    .\Demo.ps1

.EXAMPLE
    .\Demo.ps1 -NodeCount 500 -MutationRate 0.2 -CreateBundle
#>

[CmdletBinding()]
param(
    [int]$NodeCount = 200,
    [double]$MutationRate = 0.15,
    [switch]$NoOpen,
    [switch]$CreateBundle,
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# Import all modules
Write-Host "Loading modules..." -ForegroundColor Cyan
. "$scriptRoot\src\powershell\v02\core\NodeContract.ps1"
. "$scriptRoot\src\powershell\v02\core\IdentityResolver.ps1"
. "$scriptRoot\src\powershell\v02\diff\Compare-Snapshots.ps1"
. "$scriptRoot\src\powershell\v02\narrative\NarrativeEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\WorkSessionEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\IntentEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\ImpactEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\DriftEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\ComplianceEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\SimilarityEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\AnomalyEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\ExplainEngine.ps1"
. "$scriptRoot\src\powershell\v02\export\ExportBundle.ps1"

# Demo configuration
$demoConfig = @{
    ProjectName    = 'DEMO_PROJECT'
    Stations       = @('Station_Alpha', 'Station_Beta', 'Station_Gamma', 'Station_Delta')
    ToolTypes      = @('WeldGun', 'Gripper', 'Fixture', 'Clamp', 'Sensor', 'Camera')
    OperationTypes = @('Pick', 'Place', 'Weld', 'Move', 'Wait', 'Signal', 'Inspect')
}

function Show-DemoBanner {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║                                                               ║" -ForegroundColor Magenta
    Write-Host "  ║   SimTreeNav v0.3+ Full Demo                                  ║" -ForegroundColor Magenta
    Write-Host "  ║   All Analysis Engines + Offline Bundle                       ║" -ForegroundColor Magenta
    Write-Host "  ║                                                               ║" -ForegroundColor Magenta
    Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
}

function New-DemoNode {
    param(
        [string]$NodeId,
        [string]$Name,
        [string]$NodeType,
        [string]$ParentId = $null,
        [string]$Path = '/',
        [hashtable]$Attributes = @{},
        [hashtable]$Links = $null,
        [string]$Transform = $null
    )
    
    $externalId = "PP-$(([guid]::NewGuid()).ToString())"
    
    [PSCustomObject]@{
        nodeId      = $NodeId
        name        = $Name
        nodeType    = $NodeType
        parentId    = $ParentId
        path        = $Path
        attributes  = [PSCustomObject]@{
            externalId = $externalId
            className  = "$NodeType`Class"
            niceName   = $Name
            typeId     = Get-Random -Minimum 1 -Maximum 200
        }
        links       = if ($Links) { [PSCustomObject]$Links } else { $null }
        transform   = if ($Transform) { $Transform } else { "$(Get-Random -Minimum -1000 -Maximum 1000),$(Get-Random -Minimum -1000 -Maximum 1000),$(Get-Random -Minimum 0 -Maximum 500),$(Get-Random -Minimum 0 -Maximum 360),$(Get-Random -Minimum 0 -Maximum 360),$(Get-Random -Minimum 0 -Maximum 360)" }
        fingerprints = [PSCustomObject]@{
            contentHash   = ([guid]::NewGuid()).ToString().Substring(0, 16)
            attributeHash = ([guid]::NewGuid()).ToString().Substring(0, 16)
            transformHash = ([guid]::NewGuid()).ToString().Substring(0, 16)
        }
        identity    = $null
        source      = [PSCustomObject]@{
            table = "DF_DEMO_$NodeType`_DATA"
            extractedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}

function New-DemoDataset {
    param(
        [int]$NodeCount,
        [hashtable]$Config
    )
    
    $nodes = @()
    $nodeIndex = 1
    
    # Create root
    $root = New-DemoNode -NodeId "N$($nodeIndex.ToString('D6'))" -Name $Config.ProjectName -NodeType 'Root' -Path "/$($Config.ProjectName)"
    $nodes += $root
    $nodeIndex++
    
    # Create tool prototypes
    $protoIds = @{}
    foreach ($toolType in $Config.ToolTypes) {
        $protoId = "N$($nodeIndex.ToString('D6'))"
        $proto = New-DemoNode `
            -NodeId $protoId `
            -Name "$($toolType)_Prototype" `
            -NodeType 'ToolPrototype' `
            -ParentId $root.nodeId `
            -Path "/$($Config.ProjectName)/Prototypes/$($toolType)_Prototype"
        $nodes += $proto
        $protoIds[$toolType] = $protoId
        $nodeIndex++
    }
    
    # Create stations with resources and operations
    foreach ($stationName in $Config.Stations) {
        # Station node
        $stationId = "N$($nodeIndex.ToString('D6'))"
        $station = New-DemoNode `
            -NodeId $stationId `
            -Name $stationName `
            -NodeType 'Station' `
            -ParentId $root.nodeId `
            -Path "/$($Config.ProjectName)/$stationName"
        $nodes += $station
        $nodeIndex++
        
        # Resource groups
        $rgCount = Get-Random -Minimum 2 -Maximum 5
        for ($rg = 1; $rg -le $rgCount; $rg++) {
            $rgId = "N$($nodeIndex.ToString('D6'))"
            $rgName = "RG_$($stationName)_$rg"
            $resourceGroup = New-DemoNode `
                -NodeId $rgId `
                -Name $rgName `
                -NodeType 'ResourceGroup' `
                -ParentId $stationId `
                -Path "/$($Config.ProjectName)/$stationName/$rgName"
            $nodes += $resourceGroup
            $nodeIndex++
            
            # Resources (robots)
            $robotCount = Get-Random -Minimum 1 -Maximum 3
            for ($r = 1; $r -le $robotCount; $r++) {
                $robotId = "N$($nodeIndex.ToString('D6'))"
                $robotName = "Robot_$($stationName)_$rg`_$r"
                $robot = New-DemoNode `
                    -NodeId $robotId `
                    -Name $robotName `
                    -NodeType 'Resource' `
                    -ParentId $rgId `
                    -Path "/$($Config.ProjectName)/$stationName/$rgName/$robotName"
                $nodes += $robot
                $nodeIndex++
                
                # Tool instances on robot
                $toolCount = Get-Random -Minimum 1 -Maximum 3
                for ($t = 1; $t -le $toolCount; $t++) {
                    $toolType = $Config.ToolTypes | Get-Random
                    $toolId = "N$($nodeIndex.ToString('D6'))"
                    $toolName = "$($toolType)_$($nodeIndex.ToString('D3'))"
                    $tool = New-DemoNode `
                        -NodeId $toolId `
                        -Name $toolName `
                        -NodeType 'ToolInstance' `
                        -ParentId $robotId `
                        -Path "/$($Config.ProjectName)/$stationName/$rgName/$robotName/$toolName" `
                        -Links @{ prototypeId = $protoIds[$toolType] }
                    $nodes += $tool
                    $nodeIndex++
                }
            }
        }
        
        # Operations
        $opCount = Get-Random -Minimum 5 -Maximum 15
        for ($op = 1; $op -le $opCount; $op++) {
            $opType = $Config.OperationTypes | Get-Random
            $opId = "N$($nodeIndex.ToString('D6'))"
            $opName = "Op_$($stationName)_$($opType)_$op"
            $operation = New-DemoNode `
                -NodeId $opId `
                -Name $opName `
                -NodeType 'Operation' `
                -ParentId $stationId `
                -Path "/$($Config.ProjectName)/$stationName/Operations/$opName"
            $nodes += $operation
            $nodeIndex++
            
            # Locations for operation
            $locCount = Get-Random -Minimum 2 -Maximum 6
            for ($loc = 1; $loc -le $locCount; $loc++) {
                $locId = "N$($nodeIndex.ToString('D6'))"
                $locName = "Loc_$($opName)_$loc"
                $location = New-DemoNode `
                    -NodeId $locId `
                    -Name $locName `
                    -NodeType 'Location' `
                    -ParentId $opId `
                    -Path "/$($Config.ProjectName)/$stationName/Operations/$opName/$locName"
                $nodes += $location
                $nodeIndex++
            }
        }
        
        # Stop if we've reached target count
        if ($nodes.Count -ge $NodeCount) { break }
    }
    
    return $nodes
}

function Apply-Mutations {
    param(
        [array]$Nodes,
        [double]$Rate,
        [hashtable]$Config
    )
    
    $mutated = @()
    $mutationCount = [int]($Nodes.Count * $Rate)
    $mutationTypes = @('rename', 'move', 'transform', 'add', 'delete', 'rekey')
    
    # Copy all nodes
    foreach ($node in $Nodes) {
        $copy = $node.PSObject.Copy()
        $mutated += $copy
    }
    
    # Apply mutations
    $selectedIndices = 0..($mutated.Count - 1) | Get-Random -Count ([Math]::Min($mutationCount, $mutated.Count))
    
    foreach ($idx in $selectedIndices) {
        $node = $mutated[$idx]
        $mutationType = $mutationTypes | Get-Random
        
        switch ($mutationType) {
            'rename' {
                $node.name = "$($node.name)_renamed"
            }
            'move' {
                # Simulate move by changing path
                $node.path = $node.path -replace '/([^/]+)$', '/Moved/$1'
            }
            'transform' {
                # Change transform values
                $node.transform = "$(Get-Random -Minimum -2000 -Maximum 2000),$(Get-Random -Minimum -2000 -Maximum 2000),$(Get-Random -Minimum 0 -Maximum 1000),$(Get-Random -Minimum 0 -Maximum 360),$(Get-Random -Minimum 0 -Maximum 360),$(Get-Random -Minimum 0 -Maximum 360)"
            }
            'rekey' {
                # Simulate rekey - new nodeId but same externalId
                $node.nodeId = "N$(Get-Random -Minimum 900000 -Maximum 999999)"
            }
            'add' {
                # Add new sibling node
                $newNode = New-DemoNode `
                    -NodeId "N$(Get-Random -Minimum 800000 -Maximum 899999)" `
                    -Name "NewNode_$(Get-Random -Minimum 100 -Maximum 999)" `
                    -NodeType $node.nodeType `
                    -ParentId $node.parentId `
                    -Path "$($node.path | Split-Path)/NewNode_$(Get-Random)"
                $mutated += $newNode
            }
        }
    }
    
    # Delete some nodes (mark by removing from array)
    $deleteCount = [int]($mutationCount * 0.2)
    if ($deleteCount -gt 0 -and $mutated.Count -gt $deleteCount) {
        $toDelete = 0..($mutated.Count - 1) | Get-Random -Count $deleteCount
        $mutated = $mutated | Where-Object { $mutated.IndexOf($_) -notin $toDelete }
    }
    
    return $mutated
}

function Write-Progress {
    param([string]$Message, [string]$Status = 'Info')
    
    $color = switch ($Status) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        default   { 'Cyan' }
    }
    
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $color
}

# ============================================================================
# MAIN DEMO EXECUTION
# ============================================================================

Show-DemoBanner

Write-Progress "Generating baseline dataset (~$NodeCount nodes)..."
$baselineNodes = New-DemoDataset -NodeCount $NodeCount -Config $demoConfig
Write-Progress "Created $($baselineNodes.Count) baseline nodes" -Status 'Success'

Write-Progress "Applying mutations (rate: $($MutationRate * 100)%)..."
$currentNodes = Apply-Mutations -Nodes $baselineNodes -Rate $MutationRate -Config $demoConfig
Write-Progress "Current snapshot: $($currentNodes.Count) nodes" -Status 'Success'

Write-Progress "Resolving identities..."
$baselineNodes = Resolve-NodeIdentities -Nodes $baselineNodes
$currentNodes = Resolve-NodeIdentities -Nodes $currentNodes
Write-Progress "Identities resolved" -Status 'Success'

Write-Progress "Computing diff with identity matching..."
$diffResult = Compare-NodesWithIdentity -BaselineNodes $baselineNodes -CurrentNodes $currentNodes -ConfidenceThreshold 0.85
$diff = $diffResult.changes
Write-Progress "Found $($diff.Count) changes" -Status 'Success'

Write-Progress "Grouping into work sessions..."
$sessions = Group-ChangesIntoSessions -Changes $diff -TimeWindowMinutes 30 -MinChangesPerSession 2
Write-Progress "Detected $($sessions.Count) work sessions" -Status 'Success'

Write-Progress "Analyzing intents..."
$intents = @()
foreach ($session in $sessions) {
    $sessionIntents = Invoke-IntentAnalysis -Changes $session.changes -SessionId $session.sessionId
    $intents += $sessionIntents
}
Write-Progress "Detected $($intents.Count) intents" -Status 'Success'

Write-Progress "Computing impact analysis..."
$impactReport = Get-ImpactForChanges -Changes $diff -Nodes $currentNodes -MaxDepth 3
Write-Progress "Impact: $($impactReport.totalDownstreamImpact) downstream nodes affected" -Status 'Success'

Write-Progress "Measuring drift..."
$driftReport = Measure-Drift -Nodes $currentNodes
Write-Progress "Drift: $($driftReport.driftedPairs)/$($driftReport.totalPairs) pairs drifted" -Status 'Success'

Write-Progress "Checking compliance..."
$template = New-GoldenTemplate -Name 'DemoTemplate' -AllowExtras
$template.requiredTypes = @(
    (New-TypeRequirement -NodeType 'Station' -MinCount 1 -Required)
    (New-TypeRequirement -NodeType 'ResourceGroup' -MinCount 1)
    (New-TypeRequirement -NodeType 'Resource' -MinCount 1)
)
$complianceReport = Test-Compliance -Nodes $currentNodes -Template $template
Write-Progress "Compliance score: $([Math]::Round($complianceReport.score * 100))% ($($complianceReport.level))" -Status 'Success'

Write-Progress "Detecting anomalies..."
$anomalyReport = Detect-Anomalies -Changes $diff -TotalNodes $baselineNodes.Count
Write-Progress "Anomalies: $($anomalyReport.criticalCount) critical, $($anomalyReport.warnCount) warnings" -Status $(if ($anomalyReport.criticalCount -gt 0) { 'Warning' } else { 'Success' })

# Create output directory
$outputDir = Join-Path $scriptRoot 'output' 'demo'
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

Write-Progress "Saving outputs to $outputDir..."

# Build diff object for export
$diffExport = [PSCustomObject]@{
    summary = [PSCustomObject]@{
        totalChanges = $diff.Count
        added = ($diff | Where-Object { $_.changeType -eq 'added' }).Count
        removed = ($diff | Where-Object { $_.changeType -eq 'removed' }).Count
        renamed = ($diff | Where-Object { $_.changeType -eq 'renamed' }).Count
        moved = ($diff | Where-Object { $_.changeType -eq 'moved' }).Count
        transform_changed = ($diff | Where-Object { $_.changeType -eq 'transform_changed' }).Count
        rekeyed = ($diff | Where-Object { $_.changeType -eq 'rekeyed' }).Count
    }
    changes = $diff
}

# Export individual JSON files
$diffExport | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $outputDir 'diff.json') -Encoding UTF8
$sessions | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $outputDir 'sessions.json') -Encoding UTF8
$intents | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $outputDir 'intents.json') -Encoding UTF8
$impactReport | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $outputDir 'impact.json') -Encoding UTF8
$driftReport | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $outputDir 'drift.json') -Encoding UTF8
$complianceReport | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $outputDir 'compliance.json') -Encoding UTF8
$anomalyReport | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $outputDir 'anomalies.json') -Encoding UTF8

Write-Progress "JSON files saved" -Status 'Success'

# Create offline bundle
if ($CreateBundle) {
    Write-Progress "Creating offline bundle..."
    
    $bundleDir = Join-Path $outputDir 'bundle'
    $bundleResult = Export-Bundle `
        -OutDir $bundleDir `
        -Name "SimTreeNav Demo - $(Get-Date -Format 'yyyy-MM-dd')" `
        -BaselineNodes $baselineNodes `
        -CurrentNodes $currentNodes `
        -Diff $diffExport `
        -Sessions $sessions `
        -Intents $intents `
        -Impact $impactReport `
        -Drift $driftReport `
        -Compliance $complianceReport `
        -Anomalies $anomalyReport `
        -CreateZip
    
    Write-Progress "Bundle created: $($bundleResult.path)" -Status 'Success'
}

# Generate sample explanation
Write-Progress "Generating node explanation for first station..."
$firstStation = $currentNodes | Where-Object { $_.nodeType -eq 'Station' } | Select-Object -First 1
if ($firstStation) {
    $explanation = Get-NodeExplanation -NodeId $firstStation.nodeId -Nodes $currentNodes
    Export-ExplanationMarkdown -Explanation $explanation -OutputPath (Join-Path $outputDir 'explain') | Out-Null
    Write-Progress "Explanation saved to explain/$($firstStation.nodeId).md" -Status 'Success'
}

# Summary
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                      DEMO COMPLETE                            ║" -ForegroundColor Green
Write-Host "  ╠═══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "  ║  Baseline Nodes:    $($baselineNodes.Count.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Current Nodes:     $($currentNodes.Count.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Total Changes:     $($diff.Count.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Work Sessions:     $($sessions.Count.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Intents Detected:  $($intents.Count.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Compliance Score:  $([Math]::Round($complianceReport.score * 100).ToString().PadLeft(5))%                                ║" -ForegroundColor Green
Write-Host "  ║  Anomalies:         $($anomalyReport.totalAnomalies.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Output: $outputDir" -ForegroundColor Cyan

# Open bundle if created
if ($CreateBundle -and -not $NoOpen) {
    $indexPath = Join-Path $bundleDir 'index.html'
    if (Test-Path $indexPath) {
        Write-Host "  Opening bundle in browser..." -ForegroundColor Cyan
        if ($IsWindows -or $env:OS -match 'Windows') {
            Start-Process $indexPath
        }
        elseif ($IsMacOS) {
            & open $indexPath
        }
        else {
            Write-Host "  Bundle ready at: $indexPath" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
