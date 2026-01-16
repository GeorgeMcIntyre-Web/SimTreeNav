# AnomalyEngine.ps1
# Detects anomalous patterns in changes that might indicate problems
# v0.3: Monitoring mindset for quality gates

<#
.SYNOPSIS
    Flags unusual or risky change patterns.

.DESCRIPTION
    Anomaly detection for change monitoring:
    - Mass deletion spikes
    - Transform deltas beyond sane bounds
    - Naming convention violations
    - Frequent oscillation (back-and-forth)
    - Moves into unusual parents
    - Unexpected structure changes

    Severity levels: Info, Warn, Critical
    Configurable alert rules

.EXAMPLE
    $anomalies = Detect-Anomalies -Changes $diff.changes -Config $alertConfig
#>

# Default anomaly detection thresholds
$Script:AnomalyThresholds = @{
    # Mass deletion
    MassDeleteCount         = 10       # More than N deletions = alert
    MassDeleteRatio         = 0.2      # >20% of nodes deleted = alert
    
    # Transform bounds
    MaxPositionDelta_mm     = 10000    # >10m move = suspicious
    MaxRotationDelta_deg    = 180      # >180° rotation = suspicious
    
    # Oscillation (back-and-forth)
    OscillationWindow       = 5        # Last N snapshots to check
    OscillationThreshold    = 3        # Same node changed N times = alert
    
    # Structural
    UnusualParentThreshold  = 0.1      # <10% historical frequency = unusual
    
    # Naming
    NamingViolationRatio    = 0.3      # >30% naming violations = alert
}

# Alert severity levels
$Script:SeverityLevels = @{
    Info     = 0
    Warn     = 1
    Critical = 2
}

function New-Anomaly {
    <#
    .SYNOPSIS
        Creates an anomaly alert object.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,
        
        [Parameter(Mandatory = $true)]
        [string]$Description,
        
        [ValidateSet('Info', 'Warn', 'Critical')]
        [string]$Severity = 'Info',
        
        [array]$Evidence = @(),
        
        [hashtable]$Details = @{}
    )
    
    [PSCustomObject]@{
        type        = $Type
        description = $Description
        severity    = $Severity
        timestamp   = (Get-Date).ToUniversalTime().ToString('o')
        evidenceCount = $Evidence.Count
        evidence    = $Evidence | Select-Object -First 10
        details     = [PSCustomObject]$Details
    }
}

function Detect-MassDeletion {
    <#
    .SYNOPSIS
        Detects mass deletion anomaly.
    #>
    param(
        [array]$Changes,
        [int]$TotalNodes = 0,
        [hashtable]$Thresholds = $Script:AnomalyThresholds
    )
    
    $deletions = $Changes | Where-Object { $_.changeType -eq 'removed' }
    $deleteCount = $deletions.Count
    
    if ($deleteCount -eq 0) { return $null }
    
    # Check absolute count
    if ($deleteCount -ge $Thresholds.MassDeleteCount) {
        $severity = if ($deleteCount -ge $Thresholds.MassDeleteCount * 3) { 'Critical' }
                   elseif ($deleteCount -ge $Thresholds.MassDeleteCount * 2) { 'Warn' }
                   else { 'Info' }
        
        # Check if deletions are concentrated
        $subtrees = $deletions | ForEach-Object {
            $parts = $_.path -split '/' | Where-Object { $_ }
            if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" }
        } | Group-Object | Sort-Object Count -Descending
        
        $topSubtree = if ($subtrees) { $subtrees[0].Name } else { 'Various' }
        
        return New-Anomaly `
            -Type 'MassDeletion' `
            -Description "Mass deletion detected: $deleteCount nodes removed (concentrated in $topSubtree)" `
            -Severity $severity `
            -Evidence $deletions `
            -Details @{
                deleteCount = $deleteCount
                topSubtree = $topSubtree
                byNodeType = ($deletions | Group-Object nodeType | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ', '
            }
    }
    
    # Check ratio (if total nodes known)
    if ($TotalNodes -gt 0) {
        $ratio = $deleteCount / $TotalNodes
        if ($ratio -ge $Thresholds.MassDeleteRatio) {
            return New-Anomaly `
                -Type 'MassDeletionRatio' `
                -Description "High deletion ratio: $([Math]::Round($ratio * 100, 1))% of nodes deleted" `
                -Severity 'Critical' `
                -Evidence $deletions `
                -Details @{
                    deleteCount = $deleteCount
                    totalNodes = $TotalNodes
                    ratio = [Math]::Round($ratio, 3)
                }
        }
    }
    
    return $null
}

