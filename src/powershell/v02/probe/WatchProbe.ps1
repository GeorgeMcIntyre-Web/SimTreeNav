# WatchProbe.ps1
# Two-stage non-intrusive change detection probe
# v0.3.1: Lightweight probing for watch mode

<#
.SYNOPSIS
    Implements two-stage probing for efficient change detection.

.DESCRIPTION
    Stage A (Ultra-light):
    - Counts per node type/table
    - MAX(updatedAt) if available
    - Minimal key hash of first N records
    - Fast execution, minimal DB load

    Stage B (Scoped):
    - Only runs if Stage A indicates changes
    - Targets specific subtrees or node types
    - More detailed data for actual snapshot

    Persists probe.json with:
    - durationMs, rowsScanned, queriesRun, estimatedCost

.EXAMPLE
    $probe = Invoke-StageAProbe -Nodes $currentNodes -PreviousProbe $lastProbe
    if ($probe.hasChanges) {
        $scoped = Invoke-StageBProbe -Nodes $currentNodes -ChangeHints $probe.changeHints
    }
#>

# Probe configuration
$Script:ProbeConfig = @{
    SampleSize        = 100       # Number of nodes to sample for hash
    HashAlgorithm     = 'SHA256'
    TimestampField    = 'updatedAt'
    CountThreshold    = 0         # Count change threshold (0 = any change)
    HashMismatchTrigger = $true   # Trigger stage B on hash mismatch
}

function Get-ProbeHash {
    <#
    .SYNOPSIS
        Computes a fast hash of sampled node keys for change detection.
    #>
    param(
        [array]$Nodes,
        [int]$SampleSize = $Script:ProbeConfig.SampleSize
    )
    
    if (-not $Nodes -or $Nodes.Count -eq 0) {
        return '0000000000000000'
    }
    
    # Sort by nodeId for determinism and take sample
    $sorted = $Nodes | Sort-Object nodeId | Select-Object -First $SampleSize
    
    # Build key string from nodeId + contentHash (if available)
    $keyParts = $sorted | ForEach-Object {
        $contentHash = if ($_.fingerprints -and $_.fingerprints.contentHash) { 
            $_.fingerprints.contentHash 
        } else { 
            'null' 
        }
        "$($_.nodeId)|$contentHash"
    }
    
    $keyString = $keyParts -join ';'
    
    # Compute hash
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($keyString)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    return [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16).ToLower()
}

function Get-NodeTypeDistribution {
    <#
    .SYNOPSIS
        Gets count distribution by node type.
    #>
    param([array]$Nodes)
    
    $distribution = @{}
    if (-not $Nodes) { return $distribution }
    
    foreach ($node in $Nodes) {
        $type = $node.nodeType
        if (-not $distribution.ContainsKey($type)) {
            $distribution[$type] = 0
        }
        $distribution[$type]++
    }
    
    return $distribution
}

function Get-LatestTimestamp {
    <#
    .SYNOPSIS
        Gets the latest timestamp from nodes (if available).
    #>
    param(
        [array]$Nodes,
        [string]$TimestampField = 'updatedAt'
    )
    
    if (-not $Nodes) { return $null }
    
    $latest = $null
    foreach ($node in $Nodes) {
        $ts = $null
        
        # Check multiple locations
        if ($node.$TimestampField) {
            $ts = $node.$TimestampField
        }
        elseif ($node.attributes -and $node.attributes.$TimestampField) {
            $ts = $node.attributes.$TimestampField
        }
        elseif ($node.timestamps -and $node.timestamps.$TimestampField) {
            $ts = $node.timestamps.$TimestampField
        }
        
        if ($ts) {
            if (-not $latest -or $ts -gt $latest) {
                $latest = $ts
            }
        }
    }
    
    return $latest
}

