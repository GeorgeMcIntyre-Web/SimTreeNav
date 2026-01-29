<#
.SYNOPSIS
    Snapshot-based change detection for proving "what changed" between runs.

.DESCRIPTION
    Creates and compares snapshots of database state to provide bulletproof
    evidence of changes. Tracks:
    - Object metadata (id, type, modDate, lastModifiedBy)
    - Movement vectors (x, y, z coords)
    - Operation counts and relationships
    - Stable hashes for quick diff detection

.NOTES
    Snapshot files: output/management-snapshot-{Schema}-{ProjectId}.json
    Format: Array of state vectors with record hashes
#>

function New-SnapshotRecord {
    <#
    .SYNOPSIS
        Creates a snapshot record for a single object.

    .PARAMETER ObjectId
        Object ID from database

    .PARAMETER ObjectType
        Type (Study, Resource, Operation, Part, etc.)

    .PARAMETER ModificationDate
        MODIFICATIONDATE_DA_ value

    .PARAMETER LastModifiedBy
        LASTMODIFIEDBY_S_ value

    .PARAMETER Coordinates
        Hashtable with x, y, z values (optional)

    .PARAMETER OperationCounts
        Hashtable with operation-related counts (optional)

    .PARAMETER Metadata
        Additional metadata to include (optional)

    .OUTPUTS
        Hashtable with snapshot record including stable hash
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ObjectId,

        [Parameter(Mandatory=$true)]
        [string]$ObjectType,

        [datetime]$ModificationDate = [datetime]::MinValue,
        [string]$LastModifiedBy = "",
        [hashtable]$Coordinates = $null,
        [hashtable]$OperationCounts = $null,
        [hashtable]$Metadata = $null
    )

    $record = [ordered]@{
        objectId = $ObjectId
        objectType = $ObjectType
        modificationDate = if ($ModificationDate -ne [datetime]::MinValue) {
            $ModificationDate.ToString('yyyy-MM-ddTHH:mm:ss')
        } else { $null }
        lastModifiedBy = $LastModifiedBy
    }

    if ($Coordinates) {
        $record.coordinates = [ordered]@{
            x = $Coordinates.x
            y = $Coordinates.y
            z = $Coordinates.z
        }
    }

    if ($OperationCounts) {
        $record.operationCounts = $OperationCounts
    }

    if ($Metadata) {
        $record.metadata = $Metadata
    }

    $coordString = ""
    if ($Coordinates) {
        $coordString = @(
            [string]$Coordinates.x,
            [string]$Coordinates.y,
            [string]$Coordinates.z
        ) -join ','
    }

    $opCountsString = ""
    if ($OperationCounts) {
        $opCountsString = $OperationCounts | ConvertTo-Json -Compress -Depth 3
    }

    # Compute stable hash of record (for quick diff detection)
    $hashInput = @(
        $ObjectId,
        $ObjectType,
        $record.modificationDate,
        $LastModifiedBy,
        $coordString,
        $opCountsString
    ) -join '|'

    $hash = Get-StringHash -InputString $hashInput
    $record.recordHash = $hash

    return $record
}

function Get-StringHash {
    <#
    .SYNOPSIS
        Computes SHA256 hash of a string.

    .PARAMETER InputString
        String to hash

    .OUTPUTS
        Hex string of hash (first 16 chars for brevity)
    #>
    param(
        [string]$InputString
    )

    if ([string]::IsNullOrWhiteSpace($InputString)) {
        return "0000000000000000"
    }

    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $hashBytes = $hasher.ComputeHash($bytes)
    $hashHex = [System.BitConverter]::ToString($hashBytes).Replace('-', '')

    # Return first 16 chars for brevity
    return $hashHex.Substring(0, 16)
}

function Save-Snapshot {
    <#
    .SYNOPSIS
        Saves snapshot records to JSON file.

    .PARAMETER SnapshotRecords
        Array of snapshot records from New-SnapshotRecord

    .PARAMETER OutputPath
        Path to save snapshot JSON

    .PARAMETER Schema
        Database schema name

    .PARAMETER ProjectId
        Project ID

    .OUTPUTS
        Path to saved snapshot file
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$SnapshotRecords,

        [string]$OutputPath = "",
        [string]$Schema = "",
        [string]$ProjectId = ""
    )

    # Determine output path
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Get-SnapshotPath -Schema $Schema -ProjectId $ProjectId
    }

    # Build snapshot document
    $snapshot = @{
        schemaVersion = "1.0.0"
        schema = $Schema
        projectId = $ProjectId
        generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        recordCount = $SnapshotRecords.Count
        records = $SnapshotRecords
    }

    # Save to file
    $snapshot | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8

    Write-Output $OutputPath
}

function Read-Snapshot {
    <#
    .SYNOPSIS
        Loads snapshot from JSON file.

    .PARAMETER SnapshotPath
        Path to snapshot JSON file

    .OUTPUTS
        Hashtable with schema, projectId, generatedAt, records array
        Returns $null if file doesn't exist or is corrupt
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SnapshotPath
    )

    if (-not (Test-Path $SnapshotPath)) {
        Write-Verbose "Snapshot not found: $SnapshotPath (first run)"
        return $null
    }

    try {
        $content = Get-Content -Path $SnapshotPath -Raw -ErrorAction Stop
        $snapshot = $content | ConvertFrom-Json -ErrorAction Stop

        # Validate schema
        if (-not $snapshot.PSObject.Properties['records']) {
            Write-Warning "Snapshot missing 'records' field: $SnapshotPath"
            return $null
        }

        return $snapshot
    }
    catch {
        Write-Warning "Failed to load snapshot: $SnapshotPath - $_"
        return $null
    }
}

