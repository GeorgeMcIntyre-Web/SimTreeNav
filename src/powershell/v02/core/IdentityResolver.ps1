# IdentityResolver.ps1
# Stable identity resolution for nodes across snapshots
# Handles DB rekeys, copy/import scenarios with confidence-based matching

<#
.SYNOPSIS
    Provides stable logical identity for nodes across snapshots.

.DESCRIPTION
    Problem: nodeId (OBJECT_ID) can change between snapshots due to:
    - Database rekeys
    - Copy/paste operations
    - Import/export cycles
    - Schema migrations

    Solution: Generate a logicalId based on multiple stable attributes
    and use confidence-based matching to correlate nodes across snapshots.

    Matching signals (in priority order):
    1. externalId (PP-uuid format) - most stable if present
    2. name + nodeType + parentPath - structural identity
    3. contentHash - content-based fingerprint
    4. links (prototypeId) - relationship-based identity
    5. transformHash - location-based identity (for operations)

.EXAMPLE
    $resolver = New-IdentityResolver -Config $config
    $nodesWithIdentity = $resolver.ResolveAll($nodes)
#>

# Match confidence thresholds
$Script:IdentityConfig = @{
    ConfidenceThreshold = 0.85
    Weights = @{
        ExternalId      = 1.0    # Exact match on PP-uuid
        NameAndPath     = 0.7    # Name + parent path match
        ContentHash     = 0.6    # Fingerprint match
        NameOnly        = 0.4    # Just name match (weak)
        PrototypeLink   = 0.5    # Prototype relationship match
        TransformHash   = 0.3    # Transform similarity (for operations)
        NodeTypeMatch   = 0.1    # Same node type (bonus)
    }
}

function Get-LogicalId {
    <#
    .SYNOPSIS
        Computes a stable logical ID for a node.
    
    .DESCRIPTION
        The logicalId is deterministic and based on stable attributes,
        not the database OBJECT_ID which can change.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Node
    )
    
    # Priority 1: Use externalId if present and valid (PP-uuid format)
    $externalId = $Node.attributes.externalId
    if ($externalId -and $externalId -match '^PP-[a-f0-9-]{36}$') {
        return "ext:$externalId"
    }
    
    # Priority 2: Use name + nodeType + parent path for structural identity
    $name = $Node.name
    $nodeType = $Node.nodeType
    $path = $Node.path
    
    # Compute structural identity hash
    $structuralKey = "$nodeType|$path"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($structuralKey)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    $structHash = [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 12).ToLower()
    
    return "struct:$structHash"
}

function Get-IdentitySignature {
    <#
    .SYNOPSIS
        Creates a comprehensive identity signature for matching.
    
    .DESCRIPTION
        Returns a signature object containing all identity signals
        that can be used for cross-snapshot matching.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Node
    )
    
    $externalId = if ($Node.attributes) { $Node.attributes.externalId } else { $null }
    $className = if ($Node.attributes) { $Node.attributes.className } else { $null }
    $contentHash = if ($Node.fingerprints) { $Node.fingerprints.contentHash } else { $null }
    $transformHash = if ($Node.fingerprints) { $Node.fingerprints.transformHash } else { $null }
    $prototypeId = if ($Node.links -and $Node.links.prototypeId) { $Node.links.prototypeId } else { $null }
    
    # Extract parent name from path for matching
    $parentPath = $null
    if ($Node.path) {
        $pathParts = $Node.path -split '/' | Where-Object { $_ }
        if ($pathParts.Count -gt 1) {
            $parentPath = '/' + ($pathParts[0..($pathParts.Count - 2)] -join '/')
        }
    }
    
    [PSCustomObject]@{
        nodeId        = $Node.nodeId
        name          = $Node.name
        nodeType      = $Node.nodeType
        path          = $Node.path
        parentPath    = $parentPath
        externalId    = $externalId
        className     = $className
        contentHash   = $contentHash
        transformHash = $transformHash
        prototypeId   = $prototypeId
    }
}

