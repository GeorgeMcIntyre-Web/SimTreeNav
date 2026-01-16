# DriftEngine.ps1
# Measures divergence between canonical definitions and operational data
# v0.3: Drift detection with configurable tolerances

<#
.SYNOPSIS
    Detects drift between canonical definitions (MFG/panel) and operational data.

.DESCRIPTION
    Drift occurs when operational data (locations, operations) diverges from
    its canonical definitions (MFG entities, panel data). This module:
    
    - Measures position delta (mm) between pairs
    - Measures rotation delta (degrees)
    - Tracks metadata/attribute differences
    - Computes drift scores with configurable tolerances
    - Tracks drift over time (trend analysis)

    Use cases:
    - Quality monitoring (is the study still within spec?)
    - Identifying stale/outdated configurations
    - Detecting unintentional modifications

.EXAMPLE
    $drift = Measure-Drift -Nodes $nodes -Tolerances $tolerances
#>

# Default drift tolerances
$Script:DriftTolerances = @{
    position_mm     = 0.1      # 0.1mm position tolerance
    rotation_deg    = 0.01     # 0.01 degree rotation tolerance
    attribute_count = 0        # Zero attribute drift allowed by default
}

# Node type pairs that can drift from each other
$Script:DriftPairs = @{
    'MfgEntity'   = @('Operation', 'Location')
    'PanelEntity' = @('Operation', 'Location')
    'ToolPrototype' = @('ToolInstance')
}

function Parse-Transform {
    <#
    .SYNOPSIS
        Parses transform string/object into position and rotation components.
    #>
    param($Transform)
    
    if (-not $Transform) {
        return @{ position = @(0, 0, 0); rotation = @(0, 0, 0) }
    }
    
    # Handle different transform formats
    if ($Transform -is [string]) {
        # Format: "x,y,z,rx,ry,rz" or similar
        $parts = $Transform -split '[,;\s]+' | Where-Object { $_ } | ForEach-Object { [double]$_ }
        if ($parts.Count -ge 6) {
            return @{
                position = @($parts[0], $parts[1], $parts[2])
                rotation = @($parts[3], $parts[4], $parts[5])
            }
        }
        if ($parts.Count -ge 3) {
            return @{
                position = @($parts[0], $parts[1], $parts[2])
                rotation = @(0, 0, 0)
            }
        }
    }
    
    if ($Transform -is [hashtable] -or $Transform.PSObject) {
        $pos = if ($Transform.position) { $Transform.position } else { @(0, 0, 0) }
        $rot = if ($Transform.rotation) { $Transform.rotation } else { @(0, 0, 0) }
        return @{ position = $pos; rotation = $rot }
    }
    
    return @{ position = @(0, 0, 0); rotation = @(0, 0, 0) }
}

function Measure-PositionDelta {
    <#
    .SYNOPSIS
        Computes Euclidean distance between two positions.
    #>
    param(
        [array]$Position1,
        [array]$Position2
    )
    
    if (-not $Position1 -or -not $Position2) { return 0 }
    if ($Position1.Count -lt 3 -or $Position2.Count -lt 3) { return 0 }
    
    $dx = $Position1[0] - $Position2[0]
    $dy = $Position1[1] - $Position2[1]
    $dz = $Position1[2] - $Position2[2]
    
    return [Math]::Sqrt($dx * $dx + $dy * $dy + $dz * $dz)
}

function Measure-RotationDelta {
    <#
    .SYNOPSIS
        Computes maximum rotation difference across axes.
    #>
    param(
        [array]$Rotation1,
        [array]$Rotation2
    )
    
    if (-not $Rotation1 -or -not $Rotation2) { return 0 }
    if ($Rotation1.Count -lt 3 -or $Rotation2.Count -lt 3) { return 0 }
    
    $deltas = @(
        [Math]::Abs($Rotation1[0] - $Rotation2[0]),
        [Math]::Abs($Rotation1[1] - $Rotation2[1]),
        [Math]::Abs($Rotation1[2] - $Rotation2[2])
    )
    
    # Normalize to 0-180 range (handle wraparound)
    $normalizedDeltas = $deltas | ForEach-Object {
        $d = $_ % 360
        if ($d -gt 180) { 360 - $d } else { $d }
    }
    
    return ($normalizedDeltas | Measure-Object -Maximum).Maximum
}

