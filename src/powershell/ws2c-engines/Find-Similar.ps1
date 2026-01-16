<#
.SYNOPSIS
    Finds similar nodes/subtrees based on structural fingerprinting.
    
.DESCRIPTION
    Uses shape hash and attribute summary hash to find nodes similar
    to the specified source node. Returns candidates sorted by
    similarity score with explanations.
    
.PARAMETER NodesPath
    Path to the nodes JSON file.
    
.PARAMETER NodeId
    The source node ID to find similar nodes for.
    
.PARAMETER Top
    Maximum number of similar candidates to return.
    
.PARAMETER OutPath
    Output path for the similarity results JSON file.
    
.EXAMPLE
    Find-Similar -NodesPath nodes.json -NodeId "10" -Top 10 -OutPath similar.json
#>

function Find-Similar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodesPath,
        
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $false)]
        [int]$Top = 10,
        
        [Parameter(Mandatory = $true)]
        [string]$OutPath
    )
    
    # Guard: Check if nodes file exists
    if (-not (Test-Path $NodesPath)) {
        Write-Warning "Nodes file not found: $NodesPath"
        return $false
    }
    
    # Load nodes
    $nodes = Get-Content $NodesPath | ConvertFrom-Json
    
    # Guard: Check if nodes array is empty
    if ($nodes.Count -eq 0) {
        Write-Warning "Nodes file is empty"
        return $false
    }
    
    # Build node lookup
    $nodeMap = @{}
    foreach ($node in $nodes) {
        $nodeMap[$node.id] = $node
    }
    
    # Guard: Check if source node exists
    if (-not $nodeMap.ContainsKey($NodeId)) {
        Write-Warning "Source node not found: $NodeId"
        return $false
    }
    
    $sourceNode = $nodeMap[$NodeId]
    
    # Build parent-child lookup
    $childrenMap = @{}
    foreach ($node in $nodes) {
        if ($node.parentId) {
            if (-not $childrenMap.ContainsKey($node.parentId)) {
                $childrenMap[$node.parentId] = @()
            }
            $childrenMap[$node.parentId] += $node
        }
    }
    
    # Calculate fingerprint for source node subtree
    $sourceFingerprint = Get-SubtreeFingerprint -Node $sourceNode -NodeMap $nodeMap -ChildrenMap $childrenMap
    
    # Find similar nodes (same type, different ID)
    $candidates = @()
    
    foreach ($node in $nodes) {
        # Skip source node itself
        if ($node.id -eq $NodeId) {
            continue
        }
        
        # Only compare nodes of same type
        if ($node.nodeType -ne $sourceNode.nodeType) {
            continue
        }
        
        # Calculate fingerprint for candidate
        $candidateFingerprint = Get-SubtreeFingerprint -Node $node -NodeMap $nodeMap -ChildrenMap $childrenMap
        
        # Calculate similarity score
        $similarity = Calculate-Similarity -SourceFP $sourceFingerprint -CandidateFP $candidateFingerprint
        
        # Build explanation
        $why = Build-SimilarityExplanation -SourceFP $sourceFingerprint -CandidateFP $candidateFingerprint -Score $similarity.score
        
        # Build evidence
        $evidence = @{
            shapeMatch = $similarity.shapeMatch
            attributeMatch = $similarity.attributeMatch
            childCountDiff = [Math]::Abs($sourceFingerprint.childCount - $candidateFingerprint.childCount)
            commonTypes = $similarity.commonTypes
        }
        
        $candidates += @{
            nodeId = $node.id
            nodeName = $node.name
            nodeType = $node.nodeType
            similarityScore = [Math]::Round($similarity.score, 4)
            why = $why
            evidence = $evidence
        }
    }
    
    # Sort by similarity score (descending), then by nodeId (ascending) for stability
    $candidates = $candidates | Sort-Object @{Expression = { $_.similarityScore }; Descending = $true }, @{Expression = { $_.nodeId }; Ascending = $true }
    
    # Take top N
    $candidates = $candidates | Select-Object -First $Top
    
    # Build result
    $result = [ordered]@{
        sourceNodeId = $NodeId
        sourceNodeName = $sourceNode.name
        sourceNodeType = $sourceNode.nodeType
        searchedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        candidatesFound = $candidates.Count
        candidates = $candidates
        algorithm = @{
            useShapeHash = $true
            useAttributeHash = $true
            version = "1.0"
        }
    }
    
    # Ensure output directory exists
    $outDir = Split-Path $OutPath -Parent
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    
    # Write results
    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $OutPath -Encoding UTF8
    
    return $true
}

