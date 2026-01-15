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
    DebugEnabled = $false
}

# Identity debug log for explainability
$Script:IdentityDebugLog = @()

function Validate-IdentityConfig {
    <#
    .SYNOPSIS
        Validates and normalizes identity resolver configuration.
    
    .DESCRIPTION
        - Ensures threshold is in valid range (0..1)
        - Warns and normalizes if weights sum > 1.0
        - Returns validation result
    #>
    param(
        [double]$Threshold = $Script:IdentityConfig.ConfidenceThreshold,
        [hashtable]$Weights = $null
    )
    
    # Clone weights to avoid modifying during enumeration
    if (-not $Weights) {
        $Weights = @{}
        foreach ($key in $Script:IdentityConfig.Weights.Keys) {
            $Weights[$key] = $Script:IdentityConfig.Weights[$key]
        }
    }
    else {
        $clonedWeights = @{}
        foreach ($key in $Weights.Keys) {
            $clonedWeights[$key] = $Weights[$key]
        }
        $Weights = $clonedWeights
    }
    
    $warnings = @()
    
    # Validate threshold
    if ($Threshold -lt 0 -or $Threshold -gt 1) {
        $warnings += "ConfidenceThreshold ($Threshold) must be between 0 and 1. Clamping to valid range."
        $Threshold = [Math]::Max(0, [Math]::Min(1, $Threshold))
    }
    
    # Validate individual weights
    $keysToFix = @()
    foreach ($key in $Weights.Keys) {
        if ($Weights[$key] -lt 0) {
            $warnings += "Weight '$key' ($($Weights[$key])) is negative. Setting to 0."
            $keysToFix += @{ key = $key; value = 0 }
        }
        elseif ($Weights[$key] -gt 1) {
            $warnings += "Weight '$key' ($($Weights[$key])) exceeds 1.0. Clamping to 1.0."
            $keysToFix += @{ key = $key; value = 1.0 }
        }
    }
    
    # Apply fixes
    foreach ($fix in $keysToFix) {
        $Weights[$fix.key] = $fix.value
    }
    
    # Check sum of weights
    $weightSum = ($Weights.Values | Measure-Object -Sum).Sum
    if ($weightSum -gt 1.0) {
        $warnings += "Sum of weights ($([Math]::Round($weightSum, 3))) exceeds 1.0. Normalizing weights."
        $normalizeFactor = 1.0 / $weightSum
        $normalizedWeights = @{}
        foreach ($key in $Weights.Keys) {
            $normalizedWeights[$key] = [Math]::Round($Weights[$key] * $normalizeFactor, 4)
        }
        $Weights = $normalizedWeights
    }
    
    return [PSCustomObject]@{
        isValid              = $warnings.Count -eq 0
        warnings             = $warnings
        normalizedThreshold  = $Threshold
        normalizedWeights    = $Weights
        weightSum            = [Math]::Round(($Weights.Values | Measure-Object -Sum).Sum, 4)
    }
}

function Enable-IdentityDebug {
    <#
    .SYNOPSIS
        Enables identity debug logging.
    #>
    $Script:IdentityConfig.DebugEnabled = $true
    $Script:IdentityDebugLog = @()
}

function Disable-IdentityDebug {
    <#
    .SYNOPSIS
        Disables identity debug logging.
    #>
    $Script:IdentityConfig.DebugEnabled = $false
}

function Get-IdentityDebugLog {
    <#
    .SYNOPSIS
        Gets the accumulated identity debug log.
    #>
    return $Script:IdentityDebugLog
}

function Clear-IdentityDebugLog {
    <#
    .SYNOPSIS
        Clears the identity debug log.
    #>
    $Script:IdentityDebugLog = @()
}

