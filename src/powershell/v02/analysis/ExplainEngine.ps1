# ExplainEngine.ps1
# "Explain this node" - generates developer documentation
# v0.3: Reverse engineering into maintainable knowledge

<#
.SYNOPSIS
    Generates documentation explaining how a node was extracted and what it represents.

.DESCRIPTION
    For any node, produces:
    - Which extraction query produced it
    - Which tables/columns contributed to its attributes
    - Which keys define identity
    - Which links connect it to twins/prototypes/ops/mfg/panels

    Goal: turn reverse engineering into maintainable knowledge

.EXAMPLE
    $explanation = Get-NodeExplanation -NodeId 'N12345' -Nodes $nodes -Config $config
#>

# Source table mappings (from config or defaults)
$Script:SourceTableMappings = @{
    # Core tables
    'DF_ROBCADSTUDY_DESIGN'       = @{ description = 'Root study/project container'; nodeTypes = @('Root', 'Study') }
    'DF_TX_FRAMES'                = @{ description = 'Frame definitions (coordinate systems)'; nodeTypes = @('Frame') }
    'DF_TXSIMRESOURCE_DATA'       = @{ description = 'Simulation resources (robots, devices)'; nodeTypes = @('Resource', 'Robot', 'Device') }
    'DF_TXSIMRESOURCE_HIERACHY'   = @{ description = 'Resource hierarchy relationships'; nodeTypes = @('ResourceGroup') }
    'DF_TXSIMRESOURCETYPE_DATA'   = @{ description = 'Resource type definitions'; nodeTypes = @('ResourceType') }
    'DF_TXSIMTOOLPROTO_DATA'      = @{ description = 'Tool prototype definitions'; nodeTypes = @('ToolPrototype') }
    'DF_TXSIMTOOLINSTANCEASPECT_DATA' = @{ description = 'Tool instance aspects'; nodeTypes = @('ToolInstance') }
    
    # Operation tables
    'DF_TXSIMOPERATION_DATA'      = @{ description = 'Operation definitions'; nodeTypes = @('Operation') }
    'DF_TXSIMLOCATION_DATA'       = @{ description = 'Location points/targets'; nodeTypes = @('Location') }
    'DF_TXSIMCOMPOUND_OPERATION_DATA' = @{ description = 'Compound operations'; nodeTypes = @('CompoundOperation') }
    
    # MFG/Panel tables
    'DF_MFG_ENTITY_DATA'          = @{ description = 'Manufacturing entity definitions'; nodeTypes = @('MfgEntity') }
    'DF_PANEL_ENTITY_DATA'        = @{ description = 'Panel entity definitions'; nodeTypes = @('PanelEntity') }
}

# Attribute source mappings
$Script:AttributeMappings = @{
    'externalId'  = @{ column = 'EXTERNAL_ID'; description = 'Siemens-assigned unique identifier (PP-uuid format)' }
    'className'   = @{ column = 'CLASS_NAME'; description = 'Siemens class type identifier' }
    'niceName'    = @{ column = 'NICE_NAME'; description = 'Display-friendly name' }
    'typeId'      = @{ column = 'TYPE_ID'; description = 'Type classification identifier' }
    'seqNumber'   = @{ column = 'SEQ_NUMBER'; description = 'Sequence order within parent' }
    'transform'   = @{ column = 'TRANSFORM / location fields'; description = 'Position and rotation in 3D space' }
}

# Link type explanations
$Script:LinkExplanations = @{
    'prototypeId' = 'Links a tool instance to its prototype definition'
    'twinId'      = 'Links operation/resource twins across object/resource trees'
    'mfgEntityId' = 'Links to manufacturing entity definition'
    'panelId'     = 'Links to panel data entity'
    'parentId'    = 'Hierarchical parent relationship'
}

function Get-SourceTableInfo {
    <#
    .SYNOPSIS
        Gets source table information for a node type.
    #>
    param(
        [string]$NodeType,
        [string]$SourceTable = $null
    )
    
    # Try to find mapping by source table
    if ($SourceTable -and $Script:SourceTableMappings.ContainsKey($SourceTable)) {
        return $Script:SourceTableMappings[$SourceTable]
    }
    
    # Try to find by node type
    foreach ($entry in $Script:SourceTableMappings.GetEnumerator()) {
        if ($NodeType -in $entry.Value.nodeTypes) {
            return [PSCustomObject]@{
                table = $entry.Key
                description = $entry.Value.description
                nodeTypes = $entry.Value.nodeTypes
            }
        }
    }
    
    return [PSCustomObject]@{
        table = 'Unknown'
        description = 'Source table not identified'
        nodeTypes = @()
    }
}

