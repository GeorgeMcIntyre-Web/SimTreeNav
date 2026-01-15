# NarrativeEngine.ps1
# Groups diff events into meaningful "actions" for human understanding
# v0.3: Deterministic action inference (LLM-ready input)

<#
.SYNOPSIS
    Groups raw diff changes into meaningful narrative actions.

.DESCRIPTION
    Transforms low-level diff events into high-level actions like:
    - Rename: Node name changed
    - Move: Node relocated to different parent
    - RetaughtLocation: Transform/location changed (operation retaught)
    - BulkPasteCluster: Multiple similar nodes added together
    - PrototypeSwap: Tool instance changed its prototype
    - PanelDataChanged: Panel/part attributes modified
    - StationReorganized: Multiple related changes in one station

    This is deterministic (no LLM calls) - produces structured input for
    later LLM summarization if desired.

.EXAMPLE
    $actions = Invoke-NarrativeAnalysis -Changes $diff.changes
#>

# Action type definitions
$Script:ActionTypes = @{
    Rename            = 'rename'
    Move              = 'move'
    RetaughtLocation  = 'retaught_location'
    BulkPasteCluster  = 'bulk_paste_cluster'
    BulkDelete        = 'bulk_delete'
    PrototypeSwap     = 'prototype_swap'
    PanelDataChanged  = 'panel_data_changed'
    StationReorganized = 'station_reorganized'
    ToolingChange     = 'tooling_change'
    NewNode           = 'new_node'
    DeletedNode       = 'deleted_node'
    Rekeyed           = 'rekeyed'
    AttributeUpdate   = 'attribute_update'
}

function Group-ChangesByPath {
    <#
    .SYNOPSIS
        Groups changes by their path prefix for cluster detection.
    #>
    param([array]$Changes)
    
    $groups = @{}
    
    foreach ($change in $Changes) {
        $path = $change.path
        if (-not $path) { continue }
        
        # Get parent path (first two levels)
        $parts = $path -split '/' | Where-Object { $_ }
        $prefix = if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" } else { "/$($parts[0])" }
        
        if (-not $groups.ContainsKey($prefix)) {
            $groups[$prefix] = @()
        }
        $groups[$prefix] += $change
    }
    
    return $groups
}

function Group-ChangesByType {
    <#
    .SYNOPSIS
        Groups changes by their change type.
    #>
    param([array]$Changes)
    
    $groups = @{}
    
    foreach ($change in $Changes) {
        $type = $change.changeType
        if (-not $groups.ContainsKey($type)) {
            $groups[$type] = @()
        }
        $groups[$type] += $change
    }
    
    return $groups
}

function Detect-BulkPasteCluster {
    <#
    .SYNOPSIS
        Detects bulk paste operations (multiple similar nodes added together).
    #>
    param([array]$AddedChanges)
    
    $clusters = @()
    
    if ($AddedChanges.Count -lt 3) {
        return $clusters
    }
    
    # Group by parent path
    $byParent = @{}
    foreach ($change in $AddedChanges) {
        $parts = $change.path -split '/' | Where-Object { $_ }
        $parentPath = if ($parts.Count -gt 1) { '/' + ($parts[0..($parts.Count - 2)] -join '/') } else { '/' }
        
        if (-not $byParent.ContainsKey($parentPath)) {
            $byParent[$parentPath] = @()
        }
        $byParent[$parentPath] += $change
    }
    
    # Look for clusters (3+ nodes added to same parent)
    foreach ($parent in $byParent.Keys) {
        $nodes = $byParent[$parent]
        if ($nodes.Count -ge 3) {
            # Check if names follow a pattern (e.g., Node_001, Node_002, ...)
            $names = $nodes | ForEach-Object { $_.nodeName }
            $commonPrefix = Get-CommonPrefix -Strings $names
            
            $clusters += [PSCustomObject]@{
                parentPath    = $parent
                nodeCount     = $nodes.Count
                commonPrefix  = $commonPrefix
                nodeTypes     = ($nodes | Group-Object nodeType | ForEach-Object { $_.Name }) -join ', '
                evidence      = $nodes | Select-Object nodeId, nodeName, path
            }
        }
    }
    
    return $clusters
}

