# Anonymizer.ps1
# Dataset anonymization with stable deterministic pseudonyms
# v0.4: Commercial-grade anonymization for safe demos

<#
.SYNOPSIS
    Anonymizes node data with stable, deterministic pseudonyms.

.DESCRIPTION
    Provides:
    - Type-specific pseudonyms (TP-####, TI-####, ST-####, OP-####, LOC-####)
    - Stable mapping via SHA256 hash seeding
    - Structure and diff behavior preserved
    - Optional mapping export for internal use

.EXAMPLE
    $anon = New-AnonymizationContext -Seed 'demo-2026'
    $anonNodes = ConvertTo-AnonymizedNodes -Nodes $nodes -Context $anon
#>

# Pseudonym prefixes by node type
$Script:TypePrefixes = @{
    'ToolPrototype'  = 'TP'
    'ToolInstance'   = 'TI'
    'Station'        = 'ST'
    'Operation'      = 'OP'
    'Location'       = 'LOC'
    'Resource'       = 'RSC'
    'ResourceGroup'  = 'RG'
    'Root'           = 'ROOT'
    'Panel'          = 'PNL'
    'Zone'           = 'ZN'
    'Device'         = 'DEV'
    'Controller'     = 'CTL'
    'Frame'          = 'FRM'
    'Motion'         = 'MOT'
    'Weld'           = 'WLD'
    'default'        = 'NODE'
}

function New-AnonymizationContext {
    <#
    .SYNOPSIS
        Creates a new anonymization context with stable seed.
    #>
    param(
        [string]$Seed = 'simtreenav-anon',
        [switch]$ExportMapping
    )
    
    [PSCustomObject]@{
        seed           = $Seed
        exportMapping  = $ExportMapping.IsPresent
        nameMap        = @{}
        pathMap        = @{}
        idMap          = @{}
        counters       = @{}
        createdAt      = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Get-DeterministicPseudonym {
    <#
    .SYNOPSIS
        Generates a stable pseudonym based on input and seed.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OriginalValue,
        
        [Parameter(Mandatory)]
        [string]$NodeType,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )
    
    # Return cached mapping if exists
    $cacheKey = "$NodeType`:$OriginalValue"
    if ($Context.nameMap.ContainsKey($cacheKey)) {
        return $Context.nameMap[$cacheKey]
    }
    
    # Get type prefix
    $prefix = $Script:TypePrefixes[$NodeType]
    if (-not $prefix) { $prefix = $Script:TypePrefixes['default'] }
    
    # Initialize counter for this type
    if (-not $Context.counters.ContainsKey($NodeType)) {
        $Context.counters[$NodeType] = 0
    }
    
    # Compute deterministic hash to get stable ordering
    $hashInput = "$($Context.seed):$NodeType`:$OriginalValue"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($hashInput))
    $hashInt = [BitConverter]::ToUInt32($hashBytes, 0)
    
    # Use hash mod to get a stable number suffix
    $suffix = ($hashInt % 10000).ToString('D4')
    
    # Increment counter and create pseudonym
    $Context.counters[$NodeType]++
    $pseudonym = "$prefix-$suffix"
    
    # Ensure uniqueness by adding sequence if collision
    $existing = $Context.nameMap.Values | Where-Object { $_ -eq $pseudonym }
    if ($existing) {
        $seqNum = ($Context.counters[$NodeType] % 1000).ToString('D3')
        $pseudonym = "$prefix-$suffix-$seqNum"
    }
    
    # Cache the mapping
    $Context.nameMap[$cacheKey] = $pseudonym
    
    return $pseudonym
}

function ConvertTo-AnonymizedPath {
    <#
    .SYNOPSIS
        Anonymizes a path while preserving structure.
    #>
    param(
        [string]$Path,
        [PSCustomObject]$Context,
        [string]$NodeType = 'default'
    )
    
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    
    # Return cached if exists
    if ($Context.pathMap.ContainsKey($Path)) {
        return $Context.pathMap[$Path]
    }
    
    # Split path and anonymize each segment
    $segments = $Path -split '/'
    $anonSegments = @()
    
    foreach ($segment in $segments) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            $anonSegments += ''
            continue
        }
        
        # Get pseudonym for segment (use generic type for path segments)
        $pseudonym = Get-DeterministicPseudonym -OriginalValue $segment -NodeType $NodeType -Context $Context
        $anonSegments += $pseudonym
    }
    
    $anonPath = $anonSegments -join '/'
    $Context.pathMap[$Path] = $anonPath
    
    return $anonPath
}

