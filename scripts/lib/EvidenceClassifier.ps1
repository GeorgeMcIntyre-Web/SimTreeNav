<#
.SYNOPSIS
    Evidence-based work classification for simulator activity tracking.

.DESCRIPTION
    Provides functions to build evidence blocks and classify confidence levels
    for work association. Implements the Evidence Triangle pattern:
    - hasCheckout: PROXY.WORKING_VERSION_ID > 0
    - hasWrite: MODIFICATIONDATE_DA_ changed or recordHash changed
    - hasDelta: Meaningful content change (coords, ops, links)

.NOTES
    This is NOT about run-status.json (operational audit).
    This is about proving real simulator engineering work.
#>

$script:WorkflowWorkTypes = @(
    'libraries.partLibrary',
    'libraries.mfgLibrary',
    'libraries.partInstanceLibrary',
    'process.ipa',
    'resources.resourceLibrary',
    'study.layout',
    'study.robotMount',
    'study.toolMount',
    'study.accessCheck',
    'study.operationAllocation',
    'designLoop.gunCloud'
)

$script:LegacyWorkTypeMap = @{
    'PROJECT_DATABASE' = 'process.ipa'
    'Project Database' = 'process.ipa'
    'RESOURCE_LIBRARY' = 'resources.resourceLibrary'
    'Resource Library' = 'resources.resourceLibrary'
    'PART_LIBRARY' = 'libraries.partLibrary'
    'Part/MFG Library' = 'libraries.partLibrary'
    'IPA_ASSEMBLY' = 'process.ipa'
    'IPA Assembly' = 'process.ipa'
    'STUDY_SUMMARY' = 'study.layout'
    'Study Nodes' = 'study.layout'
    'STUDY_MOVEMENTS' = 'study.layout'
    'Study Movements' = 'study.layout'
    'STUDY_OPERATIONS' = 'study.operationAllocation'
    'Study Operations' = 'study.operationAllocation'
    'STUDY_WELDS' = 'designLoop.gunCloud'
    'Study Welds' = 'designLoop.gunCloud'
}

function Get-WorkflowWorkTypeList {
    <#
    .SYNOPSIS
        Returns the allowed workflow workType taxonomy values.
    #>
    return $script:WorkflowWorkTypes
}

function Test-WorkTypeAllowed {
    <#
    .SYNOPSIS
        Validates a workType against the allowed taxonomy.
    #>
    param(
        [string]$WorkType
    )

    if ([string]::IsNullOrWhiteSpace($WorkType)) {
        return $false
    }

    return $script:WorkflowWorkTypes -contains $WorkType
}

function Test-MfgObjectType {
    param(
        [string]$ObjectType
    )

    if ([string]::IsNullOrWhiteSpace($ObjectType)) {
        return $false
    }

    return ($ObjectType -match '(?i)mfg|manufactur|feature')
}

function Normalize-WorkType {
    <#
    .SYNOPSIS
        Normalizes legacy workType values to the workflow taxonomy.
    #>
    param(
        [string]$WorkType,
        [string]$ObjectType = "",
        [string]$Category = ""
    )

    if ([string]::IsNullOrWhiteSpace($WorkType)) {
        return $null
    }

    $candidate = $WorkType
    if ($script:LegacyWorkTypeMap.ContainsKey($candidate)) {
        $candidate = $script:LegacyWorkTypeMap[$candidate]
    }

    if ($candidate -eq 'libraries.partLibrary' -and (Test-MfgObjectType -ObjectType $ObjectType)) {
        $candidate = 'libraries.mfgLibrary'
    }

    if (-not (Test-WorkTypeAllowed -WorkType $candidate)) {
        return $null
    }

    return $candidate
}

function Get-AttributionStrength {
    <#
    .SYNOPSIS
        Determines attribution strength based on proxyOwner vs lastModifiedBy alignment.

    .PARAMETER ProxyOwnerName
        User name from PROXY.OWNER_ID -> USER_.CAPTION_S_

    .PARAMETER LastModifiedBy
        User name from table LASTMODIFIEDBY_S_ field

    .PARAMETER CheckoutTimestamp
        When object was checked out (if known)

    .PARAMETER ModificationTimestamp
        When object was last modified

    .OUTPUTS
        String: "strong", "medium", "weak"
    #>
    param(
        [string]$ProxyOwnerName,
        [string]$LastModifiedBy,
        [datetime]$CheckoutTimestamp = [datetime]::MinValue,
        [datetime]$ModificationTimestamp = [datetime]::MinValue
    )

    # Strong: Both fields present and match
    if (-not [string]::IsNullOrWhiteSpace($ProxyOwnerName) -and
        -not [string]::IsNullOrWhiteSpace($LastModifiedBy) -and
        $ProxyOwnerName -eq $LastModifiedBy) {

        # Extra strong if timestamps align (mod within checkout window)
        if ($CheckoutTimestamp -ne [datetime]::MinValue -and
            $ModificationTimestamp -ne [datetime]::MinValue -and
            $ModificationTimestamp -ge $CheckoutTimestamp) {
            return "strong"
        }

        return "strong"
    }

    # Medium: Both present but don't match (possible handoff or proxy mismatch)
    if (-not [string]::IsNullOrWhiteSpace($ProxyOwnerName) -and
        -not [string]::IsNullOrWhiteSpace($LastModifiedBy) -and
        $ProxyOwnerName -ne $LastModifiedBy) {
        return "medium"
    }

    # Medium: Only one attribution source present
    if (-not [string]::IsNullOrWhiteSpace($ProxyOwnerName) -or
        -not [string]::IsNullOrWhiteSpace($LastModifiedBy)) {
        return "medium"
    }

    # Weak: No attribution available
    return "weak"
}

