# ImpactEngine.ps1
# Computes dependency graph and "blast radius" for nodes
# v0.3: Impact analysis for change planning and risk assessment

<#
.SYNOPSIS
    Computes dependency graph and impact analysis for nodes.

.DESCRIPTION
    For any node, computes:
    - Upstream references (who defines/sources this node)
    - Downstream dependents (who uses/references this node)
    - Cross-tree "twin" links
    - Prototype-instance relationships
    - Risk score based on dependent count and node criticality

    This enables:
    - "What will break if I change this?" analysis
    - Change planning and risk assessment
    - Understanding node relationships

.EXAMPLE
    $impact = Get-NodeImpact -NodeId 'N12345' -Nodes $allNodes
#>

# Node criticality weights (higher = more critical)
$Script:CriticalityWeights = @{
    'Station'           = 1.0
    'ResourceGroup'     = 0.8
    'Resource'          = 0.7
    'ToolPrototype'     = 0.9
    'ToolInstance'      = 0.6
    'Operation'         = 0.7
    'Location'          = 0.5
    'MfgEntity'         = 0.8
    'PanelEntity'       = 0.7
    'CompoundResource'  = 0.6
    'Frame'             = 0.4
    'Root'              = 1.0
    'Default'           = 0.5
}

# Change severity weights
$Script:SeverityWeights = @{
    'removed'           = 1.0
    'moved'             = 0.8
    'renamed'           = 0.6
    'rekeyed'           = 0.5
    'attribute_changed' = 0.4
    'transform_changed' = 0.3
    'added'             = 0.2
}

function Build-DependencyGraph {
    <#
    .SYNOPSIS
        Builds a complete dependency graph from nodes.
    
    .DESCRIPTION
        Creates adjacency lists for:
        - Parent-child relationships
        - Prototype-instance links
        - Twin (Resource-Operation) links
        - Custom link relationships
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [array]$Nodes = @()
    )
    
    $graph = @{
        # Node lookup
        nodes = @{}
        
        # Parent-child: parent -> [children]
        children = @{}
        
        # Child-parent: child -> parent
        parents = @{}
        
        # Prototype-instance: prototype -> [instances]
        prototypeInstances = @{}
        
        # Instance-prototype: instance -> prototype
        instancePrototypes = @{}
        
        # Twin links: nodeId -> [twinNodeIds]
        twins = @{}
        
        # Generic links: nodeId -> [linkedNodeIds]
        links = @{}
        
        # Reverse links: nodeId -> [nodesLinkingToMe]
        reverseLinks = @{}
    }
    
    # Handle empty input
    if (-not $Nodes -or $Nodes.Count -eq 0) { return $graph }
    
    # Build node lookup and relationships
    foreach ($node in $Nodes) {
        $nodeId = $node.nodeId
        $graph.nodes[$nodeId] = $node
        
        # Parent-child
        if ($node.parentId) {
            $parentId = $node.parentId
            if (-not $graph.children.ContainsKey($parentId)) {
                $graph.children[$parentId] = @()
            }
            $graph.children[$parentId] += $nodeId
            $graph.parents[$nodeId] = $parentId
        }
        
        # Prototype-instance from links
        if ($node.links -and $node.links.prototypeId) {
            $protoId = $node.links.prototypeId
            if (-not $graph.prototypeInstances.ContainsKey($protoId)) {
                $graph.prototypeInstances[$protoId] = @()
            }
            $graph.prototypeInstances[$protoId] += $nodeId
            $graph.instancePrototypes[$nodeId] = $protoId
        }
        
        # Twin links from links
        if ($node.links -and $node.links.twinId) {
            $twinId = $node.links.twinId
            if (-not $graph.twins.ContainsKey($nodeId)) {
                $graph.twins[$nodeId] = @()
            }
            $graph.twins[$nodeId] += $twinId
            
            # Bidirectional
            if (-not $graph.twins.ContainsKey($twinId)) {
                $graph.twins[$twinId] = @()
            }
            if ($graph.twins[$twinId] -notcontains $nodeId) {
                $graph.twins[$twinId] += $nodeId
            }
        }
        
        # Generic links
        if ($node.links) {
            $linkTargets = @()
            
            # Collect all link targets
            foreach ($prop in $node.links.PSObject.Properties) {
                if ($prop.Value -and $prop.Name -notin @('prototypeId', 'twinId')) {
                    if ($prop.Value -is [array]) {
                        $linkTargets += $prop.Value
                    }
                    else {
                        $linkTargets += $prop.Value
                    }
                }
            }
            
            if ($linkTargets.Count -gt 0) {
                $graph.links[$nodeId] = $linkTargets
                
                # Build reverse links
                foreach ($target in $linkTargets) {
                    if (-not $graph.reverseLinks.ContainsKey($target)) {
                        $graph.reverseLinks[$target] = @()
                    }
                    if ($graph.reverseLinks[$target] -notcontains $nodeId) {
                        $graph.reverseLinks[$target] += $nodeId
                    }
                }
            }
        }
    }
    
    return $graph
}