function Get-SubtreeFingerprint {
    param(
        [Parameter(Mandatory = $true)]
        $Node,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$NodeMap,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$ChildrenMap
    )
    
    # Collect subtree nodes (BFS)
    $subtreeNodes = @()
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue($Node.id)
    $visited = @{}
    
    while ($queue.Count -gt 0) {
        $currentId = $queue.Dequeue()
        
        if ($visited.ContainsKey($currentId)) {
            continue
        }
        $visited[$currentId] = $true
        
        if ($NodeMap.ContainsKey($currentId)) {
            $subtreeNodes += $NodeMap[$currentId]
        }
        
        # Enqueue children
        if ($ChildrenMap.ContainsKey($currentId)) {
            foreach ($child in $ChildrenMap[$currentId]) {
                if (-not $visited.ContainsKey($child.id)) {
                    $queue.Enqueue($child.id)
                }
            }
        }
    }
    
    # Build shape signature (type distribution)
    $typeCounts = @{}
    foreach ($node in $subtreeNodes) {
        $nodeType = $node.nodeType
        if (-not $nodeType) {
            $nodeType = "Unknown"
        }
        if (-not $typeCounts.ContainsKey($nodeType)) {
            $typeCounts[$nodeType] = 0
        }
        $typeCounts[$nodeType]++
    }
    
    # Shape hash: sorted type:count pairs
    $shapeHash = ($typeCounts.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name):$($_.Value)" }) -join "|"
    
    # Attribute summary
    $attrSummary = @{}
    foreach ($node in $subtreeNodes) {
        if ($node.attributes) {
            foreach ($attr in $node.attributes.PSObject.Properties) {
                $key = "$($node.nodeType).$($attr.Name)"
                if (-not $attrSummary.ContainsKey($key)) {
                    $attrSummary[$key] = @()
                }
                $attrSummary[$key] += $attr.Value
            }
        }
    }
    
    # Attribute hash: sorted key:valueType pairs
    $attrHash = ($attrSummary.GetEnumerator() | Sort-Object Name | ForEach-Object { 
        $valueType = if ($_.Value.Count -gt 0) { $_.Value[0].GetType().Name } else { "null" }
        "$($_.Name):$valueType" 
    }) -join "|"
    
    # Direct children count and types
    $directChildren = if ($ChildrenMap.ContainsKey($Node.id)) { $ChildrenMap[$Node.id] } else { @() }
    $childTypes = ($directChildren | ForEach-Object { $_.nodeType } | Sort-Object -Unique) -join ","
    
    return @{
        shapeHash = $shapeHash
        attributeHash = $attrHash
        nodeCount = $subtreeNodes.Count
        childCount = $directChildren.Count
        childTypes = $childTypes
        typeCounts = $typeCounts
        attrSummary = $attrSummary
    }
}