function Measure-AttributeDelta {
    <#
    .SYNOPSIS
        Counts attribute differences between two nodes.
    #>
    param(
        [PSCustomObject]$Node1,
        [PSCustomObject]$Node2,
        [array]$IgnoreAttributes = @('nodeId', 'parentId', 'path', 'timestamp')
    )
    
    $attr1 = if ($Node1.attributes) { $Node1.attributes } else { @{} }
    $attr2 = if ($Node2.attributes) { $Node2.attributes } else { @{} }
    
    # Convert to hashtables if needed
    if ($attr1 -isnot [hashtable]) {
        $temp = @{}
        foreach ($prop in $attr1.PSObject.Properties) {
            if ($prop.Name -notin $IgnoreAttributes) {
                $temp[$prop.Name] = $prop.Value
            }
        }
        $attr1 = $temp
    }
    
    if ($attr2 -isnot [hashtable]) {
        $temp = @{}
        foreach ($prop in $attr2.PSObject.Properties) {
            if ($prop.Name -notin $IgnoreAttributes) {
                $temp[$prop.Name] = $prop.Value
            }
        }
        $attr2 = $temp
    }
    
    $allKeys = @($attr1.Keys) + @($attr2.Keys) | Select-Object -Unique
    $diffCount = 0
    $diffs = @()
    
    foreach ($key in $allKeys) {
        if ($key -in $IgnoreAttributes) { continue }
        
        $val1 = $attr1[$key]
        $val2 = $attr2[$key]
        
        if ($val1 -ne $val2) {
            $diffCount++
            $diffs += [PSCustomObject]@{
                attribute = $key
                value1 = $val1
                value2 = $val2
            }
        }
    }
    
    return [PSCustomObject]@{
        count = $diffCount
        diffs = $diffs
    }
}

function Find-DriftPairs {
    <#
    .SYNOPSIS
        Finds pairs of nodes that can drift from each other.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [array]$Nodes = @()
    )
    
    if (-not $Nodes) { return @() }
    
    $pairs = @()
    $nodesByType = @{}
    $nodesByPath = @{}
    $nodeById = @{}
    
    # Index nodes
    foreach ($node in $Nodes) {
        $nodeById[$node.nodeId] = $node
        
        $type = $node.nodeType
        if (-not $nodesByType.ContainsKey($type)) {
            $nodesByType[$type] = @()
        }
        $nodesByType[$type] += $node
        
        # Index by path for matching
        $nodesByPath[$node.path] = $node
    }
    
    # Find pairs based on links
    foreach ($node in $Nodes) {
        # Check prototype-instance links
        if ($node.links -and $node.links.prototypeId) {
            $protoId = $node.links.prototypeId
            if ($nodeById.ContainsKey($protoId)) {
                $pairs += [PSCustomObject]@{
                    sourceNode = $nodeById[$protoId]
                    targetNode = $node
                    relation = 'prototype_instance'
                }
            }
        }
        
        # Check twin links
        if ($node.links -and $node.links.twinId) {
            $twinId = $node.links.twinId
            if ($nodeById.ContainsKey($twinId)) {
                $pairs += [PSCustomObject]@{
                    sourceNode = $nodeById[$twinId]
                    targetNode = $node
                    relation = 'twin'
                }
            }
        }
        
        # Check MFG/Panel entity links
        if ($node.links -and $node.links.mfgEntityId) {
            $mfgId = $node.links.mfgEntityId
            if ($nodeById.ContainsKey($mfgId)) {
                $pairs += [PSCustomObject]@{
                    sourceNode = $nodeById[$mfgId]
                    targetNode = $node
                    relation = 'mfg_operation'
                }
            }
        }
    }
    
    return $pairs
}