function Compare-IdentitySignatures {
    <#
    .SYNOPSIS
        Compares two identity signatures and returns match confidence.
    
    .DESCRIPTION
        Returns confidence (0..1) and reason for the match assessment.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Signature1,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Signature2,
        
        [hashtable]$Weights = $Script:IdentityConfig.Weights
    )
    
    $confidence = 0.0
    $reasons = @()
    
    # Exact nodeId match (same node, not rekeyed)
    if ($Signature1.nodeId -eq $Signature2.nodeId) {
        return [PSCustomObject]@{
            confidence = 1.0
            reason     = 'exact_nodeId'
            details    = @('nodeId match')
        }
    }
    
    # ExternalId match (strongest signal)
    if ($Signature1.externalId -and $Signature2.externalId) {
        if ($Signature1.externalId -eq $Signature2.externalId) {
            $confidence += $Weights.ExternalId
            $reasons += 'externalId'
        }
    }
    
    # Name + parent path match
    if ($Signature1.name -eq $Signature2.name) {
        if ($Signature1.parentPath -and $Signature2.parentPath -and 
            $Signature1.parentPath -eq $Signature2.parentPath) {
            $confidence += $Weights.NameAndPath
            $reasons += 'name+parentPath'
        }
        else {
            $confidence += $Weights.NameOnly
            $reasons += 'nameOnly'
        }
    }
    
    # Content hash match
    if ($Signature1.contentHash -and $Signature2.contentHash -and
        $Signature1.contentHash -eq $Signature2.contentHash) {
        $confidence += $Weights.ContentHash
        $reasons += 'contentHash'
    }
    
    # Node type match (bonus)
    if ($Signature1.nodeType -eq $Signature2.nodeType) {
        $confidence += $Weights.NodeTypeMatch
        $reasons += 'nodeType'
    }
    
    # Prototype link match
    if ($Signature1.prototypeId -and $Signature2.prototypeId -and
        $Signature1.prototypeId -eq $Signature2.prototypeId) {
        $confidence += $Weights.PrototypeLink
        $reasons += 'prototypeLink'
    }
    
    # Transform hash match (for operations/locations)
    if ($Signature1.transformHash -and $Signature2.transformHash -and
        $Signature1.transformHash -eq $Signature2.transformHash) {
        $confidence += $Weights.TransformHash
        $reasons += 'transformHash'
    }
    
    # Normalize confidence to 0..1 range
    $maxPossible = ($Weights.Values | Measure-Object -Sum).Sum
    $normalizedConfidence = [Math]::Min(1.0, $confidence / $maxPossible * 2)
    
    return [PSCustomObject]@{
        confidence = [Math]::Round($normalizedConfidence, 3)
        reason     = ($reasons -join '+')
        details    = $reasons
    }
}

function Resolve-NodeIdentities {
    <#
    .SYNOPSIS
        Assigns logical IDs to all nodes in a snapshot.
    
    .DESCRIPTION
        Processes all nodes and assigns stable logicalId values
        that persist across snapshots even if nodeId changes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Nodes
    )
    
    foreach ($node in $Nodes) {
        $logicalId = Get-LogicalId -Node $node
        
        # Add identity properties to node
        if (-not $node.PSObject.Properties['identity']) {
            $node | Add-Member -NotePropertyName 'identity' -NotePropertyValue ([PSCustomObject]@{
                logicalId = $logicalId
                signature = Get-IdentitySignature -Node $node
            }) -Force
        }
        else {
            $node.identity.logicalId = $logicalId
            $node.identity.signature = Get-IdentitySignature -Node $node
        }
    }
    
    return $Nodes
}

