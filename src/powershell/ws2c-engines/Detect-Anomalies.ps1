<#
.SYNOPSIS
    Detects anomalies in nodes and timeline data.
    
.DESCRIPTION
    Analyzes nodes and optional timeline data to detect:
    - Mass delete spikes
    - Transform outliers
    - Oscillation patterns (parent moves)
    - Naming violations
    - Unusual parent moves
    
.PARAMETER NodesPath
    Path to the nodes JSON file.
    
.PARAMETER TimelinePath
    Optional path to the timeline JSON file.
    
.PARAMETER OutPath
    Output path for the anomalies JSON file.
    
.EXAMPLE
    Detect-Anomalies -NodesPath nodes.json -TimelinePath timeline.json -OutPath anomalies.json
#>

function Detect-Anomalies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodesPath,
        
        [Parameter(Mandatory = $false)]
        [string]$TimelinePath,
        
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
    
    # Load timeline if provided
    $timeline = @()
    if ($TimelinePath -and (Test-Path $TimelinePath)) {
        $timeline = Get-Content $TimelinePath | ConvertFrom-Json
    }
    
    # Initialize anomalies list
    $anomalies = @()
    
    # 1. Detect naming violations
    $namingAnomalies = Detect-NamingViolations -Nodes $nodes
    $anomalies += $namingAnomalies
    
    # 2. Detect mass delete spikes (from timeline)
    if ($timeline.Count -gt 0) {
        $deleteAnomalies = Detect-MassDeleteSpikes -Timeline $timeline
        $anomalies += $deleteAnomalies
        
        # 3. Detect transform outliers
        $transformAnomalies = Detect-TransformOutliers -Timeline $timeline
        $anomalies += $transformAnomalies
        
        # 4. Detect oscillation patterns
        $oscillationAnomalies = Detect-OscillationPatterns -Timeline $timeline
        $anomalies += $oscillationAnomalies
        
        # 5. Detect unusual parent moves
        $moveAnomalies = Detect-UnusualMoves -Timeline $timeline
        $anomalies += $moveAnomalies
    }
    
    # Sort anomalies by severity (Critical > Warn > Info), then by title
    $severityOrder = @{ "Critical" = 0; "Warn" = 1; "Info" = 2 }
    $anomalies = $anomalies | Sort-Object @{Expression = { $severityOrder[$_.severity] }}, @{Expression = { $_.title }}
    
    # Build result
    $result = [ordered]@{
        detectedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        anomalyCount = $anomalies.Count
        bySeverity = @{
            Critical = ($anomalies | Where-Object { $_.severity -eq "Critical" }).Count
            Warn = ($anomalies | Where-Object { $_.severity -eq "Warn" }).Count
            Info = ($anomalies | Where-Object { $_.severity -eq "Info" }).Count
        }
        anomalies = $anomalies
    }
    
    # Ensure output directory exists
    $outDir = Split-Path $OutPath -Parent
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    
    # Write results
    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $OutPath -Encoding UTF8
    
    return $true
}

function Detect-NamingViolations {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Nodes
    )
    
    $anomalies = @()
    
    # Standard naming pattern: alphanumeric, underscores, hyphens, dots
    $validPattern = "^[A-Za-z0-9_\-\.]+$"
    
    foreach ($node in $Nodes) {
        $name = $node.name
        
        if (-not $name) {
            continue
        }
        
        # Check for invalid characters
        if ($name -notmatch $validPattern) {
            $anomalies += @{
                severity = "Warn"
                title = "Naming violation"
                summary = "Node '$name' contains invalid characters"
                evidence = @{
                    nodeId = $node.id
                    nodeName = $name
                    nodeType = $node.nodeType
                    pattern = $validPattern
                }
            }
        }
        
        # Check for very long names
        if ($name.Length -gt 100) {
            $anomalies += @{
                severity = "Info"
                title = "Naming violation - excessive length"
                summary = "Node name exceeds 100 characters ($($name.Length) chars)"
                evidence = @{
                    nodeId = $node.id
                    nodeName = $name.Substring(0, 50) + "..."
                    length = $name.Length
                }
            }
        }
        
        # Check for whitespace-only names
        if ($name.Trim().Length -eq 0) {
            $anomalies += @{
                severity = "Critical"
                title = "Naming violation - empty name"
                summary = "Node has whitespace-only name"
                evidence = @{
                    nodeId = $node.id
                    nodeType = $node.nodeType
                }
            }
        }
    }
    
    return $anomalies
}

