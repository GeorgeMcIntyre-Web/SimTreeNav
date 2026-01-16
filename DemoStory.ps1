<#
.SYNOPSIS
    Generates a demo bundle with synthetic data for testing and demonstration.

.DESCRIPTION
    DemoStory creates a complete SimTreeNav bundle with:
    - Synthetic tree data (nodes.json)
    - Timeline with multiple snapshots
    - Diff data showing changes between snapshots
    - Actions log
    - Impact and drift analysis data
    
    This is useful for:
    - Testing the viewer without database access
    - Demonstrations and presentations
    - CI/CD pipeline testing

.PARAMETER NodeCount
    Number of nodes to generate (default: 500).

.PARAMETER SnapshotCount
    Number of timeline snapshots to generate (default: 5).

.PARAMETER OutDir
    Output directory for the bundle.

.PARAMETER NoOpen
    Don't open the viewer in browser after generation.

.EXAMPLE
    .\DemoStory.ps1 -NodeCount 500 -OutDir ./output/demo_v06

.EXAMPLE
    .\DemoStory.ps1 -NodeCount 1000 -SnapshotCount 10 -OutDir ./output/demo_large -NoOpen
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$NodeCount = 500,

    [Parameter()]
    [int]$SnapshotCount = 5,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [Parameter()]
    [switch]$NoOpen
)

# Strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# Configuration
# ============================================================================

$nodeTypes = @(
    @{ name = 'Project'; icon = '📁'; weight = 1 }
    @{ name = 'Plant'; icon = '🏭'; weight = 2 }
    @{ name = 'Line'; icon = '📏'; weight = 5 }
    @{ name = 'Station'; icon = '⚙️'; weight = 10 }
    @{ name = 'Cell'; icon = '🔲'; weight = 15 }
    @{ name = 'Robot'; icon = '🤖'; weight = 20 }
    @{ name = 'Resource'; icon = '🔧'; weight = 25 }
    @{ name = 'Part'; icon = '📦'; weight = 15 }
    @{ name = 'Operation'; icon = '▶️'; weight = 30 }
    @{ name = 'Study'; icon = '📋'; weight = 5 }
)

$actionTypes = @('add', 'remove', 'modify', 'move', 'rename')

$namePrefixes = @(
    'Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon',
    'Main', 'Aux', 'Primary', 'Secondary', 'Test',
    'North', 'South', 'East', 'West', 'Central'
)