function Compare-Snapshots {
    <#
    .SYNOPSIS
        Compares new record against previous snapshot to detect changes.

    .PARAMETER ObjectId
        Object ID to compare

    .PARAMETER NewRecord
        New snapshot record from New-SnapshotRecord

    .PARAMETER PreviousSnapshot
        Previous snapshot from Read-Snapshot

    .PARAMETER CoordinateEpsilon
        Minimum coordinate change to consider meaningful (default: 1mm)

    .OUTPUTS
        Hashtable with: hasWrite, hasDelta, changes array, previous record
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ObjectId,

        [Parameter(Mandatory=$true)]
        [hashtable]$NewRecord,

        [object]$PreviousSnapshot = $null,
        [double]$CoordinateEpsilon = 1.0
    )

    $result = @{
        hasWrite = $false
        hasDelta = $false
        changes = @()
        previousRecord = $null
    }

    # If no previous snapshot, treat as first run (baseline)
    if (-not $PreviousSnapshot) {
        return $result
    }

    # Find previous record for this object
    $previousRecord = $PreviousSnapshot.records | Where-Object { $_.objectId -eq $ObjectId } | Select-Object -First 1

    if (-not $previousRecord) {
        # New object (wasn't in previous snapshot)
        $result.hasWrite = $true
        $result.hasDelta = $true
        $result.changes += "New object (first appearance)"
        return $result
    }

    $result.previousRecord = $previousRecord

    # Check for record hash change (quick check)
    if ($NewRecord.recordHash -ne $previousRecord.recordHash) {
        $result.hasWrite = $true
    }

    # Check modification date change
    if ($NewRecord.modificationDate -and $previousRecord.modificationDate -and
        $NewRecord.modificationDate -ne $previousRecord.modificationDate) {
        $result.hasWrite = $true
        $result.changes += "Modification date changed: $($previousRecord.modificationDate) -> $($NewRecord.modificationDate)"
    }

    # Check lastModifiedBy change
    if ($NewRecord.lastModifiedBy -and $previousRecord.lastModifiedBy -and
        $NewRecord.lastModifiedBy -ne $previousRecord.lastModifiedBy) {
        $result.hasWrite = $true
        $result.changes += "Last modified by changed: $($previousRecord.lastModifiedBy) -> $($NewRecord.lastModifiedBy)"
    }

    # Check coordinate changes (movement delta)
    if ($NewRecord.coordinates -and $previousRecord.coordinates) {
        $deltaX = [Math]::Abs($NewRecord.coordinates.x - $previousRecord.coordinates.x)
        $deltaY = [Math]::Abs($NewRecord.coordinates.y - $previousRecord.coordinates.y)
        $deltaZ = [Math]::Abs($NewRecord.coordinates.z - $previousRecord.coordinates.z)

        $maxDelta = [Math]::Max([Math]::Max($deltaX, $deltaY), $deltaZ)

        if ($maxDelta -gt $CoordinateEpsilon) {
            $result.hasDelta = $true
            $result.changes += "Coordinates changed: max delta = $([Math]::Round($maxDelta, 2))mm"
        }
    }

    # Check operation count changes
    $newOpCounts = Convert-PSObjectToHashtable -InputObject $NewRecord.operationCounts
    $prevOpCounts = Convert-PSObjectToHashtable -InputObject $previousRecord.operationCounts
    if ($newOpCounts -and $prevOpCounts) {
        foreach ($key in $newOpCounts.Keys) {
            if ($prevOpCounts.ContainsKey($key)) {
                $oldVal = $prevOpCounts[$key]
                $newVal = $newOpCounts[$key]

                if ($oldVal -ne $newVal) {
                    $result.hasDelta = $true
                    $result.changes += "$key changed: $oldVal -> $newVal"
                }
            }
            else {
                # New count field
                $result.hasDelta = $true
                $result.changes += "$key added: $($newOpCounts[$key])"
            }
        }
    }

    return $result
}

function Get-SnapshotPath {
    <#
    .SYNOPSIS
        Returns standard snapshot path for schema/project.

    .PARAMETER Schema
        Database schema name

    .PARAMETER ProjectId
        Project ID

    .PARAMETER OutputDir
        Base output directory (default: data/output)

    .OUTPUTS
        Full path to snapshot JSON file
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Schema,

        [Parameter(Mandatory=$true)]
        [string]$ProjectId,

        [string]$OutputDir = ""
    )

    if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        $baseDir = Join-Path $PSScriptRoot "..\..\data\output"
        $OutputDir = [System.IO.Path]::GetFullPath($baseDir)
    }

    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    return Join-Path $OutputDir "management-snapshot-$Schema-$ProjectId.json"
}

function Convert-PSObjectToHashtable {
    <#
    .SYNOPSIS
        Normalizes PSCustomObject or Hashtable to Hashtable.
    #>
    param(
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [hashtable]) {
        return $InputObject
    }

    $table = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        $table[$prop.Name] = $prop.Value
    }

    return $table
}