function Get-Confidence {
    <#
    .SYNOPSIS
        Classifies confidence level based on evidence triangle.

    .PARAMETER HasCheckout
        Object is checked out (PROXY.WORKING_VERSION_ID > 0)

    .PARAMETER HasWrite
        Modification timestamp changed or record hash changed

    .PARAMETER HasDelta
        Meaningful content changed (coords, ops, links)

    .PARAMETER AttributionStrength
        Output from Get-AttributionStrength

    .OUTPUTS
        String: "confirmed", "likely", "checkout_only", "unattributed"
    #>
    param(
        [bool]$HasCheckout,
        [bool]$HasWrite,
        [bool]$HasDelta,
        [string]$AttributionStrength = "weak"
    )

    # Confirmed: Lock + Write + Delta with non-weak attribution
    if ($HasCheckout -and $HasWrite -and $HasDelta -and $AttributionStrength -ne "weak") {
        return "confirmed"
    }

    # Likely: Write + Delta but not confirmed
    if ($HasWrite -and $HasDelta) {
        return "likely"
    }

    # Checkout only: Lock but no write or delta
    if ($HasCheckout -and -not $HasWrite -and -not $HasDelta) {
        return "checkout_only"
    }

    # Default: Unattributed
    return "unattributed"
}

function New-EvidenceBlock {
    <#
    .SYNOPSIS
        Creates a complete evidence block for a work event.

    .PARAMETER ObjectId
        Object ID from database

    .PARAMETER ObjectType
        Type of object (Study, Resource, Operation, etc.)

    .PARAMETER ProxyOwnerId
        User ID from PROXY.OWNER_ID

    .PARAMETER ProxyOwnerName
        User name from USER_.CAPTION_S_

    .PARAMETER LastModifiedBy
        User from LASTMODIFIEDBY_S_ field

    .PARAMETER CheckoutWorkingVersionId
        PROXY.WORKING_VERSION_ID value

    .PARAMETER ModificationDate
        MODIFICATIONDATE_DA_ value

    .PARAMETER CheckoutDate
        When checkout occurred (best effort)

    .PARAMETER WriteSources
        Array of tables/fields proving write (e.g., "OPERATION_.MODIFICATIONDATE_DA_")

    .PARAMETER JoinSources
        Array of tables/fields used for joins (informational only)

    .PARAMETER DeltaSummary
        Hashtable with delta details: kind, fields, maxAbsDelta, before, after

    .PARAMETER SnapshotComparison
        Hashtable from snapshot diff: hasWrite, hasDelta, changes

    .OUTPUTS
        Hashtable with complete evidence block
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ObjectId,

        [Parameter(Mandatory=$true)]
        [string]$ObjectType,

        [string]$ProxyOwnerId = $null,
        [string]$ProxyOwnerName = $null,
        [string]$LastModifiedBy = $null,
        [int]$CheckoutWorkingVersionId = 0,
        [datetime]$ModificationDate = [datetime]::MinValue,
        [datetime]$CheckoutDate = [datetime]::MinValue,
        [string[]]$WriteSources = @(),
        [string[]]$JoinSources = @(),
        [hashtable]$DeltaSummary = $null,
        [hashtable]$SnapshotComparison = $null
    )

    # Determine evidence flags
    $hasCheckout = $CheckoutWorkingVersionId -gt 0

    $hasWrite = $false
    if ($SnapshotComparison -and $SnapshotComparison.ContainsKey('hasWrite')) {
        $hasWrite = $SnapshotComparison.hasWrite
    } elseif ($WriteSources.Count -gt 0) {
        $hasWrite = $true
    }

    $hasDelta = $false
    if ($SnapshotComparison -and $SnapshotComparison.ContainsKey('hasDelta')) {
        $hasDelta = $SnapshotComparison.hasDelta
    } elseif ($DeltaSummary -and $DeltaSummary.ContainsKey('maxAbsDelta')) {
        $hasDelta = $DeltaSummary.maxAbsDelta -gt 0
    }

    # Attribution strength
    $attributionStrength = Get-AttributionStrength `
        -ProxyOwnerName $ProxyOwnerName `
        -LastModifiedBy $LastModifiedBy `
        -CheckoutTimestamp $CheckoutDate `
        -ModificationTimestamp $ModificationDate

    # Confidence classification
    $confidence = Get-Confidence `
        -HasCheckout $hasCheckout `
        -HasWrite $hasWrite `
        -HasDelta $hasDelta `
        -AttributionStrength $attributionStrength

    # Build evidence block
    $evidence = [ordered]@{
        hasCheckout = $hasCheckout
        hasWrite = $hasWrite
        hasDelta = $hasDelta
        attributionStrength = $attributionStrength
        confidence = $confidence
    }

    # Optional fields (only include if present)
    if ($ProxyOwnerId) {
        $evidence.proxyOwnerId = $ProxyOwnerId
    }

    if ($ProxyOwnerName) {
        $evidence.proxyOwnerName = $ProxyOwnerName
    }

    if ($LastModifiedBy) {
        $evidence.lastModifiedBy = $LastModifiedBy
    }

    if ($CheckoutWorkingVersionId -gt 0) {
        $evidence.checkoutWorkingVersionId = $CheckoutWorkingVersionId
    }

    if ($WriteSources.Count -gt 0) {
        $evidence.writeSources = $WriteSources
    }

    if ($JoinSources.Count -gt 0) {
        $evidence.joinSources = $JoinSources
    }

    if ($DeltaSummary) {
        $evidence.deltaSummary = $DeltaSummary
    }

    if ($SnapshotComparison) {
        $evidence.snapshotComparison = $SnapshotComparison
    }

    return $evidence
}