function Get-UpstreamDependencies {
    <#
    .SYNOPSIS
        Gets all nodes that define/source this node.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Graph,
        
        [int]$MaxDepth = 10
    )
    
    $upstream = [System.Collections.Generic.List[PSCustomObject]]::new()
    $visited = @{}
    $queue = [System.Collections.Generic.Queue[PSCustomObject]]::new()
    $queue.Enqueue([PSCustomObject]@{ id = $NodeId; depth = 0; relation = 'self' })
    
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        
        if (-not $current.id) { continue }
        if ($visited.ContainsKey($current.id)) { continue }
        if ($current.depth -gt $MaxDepth) { continue }
        
        $visited[$current.id] = $true
        
        if ($current.id -ne $NodeId) {
            $upstream.Add([PSCustomObject]@{
                nodeId   = $current.id
                depth    = $current.depth
                relation = $current.relation
            })
        }
        
        # Parent chain
        if ($current.id -and $Graph.parents.ContainsKey($current.id)) {
            $parentId = $Graph.parents[$current.id]
            if ($parentId) {
                $queue.Enqueue([PSCustomObject]@{ id = $parentId; depth = $current.depth + 1; relation = 'parent' })
            }
        }
        
        # Prototype
        if ($current.id -and $Graph.instancePrototypes.ContainsKey($current.id)) {
            $protoId = $Graph.instancePrototypes[$current.id]
            if ($protoId) {
                $queue.Enqueue([PSCustomObject]@{ id = $protoId; depth = $current.depth + 1; relation = 'prototype' })
            }
        }
        
        # Nodes linking to this
        if ($current.id -and $Graph.reverseLinks.ContainsKey($current.id)) {
            foreach ($linkerId in $Graph.reverseLinks[$current.id]) {
                if ($linkerId) {
                    $queue.Enqueue([PSCustomObject]@{ id = $linkerId; depth = $current.depth + 1; relation = 'linked_from' })
                }
            }
        }
    }
    
    return $upstream | Sort-Object depth
}

function Get-DownstreamDependents {
    <#
    .SYNOPSIS
        Gets all nodes that depend on/use this node.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Graph,
        
        [int]$MaxDepth = 10
    )
    
    $downstream = [System.Collections.Generic.List[PSCustomObject]]::new()
    $visited = @{}
    $queue = [System.Collections.Generic.Queue[PSCustomObject]]::new()
    $queue.Enqueue([PSCustomObject]@{ id = $NodeId; depth = 0; relation = 'self' })
    
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        
        if (-not $current.id) { continue }
        if ($visited.ContainsKey($current.id)) { continue }
        if ($current.depth -gt $MaxDepth) { continue }
        
        $visited[$current.id] = $true
        
        if ($current.id -ne $NodeId) {
            $downstream.Add([PSCustomObject]@{
                nodeId   = $current.id
                depth    = $current.depth
                relation = $current.relation
            })
        }
        
        # Children
        if ($current.id -and $Graph.children.ContainsKey($current.id)) {
            foreach ($childId in $Graph.children[$current.id]) {
                if ($childId) {
                    $queue.Enqueue([PSCustomObject]@{ id = $childId; depth = $current.depth + 1; relation = 'child' })
                }
            }
        }
        
        # Instances (for prototypes)
        if ($current.id -and $Graph.prototypeInstances.ContainsKey($current.id)) {
            foreach ($instanceId in $Graph.prototypeInstances[$current.id]) {
                if ($instanceId) {
                    $queue.Enqueue([PSCustomObject]@{ id = $instanceId; depth = $current.depth + 1; relation = 'instance' })
                }
            }
        }
        
        # Twins
        if ($current.id -and $Graph.twins.ContainsKey($current.id)) {
            foreach ($twinId in $Graph.twins[$current.id]) {
                if ($twinId) {
                    $queue.Enqueue([PSCustomObject]@{ id = $twinId; depth = $current.depth + 1; relation = 'twin' })
                }
            }
        }
        
        # Nodes this links to
        if ($current.id -and $Graph.links.ContainsKey($current.id)) {
            foreach ($linkedId in $Graph.links[$current.id]) {
                if ($linkedId) {
                    $queue.Enqueue([PSCustomObject]@{ id = $linkedId; depth = $current.depth + 1; relation = 'links_to' })
                }
            }
        }
    }
    
    return $downstream | Sort-Object depth
}