$nameSuffixes = @(
    'Assembly', 'Unit', 'Module', 'System', 'Cell',
    'Station', 'Zone', 'Area', 'Block', 'Section'
)

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Status {
    param([string]$Message, [string]$Type = 'Info')
    
    $colors = @{
        'Info'    = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
    }
    
    $prefix = switch ($Type) {
        'Info'    { '[*]' }
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $colors[$Type]
}

function Get-RandomName {
    $prefix = $namePrefixes | Get-Random
    $suffix = $nameSuffixes | Get-Random
    $number = Get-Random -Minimum 1 -Maximum 999
    return "$prefix-$suffix-$number"
}

function Get-RandomNodeType {
    $totalWeight = ($nodeTypes | Measure-Object -Property weight -Sum).Sum
    $random = Get-Random -Minimum 0 -Maximum $totalWeight
    
    $cumulative = 0
    foreach ($type in $nodeTypes) {
        $cumulative += $type.weight
        if ($random -lt $cumulative) {
            return $type
        }
    }
    return $nodeTypes[-1]
}

function New-TreeNode {
    param(
        [int]$Id,
        [string]$Name,
        [string]$NodeType,
        [int]$ParentId = 0,
        [int]$Depth = 0
    )
    
    $fingerprint = [System.BitConverter]::ToString(
        [System.Security.Cryptography.SHA256]::Create().ComputeHash(
            [System.Text.Encoding]::UTF8.GetBytes("$Id-$Name-$NodeType")
        )
    ).Replace('-', '').ToLower()
    
    return @{
        id           = $Id
        name         = $Name
        nodeType     = $NodeType
        niceName     = $NodeType
        className    = "class Pm$NodeType"
        externalId   = "EXT-$Id"
        logicalId    = "LOG-$($fingerprint.Substring(0, 8))"
        path         = ""
        depth        = $Depth
        parentId     = $ParentId
        children     = @()
        fingerprint  = $fingerprint.Substring(0, 32)
        createdAt    = (Get-Date).AddDays(-$Id % 365).ToString('o')
        modifiedAt   = (Get-Date).AddDays(-($Id % 30)).ToString('o')
    }
}

function Build-TreeStructure {
    param([int]$NodeCount)
    
    $nodes = @{}
    $root = New-TreeNode -Id 1 -Name 'Demo Project' -NodeType 'Project' -Depth 0
    $nodes[1] = $root
    
    $currentId = 2
    $parentIds = @(1)
    
    while ($currentId -le $NodeCount) {
        $parentId = $parentIds | Get-Random
        $parent = $nodes[$parentId]
        
        $type = Get-RandomNodeType
        $name = Get-RandomName
        $depth = $parent.depth + 1
        
        # Limit depth to prevent overly deep trees
        if ($depth -gt 8) {
            $parentId = 1
            $parent = $nodes[1]
            $depth = 1
        }
        
        $node = New-TreeNode -Id $currentId -Name $name -NodeType $type.name -ParentId $parentId -Depth $depth
        $node.path = if ($parent.path) { "$($parent.path) / $name" } else { $name }
        
        $nodes[$currentId] = $node
        $parent.children += $node
        
        # Add this node as potential parent (with depth limits)
        if ($depth -lt 7 -and $parent.children.Count -lt 20) {
            $parentIds += $currentId
        }
        
        $currentId++
        
        if ($currentId % 100 -eq 0) {
            Write-Status "Generated $currentId / $NodeCount nodes..." 'Info'
        }
    }
    
    return $root
}

function Generate-Timeline {
    param(
        [int]$SnapshotCount,
        [int]$NodeCount
    )
    
    $snapshots = @()
    $baseTime = (Get-Date).AddDays(-$SnapshotCount)
    
    for ($i = 0; $i -lt $SnapshotCount; $i++) {
        $timestamp = $baseTime.AddDays($i).ToString('o')
        $changes = Get-Random -Minimum 0 -Maximum ([Math]::Min(50, [Math]::Floor($NodeCount / 10)))
        
        $hash = [System.BitConverter]::ToString(
            [System.Security.Cryptography.SHA256]::Create().ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes("snapshot-$i-$timestamp")
            )
        ).Replace('-', '').ToLower()
        
        $snapshots += @{
            index     = $i
            timestamp = $timestamp
            nodeCount = $NodeCount + ($i * (Get-Random -Minimum -5 -Maximum 10))
            changes   = $changes
            hash      = $hash
            label     = "Snapshot $($i + 1)"
        }
    }
    
    return @{
        schemaVersion = '0.6.0'
        snapshots     = $snapshots
        currentIndex  = $SnapshotCount - 1
    }
}

