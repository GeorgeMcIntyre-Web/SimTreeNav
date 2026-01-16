# NodeContract.ps1
# Canonical node representation for SimTreeNav v0.2
# All nodes across Resource/Operation/MFG/Panel domains use this contract

<#
.SYNOPSIS
    Defines the canonical Node contract for SimTreeNav.

.DESCRIPTION
    This module provides functions to create, validate, and serialize nodes
    according to the SimTreeNav v0.2 canonical node contract.

    Node Types:
    - ResourceGroup: Stations, lines, cells, compound resources
    - ToolPrototype: Tool definitions (one-to-many with instances)
    - ToolInstance: Actual tool instances (robots, equipment)
    - OperationGroup: Study folders, compound operations
    - Operation: Individual operations (weld, move, etc.)
    - Location: Locations, poses, shortcuts
    - MfgEntity: Manufacturing definitions
    - PanelEntity: Panel data, parts, assemblies
    - Unknown: Unclassified nodes
#>

# Valid node types enum
$Script:ValidNodeTypes = @(
    'ResourceGroup',
    'ToolPrototype',
    'ToolInstance',
    'OperationGroup',
    'Operation',
    'Location',
    'MfgEntity',
    'PanelEntity',
    'Unknown'
)

function New-SimTreeNode {
    <#
    .SYNOPSIS
        Creates a new canonical node object.
    
    .PARAMETER NodeId
        Unique identifier (string form of OBJECT_ID).
    
    .PARAMETER NodeType
        One of: ResourceGroup, ToolPrototype, ToolInstance, OperationGroup, Operation, Location, MfgEntity, PanelEntity, Unknown.
    
    .PARAMETER Name
        Display name of the node.
    
    .PARAMETER ParentId
        Parent node ID (null for root).
    
    .PARAMETER Attributes
        Flexible metadata hashtable.
    
    .PARAMETER Links
        Cross-tree references hashtable.
    
    .PARAMETER Source
        Source metadata (table, query).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet('ResourceGroup', 'ToolPrototype', 'ToolInstance', 'OperationGroup', 'Operation', 'Location', 'MfgEntity', 'PanelEntity', 'Unknown')]
        [string]$NodeType,
        
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$ParentId = $null,
        
        [string]$ExternalId = '',
        
        [string]$ClassName = '',
        
        [string]$NiceName = '',
        
        [int]$TypeId = 0,
        
        [int]$SeqNumber = 0,
        
        [hashtable]$Attributes = @{},
        
        [hashtable]$Links = @{},
        
        [hashtable]$Timestamps = @{},
        
        [hashtable]$Source = @{}
    )
    
    # Build path (will be computed later in context)
    $path = "/$Name"
    
    # Compute fingerprints for diffing
    $contentHash = Get-ContentHash -Name $Name -ExternalId $ExternalId -ClassName $ClassName
    $attributeHash = Get-AttributeHash -Attributes $Attributes
    
    # Build attributes hashtable first, then merge custom attributes
    $attrHash = @{
        externalId  = $ExternalId
        className   = $ClassName
        niceName    = $NiceName
        typeId      = $TypeId
        seqNumber   = $SeqNumber
    }
    # Merge any additional attributes
    foreach ($key in $Attributes.Keys) {
        $attrHash[$key] = $Attributes[$key]
    }
    
    [PSCustomObject]@{
        nodeId      = $NodeId
        nodeType    = $NodeType
        name        = $Name
        parentId    = $ParentId
        path        = $path
        attributes  = [PSCustomObject]$attrHash
        links       = [PSCustomObject]$Links
        fingerprints = [PSCustomObject]@{
            contentHash   = $contentHash
            attributeHash = $attributeHash
            transformHash = $null
        }
        timestamps  = [PSCustomObject]@{
            createdAt     = $Timestamps['createdAt']
            updatedAt     = $Timestamps['updatedAt']
            lastTouchedAt = $Timestamps['lastTouchedAt']
        }
        source      = [PSCustomObject]@{
            table     = $Source['table']
            query     = $Source['query']
            schema    = $Source['schema']
        }
    }
}

function Get-ContentHash {
    <#
    .SYNOPSIS
        Computes a stable content hash for node identity comparison.
    #>
    param(
        [string]$Name,
        [string]$ExternalId,
        [string]$ClassName
    )
    
    $content = "$Name|$ExternalId|$ClassName"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16).ToLower()
}

function Get-AttributeHash {
    <#
    .SYNOPSIS
        Computes a hash of node attributes for change detection.
    #>
    param(
        [hashtable]$Attributes
    )
    
    if (-not $Attributes -or $Attributes.Count -eq 0) {
        return $null
    }
    
    # Sort keys for deterministic hashing
    $sortedPairs = $Attributes.GetEnumerator() | Sort-Object Name | ForEach-Object {
        "$($_.Name)=$($_.Value)"
    }
    $content = $sortedPairs -join '|'
    
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16).ToLower()
}

function Get-TransformHash {
    <#
    .SYNOPSIS
        Computes a hash for transform/location data.
    #>
    param(
        [double[]]$Transform
    )
    
    if (-not $Transform -or $Transform.Count -eq 0) {
        return $null
    }
    
    # Round to 6 decimal places for stability
    $rounded = $Transform | ForEach-Object { [Math]::Round($_, 6) }
    $content = $rounded -join ','
    
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 16).ToLower()
}

