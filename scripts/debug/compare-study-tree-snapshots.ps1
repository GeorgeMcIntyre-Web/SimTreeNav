# Compare Study Tree Snapshots
# Purpose: Detect changes between two tree snapshots (rename, move, structure, resource mapping)
# Date: 2026-01-30

param(
    [Parameter(Mandatory=$true)]
    [string]$BaselineSnapshot,

    [Parameter(Mandatory=$true)]
    [string]$CurrentSnapshot,

    [string]$OutputFile = "",
    [switch]$ShowDetails
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Study Tree Snapshot Comparison" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Baseline: $BaselineSnapshot" -ForegroundColor Gray
Write-Host "  Current:  $CurrentSnapshot" -ForegroundColor Gray
Write-Host ""

# Validate snapshot files
if (-not (Test-Path $BaselineSnapshot)) {
    Write-Error "Baseline snapshot not found: $BaselineSnapshot"
    exit 1
}

if (-not (Test-Path $CurrentSnapshot)) {
    Write-Error "Current snapshot not found: $CurrentSnapshot"
    exit 1
}

# Load snapshots
Write-Host "[1/5] Loading snapshots..." -ForegroundColor Yellow

try {
    $baseline = Get-Content $BaselineSnapshot -Raw | ConvertFrom-Json
    $current = Get-Content $CurrentSnapshot -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse snapshot JSON: $_"
    exit 1
}

Write-Host "  Baseline: $($baseline.meta.nodeCount) nodes (captured $($baseline.meta.capturedAt))" -ForegroundColor Gray
Write-Host "  Current:  $($current.meta.nodeCount) nodes (captured $($current.meta.capturedAt))" -ForegroundColor Gray

# Build node lookup maps by node_id
# When duplicates exist (versioned tables), keep the most-populated entry
function Get-NodePopulationScore {
    param($node)
    $score = 0
    if ($node.display_name -and $node.display_name -ne 'Shortcut') { $score += 2 }
    if ($node.resource_name) { $score += 2 }
    if ($null -ne $node.x) { $score += 2 }
    if ($node.name_provenance) { $score++ }
    if ($node.mapping_type -and $node.mapping_type -ne 'none') { $score++ }
    return $score
}

$baselineMap = @{}
$baselineDupes = 0
foreach ($node in $baseline.nodes) {
    $id = "$($node.node_id)"
    if (-not $baselineMap.ContainsKey($id)) {
        $baselineMap[$id] = $node
    } else {
        $baselineDupes++
        if ((Get-NodePopulationScore $node) -gt (Get-NodePopulationScore $baselineMap[$id])) {
            $baselineMap[$id] = $node
        }
    }
}

$currentMap = @{}
$currentDupes = 0
foreach ($node in $current.nodes) {
    $id = "$($node.node_id)"
    if (-not $currentMap.ContainsKey($id)) {
        $currentMap[$id] = $node
    } else {
        $currentDupes++
        if ((Get-NodePopulationScore $node) -gt (Get-NodePopulationScore $currentMap[$id])) {
            $currentMap[$id] = $node
        }
    }
}

if ($baselineDupes -gt 0 -or $currentDupes -gt 0) {
    Write-Host "  Note: Deduplicated $baselineDupes baseline / $currentDupes current duplicate entries" -ForegroundColor DarkYellow
}

# Initialize change tracking
$changes = @{
    renamed = @()
    moved = @()
    structuralChanges = @()
    resourceMappingChanges = @()
    nodesAdded = @()
    nodesRemoved = @()
}

Write-Host "`n[2/5] Detecting renamed nodes..." -ForegroundColor Yellow

# Find renamed nodes (same node_id, different display_name)
foreach ($nodeId in $currentMap.Keys) {
    if ($baselineMap.ContainsKey($nodeId)) {
        $baseNode = $baselineMap[$nodeId]
        $currNode = $currentMap[$nodeId]

        if ($baseNode.display_name -ne $currNode.display_name) {
            $changes.renamed += [PSCustomObject]@{
                node_id = $nodeId
                old_name = $baseNode.display_name
                new_name = $currNode.display_name
                node_type = $currNode.node_type
                old_provenance = $baseNode.name_provenance
                new_provenance = $currNode.name_provenance
            }
        }
    }
}

Write-Host "  Found $($changes.renamed.Count) renamed nodes" -ForegroundColor $(if ($changes.renamed.Count -gt 0) { 'Green' } else { 'Gray' })

Write-Host "`n[3/5] Detecting moved nodes..." -ForegroundColor Yellow

# Find moved nodes (same node_id, different coordinates)
foreach ($nodeId in $currentMap.Keys) {
    if ($baselineMap.ContainsKey($nodeId)) {
        $baseNode = $baselineMap[$nodeId]
        $currNode = $currentMap[$nodeId]

        # Only compare if both have coordinates
        if ($baseNode.x -ne $null -and $currNode.x -ne $null) {
            $dx = [Math]::Round(($currNode.x - $baseNode.x), 2)
            $dy = [Math]::Round(($currNode.y - $baseNode.y), 2)
            $dz = [Math]::Round(($currNode.z - $baseNode.z), 2)

            $delta_mm = [Math]::Max([Math]::Max([Math]::Abs($dx), [Math]::Abs($dy)), [Math]::Abs($dz))

            if ($delta_mm -gt 0.01) {  # Ignore tiny floating point differences
                $movementType = if ($delta_mm -ge 1000) { "WORLD" } else { "SIMPLE" }

                $changes.moved += [PSCustomObject]@{
                    node_id = $nodeId
                    display_name = $currNode.display_name
                    node_type = $currNode.node_type
                    old_x = $baseNode.x
                    old_y = $baseNode.y
                    old_z = $baseNode.z
                    new_x = $currNode.x
                    new_y = $currNode.y
                    new_z = $currNode.z
                    delta_x = $dx
                    delta_y = $dy
                    delta_z = $dz
                    delta_mm = $delta_mm
                    movement_type = $movementType
                    mapping_type = $currNode.mapping_type
                }
            }
        }
    }
}

$simpleMove = @($changes.moved | Where-Object { $_.movement_type -eq "SIMPLE" })
$worldMove = @($changes.moved | Where-Object { $_.movement_type -eq "WORLD" })

Write-Host "  Found $($changes.moved.Count) moved nodes" -ForegroundColor $(if ($changes.moved.Count -gt 0) { 'Green' } else { 'Gray' })
if ($simpleMove.Count -gt 0) {
    Write-Host "    Simple moves (<1000mm): $($simpleMove.Count)" -ForegroundColor Cyan
}
if ($worldMove.Count -gt 0) {
    Write-Host "    World moves (>=1000mm): $($worldMove.Count)" -ForegroundColor Magenta
}

Write-Host "`n[4/5] Detecting structural changes..." -ForegroundColor Yellow

# Find structural changes (parent changed)
foreach ($nodeId in $currentMap.Keys) {
    if ($baselineMap.ContainsKey($nodeId)) {
        $baseNode = $baselineMap[$nodeId]
        $currNode = $currentMap[$nodeId]

        if ($baseNode.parent_node_id -ne $currNode.parent_node_id) {
            $changes.structuralChanges += [PSCustomObject]@{
                node_id = $nodeId
                display_name = $currNode.display_name
                node_type = $currNode.node_type
                old_parent_id = $baseNode.parent_node_id
                new_parent_id = $currNode.parent_node_id
                change_type = "parent_changed"
            }
        }
    }
}

# Find added nodes
foreach ($nodeId in $currentMap.Keys) {
    if (-not $baselineMap.ContainsKey($nodeId)) {
        $currNode = $currentMap[$nodeId]
        $changes.nodesAdded += [PSCustomObject]@{
            node_id = $nodeId
            display_name = $currNode.display_name
            node_type = $currNode.node_type
            parent_node_id = $currNode.parent_node_id
            is_shortcut = $currNode.is_shortcut
            resource_name = $currNode.resource_name
        }
    }
}

# Find removed nodes
foreach ($nodeId in $baselineMap.Keys) {
    if (-not $currentMap.ContainsKey($nodeId)) {
        $baseNode = $baselineMap[$nodeId]
        $changes.nodesRemoved += [PSCustomObject]@{
            node_id = $nodeId
            display_name = $baseNode.display_name
            node_type = $baseNode.node_type
            parent_node_id = $baseNode.parent_node_id
            is_shortcut = $baseNode.is_shortcut
            resource_name = $baseNode.resource_name
        }
    }
}

Write-Host "  Found $($changes.structuralChanges.Count) parent changes" -ForegroundColor $(if ($changes.structuralChanges.Count -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Found $($changes.nodesAdded.Count) added nodes" -ForegroundColor $(if ($changes.nodesAdded.Count -gt 0) { 'Green' } else { 'Gray' })
Write-Host "  Found $($changes.nodesRemoved.Count) removed nodes" -ForegroundColor $(if ($changes.nodesRemoved.Count -gt 0) { 'Green' } else { 'Gray' })

Write-Host "`n[5/5] Detecting resource mapping changes..." -ForegroundColor Yellow

# Find resource mapping changes (shortcut points to different resource)
foreach ($nodeId in $currentMap.Keys) {
    if ($baselineMap.ContainsKey($nodeId)) {
        $baseNode = $baselineMap[$nodeId]
        $currNode = $currentMap[$nodeId]

        if ($currNode.is_shortcut -and $baseNode.is_shortcut) {
            if ($baseNode.resource_id -ne $currNode.resource_id) {
                $changes.resourceMappingChanges += [PSCustomObject]@{
                    node_id = $nodeId
                    shortcut_name = $currNode.display_name
                    old_resource_id = $baseNode.resource_id
                    old_resource_name = $baseNode.resource_name
                    new_resource_id = $currNode.resource_id
                    new_resource_name = $currNode.resource_name
                }
            }
        }
    }
}

Write-Host "  Found $($changes.resourceMappingChanges.Count) resource mapping changes" -ForegroundColor $(if ($changes.resourceMappingChanges.Count -gt 0) { 'Green' } else { 'Gray' })

# Build diff summary
$diff = @{
    meta = @{
        schemaVersion = "1.0.0"
        comparedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        baselineFile = $BaselineSnapshot
        currentFile = $CurrentSnapshot
        baselineCaptured = $baseline.meta.capturedAt
        currentCaptured = $current.meta.capturedAt
        studyId = $current.meta.studyId
        studyName = $current.meta.studyName
        totalChanges = $changes.renamed.Count + $changes.moved.Count + $changes.structuralChanges.Count + $changes.resourceMappingChanges.Count + $changes.nodesAdded.Count + $changes.nodesRemoved.Count
    }
    summary = @{
        renamed = $changes.renamed.Count
        moved = $changes.moved.Count
        simple_moves = $simpleMove.Count
        world_moves = $worldMove.Count
        structural_changes = $changes.structuralChanges.Count
        resource_mapping_changes = $changes.resourceMappingChanges.Count
        nodes_added = $changes.nodesAdded.Count
        nodes_removed = $changes.nodesRemoved.Count
    }
    changes = @{
        renamed = $changes.renamed
        moved = $changes.moved
        structuralChanges = $changes.structuralChanges
        resourceMappingChanges = $changes.resourceMappingChanges
        nodesAdded = $changes.nodesAdded
        nodesRemoved = $changes.nodesRemoved
    }
}

# Determine output file
if (-not $OutputFile) {
    $timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $OutputFile = "data/output/tree-diff-$($current.meta.studyId)-$timestamp.json"
}

# Ensure output directory exists
$outputDir = Split-Path $OutputFile -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Write diff to file
$diff | ConvertTo-Json -Depth 10 | Out-File $OutputFile -Encoding UTF8

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Comparison Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Output: $OutputFile" -ForegroundColor White
Write-Host ""
Write-Host "  Summary of Changes:" -ForegroundColor White
Write-Host "    Renamed nodes:             $($diff.summary.renamed)" -ForegroundColor $(if ($diff.summary.renamed -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "    Moved nodes:               $($diff.summary.moved)" -ForegroundColor $(if ($diff.summary.moved -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "      - Simple (<1000mm):      $($diff.summary.simple_moves)" -ForegroundColor Cyan
Write-Host "      - World (>=1000mm):      $($diff.summary.world_moves)" -ForegroundColor Magenta
Write-Host "    Structural changes:        $($diff.summary.structural_changes)" -ForegroundColor $(if ($diff.summary.structural_changes -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "    Resource mapping changes:  $($diff.summary.resource_mapping_changes)" -ForegroundColor $(if ($diff.summary.resource_mapping_changes -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "    Nodes added:               $($diff.summary.nodes_added)" -ForegroundColor $(if ($diff.summary.nodes_added -gt 0) { 'Green' } else { 'Gray' })
Write-Host "    Nodes removed:             $($diff.summary.nodes_removed)" -ForegroundColor $(if ($diff.summary.nodes_removed -gt 0) { 'Red' } else { 'Gray' })
Write-Host ""
Write-Host "  Total changes: $($diff.meta.totalChanges)" -ForegroundColor White
Write-Host ""

# Show details if requested
if ($ShowDetails) {
    if ($changes.renamed.Count -gt 0) {
        Write-Host "`nRenamed Nodes:" -ForegroundColor Yellow
        foreach ($change in $changes.renamed) {
            Write-Host "  [$($change.node_type)] $($change.old_name) -> $($change.new_name)" -ForegroundColor White
        }
    }

    if ($worldMove.Count -gt 0) {
        Write-Host "`nWorld Moves (>= 1000mm):" -ForegroundColor Magenta
        foreach ($move in $worldMove) {
            Write-Host "  [$($move.node_type)] $($move.display_name)" -ForegroundColor White
            Write-Host "    Delta: ($($move.delta_x), $($move.delta_y), $($move.delta_z)) mm = $($move.delta_mm)mm" -ForegroundColor Gray
        }
    }

    if ($changes.nodesAdded.Count -gt 0) {
        Write-Host "`nAdded Nodes:" -ForegroundColor Green
        foreach ($node in $changes.nodesAdded) {
            Write-Host "  [$($node.node_type)] $($node.display_name)" -ForegroundColor White
            if ($node.resource_name) {
                Write-Host "    Resource: $($node.resource_name)" -ForegroundColor Gray
            }
        }
    }

    if ($changes.nodesRemoved.Count -gt 0) {
        Write-Host "`nRemoved Nodes:" -ForegroundColor Red
        foreach ($node in $changes.nodesRemoved) {
            Write-Host "  [$($node.node_type)] $($node.display_name)" -ForegroundColor White
        }
    }
}

exit 0
