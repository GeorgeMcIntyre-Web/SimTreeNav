# WorkSessionEngine.ps1
# Clusters diff events into logical "work sessions" based on temporal and spatial patterns
# v0.3: Deterministic session grouping with intent inference

<#
.SYNOPSIS
    Groups raw diff changes into logical work sessions.

.DESCRIPTION
    A WorkSession represents a coherent unit of work:
    - Temporally clustered (changes within time window)
    - Spatially localized (changes in related subtrees)
    - Thematically consistent (similar change types)

    Sessions enable:
    - Understanding "what work was done" not just "what changed"
    - Correlating changes to workflows/tasks
    - Identifying patterns for intent inference

.EXAMPLE
    $sessions = Group-ChangesIntoSessions -Changes $diff.changes -TimeWindowMinutes 30
#>

# Session configuration defaults
$Script:SessionConfig = @{
    TimeWindowMinutes     = 30      # Max gap between changes in same session
    MinChangesPerSession  = 2       # Minimum changes to form a session
    SubtreeDepth          = 2       # Depth for path grouping
    LocalityWeight        = 0.4     # Weight for spatial clustering
    TypePatternWeight     = 0.3     # Weight for change type patterns
    TimeProximityWeight   = 0.3     # Weight for temporal clustering
}

function Get-SubtreePath {
    <#
    .SYNOPSIS
        Extracts subtree path at specified depth.
    #>
    param(
        [string]$Path,
        [int]$Depth = 2
    )
    
    if (-not $Path) { return '/' }
    
    $parts = $Path -split '/' | Where-Object { $_ }
    if ($parts.Count -le $Depth) {
        return '/' + ($parts -join '/')
    }
    
    return '/' + ($parts[0..($Depth - 1)] -join '/')
}

function Get-ChangeFingerprint {
    <#
    .SYNOPSIS
        Creates a fingerprint for change pattern analysis.
    #>
    param([PSCustomObject]$Change)
    
    $subtree = Get-SubtreePath -Path $change.path -Depth 2
    
    [PSCustomObject]@{
        changeType = $Change.changeType
        nodeType   = $Change.nodeType
        subtree    = $subtree
    }
}

function Measure-SessionAffinity {
    <#
    .SYNOPSIS
        Measures how well a change fits into an existing session.
    #>
    param(
        [PSCustomObject]$Change,
        [PSCustomObject]$Session,
        [hashtable]$Config = $Script:SessionConfig
    )
    
    $score = 0.0
    
    # Temporal proximity (if timestamps available)
    if ($Change.timestamp -and $Session.endTime) {
        $timeDelta = [Math]::Abs(([DateTime]$Change.timestamp - [DateTime]$Session.endTime).TotalMinutes)
        if ($timeDelta -le $Config.TimeWindowMinutes) {
            $timeScore = 1.0 - ($timeDelta / $Config.TimeWindowMinutes)
            $score += $timeScore * $Config.TimeProximityWeight
        }
    }
    else {
        # Without timestamps, assume sequential ordering
        $score += 0.5 * $Config.TimeProximityWeight
    }
    
    # Spatial locality (subtree match)
    $changeSubtree = Get-SubtreePath -Path $Change.path -Depth $Config.SubtreeDepth
    if ($Session.subtrees -contains $changeSubtree) {
        $score += $Config.LocalityWeight
    }
    elseif ($Session.subtrees | Where-Object { $changeSubtree -like "$_*" -or $_ -like "$changeSubtree*" }) {
        $score += $Config.LocalityWeight * 0.5
    }
    
    # Change type pattern match
    if ($Session.changeTypes -contains $Change.changeType) {
        $score += $Config.TypePatternWeight
    }
    
    return $score
}

