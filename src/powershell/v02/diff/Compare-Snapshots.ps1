# Compare-Snapshots.ps1
# Compares two snapshots and generates a diff report
# Detects: Added, Removed, Renamed, Moved, Attribute changes, Transform changes

<#
.SYNOPSIS
    Compares two snapshots and produces a diff.

.DESCRIPTION
    Detects the following change types:
    - Added: New nodes not in baseline
    - Removed: Nodes missing from current
    - Renamed: Same nodeId, different name
    - Moved: Same nodeId, different parentId/path
    - AttributeChanged: Same nodeId, different attributes
    - TransformChanged: Same nodeId, different transform hash

.EXAMPLE
    .\Compare-Snapshots.ps1 -BaselinePath "./snapshots/20260115_100000_baseline" -CurrentPath "./snapshots/20260115_110000_current"

.EXAMPLE
    .\Compare-Snapshots.ps1 -BaselinePath "./snapshots/20260115_100000_baseline" -CurrentPath "./snapshots/20260115_110000_current" -OutputPath "./diffs/diff_001"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaselinePath,
    
    [Parameter(Mandatory = $true)]
    [string]$CurrentPath,
    
    [string]$OutputPath = '',
    
    [switch]$Pretty,
    
    [switch]$GenerateHtml
)

$ErrorActionPreference = 'Stop'

# Change type enum
$Script:ChangeTypes = @{
    Added             = 'added'
    Removed           = 'removed'
    Renamed           = 'renamed'
    Moved             = 'moved'
    AttributeChanged  = 'attribute_changed'
    TransformChanged  = 'transform_changed'
}

function Read-Snapshot {
    <#
    .SYNOPSIS
        Reads a snapshot from disk.
    #>
    param([string]$Path)
    
    $nodesFile = Join-Path $Path 'nodes.json'
    $metaFile = Join-Path $Path 'meta.json'
    
    if (-not (Test-Path $nodesFile)) {
        Write-Error "nodes.json not found at: $nodesFile"
        return $null
    }
    
    $nodes = Get-Content $nodesFile -Raw | ConvertFrom-Json
    $meta = if (Test-Path $metaFile) {
        Get-Content $metaFile -Raw | ConvertFrom-Json
    } else {
        [PSCustomObject]@{ timestamp = 'unknown'; label = 'unknown' }
    }
    
    return [PSCustomObject]@{
        Nodes = $nodes
        Meta  = $meta
        Path  = $Path
    }
}