function Invoke-StageAProbe {
    <#
    .SYNOPSIS
        Stage A: Ultra-light probe for quick change detection.
    
    .DESCRIPTION
        Computes lightweight metrics:
        - Total node count
        - Count by node type
        - Sample hash of first N nodes
        - Latest timestamp (if available)
        
        Compares against previous probe to detect changes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Nodes,
        
        [PSCustomObject]$PreviousProbe = $null,
        
        [int]$SampleSize = $Script:ProbeConfig.SampleSize
    )
    
    $startTime = [DateTime]::UtcNow
    
    # Compute current metrics
    $totalCount = $Nodes.Count
    $typeDistribution = Get-NodeTypeDistribution -Nodes $Nodes
    $sampleHash = Get-ProbeHash -Nodes $Nodes -SampleSize $SampleSize
    $latestTimestamp = Get-LatestTimestamp -Nodes $Nodes
    
    $endTime = [DateTime]::UtcNow
    $durationMs = ($endTime - $startTime).TotalMilliseconds
    
    # Detect changes
    $hasChanges = $false
    $changeHints = @()
    
    if ($PreviousProbe) {
        # Count change
        if ($totalCount -ne $PreviousProbe.totalCount) {
            $hasChanges = $true
            $delta = $totalCount - $PreviousProbe.totalCount
            $changeHints += [PSCustomObject]@{
                type   = 'count_change'
                detail = "Node count changed: $($PreviousProbe.totalCount) -> $totalCount (delta: $delta)"
                delta  = $delta
            }
        }
        
        # Hash change
        if ($sampleHash -ne $PreviousProbe.sampleHash) {
            $hasChanges = $true
            $changeHints += [PSCustomObject]@{
                type   = 'hash_change'
                detail = "Sample hash changed: $($PreviousProbe.sampleHash) -> $sampleHash"
            }
        }
        
        # Timestamp change
        if ($latestTimestamp -and $PreviousProbe.latestTimestamp -and 
            $latestTimestamp -ne $PreviousProbe.latestTimestamp) {
            $hasChanges = $true
            $changeHints += [PSCustomObject]@{
                type   = 'timestamp_change'
                detail = "Latest timestamp changed: $($PreviousProbe.latestTimestamp) -> $latestTimestamp"
            }
        }
        
        # Type distribution change
        $prevDist = $PreviousProbe.typeDistribution
        foreach ($type in $typeDistribution.Keys) {
            $prevCount = if ($prevDist -and $prevDist.ContainsKey($type)) { $prevDist[$type] } else { 0 }
            $currCount = $typeDistribution[$type]
            if ($prevCount -ne $currCount) {
                $hasChanges = $true
                $changeHints += [PSCustomObject]@{
                    type   = 'type_count_change'
                    detail = "Node type '$type' count changed: $prevCount -> $currCount"
                    nodeType = $type
                    delta  = $currCount - $prevCount
                }
            }
        }
        
        # Check for removed types
        if ($prevDist) {
            foreach ($type in $prevDist.Keys) {
                if (-not $typeDistribution.ContainsKey($type)) {
                    $hasChanges = $true
                    $changeHints += [PSCustomObject]@{
                        type   = 'type_removed'
                        detail = "Node type '$type' no longer present (was $($prevDist[$type]) nodes)"
                        nodeType = $type
                    }
                }
            }
        }
    }
    else {
        # No previous probe = always consider changed (first run)
        $hasChanges = $true
        $changeHints += [PSCustomObject]@{
            type   = 'initial_probe'
            detail = 'First probe run, no baseline to compare'
        }
    }
    
    return [PSCustomObject]@{
        stage            = 'A'
        timestamp        = $startTime.ToString('o')
        durationMs       = [Math]::Round($durationMs, 2)
        rowsScanned      = $totalCount
        queriesRun       = 1
        estimatedCost    = 'low'
        
        totalCount       = $totalCount
        typeDistribution = $typeDistribution
        sampleHash       = $sampleHash
        sampleSize       = [Math]::Min($SampleSize, $totalCount)
        latestTimestamp  = $latestTimestamp
        
        hasChanges       = $hasChanges
        changeHints      = $changeHints
    }
}

function Invoke-StageBProbe {
    <#
    .SYNOPSIS
        Stage B: Scoped deeper probe based on Stage A hints.
    
    .DESCRIPTION
        Only runs when Stage A indicates changes.
        Focuses on specific areas based on change hints:
        - Changed node types
        - Subtrees with changes
        - Recently modified nodes
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Nodes,
        
        [array]$ChangeHints = @(),
        
        [array]$NodeTypeFilter = @(),
        
        [string]$PathPrefixFilter = $null,
        
        [int]$MaxNodes = 1000
    )
    
    $startTime = [DateTime]::UtcNow
    
    # Filter nodes based on hints
    $filteredNodes = $Nodes
    
    # Apply node type filter
    if ($NodeTypeFilter -and $NodeTypeFilter.Count -gt 0) {
        $filteredNodes = $filteredNodes | Where-Object { $_.nodeType -in $NodeTypeFilter }
    }
    
    # Apply path prefix filter
    if ($PathPrefixFilter) {
        $filteredNodes = $filteredNodes | Where-Object { $_.path -like "$PathPrefixFilter*" }
    }
    
    # Limit for performance
    $filteredNodes = $filteredNodes | Select-Object -First $MaxNodes
    
    # Compute detailed hashes for filtered set
    $detailedHashes = @{}
    foreach ($node in $filteredNodes) {
        $hash = if ($node.fingerprints) {
            @{
                content   = $node.fingerprints.contentHash
                attribute = $node.fingerprints.attributeHash
                transform = $node.fingerprints.transformHash
            }
        }
        else {
            @{ content = $null; attribute = $null; transform = $null }
        }
        $detailedHashes[$node.nodeId] = $hash
    }
    
    # Group by subtree
    $subtreeStats = @{}
    foreach ($node in $filteredNodes) {
        $subtree = '/'
        if ($node.path) {
            $parts = $node.path -split '/' | Where-Object { $_ }
            if ($parts.Count -ge 2) {
                $subtree = "/$($parts[0])/$($parts[1])"
            }
            elseif ($parts.Count -eq 1) {
                $subtree = "/$($parts[0])"
            }
        }
        
        if (-not $subtreeStats.ContainsKey($subtree)) {
            $subtreeStats[$subtree] = 0
        }
        $subtreeStats[$subtree]++
    }
    
    $endTime = [DateTime]::UtcNow
    $durationMs = ($endTime - $startTime).TotalMilliseconds
    
    return [PSCustomObject]@{
        stage          = 'B'
        timestamp      = $startTime.ToString('o')
        durationMs     = [Math]::Round($durationMs, 2)
        rowsScanned    = $filteredNodes.Count
        queriesRun     = 1
        estimatedCost  = 'medium'
        
        nodesAnalyzed  = $filteredNodes.Count
        subtreeStats   = $subtreeStats
        detailedHashes = $detailedHashes
        filters        = [PSCustomObject]@{
            nodeTypes  = $NodeTypeFilter
            pathPrefix = $PathPrefixFilter
            maxNodes   = $MaxNodes
        }
    }
}