function Detect-ExtremTransforms {
    <#
    .SYNOPSIS
        Detects transform changes beyond reasonable bounds.
    #>
    param(
        [array]$Changes,
        [hashtable]$Thresholds = $Script:AnomalyThresholds
    )
    
    $transformChanges = $Changes | Where-Object { $_.changeType -eq 'transform_changed' }
    
    if ($transformChanges.Count -eq 0) { return $null }
    
    $extremeChanges = @()
    
    foreach ($change in $transformChanges) {
        $isExtreme = $false
        $reasons = @()
        
        # Check position delta if available
        if ($change.details -and $change.details.positionDelta) {
            $delta = $change.details.positionDelta
            if ($delta -gt $Thresholds.MaxPositionDelta_mm) {
                $isExtreme = $true
                $reasons += "Position delta: $delta mm"
            }
        }
        
        # Check rotation delta if available
        if ($change.details -and $change.details.rotationDelta) {
            $delta = $change.details.rotationDelta
            if ($delta -gt $Thresholds.MaxRotationDelta_deg) {
                $isExtreme = $true
                $reasons += "Rotation delta: $delta deg"
            }
        }
        
        if ($isExtreme) {
            $extremeChanges += [PSCustomObject]@{
                nodeId = $change.nodeId
                nodeName = $change.nodeName
                reasons = $reasons
            }
        }
    }
    
    if ($extremeChanges.Count -gt 0) {
        return New-Anomaly `
            -Type 'ExtremeTransform' `
            -Description "$($extremeChanges.Count) nodes moved/rotated beyond reasonable bounds" `
            -Severity 'Warn' `
            -Evidence $extremeChanges `
            -Details @{
                count = $extremeChanges.Count
                maxPositionThreshold = $Thresholds.MaxPositionDelta_mm
                maxRotationThreshold = $Thresholds.MaxRotationDelta_deg
            }
    }
    
    return $null
}

function Detect-NamingViolations {
    <#
    .SYNOPSIS
        Detects high rate of naming convention violations.
    #>
    param(
        [array]$Changes,
        [hashtable]$NamingRules = $null,
        [hashtable]$Thresholds = $Script:AnomalyThresholds
    )
    
    if (-not $NamingRules) {
        # Use default rules
        $NamingRules = @{
            Station       = '^[A-Z][A-Za-z0-9_]+$'
            Resource      = '^[A-Z][A-Za-z0-9_]+$'
            Operation     = '^[A-Za-z0-9_]+$'
        }
    }
    
    $addedOrRenamed = $Changes | Where-Object { $_.changeType -in @('added', 'renamed') }
    
    if ($addedOrRenamed.Count -eq 0) { return $null }
    
    $violations = @()
    foreach ($change in $addedOrRenamed) {
        $nodeType = $change.nodeType
        $name = $change.nodeName
        
        if ($NamingRules.ContainsKey($nodeType)) {
            $pattern = $NamingRules[$nodeType]
            if ($name -notmatch $pattern) {
                $violations += [PSCustomObject]@{
                    nodeId = $change.nodeId
                    name = $name
                    nodeType = $nodeType
                    pattern = $pattern
                }
            }
        }
    }
    
    $violationRatio = $violations.Count / $addedOrRenamed.Count
    
    if ($violationRatio -ge $Thresholds.NamingViolationRatio) {
        return New-Anomaly `
            -Type 'NamingViolations' `
            -Description "$($violations.Count) nodes ($([Math]::Round($violationRatio * 100, 1))%) violate naming conventions" `
            -Severity 'Warn' `
            -Evidence $violations `
            -Details @{
                violationCount = $violations.Count
                totalChecked = $addedOrRenamed.Count
                ratio = [Math]::Round($violationRatio, 3)
            }
    }
    
    return $null
}