function Get-WriteSourceViolations {
    <#
    .SYNOPSIS
        Returns writeSources entries that are not valid write indicators.
    #>
    param(
        [string[]]$WriteSources
    )

    if (-not $WriteSources -or $WriteSources.Count -eq 0) {
        return @()
    }

    $violations = @()
    foreach ($entry in $WriteSources) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        if ($entry -match '\.OBJECT_ID$' -or $entry -match '(^|\.)(ID|PUID)$') {
            $violations += $entry
            continue
        }
    }

    return $violations
}

function Test-WriteSourcesValid {
    <#
    .SYNOPSIS
        Validates that writeSources contain only write-indicator columns.
    #>
    param(
        [string[]]$WriteSources
    )

    $violations = Get-WriteSourceViolations -WriteSources $WriteSources
    return $violations.Count -eq 0
}

function Test-EvidenceWriteSources {
    <#
    .SYNOPSIS
        Validates evidence writeSources when hasWrite is true.
    #>
    param(
        [hashtable]$Evidence
    )

    if (-not $Evidence) {
        return $false
    }

    if (-not $Evidence.hasWrite) {
        return $true
    }

    if (-not $Evidence.ContainsKey('writeSources')) {
        return $false
    }

    return Test-WriteSourcesValid -WriteSources $Evidence.writeSources
}

function Test-EvidenceQuality {
    <#
    .SYNOPSIS
        Validates evidence block quality and returns diagnostic info.

    .PARAMETER Evidence
        Evidence block from New-EvidenceBlock

    .OUTPUTS
        Hashtable with isValid, warnings, recommendations
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Evidence
    )

    $warnings = @()
    $recommendations = @()

    # Check for confirmed work without all fields
    if ($Evidence.confidence -eq "confirmed" -and -not $Evidence.ContainsKey('proxyOwnerName')) {
        $warnings += "Confirmed work missing proxyOwnerName"
    }

    if ($Evidence.confidence -eq "confirmed" -and -not $Evidence.ContainsKey('lastModifiedBy')) {
        $warnings += "Confirmed work missing lastModifiedBy"
    }

    # Check for weak attribution
    if ($Evidence.attributionStrength -eq "weak" -and $Evidence.hasWrite) {
        $recommendations += "Consider enhancing queries to include LASTMODIFIEDBY_S_ field"
    }

    # Check for invalid writeSources entries
    if ($Evidence.ContainsKey('writeSources')) {
        $invalidWriteSources = Get-WriteSourceViolations -WriteSources $Evidence.writeSources
        if ($invalidWriteSources.Count -gt 0) {
            $warnings += "writeSources contains non-write indicators: $($invalidWriteSources -join ', ')"
        }
    }

    if ($Evidence.hasWrite -and -not (Test-EvidenceWriteSources -Evidence $Evidence)) {
        $warnings += "hasWrite=true but writeSources missing or invalid"
    }

    # Check for checkout without delta
    if ($Evidence.confidence -eq "checkout_only") {
        $recommendations += "Object checked out but unchanged - possible stale checkout"
    }

    # Check for unattributed work
    if ($Evidence.confidence -eq "unattributed" -and ($Evidence.hasWrite -or $Evidence.hasDelta)) {
        $warnings += "Real work detected but attribution missing or contradictory"
    }

    return @{
        isValid = $true
        warnings = $warnings
        recommendations = $recommendations
        qualityScore = switch ($Evidence.confidence) {
            "confirmed" { 100 }
            "likely" { 75 }
            "checkout_only" { 50 }
            "unattributed" { 25 }
            default { 0 }
        }
    }
}