function Detect-MassDeleteSpikes {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Timeline
    )
    
    $anomalies = @()
    
    # Filter delete events
    $deleteEvents = $Timeline | Where-Object { $_.changeType -eq "delete" }
    
    if ($deleteEvents.Count -lt 3) {
        return $anomalies
    }
    
    # Group deletes by time window (60 seconds)
    $windowSeconds = 60
    $deleteGroups = @{}
    
    foreach ($event in $deleteEvents) {
        try {
            $timestamp = [DateTime]::Parse($event.timestamp)
            $windowKey = $timestamp.ToString("yyyy-MM-dd HH:mm")
            
            if (-not $deleteGroups.ContainsKey($windowKey)) {
                $deleteGroups[$windowKey] = @()
            }
            $deleteGroups[$windowKey] += $event
        } catch {
            # Skip events with invalid timestamps
            continue
        }
    }
    
    # Find spikes (5+ deletes in one window)
    foreach ($windowKey in $deleteGroups.Keys) {
        $events = $deleteGroups[$windowKey]
        
        if ($events.Count -ge 5) {
            $severity = if ($events.Count -ge 20) { "Critical" } elseif ($events.Count -ge 10) { "Warn" } else { "Warn" }
            
            $nodeIds = @($events | ForEach-Object { $_.nodeId } | Select-Object -Unique)
            $changeIds = @($events | ForEach-Object { $_.changeId } | Select-Object -Unique)
            $users = @($events | ForEach-Object { $_.user } | Select-Object -Unique)
            
            $anomalies += @{
                severity = $severity
                title = "Mass delete spike"
                summary = "$($events.Count) nodes deleted in $windowKey by $($users -join ', ')"
                evidence = @{
                    nodeIds = $nodeIds
                    changeIds = $changeIds
                    users = $users
                    count = $events.Count
                    timeWindow = $windowKey
                }
            }
        }
    }
    
    return $anomalies
}

function Detect-TransformOutliers {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Timeline
    )
    
    $anomalies = @()
    
    # Filter transform events
    $transformEvents = $Timeline | Where-Object { $_.changeType -eq "transform" }
    
    foreach ($event in $transformEvents) {
        $details = $event.details
        
        if (-not $details) {
            continue
        }
        
        # Check translation values
        if ($details.translation) {
            $trans = $details.translation
            $maxTrans = 10000  # Threshold for "extreme" translation
            
            $x = if ($trans.x) { [Math]::Abs($trans.x) } else { 0 }
            $y = if ($trans.y) { [Math]::Abs($trans.y) } else { 0 }
            $z = if ($trans.z) { [Math]::Abs($trans.z) } else { 0 }
            
            if ($x -gt $maxTrans -or $y -gt $maxTrans -or $z -gt $maxTrans) {
                $anomalies += @{
                    severity = "Warn"
                    title = "Transform outlier - extreme translation"
                    summary = "Node moved to extreme position (x=$x, y=$y, z=$z)"
                    evidence = @{
                        nodeId = $event.nodeId
                        changeId = $event.changeId
                        translation = @{ x = $x; y = $y; z = $z }
                        threshold = $maxTrans
                        user = $event.user
                        timestamp = $event.timestamp
                    }
                }
            }
        }
    }
    
    return $anomalies
}