function Get-AttributeExplanation {
    <#
    .SYNOPSIS
        Explains where an attribute comes from.
    #>
    param(
        [string]$AttributeName
    )
    
    if ($Script:AttributeMappings.ContainsKey($AttributeName)) {
        return $Script:AttributeMappings[$AttributeName]
    }
    
    return @{
        column = $AttributeName.ToUpper()
        description = 'Custom or derived attribute'
    }
}

function Get-LinkExplanation {
    <#
    .SYNOPSIS
        Explains what a link type means.
    #>
    param(
        [string]$LinkType
    )
    
    if ($Script:LinkExplanations.ContainsKey($LinkType)) {
        return $Script:LinkExplanations[$LinkType]
    }
    
    return "Link to related node ($LinkType)"
}

function Get-IdentityKeyExplanation {
    <#
    .SYNOPSIS
        Explains what defines this node's identity.
    #>
    param(
        [PSCustomObject]$Node
    )
    
    $keys = @()
    
    # Primary key: nodeId (OBJECT_ID)
    $keys += [PSCustomObject]@{
        key         = 'nodeId'
        value       = $Node.nodeId
        stability   = 'Low'
        description = 'Database OBJECT_ID - can change with rekey operations'
    }
    
    # External ID (most stable)
    $externalId = if ($Node.attributes) { $Node.attributes.externalId } else { $null }
    if ($externalId) {
        $keys += [PSCustomObject]@{
            key         = 'externalId'
            value       = $externalId
            stability   = 'High'
            description = 'Siemens-assigned identifier - stable across exports/imports'
        }
    }
    
    # Structural identity
    $keys += [PSCustomObject]@{
        key         = 'path'
        value       = $Node.path
        stability   = 'Medium'
        description = 'Hierarchical path - changes when node or ancestors move'
    }
    
    # Content hash
    $contentHash = if ($Node.fingerprints) { $Node.fingerprints.contentHash } else { $null }
    if ($contentHash) {
        $keys += [PSCustomObject]@{
            key         = 'contentHash'
            value       = $contentHash
            stability   = 'Derived'
            description = 'Hash of name + externalId + className - changes with any of these'
        }
    }
    
    return $keys
}

function Get-RelatedNodes {
    <#
    .SYNOPSIS
        Gets nodes related to this one via links.
    #>
    param(
        [PSCustomObject]$Node,
        [array]$AllNodes
    )
    
    $related = @()
    $nodeById = @{}
    foreach ($n in $AllNodes) {
        $nodeById[$n.nodeId] = $n
    }
    
    # Parent
    if ($Node.parentId -and $nodeById.ContainsKey($Node.parentId)) {
        $parent = $nodeById[$Node.parentId]
        $related += [PSCustomObject]@{
            relationship = 'parent'
            nodeId       = $parent.nodeId
            name         = $parent.name
            nodeType     = $parent.nodeType
            direction    = 'up'
        }
    }
    
    # Children
    $children = $AllNodes | Where-Object { $_.parentId -eq $Node.nodeId }
    foreach ($child in $children | Select-Object -First 5) {
        $related += [PSCustomObject]@{
            relationship = 'child'
            nodeId       = $child.nodeId
            name         = $child.name
            nodeType     = $child.nodeType
            direction    = 'down'
        }
    }
    if ($children.Count -gt 5) {
        $related += [PSCustomObject]@{
            relationship = 'children'
            nodeId       = '...'
            name         = "($($children.Count - 5) more children)"
            nodeType     = 'various'
            direction    = 'down'
        }
    }
    
    # Links
    if ($Node.links) {
        foreach ($prop in $Node.links.PSObject.Properties) {
            if ($prop.Value -and $prop.Name -ne 'parentId') {
                $linkedId = if ($prop.Value -is [array]) { $prop.Value[0] } else { $prop.Value }
                $linkedNode = if ($nodeById.ContainsKey($linkedId)) { $nodeById[$linkedId] } else { $null }
                
                $related += [PSCustomObject]@{
                    relationship = $prop.Name
                    nodeId       = $linkedId
                    name         = if ($linkedNode) { $linkedNode.name } else { 'Unknown' }
                    nodeType     = if ($linkedNode) { $linkedNode.nodeType } else { 'Unknown' }
                    direction    = 'link'
                    explanation  = Get-LinkExplanation -LinkType $prop.Name
                }
            }
        }
    }
    
    return $related
}