function Get-NodeCriticality {
    <#
    .SYNOPSIS
        Computes criticality weight for a node.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Node
    )
    
    $nodeType = $Node.nodeType
    if ($Script:CriticalityWeights.ContainsKey($nodeType)) {
        return $Script:CriticalityWeights[$nodeType]
    }
    return $Script:CriticalityWeights['Default']
}

function Get-ChangeSeverity {
    <#
    .SYNOPSIS
        Computes severity weight for a change type.
    #>
    param([string]$ChangeType)
    
    if ($Script:SeverityWeights.ContainsKey($ChangeType)) {
        return $Script:SeverityWeights[$ChangeType]
    }
    return 0.5
}

function Compute-RiskScore {
    <#
    .SYNOPSIS
        Computes risk score for a node based on dependencies and criticality.
    
    .DESCRIPTION
        Risk = f(dependentCount, nodeCriticality, changeSeverity)
        Higher score = higher risk of impact from changes
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Node,
        
        [Parameter(Mandatory = $false)]
        [array]$Downstream = @(),
        
        [string]$ChangeType = $null
    )
    
    # Handle null/empty downstream
    if (-not $Downstream) { $Downstream = @() }
    
    # Base criticality
    $criticality = Get-NodeCriticality -Node $Node
    
    # Dependent count factor (log scale to handle large numbers)
    $dependentCount = $Downstream.Count
    $dependentFactor = if ($dependentCount -gt 0) {
        [Math]::Min(1.0, [Math]::Log10($dependentCount + 1) / 2)
    } else { 0 }
    
    # Direct dependent weight (depth 1 counts more)
    $directDependents = ($Downstream | Where-Object { $_.depth -eq 1 }).Count
    $directFactor = if ($directDependents -gt 0) {
        [Math]::Min(0.5, $directDependents / 10)
    } else { 0 }
    
    # Change severity (if provided)
    $severityFactor = if ($ChangeType) {
        Get-ChangeSeverity -ChangeType $ChangeType
    } else { 0.5 }
    
    # Combined risk score (0..1)
    $rawScore = ($criticality * 0.3) + ($dependentFactor * 0.3) + ($directFactor * 0.2) + ($severityFactor * 0.2)
    $normalizedScore = [Math]::Min(1.0, $rawScore)
    
    return [Math]::Round($normalizedScore, 2)
}

