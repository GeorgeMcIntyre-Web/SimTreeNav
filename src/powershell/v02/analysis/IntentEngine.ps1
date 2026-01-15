# IntentEngine.ps1
# Infers user intent/work mode from diff change patterns
# v0.3: Deterministic intent inference (no LLM required)

<#
.SYNOPSIS
    Infers work intent/mode from change patterns.

.DESCRIPTION
    Analyzes diff events to determine what type of work was being done:
    - RetouchingPoints: Many transform changes, localized to operations
    - StationRestructure: High moved/renamed in resource groups
    - BulkPasteTemplate: Burst of adds with systematic renames
    - PrototypeSwap: Tool instance attribute changes linking new prototype
    - JoiningUpdate: MFG/Panel changes followed by operation drift
    - Cleanup: Bulk deletes, often with systematic patterns
    - Commissioning: New nodes added with transforms being set

    Each intent has:
    - Evidence list (diff event references)
    - Confidence score (0..1)
    - One-line explanation

.EXAMPLE
    $intents = Invoke-IntentAnalysis -Session $session
#>

# Intent type definitions
$Script:IntentTypes = @{
    RetouchingPoints    = 'retouching_points'
    StationRestructure  = 'station_restructure'
    BulkPasteTemplate   = 'bulk_paste_template'
    PrototypeSwap       = 'prototype_swap'
    JoiningUpdate       = 'joining_update'
    Cleanup             = 'cleanup'
    Commissioning       = 'commissioning'
    Renaming            = 'renaming'
    Reorganizing        = 'reorganizing'
    Debugging           = 'debugging'
    Unknown             = 'unknown'
}

# Intent detection thresholds
$Script:IntentConfig = @{
    RetouchingMinTransforms     = 3
    RetouchingTransformRatio    = 0.5
    RestructureMinMoves         = 3
    RestructureMoveRatio        = 0.3
    BulkPasteMinAdds            = 5
    BulkPasteAddRatio           = 0.6
    CleanupMinDeletes           = 3
    CleanupDeleteRatio          = 0.5
    CommissioningAddRatio       = 0.4
    CommissioningTransformRatio = 0.3
}