function Export-IdentityDebug {
    <#
    .SYNOPSIS
        Exports identity debug log to JSON file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    $parentDir = Split-Path $OutputPath -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    $debugData = [PSCustomObject]@{
        timestamp    = (Get-Date).ToUniversalTime().ToString('o')
        config       = $Script:IdentityConfig
        matchCount   = $Script:IdentityDebugLog.Count
        matches      = $Script:IdentityDebugLog
    }
    
    $json = $debugData | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutputPath, $json, $utf8NoBom)
    
    return $OutputPath
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
        Returns confidence (0..1), reason for the match, and detailed
        signal scores for each identity component.
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
    $signalScores = @{}  # Detailed breakdown
    
    # Initialize all signal scores to 0
    foreach ($key in $Weights.Keys) {
        $signalScores[$key] = [PSCustomObject]@{
            weight    = $Weights[$key]
            matched   = $false
            score     = 0.0
            value1    = $null
            value2    = $null
        }
    }
    
    # Exact nodeId match (same node, not rekeyed)
    if ($Signature1.nodeId -eq $Signature2.nodeId) {
        $result = [PSCustomObject]@{
            confidence    = 1.0
            reason        = 'exact_nodeId'
            details       = @('nodeId match')
            signalScores  = @{
                ExactNodeId = [PSCustomObject]@{
                    weight = 1.0; matched = $true; score = 1.0
                    value1 = $Signature1.nodeId; value2 = $Signature2.nodeId
                }
            }
        }
        
        # Log if debug enabled
        if ($Script:IdentityConfig.DebugEnabled) {
            $Script:IdentityDebugLog += [PSCustomObject]@{
                type          = 'exact_match'
                nodeId1       = $Signature1.nodeId
                nodeId2       = $Signature2.nodeId
                confidence    = 1.0
                reason        = 'exact_nodeId'
                signalScores  = $result.signalScores
            }
        }
        
        return $result
    }
    
    # ExternalId match (strongest signal)
    $signalScores.ExternalId.value1 = $Signature1.externalId
    $signalScores.ExternalId.value2 = $Signature2.externalId
    if ($Signature1.externalId -and $Signature2.externalId) {
        if ($Signature1.externalId -eq $Signature2.externalId) {
            $confidence += $Weights.ExternalId
            $reasons += 'externalId'
            $signalScores.ExternalId.matched = $true
            $signalScores.ExternalId.score = $Weights.ExternalId
        }
    }
    
    # Name + parent path match
    $signalScores.NameAndPath.value1 = "$($Signature1.name)@$($Signature1.parentPath)"
    $signalScores.NameAndPath.value2 = "$($Signature2.name)@$($Signature2.parentPath)"
    $signalScores.NameOnly.value1 = $Signature1.name
    $signalScores.NameOnly.value2 = $Signature2.name
    
    if ($Signature1.name -eq $Signature2.name) {
        if ($Signature1.parentPath -and $Signature2.parentPath -and 
            $Signature1.parentPath -eq $Signature2.parentPath) {
            $confidence += $Weights.NameAndPath
            $reasons += 'name+parentPath'
            $signalScores.NameAndPath.matched = $true
            $signalScores.NameAndPath.score = $Weights.NameAndPath
        }
        else {
            $confidence += $Weights.NameOnly
            $reasons += 'nameOnly'
            $signalScores.NameOnly.matched = $true
            $signalScores.NameOnly.score = $Weights.NameOnly
        }
    }
    
    # Content hash match
    $signalScores.ContentHash.value1 = $Signature1.contentHash
    $signalScores.ContentHash.value2 = $Signature2.contentHash
    if ($Signature1.contentHash -and $Signature2.contentHash -and
        $Signature1.contentHash -eq $Signature2.contentHash) {
        $confidence += $Weights.ContentHash
        $reasons += 'contentHash'
        $signalScores.ContentHash.matched = $true
        $signalScores.ContentHash.score = $Weights.ContentHash
    }
    
    # Node type match (bonus)
    $signalScores.NodeTypeMatch.value1 = $Signature1.nodeType
    $signalScores.NodeTypeMatch.value2 = $Signature2.nodeType
    if ($Signature1.nodeType -eq $Signature2.nodeType) {
        $confidence += $Weights.NodeTypeMatch
        $reasons += 'nodeType'
        $signalScores.NodeTypeMatch.matched = $true
        $signalScores.NodeTypeMatch.score = $Weights.NodeTypeMatch
    }
    
    # Prototype link match
    $signalScores.PrototypeLink.value1 = $Signature1.prototypeId
    $signalScores.PrototypeLink.value2 = $Signature2.prototypeId
    if ($Signature1.prototypeId -and $Signature2.prototypeId -and
        $Signature1.prototypeId -eq $Signature2.prototypeId) {
        $confidence += $Weights.PrototypeLink
        $reasons += 'prototypeLink'
        $signalScores.PrototypeLink.matched = $true
        $signalScores.PrototypeLink.score = $Weights.PrototypeLink
    }
    
    # Transform hash match (for operations/locations)
    $signalScores.TransformHash.value1 = $Signature1.transformHash
    $signalScores.TransformHash.value2 = $Signature2.transformHash
    if ($Signature1.transformHash -and $Signature2.transformHash -and
        $Signature1.transformHash -eq $Signature2.transformHash) {
        $confidence += $Weights.TransformHash
        $reasons += 'transformHash'
        $signalScores.TransformHash.matched = $true
        $signalScores.TransformHash.score = $Weights.TransformHash
    }
    
    # Normalize confidence to 0..1 range
    $maxPossible = ($Weights.Values | Measure-Object -Sum).Sum
    $normalizedConfidence = [Math]::Min(1.0, $confidence / $maxPossible * 2)
    
    $result = [PSCustomObject]@{
        confidence    = [Math]::Round($normalizedConfidence, 3)
        reason        = ($reasons -join '+')
        details       = $reasons
        signalScores  = $signalScores
        rawScore      = [Math]::Round($confidence, 4)
        maxPossible   = [Math]::Round($maxPossible, 4)
    }
    
    # Log if debug enabled
    if ($Script:IdentityConfig.DebugEnabled) {
        $Script:IdentityDebugLog += [PSCustomObject]@{
            type          = 'fuzzy_comparison'
            nodeId1       = $Signature1.nodeId
            nodeId2       = $Signature2.nodeId
            name1         = $Signature1.name
            name2         = $Signature2.name
            confidence    = $result.confidence
            reason        = $result.reason
            rawScore      = $result.rawScore
            maxPossible   = $result.maxPossible
            signalScores  = $signalScores
        }
    }
    
    return $result
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
        
        [Parameter(Mandatory = $false)]
        [array]$TargetNodes = @(),
        
        [double]$ConfidenceThreshold = $Script:IdentityConfig.ConfidenceThreshold,
        
        [switch]$IncludeCandidates
    )
    
    # Handle empty target nodes
    if (-not $TargetNodes -or $TargetNodes.Count -eq 0) {
        return [PSCustomObject]@{
            matched         = $false
            matchedNode     = $null
            matchConfidence = 0.0
            matchReason     = 'no_targets'
            isRekeyed       = $false
            candidates      = @()
        }
    }
    
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

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Get-LogicalId',
        'Get-IdentitySignature',
        'Compare-IdentitySignatures',
        'Resolve-NodeIdentities',
        'Find-MatchingNode',
        'Build-IdentityMap',
        'Get-IdentityResolverConfig',
        'Set-IdentityResolverConfig',
        'Validate-IdentityConfig',
        'Enable-IdentityDebug',
        'Disable-IdentityDebug',
        'Get-IdentityDebugLog',
        'Clear-IdentityDebugLog',
        'Export-IdentityDebug'
    )
}
