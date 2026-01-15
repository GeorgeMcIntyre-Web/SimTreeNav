# Demo.ps1
# SimTreeNav v0.3 Demo - Runs without database using generated anonymized data
# Demonstrates: Snapshots, Identity Resolution, Diff, Narrative Analysis

<#
.SYNOPSIS
    Demonstrates SimTreeNav v0.3 features without requiring a database.

.DESCRIPTION
    This script:
    1. Generates an anonymized baseline snapshot
    2. Applies realistic mutations (renames, moves, adds, deletes, rekeys)
    3. Runs the diff engine with identity resolution
    4. Produces narrative analysis
    5. Opens the HTML reports in browser

.EXAMPLE
    .\Demo.ps1

.EXAMPLE
    .\Demo.ps1 -NodeCount 500 -MutationRate 0.1
#>

[CmdletBinding()]
param(
    [int]$NodeCount = 150,
    [double]$MutationRate = 0.15,
    [switch]$NoOpen,
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# Import modules
. "$scriptRoot\src\powershell\v02\core\NodeContract.ps1"
. "$scriptRoot\src\powershell\v02\core\IdentityResolver.ps1"
. "$scriptRoot\src\powershell\v02\diff\Compare-Snapshots.ps1"
. "$scriptRoot\src\powershell\v02\narrative\NarrativeEngine.ps1"

# Demo configuration
$demoConfig = @{
    ProjectName = 'DEMO_PROJECT'
    Stations = @('Station_A', 'Station_B', 'Station_C', 'Station_D')
    ToolTypes = @('WeldGun', 'Gripper', 'Fixture', 'Clamp', 'Sensor')
    OperationTypes = @('Pick', 'Place', 'Weld', 'Move', 'Wait', 'Signal')
}

function Show-DemoBanner {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║                                                               ║" -ForegroundColor Magenta
    Write-Host "  ║   SimTreeNav v0.3 Demo                                        ║" -ForegroundColor Magenta
    Write-Host "  ║   Identity Resolution + Narrative Analysis                    ║" -ForegroundColor Magenta
    Write-Host "  ║                                                               ║" -ForegroundColor Magenta
    Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
}

function New-DemoNode {
    param(
        [string]$NodeId,
        [string]$Name,
        [string]$ParentId,
        [string]$Path,
        [string]$NodeType,
        [string]$ClassName,
        [string]$ExternalId = ''
    )
    
    $contentHash = Get-ContentHash -Name $Name -ExternalId $ExternalId -ClassName $ClassName
    
    [PSCustomObject]@{
        nodeId      = $NodeId
        nodeType    = $NodeType
        name        = $Name
        parentId    = $ParentId
        path        = $Path
        attributes  = [PSCustomObject]@{
            externalId  = $ExternalId
            className   = $ClassName
            niceName    = $NodeType
            typeId      = [int]($NodeId.Substring($NodeId.Length - 2))
            seqNumber   = 0
            level       = ($Path -split '/').Count - 1
        }
        links       = [PSCustomObject]@{}
        fingerprints = [PSCustomObject]@{
            contentHash   = $contentHash
            attributeHash = $null
            transformHash = $null
        }
        timestamps  = [PSCustomObject]@{
            createdAt     = $null
            updatedAt     = $null
            lastTouchedAt = $null
        }
        source      = [PSCustomObject]@{
            table     = 'DEMO'
            query     = 'generated'
            schema    = 'DEMO'
        }
    }
}

function New-RandomUuid {
    $guid = [guid]::NewGuid().ToString()
    "PP-$guid"
}

function Generate-BaselineSnapshot {
    param([int]$TargetCount)
    
    Write-Host "  Generating baseline snapshot with ~$TargetCount nodes..." -ForegroundColor Cyan
    
    $nodes = @()
    $nodeIdCounter = 1000000
    
    # Root project
    $projectId = "$nodeIdCounter"
    $nodes += New-DemoNode `
        -NodeId $projectId `
        -Name $demoConfig.ProjectName `
        -ParentId $null `
        -Path "/$($demoConfig.ProjectName)" `
        -NodeType 'ResourceGroup' `
        -ClassName 'class PmProject' `
        -ExternalId (New-RandomUuid)
    $nodeIdCounter++
    
    # Calculate nodes per station
    $nodesPerStation = [Math]::Floor(($TargetCount - 1) / $demoConfig.Stations.Count)
    
    foreach ($stationName in $demoConfig.Stations) {
        # Station node
        $stationId = "$nodeIdCounter"
        $stationPath = "/$($demoConfig.ProjectName)/$stationName"
        $nodes += New-DemoNode `
            -NodeId $stationId `
            -Name $stationName `
            -ParentId $projectId `
            -Path $stationPath `
            -NodeType 'ResourceGroup' `
            -ClassName 'class PmStation' `
            -ExternalId (New-RandomUuid)
        $nodeIdCounter++
        
        # Resources under station
        $resourcesPerStation = [Math]::Floor($nodesPerStation * 0.3)
        for ($r = 1; $r -le $resourcesPerStation; $r++) {
            $toolType = $demoConfig.ToolTypes[$r % $demoConfig.ToolTypes.Count]
            $resourceName = "${toolType}_${stationName}_$($r.ToString('D2'))"
            $resourceId = "$nodeIdCounter"
            
            $nodes += New-DemoNode `
                -NodeId $resourceId `
                -Name $resourceName `
                -ParentId $stationId `
                -Path "$stationPath/$resourceName" `
                -NodeType 'ToolInstance' `
                -ClassName 'class Robot' `
                -ExternalId (New-RandomUuid)
            $nodeIdCounter++
        }
        
        # Operations under station
        $opsPerStation = [Math]::Floor($nodesPerStation * 0.6)
        for ($o = 1; $o -le $opsPerStation; $o++) {
            $opType = $demoConfig.OperationTypes[$o % $demoConfig.OperationTypes.Count]
            $opName = "${opType}_$($o.ToString('D3'))"
            $opId = "$nodeIdCounter"
            
            $nodes += New-DemoNode `
                -NodeId $opId `
                -Name $opName `
                -ParentId $stationId `
                -Path "$stationPath/$opName" `
                -NodeType 'Operation' `
                -ClassName "class ${opType}Operation" `
                -ExternalId (New-RandomUuid)
            $nodeIdCounter++
        }
    }
    
    Write-Host "    Generated $($nodes.Count) nodes" -ForegroundColor Gray
    return $nodes
}