function Get-NodeImpact {
    <#
    .SYNOPSIS
        Main entry point for impact analysis.
    
    .DESCRIPTION
        Computes complete impact analysis for a node including:
        - Upstream dependencies
        - Downstream dependents
        - Risk score
        - Summary statistics
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [array]$Nodes,
        
        [int]$MaxDepth = 5,
        
        [string]$ChangeType = $null
    )
    
    # Build graph if not already built
    $graph = Build-DependencyGraph -Nodes $Nodes
    
    # Check node exists
    if (-not $graph.nodes.ContainsKey($NodeId)) {
        return $null
    }
    
    $node = $graph.nodes[$NodeId]
    
    # Get dependencies
    $upstream = Get-UpstreamDependencies -NodeId $NodeId -Graph $graph -MaxDepth $MaxDepth
    $downstream = Get-DownstreamDependents -NodeId $NodeId -Graph $graph -MaxDepth $MaxDepth
    
    # Compute risk
    $riskScore = Compute-RiskScore -Node $node -Downstream $downstream -ChangeType $ChangeType
    
    # Build impact summary
    $impactSummary = [PSCustomObject]@{
        nodeId              = $NodeId
        nodeName            = $node.name
        nodeType            = $node.nodeType
        path                = $node.path
        upstreamCount       = $upstream.Count
        downstreamCount     = $downstream.Count
        directDependents    = ($downstream | Where-Object { $_.depth -eq 1 }).Count
        transitiveDependents = ($downstream | Where-Object { $_.depth -gt 1 }).Count
        maxDepth            = if ($downstream.Count -gt 0) { ($downstream | Measure-Object -Property depth -Maximum).Maximum } else { 0 }
        riskScore           = $riskScore
        riskLevel           = Get-RiskLevel -Score $riskScore
        upstream            = $upstream | Select-Object -First 20
        downstream          = $downstream | Select-Object -First 50
        relatedTypes        = ($downstream | Group-Object { $graph.nodes[$_.nodeId].nodeType } | 
                              ForEach-Object { [PSCustomObject]@{ nodeType = $_.Name; count = $_.Count } })
    }
    
    return $impactSummary
}

function Get-RiskLevel {
    <#
    .SYNOPSIS
        Converts numeric risk score to level.
    #>
    param([double]$Score)
    
    if ($Score -ge 0.8) { return 'Critical' }
    if ($Score -ge 0.6) { return 'High' }
    if ($Score -ge 0.4) { return 'Medium' }
    if ($Score -ge 0.2) { return 'Low' }
    return 'Info'
}

function Get-ImpactForChanges {
    <#
    .SYNOPSIS
        Computes impact analysis for a set of changes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Changes,
        
        [Parameter(Mandatory = $true)]
        [array]$Nodes,
        
        [int]$MaxDepth = 3
    )
    
    $graph = Build-DependencyGraph -Nodes $Nodes
    $impacts = @()
    
    foreach ($change in $Changes) {
        $nodeId = $change.nodeId
        
        # Skip if node not in graph (removed nodes)
        if (-not $graph.nodes.ContainsKey($nodeId)) {
            continue
        }
        
        $impact = Get-NodeImpact -NodeId $nodeId -Nodes $Nodes -MaxDepth $MaxDepth -ChangeType $change.changeType
        if ($impact) {
            $impacts += $impact
        }
    }
    
    # Sort by risk score
    $impacts = $impacts | Sort-Object riskScore -Descending
    
    # Aggregate statistics
    $aggregate = [PSCustomObject]@{
        totalChangesAnalyzed = $impacts.Count
        totalDownstreamImpact = ($impacts | Measure-Object -Property downstreamCount -Sum).Sum
        maxRiskScore = if ($impacts.Count -gt 0) { ($impacts | Measure-Object -Property riskScore -Maximum).Maximum } else { 0 }
        criticalRiskCount = ($impacts | Where-Object { $_.riskLevel -eq 'Critical' }).Count
        highRiskCount = ($impacts | Where-Object { $_.riskLevel -eq 'High' }).Count
        topRiskNodes = $impacts | Select-Object nodeId, nodeName, riskScore, riskLevel, downstreamCount -First 10
        impacts = $impacts
    }
    
    return $aggregate
}

function Export-ImpactJson {
    <#
    .SYNOPSIS
        Exports impact analysis to JSON with deterministic ordering.
    #>
    param(
        [PSCustomObject]$ImpactReport,
        [string]$OutputPath,
        [switch]$Pretty
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Ensure deterministic ordering - sort dependents by depth, nodeType, path, name, nodeId
    $sortedReport = [PSCustomObject]@{
        nodeId              = $ImpactReport.nodeId
        nodeName            = $ImpactReport.nodeName
        nodeType            = $ImpactReport.nodeType
        path                = $ImpactReport.path
        upstreamCount       = $ImpactReport.upstreamCount
        downstreamCount     = $ImpactReport.downstreamCount
        directDependents    = $ImpactReport.directDependents
        transitiveDependents = $ImpactReport.transitiveDependents
        maxDepth            = $ImpactReport.maxDepth
        riskScore           = $ImpactReport.riskScore
        riskLevel           = $ImpactReport.riskLevel
        upstream            = $ImpactReport.upstream | Sort-Object depth, @{E={$_.nodeId}}
        downstream          = $ImpactReport.downstream | Sort-Object depth, @{E={$_.nodeId}}
        relatedTypes        = $ImpactReport.relatedTypes | Sort-Object nodeType
    }
    
    $json = if ($Pretty) {
        $sortedReport | ConvertTo-Json -Depth 10
    } else {
        $sortedReport | ConvertTo-Json -Depth 10 -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $OutputPath 'impact.json'), $json, $utf8NoBom)
    
    return (Join-Path $OutputPath 'impact.json')
}