function Compare-Nodes {
    <#
    .SYNOPSIS
        Compares two node sets and returns a list of changes.
    #>
    param(
        [array]$BaselineNodes,
        [array]$CurrentNodes
    )
    
    $changes = @()
    
    # Build lookup maps
    $baselineMap = @{}
    foreach ($node in $BaselineNodes) {
        $baselineMap[$node.nodeId] = $node
    }
    
    $currentMap = @{}
    foreach ($node in $CurrentNodes) {
        $currentMap[$node.nodeId] = $node
    }
    
    # Find added nodes (in current but not in baseline)
    foreach ($nodeId in $currentMap.Keys) {
        if (-not $baselineMap.ContainsKey($nodeId)) {
            $node = $currentMap[$nodeId]
            $changes += [PSCustomObject]@{
                changeType = $Script:ChangeTypes.Added
                nodeId     = $nodeId
                nodeName   = $node.name
                nodeType   = $node.nodeType
                path       = $node.path
                parentId   = $node.parentId
                details    = $null
                before     = $null
                after      = $node
            }
        }
    }
    
    # Find removed nodes (in baseline but not in current)
    foreach ($nodeId in $baselineMap.Keys) {
        if (-not $currentMap.ContainsKey($nodeId)) {
            $node = $baselineMap[$nodeId]
            $changes += [PSCustomObject]@{
                changeType = $Script:ChangeTypes.Removed
                nodeId     = $nodeId
                nodeName   = $node.name
                nodeType   = $node.nodeType
                path       = $node.path
                parentId   = $node.parentId
                details    = $null
                before     = $node
                after      = $null
            }
        }
    }
    
    # Find modified nodes (same nodeId, different properties)
    foreach ($nodeId in $currentMap.Keys) {
        if (-not $baselineMap.ContainsKey($nodeId)) {
            continue
        }
        
        $baseline = $baselineMap[$nodeId]
        $current = $currentMap[$nodeId]
        
        # Check for rename
        if ($baseline.name -ne $current.name) {
            $changes += [PSCustomObject]@{
                changeType = $Script:ChangeTypes.Renamed
                nodeId     = $nodeId
                nodeName   = $current.name
                nodeType   = $current.nodeType
                path       = $current.path
                parentId   = $current.parentId
                details    = [PSCustomObject]@{
                    oldName = $baseline.name
                    newName = $current.name
                }
                before     = $baseline
                after      = $current
            }
        }
        
        # Check for move (different parent)
        if ($baseline.parentId -ne $current.parentId) {
            $changes += [PSCustomObject]@{
                changeType = $Script:ChangeTypes.Moved
                nodeId     = $nodeId
                nodeName   = $current.name
                nodeType   = $current.nodeType
                path       = $current.path
                parentId   = $current.parentId
                details    = [PSCustomObject]@{
                    oldParentId = $baseline.parentId
                    newParentId = $current.parentId
                    oldPath     = $baseline.path
                    newPath     = $current.path
                }
                before     = $baseline
                after      = $current
            }
        }
        
        # Check for attribute changes (using fingerprints)
        $baselineAttrHash = if ($baseline.fingerprints) { $baseline.fingerprints.attributeHash } else { $null }
        $currentAttrHash = if ($current.fingerprints) { $current.fingerprints.attributeHash } else { $null }
        
        if ($baselineAttrHash -ne $currentAttrHash -and ($baselineAttrHash -or $currentAttrHash)) {
            $changes += [PSCustomObject]@{
                changeType = $Script:ChangeTypes.AttributeChanged
                nodeId     = $nodeId
                nodeName   = $current.name
                nodeType   = $current.nodeType
                path       = $current.path
                parentId   = $current.parentId
                details    = [PSCustomObject]@{
                    oldHash = $baselineAttrHash
                    newHash = $currentAttrHash
                }
                before     = $baseline
                after      = $current
            }
        }
        
        # Check for transform changes
        $baselineTransformHash = if ($baseline.fingerprints) { $baseline.fingerprints.transformHash } else { $null }
        $currentTransformHash = if ($current.fingerprints) { $current.fingerprints.transformHash } else { $null }
        
        if ($baselineTransformHash -ne $currentTransformHash -and ($baselineTransformHash -or $currentTransformHash)) {
            $changes += [PSCustomObject]@{
                changeType = $Script:ChangeTypes.TransformChanged
                nodeId     = $nodeId
                nodeName   = $current.name
                nodeType   = $current.nodeType
                path       = $current.path
                parentId   = $current.parentId
                details    = [PSCustomObject]@{
                    oldHash = $baselineTransformHash
                    newHash = $currentTransformHash
                }
                before     = $baseline
                after      = $current
            }
        }
    }
    
    return $changes
}

function Get-ChangeSummary {
    <#
    .SYNOPSIS
        Generates a summary of changes by type and subtree.
    #>
    param([array]$Changes)
    
    $byType = $Changes | Group-Object changeType | ForEach-Object {
        [PSCustomObject]@{
            type  = $_.Name
            count = $_.Count
        }
    }
    
    # Find hot subtrees (most changes)
    $pathCounts = @{}
    foreach ($change in $Changes) {
        if ($change.path) {
            # Get root subtree (first two levels)
            $parts = $change.path -split '/' | Where-Object { $_ }
            $subtree = if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" } else { "/$($parts[0])" }
            if (-not $pathCounts.ContainsKey($subtree)) {
                $pathCounts[$subtree] = 0
            }
            $pathCounts[$subtree]++
        }
    }
    
    $hotSubtrees = $pathCounts.GetEnumerator() | 
        Sort-Object Value -Descending | 
        Select-Object -First 10 |
        ForEach-Object {
            [PSCustomObject]@{
                path  = $_.Key
                count = $_.Value
            }
        }
    
    # Group by node type
    $byNodeType = $Changes | Group-Object nodeType | ForEach-Object {
        [PSCustomObject]@{
            nodeType = $_.Name
            count    = $_.Count
        }
    }
    
    return [PSCustomObject]@{
        totalChanges   = $Changes.Count
        byChangeType   = $byType
        byNodeType     = $byNodeType
        hotSubtrees    = $hotSubtrees
    }
}