function Measure-PairDrift {
    <#
    .SYNOPSIS
        Measures drift between a pair of related nodes.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SourceNode,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$TargetNode,
        
        [string]$Relation = 'unknown',
        
        [hashtable]$Tolerances = $Script:DriftTolerances
    )
    
    # Parse transforms
    $sourceTransform = Parse-Transform -Transform $SourceNode.transform
    $targetTransform = Parse-Transform -Transform $TargetNode.transform
    
    # Measure deltas
    $positionDelta = Measure-PositionDelta -Position1 $sourceTransform.position -Position2 $targetTransform.position
    $rotationDelta = Measure-RotationDelta -Rotation1 $sourceTransform.rotation -Rotation2 $targetTransform.rotation
    $attributeDelta = Measure-AttributeDelta -Node1 $SourceNode -Node2 $TargetNode
    
    # Check against tolerances
    $positionDrift = $positionDelta -gt $Tolerances.position_mm
    $rotationDrift = $rotationDelta -gt $Tolerances.rotation_deg
    $attributeDrift = $attributeDelta.count -gt $Tolerances.attribute_count
    
    $hasDrift = $positionDrift -or $rotationDrift -or $attributeDrift
    
    # Compute drift severity (0..1)
    $severityFactors = @()
    if ($Tolerances.position_mm -gt 0) {
        $severityFactors += [Math]::Min(1.0, $positionDelta / ($Tolerances.position_mm * 10))
    }
    if ($Tolerances.rotation_deg -gt 0) {
        $severityFactors += [Math]::Min(1.0, $rotationDelta / ($Tolerances.rotation_deg * 100))
    }
    $severity = if ($severityFactors.Count -gt 0) {
        [Math]::Round(($severityFactors | Measure-Object -Average).Average, 3)
    } else { 0 }
    
    return [PSCustomObject]@{
        sourceNodeId    = $SourceNode.nodeId
        sourceName      = $SourceNode.name
        sourceType      = $SourceNode.nodeType
        targetNodeId    = $TargetNode.nodeId
        targetName      = $TargetNode.name
        targetType      = $TargetNode.nodeType
        relation        = $Relation
        positionDelta_mm = [Math]::Round($positionDelta, 4)
        rotationDelta_deg = [Math]::Round($rotationDelta, 4)
        attributeDeltaCount = $attributeDelta.count
        attributeDiffs  = $attributeDelta.diffs
        hasDrift        = $hasDrift
        positionDrift   = $positionDrift
        rotationDrift   = $rotationDrift
        attributeDrift  = $attributeDrift
        severity        = $severity
    }
}