function Calculate-Similarity {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SourceFP,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CandidateFP
    )
    
    # Shape similarity (Jaccard-like)
    $sourceTypes = [System.Collections.Generic.HashSet[string]]::new()
    $candidateTypes = [System.Collections.Generic.HashSet[string]]::new()
    
    foreach ($key in $SourceFP.typeCounts.Keys) {
        $sourceTypes.Add($key) | Out-Null
    }
    foreach ($key in $CandidateFP.typeCounts.Keys) {
        $candidateTypes.Add($key) | Out-Null
    }
    
    $intersection = [System.Collections.Generic.HashSet[string]]::new($sourceTypes)
    $intersection.IntersectWith($candidateTypes)
    
    $union = [System.Collections.Generic.HashSet[string]]::new($sourceTypes)
    $union.UnionWith($candidateTypes)
    
    $typeJaccard = if ($union.Count -gt 0) { $intersection.Count / $union.Count } else { 0 }
    
    # Count similarity
    $maxCount = [Math]::Max($SourceFP.nodeCount, $CandidateFP.nodeCount)
    $countDiff = [Math]::Abs($SourceFP.nodeCount - $CandidateFP.nodeCount)
    $countSimilarity = if ($maxCount -gt 0) { 1 - ($countDiff / $maxCount) } else { 1 }
    
    # Shape hash exact match bonus
    $shapeMatch = ($SourceFP.shapeHash -eq $CandidateFP.shapeHash)
    $shapeBonus = if ($shapeMatch) { 0.2 } else { 0 }
    
    # Attribute hash similarity
    $sourceAttrs = [System.Collections.Generic.HashSet[string]]::new()
    $candidateAttrs = [System.Collections.Generic.HashSet[string]]::new()
    
    foreach ($key in $SourceFP.attrSummary.Keys) {
        $sourceAttrs.Add($key) | Out-Null
    }
    foreach ($key in $CandidateFP.attrSummary.Keys) {
        $candidateAttrs.Add($key) | Out-Null
    }
    
    $attrIntersection = [System.Collections.Generic.HashSet[string]]::new($sourceAttrs)
    $attrIntersection.IntersectWith($candidateAttrs)
    
    $attrUnion = [System.Collections.Generic.HashSet[string]]::new($sourceAttrs)
    $attrUnion.UnionWith($candidateAttrs)
    
    $attrJaccard = if ($attrUnion.Count -gt 0) { $attrIntersection.Count / $attrUnion.Count } else { 1 }
    
    $attributeMatch = ($SourceFP.attributeHash -eq $CandidateFP.attributeHash)
    $attrBonus = if ($attributeMatch) { 0.1 } else { 0 }
    
    # Child types similarity
    $childTypeSimilarity = 0
    if ($SourceFP.childTypes -eq $CandidateFP.childTypes) {
        $childTypeSimilarity = 0.1
    }
    
    # Weighted score
    $score = ($typeJaccard * 0.35) + ($countSimilarity * 0.25) + ($attrJaccard * 0.2) + $shapeBonus + $attrBonus + $childTypeSimilarity
    
    # Clamp to [0, 1]
    $score = [Math]::Max(0, [Math]::Min(1, $score))
    
    return @{
        score = $score
        shapeMatch = $shapeMatch
        attributeMatch = $attributeMatch
        typeJaccard = $typeJaccard
        countSimilarity = $countSimilarity
        attrJaccard = $attrJaccard
        commonTypes = @($intersection)
    }
}

function Build-SimilarityExplanation {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$SourceFP,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CandidateFP,
        
        [Parameter(Mandatory = $true)]
        [double]$Score
    )
    
    $reasons = @()
    
    if ($SourceFP.shapeHash -eq $CandidateFP.shapeHash) {
        $reasons += "Identical structure shape"
    }
    
    if ($SourceFP.nodeCount -eq $CandidateFP.nodeCount) {
        $reasons += "Same node count ($($SourceFP.nodeCount))"
    }
    
    if ($SourceFP.childCount -eq $CandidateFP.childCount) {
        $reasons += "Same direct child count ($($SourceFP.childCount))"
    }
    
    if ($SourceFP.childTypes -eq $CandidateFP.childTypes -and $SourceFP.childTypes) {
        $reasons += "Same child types ($($SourceFP.childTypes))"
    }
    
    if ($SourceFP.attributeHash -eq $CandidateFP.attributeHash) {
        $reasons += "Matching attribute patterns"
    }
    
    if ($reasons.Count -eq 0) {
        $reasons += "Partial structure match"
    }
    
    return $reasons -join "; "
}

# Export function for module use
Export-ModuleMember -Function Find-Similar -ErrorAction SilentlyContinue