function New-WorkSession {
    <#
    .SYNOPSIS
        Creates a new work session object.
    #>
    param(
        [string]$SessionId,
        [PSCustomObject]$InitialChange
    )
    
    $subtree = Get-SubtreePath -Path $InitialChange.path -Depth 2
    $timestamp = if ($InitialChange.timestamp) { $InitialChange.timestamp } else { (Get-Date).ToUniversalTime().ToString('o') }
    
    [PSCustomObject]@{
        sessionId    = $SessionId
        startTime    = $timestamp
        endTime      = $timestamp
        changeCount  = 1
        subtrees     = @($subtree)
        changeTypes  = @($InitialChange.changeType)
        nodeTypes    = @($InitialChange.nodeType)
        changes      = @($InitialChange)
        topPaths     = @{}
        summary      = $null
        confidence   = 1.0
    }
}

function Add-ChangeToSession {
    <#
    .SYNOPSIS
        Adds a change to an existing session.
    #>
    param(
        [PSCustomObject]$Session,
        [PSCustomObject]$Change
    )
    
    $Session.changes += $Change
    $Session.changeCount++
    
    # Update time bounds
    if ($Change.timestamp) {
        if (-not $Session.endTime -or $Change.timestamp -gt $Session.endTime) {
            $Session.endTime = $Change.timestamp
        }
        if (-not $Session.startTime -or $Change.timestamp -lt $Session.startTime) {
            $Session.startTime = $Change.timestamp
        }
    }
    
    # Update subtrees
    $subtree = Get-SubtreePath -Path $Change.path -Depth 2
    if ($subtree -and $Session.subtrees -notcontains $subtree) {
        $Session.subtrees += $subtree
    }
    
    # Update change types
    if ($Change.changeType -and $Session.changeTypes -notcontains $Change.changeType) {
        $Session.changeTypes += $Change.changeType
    }
    
    # Update node types
    if ($Change.nodeType -and $Session.nodeTypes -notcontains $Change.nodeType) {
        $Session.nodeTypes += $Change.nodeType
    }
    
    # Update top paths
    $pathKey = Get-SubtreePath -Path $Change.path -Depth 3
    if (-not $Session.topPaths.ContainsKey($pathKey)) {
        $Session.topPaths[$pathKey] = 0
    }
    $Session.topPaths[$pathKey]++
    
    return $Session
}

function Complete-Session {
    <#
    .SYNOPSIS
        Finalizes a session with summary statistics.
    #>
    param([PSCustomObject]$Session)
    
    # Compute summary
    $byType = $Session.changes | Group-Object changeType | ForEach-Object {
        [PSCustomObject]@{ type = $_.Name; count = $_.Count }
    }
    
    $byNodeType = $Session.changes | Group-Object nodeType | ForEach-Object {
        [PSCustomObject]@{ nodeType = $_.Name; count = $_.Count }
    }
    
    # Sort top paths
    $sortedPaths = $Session.topPaths.GetEnumerator() | 
        Sort-Object Value -Descending | 
        Select-Object -First 5 |
        ForEach-Object { [PSCustomObject]@{ path = $_.Key; count = $_.Value } }
    
    $Session.summary = [PSCustomObject]@{
        totalChanges   = $Session.changeCount
        byChangeType   = $byType
        byNodeType     = $byNodeType
        topPaths       = $sortedPaths
        subtreeCount   = $Session.subtrees.Count
        duration       = if ($Session.startTime -and $Session.endTime) {
            ([DateTime]$Session.endTime - [DateTime]$Session.startTime).TotalMinutes
        } else { 0 }
    }
    
    # Compute confidence based on session coherence
    $typeConcentration = if ($byType.Count -gt 0) { 
        ($byType | Measure-Object -Property count -Maximum).Maximum / $Session.changeCount 
    } else { 0.5 }
    
    $spatialConcentration = if ($Session.subtrees.Count -gt 0) {
        1.0 / [Math]::Sqrt($Session.subtrees.Count)
    } else { 0.5 }
    
    $Session.confidence = [Math]::Round(($typeConcentration + $spatialConcentration) / 2, 2)
    
    return $Session
}

