# DemoStory.ps1
# SimTreeNav v0.4 Demo Story - Generates narrative timeline demos
# Creates presentation-ready bundles with talk-track documentation

<#
.SYNOPSIS
    Generates a narrative story timeline for demonstrations.

.DESCRIPTION
    Creates 6-10 snapshots showing realistic manufacturing data evolution:
    1. Baseline - Initial clean state
    2. Bulk Paste - Mass import of station data
    3. Rename Pass - Standardization renaming
    4. Retouch Session - Transform adjustments (drift)
    5. Station Restructure - Reorganization
    6. Prototype Swap - Tool prototype changes
    7. Anomaly Event - Mass delete spike
    8. Recovery - Partial restoration

    Generates:
    - Self-contained offline bundle
    - docs/DEMO-TALK-TRACK.md with speaker notes

.EXAMPLE
    .\DemoStory.ps1 -NodeCount 500 -OutDir ./bundles/demo_v04

.EXAMPLE
    .\DemoStory.ps1 -Anonymize -CreateZip -StoryName "Q4 Production Review"
#>

[CmdletBinding()]
param(
    [int]$NodeCount = 300,
    [string]$OutDir = './bundles/demo_story',
    [string]$StoryName = 'Manufacturing Evolution Story',
    [int]$Seed = 0,
    [switch]$Anonymize,
    [switch]$CreateZip,
    [switch]$NoOpen,
    [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# ============================================================================
# DETERMINISTIC SEEDING
# ============================================================================

# If Seed is provided (non-zero), seed the random number generator for deterministic output
$Script:DeterministicMode = $Seed -ne 0
$Script:DeterministicCounter = 0
$Script:DeterministicSeed = $Seed

if ($Script:DeterministicMode) {
    # Seed PowerShell's random number generator
    $null = Get-Random -SetSeed $Seed
}

function Get-DeterministicGuid {
    <#
    .SYNOPSIS
        Returns a deterministic pseudo-GUID when in deterministic mode.
    #>
    if (-not $Script:DeterministicMode) {
        return [guid]::NewGuid()
    }
    
    # Generate deterministic GUID based on seed and counter
    $Script:DeterministicCounter++
    $seedValue = $Script:DeterministicSeed
    $counterValue = $Script:DeterministicCounter
    $inputStr = "SEED-${seedValue}-${counterValue}"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($inputStr)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    
    # Convert first 32 hex chars to GUID format (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
    $hexString = [System.BitConverter]::ToString($hashBytes).Replace('-', '').Substring(0, 32).ToLower()
    $guidString = "$($hexString.Substring(0,8))-$($hexString.Substring(8,4))-$($hexString.Substring(12,4))-$($hexString.Substring(16,4))-$($hexString.Substring(20,12))"
    return [guid]::new($guidString)
}

function Get-DeterministicTimestamp {
    <#
    .SYNOPSIS
        Returns a deterministic timestamp when in deterministic mode.
    #>
    param([datetime]$BaseTime = (Get-Date '2025-01-01T00:00:00Z'))
    
    if (-not $Script:DeterministicMode) {
        return (Get-Date).ToUniversalTime()
    }
    
    # Return a fixed base time offset by counter (for ordering)
    $Script:DeterministicCounter++
    return $BaseTime.AddSeconds($Script:DeterministicCounter)
}

# ============================================================================
# IMPORTS
# ============================================================================

Write-Host "Loading modules..." -ForegroundColor Cyan
. "$scriptRoot\src\powershell\v02\core\NodeContract.ps1"
. "$scriptRoot\src\powershell\v02\core\IdentityResolver.ps1"
. "$scriptRoot\src\powershell\v02\diff\Compare-Snapshots.ps1"
. "$scriptRoot\src\powershell\v02\narrative\NarrativeEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\WorkSessionEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\IntentEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\ImpactEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\DriftEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\ComplianceEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\SimilarityEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\AnomalyEngine.ps1"
. "$scriptRoot\src\powershell\v02\analysis\ExplainEngine.ps1"
. "$scriptRoot\src\powershell\v02\export\ExportBundle.ps1"
. "$scriptRoot\src\powershell\v02\export\Anonymizer.ps1"

# ============================================================================
# STORY CONFIGURATION
# ============================================================================

$storyConfig = @{
    ProjectName    = 'PLANT_ALPHA'
    Stations       = @('Weld_Cell_A', 'Weld_Cell_B', 'Assembly_1', 'Assembly_2', 'Quality_Check', 'Final_Assembly')
    ToolTypes      = @('WeldGun', 'Gripper', 'Fixture', 'Clamp', 'Sensor', 'Camera', 'Torch', 'Nozzle')
    OperationTypes = @('Pick', 'Place', 'Weld', 'Move', 'Wait', 'Signal', 'Inspect', 'Rotate', 'Press')
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

function Show-StoryBanner {
    Write-Host ""
    Write-Host "  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "  ║                                                               ║" -ForegroundColor Magenta
    Write-Host "  ║   SimTreeNav v0.4 - Demo Story Generator                      ║" -ForegroundColor Magenta
    Write-Host "  ║   Narrative Timeline for Presentations                        ║" -ForegroundColor Magenta
    Write-Host "  ║                                                               ║" -ForegroundColor Magenta
    Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
}

function Write-StoryProgress {
    param([string]$Step, [string]$Message, [string]$Status = 'Info')
    
    $color = switch ($Status) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error'   { 'Red' }
        'Story'   { 'Magenta' }
        default   { 'Cyan' }
    }
    
    Write-Host "  [$Step] $Message" -ForegroundColor $color
}

function New-StoryNode {
    param(
        [string]$NodeId,
        [string]$Name,
        [string]$NodeType,
        [string]$ParentId = $null,
        [string]$Path = '/',
        [hashtable]$Attributes = @{},
        [hashtable]$Links = $null,
        [string]$Transform = $null
    )
    
    $externalId = "EXT-$((Get-DeterministicGuid).ToString().Substring(0,8).ToUpper())"
    
    [PSCustomObject]@{
        nodeId      = $NodeId
        name        = $Name
        nodeType    = $NodeType
        parentId    = $ParentId
        path        = $Path
        attributes  = [PSCustomObject]@{
            externalId = $externalId
            className  = "$NodeType`Class"
            niceName   = $Name
            typeId     = Get-Random -Minimum 1 -Maximum 200
        }
        links       = if ($Links) { [PSCustomObject]$Links } else { $null }
        transform   = if ($Transform) { $Transform } else { "$(Get-Random -Minimum -1000 -Maximum 1000),$(Get-Random -Minimum -1000 -Maximum 1000),$(Get-Random -Minimum 0 -Maximum 500),$(Get-Random -Minimum 0 -Maximum 360),$(Get-Random -Minimum 0 -Maximum 360),$(Get-Random -Minimum 0 -Maximum 360)" }
        fingerprints = [PSCustomObject]@{
            contentHash   = (Get-DeterministicGuid).ToString().Substring(0, 16)
            attributeHash = (Get-DeterministicGuid).ToString().Substring(0, 16)
            transformHash = (Get-DeterministicGuid).ToString().Substring(0, 16)
        }
        identity    = $null
        source      = [PSCustomObject]@{
            table       = "DF_$NodeType`_DATA"
            extractedAt = (Get-DeterministicTimestamp).ToString('o')
        }
    }
}

function New-BaselineDataset {
    param([int]$NodeCount, [hashtable]$Config)
    
    $nodes = @()
    $nodeIndex = 1
    
    # Create root
    $root = New-StoryNode -NodeId "N$($nodeIndex.ToString('D6'))" -Name $Config.ProjectName -NodeType 'Root' -Path "/$($Config.ProjectName)"
    $nodes += $root
    $nodeIndex++
    
    # Create tool prototypes
    $protoIds = @{}
    foreach ($toolType in $Config.ToolTypes) {
        $protoId = "N$($nodeIndex.ToString('D6'))"
        $proto = New-StoryNode `
            -NodeId $protoId `
            -Name "$($toolType)_Proto_Master" `
            -NodeType 'ToolPrototype' `
            -ParentId $root.nodeId `
            -Path "/$($Config.ProjectName)/Prototypes/$($toolType)_Proto_Master"
        $nodes += $proto
        $protoIds[$toolType] = $protoId
        $nodeIndex++
    }
    
    # Create stations with resources and operations
    foreach ($stationName in $Config.Stations) {
        if ($nodes.Count -ge $NodeCount) { break }
        
        # Station node
        $stationId = "N$($nodeIndex.ToString('D6'))"
        $station = New-StoryNode `
            -NodeId $stationId `
            -Name $stationName `
            -NodeType 'Station' `
            -ParentId $root.nodeId `
            -Path "/$($Config.ProjectName)/$stationName"
        $nodes += $station
        $nodeIndex++
        
        # Resource groups (2-4 per station)
        $rgCount = Get-Random -Minimum 2 -Maximum 5
        for ($rg = 1; $rg -le $rgCount; $rg++) {
            if ($nodes.Count -ge $NodeCount) { break }
            
            $rgId = "N$($nodeIndex.ToString('D6'))"
            $rgName = "RG_$($stationName)_$rg"
            $resourceGroup = New-StoryNode `
                -NodeId $rgId `
                -Name $rgName `
                -NodeType 'ResourceGroup' `
                -ParentId $stationId `
                -Path "/$($Config.ProjectName)/$stationName/$rgName"
            $nodes += $resourceGroup
            $nodeIndex++
            
            # Resources (robots, 1-3 per group)
            $robotCount = Get-Random -Minimum 1 -Maximum 4
            for ($r = 1; $r -le $robotCount; $r++) {
                if ($nodes.Count -ge $NodeCount) { break }
                
                $robotId = "N$($nodeIndex.ToString('D6'))"
                $robotName = "Robot_$($stationName.Substring(0, [Math]::Min(6, $stationName.Length)))_$rg`R$r"
                $robot = New-StoryNode `
                    -NodeId $robotId `
                    -Name $robotName `
                    -NodeType 'Resource' `
                    -ParentId $rgId `
                    -Path "/$($Config.ProjectName)/$stationName/$rgName/$robotName"
                $nodes += $robot
                $nodeIndex++
                
                # Tool instances on robot (1-3 each)
                $toolCount = Get-Random -Minimum 1 -Maximum 4
                for ($t = 1; $t -le $toolCount; $t++) {
                    if ($nodes.Count -ge $NodeCount) { break }
                    
                    $toolType = $Config.ToolTypes | Get-Random
                    $toolId = "N$($nodeIndex.ToString('D6'))"
                    $toolName = "$($toolType)_$($robotName)_$t"
                    $tool = New-StoryNode `
                        -NodeId $toolId `
                        -Name $toolName `
                        -NodeType 'ToolInstance' `
                        -ParentId $robotId `
                        -Path "/$($Config.ProjectName)/$stationName/$rgName/$robotName/$toolName" `
                        -Links @{ prototypeId = $protoIds[$toolType] }
                    $nodes += $tool
                    $nodeIndex++
                }
            }
        }
        
        # Operations (5-12 per station)
        $opCount = Get-Random -Minimum 5 -Maximum 13
        for ($op = 1; $op -le $opCount; $op++) {
            if ($nodes.Count -ge $NodeCount) { break }
            
            $opType = $Config.OperationTypes | Get-Random
            $opId = "N$($nodeIndex.ToString('D6'))"
            $opName = "Op_$($stationName.Substring(0, [Math]::Min(6, $stationName.Length)))_$($opType)_$op"
            $operation = New-StoryNode `
                -NodeId $opId `
                -Name $opName `
                -NodeType 'Operation' `
                -ParentId $stationId `
                -Path "/$($Config.ProjectName)/$stationName/Operations/$opName"
            $nodes += $operation
            $nodeIndex++
            
            # Locations per operation (2-5 each)
            $locCount = Get-Random -Minimum 2 -Maximum 6
            for ($loc = 1; $loc -le $locCount; $loc++) {
                if ($nodes.Count -ge $NodeCount) { break }
                
                $locId = "N$($nodeIndex.ToString('D6'))"
                $locName = "Loc_$($opName)_$loc"
                $location = New-StoryNode `
                    -NodeId $locId `
                    -Name $locName `
                    -NodeType 'Location' `
                    -ParentId $opId `
                    -Path "/$($Config.ProjectName)/$stationName/Operations/$opName/$locName"
                $nodes += $location
                $nodeIndex++
            }
        }
    }
    
    return $nodes
}

# ============================================================================
# STORY EVENT FUNCTIONS
# ============================================================================

function Apply-BulkPasteEvent {
    param([array]$Nodes, [hashtable]$Config)
    
    $mutated = $Nodes | ForEach-Object { $_.PSObject.Copy() }
    $newNodes = @()
    $nodeIndex = 700000
    
    # Add 15-25 new nodes simulating bulk paste from another station
    $bulkCount = Get-Random -Minimum 15 -Maximum 26
    $targetStation = $Config.Stations | Get-Random
    $stationNode = $mutated | Where-Object { $_.name -eq $targetStation } | Select-Object -First 1
    
    if (-not $stationNode) {
        return @($mutated) + @($newNodes)
    }
    
    for ($i = 1; $i -le $bulkCount; $i++) {
        $toolType = $Config.ToolTypes | Get-Random
        $nodeId = "N$($nodeIndex.ToString('D6'))"
        $newNode = New-StoryNode `
            -NodeId $nodeId `
            -Name "PASTED_$($toolType)_$i" `
            -NodeType 'ToolInstance' `
            -ParentId $stationNode.nodeId `
            -Path "/$($Config.ProjectName)/$targetStation/PASTED_$($toolType)_$i"
        $newNodes += $newNode
        $nodeIndex++
    }
    
    return @($mutated) + @($newNodes)
}

function Apply-RenamePassEvent {
    param([array]$Nodes)
    
    $mutated = @()
    $renameCount = [int]($Nodes.Count * 0.1)  # Rename 10%
    $indicesToRename = 0..($Nodes.Count - 1) | Get-Random -Count $renameCount
    
    for ($i = 0; $i -lt $Nodes.Count; $i++) {
        $node = $Nodes[$i].PSObject.Copy()
        if ($i -in $indicesToRename -and $node.nodeType -notin @('Root', 'Station')) {
            $node.name = "$($node.name)_STD"
        }
        $mutated += $node
    }
    
    return $mutated
}

function Apply-RetouchSessionEvent {
    param([array]$Nodes)
    
    $mutated = @()
    $transformCount = [int]($Nodes.Count * 0.15)  # Transform 15%
    $indicesToTransform = 0..($Nodes.Count - 1) | Get-Random -Count $transformCount
    
    for ($i = 0; $i -lt $Nodes.Count; $i++) {
        $node = $Nodes[$i].PSObject.Copy()
        if ($i -in $indicesToTransform -and $node.transform) {
            # Apply small drift (simulate retouch)
            $parts = $node.transform -split ','
            if ($parts.Count -eq 6) {
                $parts[0] = [string]([int]$parts[0] + (Get-Random -Minimum -50 -Maximum 51))
                $parts[1] = [string]([int]$parts[1] + (Get-Random -Minimum -50 -Maximum 51))
                $parts[2] = [string]([int]$parts[2] + (Get-Random -Minimum -20 -Maximum 21))
                $node.transform = $parts -join ','
            }
        }
        $mutated += $node
    }
    
    return $mutated
}

function Apply-StationRestructureEvent {
    param([array]$Nodes, [hashtable]$Config)
    
    $mutated = @()
    
    foreach ($node in $Nodes) {
        $copy = $node.PSObject.Copy()
        
        # Move some ResourceGroups to different stations
        if ($node.nodeType -eq 'ResourceGroup' -and (Get-Random -Minimum 0 -Maximum 10) -lt 2) {
            $newParent = $Nodes | Where-Object { $_.nodeType -eq 'Station' -and $_.nodeId -ne $node.parentId } | Get-Random
            if ($newParent) {
                $copy.parentId = $newParent.nodeId
                $copy.path = $copy.path -replace '/[^/]+/RG_', "/$($newParent.name)/RG_"
            }
        }
        
        $mutated += $copy
    }
    
    return $mutated
}

function Apply-PrototypeSwapEvent {
    param([array]$Nodes, [hashtable]$Config)
    
    $mutated = @()
    $protoIds = @{}
    
    # Find all prototypes
    $prototypes = $Nodes | Where-Object { $_.nodeType -eq 'ToolPrototype' }
    foreach ($proto in $prototypes) {
        $typeName = $proto.name -replace '_Proto_Master', ''
        $protoIds[$typeName] = $proto.nodeId
    }
    
    foreach ($node in $Nodes) {
        $copy = $node.PSObject.Copy()
        
        # Swap some prototype links
        if ($node.nodeType -eq 'ToolInstance' -and $node.links.prototypeId -and (Get-Random -Minimum 0 -Maximum 10) -lt 2) {
            $newProtoType = $Config.ToolTypes | Get-Random
            if ($protoIds.ContainsKey($newProtoType)) {
                $copy.links = [PSCustomObject]@{ prototypeId = $protoIds[$newProtoType] }
            }
        }
        
        $mutated += $copy
    }
    
    return $mutated
}

function Apply-AnomalyEvent {
    param([array]$Nodes)
    
    # Delete 10-20% of nodes (mass delete spike)
    $deleteRate = Get-Random -Minimum 10 -Maximum 21
    $deleteCount = [int]($Nodes.Count * $deleteRate / 100)
    $indicesToKeep = 0..($Nodes.Count - 1) | Where-Object { $_ -notin (0..($Nodes.Count - 1) | Get-Random -Count $deleteCount) }
    
    # Always keep Root and Stations
    $protected = @()
    for ($i = 0; $i -lt $Nodes.Count; $i++) {
        if ($Nodes[$i].nodeType -in @('Root', 'Station', 'ToolPrototype')) {
            $protected += $i
        }
    }
    
    $finalIndices = ($indicesToKeep + $protected) | Sort-Object -Unique
    
    return $Nodes[$finalIndices]
}

function Apply-RecoveryEvent {
    param([array]$CurrentNodes, [array]$BaselineNodes)
    
    # Restore 30-50% of deleted nodes
    $currentIds = $CurrentNodes.nodeId
    $deletedNodes = $BaselineNodes | Where-Object { $_.nodeId -notin $currentIds }
    
    $restoreCount = [int]($deletedNodes.Count * (Get-Random -Minimum 30 -Maximum 51) / 100)
    $toRestore = $deletedNodes | Get-Random -Count ([Math]::Min($restoreCount, $deletedNodes.Count))
    
    return @($CurrentNodes) + @($toRestore)
}

# ============================================================================
# TALK-TRACK GENERATION
# ============================================================================

function New-TalkTrackMarkdown {
    param(
        [string]$StoryName,
        [array]$Timeline,
        [PSCustomObject]$FinalStats
    )
    
    $genDate = if ($Script:DeterministicMode) { '2025-01-01 09:00' } else { Get-Date -Format 'yyyy-MM-dd HH:mm' }
    $md = @"
# SimTreeNav Demo Talk Track

## $StoryName

Generated: $genDate

---

## Overview

This demo shows how SimTreeNav tracks changes across a manufacturing plant's digital twin data over time. We'll walk through real-world scenarios that manufacturing engineers face daily.

---

## Timeline Summary

| Step | Event | Changes | Node Count |
|------|-------|---------|------------|
"@
    
    foreach ($entry in $Timeline) {
        $md += "`n| $($entry.label) | $($entry.eventType) | $($entry.changeCount) | $($entry.nodeCount) |"
    }
    
    $md += @"


---

## Scene-by-Scene Talk Track

### Scene 1: Baseline (Clean State)
**[CLICK: Timeline -> Baseline]**

> "Here's our starting point - a clean snapshot of Plant Alpha with $($Timeline[0].nodeCount) nodes. 
> Notice the hierarchical structure: Stations contain Resource Groups, which contain Robots with their Tools."

**Key points:**
- Explain the node types: Station, ResourceGroup, Resource, ToolInstance, Operation, Location
- Show the tree structure
- Highlight prototype-instance relationships

---

### Scene 2: Bulk Paste Event
**[CLICK: Timeline -> Bulk Paste]**

> "A technician just imported tools from another project - we see a spike of $($Timeline[1].changeCount) new nodes.
> SimTreeNav detects this as a 'Bulk Paste' intent with high confidence."

**Demo actions:**
- Click on the Intents tab
- Show the "BulkPaste" intent detection
- Highlight the affected subtree

---

### Scene 3: Rename Pass (Standardization)
**[CLICK: Timeline -> Rename Pass]**

> "Engineering standardized naming conventions. Notice how SimTreeNav tracks renames while preserving identity."

**Demo actions:**
- Show renamed nodes with `_STD` suffix
- Explain identity resolution (same node, different name)
- Point out zero false positives

---

### Scene 4: Retouch Session (Transform Drift)
**[CLICK: Timeline -> Retouch]**

> "Here's where it gets interesting. Someone adjusted tool positions - look at the Drift tab."

**Demo actions:**
- Switch to Drift view
- Show position/rotation deltas
- Explain tolerance thresholds
- Highlight "drifted pairs"

---

### Scene 5: Station Restructure
**[CLICK: Timeline -> Restructure]**

> "Management reorganized resource groups between stations. SimTreeNav tracks the moves."

**Demo actions:**
- Show Move changes
- Explain parent-child tracking
- Demonstrate impact analysis on restructured nodes

---

### Scene 6: Prototype Swap
**[CLICK: Timeline -> Prototype Swap]**

> "Tool prototypes were updated - some instances now point to different master definitions."

**Demo actions:**
- Show link changes
- Explain prototype-instance relationships
- Highlight compliance impact

---

### Scene 7: Anomaly Event (Mass Delete)
**[CLICK: Timeline -> Anomaly]**

> "This is critical - an accidental mass deletion. SimTreeNav immediately flags this as an anomaly."

**Demo actions:**
- Switch to Anomalies tab
- Show Critical severity alert
- Demonstrate the anomaly evidence
- Explain blast radius impact

---

### Scene 8: Recovery
**[CLICK: Timeline -> Recovery]**

> "Partial recovery was performed. SimTreeNav shows which nodes were restored."

**Demo actions:**
- Compare before/after counts
- Show restored nodes
- Demonstrate compliance score recovery

---

## Final Statistics

| Metric | Value |
|--------|-------|
| Total Snapshots | $($Timeline.Count) |
| Final Node Count | $($FinalStats.nodeCount) |
| Total Changes Tracked | $($FinalStats.totalChanges) |
| Anomalies Detected | $($FinalStats.anomalies) |
| Compliance Score | $($FinalStats.compliance)% |

---

## Q&A Talking Points

1. **"How does identity resolution work?"**
   > We use multiple signals: externalId, name+path, content hash, prototype links. Each has a weight, and we compute a confidence score.

2. **"Is this real-time?"**
   > For demos, we generate synthetic data. In production, we poll the database at configurable intervals (watch mode).

3. **"What about performance with 100k nodes?"**
   > We use streaming writers, paging, and virtualized UI. The viewer caps at 2000 nodes but the full data is in JSON files.

4. **"Can we export this?"**
   > Yes! The bundle is self-contained HTML+JSON. Works offline, no server needed.

---

## Next Steps

- Review the `data/` folder for raw JSON exports
- Check `manifest.json` for bundle contents
- Try the search/filter features in the viewer

---

*Generated by SimTreeNav v0.4 DemoStory*
"@
    
    return $md
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Show-StoryBanner

# Track timeline
$timeline = @()
$allDiffs = @()
$baseTimestamp = if ($Script:DeterministicMode) { 
    [datetime]'2025-01-01T09:00:00Z' 
} else { 
    Get-Date 
}

Write-StoryProgress "1/8" "Creating baseline dataset (~$NodeCount nodes)..." -Status 'Story'
$baselineNodes = New-BaselineDataset -NodeCount $NodeCount -Config $storyConfig
$timeline += New-TimelineEntry -SnapshotId 'snap_01_baseline' -Label 'Baseline' -Timestamp $baseTimestamp `
    -NodeCount $baselineNodes.Count -EventType 'baseline' -Description 'Initial clean state'
Write-StoryProgress "1/8" "Baseline: $($baselineNodes.Count) nodes" -Status 'Success'

Write-StoryProgress "2/8" "Applying Bulk Paste event..." -Status 'Story'
$snap2 = Apply-BulkPasteEvent -Nodes $baselineNodes -Config $storyConfig
$timeline += New-TimelineEntry -SnapshotId 'snap_02_bulkpaste' -Label 'Bulk Paste' -Timestamp $baseTimestamp.AddMinutes(30) `
    -NodeCount $snap2.Count -ChangeCount ($snap2.Count - $baselineNodes.Count) -EventType 'bulk_paste' -Description 'Mass import of station data'
Write-StoryProgress "2/8" "Bulk Paste: +$($snap2.Count - $baselineNodes.Count) nodes" -Status 'Success'

Write-StoryProgress "3/8" "Applying Rename Pass event..." -Status 'Story'
$snap3 = Apply-RenamePassEvent -Nodes $snap2
$renamedCount = ($snap3 | Where-Object { $_.name -match '_STD$' }).Count
$timeline += New-TimelineEntry -SnapshotId 'snap_03_rename' -Label 'Rename Pass' -Timestamp $baseTimestamp.AddHours(2) `
    -NodeCount $snap3.Count -ChangeCount $renamedCount -EventType 'standardization' -Description 'Naming convention standardization'
Write-StoryProgress "3/8" "Rename Pass: $renamedCount nodes renamed" -Status 'Success'

Write-StoryProgress "4/8" "Applying Retouch Session (drift)..." -Status 'Story'
$snap4 = Apply-RetouchSessionEvent -Nodes $snap3
$timeline += New-TimelineEntry -SnapshotId 'snap_04_retouch' -Label 'Retouch' -Timestamp $baseTimestamp.AddHours(5) `
    -NodeCount $snap4.Count -ChangeCount ([int]($snap4.Count * 0.15)) -EventType 'transform_adjust' -Description 'Transform adjustments causing drift'
Write-StoryProgress "4/8" "Retouch Session: transforms adjusted" -Status 'Success'

Write-StoryProgress "5/8" "Applying Station Restructure..." -Status 'Story'
$snap5 = Apply-StationRestructureEvent -Nodes $snap4 -Config $storyConfig
$movedCount = ($snap5 | Where-Object { $_.nodeType -eq 'ResourceGroup' -and $snap4.Where({$_.nodeId -eq $snap5[0].nodeId}).parentId -ne $_.parentId }).Count
$timeline += New-TimelineEntry -SnapshotId 'snap_05_restructure' -Label 'Restructure' -Timestamp $baseTimestamp.AddDays(1) `
    -NodeCount $snap5.Count -ChangeCount $movedCount -EventType 'reorganization' -Description 'Station reorganization'
Write-StoryProgress "5/8" "Station Restructure complete" -Status 'Success'

Write-StoryProgress "6/8" "Applying Prototype Swap..." -Status 'Story'
$snap6 = Apply-PrototypeSwapEvent -Nodes $snap5 -Config $storyConfig
$timeline += New-TimelineEntry -SnapshotId 'snap_06_protoswap' -Label 'Prototype Swap' -Timestamp $baseTimestamp.AddDays(1).AddHours(3) `
    -NodeCount $snap6.Count -ChangeCount ([int]($snap6.Count * 0.02)) -EventType 'prototype_change' -Description 'Tool prototype updates'
Write-StoryProgress "6/8" "Prototype Swap complete" -Status 'Success'

Write-StoryProgress "7/8" "Applying Anomaly Event (mass delete)..." -Status 'Story'
$snap7 = Apply-AnomalyEvent -Nodes $snap6
$deletedCount = $snap6.Count - $snap7.Count
$timeline += New-TimelineEntry -SnapshotId 'snap_07_anomaly' -Label 'Anomaly' -Timestamp $baseTimestamp.AddDays(2) `
    -NodeCount $snap7.Count -ChangeCount $deletedCount -EventType 'mass_delete' -Description 'Accidental mass deletion - CRITICAL'
Write-StoryProgress "7/8" "Anomaly Event: -$deletedCount nodes (ALERT!)" -Status 'Warning'

Write-StoryProgress "8/8" "Applying Recovery..." -Status 'Story'
$snap8 = Apply-RecoveryEvent -CurrentNodes $snap7 -BaselineNodes $snap6
$restoredCount = $snap8.Count - $snap7.Count
$timeline += New-TimelineEntry -SnapshotId 'snap_08_recovery' -Label 'Recovery' -Timestamp $baseTimestamp.AddDays(2).AddHours(1) `
    -NodeCount $snap8.Count -ChangeCount $restoredCount -EventType 'recovery' -Description 'Partial restoration'
Write-StoryProgress "8/8" "Recovery: +$restoredCount nodes restored" -Status 'Success'

# Final current state
$currentNodes = $snap8

Write-StoryProgress "ANALYSIS" "Resolving identities..." -Status 'Info'
$baselineNodes = Resolve-NodeIdentities -Nodes $baselineNodes
$currentNodes = Resolve-NodeIdentities -Nodes $currentNodes

Write-StoryProgress "ANALYSIS" "Computing diff with identity matching..." -Status 'Info'
$diffResult = Compare-NodesWithIdentity -BaselineNodes $baselineNodes -CurrentNodes $currentNodes -ConfidenceThreshold 0.85
$diff = $diffResult.changes

Write-StoryProgress "ANALYSIS" "Grouping into work sessions..." -Status 'Info'
$sessions = Group-ChangesIntoSessions -Changes $diff -TimeWindowMinutes 60 -MinChangesPerSession 2

Write-StoryProgress "ANALYSIS" "Analyzing intents..." -Status 'Info'
$intents = @()
foreach ($session in $sessions) {
    $sessionIntents = Invoke-IntentAnalysis -Changes $session.changes -SessionId $session.sessionId
    $intents += $sessionIntents
}

Write-StoryProgress "ANALYSIS" "Computing impact analysis..." -Status 'Info'
$impactReport = Get-ImpactForChanges -Changes $diff -Nodes $currentNodes -MaxDepth 3

Write-StoryProgress "ANALYSIS" "Measuring drift..." -Status 'Info'
$driftReport = Measure-Drift -Nodes $currentNodes

Write-StoryProgress "ANALYSIS" "Checking compliance..." -Status 'Info'
$template = New-GoldenTemplate -Name 'PlantAlphaTemplate' -AllowExtras
$template.requiredTypes = @(
    (New-TypeRequirement -NodeType 'Station' -MinCount 1 -Required)
    (New-TypeRequirement -NodeType 'ResourceGroup' -MinCount 1)
    (New-TypeRequirement -NodeType 'Resource' -MinCount 1)
    (New-TypeRequirement -NodeType 'ToolPrototype' -MinCount 1)
)
$complianceReport = Test-Compliance -Nodes $currentNodes -Template $template

Write-StoryProgress "ANALYSIS" "Detecting anomalies..." -Status 'Info'
$anomalyReport = Detect-Anomalies -Changes $diff -TotalNodes $baselineNodes.Count

# Build diff export object
$diffExport = [PSCustomObject]@{
    summary = [PSCustomObject]@{
        totalChanges      = $diff.Count
        added             = ($diff | Where-Object { $_.changeType -eq 'added' }).Count
        removed           = ($diff | Where-Object { $_.changeType -eq 'removed' }).Count
        renamed           = ($diff | Where-Object { $_.changeType -eq 'renamed' }).Count
        moved             = ($diff | Where-Object { $_.changeType -eq 'moved' }).Count
        transform_changed = ($diff | Where-Object { $_.changeType -eq 'transform_changed' }).Count
        rekeyed           = ($diff | Where-Object { $_.changeType -eq 'rekeyed' }).Count
    }
    changes = $diff
}

# Create output directory
if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

Write-StoryProgress "BUNDLE" "Creating offline bundle..." -Status 'Info'

$bundleResult = Export-Bundle `
    -OutDir $OutDir `
    -BundleName $StoryName `
    -BaselineNodes $baselineNodes `
    -CurrentNodes $currentNodes `
    -Diff $diffExport `
    -Sessions $sessions `
    -Intents $intents `
    -Impact $impactReport `
    -Drift $driftReport `
    -Compliance $complianceReport `
    -Anomalies $anomalyReport `
    -Timeline $timeline `
    -Anonymize:$Anonymize `
    -CreateZip:$CreateZip

Write-StoryProgress "BUNDLE" "Bundle created: $($bundleResult.path)" -Status 'Success'

# Generate talk-track markdown
Write-StoryProgress "DOCS" "Generating talk-track documentation..." -Status 'Info'

$finalStats = [PSCustomObject]@{
    nodeCount    = $currentNodes.Count
    totalChanges = $diff.Count
    anomalies    = $anomalyReport.totalAnomalies
    compliance   = [Math]::Round($complianceReport.score * 100)
}

$talkTrack = New-TalkTrackMarkdown -StoryName $StoryName -Timeline $timeline -FinalStats $finalStats

# Save talk-track
$docsDir = Join-Path $PSScriptRoot 'docs'
if (-not (Test-Path $docsDir)) {
    New-Item -ItemType Directory -Path $docsDir -Force | Out-Null
}
$talkTrackPath = Join-Path $docsDir 'DEMO-TALK-TRACK.md'
$talkTrack | Set-Content $talkTrackPath -Encoding UTF8
Write-StoryProgress "DOCS" "Talk-track saved: $talkTrackPath" -Status 'Success'

# Also save in bundle
$talkTrack | Set-Content (Join-Path $OutDir 'TALK-TRACK.md') -Encoding UTF8

# Summary
Write-Host ""
Write-Host "  ╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║                    DEMO STORY COMPLETE                        ║" -ForegroundColor Green
Write-Host "  ╠═══════════════════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "  ║  Story Name:        $($StoryName.PadRight(37).Substring(0,37))  ║" -ForegroundColor Green
Write-Host "  ║  Timeline Steps:    $($timeline.Count.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Baseline Nodes:    $($baselineNodes.Count.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Final Nodes:       $($currentNodes.Count.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Total Changes:     $($diff.Count.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Anomalies:         $($anomalyReport.totalAnomalies.ToString().PadLeft(6))                                 ║" -ForegroundColor Green
Write-Host "  ║  Compliance Score:  $([Math]::Round($complianceReport.score * 100).ToString().PadLeft(5))%                                ║" -ForegroundColor Green
Write-Host "  ║  Anonymized:        $(if ($Anonymize) { '   Yes' } else { '    No' })                                 ║" -ForegroundColor Green
Write-Host "  ╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Bundle: $OutDir" -ForegroundColor Cyan
Write-Host "  Talk-Track: $talkTrackPath" -ForegroundColor Cyan
Write-Host ""

# Open bundle if requested
if (-not $NoOpen) {
    $indexPath = Join-Path $OutDir 'index.html'
    if (Test-Path $indexPath) {
        Write-Host "  Opening bundle in browser..." -ForegroundColor Cyan
        if ($IsWindows -or $env:OS -match 'Windows') {
            Start-Process $indexPath
        }
        elseif ($IsMacOS) {
            & open $indexPath
        }
        else {
            Write-Host "  Bundle ready at: $indexPath" -ForegroundColor Yellow
        }
    }
}

# Return result for automation
[PSCustomObject]@{
    bundlePath   = $bundleResult.path
    talkTrackPath = $talkTrackPath
    timeline     = $timeline
    stats        = $finalStats
    isAnonymized = $Anonymize.IsPresent
}