function ConvertTo-AnonymizedNode {
    <#
    .SYNOPSIS
        Anonymizes a single node.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Node,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )
    
    # Deep copy the node
    $anonNode = $Node | ConvertTo-Json -Depth 10 | ConvertFrom-Json
    
    # Anonymize name
    $anonNode.name = Get-DeterministicPseudonym -OriginalValue $Node.name -NodeType $Node.nodeType -Context $Context
    
    # Anonymize path
    if ($Node.path) {
        $anonNode.path = ConvertTo-AnonymizedPath -Path $Node.path -Context $Context -NodeType $Node.nodeType
    }
    
    # Map node ID (for reference tracking)
    $Context.idMap[$Node.nodeId] = $anonNode.nodeId
    
    # Anonymize attributes if present
    if ($anonNode.attributes) {
        if ($anonNode.attributes.niceName) {
            $anonNode.attributes.niceName = $anonNode.name
        }
        if ($anonNode.attributes.externalId) {
            $anonNode.attributes.externalId = "ANON-$($Node.nodeId)"
        }
        if ($anonNode.attributes.className) {
            $anonNode.attributes.className = "$($Node.nodeType)Class"
        }
    }
    
    # Preserve source table structure but anonymize table names
    if ($anonNode.source -and $anonNode.source.table) {
        $anonNode.source.table = "ANON_DATA_TABLE"
    }
    
    return $anonNode
}

function ConvertTo-AnonymizedNodes {
    <#
    .SYNOPSIS
        Anonymizes an array of nodes.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [array]$Nodes = @(),
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )
    
    if (-not $Nodes -or $Nodes.Count -eq 0) { return @() }
    
    $anonNodes = @()
    
    foreach ($node in $Nodes) {
        $anonNodes += ConvertTo-AnonymizedNode -Node $node -Context $Context
    }
    
    return $anonNodes
}

function ConvertTo-AnonymizedDiff {
    <#
    .SYNOPSIS
        Anonymizes diff/changes data.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Diff,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )
    
    # Deep copy
    $anonDiff = $Diff | ConvertTo-Json -Depth 15 | ConvertFrom-Json
    
    # Anonymize each change
    if ($anonDiff.changes) {
        foreach ($change in $anonDiff.changes) {
            if ($change.nodeName) {
                $nodeType = if ($change.nodeType) { $change.nodeType } else { 'default' }
                $change.nodeName = Get-DeterministicPseudonym -OriginalValue $change.nodeName -NodeType $nodeType -Context $Context
            }
            if ($change.oldName) {
                $nodeType = if ($change.nodeType) { $change.nodeType } else { 'default' }
                $change.oldName = Get-DeterministicPseudonym -OriginalValue $change.oldName -NodeType $nodeType -Context $Context
            }
            if ($change.newName) {
                $nodeType = if ($change.nodeType) { $change.nodeType } else { 'default' }
                $change.newName = Get-DeterministicPseudonym -OriginalValue $change.newName -NodeType $nodeType -Context $Context
            }
            if ($change.path) {
                $change.path = ConvertTo-AnonymizedPath -Path $change.path -Context $Context
            }
            if ($change.oldPath) {
                $change.oldPath = ConvertTo-AnonymizedPath -Path $change.oldPath -Context $Context
            }
            if ($change.newPath) {
                $change.newPath = ConvertTo-AnonymizedPath -Path $change.newPath -Context $Context
            }
        }
    }
    
    return $anonDiff
}

function ConvertTo-AnonymizedSessions {
    <#
    .SYNOPSIS
        Anonymizes work sessions.
    #>
    param(
        [array]$Sessions,
        [PSCustomObject]$Context
    )
    
    if (-not $Sessions -or $Sessions.Count -eq 0) { return @() }
    
    $anonSessions = @()
    
    foreach ($session in $Sessions) {
        $anonSession = $session | ConvertTo-Json -Depth 15 | ConvertFrom-Json
        
        # Anonymize changes within session
        if ($anonSession.changes) {
            foreach ($change in $anonSession.changes) {
                if ($change.nodeName) {
                    $nodeType = if ($change.nodeType) { $change.nodeType } else { 'default' }
                    $change.nodeName = Get-DeterministicPseudonym -OriginalValue $change.nodeName -NodeType $nodeType -Context $Context
                }
            }
        }
        
        # Anonymize affected nodes
        if ($anonSession.affectedNodes) {
            $anonSession.affectedNodes = $anonSession.affectedNodes | ForEach-Object {
                Get-DeterministicPseudonym -OriginalValue $_ -NodeType 'default' -Context $Context
            }
        }
        
        $anonSessions += $anonSession
    }
    
    return $anonSessions
}

