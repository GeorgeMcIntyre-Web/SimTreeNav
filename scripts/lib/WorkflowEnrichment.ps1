<#
.SYNOPSIS
    Workflow-aware event enrichment helpers.

.DESCRIPTION
    Provides context and description enrichment functions for management events.
    Keeps logic guard-clause driven and null-safe.
#>

function Get-WorkflowPhase {
    <#
    .SYNOPSIS
        Returns workflow phase prefix from workType.
    #>
    param(
        [string]$WorkType
    )

    if ([string]::IsNullOrWhiteSpace($WorkType)) {
        return $null
    }

    if ($WorkType -notmatch '\.') {
        return $WorkType
    }

    return $WorkType.Split('.')[0]
}

function Get-AllocationFingerprintHash {
    <#
    .SYNOPSIS
        Computes SHA-256 hash for allocation fingerprint input.
    #>
    param(
        [string]$InputString
    )

    if ([string]::IsNullOrWhiteSpace($InputString)) {
        return $null
    }

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $hashBytes = $hasher.ComputeHash($bytes)
    $hashHex = [System.BitConverter]::ToString($hashBytes).Replace('-', '')

    return $hashHex.Substring(0, 16)
}

function New-AllocationFingerprint {
    <#
    .SYNOPSIS
        Creates a deterministic allocation fingerprint hash.
    #>
    param(
        [string]$Station = "",
        [string[]]$OperationIds = @(),
        [string[]]$ResourceIds = @(),
        [int]$OperationCount = 0
    )

    $stationValue = if ($Station) { $Station } else { "" }
    $ops = @($OperationIds | Where-Object { $_ }) | Sort-Object -Unique
    $resources = @($ResourceIds | Where-Object { $_ }) | Sort-Object -Unique

    if (-not $stationValue -and $ops.Count -eq 0 -and $resources.Count -eq 0 -and $OperationCount -le 0) {
        return $null
    }

    $raw = @(
        "station=$stationValue",
        "opCount=$OperationCount",
        "ops=$($ops -join ',')",
        "resources=$($resources -join ',')"
    ) -join '|'

    return Get-AllocationFingerprintHash -InputString $raw
}

function Get-AllocationStabilityState {
    <#
    .SYNOPSIS
        Returns allocation stability state from fingerprint history.
    #>
    param(
        [string[]]$FingerprintHistory,
        [int]$Window = 3
    )

    $history = @($FingerprintHistory | Where-Object { $_ })
    if ($history.Count -lt 2) {
        return $null
    }

    $last = $history[-1]
    $prev = $history[-2]
    if ($last -ne $prev) {
        return "volatile"
    }

    if ($history.Count -lt $Window) {
        return "settling"
    }

    $slice = $history[-$Window..-1]
    if ($slice | Where-Object { $_ -ne $last }) {
        return "settling"
    }

    return "stable"
}

function Get-IpaWriteSources {
    <#
    .SYNOPSIS
        Returns write sources for IPA events based on queried tables.
    #>
    param(
        [int]$OperationCount = 0
    )

    return @("PART_.MODIFICATIONDATE_DA_")
}

function Try-ResolveStationContext {
    <#
    .SYNOPSIS
        Attempts to resolve station context from known fields.
    #>
    param(
        [object]$Item,
        [string]$ObjectName
    )

    $candidates = @()
    if ($Item) {
        foreach ($field in @('station', 'shortcut_name', 'operation_name', 'study_name')) {
            if ($Item.PSObject.Properties[$field] -and $Item.$field) {
                $candidates += $Item.$field
            }
        }
    }

    if ($ObjectName) {
        $candidates += $ObjectName
    }

    foreach ($candidate in $candidates) {
        if ($candidate -match '([0-9]{1,2}J[-_][0-9]{3})') {
            $stationValue = $Matches[1].Replace('_', '-')
            return @{ station = $stationValue }
        }
    }

    return $null
}

function Get-ContextObjectType {
    <#
    .SYNOPSIS
        Determines context.objectType based on workType and source metadata.
    #>
    param(
        [string]$WorkType,
        [string]$ObjectType,
        [string]$OperationCategory = ""
    )

    if ([string]::IsNullOrWhiteSpace($WorkType)) {
        return $null
    }

    switch ($WorkType) {
        'libraries.partLibrary' { return 'partPrototype' }
        'libraries.partInstanceLibrary' { return 'partInstance' }
        'libraries.mfgLibrary' { return 'mfgFeature' }
        'resources.resourceLibrary' {
            if ([string]::IsNullOrWhiteSpace($ObjectType)) {
                return $null
            }

            if ($ObjectType -match '(?i)robot') { return 'robot' }
            if ($ObjectType -match '(?i)gun') { return 'gun' }
            if ($ObjectType -match '(?i)fixture') { return 'fixture' }
            if ($ObjectType -match '(?i)station|cell') { return 'station' }
            return $null
        }
        'study.operationAllocation' {
            if ($ObjectType -match '(?i)weld') { return 'weldOp' }
            if ($OperationCategory -match '(?i)weld') { return 'weldOp' }
            return $null
        }
        'designLoop.gunCloud' { return 'weldOp' }
        default { return $null }
    }
}