function Invoke-TwoStageProbe {
    <#
    .SYNOPSIS
        Runs complete two-stage probe workflow.
    
    .DESCRIPTION
        1. Runs Stage A (ultra-light)
        2. If changes detected, runs Stage B (scoped)
        3. Returns combined probe results with metrics
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Nodes,
        
        [PSCustomObject]$PreviousProbe = $null,
        
        [switch]$ForceStageB
    )
    
    $overallStart = [DateTime]::UtcNow
    
    # Stage A
    $stageA = Invoke-StageAProbe -Nodes $Nodes -PreviousProbe $PreviousProbe
    
    # Stage B (only if needed)
    $stageB = $null
    if ($stageA.hasChanges -or $ForceStageB) {
        # Extract node type hints from Stage A
        $changedTypes = @()
        foreach ($hint in $stageA.changeHints) {
            if ($hint.nodeType) {
                $changedTypes += $hint.nodeType
            }
        }
        
        $stageB = Invoke-StageBProbe -Nodes $Nodes -ChangeHints $stageA.changeHints -NodeTypeFilter $changedTypes
    }
    
    $overallEnd = [DateTime]::UtcNow
    $totalDurationMs = ($overallEnd - $overallStart).TotalMilliseconds
    
    return [PSCustomObject]@{
        timestamp        = $overallStart.ToString('o')
        totalDurationMs  = [Math]::Round($totalDurationMs, 2)
        hasChanges       = $stageA.hasChanges
        
        stageA           = $stageA
        stageB           = $stageB
        
        metrics          = [PSCustomObject]@{
            durationMs     = [Math]::Round($totalDurationMs, 2)
            rowsScanned    = $stageA.rowsScanned + $(if ($stageB) { $stageB.rowsScanned } else { 0 })
            queriesRun     = 1 + $(if ($stageB) { 1 } else { 0 })
            estimatedCost  = if ($stageB) { 'medium' } else { 'low' }
            stagesRun      = @('A') + $(if ($stageB) { @('B') } else { @() })
        }
    }
}

function Export-ProbeJson {
    <#
    .SYNOPSIS
        Exports probe results to JSON file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ProbeResult,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    $parentDir = Split-Path $OutputPath -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }
    
    $json = $ProbeResult | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutputPath, $json, $utf8NoBom)
    
    return $OutputPath
}

function Read-ProbeJson {
    <#
    .SYNOPSIS
        Reads probe results from JSON file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        return $null
    }
    
    Get-Content $Path -Raw | ConvertFrom-Json
}

function New-ProbeMetadata {
    <#
    .SYNOPSIS
        Creates probe metadata for inclusion in meta.json.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$ProbeResult
    )
    
    [PSCustomObject]@{
        probeDurationMs   = $ProbeResult.totalDurationMs
        rowsScanned       = $ProbeResult.metrics.rowsScanned
        queriesRun        = $ProbeResult.metrics.queriesRun
        estimatedCost     = $ProbeResult.metrics.estimatedCost
        hasChanges        = $ProbeResult.hasChanges
        stagesRun         = $ProbeResult.metrics.stagesRun
        probeTimestamp    = $ProbeResult.timestamp
    }
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Invoke-StageAProbe',
        'Invoke-StageBProbe',
        'Invoke-TwoStageProbe',
        'Get-ProbeHash',
        'Get-NodeTypeDistribution',
        'Get-LatestTimestamp',
        'Export-ProbeJson',
        'Read-ProbeJson',
        'New-ProbeMetadata'
    )
}