function Export-DiffHtml {
    <#
    .SYNOPSIS
        Generates an HTML diff report.
    #>
    param(
        [PSCustomObject]$Diff,
        [string]$OutputPath
    )
    
    $summary = $Diff.summary
    $changes = $Diff.changes
    
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>SimTreeNav Diff Report</title>
    <style>
        body { font-family: 'Segoe UI', sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #667eea; padding-bottom: 10px; }
        h2 { color: #444; margin-top: 20px; }
        .summary { display: flex; gap: 20px; flex-wrap: wrap; margin: 20px 0; }
        .summary-card { background: #f8f9fa; padding: 15px 20px; border-radius: 5px; min-width: 150px; }
        .summary-card h3 { margin: 0 0 10px 0; font-size: 14px; color: #666; }
        .summary-card .count { font-size: 24px; font-weight: bold; color: #333; }
        .change-added { color: #28a745; }
        .change-removed { color: #dc3545; }
        .change-renamed { color: #fd7e14; }
        .change-moved { color: #6f42c1; }
        .change-attribute_changed { color: #17a2b8; }
        .change-transform_changed { color: #e83e8c; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; }
        th, td { padding: 10px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f8f9fa; }
        .badge { display: inline-block; padding: 3px 8px; border-radius: 3px; font-size: 12px; color: white; }
        .badge-added { background: #28a745; }
        .badge-removed { background: #dc3545; }
        .badge-renamed { background: #fd7e14; }
        .badge-moved { background: #6f42c1; }
        .badge-attribute_changed { background: #17a2b8; }
        .badge-transform_changed { background: #e83e8c; }
        .details { font-size: 12px; color: #666; }
        .path { font-family: monospace; font-size: 12px; color: #888; }
    </style>
</head>
<body>
    <div class="container">
        <h1>SimTreeNav Diff Report</h1>
        <p>Baseline: <strong>$($Diff.baseline.path)</strong></p>
        <p>Current: <strong>$($Diff.current.path)</strong></p>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        
        <h2>Summary</h2>
        <div class="summary">
            <div class="summary-card">
                <h3>Total Changes</h3>
                <div class="count">$($summary.totalChanges)</div>
            </div>
"@
    
    foreach ($ct in $summary.byChangeType) {
        $html += @"
            <div class="summary-card">
                <h3>$($ct.type)</h3>
                <div class="count change-$($ct.type)">$($ct.count)</div>
            </div>
"@
    }
    
    $html += @"
        </div>
        
        <h2>Hot Subtrees</h2>
        <table>
            <tr><th>Subtree</th><th>Changes</th></tr>
"@
    
    foreach ($hs in $summary.hotSubtrees) {
        $html += "<tr><td class='path'>$($hs.path)</td><td>$($hs.count)</td></tr>`n"
    }
    
    $html += @"
        </table>
        
        <h2>All Changes</h2>
        <table>
            <tr><th>Type</th><th>Node</th><th>Path</th><th>Details</th></tr>
"@
    
    foreach ($change in $changes) {
        $detailsHtml = ''
        if ($change.details) {
            if ($change.changeType -eq 'renamed') {
                $detailsHtml = "$($change.details.oldName) → $($change.details.newName)"
            } elseif ($change.changeType -eq 'moved') {
                $detailsHtml = "Parent: $($change.details.oldParentId) → $($change.details.newParentId)"
            } else {
                $detailsHtml = "Hash changed"
            }
        }
        
        $html += @"
            <tr>
                <td><span class="badge badge-$($change.changeType)">$($change.changeType)</span></td>
                <td>$($change.nodeName) <span class="details">($($change.nodeId))</span></td>
                <td class="path">$($change.path)</td>
                <td class="details">$detailsHtml</td>
            </tr>
"@
    }
    
    $html += @"
        </table>
    </div>
</body>
</html>
"@
    
    $htmlFile = Join-Path $OutputPath 'diff.html'
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($htmlFile, $html, $utf8NoBom)
    
    Write-Host "    HTML report: $htmlFile" -ForegroundColor Gray
}

# Main comparison function
function Invoke-SnapshotComparison {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SimTreeNav Diff Engine" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Read snapshots
    Write-Host "  Loading snapshots..." -ForegroundColor Cyan
    $baseline = Read-Snapshot -Path $BaselinePath
    $current = Read-Snapshot -Path $CurrentPath
    
    if (-not $baseline -or -not $current) {
        Write-Error "Failed to load snapshots"
        return $null
    }
    
    Write-Host "    Baseline: $($baseline.Nodes.Count) nodes" -ForegroundColor Gray
    Write-Host "    Current:  $($current.Nodes.Count) nodes" -ForegroundColor Gray
    
    # Compare
    Write-Host "  Comparing nodes..." -ForegroundColor Cyan
    $changes = Compare-Nodes -BaselineNodes $baseline.Nodes -CurrentNodes $current.Nodes
    
    Write-Host "    Found $($changes.Count) changes" -ForegroundColor Gray
    
    # Generate summary
    Write-Host "  Generating summary..." -ForegroundColor Cyan
    $summary = Get-ChangeSummary -Changes $changes
    
    # Build diff object
    $diff = [PSCustomObject]@{
        version   = '0.2.0'
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        baseline  = [PSCustomObject]@{
            path      = $BaselinePath
            timestamp = $baseline.Meta.timestamp
            nodeCount = $baseline.Nodes.Count
        }
        current   = [PSCustomObject]@{
            path      = $CurrentPath
            timestamp = $current.Meta.timestamp
            nodeCount = $current.Nodes.Count
        }
        summary   = $summary
        changes   = $changes
    }
    
    # Output
    if ($OutputPath) {
        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        }
        
        Write-Host "  Writing diff files..." -ForegroundColor Cyan
        
        $jsonDepth = 10
        $diffJson = if ($Pretty) {
            $diff | ConvertTo-Json -Depth $jsonDepth
        } else {
            $diff | ConvertTo-Json -Depth $jsonDepth -Compress
        }
        
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText((Join-Path $OutputPath 'diff.json'), $diffJson, $utf8NoBom)
        
        if ($GenerateHtml) {
            Export-DiffHtml -Diff $diff -OutputPath $OutputPath
        }
        
        Write-Host "    Output: $OutputPath" -ForegroundColor Gray
    }
    
    # Print summary
    Write-Host ""
    Write-Host "  Summary:" -ForegroundColor Green
    Write-Host "    Total changes: $($summary.totalChanges)" -ForegroundColor White
    
    foreach ($ct in $summary.byChangeType) {
        $color = switch ($ct.type) {
            'added'             { 'Green' }
            'removed'           { 'Red' }
            'renamed'           { 'Yellow' }
            'moved'             { 'Magenta' }
            'attribute_changed' { 'Cyan' }
            'transform_changed' { 'DarkMagenta' }
            default             { 'Gray' }
        }
        Write-Host "      $($ct.type): $($ct.count)" -ForegroundColor $color
    }
    
    if ($summary.hotSubtrees -and $summary.hotSubtrees.Count -gt 0) {
        Write-Host ""
        Write-Host "    Hot subtrees:" -ForegroundColor Yellow
        foreach ($hs in $summary.hotSubtrees | Select-Object -First 5) {
            Write-Host "      $($hs.path): $($hs.count) changes" -ForegroundColor Gray
        }
    }
    
    Write-Host ""
    
    return $diff
}

# Run comparison
$result = Invoke-SnapshotComparison
$result