function Get-ChangeAction {
    <#
    .SYNOPSIS
        Determines a human-friendly action label from snapshot comparison.
    #>
    param(
        [hashtable]$SnapshotComparison
    )

    if (-not $SnapshotComparison) {
        return 'Updated'
    }

    if (-not $SnapshotComparison.previousRecord) {
        return 'Added'
    }

    if ($SnapshotComparison.hasWrite -or $SnapshotComparison.hasDelta) {
        return 'Updated'
    }

    return 'Observed'
}

function New-LibraryDeltaSummary {
    <#
    .SYNOPSIS
        Creates a delta summary for library add/change events.
    #>
    param(
        [hashtable]$SnapshotComparison,
        [hashtable]$NewRecord
    )

    if (-not $SnapshotComparison) {
        return $null
    }

    if (-not $SnapshotComparison.hasDelta) {
        return $null
    }

    $isNew = -not $SnapshotComparison.previousRecord
    $kind = if ($isNew) { 'libraryAdd' } else { 'libraryChange' }

    $before = $null
    if (-not $isNew -and $SnapshotComparison.previousRecord -and $SnapshotComparison.previousRecord.PSObject.Properties['metadata']) {
        $before = $SnapshotComparison.previousRecord.metadata
    }

    $after = $null
    if ($NewRecord -and $NewRecord.metadata) {
        $after = $NewRecord.metadata
    }

    return @{
        kind = $kind
        fields = @('record')
        before = $before
        after = $after
    }
}

function New-AllocationDeltaSummary {
    <#
    .SYNOPSIS
        Creates a delta summary for allocation-style changes when detectable.
    #>
    param(
        [hashtable]$SnapshotComparison,
        [hashtable]$NewRecord
    )

    if (-not $SnapshotComparison) {
        return $null
    }

    if (-not $SnapshotComparison.hasDelta) {
        return $null
    }

    $beforeRecord = $SnapshotComparison.previousRecord
    if (-not $beforeRecord) {
        return $null
    }

    $beforeCounts = $beforeRecord.operationCounts
    $afterCounts = $null
    if ($NewRecord) {
        $afterCounts = $NewRecord.operationCounts
    }

    if (-not $beforeCounts -and -not $afterCounts) {
        return $null
    }

    $beforeCount = 0
    $afterCount = 0
    if ($beforeCounts -and $beforeCounts.operationCount -ne $null) {
        $beforeCount = [int]$beforeCounts.operationCount
    }
    if ($afterCounts -and $afterCounts.operationCount -ne $null) {
        $afterCount = [int]$afterCounts.operationCount
    }

    $diff = $afterCount - $beforeCount
    $added = if ($diff -gt 0) { $diff } else { 0 }
    $removed = if ($diff -lt 0) { [Math]::Abs($diff) } else { 0 }

    $fingerprintBefore = $null
    if ($beforeCounts -and $beforeCounts.allocationFingerprint) {
        $fingerprintBefore = $beforeCounts.allocationFingerprint
    }

    $fingerprintAfter = $null
    if ($afterCounts -and $afterCounts.allocationFingerprint) {
        $fingerprintAfter = $afterCounts.allocationFingerprint
    }

    if (-not $fingerprintBefore -and -not $fingerprintAfter -and $added -eq 0 -and $removed -eq 0) {
        return $null
    }

    return @{
        kind = 'allocation'
        fields = @('operationsAdded', 'operationsRemoved', 'fingerprintChanged')
        operationsAddedCount = $added
        operationsRemovedCount = $removed
        fingerprintBefore = $fingerprintBefore
        fingerprintAfter = $fingerprintAfter
    }
}

