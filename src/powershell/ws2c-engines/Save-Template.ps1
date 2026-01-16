<#
.SYNOPSIS
    Saves a compliance template from a subtree of nodes.
    
.DESCRIPTION
    Creates a template JSON file that captures the structure, naming rules,
    required types, and links from a given subtree. This template can then
    be used to check compliance of other subtrees.
    
.PARAMETER NodesPath
    Path to the nodes JSON file.
    
.PARAMETER NodeId
    The root node ID to create template from.
    
.PARAMETER TemplateName
    Name for the template.
    
.PARAMETER OutPath
    Output path for the template JSON file.
    
.EXAMPLE
    Save-Template -NodesPath nodes.json -NodeId "1" -TemplateName "StationTemplate" -OutPath template.json
#>

function Save-Template {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodesPath,
        
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [string]$TemplateName,
        
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
    
    # Guard: Check if root node exists
    if (-not $nodeMap.ContainsKey($NodeId)) {
        Write-Warning "Root node not found: $NodeId"
        return $false
    }
    
    $rootNode = $nodeMap[$NodeId]
    
    # Collect subtree nodes
    $subtreeNodes = @()
    $queue = [System.Collections.Queue]::new()
    $queue.Enqueue($NodeId)
    $visited = @{}
    
    while ($queue.Count -gt 0) {
        $currentId = $queue.Dequeue()
        
        if ($visited.ContainsKey($currentId)) {
            continue
        }
        $visited[$currentId] = $true
        
        if ($nodeMap.ContainsKey($currentId)) {
            $subtreeNodes += $nodeMap[$currentId]
        }
        
        # Find children
        foreach ($node in $nodes) {
            if ($node.parentId -eq $currentId -and -not $visited.ContainsKey($node.id)) {
                $queue.Enqueue($node.id)
            }
        }
    }
    
    # Analyze subtree for template creation
    
    # 1. Count node types (for requiredTypes)
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
    
    $requiredTypes = @()
    foreach ($nodeType in ($typeCounts.Keys | Sort-Object)) {
        $count = $typeCounts[$nodeType]
        $requiredTypes += @{
            nodeType = $nodeType
            min = 1
            max = [Math]::Max($count * 2, 10)  # Allow some flexibility
        }
    }
    
    # 2. Analyze parent-child links (for requiredLinks)
    $linkSet = @{}
    foreach ($node in $subtreeNodes) {
        if ($node.parentId -and $nodeMap.ContainsKey($node.parentId)) {
            $parentNode = $nodeMap[$node.parentId]
            $linkKey = "$($parentNode.nodeType)->$($node.nodeType)"
            $linkSet[$linkKey] = @{
                from = $parentNode.nodeType
                to = $node.nodeType
            }
        }
    }
    
    $requiredLinks = @()
    foreach ($linkKey in ($linkSet.Keys | Sort-Object)) {
        $requiredLinks += $linkSet[$linkKey]
    }
    
    # 3. Infer naming rules (for namingRules)
    $namingPatterns = @{}
    foreach ($node in $subtreeNodes) {
        $nodeType = $node.nodeType
        if (-not $nodeType) {
            continue
        }
        
        $name = $node.name
        if (-not $name) {
            continue
        }
        
        # Try to infer pattern from name
        $pattern = InferNamingPattern -Name $name -NodeType $nodeType
        
        if (-not $namingPatterns.ContainsKey($nodeType)) {
            $namingPatterns[$nodeType] = $pattern
        }
    }
    
    $namingRules = @()
    foreach ($nodeType in ($namingPatterns.Keys | Sort-Object)) {
        $namingRules += @{
            nodeType = $nodeType
            pattern = $namingPatterns[$nodeType]
        }
    }
    
    # 4. Build template
    $template = [ordered]@{
        name = $TemplateName
        version = "1.0"
        rootType = $rootNode.nodeType
        requiredTypes = $requiredTypes
        requiredLinks = $requiredLinks
        namingRules = $namingRules
        allowedExtras = $true
        driftRules = @()
    }
    
    # Ensure output directory exists
    $outDir = Split-Path $OutPath -Parent
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    
    # Write template (deterministic output with sorted keys)
    $template | ConvertTo-Json -Depth 10 | Set-Content -Path $OutPath -Encoding UTF8
    
    return $true
}

function InferNamingPattern {
    param(
        [string]$Name,
        [string]$NodeType
    )
    
    # Common patterns to match
    # Pattern: Type_###
    if ($Name -match "^${NodeType}_\d{3}$") {
        return "^${NodeType}_\d{3}$"
    }
    
    # Pattern: Type###
    if ($Name -match "^${NodeType}\d{3}$") {
        return "^${NodeType}\d{3}$"
    }
    
    # Pattern: Prefix_Type_###
    if ($Name -match "^[A-Za-z]+_${NodeType}_\d+$") {
        return "^[A-Za-z]+_${NodeType}_\d+$"
    }
    
    # Pattern: WordChars with underscores
    if ($Name -match "^\w+$") {
        return "^\w+$"
    }
    
    # Default: alphanumeric with underscores
    return "^[A-Za-z0-9_]+$"
}

# Export function for module use
Export-ModuleMember -Function Save-Template -ErrorAction SilentlyContinue
