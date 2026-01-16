# Compare-Snapshots.ps1
# Compares two snapshots and generates a diff report
# v0.3: Uses IdentityResolver for stable matching across DB rekeys

<#
.SYNOPSIS
    Compares two snapshots and produces a diff with identity-aware matching.

.DESCRIPTION
    Detects the following change types:
    - Added: New nodes not in baseline
    - Removed: Nodes missing from current
    - Rekeyed: Same logical node, different nodeId (NEW in v0.3)
    - Renamed: Same node, different name
    - Moved: Same node, different parentId/path
    - AttributeChanged: Same node, different attributes
    - TransformChanged: Same node, different transform hash

.EXAMPLE
    .\Compare-Snapshots.ps1 -BaselinePath "./snapshots/baseline" -CurrentPath "./snapshots/current"

.EXAMPLE
    .\Compare-Snapshots.ps1 -BaselinePath "./snapshots/baseline" -CurrentPath "./snapshots/current" -UseIdentityMatching -ConfidenceThreshold 0.85
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BaselinePath,
    
    [Parameter(Mandatory = $true)]
    [string]$CurrentPath,
    
    [string]$OutputPath = '',
    
    [switch]$Pretty,
    
    [switch]$GenerateHtml,
    
    [switch]$UseIdentityMatching = $true,
    
    [double]$ConfidenceThreshold = 0.85,
    
    [switch]$Compress
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# Import IdentityResolver
$identityResolverPath = Join-Path $scriptRoot '..\core\IdentityResolver.ps1'
if (Test-Path $identityResolverPath) {
    . $identityResolverPath
}

# Change type enum (v0.3: added 'rekeyed')
$Script:ChangeTypes = @{
    Added             = 'added'
    Removed           = 'removed'
    Rekeyed           = 'rekeyed'
    Renamed           = 'renamed'
    Moved             = 'moved'
    AttributeChanged  = 'attribute_changed'
    TransformChanged  = 'transform_changed'
}