function Generate-Diff {
    param(
        $RootNode,
        [int]$ChangeCount
    )
    
    $changes = @()
    $allNodes = @()
    
    # Flatten tree to get all node IDs
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue($RootNode)
    
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        $allNodes += $node
        foreach ($child in $node.children) {
            $queue.Enqueue($child)
        }
    }
    
    $changedCount = [Math]::Min($ChangeCount, $allNodes.Count - 1)
    $changedNodes = $allNodes | Get-Random -Count $changedCount
    
    foreach ($node in $changedNodes) {
        $changeType = @('added', 'modified', 'removed') | Get-Random
        
        $change = @{
            nodeId   = $node.id
            nodeName = $node.name
            path     = $node.path
            type     = $changeType
        }
        
        if ($changeType -eq 'modified') {
            $fields = @('name', 'externalId', 'status', 'position')
            $field = $fields | Get-Random
            $change.field = $field
            $change.before = "old_$field"
            $change.after = "new_$field"
        }
        
        $changes += $change
    }
    
    return @{
        schemaVersion = '0.6.0'
        timestamp     = (Get-Date).ToString('o')
        changes       = $changes
        summary       = @{
            added    = ($changes | Where-Object { $_.type -eq 'added' }).Count
            modified = ($changes | Where-Object { $_.type -eq 'modified' }).Count
            removed  = ($changes | Where-Object { $_.type -eq 'removed' }).Count
        }
    }
}

function Generate-Actions {
    param(
        $RootNode,
        [int]$ActionCount
    )
    
    $actions = @()
    $allNodes = @()
    
    # Flatten tree
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue($RootNode)
    
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        $allNodes += $node
        foreach ($child in $node.children) {
            $queue.Enqueue($child)
        }
    }
    
    for ($i = 0; $i -lt $ActionCount; $i++) {
        $node = $allNodes | Get-Random
        $actionType = $actionTypes | Get-Random
        
        $actions += @{
            id        = $i + 1
            type      = $actionType
            nodeId    = $node.id
            nodeName  = $node.name
            path      = $node.path
            timestamp = (Get-Date).AddMinutes(-$i * 5).ToString('o')
            user      = @('admin', 'user1', 'user2', 'robot') | Get-Random
        }
    }
    
    return $actions | Sort-Object { $_.timestamp } -Descending
}

function Generate-Impact {
    param(
        $RootNode,
        [int]$ImpactCount
    )
    
    $impacts = @()
    $allNodes = @()
    
    # Flatten tree
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue($RootNode)
    
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        $allNodes += $node
        foreach ($child in $node.children) {
            $queue.Enqueue($child)
        }
    }
    
    $impactedNodes = $allNodes | Get-Random -Count ([Math]::Min($ImpactCount, $allNodes.Count))
    
    foreach ($node in $impactedNodes) {
        $riskScore = [Math]::Round((Get-Random -Minimum 0 -Maximum 100) / 10, 1)
        
        $reasons = @()
        $reasonCount = Get-Random -Minimum 1 -Maximum 4
        $possibleReasons = @(
            @{ text = 'High connectivity'; weight = 2.5 }
            @{ text = 'Critical path dependency'; weight = 3.0 }
            @{ text = 'Recent modifications'; weight = 1.5 }
            @{ text = 'Production system'; weight = 4.0 }
            @{ text = 'Safety related'; weight = 5.0 }
        )
        
        $reasons = $possibleReasons | Get-Random -Count $reasonCount
        
        $impacts += @{
            nodeId        = $node.id
            nodeName      = $node.name
            path          = $node.path
            riskScore     = $riskScore
            impactReasons = $reasons
        }
    }
    
    return @{
        schemaVersion = '0.6.0'
        timestamp     = (Get-Date).ToString('o')
        impacts       = ($impacts | Sort-Object { $_.riskScore } -Descending)
    }
}

function Generate-Drift {
    param(
        $RootNode,
        [int]$DriftCount
    )
    
    $drifts = @()
    $allNodes = @()
    
    # Flatten tree
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue($RootNode)
    
    while ($queue.Count -gt 0) {
        $node = $queue.Dequeue()
        $allNodes += $node
        foreach ($child in $node.children) {
            $queue.Enqueue($child)
        }
    }
    
    $driftedNodes = $allNodes | Get-Random -Count ([Math]::Min($DriftCount, $allNodes.Count))
    
    foreach ($node in $driftedNodes) {
        $driftScore = [Math]::Round((Get-Random -Minimum 0 -Maximum 100) / 100, 2)
        $pairingConfidence = [Math]::Round((Get-Random -Minimum 50 -Maximum 100) / 100, 2)
        
        $drifts += @{
            nodeId            = $node.id
            nodeName          = $node.name
            path              = $node.path
            driftScore        = $driftScore
            pairingConfidence = $pairingConfidence
            pairingReason     = 'Matched by logicalId with structural verification'
            deltas            = @(
                @{
                    field  = 'position'
                    before = '100, 200, 300'
                    after  = '105, 202, 301'
                }
            )
        }
    }
    
    return @{
        schemaVersion = '0.6.0'
        timestamp     = (Get-Date).ToString('o')
        drifts        = ($drifts | Sort-Object { $_.driftScore } -Descending)
    }
}