function Measure-Drift {
    <#
    .SYNOPSIS
        Main entry point for drift analysis.
    
    .DESCRIPTION
        Analyzes all drift pairs in the node set and returns a comprehensive report.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [array]$Nodes = @(),
        
        [hashtable]$Tolerances = $Script:DriftTolerances
    )
    
    # Handle null/empty nodes
    if (-not $Nodes) { $Nodes = @() }
    
    # Find all drift pairs
    $pairs = Find-DriftPairs -Nodes $Nodes
    
    # Measure drift for each pair
    $driftMeasurements = @()
    foreach ($pair in $pairs) {
        $measurement = Measure-PairDrift `
            -SourceNode $pair.sourceNode `
            -TargetNode $pair.targetNode `
            -Relation $pair.relation `
            -Tolerances $Tolerances
        
        $driftMeasurements += $measurement
    }
    
    # Summary statistics
    $driftedPairs = $driftMeasurements | Where-Object { $_.hasDrift }
    $positionDrifted = $driftMeasurements | Where-Object { $_.positionDrift }
    $rotationDrifted = $driftMeasurements | Where-Object { $_.rotationDrift }
    $attributeDrifted = $driftMeasurements | Where-Object { $_.attributeDrift }
    
    # Top drifted by severity
    $topDrifted = $driftedPairs | Sort-Object severity -Descending | Select-Object -First 10
    
    $report = [PSCustomObject]@{
        timestamp         = (Get-Date).ToUniversalTime().ToString('o')
        totalPairs        = $pairs.Count
        driftedPairs      = $driftedPairs.Count
        positionDrifted   = $positionDrifted.Count
        rotationDrifted   = $rotationDrifted.Count
        attributeDrifted  = $attributeDrifted.Count
        driftRate         = if ($pairs.Count -gt 0) { [Math]::Round($driftedPairs.Count / $pairs.Count, 3) } else { 0 }
        avgPositionDelta  = if ($driftMeasurements.Count -gt 0) { 
            [Math]::Round(($driftMeasurements | Measure-Object -Property positionDelta_mm -Average).Average, 4) 
        } else { 0 }
        maxPositionDelta  = if ($driftMeasurements.Count -gt 0) { 
            [Math]::Round(($driftMeasurements | Measure-Object -Property positionDelta_mm -Maximum).Maximum, 4) 
        } else { 0 }
        avgRotationDelta  = if ($driftMeasurements.Count -gt 0) { 
            [Math]::Round(($driftMeasurements | Measure-Object -Property rotationDelta_deg -Average).Average, 4) 
        } else { 0 }
        maxRotationDelta  = if ($driftMeasurements.Count -gt 0) { 
            [Math]::Round(($driftMeasurements | Measure-Object -Property rotationDelta_deg -Maximum).Maximum, 4) 
        } else { 0 }
        tolerances        = $Tolerances
        topDrifted        = $topDrifted
        measurements      = $driftMeasurements
    }
    
    return $report
}

function Compare-DriftTrend {
    <#
    .SYNOPSIS
        Compares drift between two snapshots to detect trend.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$BaselineDrift,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$CurrentDrift
    )
    
    $trend = [PSCustomObject]@{
        baselineTimestamp  = $BaselineDrift.timestamp
        currentTimestamp   = $CurrentDrift.timestamp
        pairsDelta         = $CurrentDrift.totalPairs - $BaselineDrift.totalPairs
        driftedDelta       = $CurrentDrift.driftedPairs - $BaselineDrift.driftedPairs
        driftRateDelta     = [Math]::Round($CurrentDrift.driftRate - $BaselineDrift.driftRate, 3)
        positionDeltaChange = [Math]::Round($CurrentDrift.avgPositionDelta - $BaselineDrift.avgPositionDelta, 4)
        rotationDeltaChange = [Math]::Round($CurrentDrift.avgRotationDelta - $BaselineDrift.avgRotationDelta, 4)
        trendDirection     = if ($CurrentDrift.driftRate -gt $BaselineDrift.driftRate) { 'worsening' }
                            elseif ($CurrentDrift.driftRate -lt $BaselineDrift.driftRate) { 'improving' }
                            else { 'stable' }
        alertLevel         = if ($CurrentDrift.driftRate - $BaselineDrift.driftRate -gt 0.1) { 'Critical' }
                            elseif ($CurrentDrift.driftRate - $BaselineDrift.driftRate -gt 0.05) { 'Warn' }
                            else { 'Info' }
    }
    
    return $trend
}

function Export-DriftJson {
    <#
    .SYNOPSIS
        Exports drift report to JSON.
    #>
    param(
        [PSCustomObject]$DriftReport,
        [string]$OutputPath,
        [switch]$Pretty
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $json = if ($Pretty) {
        $DriftReport | ConvertTo-Json -Depth 10
    } else {
        $DriftReport | ConvertTo-Json -Depth 10 -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $OutputPath 'drift.json'), $json, $utf8NoBom)
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Measure-Drift',
        'Measure-PairDrift',
        'Find-DriftPairs',
        'Parse-Transform',
        'Measure-PositionDelta',
        'Measure-RotationDelta',
        'Measure-AttributeDelta',
        'Compare-DriftTrend',
        'Export-DriftJson'
    )
}