function ConvertFrom-PipeDelimited {
    <#
    .SYNOPSIS
        Converts pipe-delimited line to canonical node.
    
    .DESCRIPTION
        Parses the existing output format:
        LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Line,
        
        [string]$Schema = '',
        
        [string]$SourceTable = 'COLLECTION_',
        
        [hashtable]$NodeTypeRules = @{}
    )
    
    if (-not $Line -or -not $Line.Contains('|')) {
        return $null
    }
    
    $parts = $Line.Split('|')
    if ($parts.Count -lt 9) {
        return $null
    }
    
    $level = [int]$parts[0]
    $parentId = $parts[1]
    $objectId = $parts[2]
    $caption = $parts[3]
    $name = $parts[4]
    $externalId = $parts[5]
    $seqNumber = if ($parts[6]) { [int]$parts[6] } else { 0 }
    $className = $parts[7]
    $niceName = $parts[8]
    $typeId = if ($parts.Count -ge 10 -and $parts[9]) { [int]$parts[9] } else { 0 }
    
    # Determine node type from class name
    $nodeType = Get-NodeTypeFromClass -ClassName $className -Rules $NodeTypeRules
    
    # Use caption as display name, fallback to name
    $displayName = if ($caption -and $caption -ne 'Unnamed') { $caption } else { $name }
    if (-not $displayName -or $displayName -eq 'Unnamed') {
        $displayName = "Node_$objectId"
    }
    
    # Handle root case (parentId = 0)
    $parentIdValue = if ($parentId -eq '0' -or [string]::IsNullOrWhiteSpace($parentId)) { $null } else { $parentId }
    
    New-SimTreeNode `
        -NodeId $objectId `
        -NodeType $nodeType `
        -Name $displayName `
        -ParentId $parentIdValue `
        -ExternalId $externalId `
        -ClassName $className `
        -NiceName $niceName `
        -TypeId $typeId `
        -SeqNumber $seqNumber `
        -Attributes @{ level = $level } `
        -Source @{ table = $SourceTable; schema = $Schema; query = 'tree-extraction' }
}

function Get-NodeTypeFromClass {
    <#
    .SYNOPSIS
        Determines node type from class name using pattern matching.
    #>
    param(
        [string]$ClassName,
        [hashtable]$Rules = @{}
    )
    
    if ([string]::IsNullOrWhiteSpace($ClassName)) {
        return 'Unknown'
    }
    
    # Default rules if none provided
    $defaultRules = @{
        'ResourceGroup'  = @('PmProject', 'PmPlant', 'PmFactory', 'PmLine', 'PmStation', 'PmCell', 'PmZone', 'PmCompoundResource', 'PmResourceLibrary', 'Collection', 'RobcadResourceLibrary')
        'ToolPrototype'  = @('ToolPrototype', 'Equipment')
        'ToolInstance'   = @('ToolInstanceAspect', 'Robot', 'Device', 'Resource')
        'OperationGroup' = @('PmStudy', 'PmStudyFolder', 'RobcadStudy', 'LineSimulationStudy', 'GanttStudy', 'SimpleDetailedStudy', 'LocationalStudy')
        'Operation'      = @('Operation', 'WeldOperation', 'MoveOperation', 'PickOperation', 'PlaceOperation')
        'Location'       = @('PmShortcut', 'Shortcut', 'Location')
        'MfgEntity'      = @('PmMfg', 'MfgLibrary', 'MfgFeature')
        'PanelEntity'    = @('PmPart', 'Part', 'Assembly', 'CompoundPart', 'TxProcessAssembly')
    }
    
    $rulesMap = if ($Rules.Count -gt 0) { $Rules } else { $defaultRules }
    
    # Extract clean class name (remove 'class ' prefix)
    $cleanClass = $ClassName -replace '^class\s+', ''
    
    foreach ($nodeType in $rulesMap.Keys) {
        foreach ($pattern in $rulesMap[$nodeType]) {
            if ($cleanClass -like "*$pattern*") {
                return $nodeType
            }
        }
    }
    
    return 'Unknown'
}

function ConvertTo-CanonicalJson {
    <#
    .SYNOPSIS
        Converts node collection to deterministic JSON.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Nodes,
        
        [switch]$Pretty
    )
    
    # Sort by nodeId for deterministic output
    $sortedNodes = $Nodes | Sort-Object { [long]$_.nodeId }
    
    $depth = if ($Pretty) { 10 } else { 2 }
    $sortedNodes | ConvertTo-Json -Depth $depth -Compress:(-not $Pretty)
}

function Compute-NodePaths {
    <#
    .SYNOPSIS
        Computes full paths for all nodes based on parent hierarchy.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Nodes
    )
    
    # Build lookup table
    $nodeMap = @{}
    foreach ($node in $Nodes) {
        $nodeMap[$node.nodeId] = $node
    }
    
    # Compute paths iteratively
    foreach ($node in $Nodes) {
        $pathParts = @($node.name)
        $currentId = $node.parentId
        $visited = @{}
        
        while ($currentId -and $nodeMap.ContainsKey($currentId) -and -not $visited.ContainsKey($currentId)) {
            $visited[$currentId] = $true
            $parent = $nodeMap[$currentId]
            $pathParts = @($parent.name) + $pathParts
            $currentId = $parent.parentId
        }
        
        $node.path = '/' + ($pathParts -join '/')
    }
    
    return $Nodes
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'New-SimTreeNode',
        'Get-ContentHash',
        'Get-AttributeHash',
        'Get-TransformHash',
        'ConvertFrom-PipeDelimited',
        'Get-NodeTypeFromClass',
        'ConvertTo-CanonicalJson',
        'Compute-NodePaths'
    )
}