# ============================================================================
# Main Script
# ============================================================================

Write-Host ""
Write-Host "SimTreeNav DemoStory Generator v0.6.0" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Status "Generating demo bundle..." 'Info'
Write-Status "Node Count: $NodeCount" 'Info'
Write-Status "Snapshot Count: $SnapshotCount" 'Info'
Write-Status "Output: $OutDir" 'Info'
Write-Host ""

# Create output directory
if (Test-Path $OutDir) {
    Write-Status "Cleaning existing output directory..." 'Warning'
    Remove-Item $OutDir -Recurse -Force
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null

# Generate tree structure
Write-Status "Building tree structure..." 'Info'
$rootNode = Build-TreeStructure -NodeCount $NodeCount
Write-Status "Tree structure complete" 'Success'

# Save nodes.json
Write-Status "Saving nodes.json..." 'Info'
$nodesPath = Join-Path $OutDir 'nodes.json'
@{ root = $rootNode } | ConvertTo-Json -Depth 20 -Compress | Set-Content $nodesPath -Encoding UTF8
Write-Status "Nodes saved" 'Success'

# Generate timeline
Write-Status "Generating timeline..." 'Info'
$timeline = Generate-Timeline -SnapshotCount $SnapshotCount -NodeCount $NodeCount
$timelinePath = Join-Path $OutDir 'timeline.json'
$timeline | ConvertTo-Json -Depth 10 | Set-Content $timelinePath -Encoding UTF8
Write-Status "Timeline saved with $SnapshotCount snapshots" 'Success'

# Generate diff
Write-Status "Generating diff data..." 'Info'
$changeCount = [Math]::Floor($NodeCount * 0.1)
$diff = Generate-Diff -RootNode $rootNode -ChangeCount $changeCount
$diffPath = Join-Path $OutDir 'diff.json'
$diff | ConvertTo-Json -Depth 10 | Set-Content $diffPath -Encoding UTF8
Write-Status "Diff saved with $($diff.changes.Count) changes" 'Success'

# Generate actions
Write-Status "Generating actions log..." 'Info'
$actionCount = [Math]::Min(50, [Math]::Floor($NodeCount * 0.05))
$actions = Generate-Actions -RootNode $rootNode -ActionCount $actionCount
$actionsPath = Join-Path $OutDir 'actions.json'
$actions | ConvertTo-Json -Depth 10 | Set-Content $actionsPath -Encoding UTF8
Write-Status "Actions saved with $($actions.Count) entries" 'Success'

# Generate impact analysis
Write-Status "Generating impact analysis..." 'Info'
$impactCount = [Math]::Floor($NodeCount * 0.05)
$impact = Generate-Impact -RootNode $rootNode -ImpactCount $impactCount
$impactPath = Join-Path $OutDir 'impact.json'
$impact | ConvertTo-Json -Depth 10 | Set-Content $impactPath -Encoding UTF8
Write-Status "Impact analysis saved" 'Success'

# Generate drift data
Write-Status "Generating drift data..." 'Info'
$driftCount = [Math]::Floor($NodeCount * 0.03)
$drift = Generate-Drift -RootNode $rootNode -DriftCount $driftCount
$driftPath = Join-Path $OutDir 'drift.json'
$drift | ConvertTo-Json -Depth 10 | Set-Content $driftPath -Encoding UTF8
Write-Status "Drift data saved" 'Success'

# Copy viewer files
Write-Status "Copying viewer files..." 'Info'
$viewerSource = Join-Path $PSScriptRoot 'viewer'
if (Test-Path $viewerSource) {
    Copy-Item (Join-Path $viewerSource 'index.html') $OutDir -Force
    
    $assetsDest = Join-Path $OutDir 'assets'
    if (-not (Test-Path $assetsDest)) {
        New-Item -ItemType Directory -Path $assetsDest -Force | Out-Null
    }
    Copy-Item (Join-Path $viewerSource 'assets' '*') $assetsDest -Recurse -Force
    
    # Move data files to data subdirectory
    $dataDir = Join-Path $OutDir 'data'
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    
    $dataFiles = @('nodes.json', 'timeline.json', 'diff.json', 'actions.json', 'impact.json', 'drift.json')
    foreach ($file in $dataFiles) {
        $sourcePath = Join-Path $OutDir $file
        if (Test-Path $sourcePath) {
            Move-Item $sourcePath $dataDir -Force
        }
    }
    
    Write-Status "Viewer files copied" 'Success'
} else {
    Write-Status "Viewer not found at $viewerSource - bundle will need viewer added separately" 'Warning'
}

# Create manifest
Write-Status "Creating manifest..." 'Info'
$manifest = @{
    schemaVersion = '0.6.0'
    siteName      = 'SimTreeNav Demo'
    generatedAt   = (Get-Date).ToString('o')
    generator     = 'DemoStory v0.6.0'
    nodeCount     = $NodeCount
    snapshotCount = $SnapshotCount
    viewer        = @{
        basePath = ''
    }
    files         = @{
        nodes    = 'nodes.json'
        timeline = 'timeline.json'
        diff     = 'diff.json'
        actions  = 'actions.json'
        impact   = 'impact.json'
        drift    = 'drift.json'
    }
}
$manifestPath = Join-Path $OutDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Set-Content $manifestPath -Encoding UTF8
Write-Status "Manifest created" 'Success'

# Summary
Write-Host ""
Write-Host "======================================" -ForegroundColor Cyan
Write-Status "Demo bundle generation complete!" 'Success'
Write-Host ""
Write-Host "Bundle contents:" -ForegroundColor White
Get-ChildItem $OutDir -Recurse | ForEach-Object {
    $indent = '  ' * ($_.FullName.Replace($OutDir, '').Split([IO.Path]::DirectorySeparatorChar).Count - 1)
    $name = if ($_.PSIsContainer) { "$($_.Name)/" } else { $_.Name }
    $size = if (-not $_.PSIsContainer) { " ($([Math]::Round($_.Length / 1KB, 1)) KB)" } else { '' }
    Write-Host "  $indent$name$size" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Statistics:" -ForegroundColor White
Write-Host "  Nodes:     $NodeCount" -ForegroundColor Gray
Write-Host "  Snapshots: $SnapshotCount" -ForegroundColor Gray
Write-Host "  Changes:   $($diff.changes.Count)" -ForegroundColor Gray
Write-Host "  Actions:   $($actions.Count)" -ForegroundColor Gray

# Open viewer if requested
if (-not $NoOpen) {
    $indexPath = Join-Path $OutDir 'index.html'
    if (Test-Path $indexPath) {
        Write-Host ""
        Write-Status "Opening viewer in browser..." 'Info'
        Start-Process $indexPath
    }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Deploy: .\DeployPack.ps1 -BundlePath $OutDir -OutDir ./deploy/site -SiteName demo" -ForegroundColor Gray
Write-Host "  2. Verify: .\VerifyDeploy.ps1 -SiteDir ./deploy/site" -ForegroundColor Gray