function New-Intent {
    <#
    .SYNOPSIS
        Creates an intent object.
    #>
    param(
        [string]$IntentType,
        [string]$Explanation,
        [double]$Confidence,
        [array]$Evidence,
        [hashtable]$Details = @{}
    )
    
    [PSCustomObject]@{
        intentType  = $IntentType
        explanation = $Explanation
        confidence  = [Math]::Round($Confidence, 2)
        evidenceCount = $Evidence.Count
        evidence    = $Evidence | Select-Object nodeId, changeType, nodeName, path -First 10
        details     = [PSCustomObject]$Details
        timestamp   = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function Detect-RetouchingPoints {
    <#
    .SYNOPSIS
        Detects retouching/reteaching of operation points.
    #>
    param(
        [array]$Changes,
        [hashtable]$Config = $Script:IntentConfig
    )
    
    $transformChanges = $Changes | Where-Object { $_.changeType -eq 'transform_changed' }
    $operationTransforms = $transformChanges | Where-Object { $_.nodeType -in @('Operation', 'Location') }
    
    if ($operationTransforms.Count -lt $Config.RetouchingMinTransforms) {
        return $null
    }
    
    $ratio = $operationTransforms.Count / [Math]::Max(1, $Changes.Count)
    if ($ratio -lt $Config.RetouchingTransformRatio) {
        return $null
    }
    
    # Check for spatial locality
    $subtrees = $operationTransforms | ForEach-Object {
        $parts = $_.path -split '/' | Where-Object { $_ }
        if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" }
    } | Select-Object -Unique
    
    $confidence = [Math]::Min(1.0, $ratio + (1.0 / [Math]::Max(1, $subtrees.Count)) * 0.3)
    
    $explanation = "Detected $($operationTransforms.Count) operation/location transforms in $($subtrees.Count) subtree(s) - likely retouching robot points"
    
    return New-Intent `
        -IntentType $Script:IntentTypes.RetouchingPoints `
        -Explanation $explanation `
        -Confidence $confidence `
        -Evidence $operationTransforms `
        -Details @{
            transformCount = $operationTransforms.Count
            subtrees = $subtrees
            affectedNodeTypes = ($operationTransforms | Group-Object nodeType | ForEach-Object { $_.Name })
        }
}

function Detect-StationRestructure {
    <#
    .SYNOPSIS
        Detects station restructuring (reorganization of resources/operations).
    #>
    param(
        [array]$Changes,
        [hashtable]$Config = $Script:IntentConfig
    )
    
    $moveChanges = $Changes | Where-Object { $_.changeType -eq 'moved' }
    $renameChanges = $Changes | Where-Object { $_.changeType -eq 'renamed' }
    $restructureChanges = @($moveChanges) + @($renameChanges)
    
    if ($moveChanges.Count -lt $Config.RestructureMinMoves) {
        return $null
    }
    
    $ratio = $restructureChanges.Count / [Math]::Max(1, $Changes.Count)
    if ($ratio -lt $Config.RestructureMoveRatio) {
        return $null
    }
    
    # Check if concentrated in resource groups
    $resourceGroupChanges = $restructureChanges | Where-Object { $_.nodeType -eq 'ResourceGroup' }
    $resourceRatio = $resourceGroupChanges.Count / [Math]::Max(1, $restructureChanges.Count)
    
    $confidence = [Math]::Min(1.0, $ratio * 0.7 + $resourceRatio * 0.3)
    
    # Find most affected subtrees
    $subtreeCounts = @{}
    foreach ($change in $restructureChanges) {
        $parts = $change.path -split '/' | Where-Object { $_ }
        $subtree = if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" } else { "/" }
        if (-not $subtreeCounts.ContainsKey($subtree)) { $subtreeCounts[$subtree] = 0 }
        $subtreeCounts[$subtree]++
    }
    $topSubtree = ($subtreeCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1).Key
    
    $explanation = "Station restructure detected: $($moveChanges.Count) moves, $($renameChanges.Count) renames - concentrated in $topSubtree"
    
    return New-Intent `
        -IntentType $Script:IntentTypes.StationRestructure `
        -Explanation $explanation `
        -Confidence $confidence `
        -Evidence $restructureChanges `
        -Details @{
            moveCount = $moveChanges.Count
            renameCount = $renameChanges.Count
            topSubtree = $topSubtree
            resourceGroupRatio = [Math]::Round($resourceRatio, 2)
        }
}

function Detect-BulkPasteTemplate {
    <#
    .SYNOPSIS
        Detects bulk paste/template operations (mass adds with patterns).
    #>
    param(
        [array]$Changes,
        [hashtable]$Config = $Script:IntentConfig
    )
    
    $addChanges = $Changes | Where-Object { $_.changeType -eq 'added' }
    
    if ($addChanges.Count -lt $Config.BulkPasteMinAdds) {
        return $null
    }
    
    $ratio = $addChanges.Count / [Math]::Max(1, $Changes.Count)
    if ($ratio -lt $Config.BulkPasteAddRatio) {
        return $null
    }
    
    # Check for naming patterns (common prefixes)
    $names = $addChanges | ForEach-Object { $_.nodeName }
    $commonPrefix = Get-CommonPrefix -Strings $names
    
    # Check for parent clustering
    $parentCounts = @{}
    foreach ($change in $addChanges) {
        $parent = $change.parentId
        if (-not $parent) { continue }
        if (-not $parentCounts.ContainsKey($parent)) { $parentCounts[$parent] = 0 }
        $parentCounts[$parent]++
    }
    $maxParentCount = if ($parentCounts.Count -gt 0) { ($parentCounts.Values | Measure-Object -Maximum).Maximum } else { 0 }
    $parentConcentration = $maxParentCount / [Math]::Max(1, $addChanges.Count)
    
    $confidence = [Math]::Min(1.0, $ratio * 0.5 + $parentConcentration * 0.5)
    
    $explanation = "Bulk paste detected: $($addChanges.Count) nodes added"
    if ($commonPrefix.Length -gt 3) {
        $explanation += " with common prefix '$commonPrefix'"
    }
    
    return New-Intent `
        -IntentType $Script:IntentTypes.BulkPasteTemplate `
        -Explanation $explanation `
        -Confidence $confidence `
        -Evidence $addChanges `
        -Details @{
            addCount = $addChanges.Count
            commonPrefix = $commonPrefix
            parentConcentration = [Math]::Round($parentConcentration, 2)
            nodeTypes = ($addChanges | Group-Object nodeType | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ', '
        }
}

function Detect-Cleanup {
    <#
    .SYNOPSIS
        Detects cleanup operations (bulk deletions).
    #>
    param(
        [array]$Changes,
        [hashtable]$Config = $Script:IntentConfig
    )
    
    $deleteChanges = $Changes | Where-Object { $_.changeType -eq 'removed' }
    
    if ($deleteChanges.Count -lt $Config.CleanupMinDeletes) {
        return $null
    }
    
    $ratio = $deleteChanges.Count / [Math]::Max(1, $Changes.Count)
    if ($ratio -lt $Config.CleanupDeleteRatio) {
        return $null
    }
    
    # Check for subtree concentration
    $subtreeCounts = @{}
    foreach ($change in $deleteChanges) {
        $parts = $change.path -split '/' | Where-Object { $_ }
        $subtree = if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" } else { "/" }
        if (-not $subtreeCounts.ContainsKey($subtree)) { $subtreeCounts[$subtree] = 0 }
        $subtreeCounts[$subtree]++
    }
    
    $confidence = [Math]::Min(1.0, $ratio)
    $topSubtrees = $subtreeCounts.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 3
    
    $explanation = "Cleanup detected: $($deleteChanges.Count) nodes removed"
    
    return New-Intent `
        -IntentType $Script:IntentTypes.Cleanup `
        -Explanation $explanation `
        -Confidence $confidence `
        -Evidence $deleteChanges `
        -Details @{
            deleteCount = $deleteChanges.Count
            topSubtrees = ($topSubtrees | ForEach-Object { "$($_.Key):$($_.Value)" }) -join ', '
            nodeTypes = ($deleteChanges | Group-Object nodeType | ForEach-Object { "$($_.Name):$($_.Count)" }) -join ', '
        }
}

function Detect-Commissioning {
    <#
    .SYNOPSIS
        Detects commissioning work (new nodes + transforms being set).
    #>
    param(
        [array]$Changes,
        [hashtable]$Config = $Script:IntentConfig
    )
    
    $addChanges = $Changes | Where-Object { $_.changeType -eq 'added' }
    $transformChanges = $Changes | Where-Object { $_.changeType -eq 'transform_changed' }
    
    $addRatio = $addChanges.Count / [Math]::Max(1, $Changes.Count)
    $transformRatio = $transformChanges.Count / [Math]::Max(1, $Changes.Count)
    
    if ($addRatio -lt $Config.CommissioningAddRatio -or $transformRatio -lt $Config.CommissioningTransformRatio) {
        return $null
    }
    
    # Check for co-location
    $addSubtrees = $addChanges | ForEach-Object {
        $parts = $_.path -split '/' | Where-Object { $_ }
        if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" }
    } | Select-Object -Unique
    
    $transformSubtrees = $transformChanges | ForEach-Object {
        $parts = $_.path -split '/' | Where-Object { $_ }
        if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" }
    } | Select-Object -Unique
    
    $overlap = $addSubtrees | Where-Object { $transformSubtrees -contains $_ }
    $overlapRatio = $overlap.Count / [Math]::Max(1, [Math]::Max($addSubtrees.Count, $transformSubtrees.Count))
    
    $confidence = [Math]::Min(1.0, ($addRatio + $transformRatio) / 2 + $overlapRatio * 0.3)
    
    if ($confidence -lt 0.4) {
        return $null
    }
    
    $explanation = "Commissioning detected: $($addChanges.Count) new nodes + $($transformChanges.Count) transforms"
    
    return New-Intent `
        -IntentType $Script:IntentTypes.Commissioning `
        -Explanation $explanation `
        -Confidence $confidence `
        -Evidence (@($addChanges) + @($transformChanges)) `
        -Details @{
            addCount = $addChanges.Count
            transformCount = $transformChanges.Count
            overlappingSubtrees = $overlap
        }
}

function Detect-JoiningUpdate {
    <#
    .SYNOPSIS
        Detects joining/MFG updates (MFG changes followed by operation adjustments).
    #>
    param(
        [array]$Changes,
        [hashtable]$Config = $Script:IntentConfig
    )
    
    $mfgChanges = $Changes | Where-Object { $_.nodeType -in @('MfgEntity', 'PanelEntity') }
    $operationChanges = $Changes | Where-Object { $_.nodeType -in @('Operation', 'Location') }
    
    if ($mfgChanges.Count -eq 0 -or $operationChanges.Count -eq 0) {
        return $null
    }
    
    # Check for correlation
    $mfgSubtrees = $mfgChanges | ForEach-Object {
        $parts = $_.path -split '/' | Where-Object { $_ }
        if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" }
    } | Select-Object -Unique
    
    $opSubtrees = $operationChanges | ForEach-Object {
        $parts = $_.path -split '/' | Where-Object { $_ }
        if ($parts.Count -ge 2) { "/$($parts[0])/$($parts[1])" }
    } | Select-Object -Unique
    
    # Look for any relationship
    $allChanges = @($mfgChanges) + @($operationChanges)
    $confidence = [Math]::Min(0.8, $allChanges.Count / [Math]::Max(1, $Changes.Count))
    
    if ($confidence -lt 0.3) {
        return $null
    }
    
    $explanation = "Joining update detected: $($mfgChanges.Count) MFG/Panel changes + $($operationChanges.Count) operation adjustments"
    
    return New-Intent `
        -IntentType $Script:IntentTypes.JoiningUpdate `
        -Explanation $explanation `
        -Confidence $confidence `
        -Evidence $allChanges `
        -Details @{
            mfgChangeCount = $mfgChanges.Count
            operationChangeCount = $operationChanges.Count
        }
}

function Get-CommonPrefix {
    <#
    .SYNOPSIS
        Finds common prefix among strings.
    #>
    param([array]$Strings)
    
    if (-not $Strings -or $Strings.Count -eq 0) { return '' }
    if ($Strings.Count -eq 1) { return $Strings[0] }
    
    $first = $Strings[0]
    $prefix = ''
    
    for ($i = 0; $i -lt $first.Length; $i++) {
        $char = $first[$i]
        $allMatch = $true
        
        foreach ($str in $Strings[1..($Strings.Count - 1)]) {
            if ($i -ge $str.Length -or $str[$i] -ne $char) {
                $allMatch = $false
                break
            }
        }
        
        if (-not $allMatch) { break }
        $prefix += $char
    }
    
    return $prefix -replace '[_\d]+$', ''
}

function Invoke-IntentAnalysis {
    <#
    .SYNOPSIS
        Main entry point for intent analysis.
    
    .DESCRIPTION
        Analyzes a session or set of changes to infer work intent.
        Returns all detected intents sorted by confidence.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Changes,
        
        [string]$SessionId = $null
    )
    
    $intents = @()
    
    # Run all detectors
    $retouching = Detect-RetouchingPoints -Changes $Changes
    if ($retouching) { $intents += $retouching }
    
    $restructure = Detect-StationRestructure -Changes $Changes
    if ($restructure) { $intents += $restructure }
    
    $bulkPaste = Detect-BulkPasteTemplate -Changes $Changes
    if ($bulkPaste) { $intents += $bulkPaste }
    
    $cleanup = Detect-Cleanup -Changes $Changes
    if ($cleanup) { $intents += $cleanup }
    
    $commissioning = Detect-Commissioning -Changes $Changes
    if ($commissioning) { $intents += $commissioning }
    
    $joining = Detect-JoiningUpdate -Changes $Changes
    if ($joining) { $intents += $joining }
    
    # If no specific intent detected, mark as unknown
    if ($intents.Count -eq 0) {
        $byType = $Changes | Group-Object changeType | Sort-Object Count -Descending | Select-Object -First 1
        $intents += New-Intent `
            -IntentType $Script:IntentTypes.Unknown `
            -Explanation "Mixed changes, no clear pattern detected (dominant: $($byType.Name))" `
            -Confidence 0.3 `
            -Evidence ($Changes | Select-Object -First 5) `
            -Details @{ dominantChangeType = $byType.Name; dominantCount = $byType.Count }
    }
    
    # Sort by confidence and add session reference
    $sortedIntents = $intents | Sort-Object confidence -Descending
    
    if ($SessionId) {
        $sortedIntents | ForEach-Object {
            $_ | Add-Member -NotePropertyName 'sessionId' -NotePropertyValue $SessionId -Force
        }
    }
    
    return $sortedIntents
}

function Export-IntentsJson {
    <#
    .SYNOPSIS
        Exports intents to JSON format.
    #>
    param(
        [array]$Intents,
        [string]$OutputPath,
        [switch]$Pretty
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $json = if ($Pretty) {
        $Intents | ConvertTo-Json -Depth 10
    } else {
        $Intents | ConvertTo-Json -Depth 10 -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $OutputPath 'intents.json'), $json, $utf8NoBom)
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Invoke-IntentAnalysis',
        'New-Intent',
        'Detect-RetouchingPoints',
        'Detect-StationRestructure',
        'Detect-BulkPasteTemplate',
        'Detect-Cleanup',
        'Detect-Commissioning',
        'Detect-JoiningUpdate',
        'Export-IntentsJson'
    )
}