function Find-MatchingNode {
    <#
    .SYNOPSIS
        Finds the best matching node in a target set for a source node.
    
    .DESCRIPTION
        Uses multi-signal matching to find corresponding nodes
        even when nodeId has changed (rekeyed scenario).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SourceNode,
        
        [Parameter(Mandatory = $true)]
        [array]$TargetNodes,
        
        [double]$ConfidenceThreshold = $Script:IdentityConfig.ConfidenceThreshold,
        
        [switch]$IncludeCandidates
    )
    
    $sourceSignature = if ($SourceNode.identity -and $SourceNode.identity.signature) {
        $SourceNode.identity.signature
    } else {
        Get-IdentitySignature -Node $SourceNode
    }
    
    $candidates = @()
    $bestMatch = $null
    $bestConfidence = 0.0
    
    foreach ($target in $TargetNodes) {
        $targetSignature = if ($target.identity -and $target.identity.signature) {
            $target.identity.signature
        } else {
            Get-IdentitySignature -Node $target
        }
        
        $comparison = Compare-IdentitySignatures -Signature1 $sourceSignature -Signature2 $targetSignature
        
        if ($comparison.confidence -gt 0) {
            $candidates += [PSCustomObject]@{
                node       = $target
                confidence = $comparison.confidence
                reason     = $comparison.reason
            }
        }
        
        if ($comparison.confidence -gt $bestConfidence) {
            $bestConfidence = $comparison.confidence
            $bestMatch = [PSCustomObject]@{
                node       = $target
                confidence = $comparison.confidence
                reason     = $comparison.reason
            }
        }
    }
    
    # Sort candidates by confidence
    $sortedCandidates = $candidates | Sort-Object confidence -Descending | Select-Object -First 5
    
    $result = [PSCustomObject]@{
        matched          = ($bestConfidence -ge $ConfidenceThreshold)
        matchedNode      = if ($bestConfidence -ge $ConfidenceThreshold) { $bestMatch.node } else { $null }
        matchConfidence  = $bestConfidence
        matchReason      = if ($bestMatch) { $bestMatch.reason } else { 'no_match' }
        isRekeyed        = ($bestConfidence -ge $ConfidenceThreshold -and 
                           $bestMatch -and 
                           $bestMatch.node.nodeId -ne $SourceNode.nodeId)
    }
    
    if ($IncludeCandidates) {
        $result | Add-Member -NotePropertyName 'candidates' -NotePropertyValue $sortedCandidates
    }
    
    return $result
}