function Get-ImpactForNode {
    <#
    .SYNOPSIS
        Gets impact analysis for a single node with deterministic output.
    .DESCRIPTION
        v0.5 API: Returns impact object with:
        - rootNodeId, depth
        - directDependents[] (depth 1)
        - transitiveDependents[] (depth 2..N) with path
        - upstreamReferences[]
        - riskScore 0..100 and breakdown
        - why[] strings listing top contributors
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeId,
        
        [Parameter(Mandatory = $true)]
        [array]$Nodes,
        
        [int]$MaxDepth = 5,
        
        [int]$MaxNodes = 100
    )
    
    $impact = Get-NodeImpact -NodeId $NodeId -Nodes $Nodes -MaxDepth $MaxDepth
    if (-not $impact) { return $null }
    
    # Build v0.5 format with deterministic ordering
    $directDeps = $impact.downstream | Where-Object { $_.depth -eq 1 } | 
        Sort-Object @{E={$_.nodeId}} |
        Select-Object -First $MaxNodes
    
    $transitiveDeps = $impact.downstream | Where-Object { $_.depth -gt 1 } | 
        Sort-Object depth, @{E={$_.nodeId}} |
        Select-Object -First $MaxNodes
    
    $upstreamRefs = $impact.upstream | 
        Sort-Object depth, @{E={$_.nodeId}} |
        Select-Object -First $MaxNodes
    
    # Build "why" breakdown
    $why = @()
    if ($impact.directDependents -gt 0) {
        $why += "$($impact.directDependents) direct dependents"
    }
    if ($impact.transitiveDependents -gt 0) {
        $why += "$($impact.transitiveDependents) transitive dependents (depth 2+)"
    }
    if ($impact.nodeType -in @('Station', 'ToolPrototype', 'Root')) {
        $why += "High-criticality node type: $($impact.nodeType)"
    }
    if ($impact.riskLevel -in @('Critical', 'High')) {
        $why += "Risk level: $($impact.riskLevel)"
    }
    
    # Convert riskScore to 0..100
    $riskScore100 = [int]($impact.riskScore * 100)
    
    return [PSCustomObject]@{
        rootNodeId          = $impact.nodeId
        nodeName            = $impact.nodeName
        nodeType            = $impact.nodeType
        path                = $impact.path
        depth               = $impact.maxDepth
        directDependents    = @($directDeps)
        transitiveDependents = @($transitiveDeps)
        upstreamReferences  = @($upstreamRefs)
        riskScore           = $riskScore100
        riskLevel           = $impact.riskLevel
        breakdown           = [PSCustomObject]@{
            dependentCountWeight = [Math]::Round($impact.downstreamCount / 100, 2)
            nodeTypeWeight       = (Get-NodeCriticality -Node ([PSCustomObject]@{ nodeType = $impact.nodeType }))
            criticalLinkWeight   = if ($impact.nodeType -eq 'ToolPrototype') { 0.9 } else { 0.5 }
        }
        why                 = $why
        stats               = [PSCustomObject]@{
            upstreamCount       = $impact.upstreamCount
            downstreamCount     = $impact.downstreamCount
            directCount         = $impact.directDependents
            transitiveCount     = $impact.transitiveDependents
        }
    }
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Build-DependencyGraph',
        'Get-UpstreamDependencies',
        'Get-DownstreamDependents',
        'Get-NodeImpact',
        'Get-ImpactForNode',
        'Get-ImpactForChanges',
        'Compute-RiskScore',
        'Get-NodeCriticality',
        'Get-RiskLevel',
        'Export-ImpactJson'
    )
}