function ConvertTo-AnonymizedIntents {
    <#
    .SYNOPSIS
        Anonymizes intents data.
    #>
    param(
        [array]$Intents,
        [PSCustomObject]$Context
    )
    
    if (-not $Intents -or $Intents.Count -eq 0) { return @() }
    
    $anonIntents = @()
    
    foreach ($intent in $Intents) {
        $anonIntent = $intent | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        
        # Anonymize affected nodes/paths
        if ($anonIntent.affectedNodes) {
            $anonIntent.affectedNodes = $anonIntent.affectedNodes | ForEach-Object {
                Get-DeterministicPseudonym -OriginalValue $_ -NodeType 'default' -Context $Context
            }
        }
        
        if ($anonIntent.targetPath) {
            $anonIntent.targetPath = ConvertTo-AnonymizedPath -Path $anonIntent.targetPath -Context $Context
        }
        
        $anonIntents += $anonIntent
    }
    
    return $anonIntents
}

function Export-AnonymizationMapping {
    <#
    .SYNOPSIS
        Exports the anonymization mapping to a file (for internal use only).
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context,
        
        [Parameter(Mandatory)]
        [string]$OutputPath
    )
    
    $mapping = [PSCustomObject]@{
        seed       = $Context.seed
        createdAt  = $Context.createdAt
        exportedAt = (Get-Date).ToUniversalTime().ToString('o')
        nameMap    = $Context.nameMap
        pathMap    = $Context.pathMap
        idMap      = $Context.idMap
        counters   = $Context.counters
        warning    = "CONFIDENTIAL: This file contains original-to-pseudonym mappings. Do not share externally."
    }
    
    $json = $mapping | ConvertTo-Json -Depth 10
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutputPath, $json, $utf8NoBom)
    
    return $OutputPath
}

function Import-AnonymizationMapping {
    <#
    .SYNOPSIS
        Imports a previously saved anonymization mapping.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    
    if (-not (Test-Path $Path)) {
        throw "Anonymization mapping file not found: $Path"
    }
    
    $mapping = Get-Content $Path -Raw | ConvertFrom-Json
    
    # Reconstruct context
    $context = New-AnonymizationContext -Seed $mapping.seed
    
    # Restore maps (convert from PSCustomObject to hashtable)
    $mapping.nameMap.PSObject.Properties | ForEach-Object {
        $context.nameMap[$_.Name] = $_.Value
    }
    $mapping.pathMap.PSObject.Properties | ForEach-Object {
        $context.pathMap[$_.Name] = $_.Value
    }
    $mapping.idMap.PSObject.Properties | ForEach-Object {
        $context.idMap[$_.Name] = $_.Value
    }
    $mapping.counters.PSObject.Properties | ForEach-Object {
        $context.counters[$_.Name] = $_.Value
    }
    
    return $context
}

function Get-AnonymizationSummary {
    <#
    .SYNOPSIS
        Returns summary statistics for an anonymization context.
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Context
    )
    
    [PSCustomObject]@{
        seed                = $Context.seed
        totalNamesAnonymized = $Context.nameMap.Count
        totalPathsAnonymized = $Context.pathMap.Count
        totalIdsTracked     = $Context.idMap.Count
        typeBreakdown       = $Context.counters.Clone()
        createdAt           = $Context.createdAt
    }
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'New-AnonymizationContext',
        'Get-DeterministicPseudonym',
        'ConvertTo-AnonymizedPath',
        'ConvertTo-AnonymizedNode',
        'ConvertTo-AnonymizedNodes',
        'ConvertTo-AnonymizedDiff',
        'ConvertTo-AnonymizedSessions',
        'ConvertTo-AnonymizedIntents',
        'Export-AnonymizationMapping',
        'Import-AnonymizationMapping',
        'Get-AnonymizationSummary'
    )
}