function Read-Snapshot {
    <#
    .SYNOPSIS
        Reads a snapshot from disk with optional decompression.
    #>
    param([string]$Path)
    
    $nodesFile = Join-Path $Path 'nodes.json'
    $nodesGzFile = Join-Path $Path 'nodes.json.gz'
    $metaFile = Join-Path $Path 'meta.json'
    
    # Try compressed first, then uncompressed
    $nodes = $null
    if (Test-Path $nodesGzFile) {
        try {
            $gzStream = [System.IO.File]::OpenRead($nodesGzFile)
            $decompStream = New-Object System.IO.Compression.GZipStream($gzStream, [System.IO.Compression.CompressionMode]::Decompress)
            $reader = New-Object System.IO.StreamReader($decompStream)
            $jsonContent = $reader.ReadToEnd()
            $reader.Close()
            $nodes = $jsonContent | ConvertFrom-Json
        }
        catch {
            Write-Warning "Failed to read compressed nodes: $_"
        }
    }
    
    if (-not $nodes -and (Test-Path $nodesFile)) {
        $nodes = Get-Content $nodesFile -Raw | ConvertFrom-Json
    }
    
    if (-not $nodes) {
        Write-Error "nodes.json not found at: $Path"
        return $null
    }
    
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

function Compare-NodesWithIdentity {
    <#
    .SYNOPSIS
        Compares two node sets using identity-aware matching.
    
    .DESCRIPTION
        Uses IdentityResolver to handle rekeyed nodes where the
        database OBJECT_ID changed but the logical node is the same.
    #>
    param(
        [array]$BaselineNodes,
        [array]$CurrentNodes,
        [double]$ConfidenceThreshold = 0.85
    )
    
    $changes = @()
    
    # Build identity map
    $identityMap = Build-IdentityMap -BaselineNodes $BaselineNodes -CurrentNodes $CurrentNodes -ConfidenceThreshold $ConfidenceThreshold
    
    # Process added nodes
    foreach ($node in $identityMap.addedNodes) {
        $changes += [PSCustomObject]@{
            changeType      = $Script:ChangeTypes.Added
            nodeId          = $node.nodeId
            logicalId       = if ($node.identity) { $node.identity.logicalId } else { $null }
            nodeName        = $node.name
            nodeType        = $node.nodeType
            path            = $node.path
            parentId        = $node.parentId
            matchConfidence = $null
            matchReason     = $null
            details         = $null
            before          = $null
            after           = $node
        }
    }
    
    # Process removed nodes
    foreach ($node in $identityMap.removedNodes) {
        $changes += [PSCustomObject]@{
            changeType      = $Script:ChangeTypes.Removed
            nodeId          = $node.nodeId
            logicalId       = if ($node.identity) { $node.identity.logicalId } else { $null }
            nodeName        = $node.name
            nodeType        = $node.nodeType
            path            = $node.path
            parentId        = $node.parentId
            matchConfidence = $null
            matchReason     = $null
            details         = $null
            before          = $node
            after           = $null
        }
    }
    
    # Process matched nodes (including rekeyed)
    foreach ($mapping in $identityMap.mappings) {
        $baseline = $mapping.baselineNode
        $current = $mapping.currentNode
        
        # Check for rekey (different nodeId, same logical node)
        if ($mapping.matchType -like 'rekeyed*') {
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.Rekeyed
                nodeId          = $current.nodeId
                logicalId       = $mapping.logicalId
                nodeName        = $current.name
                nodeType        = $current.nodeType
                path            = $current.path
                parentId        = $current.parentId
                matchConfidence = $mapping.matchConfidence
                matchReason     = $mapping.matchReason
                details         = [PSCustomObject]@{
                    oldNodeId = $baseline.nodeId
                    newNodeId = $current.nodeId
                    matchType = $mapping.matchType
                }
                before          = $baseline
                after           = $current
            }
        }
        
        # Check for rename
        if ($baseline.name -ne $current.name) {
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.Renamed
                nodeId          = $current.nodeId
                logicalId       = $mapping.logicalId
                nodeName        = $current.name
                nodeType        = $current.nodeType
                path            = $current.path
                parentId        = $current.parentId
                matchConfidence = $mapping.matchConfidence
                matchReason     = $mapping.matchReason
                details         = [PSCustomObject]@{
                    oldName = $baseline.name
                    newName = $current.name
                }
                before          = $baseline
                after           = $current
            }
        }
        
        # Check for move (different parent)
        if ($baseline.parentId -ne $current.parentId) {
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.Moved
                nodeId          = $current.nodeId
                logicalId       = $mapping.logicalId
                nodeName        = $current.name
                nodeType        = $current.nodeType
                path            = $current.path
                parentId        = $current.parentId
                matchConfidence = $mapping.matchConfidence
                matchReason     = $mapping.matchReason
                details         = [PSCustomObject]@{
                    oldParentId = $baseline.parentId
                    newParentId = $current.parentId
                    oldPath     = $baseline.path
                    newPath     = $current.path
                }
                before          = $baseline
                after           = $current
            }
        }
        
        # Check for attribute changes
        $baselineAttrHash = if ($baseline.fingerprints) { $baseline.fingerprints.attributeHash } else { $null }
        $currentAttrHash = if ($current.fingerprints) { $current.fingerprints.attributeHash } else { $null }
        
        if ($baselineAttrHash -ne $currentAttrHash -and ($baselineAttrHash -or $currentAttrHash)) {
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.AttributeChanged
                nodeId          = $current.nodeId
                logicalId       = $mapping.logicalId
                nodeName        = $current.name
                nodeType        = $current.nodeType
                path            = $current.path
                parentId        = $current.parentId
                matchConfidence = $mapping.matchConfidence
                matchReason     = $mapping.matchReason
                details         = [PSCustomObject]@{
                    oldHash = $baselineAttrHash
                    newHash = $currentAttrHash
                }
                before          = $baseline
                after           = $current
            }
        }
        
        # Check for transform changes
        $baselineTransformHash = if ($baseline.fingerprints) { $baseline.fingerprints.transformHash } else { $null }
        $currentTransformHash = if ($current.fingerprints) { $current.fingerprints.transformHash } else { $null }
        
        if ($baselineTransformHash -ne $currentTransformHash -and ($baselineTransformHash -or $currentTransformHash)) {
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.TransformChanged
                nodeId          = $current.nodeId
                logicalId       = $mapping.logicalId
                nodeName        = $current.name
                nodeType        = $current.nodeType
                path            = $current.path
                parentId        = $current.parentId
                matchConfidence = $mapping.matchConfidence
                matchReason     = $mapping.matchReason
                details         = [PSCustomObject]@{
                    oldHash = $baselineTransformHash
                    newHash = $currentTransformHash
                }
                before          = $baseline
                after           = $current
            }
        }
    }
    
    return [PSCustomObject]@{
        changes     = $changes
        identityMap = $identityMap
    }
}