function Build-IdentityMap {
    <#
    .SYNOPSIS
        Builds a mapping between nodes in two snapshots using identity resolution.
    
    .DESCRIPTION
        Creates a comprehensive map that links nodes across snapshots,
        identifying exact matches, rekeyed nodes, and orphans.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$BaselineNodes,
        
        [Parameter(Mandatory = $true)]
        [array]$CurrentNodes,
        
        [double]$ConfidenceThreshold = $Script:IdentityConfig.ConfidenceThreshold
    )
    
    # Resolve identities for both snapshots
    $baselineWithIdentity = Resolve-NodeIdentities -Nodes $BaselineNodes
    $currentWithIdentity = Resolve-NodeIdentities -Nodes $CurrentNodes
    
    # Build lookup maps
    $baselineByNodeId = @{}
    $baselineByLogicalId = @{}
    foreach ($node in $baselineWithIdentity) {
        $baselineByNodeId[$node.nodeId] = $node
        if ($node.identity -and $node.identity.logicalId) {
            $baselineByLogicalId[$node.identity.logicalId] = $node
        }
    }
    
    $currentByNodeId = @{}
    $currentByLogicalId = @{}
    foreach ($node in $currentWithIdentity) {
        $currentByNodeId[$node.nodeId] = $node
        if ($node.identity -and $node.identity.logicalId) {
            $currentByLogicalId[$node.identity.logicalId] = $node
        }
    }
    
    $mappings = @()
    $matchedCurrentIds = @{}
    
    # First pass: Match by nodeId (exact)
    foreach ($baseline in $baselineWithIdentity) {
        if ($currentByNodeId.ContainsKey($baseline.nodeId)) {
            $current = $currentByNodeId[$baseline.nodeId]
            $mappings += [PSCustomObject]@{
                baselineNodeId  = $baseline.nodeId
                currentNodeId   = $current.nodeId
                logicalId       = $baseline.identity.logicalId
                matchType       = 'exact'
                matchConfidence = 1.0
                matchReason     = 'exact_nodeId'
                baselineNode    = $baseline
                currentNode     = $current
            }
            $matchedCurrentIds[$current.nodeId] = $true
        }
    }
    
    # Second pass: Match by logicalId (rekeyed)
    foreach ($baseline in $baselineWithIdentity) {
        # Skip if already matched
        $alreadyMatched = $mappings | Where-Object { $_.baselineNodeId -eq $baseline.nodeId }
        if ($alreadyMatched) { continue }
        
        # Try logicalId match
        $logicalId = $baseline.identity.logicalId
        if ($logicalId -and $currentByLogicalId.ContainsKey($logicalId)) {
            $current = $currentByLogicalId[$logicalId]
            if (-not $matchedCurrentIds.ContainsKey($current.nodeId)) {
                $mappings += [PSCustomObject]@{
                    baselineNodeId  = $baseline.nodeId
                    currentNodeId   = $current.nodeId
                    logicalId       = $logicalId
                    matchType       = 'rekeyed_logicalId'
                    matchConfidence = 0.95
                    matchReason     = 'logicalId_match'
                    baselineNode    = $baseline
                    currentNode     = $current
                }
                $matchedCurrentIds[$current.nodeId] = $true
            }
        }
    }
    
    # Third pass: Fuzzy match for remaining unmatched baseline nodes
    $unmatchedBaseline = $baselineWithIdentity | Where-Object { 
        $nodeId = $_.nodeId
        -not ($mappings | Where-Object { $_.baselineNodeId -eq $nodeId })
    }
    
    $unmatchedCurrent = $currentWithIdentity | Where-Object {
        -not $matchedCurrentIds.ContainsKey($_.nodeId)
    }
    
    foreach ($baseline in $unmatchedBaseline) {
        $match = Find-MatchingNode -SourceNode $baseline -TargetNodes $unmatchedCurrent -ConfidenceThreshold $ConfidenceThreshold
        
        if ($match.matched -and $match.matchedNode) {
            $mappings += [PSCustomObject]@{
                baselineNodeId  = $baseline.nodeId
                currentNodeId   = $match.matchedNode.nodeId
                logicalId       = $baseline.identity.logicalId
                matchType       = if ($match.isRekeyed) { 'rekeyed_fuzzy' } else { 'fuzzy' }
                matchConfidence = $match.matchConfidence
                matchReason     = $match.matchReason
                baselineNode    = $baseline
                currentNode     = $match.matchedNode
            }
            $matchedCurrentIds[$match.matchedNode.nodeId] = $true
        }
    }
    
    # Identify orphans (unmatched nodes)
    $removedNodes = $baselineWithIdentity | Where-Object {
        $nodeId = $_.nodeId
        -not ($mappings | Where-Object { $_.baselineNodeId -eq $nodeId })
    }
    
    $addedNodes = $currentWithIdentity | Where-Object {
        -not $matchedCurrentIds.ContainsKey($_.nodeId)
    }
    
    return [PSCustomObject]@{
        mappings      = $mappings
        removedNodes  = $removedNodes
        addedNodes    = $addedNodes
        stats         = [PSCustomObject]@{
            totalBaseline     = $baselineWithIdentity.Count
            totalCurrent      = $currentWithIdentity.Count
            exactMatches      = ($mappings | Where-Object { $_.matchType -eq 'exact' }).Count
            rekeyedMatches    = ($mappings | Where-Object { $_.matchType -like 'rekeyed*' }).Count
            fuzzyMatches      = ($mappings | Where-Object { $_.matchType -eq 'fuzzy' }).Count
            removedCount      = $removedNodes.Count
            addedCount        = $addedNodes.Count
        }
    }
}

function Get-IdentityResolverConfig {
    <#
    .SYNOPSIS
        Gets the current identity resolver configuration.
    #>
    return $Script:IdentityConfig
}

function Set-IdentityResolverConfig {
    <#
    .SYNOPSIS
        Updates the identity resolver configuration.
    #>
    param(
        [double]$ConfidenceThreshold,
        [hashtable]$Weights
    )
    
    if ($PSBoundParameters.ContainsKey('ConfidenceThreshold')) {
        $Script:IdentityConfig.ConfidenceThreshold = $ConfidenceThreshold
    }
    
    if ($Weights) {
        foreach ($key in $Weights.Keys) {
            if ($Script:IdentityConfig.Weights.ContainsKey($key)) {
                $Script:IdentityConfig.Weights[$key] = $Weights[$key]
            }
        }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-LogicalId',
    'Get-IdentitySignature',
    'Compare-IdentitySignatures',
    'Resolve-NodeIdentities',
    'Find-MatchingNode',
    'Build-IdentityMap',
    'Get-IdentityResolverConfig',
    'Set-IdentityResolverConfig'
)