function Get-CommonPrefix {
    <#
    .SYNOPSIS
        Finds common prefix among a set of strings.
    #>
    param([array]$Strings)
    
    if (-not $Strings -or $Strings.Count -eq 0) {
        return ''
    }
    
    if ($Strings.Count -eq 1) {
        return $Strings[0]
    }
    
    $first = $Strings[0]
    $prefix = ''
    
    for ($i = 0; $i -lt $first.Length; $i++) {
        $char = $first[$i]
        $allMatch = $true
        
        foreach ($str in $Strings[1..($Strings.Count - 1)]) {
            if ($i -ge $str.Length -or $str[$i] -ne $char) {
                $allMatch = $false
                break
            }
        }
        
        if ($allMatch) {
            $prefix += $char
        }
        else {
            break
        }
    }
    
    # Trim trailing numbers/underscores for cleaner prefix
    $prefix = $prefix -replace '[_\d]+$', ''
    
    return $prefix
}

function Detect-StationReorganization {
    <#
    .SYNOPSIS
        Detects station reorganization (multiple related changes in one subtree).
    #>
    param(
        [array]$Changes,
        [int]$Threshold = 5
    )
    
    $reorganizations = @()
    
    $byPath = Group-ChangesByPath -Changes $Changes
    
    foreach ($path in $byPath.Keys) {
        $pathChanges = $byPath[$path]
        
        if ($pathChanges.Count -ge $Threshold) {
            $changeTypes = $pathChanges | Group-Object changeType
            $hasMultipleTypes = $changeTypes.Count -ge 2
            
            if ($hasMultipleTypes) {
                $reorganizations += [PSCustomObject]@{
                    subtree       = $path
                    changeCount   = $pathChanges.Count
                    changeTypes   = ($changeTypes | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ', '
                    evidence      = $pathChanges | Select-Object changeType, nodeId, nodeName
                }
            }
        }
    }
    
    return $reorganizations
}

function Detect-RetaughtLocations {
    <#
    .SYNOPSIS
        Detects retaught operations (transform changes on Operation nodes).
    #>
    param([array]$TransformChanges)
    
    $retaught = @()
    
    foreach ($change in $TransformChanges) {
        if ($change.nodeType -in @('Operation', 'Location')) {
            $retaught += [PSCustomObject]@{
                nodeId     = $change.nodeId
                nodeName   = $change.nodeName
                path       = $change.path
                nodeType   = $change.nodeType
                confidence = 0.9
                evidence   = $change
            }
        }
    }
    
    return $retaught
}

function Detect-ToolingChanges {
    <#
    .SYNOPSIS
        Detects tooling-related changes (tool prototypes, instances).
    #>
    param([array]$Changes)
    
    $toolingChanges = @()
    
    $toolTypes = @('ToolPrototype', 'ToolInstance')
    $toolChanges = $Changes | Where-Object { $_.nodeType -in $toolTypes }
    
    if ($toolChanges.Count -eq 0) {
        return $toolingChanges
    }
    
    # Group by change type
    $byType = $toolChanges | Group-Object changeType
    
    foreach ($group in $byType) {
        $toolingChanges += [PSCustomObject]@{
            changeType  = $group.Name
            nodeCount   = $group.Count
            nodes       = $group.Group | ForEach-Object { $_.nodeName }
            evidence    = $group.Group | Select-Object nodeId, nodeName, path, changeType
        }
    }
    
    return $toolingChanges
}

function New-NarrativeAction {
    <#
    .SYNOPSIS
        Creates a narrative action object.
    #>
    param(
        [string]$ActionType,
        [string]$Description,
        [double]$Confidence,
        [array]$Evidence,
        [hashtable]$Details = @{}
    )
    
    [PSCustomObject]@{
        actionType  = $ActionType
        description = $Description
        confidence  = [Math]::Round($Confidence, 2)
        timestamp   = (Get-Date).ToUniversalTime().ToString('o')
        evidence    = $Evidence
        details     = [PSCustomObject]$Details
    }
}

function Invoke-NarrativeAnalysis {
    <#
    .SYNOPSIS
        Main entry point for narrative analysis.
    
    .DESCRIPTION
        Analyzes raw diff changes and produces meaningful action groupings.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Changes,
        
        [int]$BulkThreshold = 3,
        
        [int]$ReorgThreshold = 5
    )
    
    $actions = @()
    
    # Group changes by type
    $byType = Group-ChangesByType -Changes $Changes
    
    # Process each change type
    
    # 1. Renames
    if ($byType.ContainsKey('renamed')) {
        foreach ($change in $byType['renamed']) {
            $actions += New-NarrativeAction `
                -ActionType $Script:ActionTypes.Rename `
                -Description "Renamed '$($change.details.oldName)' to '$($change.details.newName)'" `
                -Confidence 1.0 `
                -Evidence @($change) `
                -Details @{
                    oldName = $change.details.oldName
                    newName = $change.details.newName
                    path    = $change.path
                }
        }
    }
    
    # 2. Moves
    if ($byType.ContainsKey('moved')) {
        foreach ($change in $byType['moved']) {
            $actions += New-NarrativeAction `
                -ActionType $Script:ActionTypes.Move `
                -Description "Moved '$($change.nodeName)' from '$($change.details.oldPath)' to '$($change.details.newPath)'" `
                -Confidence 1.0 `
                -Evidence @($change) `
                -Details @{
                    oldPath = $change.details.oldPath
                    newPath = $change.details.newPath
                }
        }
    }
    
    # 3. Rekeyed nodes
    if ($byType.ContainsKey('rekeyed')) {
        foreach ($change in $byType['rekeyed']) {
            $actions += New-NarrativeAction `
                -ActionType $Script:ActionTypes.Rekeyed `
                -Description "Node '$($change.nodeName)' was rekeyed (ID: $($change.details.oldNodeId) → $($change.details.newNodeId))" `
                -Confidence $change.matchConfidence `
                -Evidence @($change) `
                -Details @{
                    oldNodeId = $change.details.oldNodeId
                    newNodeId = $change.details.newNodeId
                    matchReason = $change.matchReason
                }
        }
    }
    
    # 4. Transform changes (retaught locations)
    if ($byType.ContainsKey('transform_changed')) {
        $retaught = Detect-RetaughtLocations -TransformChanges $byType['transform_changed']
        foreach ($r in $retaught) {
            $actions += New-NarrativeAction `
                -ActionType $Script:ActionTypes.RetaughtLocation `
                -Description "Operation '$($r.nodeName)' was retaught/relocated" `
                -Confidence $r.confidence `
                -Evidence @($r.evidence) `
                -Details @{
                    nodeType = $r.nodeType
                    path = $r.path
                }
        }
    }
    
    # 5. Bulk paste clusters
    if ($byType.ContainsKey('added')) {
        $clusters = Detect-BulkPasteCluster -AddedChanges $byType['added']
        foreach ($cluster in $clusters) {
            $actions += New-NarrativeAction `
                -ActionType $Script:ActionTypes.BulkPasteCluster `
                -Description "Bulk paste of $($cluster.nodeCount) nodes under '$($cluster.parentPath)'" `
                -Confidence 0.85 `
                -Evidence $cluster.evidence `
                -Details @{
                    parentPath = $cluster.parentPath
                    nodeCount = $cluster.nodeCount
                    commonPrefix = $cluster.commonPrefix
                    nodeTypes = $cluster.nodeTypes
                }
        }
        
        # Individual adds not in clusters
        $clusteredIds = $clusters | ForEach-Object { $_.evidence } | ForEach-Object { $_.nodeId }
        $individualAdds = $byType['added'] | Where-Object { $_.nodeId -notin $clusteredIds }
        
        foreach ($add in $individualAdds) {
            $actions += New-NarrativeAction `
                -ActionType $Script:ActionTypes.NewNode `
                -Description "Added new node '$($add.nodeName)'" `
                -Confidence 1.0 `
                -Evidence @($add) `
                -Details @{
                    nodeType = $add.nodeType
                    path = $add.path
                }
        }
    }
    
    # 6. Bulk deletes
    if ($byType.ContainsKey('removed')) {
        $removed = $byType['removed']
        
        # Check for bulk delete pattern
        $byParent = @{}
        foreach ($r in $removed) {
            $parts = $r.path -split '/' | Where-Object { $_ }
            $parent = if ($parts.Count -gt 1) { '/' + ($parts[0..($parts.Count - 2)] -join '/') } else { '/' }
            if (-not $byParent.ContainsKey($parent)) { $byParent[$parent] = @() }
            $byParent[$parent] += $r
        }
        
        foreach ($parent in $byParent.Keys) {
            $nodes = $byParent[$parent]
            if ($nodes.Count -ge $BulkThreshold) {
                $actions += New-NarrativeAction `
                    -ActionType $Script:ActionTypes.BulkDelete `
                    -Description "Bulk delete of $($nodes.Count) nodes from '$parent'" `
                    -Confidence 0.85 `
                    -Evidence $nodes `
                    -Details @{
                        parentPath = $parent
                        nodeCount = $nodes.Count
                    }
            }
            else {
                foreach ($node in $nodes) {
                    $actions += New-NarrativeAction `
                        -ActionType $Script:ActionTypes.DeletedNode `
                        -Description "Deleted node '$($node.nodeName)'" `
                        -Confidence 1.0 `
                        -Evidence @($node) `
                        -Details @{
                            nodeType = $node.nodeType
                            path = $node.path
                        }
                }
            }
        }
    }
    
    # 7. Attribute changes
    if ($byType.ContainsKey('attribute_changed')) {
        foreach ($change in $byType['attribute_changed']) {
            $actions += New-NarrativeAction `
                -ActionType $Script:ActionTypes.AttributeUpdate `
                -Description "Attributes updated on '$($change.nodeName)'" `
                -Confidence 1.0 `
                -Evidence @($change) `
                -Details @{
                    path = $change.path
                    nodeType = $change.nodeType
                }
        }
    }
    
    # 8. Station reorganization (meta-action)
    $reorgs = Detect-StationReorganization -Changes $Changes -Threshold $ReorgThreshold
    foreach ($reorg in $reorgs) {
        $actions += New-NarrativeAction `
            -ActionType $Script:ActionTypes.StationReorganized `
            -Description "Station '$($reorg.subtree)' was reorganized ($($reorg.changeCount) changes)" `
            -Confidence 0.8 `
            -Evidence $reorg.evidence `
            -Details @{
                subtree = $reorg.subtree
                changeCount = $reorg.changeCount
                changeTypes = $reorg.changeTypes
            }
    }
    
    # 9. Tooling changes
    $tooling = Detect-ToolingChanges -Changes $Changes
    foreach ($tc in $tooling) {
        $actions += New-NarrativeAction `
            -ActionType $Script:ActionTypes.ToolingChange `
            -Description "Tooling change: $($tc.changeType) on $($tc.nodeCount) tool(s)" `
            -Confidence 0.9 `
            -Evidence $tc.evidence `
            -Details @{
                changeType = $tc.changeType
                nodeCount = $tc.nodeCount
                nodes = $tc.nodes
            }
    }
    
    # Sort actions by confidence (highest first), then by type
    $sortedActions = $actions | Sort-Object @{Expression = {$_.confidence}; Descending = $true}, actionType
    
    return $sortedActions
}

function Get-NarrativeSummary {
    <#
    .SYNOPSIS
        Generates a text summary of narrative actions.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Actions
    )
    
    $summary = @()
    $summary += "## Change Narrative"
    $summary += ""
    
    $byType = $Actions | Group-Object actionType
    
    foreach ($group in $byType | Sort-Object { $_.Group[0].confidence } -Descending) {
        $summary += "### $($group.Name) ($($group.Count))"
        
        foreach ($action in $group.Group | Select-Object -First 5) {
            $summary += "- $($action.description)"
        }
        
        if ($group.Count -gt 5) {
            $summary += "- ... and $($group.Count - 5) more"
        }
        
        $summary += ""
    }
    
    return $summary -join "`n"
}

function Export-NarrativeReport {
    <#
    .SYNOPSIS
        Exports narrative analysis as JSON and optional HTML.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Actions,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [switch]$Pretty,
        
        [switch]$GenerateHtml
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Write actions.json
    $actionsJson = if ($Pretty) {
        $Actions | ConvertTo-Json -Depth 10
    } else {
        $Actions | ConvertTo-Json -Depth 10 -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $OutputPath 'actions.json'), $actionsJson, $utf8NoBom)
    
    if ($GenerateHtml) {
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SimTreeNav Narrative Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 0; background: #1e1e2e; color: #cdd6f4; }
        .header { background: linear-gradient(135deg, #89b4fa, #cba6f7); padding: 30px; }
        .header h1 { margin: 0; color: #1e1e2e; }
        .container { max-width: 1200px; margin: 0 auto; padding: 20px; }
        .action-card { background: #313244; border-radius: 10px; padding: 20px; margin: 15px 0; border-left: 4px solid #89b4fa; }
        .action-type { font-size: 11px; color: #89b4fa; text-transform: uppercase; margin-bottom: 5px; }
        .action-desc { font-size: 16px; margin-bottom: 10px; }
        .confidence { font-size: 12px; color: #a6adc8; }
        .evidence { font-size: 12px; color: #6c7086; margin-top: 10px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin: 20px 0; }
        .summary-card { background: #313244; padding: 20px; border-radius: 10px; text-align: center; }
        .summary-card .count { font-size: 32px; font-weight: bold; color: #89b4fa; }
        .summary-card .label { font-size: 12px; color: #a6adc8; }
    </style>
</head>
<body>
    <div class="header">
        <h1>Narrative Report</h1>
        <p>SimTreeNav v0.3 | Action Analysis</p>
    </div>
    <div class="container">
        <div class="summary">
"@
        
        $byType = $Actions | Group-Object actionType
        foreach ($group in $byType) {
            $html += @"
            <div class="summary-card">
                <div class="count">$($group.Count)</div>
                <div class="label">$($group.Name)</div>
            </div>
"@
        }
        
        $html += "</div>"
        
        foreach ($action in $Actions | Select-Object -First 50) {
            $html += @"
        <div class="action-card">
            <div class="action-type">$($action.actionType)</div>
            <div class="action-desc">$($action.description)</div>
            <div class="confidence">Confidence: $([Math]::Round($action.confidence * 100))%</div>
        </div>
"@
        }
        
        if ($Actions.Count -gt 50) {
            $html += "<p style='text-align:center;color:#6c7086;'>... and $($Actions.Count - 50) more actions</p>"
        }
        
        $html += @"
    </div>
</body>
</html>
"@
        
        [System.IO.File]::WriteAllText((Join-Path $OutputPath 'narrative.html'), $html, $utf8NoBom)
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Invoke-NarrativeAnalysis',
    'Get-NarrativeSummary',
    'Export-NarrativeReport',
    'New-NarrativeAction',
    'Detect-BulkPasteCluster',
    'Detect-StationReorganization',
    'Detect-RetaughtLocations',
    'Detect-ToolingChanges'
)