function Apply-Mutations {
    param(
        [array]$Nodes,
        [double]$MutationRate
    )
    
    Write-Host "  Applying mutations (rate: $([Math]::Round($MutationRate * 100))%)..." -ForegroundColor Cyan
    
    $mutatedNodes = $Nodes | ForEach-Object { $_.PSObject.Copy() }
    $mutations = @{
        renames = 0
        moves = 0
        adds = 0
        deletes = 0
        rekeys = 0
        transforms = 0
    }
    
    $random = New-Object System.Random
    $targetMutations = [Math]::Floor($Nodes.Count * $MutationRate)
    
    # Select random nodes for mutation (skip root)
    $candidateNodes = $mutatedNodes | Where-Object { $_.parentId -ne $null } | Get-Random -Count ([Math]::Min($targetMutations * 2, $mutatedNodes.Count - 1))
    
    $mutationIndex = 0
    foreach ($node in $candidateNodes) {
        $mutationType = $random.Next(6)
        
        switch ($mutationType) {
            0 {
                # Rename
                $oldName = $node.name
                $node.name = $node.name + "_v2"
                $node.path = $node.path -replace [regex]::Escape($oldName), $node.name
                $node.fingerprints.contentHash = Get-ContentHash -Name $node.name -ExternalId $node.attributes.externalId -ClassName $node.attributes.className
                $mutations.renames++
            }
            1 {
                # Move (change parent within same station type)
                $potentialParents = $mutatedNodes | Where-Object { $_.nodeType -eq 'ResourceGroup' -and $_.nodeId -ne $node.nodeId -and $_.parentId -ne $null }
                if ($potentialParents.Count -gt 0) {
                    $newParent = $potentialParents | Get-Random
                    $node.parentId = $newParent.nodeId
                    $node.path = "$($newParent.path)/$($node.name)"
                    $mutations.moves++
                }
            }
            2 {
                # Rekey (same logical node, new nodeId)
                $oldId = $node.nodeId
                $node.nodeId = "$([int]$oldId + 900000)"
                # Update children's parentId
                $mutatedNodes | Where-Object { $_.parentId -eq $oldId } | ForEach-Object {
                    $_.parentId = $node.nodeId
                }
                $mutations.rekeys++
            }
            3 {
                # Transform change (for operations)
                if ($node.nodeType -eq 'Operation') {
                    $node.fingerprints.transformHash = [guid]::NewGuid().ToString().Substring(0, 16)
                    $mutations.transforms++
                }
            }
            4 {
                # Delete (mark for removal)
                $node | Add-Member -NotePropertyName '_delete' -NotePropertyValue $true -Force
                $mutations.deletes++
            }
            5 {
                # Add new sibling
                $newId = "$([int]$node.nodeId + 500000)"
                $newName = "New_Node_$mutationIndex"
                $mutatedNodes += New-DemoNode `
                    -NodeId $newId `
                    -Name $newName `
                    -ParentId $node.parentId `
                    -Path "$($node.path | Split-Path -Parent)/$newName" `
                    -NodeType $node.nodeType `
                    -ClassName $node.attributes.className `
                    -ExternalId (New-RandomUuid)
                $mutations.adds++
            }
        }
        
        $mutationIndex++
        if ($mutationIndex -ge $targetMutations) { break }
    }
    
    # Remove deleted nodes
    $finalNodes = $mutatedNodes | Where-Object { -not $_._delete }
    
    Write-Host "    Renames: $($mutations.renames)" -ForegroundColor Yellow
    Write-Host "    Moves: $($mutations.moves)" -ForegroundColor Magenta
    Write-Host "    Rekeys: $($mutations.rekeys)" -ForegroundColor DarkYellow
    Write-Host "    Transforms: $($mutations.transforms)" -ForegroundColor Cyan
    Write-Host "    Adds: $($mutations.adds)" -ForegroundColor Green
    Write-Host "    Deletes: $($mutations.deletes)" -ForegroundColor Red
    
    return $finalNodes
}

function Save-Snapshot {
    param(
        [array]$Nodes,
        [string]$Path,
        [string]$Label
    )
    
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    
    # Resolve identities
    $nodesWithIdentity = Resolve-NodeIdentities -Nodes $Nodes
    
    # Sort for deterministic output
    $sortedNodes = $nodesWithIdentity | Sort-Object { [long]$_.nodeId }
    
    # Write nodes.json
    $nodesJson = $sortedNodes | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $Path 'nodes.json'), $nodesJson, $utf8NoBom)
    
    # Write meta.json
    $meta = [PSCustomObject]@{
        version = '0.3.0'
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        label = $Label
        source = [PSCustomObject]@{
            type = 'demo'
            projectName = $demoConfig.ProjectName
        }
        stats = [PSCustomObject]@{
            totalNodes = $Nodes.Count
            nodeTypes = ($Nodes | Group-Object nodeType | ForEach-Object { [PSCustomObject]@{ type = $_.Name; count = $_.Count } })
        }
    }
    $metaJson = $meta | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText((Join-Path $Path 'meta.json'), $metaJson, $utf8NoBom)
    
    return $Path
}

# Main demo flow
Show-DemoBanner

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$demoDir = Join-Path $scriptRoot "demo_output_$timestamp"

Write-Host "Step 1: Generate Baseline Snapshot" -ForegroundColor White
Write-Host "─────────────────────────────────────────────" -ForegroundColor DarkGray
$baselineNodes = Generate-BaselineSnapshot -TargetCount $NodeCount
$baselinePath = Join-Path $demoDir 'baseline'
Save-Snapshot -Nodes $baselineNodes -Path $baselinePath -Label 'baseline'
Write-Host ""

Write-Host "Step 2: Apply Mutations (Simulating Real Changes)" -ForegroundColor White
Write-Host "─────────────────────────────────────────────" -ForegroundColor DarkGray
$mutatedNodes = Apply-Mutations -Nodes $baselineNodes -MutationRate $MutationRate
$currentPath = Join-Path $demoDir 'current'
Save-Snapshot -Nodes $mutatedNodes -Path $currentPath -Label 'current'
Write-Host ""

Write-Host "Step 3: Run Diff Engine with Identity Resolution" -ForegroundColor White
Write-Host "─────────────────────────────────────────────" -ForegroundColor DarkGray
$diffPath = Join-Path $demoDir 'diff'

# Read snapshots
$baseline = [PSCustomObject]@{
    Nodes = Get-Content (Join-Path $baselinePath 'nodes.json') -Raw | ConvertFrom-Json
    Meta = Get-Content (Join-Path $baselinePath 'meta.json') -Raw | ConvertFrom-Json
    Path = $baselinePath
}
$current = [PSCustomObject]@{
    Nodes = Get-Content (Join-Path $currentPath 'nodes.json') -Raw | ConvertFrom-Json
    Meta = Get-Content (Join-Path $currentPath 'meta.json') -Raw | ConvertFrom-Json
    Path = $currentPath
}

Write-Host "  Running identity-aware comparison..." -ForegroundColor Cyan
$diffResult = Compare-NodesWithIdentity -BaselineNodes $baseline.Nodes -CurrentNodes $current.Nodes -ConfidenceThreshold 0.85
$changes = $diffResult.changes
$identityMap = $diffResult.identityMap

Write-Host "    Found $($changes.Count) changes" -ForegroundColor Gray
if ($identityMap -and $identityMap.stats) {
    Write-Host "    Exact matches: $($identityMap.stats.exactMatches)" -ForegroundColor Gray
    Write-Host "    Rekeyed matches: $($identityMap.stats.rekeyedMatches)" -ForegroundColor Yellow
}
Write-Host ""

# Generate diff summary
$summary = Get-ChangeSummary -Changes $changes -IdentityMap $identityMap

# Build diff object
$diff = [PSCustomObject]@{
    version = '0.3.0'
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    baseline = [PSCustomObject]@{
        path = $baselinePath
        timestamp = $baseline.Meta.timestamp
        nodeCount = $baseline.Nodes.Count
    }
    current = [PSCustomObject]@{
        path = $currentPath
        timestamp = $current.Meta.timestamp
        nodeCount = $current.Nodes.Count
    }
    config = [PSCustomObject]@{
        useIdentityMatching = $true
        confidenceThreshold = 0.85
    }
    summary = $summary
    changes = $changes
}

# Save diff
if (-not (Test-Path $diffPath)) {
    New-Item -ItemType Directory -Path $diffPath -Force | Out-Null
}
$diffJson = $diff | ConvertTo-Json -Depth 10
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText((Join-Path $diffPath 'diff.json'), $diffJson, $utf8NoBom)

# Generate HTML
Export-DiffHtml -Diff $diff -OutputPath $diffPath

Write-Host "Step 4: Run Narrative Analysis" -ForegroundColor White
Write-Host "─────────────────────────────────────────────" -ForegroundColor DarkGray
$actions = Invoke-NarrativeAnalysis -Changes $changes

Write-Host "  Generated $($actions.Count) narrative actions" -ForegroundColor Cyan

$actionSummary = $actions | Group-Object actionType | ForEach-Object {
    Write-Host "    $($_.Name): $($_.Count)" -ForegroundColor Gray
}

Export-NarrativeReport -Actions $actions -OutputPath $diffPath -Pretty -GenerateHtml
Write-Host ""

Write-Host "Step 5: Output Summary" -ForegroundColor White
Write-Host "─────────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Demo output directory: $demoDir" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Files generated:" -ForegroundColor White
Write-Host "    baseline/nodes.json    - Baseline snapshot" -ForegroundColor Gray
Write-Host "    baseline/meta.json     - Baseline metadata" -ForegroundColor Gray
Write-Host "    current/nodes.json     - Current snapshot" -ForegroundColor Gray
Write-Host "    current/meta.json      - Current metadata" -ForegroundColor Gray
Write-Host "    diff/diff.json         - Diff with identity resolution" -ForegroundColor Gray
Write-Host "    diff/diff.html         - Interactive diff report" -ForegroundColor Green
Write-Host "    diff/actions.json      - Narrative actions" -ForegroundColor Gray
Write-Host "    diff/narrative.html    - Narrative report" -ForegroundColor Green
Write-Host ""

# Open HTML reports
if (-not $NoOpen) {
    Write-Host "  Opening reports in browser..." -ForegroundColor Yellow
    Start-Process (Join-Path $diffPath 'diff.html')
    Start-Sleep -Milliseconds 500
    Start-Process (Join-Path $diffPath 'narrative.html')
}

Write-Host ""
Write-Host "  ✓ Demo complete!" -ForegroundColor Green
Write-Host ""
Write-Host "  Key v0.3 features demonstrated:" -ForegroundColor White
Write-Host "    • Identity Resolution - Detects rekeyed nodes (same logical node, different ID)" -ForegroundColor Gray
Write-Host "    • Confidence Scoring - Match quality indicated for each correlation" -ForegroundColor Gray
Write-Host "    • Narrative Engine - Groups raw changes into meaningful actions" -ForegroundColor Gray
Write-Host "    • Bulk Detection - Identifies paste clusters and station reorganizations" -ForegroundColor Gray
Write-Host ""