function New-CoordinateDeltaSummary {
    <#
    .SYNOPSIS
        Creates a delta summary for movement events.
    #>
    param(
        [hashtable]$NewRecord,
        [hashtable]$PreviousRecord
    )

    if (-not $NewRecord -or -not $PreviousRecord) {
        return $null
    }

    if (-not $NewRecord.coordinates -or -not $PreviousRecord.coordinates) {
        return $null
    }

    $dx = [Math]::Round(($NewRecord.coordinates.x - $PreviousRecord.coordinates.x), 2)
    $dy = [Math]::Round(($NewRecord.coordinates.y - $PreviousRecord.coordinates.y), 2)
    $dz = [Math]::Round(($NewRecord.coordinates.z - $PreviousRecord.coordinates.z), 2)

    $maxDelta = [Math]::Max([Math]::Max([Math]::Abs($dx), [Math]::Abs($dy)), [Math]::Abs($dz))

    return @{
        kind = 'movement'
        fields = @('x', 'y', 'z')
        maxAbsDelta = $maxDelta
        before = $PreviousRecord.coordinates
        after = $NewRecord.coordinates
        delta = @{ x = $dx; y = $dy; z = $dz }
    }
}

function New-OperationCountDeltaSummary {
    <#
    .SYNOPSIS
        Creates a delta summary for operation count changes.
    #>
    param(
        [hashtable]$NewRecord,
        [hashtable]$PreviousRecord
    )

    if (-not $NewRecord -or -not $PreviousRecord) {
        return $null
    }

    if (-not $NewRecord.operationCounts -or -not $PreviousRecord.operationCounts) {
        return $null
    }

    $changed = @()
    foreach ($key in $NewRecord.operationCounts.Keys) {
        if (-not $PreviousRecord.operationCounts.ContainsKey($key)) {
            $changed += $key
            continue
        }

        if ($NewRecord.operationCounts[$key] -ne $PreviousRecord.operationCounts[$key]) {
            $changed += $key
        }
    }

    if ($changed.Count -eq 0) {
        return $null
    }

    return @{
        kind = 'operationCounts'
        fields = $changed
        before = $PreviousRecord.operationCounts
        after = $NewRecord.operationCounts
    }
}

function New-EventEnrichment {
    <#
    .SYNOPSIS
        Builds human-readable description and optional context for an event.
    #>
    param(
        [string]$WorkType,
        [string]$ObjectName,
        [string]$ObjectType,
        [string]$ObjectId,
        [string]$Category,
        [object]$Item,
        [hashtable]$DeltaSummary,
        [hashtable]$SnapshotComparison
    )

    $context = @{}
    $stationContext = Try-ResolveStationContext -Item $Item -ObjectName $ObjectName
    if ($stationContext -and $stationContext.station) {
        $context.station = $stationContext.station
    }

    $operationCategory = $null
    if ($Item -and $Item.PSObject.Properties['operation_category']) {
        $operationCategory = $Item.operation_category
    }

    $contextObjectType = Get-ContextObjectType -WorkType $WorkType -ObjectType $ObjectType -OperationCategory $operationCategory
    if ($contextObjectType) {
        $context.objectType = $contextObjectType
    }

    if ($context.Count -eq 0) {
        $context = $null
    }

    $action = Get-ChangeAction -SnapshotComparison $SnapshotComparison
    $safeName = if ($ObjectName) { $ObjectName } else { $ObjectId }

    switch ($WorkType) {
        'libraries.partLibrary' {
            $suffix = if ($Category) { " ($Category)" } else { "" }
            return @{ description = "$action library item: $safeName$suffix"; context = $context }
        }
        'libraries.mfgLibrary' {
            return @{ description = "$action MFG library item: $safeName"; context = $context }
        }
        'libraries.partInstanceLibrary' {
            return @{ description = "$action part instance: $safeName"; context = $context }
        }
        'resources.resourceLibrary' {
            $typeSuffix = if ($ObjectType) { " ($ObjectType)" } else { "" }
            return @{ description = "$action resource: $safeName$typeSuffix"; context = $context }
        }
        'process.ipa' {
            return @{ description = "$action IPA assembly: $safeName"; context = $context }
        }
        'study.layout' {
            if ($DeltaSummary -and $DeltaSummary.kind -eq 'movement' -and $DeltaSummary.delta) {
                $dx = $DeltaSummary.delta.x
                $dy = $DeltaSummary.delta.y
                $dz = $DeltaSummary.delta.z
                return @{ description = "Layout moved (dx=$dx, dy=$dy, dz=$dz)"; context = $context }
            }

            return @{ description = "Study layout updated: $safeName"; context = $context }
        }
        'study.operationAllocation' {
            $categorySuffix = if ($operationCategory) { " ($operationCategory)" } else { "" }
            return @{ description = "$action operation: $safeName$categorySuffix"; context = $context }
        }
        'designLoop.gunCloud' {
            return @{ description = "$action gun cloud weld: $safeName"; context = $context }
        }
        default {
            return @{ description = $safeName; context = $context }
        }
    }
}