function Compare-NodesLegacy {
    <#
    .SYNOPSIS
        Legacy node comparison using only nodeId (v0.2 behavior).
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
    
    # Find added nodes
    foreach ($nodeId in $currentMap.Keys) {
        if (-not $baselineMap.ContainsKey($nodeId)) {
            $node = $currentMap[$nodeId]
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.Added
                nodeId          = $nodeId
                logicalId       = $null
                nodeName        = $node.name
                nodeType        = $node.nodeType
                path            = $node.path
                parentId        = $node.parentId
                matchConfidence = $null
                matchReason     = $null
                details         = $null
                before          = $null
                after           = $node
            }
        }
    }
    
    # Find removed nodes
    foreach ($nodeId in $baselineMap.Keys) {
        if (-not $currentMap.ContainsKey($nodeId)) {
            $node = $baselineMap[$nodeId]
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.Removed
                nodeId          = $nodeId
                logicalId       = $null
                nodeName        = $node.name
                nodeType        = $node.nodeType
                path            = $node.path
                parentId        = $node.parentId
                matchConfidence = $null
                matchReason     = $null
                details         = $null
                before          = $node
                after           = $null
            }
        }
    }
    
    # Find modified nodes
    foreach ($nodeId in $currentMap.Keys) {
        if (-not $baselineMap.ContainsKey($nodeId)) { continue }
        
        $baseline = $baselineMap[$nodeId]
        $current = $currentMap[$nodeId]
        
        if ($baseline.name -ne $current.name) {
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.Renamed
                nodeId          = $nodeId
                logicalId       = $null
                nodeName        = $current.name
                nodeType        = $current.nodeType
                path            = $current.path
                parentId        = $current.parentId
                matchConfidence = 1.0
                matchReason     = 'exact_nodeId'
                details         = [PSCustomObject]@{ oldName = $baseline.name; newName = $current.name }
                before          = $baseline
                after           = $current
            }
        }
        
        if ($baseline.parentId -ne $current.parentId) {
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.Moved
                nodeId          = $nodeId
                logicalId       = $null
                nodeName        = $current.name
                nodeType        = $current.nodeType
                path            = $current.path
                parentId        = $current.parentId
                matchConfidence = 1.0
                matchReason     = 'exact_nodeId'
                details         = [PSCustomObject]@{ oldParentId = $baseline.parentId; newParentId = $current.parentId; oldPath = $baseline.path; newPath = $current.path }
                before          = $baseline
                after           = $current
            }
        }
        
        $baselineAttrHash = if ($baseline.fingerprints) { $baseline.fingerprints.attributeHash } else { $null }
        $currentAttrHash = if ($current.fingerprints) { $current.fingerprints.attributeHash } else { $null }
        if ($baselineAttrHash -ne $currentAttrHash -and ($baselineAttrHash -or $currentAttrHash)) {
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.AttributeChanged
                nodeId          = $nodeId
                logicalId       = $null
                nodeName        = $current.name
                nodeType        = $current.nodeType
                path            = $current.path
                parentId        = $current.parentId
                matchConfidence = 1.0
                matchReason     = 'exact_nodeId'
                details         = [PSCustomObject]@{ oldHash = $baselineAttrHash; newHash = $currentAttrHash }
                before          = $baseline
                after           = $current
            }
        }
        
        $baselineTransformHash = if ($baseline.fingerprints) { $baseline.fingerprints.transformHash } else { $null }
        $currentTransformHash = if ($current.fingerprints) { $current.fingerprints.transformHash } else { $null }
        if ($baselineTransformHash -ne $currentTransformHash -and ($baselineTransformHash -or $currentTransformHash)) {
            $changes += [PSCustomObject]@{
                changeType      = $Script:ChangeTypes.TransformChanged
                nodeId          = $nodeId
                logicalId       = $null
                nodeName        = $current.name
                nodeType        = $current.nodeType
                path            = $current.path
                parentId        = $current.parentId
                matchConfidence = 1.0
                matchReason     = 'exact_nodeId'
                details         = [PSCustomObject]@{ oldHash = $baselineTransformHash; newHash = $currentTransformHash }
                before          = $baseline
                after           = $current
            }
        }
    }
    
    return [PSCustomObject]@{
        changes     = $changes
        identityMap = $null
    }
}