function Detect-UnusualParentMoves {
    <#
    .SYNOPSIS
        Detects moves to unusual parent types.
    #>
    param(
        [array]$Changes,
        [hashtable]$ExpectedParents = $null
    )
    
    if (-not $ExpectedParents) {
        # Default expected parent types
        $ExpectedParents = @{
            Resource     = @('ResourceGroup', 'Station')
            ToolInstance = @('Resource', 'Robot')
            Operation    = @('OperationGroup', 'Station', 'CompoundOperation')
        }
    }
    
    $moves = $Changes | Where-Object { $_.changeType -eq 'moved' }
    
    if ($moves.Count -eq 0) { return $null }
    
    $unusual = @()
    foreach ($move in $moves) {
        $nodeType = $move.nodeType
        if ($ExpectedParents.ContainsKey($nodeType) -and $move.newParentType) {
            $expectedTypes = $ExpectedParents[$nodeType]
            if ($move.newParentType -notin $expectedTypes) {
                $unusual += [PSCustomObject]@{
                    nodeId = $move.nodeId
                    nodeName = $move.nodeName
                    nodeType = $nodeType
                    newParentType = $move.newParentType
                    expectedTypes = $expectedTypes -join ', '
                }
            }
        }
    }
    
    if ($unusual.Count -gt 0) {
        return New-Anomaly `
            -Type 'UnusualParentMove' `
            -Description "$($unusual.Count) nodes moved to unexpected parent types" `
            -Severity 'Info' `
            -Evidence $unusual `
            -Details @{
                count = $unusual.Count
            }
    }
    
    return $null
}

function Detect-RapidChurn {
    <#
    .SYNOPSIS
        Detects nodes being changed repeatedly (oscillation).
    #>
    param(
        [array]$Changes,
        [array]$HistoricalNodeIds = @(),
        [int]$ChurnThreshold = 3
    )
    
    # Count how many times each node changed in current batch
    $changeCounts = @{}
    foreach ($change in $Changes) {
        $nodeId = $change.nodeId
        if (-not $changeCounts.ContainsKey($nodeId)) {
            $changeCounts[$nodeId] = 0
        }
        $changeCounts[$nodeId]++
    }
    
    # Also count historical occurrences
    foreach ($nodeId in $HistoricalNodeIds) {
        if (-not $changeCounts.ContainsKey($nodeId)) {
            $changeCounts[$nodeId] = 0
        }
        $changeCounts[$nodeId]++
    }
    
    # Find churned nodes
    $churned = $changeCounts.GetEnumerator() | Where-Object { $_.Value -ge $ChurnThreshold }
    
    if ($churned.Count -gt 0) {
        $evidence = $churned | ForEach-Object {
            [PSCustomObject]@{
                nodeId = $_.Key
                changeCount = $_.Value
            }
        }
        
        return New-Anomaly `
            -Type 'RapidChurn' `
            -Description "$($churned.Count) nodes changed $ChurnThreshold+ times - possible oscillation" `
            -Severity 'Warn' `
            -Evidence $evidence `
            -Details @{
                churnedCount = $churned.Count
                threshold = $ChurnThreshold
            }
    }
    
    return $null
}

function Detect-Anomalies {
    <#
    .SYNOPSIS
        Main entry point for anomaly detection.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [array]$Changes = @(),
        
        [int]$TotalNodes = 0,
        
        [array]$HistoricalNodeIds = @(),
        
        [hashtable]$Thresholds = $Script:AnomalyThresholds,
        
        [hashtable]$NamingRules = $null
    )
    
    if (-not $Changes) { $Changes = @() }
    
    $anomalies = @()
    
    # Run all detectors
    $massDeletion = Detect-MassDeletion -Changes $Changes -TotalNodes $TotalNodes -Thresholds $Thresholds
    if ($massDeletion) { $anomalies += $massDeletion }
    
    $extremeTransforms = Detect-ExtremTransforms -Changes $Changes -Thresholds $Thresholds
    if ($extremeTransforms) { $anomalies += $extremeTransforms }
    
    $namingViolations = Detect-NamingViolations -Changes $Changes -NamingRules $NamingRules -Thresholds $Thresholds
    if ($namingViolations) { $anomalies += $namingViolations }
    
    $unusualMoves = Detect-UnusualParentMoves -Changes $Changes
    if ($unusualMoves) { $anomalies += $unusualMoves }
    
    $churn = Detect-RapidChurn -Changes $Changes -HistoricalNodeIds $HistoricalNodeIds
    if ($churn) { $anomalies += $churn }
    
    # Sort by severity
    $severityOrder = @{ 'Critical' = 0; 'Warn' = 1; 'Info' = 2 }
    $sortedAnomalies = $anomalies | Sort-Object { $severityOrder[$_.severity] }
    
    # Build report
    [PSCustomObject]@{
        timestamp           = (Get-Date).ToUniversalTime().ToString('o')
        totalAnomalies      = $anomalies.Count
        criticalCount       = ($anomalies | Where-Object { $_.severity -eq 'Critical' }).Count
        warnCount           = ($anomalies | Where-Object { $_.severity -eq 'Warn' }).Count
        infoCount           = ($anomalies | Where-Object { $_.severity -eq 'Info' }).Count
        hasBlockingIssues   = ($anomalies | Where-Object { $_.severity -eq 'Critical' }).Count -gt 0
        anomalies           = $sortedAnomalies
    }
}

function Export-AnomaliesJson {
    <#
    .SYNOPSIS
        Exports anomalies to JSON.
    #>
    param(
        [PSCustomObject]$Report,
        [string]$OutputPath,
        [switch]$Pretty
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $json = if ($Pretty) {
        $Report | ConvertTo-Json -Depth 10
    } else {
        $Report | ConvertTo-Json -Depth 10 -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $OutputPath 'anomalies.json'), $json, $utf8NoBom)
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'New-Anomaly',
        'Detect-MassDeletion',
        'Detect-ExtremTransforms',
        'Detect-NamingViolations',
        'Detect-UnusualParentMoves',
        'Detect-RapidChurn',
        'Detect-Anomalies',
        'Export-AnomaliesJson'
    )
}
