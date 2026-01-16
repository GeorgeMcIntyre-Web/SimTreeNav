# SimilarityEngine.ps1
# Computes subtree fingerprints and finds similar stations/studies
# v0.3: Similarity search for pattern reuse and auditing

<#
.SYNOPSIS
    Computes structural fingerprints and finds similar subtrees.

.DESCRIPTION
    For comparing stations/studies across or within projects:
    - Structural hash (tree shape)
    - Attribute summary hash
    - Name pattern fingerprint
    - Optional MinHash/LSH for scale

    Use cases:
    - "Find stations similar to this one"
    - Template reuse detection
    - Cross-study auditing
    - Detecting copy/paste lineage

.EXAMPLE
    $similar = Find-SimilarNodes -TargetNodeId 'station1' -Nodes $allNodes
#>

# Similarity configuration
$Script:SimilarityConfig = @{
    MinSimilarity        = 0.5       # Minimum similarity to report
    MaxResults           = 10        # Max similar items to return
    StructureWeight      = 0.4       # Weight for structural similarity
    AttributeWeight      = 0.3       # Weight for attribute similarity
    NamePatternWeight    = 0.3       # Weight for naming similarity
}

function Get-SubtreeNodes {
    <#
    .SYNOPSIS
        Gets all nodes in a subtree rooted at given node.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootNodeId,
        
        [Parameter(Mandatory = $true)]
        [array]$Nodes
    )
    
    $nodeById = @{}
    $childrenOf = @{}
    
    foreach ($node in $Nodes) {
        $nodeById[$node.nodeId] = $node
        if ($node.parentId) {
            if (-not $childrenOf.ContainsKey($node.parentId)) {
                $childrenOf[$node.parentId] = @()
            }
            $childrenOf[$node.parentId] += $node.nodeId
        }
    }
    
    if (-not $nodeById.ContainsKey($RootNodeId)) {
        return @()
    }
    
    $result = @()
    $queue = @($RootNodeId)
    
    while ($queue.Count -gt 0) {
        $currentId = $queue[0]
        $queue = if ($queue.Count -gt 1) { $queue[1..($queue.Count - 1)] } else { @() }
        
        if ($nodeById.ContainsKey($currentId)) {
            $result += $nodeById[$currentId]
        }
        
        if ($childrenOf.ContainsKey($currentId)) {
            $queue += $childrenOf[$currentId]
        }
    }
    
    return $result
}

function Get-StructuralFingerprint {
    <#
    .SYNOPSIS
        Computes structural fingerprint of a subtree.
    
    .DESCRIPTION
        Encodes tree structure: depth, branching, type distribution
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$SubtreeNodes
    )
    
    if ($SubtreeNodes.Count -eq 0) {
        return [PSCustomObject]@{
            hash = '0000000000000000'
            nodeCount = 0
            maxDepth = 0
            typeDistribution = @{}
            branchingFactor = 0
        }
    }
    
    # Compute type distribution
    $typeDistribution = @{}
    foreach ($node in $SubtreeNodes) {
        $type = $node.nodeType
        if (-not $typeDistribution.ContainsKey($type)) {
            $typeDistribution[$type] = 0
        }
        $typeDistribution[$type]++
    }
    
    # Compute depth (from paths)
    $maxDepth = 0
    foreach ($node in $SubtreeNodes) {
        if ($node.path) {
            $depth = ($node.path -split '/' | Where-Object { $_ }).Count
            if ($depth -gt $maxDepth) { $maxDepth = $depth }
        }
    }
    
    # Build children count for branching factor
    $childrenCount = @{}
    foreach ($node in $SubtreeNodes) {
        $parentId = $node.parentId
        if ($parentId) {
            if (-not $childrenCount.ContainsKey($parentId)) {
                $childrenCount[$parentId] = 0
            }
            $childrenCount[$parentId]++
        }
    }
    $avgBranching = if ($childrenCount.Count -gt 0) {
        ($childrenCount.Values | Measure-Object -Average).Average
    } else { 0 }
    
    # Encode structure as string for hashing
    $sortedTypes = $typeDistribution.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key):$($_.Value)" }
    $structString = "N:$($SubtreeNodes.Count)|D:$maxDepth|B:$([Math]::Round($avgBranching, 2))|T:$($sortedTypes -join ',')"
    
    # Compute hash
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($structString)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    $hash = [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16).ToLower()
    
    [PSCustomObject]@{
        hash             = $hash
        nodeCount        = $SubtreeNodes.Count
        maxDepth         = $maxDepth
        typeDistribution = $typeDistribution
        branchingFactor  = [Math]::Round($avgBranching, 2)
    }
}