function Get-ChangeSummary {
    <#
    .SYNOPSIS
        Generates a summary of changes by type and subtree.
    #>
    param(
        [array]$Changes,
        [PSCustomObject]$IdentityMap = $null
    )
    
    $byType = $Changes | Group-Object changeType | ForEach-Object {
        [PSCustomObject]@{
            type  = $_.Name
            count = $_.Count
        }
    }
    
    # Find hot subtrees
    $pathCounts = @{}
    foreach ($change in $Changes) {
        if ($change.path) {
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
    
    $byNodeType = $Changes | Group-Object nodeType | ForEach-Object {
        [PSCustomObject]@{
            nodeType = $_.Name
            count    = $_.Count
        }
    }
    
    $summary = [PSCustomObject]@{
        totalChanges   = $Changes.Count
        byChangeType   = $byType
        byNodeType     = $byNodeType
        hotSubtrees    = $hotSubtrees
    }
    
    # Add identity stats if available
    if ($IdentityMap -and $IdentityMap.stats) {
        $summary | Add-Member -NotePropertyName 'identityStats' -NotePropertyValue $IdentityMap.stats
    }
    
    return $summary
}

function Export-DiffHtml {
    <#
    .SYNOPSIS
        Generates an HTML diff report with v0.3 features.
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
    <title>SimTreeNav Diff Report v0.3</title>
    <style>
        * { box-sizing: border-box; }
        body { font-family: 'Segoe UI', sans-serif; margin: 0; background: #1a1a2e; color: #eee; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; }
        .header h1 { margin: 0; color: white; font-size: 28px; }
        .header p { margin: 5px 0 0 0; color: rgba(255,255,255,0.8); }
        .container { max-width: 1400px; margin: 0 auto; padding: 20px; }
        .summary-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(140px, 1fr)); gap: 15px; margin: 20px 0; }
        .summary-card { background: #16213e; padding: 20px; border-radius: 10px; text-align: center; border: 1px solid #0f3460; }
        .summary-card h3 { margin: 0 0 10px 0; font-size: 12px; color: #888; text-transform: uppercase; }
        .summary-card .count { font-size: 32px; font-weight: bold; }
        .change-added { color: #00d26a; }
        .change-removed { color: #ff6b6b; }
        .change-rekeyed { color: #ffd93d; }
        .change-renamed { color: #ff9f43; }
        .change-moved { color: #a55eea; }
        .change-attribute_changed { color: #54a0ff; }
        .change-transform_changed { color: #ff6b81; }
        .section { background: #16213e; border-radius: 10px; padding: 20px; margin: 20px 0; border: 1px solid #0f3460; }
        .section h2 { margin: 0 0 15px 0; color: #667eea; font-size: 18px; border-bottom: 1px solid #0f3460; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #0f3460; }
        th { color: #888; font-size: 12px; text-transform: uppercase; }
        .badge { display: inline-block; padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: bold; text-transform: uppercase; }
        .badge-added { background: rgba(0,210,106,0.2); color: #00d26a; }
        .badge-removed { background: rgba(255,107,107,0.2); color: #ff6b6b; }
        .badge-rekeyed { background: rgba(255,217,61,0.2); color: #ffd93d; }
        .badge-renamed { background: rgba(255,159,67,0.2); color: #ff9f43; }
        .badge-moved { background: rgba(165,94,234,0.2); color: #a55eea; }
        .badge-attribute_changed { background: rgba(84,160,255,0.2); color: #54a0ff; }
        .badge-transform_changed { background: rgba(255,107,129,0.2); color: #ff6b81; }
        .path { font-family: 'Consolas', monospace; font-size: 12px; color: #888; }
        .details { font-size: 12px; color: #aaa; }
        .confidence { font-size: 11px; color: #667eea; margin-left: 10px; }
        .hot-bar { height: 6px; background: #0f3460; border-radius: 3px; overflow: hidden; margin-top: 5px; }
        .hot-bar-fill { height: 100%; background: linear-gradient(90deg, #667eea, #764ba2); }
        .identity-stats { display: grid; grid-template-columns: repeat(4, 1fr); gap: 10px; margin-top: 15px; padding-top: 15px; border-top: 1px solid #0f3460; }
        .identity-stat { text-align: center; }
        .identity-stat .value { font-size: 20px; font-weight: bold; color: #667eea; }
        .identity-stat .label { font-size: 11px; color: #888; }
    </style>
</head>
<body>
    <div class="header">
        <h1>SimTreeNav Diff Report</h1>
        <p>Version 0.3 | Identity-Aware Comparison</p>
    </div>
    <div class="container">
        <div class="section">
            <p><strong>Baseline:</strong> $($Diff.baseline.path) ($($Diff.baseline.nodeCount) nodes)</p>
            <p><strong>Current:</strong> $($Diff.current.path) ($($Diff.current.nodeCount) nodes)</p>
            <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        </div>
        
        <div class="summary-grid">
            <div class="summary-card">
                <h3>Total Changes</h3>
                <div class="count" style="color: white;">$($summary.totalChanges)</div>
            </div>
"@
    
    $typeOrder = @('added', 'removed', 'rekeyed', 'renamed', 'moved', 'attribute_changed', 'transform_changed')
    foreach ($type in $typeOrder) {
        $ct = $summary.byChangeType | Where-Object { $_.type -eq $type }
        $count = if ($ct) { $ct.count } else { 0 }
        if ($count -gt 0) {
            $html += @"
            <div class="summary-card">
                <h3>$type</h3>
                <div class="count change-$type">$count</div>
            </div>
"@
        }
    }
    
    $html += "</div>"
    
    # Identity stats if available
    if ($summary.identityStats) {
        $stats = $summary.identityStats
        $html += @"
        <div class="section">
            <h2>Identity Resolution Stats</h2>
            <div class="identity-stats">
                <div class="identity-stat">
                    <div class="value">$($stats.exactMatches)</div>
                    <div class="label">Exact Matches</div>
                </div>
                <div class="identity-stat">
                    <div class="value">$($stats.rekeyedMatches)</div>
                    <div class="label">Rekeyed Nodes</div>
                </div>
                <div class="identity-stat">
                    <div class="value">$($stats.addedCount)</div>
                    <div class="label">Added</div>
                </div>
                <div class="identity-stat">
                    <div class="value">$($stats.removedCount)</div>
                    <div class="label">Removed</div>
                </div>
            </div>
        </div>
"@
    }
    
    # Hot subtrees
    if ($summary.hotSubtrees -and $summary.hotSubtrees.Count -gt 0) {
        $maxCount = ($summary.hotSubtrees | Measure-Object -Property count -Maximum).Maximum
        $html += @"
        <div class="section">
            <h2>Hot Subtrees</h2>
            <table>
                <tr><th>Subtree</th><th>Changes</th><th></th></tr>
"@
        foreach ($hs in $summary.hotSubtrees) {
            $pct = if ($maxCount -gt 0) { [Math]::Round($hs.count / $maxCount * 100) } else { 0 }
            $html += @"
                <tr>
                    <td class="path">$($hs.path)</td>
                    <td>$($hs.count)</td>
                    <td style="width: 200px;"><div class="hot-bar"><div class="hot-bar-fill" style="width: $pct%;"></div></div></td>
                </tr>
"@
        }
        $html += "</table></div>"
    }
    
    # All changes
    $html += @"
        <div class="section">
            <h2>All Changes ($($changes.Count))</h2>
            <table>
                <tr><th>Type</th><th>Node</th><th>Path</th><th>Details</th></tr>
"@
    
    foreach ($change in $changes | Select-Object -First 500) {
        $detailsHtml = ''
        if ($change.details) {
            switch ($change.changeType) {
                'renamed' { $detailsHtml = "$($change.details.oldName) → $($change.details.newName)" }
                'moved' { $detailsHtml = "Parent: $($change.details.oldParentId) → $($change.details.newParentId)" }
                'rekeyed' { $detailsHtml = "ID: $($change.details.oldNodeId) → $($change.details.newNodeId)" }
                default { $detailsHtml = "Hash changed" }
            }
        }
        
        $confidenceHtml = ''
        if ($change.matchConfidence -and $change.matchConfidence -lt 1.0) {
            $confidenceHtml = "<span class='confidence'>($([Math]::Round($change.matchConfidence * 100))% confidence)</span>"
        }
        
        $html += @"
            <tr>
                <td><span class="badge badge-$($change.changeType)">$($change.changeType)</span></td>
                <td>$($change.nodeName) <span class="details">($($change.nodeId))</span>$confidenceHtml</td>
                <td class="path">$($change.path)</td>
                <td class="details">$detailsHtml</td>
            </tr>
"@
    }
    
    if ($changes.Count -gt 500) {
        $html += "<tr><td colspan='4' style='text-align:center; color:#888;'>... and $($changes.Count - 500) more changes</td></tr>"
    }
    
    $html += @"
            </table>
        </div>
    </div>
</body>
</html>
"@
    
    $htmlFile = Join-Path $OutputPath 'diff.html'
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($htmlFile, $html, $utf8NoBom)
    
    Write-Host "    HTML report: $htmlFile" -ForegroundColor Gray
}

function Write-CompressedJson {
    <#
    .SYNOPSIS
        Writes JSON with optional gzip compression.
    #>
    param(
        [string]$Path,
        [string]$Json,
        [switch]$Compress
    )
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    
    if ($Compress) {
        $gzPath = "$Path.gz"
        $bytes = $utf8NoBom.GetBytes($Json)
        $fileStream = [System.IO.File]::Create($gzPath)
        $gzStream = New-Object System.IO.Compression.GZipStream($fileStream, [System.IO.Compression.CompressionMode]::Compress)
        $gzStream.Write($bytes, 0, $bytes.Length)
        $gzStream.Close()
        $fileStream.Close()
        Write-Host "    Compressed: $gzPath" -ForegroundColor Gray
    }
    else {
        [System.IO.File]::WriteAllText($Path, $Json, $utf8NoBom)
    }
}

# Main comparison function
function Invoke-SnapshotComparison {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SimTreeNav Diff Engine v0.3" -ForegroundColor Yellow
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
    
    # Compare using identity-aware or legacy method
    Write-Host "  Comparing nodes..." -ForegroundColor Cyan
    $result = if ($UseIdentityMatching) {
        Write-Host "    Using identity-aware matching (threshold: $ConfidenceThreshold)" -ForegroundColor Gray
        Compare-NodesWithIdentity -BaselineNodes $baseline.Nodes -CurrentNodes $current.Nodes -ConfidenceThreshold $ConfidenceThreshold
    }
    else {
        Write-Host "    Using legacy nodeId matching" -ForegroundColor Gray
        Compare-NodesLegacy -BaselineNodes $baseline.Nodes -CurrentNodes $current.Nodes
    }
    
    $changes = $result.changes
    Write-Host "    Found $($changes.Count) changes" -ForegroundColor Gray
    
    # Generate summary
    Write-Host "  Generating summary..." -ForegroundColor Cyan
    $summary = Get-ChangeSummary -Changes $changes -IdentityMap $result.identityMap
    
    # Build diff object
    $diff = [PSCustomObject]@{
        version   = '0.3.0'
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
        config    = [PSCustomObject]@{
            useIdentityMatching = $UseIdentityMatching.IsPresent
            confidenceThreshold = $ConfidenceThreshold
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
        
        Write-CompressedJson -Path (Join-Path $OutputPath 'diff.json') -Json $diffJson -Compress:$Compress
        
        if ($GenerateHtml) {
            Export-DiffHtml -Diff $diff -OutputPath $OutputPath
        }
        
        Write-Host "    Output: $OutputPath" -ForegroundColor Gray
    }
    
    # Print summary
    Write-Host ""
    Write-Host "  Summary:" -ForegroundColor Green
    Write-Host "    Total changes: $($summary.totalChanges)" -ForegroundColor White
    
    $typeColors = @{
        'added' = 'Green'; 'removed' = 'Red'; 'rekeyed' = 'Yellow'
        'renamed' = 'DarkYellow'; 'moved' = 'Magenta'
        'attribute_changed' = 'Cyan'; 'transform_changed' = 'DarkMagenta'
    }
    
    foreach ($ct in $summary.byChangeType) {
        $color = if ($typeColors.ContainsKey($ct.type)) { $typeColors[$ct.type] } else { 'Gray' }
        Write-Host "      $($ct.type): $($ct.count)" -ForegroundColor $color
    }
    
    if ($summary.identityStats) {
        Write-Host ""
        Write-Host "    Identity resolution:" -ForegroundColor Yellow
        Write-Host "      Exact matches: $($summary.identityStats.exactMatches)" -ForegroundColor Gray
        Write-Host "      Rekeyed: $($summary.identityStats.rekeyedMatches)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    return $diff
}

# Run comparison
$result = Invoke-SnapshotComparison
$result