function Get-NodeExplanation {
    <#
    .SYNOPSIS
        Main entry point - generates complete explanation for a node.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [array]$Nodes
    )
    
    $node = $Nodes | Where-Object { $_.nodeId -eq $NodeId } | Select-Object -First 1
    
    if (-not $node) {
        return [PSCustomObject]@{
            error = "Node not found: $NodeId"
        }
    }
    
    # Get source table info
    $sourceTable = if ($node.source) { $node.source.table } else { $null }
    $sourceInfo = Get-SourceTableInfo -NodeType $node.nodeType -SourceTable $sourceTable
    
    # Explain attributes
    $attributeExplanations = @()
    if ($node.attributes) {
        foreach ($prop in $node.attributes.PSObject.Properties) {
            $explanation = Get-AttributeExplanation -AttributeName $prop.Name
            $attributeExplanations += [PSCustomObject]@{
                attribute   = $prop.Name
                value       = $prop.Value
                column      = $explanation.column
                description = $explanation.description
            }
        }
    }
    
    # Get identity keys
    $identityKeys = Get-IdentityKeyExplanation -Node $node
    
    # Get related nodes
    $relatedNodes = Get-RelatedNodes -Node $node -AllNodes $Nodes
    
    # Build explanation
    [PSCustomObject]@{
        nodeId           = $node.nodeId
        name             = $node.name
        nodeType         = $node.nodeType
        path             = $node.path
        
        source           = [PSCustomObject]@{
            table        = $sourceInfo.table
            description  = $sourceInfo.description
            query        = "SELECT * FROM $($sourceInfo.table) WHERE OBJECT_ID = '$($node.nodeId)'"
        }
        
        identityKeys     = $identityKeys
        
        attributes       = $attributeExplanations
        
        relationships    = $relatedNodes
        
        fingerprints     = if ($node.fingerprints) {
            [PSCustomObject]@{
                contentHash   = $node.fingerprints.contentHash
                attributeHash = $node.fingerprints.attributeHash
                transformHash = $node.fingerprints.transformHash
                description   = 'Deterministic hashes for change detection and identity matching'
            }
        } else { $null }
        
        notes            = @(
            "Node type '$($node.nodeType)' is extracted from the $($sourceInfo.description)"
            if ($node.links -and $node.links.prototypeId) { "This is an instance of a prototype" }
            if ($relatedNodes | Where-Object { $_.relationship -eq 'twin' }) { "Has twin relationship in resource/operation tree" }
        ) | Where-Object { $_ }
        
        generatedAt      = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Export-ExplanationMarkdown {
    <#
    .SYNOPSIS
        Exports explanation as Markdown document.
    #>
    param(
        [PSCustomObject]$Explanation,
        [string]$OutputPath
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $md = @"
# Node Explanation: $($Explanation.name)

**Node ID:** ``$($Explanation.nodeId)``  
**Type:** $($Explanation.nodeType)  
**Path:** ``$($Explanation.path)``

## Source

**Table:** ``$($Explanation.source.table)``  
**Description:** $($Explanation.source.description)

```sql
$($Explanation.source.query)
```

## Identity Keys

| Key | Value | Stability | Description |
|-----|-------|-----------|-------------|
$(($Explanation.identityKeys | ForEach-Object { "| $($_.key) | ``$($_.value)`` | $($_.stability) | $($_.description) |" }) -join "`n")

## Attributes

| Attribute | Value | Source Column | Description |
|-----------|-------|---------------|-------------|
$(($Explanation.attributes | ForEach-Object { "| $($_.attribute) | ``$($_.value)`` | ``$($_.column)`` | $($_.description) |" }) -join "`n")

## Relationships

$(($Explanation.relationships | ForEach-Object { "- **$($_.relationship)**: $($_.name) ($($_.nodeType)) ``$($_.nodeId)``" }) -join "`n")

## Fingerprints

$(if ($Explanation.fingerprints) { @"
- **contentHash:** ``$($Explanation.fingerprints.contentHash)``
- **attributeHash:** ``$($Explanation.fingerprints.attributeHash)``
- **transformHash:** ``$($Explanation.fingerprints.transformHash)``

$($Explanation.fingerprints.description)
"@ } else { "_No fingerprints available_" })

## Notes

$(($Explanation.notes | ForEach-Object { "- $_" }) -join "`n")

---
*Generated: $($Explanation.generatedAt)*
"@
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $filePath = Join-Path $OutputPath "$($Explanation.nodeId).md"
    [System.IO.File]::WriteAllText($filePath, $md, $utf8NoBom)
    
    return $filePath
}

function Export-ExplanationJson {
    <#
    .SYNOPSIS
        Exports explanation as JSON.
    #>
    param(
        [PSCustomObject]$Explanation,
        [string]$OutputPath,
        [switch]$Pretty
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $json = if ($Pretty) {
        $Explanation | ConvertTo-Json -Depth 10
    } else {
        $Explanation | ConvertTo-Json -Depth 10 -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $filePath = Join-Path $OutputPath "$($Explanation.nodeId).json"
    [System.IO.File]::WriteAllText($filePath, $json, $utf8NoBom)
    
    return $filePath
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Get-NodeExplanation',
        'Get-SourceTableInfo',
        'Get-AttributeExplanation',
        'Get-LinkExplanation',
        'Get-IdentityKeyExplanation',
        'Get-RelatedNodes',
        'Export-ExplanationMarkdown',
        'Export-ExplanationJson'
    )
}