function Get-AttributeFingerprint {
    <#
    .SYNOPSIS
        Computes attribute fingerprint of a subtree.
    #>
    param(
        [array]$SubtreeNodes
    )
    
    if (-not $SubtreeNodes -or $SubtreeNodes.Count -eq 0) {
        return [PSCustomObject]@{
            hash = '0000000000000000'
            attributeCount = 0
            commonAttributes = @()
        }
    }
    
    $attributeCounts = @{}
    $totalAttributes = 0
    
    foreach ($node in $SubtreeNodes) {
        if ($node.attributes) {
            foreach ($prop in $node.attributes.PSObject.Properties) {
                $key = $prop.Name
                if (-not $attributeCounts.ContainsKey($key)) {
                    $attributeCounts[$key] = 0
                }
                $attributeCounts[$key]++
                $totalAttributes++
            }
        }
    }
    
    # Common attributes (present in >50% of nodes)
    $threshold = $SubtreeNodes.Count * 0.5
    $commonAttrs = $attributeCounts.GetEnumerator() | 
        Where-Object { $_.Value -ge $threshold } | 
        Sort-Object Value -Descending |
        Select-Object -First 10 -ExpandProperty Key
    
    # Build fingerprint string
    $fingerString = ($attributeCounts.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key):$($_.Value)" }) -join '|'
    
    # Compute hash
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($fingerString)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    $hash = [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16).ToLower()
    
    [PSCustomObject]@{
        hash             = $hash
        attributeCount   = $totalAttributes
        commonAttributes = $commonAttrs
    }
}

function Get-NamePatternFingerprint {
    <#
    .SYNOPSIS
        Computes naming pattern fingerprint.
    #>
    param(
        [array]$SubtreeNodes
    )
    
    if (-not $SubtreeNodes -or $SubtreeNodes.Count -eq 0) {
        return [PSCustomObject]@{
            hash = '0000000000000000'
            patterns = @()
        }
    }
    
    # Extract common prefixes/suffixes by type
    $patternsByType = @{}
    
    foreach ($node in $SubtreeNodes) {
        $type = $node.nodeType
        $name = $node.name
        
        if (-not $patternsByType.ContainsKey($type)) {
            $patternsByType[$type] = @()
        }
        $patternsByType[$type] += $name
    }
    
    $patterns = @()
    foreach ($entry in $patternsByType.GetEnumerator()) {
        $names = $entry.Value
        if ($names.Count -gt 1) {
            # Try to find common prefix
            $prefix = Get-CommonPrefix -Strings $names
            if ($prefix.Length -ge 2) {
                $patterns += "$($entry.Key):prefix=$prefix"
            }
        }
    }
    
    $patternString = ($patterns | Sort-Object) -join '|'
    
    # Compute hash
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($patternString)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    $hash = [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16).ToLower()
    
    [PSCustomObject]@{
        hash     = $hash
        patterns = $patterns
    }
}

function Get-CommonPrefix {
    <#
    .SYNOPSIS
        Finds common prefix among strings.
    #>
    param([array]$Strings)
    
    if (-not $Strings -or $Strings.Count -eq 0) { return '' }
    if ($Strings.Count -eq 1) { return $Strings[0] }
    
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
        
        if (-not $allMatch) { break }
        $prefix += $char
    }
    
    return $prefix -replace '[_\d]+$', ''
}

function Get-SubtreeFingerprint {
    <#
    .SYNOPSIS
        Computes complete fingerprint for a subtree.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootNodeId,
        
        [Parameter(Mandatory = $true)]
        [array]$Nodes
    )
    
    $subtreeNodes = Get-SubtreeNodes -RootNodeId $RootNodeId -Nodes $Nodes
    
    $structural = Get-StructuralFingerprint -SubtreeNodes $subtreeNodes
    $attribute = Get-AttributeFingerprint -SubtreeNodes $subtreeNodes
    $naming = Get-NamePatternFingerprint -SubtreeNodes $subtreeNodes
    
    [PSCustomObject]@{
        rootNodeId  = $RootNodeId
        nodeCount   = $subtreeNodes.Count
        structural  = $structural
        attribute   = $attribute
        naming      = $naming
    }
}