function Group-ChangesIntoSessions {
    <#
    .SYNOPSIS
        Main entry point for session grouping.
    
    .DESCRIPTION
        Groups changes into logical work sessions using:
        - Temporal clustering (time windows)
        - Spatial locality (subtree grouping)
        - Pattern matching (change type consistency)
    #>
    param(
        [Parameter(Mandatory = $false)]
        [array]$Changes = @(),
        
        [int]$TimeWindowMinutes = 30,
        
        [double]$AffinityThreshold = 0.3,
        
        [int]$MinChangesPerSession = 2
    )
    
    if (-not $Changes -or $Changes.Count -eq 0) {
        return @()
    }
    
    $config = $Script:SessionConfig.Clone()
    $config.TimeWindowMinutes = $TimeWindowMinutes
    $config.MinChangesPerSession = $MinChangesPerSession
    
    $sessions = @()
    $currentSession = $null
    $sessionCounter = 0
    
    # Process changes in order
    foreach ($change in $Changes) {
        # First change starts a new session
        if (-not $currentSession) {
            $sessionCounter++
            $currentSession = New-WorkSession -SessionId "session_$($sessionCounter.ToString('D3'))" -InitialChange $change
            continue
        }
        
        # Check affinity with current session
        $affinity = Measure-SessionAffinity -Change $change -Session $currentSession -Config $config
        
        if ($affinity -ge $AffinityThreshold) {
            # Add to current session
            $currentSession = Add-ChangeToSession -Session $currentSession -Change $change
        }
        else {
            # Complete current session and start new one
            if ($currentSession.changeCount -ge $config.MinChangesPerSession) {
                $sessions += Complete-Session -Session $currentSession
            }
            else {
                # Merge small session into previous if exists, or discard
                if ($sessions.Count -gt 0) {
                    foreach ($c in $currentSession.changes) {
                        $sessions[-1] = Add-ChangeToSession -Session $sessions[-1] -Change $c
                    }
                    $sessions[-1] = Complete-Session -Session $sessions[-1]
                }
            }
            
            $sessionCounter++
            $currentSession = New-WorkSession -SessionId "session_$($sessionCounter.ToString('D3'))" -InitialChange $change
        }
    }
    
    # Complete final session
    if ($currentSession -and $currentSession.changeCount -ge $config.MinChangesPerSession) {
        $sessions += Complete-Session -Session $currentSession
    }
    elseif ($currentSession -and $sessions.Count -gt 0) {
        # Merge into last session
        foreach ($c in $currentSession.changes) {
            $sessions[-1] = Add-ChangeToSession -Session $sessions[-1] -Change $c
        }
        $sessions[-1] = Complete-Session -Session $sessions[-1]
    }
    elseif ($currentSession) {
        # Keep even if small - it's the only session
        $sessions += Complete-Session -Session $currentSession
    }
    
    return $sessions
}

function Export-SessionsJson {
    <#
    .SYNOPSIS
        Exports sessions to JSON format.
    #>
    param(
        [array]$Sessions,
        [string]$OutputPath,
        [switch]$Pretty
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    # Create sessions without full change objects (for size)
    $exportSessions = $Sessions | ForEach-Object {
        [PSCustomObject]@{
            sessionId   = $_.sessionId
            startTime   = $_.startTime
            endTime     = $_.endTime
            changeCount = $_.changeCount
            subtrees    = $_.subtrees
            changeTypes = $_.changeTypes
            nodeTypes   = $_.nodeTypes
            summary     = $_.summary
            confidence  = $_.confidence
            changeIds   = $_.changes | ForEach-Object { $_.nodeId }
        }
    }
    
    $json = if ($Pretty) {
        $exportSessions | ConvertTo-Json -Depth 10
    } else {
        $exportSessions | ConvertTo-Json -Depth 10 -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $OutputPath 'sessions.json'), $json, $utf8NoBom)
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Group-ChangesIntoSessions',
        'New-WorkSession',
        'Add-ChangeToSession',
        'Complete-Session',
        'Measure-SessionAffinity',
        'Get-SubtreePath',
        'Export-SessionsJson'
    )
}