function Detect-OscillationPatterns {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Timeline
    )
    
    $anomalies = @()
    
    # Filter move events
    $moveEvents = $Timeline | Where-Object { $_.changeType -eq "move" }
    
    # Group by nodeId
    $nodeMovesMap = @{}
    foreach ($event in $moveEvents) {
        $nodeId = $event.nodeId
        if (-not $nodeMovesMap.ContainsKey($nodeId)) {
            $nodeMovesMap[$nodeId] = @()
        }
        $nodeMovesMap[$nodeId] += $event
    }
    
    # Check for oscillation (back and forth moves)
    foreach ($nodeId in $nodeMovesMap.Keys) {
        $moves = $nodeMovesMap[$nodeId] | Sort-Object { [DateTime]::Parse($_.timestamp) }
        
        if ($moves.Count -lt 3) {
            continue
        }
        
        # Check for A -> B -> A pattern
        $oscillations = 0
        $oscillationEvents = @()
        
        for ($i = 2; $i -lt $moves.Count; $i++) {
            $move1 = $moves[$i - 2]
            $move2 = $moves[$i - 1]
            $move3 = $moves[$i]
            
            # A -> B -> A pattern
            $oldParent1 = $move1.details.oldParentId
            $newParent1 = $move1.details.newParentId
            $oldParent3 = $move3.details.oldParentId
            $newParent3 = $move3.details.newParentId
            
            if ($newParent1 -eq $oldParent3 -and $newParent3 -eq $oldParent1) {
                $oscillations++
                $oscillationEvents += $move1.changeId
                $oscillationEvents += $move2.changeId
                $oscillationEvents += $move3.changeId
            }
        }
        
        if ($oscillations -ge 1) {
            $severity = if ($oscillations -ge 3) { "Critical" } else { "Warn" }
            
            $anomalies += @{
                severity = $severity
                title = "Oscillation pattern detected"
                summary = "Node '$nodeId' moved back and forth $oscillations time(s)"
                evidence = @{
                    nodeId = $nodeId
                    oscillationCount = $oscillations
                    changeIds = @($oscillationEvents | Select-Object -Unique)
                    moveCount = $moves.Count
                }
            }
        }
    }
    
    return $anomalies
}

function Detect-UnusualMoves {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Timeline
    )
    
    $anomalies = @()
    
    # Filter move events
    $moveEvents = $Timeline | Where-Object { $_.changeType -eq "move" }
    
    # Count moves per user
    $userMoves = @{}
    foreach ($event in $moveEvents) {
        $user = $event.user
        if (-not $user) {
            continue
        }
        if (-not $userMoves.ContainsKey($user)) {
            $userMoves[$user] = 0
        }
        $userMoves[$user]++
    }
    
    # Calculate average and std dev
    $counts = @($userMoves.Values)
    if ($counts.Count -lt 2) {
        return $anomalies
    }
    
    $avg = ($counts | Measure-Object -Average).Average
    $variance = ($counts | ForEach-Object { [Math]::Pow($_ - $avg, 2) } | Measure-Object -Average).Average
    $stdDev = [Math]::Sqrt($variance)
    
    # Flag users with move count > 2 std dev above average
    foreach ($user in $userMoves.Keys) {
        $count = $userMoves[$user]
        
        if ($count -gt ($avg + 2 * $stdDev) -and $count -gt 5) {
            $anomalies += @{
                severity = "Info"
                title = "Unusual move activity"
                summary = "User '$user' performed $count moves (average: $([Math]::Round($avg, 1)))"
                evidence = @{
                    user = $user
                    moveCount = $count
                    average = [Math]::Round($avg, 1)
                    stdDev = [Math]::Round($stdDev, 1)
                }
            }
        }
    }
    
    return $anomalies
}

# Export function for module use
Export-ModuleMember -Function Detect-Anomalies -ErrorAction SilentlyContinue