function Compare-Fingerprints {
    <#
    .SYNOPSIS
        Computes similarity between two fingerprints.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Fingerprint1,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Fingerprint2,
        
        [hashtable]$Weights = $Script:SimilarityConfig
    )
    
    $scores = @()
    
    # Structural similarity (hash match = 1.0, type overlap otherwise)
    $structScore = 0
    if ($Fingerprint1.structural.hash -eq $Fingerprint2.structural.hash) {
        $structScore = 1.0
    }
    else {
        # Compute type distribution overlap
        $types1 = $Fingerprint1.structural.typeDistribution
        $types2 = $Fingerprint2.structural.typeDistribution
        $allTypes = @($types1.Keys) + @($types2.Keys) | Select-Object -Unique
        
        $overlap = 0
        $total = 0
        foreach ($type in $allTypes) {
            $v1 = if ($types1.ContainsKey($type)) { $types1[$type] } else { 0 }
            $v2 = if ($types2.ContainsKey($type)) { $types2[$type] } else { 0 }
            $overlap += [Math]::Min($v1, $v2)
            $total += [Math]::Max($v1, $v2)
        }
        $structScore = if ($total -gt 0) { $overlap / $total } else { 0 }
    }
    
    # Attribute similarity
    $attrScore = if ($Fingerprint1.attribute.hash -eq $Fingerprint2.attribute.hash) { 1.0 } else { 0.5 }
    
    # Name pattern similarity
    $nameScore = if ($Fingerprint1.naming.hash -eq $Fingerprint2.naming.hash) { 1.0 } else { 0.3 }
    
    # Weighted average
    $similarity = ($structScore * $Weights.StructureWeight) + 
                  ($attrScore * $Weights.AttributeWeight) + 
                  ($nameScore * $Weights.NamePatternWeight)
    
    [PSCustomObject]@{
        similarity     = [Math]::Round($similarity, 3)
        structuralScore = [Math]::Round($structScore, 3)
        attributeScore = [Math]::Round($attrScore, 3)
        namingScore    = [Math]::Round($nameScore, 3)
        hashMatch      = $Fingerprint1.structural.hash -eq $Fingerprint2.structural.hash
    }
}

function Find-SimilarNodes {
    <#
    .SYNOPSIS
        Finds nodes/subtrees similar to a target.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetNodeId,
        
        [Parameter(Mandatory = $true)]
        [array]$Nodes,
        
        [array]$CandidateTypes = @('Station', 'ResourceGroup'),
        
        [double]$MinSimilarity = 0.5,
        
        [int]$MaxResults = 10
    )
    
    # Get target fingerprint
    $targetFingerprint = Get-SubtreeFingerprint -RootNodeId $TargetNodeId -Nodes $Nodes
    
    if ($targetFingerprint.nodeCount -eq 0) {
        return @()
    }
    
    # Get candidate nodes (same type as target or specified types)
    $targetNode = $Nodes | Where-Object { $_.nodeId -eq $TargetNodeId } | Select-Object -First 1
    $targetType = if ($targetNode) { $targetNode.nodeType } else { 'Station' }
    
    $candidates = $Nodes | Where-Object { 
        $_.nodeType -in $CandidateTypes -and $_.nodeId -ne $TargetNodeId
    }
    
    # Compare with each candidate
    $results = @()
    foreach ($candidate in $candidates) {
        $candidateFingerprint = Get-SubtreeFingerprint -RootNodeId $candidate.nodeId -Nodes $Nodes
        
        if ($candidateFingerprint.nodeCount -eq 0) { continue }
        
        $comparison = Compare-Fingerprints -Fingerprint1 $targetFingerprint -Fingerprint2 $candidateFingerprint
        
        if ($comparison.similarity -ge $MinSimilarity) {
            $results += [PSCustomObject]@{
                nodeId          = $candidate.nodeId
                nodeName        = $candidate.name
                nodeType        = $candidate.nodeType
                path            = $candidate.path
                similarity      = $comparison.similarity
                structuralScore = $comparison.structuralScore
                attributeScore  = $comparison.attributeScore
                namingScore     = $comparison.namingScore
                hashMatch       = $comparison.hashMatch
                nodeCount       = $candidateFingerprint.nodeCount
            }
        }
    }
    
    # Sort by similarity and limit
    $results | Sort-Object similarity -Descending | Select-Object -First $MaxResults
}

function Export-SimilarityJson {
    <#
    .SYNOPSIS
        Exports similarity results to JSON.
    #>
    param(
        [array]$Results,
        [string]$OutputPath,
        [switch]$Pretty
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $report = [PSCustomObject]@{
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        count     = $Results.Count
        results   = $Results
    }
    
    $json = if ($Pretty) {
        $report | ConvertTo-Json -Depth 10
    } else {
        $report | ConvertTo-Json -Depth 10 -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $OutputPath 'similar.json'), $json, $utf8NoBom)
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Get-SubtreeNodes',
        'Get-StructuralFingerprint',
        'Get-AttributeFingerprint',
        'Get-NamePatternFingerprint',
        'Get-SubtreeFingerprint',
        'Compare-Fingerprints',
        'Find-SimilarNodes',
        'Export-SimilarityJson'
    )
}
