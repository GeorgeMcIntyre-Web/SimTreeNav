# Get Management Reporting Data
# Purpose: Query database for all management reporting data across 5 work types
# Date: 2026-01-19

param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ProjectId,

    [DateTime]$StartDate = (Get-Date).AddDays(-7),
    [DateTime]$EndDate = (Get-Date),

    [string]$OutputFile = "management-data-${Schema}-${ProjectId}.json"
)

# Start timer
$scriptTimer = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Management Reporting Data Collection" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TNS:        $TNSName" -ForegroundColor Gray
Write-Host "  Schema:     $Schema" -ForegroundColor Gray
Write-Host "  Project ID: $ProjectId" -ForegroundColor Gray
Write-Host "  Date Range: $($StartDate.ToString('yyyy-MM-dd')) to $($EndDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
Write-Host ""

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "..\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
} else {
    Write-Warning "Credential manager not found. Using default password."
}

# Import evidence and snapshot libraries
$evidenceLibPath = Join-Path $PSScriptRoot "..\..\..\scripts\lib\EvidenceClassifier.ps1"
if (Test-Path $evidenceLibPath) {
    . $evidenceLibPath
} else {
    Write-Warning "Evidence classifier not found: $evidenceLibPath"
}

$treeEvidenceLibPath = Join-Path $PSScriptRoot "..\utilities\TreeEvidenceClassifier.ps1"
if (Test-Path $treeEvidenceLibPath) {
    . $treeEvidenceLibPath
} else {
    Write-Warning "Tree evidence classifier not found: $treeEvidenceLibPath"
}

$snapshotLibPath = Join-Path $PSScriptRoot "..\..\..\scripts\lib\SnapshotManager.ps1"
if (Test-Path $snapshotLibPath) {
    . $snapshotLibPath
} else {
    Write-Warning "Snapshot manager not found: $snapshotLibPath"
}

$enrichmentLibPath = Join-Path $PSScriptRoot "..\..\..\scripts\lib\WorkflowEnrichment.ps1"
if (Test-Path $enrichmentLibPath) {
    . $enrichmentLibPath
} else {
    Write-Warning "Workflow enrichment library not found: $enrichmentLibPath"
}

# Format dates for SQL
$startDateStr = $StartDate.ToString('yyyy-MM-dd')
$endDateStr = $EndDate.ToString('yyyy-MM-dd')

# Initialize results object
$results = @{
    metadata = @{
        schemaVersion = "1.3.0"
        schema = $Schema
        projectId = $ProjectId
        startDate = $startDateStr
        endDate = $endDateStr
        generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
    projectDatabase = @()
    resourceLibrary = @()
    partLibrary = @()
    ipaAssembly = @()
    studySummary = @()
    studyResources = @()
    studyPanels = @()
    studyOperations = @()
    studyMovements = @()
    studyWelds = @()
    userActivity = @()
    events = @()
    treeChanges = @()
    studyHealth = @{
        summary = @{
            totalStudies = 0
            totalIssues = 0
            criticalIssues = 0
            highIssues = 0
            mediumIssues = 0
            lowIssues = 0
        }
        issues = @()
        suspicious = @()
        renameSuggestions = @()
    }
    resourceConflicts = @()
    staleCheckouts = @()
    bottleneckQueue = @()
}

# Parse SQL*Plus pipe-delimited output into objects for JSON conversion.
function Convert-PipeDelimitedToObjects {
    param(
        [string[]]$Lines
    )

    $lineList = @($Lines)

    if (-not $lineList -or $lineList.Count -lt 2) {
        return @()
    }

    $filtered = $lineList | Where-Object {
        $_ -match '\|' -and ($_ -notmatch '^[\s\-\|]+$')
    }
    $filtered = @($filtered)

    if ($filtered.Count -lt 2) {
        return @()
    }

    $headers = $filtered[0] -split '\|'
    $headers = $headers | ForEach-Object { $_.Trim() }

    $objects = foreach ($line in $filtered[1..($filtered.Count - 1)]) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $values = $line -split '\|', $headers.Count
        $obj = [ordered]@{}

        for ($i = 0; $i -lt $headers.Count; $i++) {
            $header = $headers[$i]
            if ([string]::IsNullOrWhiteSpace($header)) {
                $header = "Column$($i + 1)"
            }

            $value = if ($i -lt $values.Count) { $values[$i].Trim() } else { "" }
            $obj[$header] = $value
        }

        [PSCustomObject]$obj
    }

    return $objects
}

function Convert-StringToDateTime {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [datetime]::MinValue
    }

    $parsed = [datetime]::MinValue
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::AssumeLocal

    if ([datetime]::TryParseExact($Value, 'yyyy-MM-dd HH:mm:ss', $culture, $styles, [ref]$parsed)) {
        return $parsed
    }

    if ([datetime]::TryParse($Value, $culture, $styles, [ref]$parsed)) {
        return $parsed
    }

    return [datetime]::MinValue
}

function Test-DateInRange {
    param(
        [datetime]$Value,
        [datetime]$Start,
        [datetime]$End
    )

    if ($Value -eq [datetime]::MinValue) {
        return $false
    }

    return ($Value -ge $Start -and $Value -le $End)
}

function New-SnapshotEvidence {
    param(
        [hashtable]$SnapshotComparison
    )

    if (-not $SnapshotComparison) {
        return $null
    }

    return @{
        hasWrite = $SnapshotComparison.hasWrite
        hasDelta = $SnapshotComparison.hasDelta
        changes = $SnapshotComparison.changes
    }
}

function New-DefaultEvidence {
    return @{
        hasCheckout = $false
        hasWrite = $false
        hasDelta = $false
        attributionStrength = "weak"
        confidence = "unattributed"
    }
}

function Ensure-EvidenceBlock {
    param(
        [hashtable]$Evidence
    )

    if (-not $Evidence) {
        return New-DefaultEvidence
    }

    $defaultEvidence = New-DefaultEvidence
    foreach ($key in $defaultEvidence.Keys) {
        if (-not $Evidence.ContainsKey($key)) {
            $Evidence[$key] = $defaultEvidence[$key]
        }
    }

    return $Evidence
}

if (-not (Get-Command -Name New-CoordinateDeltaSummary -ErrorAction SilentlyContinue)) {
    function New-CoordinateDeltaSummary {
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
            kind = "movement"
            fields = @("x", "y", "z")
            maxAbsDelta = $maxDelta
            before = $PreviousRecord.coordinates
            after = $NewRecord.coordinates
            delta = @{ x = $dx; y = $dy; z = $dz }
        }
    }
}

if (-not (Get-Command -Name New-AllocationDeltaSummary -ErrorAction SilentlyContinue)) {
    function New-AllocationDeltaSummary {
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

        $fields = @()
        if ($SnapshotComparison.changes -and $SnapshotComparison.changes.Count -gt 0) {
            $fields = $SnapshotComparison.changes
        }

        if ($fields.Count -eq 0) {
            $fields = @("operation")
        }

        $before = $null
        if ($SnapshotComparison.previousRecord -and $SnapshotComparison.previousRecord.PSObject.Properties['metadata']) {
            $before = $SnapshotComparison.previousRecord.metadata
        }

        $after = $null
        if ($NewRecord -and $NewRecord.metadata) {
            $after = $NewRecord.metadata
        }

        return @{
            kind = "allocation"
            fields = $fields
            before = $before
            after = $after
        }
    }
}

if (-not (Get-Command -Name New-LibraryDeltaSummary -ErrorAction SilentlyContinue)) {
    function New-LibraryDeltaSummary {
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
        $kind = if ($isNew) { "libraryAdd" } else { "libraryChange" }

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
            fields = @("record")
            before = $before
            after = $after
        }
    }
}

function Normalize-WorkTypeSafe {
    param(
        [string]$WorkType,
        [string]$ObjectType = "",
        [string]$Category = ""
    )

    if (Get-Command -Name Normalize-WorkType -ErrorAction SilentlyContinue) {
        $normalized = Normalize-WorkType -WorkType $WorkType -ObjectType $ObjectType -Category $Category
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            return $normalized
        }

        Write-Warning "Unknown workType '$WorkType' - falling back to original value"
        return $WorkType
    }

    return $WorkType
}

function Test-FileLocked {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        $stream.Close()
        return $false
    } catch {
        return $true
    }
}

# Helper function to execute SQL query
function Execute-Query {
    param(
        [string]$QueryName,
        [string]$Query
    )

    Write-Host "  Querying $QueryName..." -ForegroundColor Yellow

    try {
        # Create temp SQL file
        $tempSqlFile = Join-Path $env:TEMP "${QueryName}-${Schema}-${ProjectId}.sql"

        # Wrap query with SQL*Plus settings
        $sqlScript = @'
SET PAGESIZE 50000
SET LINESIZE 32767
SET FEEDBACK OFF
SET HEADING ON
SET VERIFY OFF
SET COLSEP '|'
SET TRIMSPOOL ON
SET WRAP OFF

##QUERY##

EXIT;
'@
        $sqlScript = $sqlScript.Replace('##QUERY##', $Query)

        $sqlScript | Out-File $tempSqlFile -Encoding ASCII

        # Execute query
        $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop

        if ($connectionString) {
            # Execute query directly (same method as other working scripts)
            # Use job with timeout to prevent hanging
            $timeoutSeconds = 60  # Increased timeout for complex queries
            $job = Start-Job -ScriptBlock {
                param($connStr, $sqlFile)
                $result = & sqlplus -S $connStr "@$sqlFile" 2>&1
                return $result
            } -ArgumentList $connectionString, $tempSqlFile
            
            $completed = Wait-Job $job -Timeout $timeoutSeconds
            
            if (-not $completed) {
                Stop-Job $job -ErrorAction SilentlyContinue
                Remove-Job $job -Force -ErrorAction SilentlyContinue
                Write-Warning "    Query timed out after $timeoutSeconds seconds - skipping"
                Remove-Item $tempSqlFile -ErrorAction SilentlyContinue
                return @()
            }
            
            $result = Receive-Job $job
            Remove-Job $job -Force -ErrorAction SilentlyContinue

            if (-not $result) {
                Write-Warning "    No results returned"
                Remove-Item $tempSqlFile -ErrorAction SilentlyContinue
                return @()
            }

            # Parse results
            $data = $result | Where-Object { $_ -match '\|' }
            $objects = Convert-PipeDelimitedToObjects -Lines $data

            # Cleanup
            Remove-Item $tempSqlFile -ErrorAction SilentlyContinue

            Write-Host "    Retrieved $($objects.Count) rows" -ForegroundColor Green
            return $objects
        } else {
            Write-Warning "    Failed to get connection string"
            return @()
        }
    }
    catch {
        Write-Warning "    Error: $_"
        return @()
    }
}

# QUERY 1: Project Database Activity
Write-Host "`n[1/14] Project Database Setup" -ForegroundColor Cyan

$query1 = @'
SELECT
    'PROJECT_DATABASE' as work_type,
    c.OBJECT_ID as object_id,
    c.CAPTION_S_ as object_name,
    'Project' as object_type,
    c.CREATEDBY_S_ as created_by,
    TO_CHAR(c.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    c.LASTMODIFIEDBY_S_ as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM ##SCHEMA##.COLLECTION_ c
LEFT JOIN ##SCHEMA##.PROXY p ON c.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE c.OBJECT_ID = ##PROJECTID##;
'@
$query1 = $query1.Replace('##SCHEMA##', $Schema).Replace('##PROJECTID##', $ProjectId).Replace('##STARTDATE##', $startDateStr)
$results.projectDatabase = Execute-Query -QueryName "ProjectDatabase" -Query $query1

# QUERY 2: Resource Library Activity
Write-Host "`n[2/14] Resource Library" -ForegroundColor Cyan

$query2 = @'
SELECT
    'RESOURCE_LIBRARY' as work_type,
    r.OBJECT_ID as object_id,
    r.NAME_S_ as object_name,
    cd.NICE_NAME as object_type,
    NVL(r.CREATEDBY_S_, '') as created_by,
    TO_CHAR(r.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(r.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM ##SCHEMA##.RESOURCE_ r
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE (r.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  OR p.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY r.MODIFICATIONDATE_DA_ DESC;
'@
$query2 = $query2.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.resourceLibrary = Execute-Query -QueryName "ResourceLibrary" -Query $query2

# QUERY 3: Part/MFG Library Activity
Write-Host "`n[3/14] Part/MFG Library" -ForegroundColor Cyan

$query3 = @'
SELECT
    'PART_LIBRARY' as work_type,
    p.OBJECT_ID as object_id,
    p.NAME_S_ as object_name,
    cd.NICE_NAME as object_type,
    CASE
        WHEN p.NAME_S_ IN ('CC', 'RCC') THEN 'Cell Coat'
        WHEN p.NAME_S_ = 'RC' THEN 'Robot Coat'
        WHEN p.NAME_S_ = 'SC' THEN 'Spot Coat'
        WHEN p.NAME_S_ = 'CMN' THEN 'Common'
        WHEN p.NAME_S_ IN ('P702', 'P736') THEN 'Build Assembly'
        WHEN REGEXP_LIKE(p.NAME_S_, '^[0-9]+$') THEN 'Level Code'
        ELSE 'Panel/Part'
    END as category,
    NVL(p.CREATEDBY_S_, '') as created_by,
    TO_CHAR(p.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(p.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(pr.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(pr.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM ##SCHEMA##.PART_ p
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY pr ON p.OBJECT_ID = pr.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE (p.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  OR pr.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY p.MODIFICATIONDATE_DA_ DESC;
'@
$query3 = $query3.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.partLibrary = Execute-Query -QueryName "PartLibrary" -Query $query3

# QUERY 4: IPA Assembly Activity
Write-Host "`n[4/14] IPA Assembly" -ForegroundColor Cyan

$query4 = @'
SELECT
    'IPA_ASSEMBLY' as work_type,
    pa.OBJECT_ID as object_id,
    pa.NAME_S_ as object_name,
    'TxProcessAssembly' as object_type,
    NVL(pa.CREATEDBY_S_, '') as created_by,
    TO_CHAR(pa.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(pa.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(pr.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(pr.WORKING_VERSION_ID, 0) as checkout_working_version_id,
    (SELECT COUNT(DISTINCT o.OBJECT_ID)
        FROM ##SCHEMA##.REL_COMMON r
        INNER JOIN ##SCHEMA##.OPERATION_ o ON r.OBJECT_ID = o.OBJECT_ID
        WHERE r.FORWARD_OBJECT_ID = pa.OBJECT_ID) as operation_count
FROM ##SCHEMA##.PART_ pa
LEFT JOIN ##SCHEMA##.PROXY pr ON pa.OBJECT_ID = pr.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE pa.CLASS_ID = 133
  AND (pa.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
    OR pr.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY pa.MODIFICATIONDATE_DA_ DESC;
'@
$query4 = $query4.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.ipaAssembly = Execute-Query -QueryName "IpaAssembly" -Query $query4

# QUERY 5A: Study Summary
Write-Host "`n[5/14] Study Summary" -ForegroundColor Cyan

$query5a = @'
SELECT
    'STUDY_SUMMARY' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    cd.NICE_NAME as study_type,
    NVL(rs.CREATEDBY_S_, '') as created_by,
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(rs.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Active' ELSE 'Idle' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM ##SCHEMA##.ROBCADSTUDY_ rs
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.OBJECT_ID
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE EXISTS (
    SELECT 1 FROM ##SCHEMA##.REL_COMMON r2
    INNER JOIN ##SCHEMA##.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM ##SCHEMA##.REL_COMMON r3
        INNER JOIN ##SCHEMA##.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = ##PROJECTID##
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  )
  AND (rs.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
    OR p.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 50
ORDER BY rs.MODIFICATIONDATE_DA_ DESC;
'@
$query5a = $query5a.Replace('##SCHEMA##', $Schema).Replace('##PROJECTID##', $ProjectId).Replace('##STARTDATE##', $startDateStr)
$results.studySummary = Execute-Query -QueryName "StudySummary" -Query $query5a

# QUERY 5B: Study Resources
Write-Host "`n[6/14] Study Resource Allocation" -ForegroundColor Cyan

$query5b = @'
SELECT
    'STUDY_RESOURCES' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    s.NAME_S_ as shortcut_name,
    NVL(res.NAME_S_, '') as resource_name,
    NVL(cd.NICE_NAME, '') as resource_type,
    CASE
        WHEN s.NAME_S_ = 'LAYOUT' THEN 'Layout Configuration'
        WHEN s.NAME_S_ LIKE '8J-%' AND s.NAME_S_ NOT LIKE '%\_%' ESCAPE '\' THEN 'Station Reference'
        WHEN s.NAME_S_ LIKE '%\_CMN' ESCAPE '\' THEN 'Common Operations'
        WHEN s.NAME_S_ LIKE '%\_SC' ESCAPE '\' THEN 'Spot Coat Operations'
        WHEN s.NAME_S_ LIKE '%\_RC' ESCAPE '\' THEN 'Robot Coat Operations'
        WHEN s.NAME_S_ LIKE '%\_CC' ESCAPE '\' THEN 'Cell Coat Operations'
        ELSE 'Other'
    END as allocation_type
FROM ##SCHEMA##.ROBCADSTUDY_ rs
INNER JOIN ##SCHEMA##.REL_COMMON r_study ON rs.OBJECT_ID = r_study.OBJECT_ID
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN ##SCHEMA##.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN ##SCHEMA##.RESOURCE_ res
    ON (s.LINKEXTERNALID_S_ IS NOT NULL AND s.LINKEXTERNALID_S_ = res.EXTERNALID_S_)
    OR (s.LINKEXTERNALID_S_ IS NULL AND s.NAME_S_ = res.NAME_S_)
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM ##SCHEMA##.REL_COMMON r2
    INNER JOIN ##SCHEMA##.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r_study.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM ##SCHEMA##.REL_COMMON r3
        INNER JOIN ##SCHEMA##.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = ##PROJECTID##
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  )
  AND rs.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 200
ORDER BY rs.NAME_S_, r.SEQ_NUMBER;
'@
$query5b = $query5b.Replace('##SCHEMA##', $Schema).Replace('##PROJECTID##', $ProjectId).Replace('##STARTDATE##', $startDateStr)
$results.studyResources = Execute-Query -QueryName "StudyResources" -Query $query5b

# QUERY 5C: Study Panels
Write-Host "`n[7/14] Study Panel Usage" -ForegroundColor Cyan

$query5c = @'
SELECT
    'STUDY_PANELS' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    s.NAME_S_ as shortcut_name,
    CASE
        WHEN s.NAME_S_ LIKE '%\_CC' ESCAPE '\' THEN 'CC (Cell Coat)'
        WHEN s.NAME_S_ LIKE '%\_RC' ESCAPE '\' THEN 'RC (Robot Coat)'
        WHEN s.NAME_S_ LIKE '%\_SC' ESCAPE '\' THEN 'SC (Spot Coat)'
        WHEN s.NAME_S_ LIKE '%\_CMN' ESCAPE '\' THEN 'CMN (Common)'
        ELSE 'N/A'
    END as panel_code,
    SUBSTR(s.NAME_S_, 1, INSTR(s.NAME_S_, '_') - 1) as station
FROM ##SCHEMA##.ROBCADSTUDY_ rs
INNER JOIN ##SCHEMA##.REL_COMMON r_study ON rs.OBJECT_ID = r_study.OBJECT_ID
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN ##SCHEMA##.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE EXISTS (
    SELECT 1 FROM ##SCHEMA##.REL_COMMON r2
    INNER JOIN ##SCHEMA##.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r_study.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM ##SCHEMA##.REL_COMMON r3
        INNER JOIN ##SCHEMA##.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = ##PROJECTID##
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  )
  AND s.NAME_S_ LIKE '%\_%' ESCAPE '\'
  AND rs.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 200
ORDER BY rs.NAME_S_, s.NAME_S_;
'@
$query5c = $query5c.Replace('##SCHEMA##', $Schema).Replace('##PROJECTID##', $ProjectId).Replace('##STARTDATE##', $startDateStr)
$results.studyPanels = Execute-Query -QueryName "StudyPanels" -Query $query5c

# QUERY 5D: Study Operations
Write-Host "`n[8/14] Study Operations" -ForegroundColor Cyan

$query5d = @'
SELECT
    'STUDY_OPERATIONS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    cd.NICE_NAME as operation_class,
    NVL(o.OPERATIONTYPE_S_, '') as operation_type,
    TO_CHAR(o.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(o.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE
        WHEN o.NAME_S_ LIKE 'PG%' THEN 'Weld Point Group'
        WHEN o.NAME_S_ LIKE 'MOV\_%' ESCAPE '\' THEN 'Movement Operation'
        WHEN o.NAME_S_ LIKE 'tip\_%' ESCAPE '\' THEN 'Tool Maintenance'
        WHEN o.NAME_S_ LIKE '%WELD%' THEN 'Weld Operation'
        ELSE 'Other'
    END as operation_category,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM ##SCHEMA##.OPERATION_ o
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY p ON o.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE (o.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  OR p.WORKING_VERSION_ID > 0)
  AND o.CLASS_ID = 141
  AND ROWNUM <= 100
ORDER BY o.MODIFICATIONDATE_DA_ DESC;
'@
$query5d = $query5d.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.studyOperations = Execute-Query -QueryName "StudyOperations" -Query $query5d

# QUERY 5E: Study Movements
Write-Host "`n[9/14] Study Movement/Location Changes" -ForegroundColor Cyan

$query5e = @'
SELECT
    'STUDY_MOVEMENTS' as work_type,
    sl.OBJECT_ID as studylayout_id,
    sl.STUDYINFO_SR_ as studyinfo_id,
    TO_CHAR(sl.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(sl.LASTMODIFIEDBY_S_, '') as modified_by,
    sl.OBJECT_ID as location_vector_id,
    sl.OBJECT_ID as rotation_vector_id,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 0 THEN TO_NUMBER(vl.DATA) END)
        FROM ##SCHEMA##.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as x_coord,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 1 THEN TO_NUMBER(vl.DATA) END)
        FROM ##SCHEMA##.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as y_coord,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 2 THEN TO_NUMBER(vl.DATA) END)
        FROM ##SCHEMA##.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as z_coord,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM ##SCHEMA##.ROBCADSTUDY_ rs
INNER JOIN ##SCHEMA##.REL_COMMON r_info ON r_info.FORWARD_OBJECT_ID = rs.OBJECT_ID AND r_info.CLASS_ID = 71
INNER JOIN ##SCHEMA##.STUDYLAYOUT_ sl ON sl.STUDYINFO_SR_ = r_info.OBJECT_ID
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.OBJECT_ID
LEFT JOIN ##SCHEMA##.PROXY p ON sl.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE EXISTS (
    SELECT 1 FROM ##SCHEMA##.REL_COMMON r2
    INNER JOIN ##SCHEMA##.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM ##SCHEMA##.REL_COMMON r3
        INNER JOIN ##SCHEMA##.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = ##PROJECTID##
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  )
  AND (sl.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
    OR p.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY sl.MODIFICATIONDATE_DA_ DESC;
'@
$query5e = $query5e.Replace('##SCHEMA##', $Schema).Replace('##PROJECTID##', $ProjectId).Replace('##STARTDATE##', $startDateStr)
$results.studyMovements = Execute-Query -QueryName "StudyMovements" -Query $query5e

# QUERY 5F: Study Welds
Write-Host "`n[10/14] Study Weld Points" -ForegroundColor Cyan

$query5f = @'
SELECT
    'STUDY_WELDS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    TO_CHAR(o.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(o.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM ##SCHEMA##.OPERATION_ o
LEFT JOIN ##SCHEMA##.PROXY p ON o.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE o.CLASS_ID = 141
  AND (o.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
    OR p.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY o.MODIFICATIONDATE_DA_ DESC;
'@
$query5f = $query5f.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.studyWelds = Execute-Query -QueryName "StudyWelds" -Query $query5f

# QUERY 6: User Activity
Write-Host "`n[11/14] User Activity Summary" -ForegroundColor Cyan

$query6 = @'
SELECT
    u.OBJECT_ID as user_id,
    u.CAPTION_S_ as user_name,
    u.NAME_ as username,
    COUNT(DISTINCT p.OBJECT_ID) as objects_total,
    COUNT(DISTINCT CASE WHEN p.WORKING_VERSION_ID > 0 THEN p.OBJECT_ID END) as active_checkouts
FROM ##SCHEMA##.USER_ u
LEFT JOIN ##SCHEMA##.PROXY p ON u.OBJECT_ID = p.OWNER_ID
GROUP BY u.OBJECT_ID, u.CAPTION_S_, u.NAME_
HAVING COUNT(DISTINCT p.OBJECT_ID) > 0
ORDER BY active_checkouts DESC;
'@
$query6 = $query6.Replace('##SCHEMA##', $Schema)
$results.userActivity = Execute-Query -QueryName "UserActivity" -Query $query6

# QUERY 7: Study Health Analysis
Write-Host "`n[12/14] Study Health Analysis" -ForegroundColor Cyan
$query7 = @'
SELECT
    rs.OBJECT_ID as object_id,
    rs.NAME_S_ as study_name,
    cd.NICE_NAME as study_type,
    NVL(rs.CREATEDBY_S_, '') as created_by,
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(rs.LASTMODIFIEDBY_S_, '') as modified_by,
    rs.CLASS_ID as class_id
FROM ##SCHEMA##.ROBCADSTUDY_ rs
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.OBJECT_ID
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM ##SCHEMA##.REL_COMMON r2
    INNER JOIN ##SCHEMA##.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM ##SCHEMA##.REL_COMMON r3
        INNER JOIN ##SCHEMA##.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = ##PROJECTID##
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  )
  AND rs.NAME_S_ IS NOT NULL
ORDER BY rs.NAME_S_;
'@
$query7 = $query7.Replace('##SCHEMA##', $Schema).Replace('##PROJECTID##', $ProjectId)
$allStudies = Execute-Query -QueryName "StudyHealthData" -Query $query7

# Perform health checks on studies
Write-Host "  Analyzing study names for health issues..." -ForegroundColor Yellow

# Load rules from config file
$rulesPath = Join-Path $PSScriptRoot "..\..\..\config\robcad-study-health-rules.json"
$rules = @{
    maxNameLength = 60
    maxWordCount = 8
    illegalChars = @(":", "*", "?", '"', "<", ">", "|")
    junkTokens = @("test", "temp", "asdf", "qwerty", "xxx", "copy")
    junkPhrases = @("new folder", "do not delete", "final_final")
    legacyTokens = @("old", "legacy", "backup", "deprecated", "unused", "archive")
    yearPattern = "(19|20)\d{2}"
}

if (Test-Path $rulesPath) {
    try {
        $rulesJson = Get-Content $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $rules.maxNameLength = $rulesJson.maxNameLength
        $rules.maxWordCount = $rulesJson.maxWordCount
        $rules.illegalChars = $rulesJson.illegalChars
        $rules.junkTokens = $rulesJson.junkTokens
        $rules.junkPhrases = $rulesJson.junkPhrases
        $rules.legacyTokens = $rulesJson.legacyTokens
        $rules.yearPattern = $rulesJson.yearPattern
    } catch {
        Write-Warning "    Could not load rules from $rulesPath, using defaults"
    }
}

$issues = @()
$suspicious = @()
$renameSuggestions = @()

# Helper function to check for illegal characters
function Test-IllegalChars {
    param([string]$Name, [string[]]$IllegalChars)
    foreach ($char in $IllegalChars) {
        if ($Name.Contains($char)) {
            return $true
        }
    }
    return $false
}

# Helper function to extract tokens
function Get-NameTokens {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return @()
    }
    $matches = [regex]::Matches($Name, "[A-Za-z0-9]+")
    return $matches | ForEach-Object { $_.Value.ToLowerInvariant() }
}

# Analyze each study
foreach ($study in $allStudies) {
    $name = $study.study_name

    # Skip if name is null or whitespace
    if ([string]::IsNullOrWhiteSpace($name)) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = ""
            severity = "Critical"
            issue = "empty_name"
            details = "Name is empty or whitespace"
        }
        continue
    }

    # Check for leading/trailing whitespace
    if ($name -ne $name.Trim()) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "Critical"
            issue = "leading_trailing_whitespace"
            details = "Leading or trailing whitespace detected"
        }
    }

    # Check for illegal characters
    if (Test-IllegalChars -Name $name -IllegalChars $rules.illegalChars) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "Critical"
            issue = "illegal_chars"
            details = "Contains illegal characters"
        }
    }

    # Check for junk tokens
    $tokens = Get-NameTokens -Name $name
    $junkFound = @()
    foreach ($junk in $rules.junkTokens) {
        if ($tokens -contains $junk.ToLowerInvariant()) {
            $junkFound += $junk
        }
    }

    # Check for junk phrases
    $nameLower = $name.ToLowerInvariant()
    foreach ($phrase in $rules.junkPhrases) {
        if ($nameLower.Contains($phrase.ToLowerInvariant())) {
            $junkFound += $phrase
        }
    }

    if ($junkFound.Count -gt 0) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "High"
            issue = "junk_tokens"
            details = "Contains placeholder tokens: $($junkFound -join ', ')"
        }
    }

    # Check for hash-like names
    if ($nameLower -match '[0-9a-f]{16,}') {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "High"
            issue = "hash_like_name"
            details = "Looks like a GUID or hash"
        }
    }

    # Check for file path in name
    if ($nameLower -match '([a-z]:\\|\\\\|/home/)') {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "High"
            issue = "file_path_name"
            details = "Contains a file path"
        }
    }

    # Check for legacy markers
    $legacyFound = @()
    foreach ($legacy in $rules.legacyTokens) {
        if ($tokens -contains $legacy.ToLowerInvariant()) {
            $legacyFound += $legacy
        }
    }

    # Check for year stamp
    if ($nameLower -match $rules.yearPattern) {
        $legacyFound += "year_stamp"
    }

    if ($legacyFound.Count -gt 0) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "High"
            issue = "legacy_markers"
            details = "Contains legacy markers: $($legacyFound -join ', ')"
        }
    }

    # Check for overlong name
    if ($name.Length -gt $rules.maxNameLength) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "Low"
            issue = "overlong_name"
            details = "Length $($name.Length) exceeds $($rules.maxNameLength)"
        }
    }

    # Check for too many words
    $wordTokens = ($name.Trim() -split '\s+') | Where-Object { $_ }
    if ($wordTokens.Count -gt $rules.maxWordCount) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "Low"
            issue = "too_many_tokens"
            details = "Word count $($wordTokens.Count) exceeds $($rules.maxWordCount)"
        }
    }
}

# Calculate summary statistics
$results.studyHealth.summary.totalStudies = $allStudies.Count
$results.studyHealth.summary.totalIssues = $issues.Count
$results.studyHealth.summary.criticalIssues = @($issues | Where-Object { $_.severity -eq "Critical" }).Count
$results.studyHealth.summary.highIssues = @($issues | Where-Object { $_.severity -eq "High" }).Count
$results.studyHealth.summary.mediumIssues = @($issues | Where-Object { $_.severity -eq "Medium" }).Count
$results.studyHealth.summary.lowIssues = @($issues | Where-Object { $_.severity -eq "Low" }).Count

# Add to results
$results.studyHealth.issues = $issues
$results.studyHealth.suspicious = $suspicious
$results.studyHealth.renameSuggestions = $renameSuggestions

Write-Host "Analyzed $($allStudies.Count) studies, found $($issues.Count) issues" -ForegroundColor Green
Write-Host "      Critical: $($results.studyHealth.summary.criticalIssues), High: $($results.studyHealth.summary.highIssues), Medium: $($results.studyHealth.summary.mediumIssues), Low: $($results.studyHealth.summary.lowIssues)" -ForegroundColor Gray
# QUERY 7: Resource Conflicts
Write-Host "`n[13/14] Resource Conflict Detection" -ForegroundColor Cyan
$query7 = @'
SELECT
    r.NAME_S_ as resource_name,
    r.OBJECT_ID as resource_id,
    cd.NICE_NAME as resource_type,
    COUNT(DISTINCT rs.OBJECT_ID) as study_count,
    LISTAGG(rs.NAME_S_, ', ') WITHIN GROUP (ORDER BY rs.NAME_S_) as studies_using_resource
FROM ##SCHEMA##.SHORTCUT_ s
INNER JOIN ##SCHEMA##.RESOURCE_ r ON s.NAME_S_ = r.NAME_S_
INNER JOIN ##SCHEMA##.REL_COMMON rc ON s.OBJECT_ID = rc.OBJECT_ID
INNER JOIN ##SCHEMA##.ROBCADSTUDY_ rs ON rc.FORWARD_OBJECT_ID = rs.OBJECT_ID
INNER JOIN ##SCHEMA##.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
WHERE p.WORKING_VERSION_ID > 0
GROUP BY r.NAME_S_, r.OBJECT_ID, cd.NICE_NAME
HAVING COUNT(DISTINCT rs.OBJECT_ID) > 1
ORDER BY study_count DESC;
'@
$query7 = $query7.Replace('##SCHEMA##', $Schema)
$conflicts = Execute-Query -QueryName "ResourceConflicts" -Query $query7

# Add risk level classification
$results.resourceConflicts = $conflicts | ForEach-Object {
    $studyCount = [int]$_.study_count
    $riskLevel = if ($studyCount -ge 3) { "Critical" } elseif ($studyCount -eq 2) { "High" } else { "Medium" }

    [PSCustomObject]@{
        resource_name = $_.resource_name
        resource_id = $_.resource_id
        resource_type = $_.resource_type
        study_count = $studyCount
        studies = $_.studies_using_resource
        risk_level = $riskLevel
    }
}

# QUERY 8: Stale Checkouts (>72 hours)
Write-Host "`n[14/14] Stale Checkout Detection" -ForegroundColor Cyan
$query8 = @'
SELECT
    c.OBJECT_ID as object_id,
    c.CAPTION_S_ as object_name,
    cd.NICE_NAME as object_type,
    c.MODIFICATIONDATE_DA_ as last_modified,
    u.CAPTION_S_ as checked_out_by,
    u.OBJECT_ID as user_id,
    ROUND((SYSDATE - c.MODIFICATIONDATE_DA_) * 24, 1) as checkout_duration_hours,
    ROUND((SYSDATE - c.MODIFICATIONDATE_DA_), 1) as checkout_duration_days
FROM ##SCHEMA##.COLLECTION_ c
INNER JOIN ##SCHEMA##.PROXY p ON c.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE p.WORKING_VERSION_ID > 0
  AND c.MODIFICATIONDATE_DA_ < SYSDATE - 3
ORDER BY checkout_duration_hours DESC;
'@
$query8 = $query8.Replace('##SCHEMA##', $Schema)
$staleCheckouts = Execute-Query -QueryName "StaleCheckouts" -Query $query8

# Add severity classification
$results.staleCheckouts = $staleCheckouts | ForEach-Object {
    $hours = [double]$_.checkout_duration_hours
    $days = [double]$_.checkout_duration_days
    $severity = if ($hours -ge 168) { "Critical" } elseif ($hours -ge 120) { "High" } elseif ($hours -ge 72) { "Medium" } else { "Low" }

    [PSCustomObject]@{
        object_id = $_.object_id
        object_name = $_.object_name
        object_type = $_.object_type
        last_modified = $_.last_modified
        checked_out_by = $_.checked_out_by
        user_id = $_.user_id
        checkout_duration_hours = $hours
        checkout_duration_days = $days
        severity = $severity
        flagged = ($hours -ge 72)
    }
}

# Create bottleneck queue (group by user)
$results.bottleneckQueue = $results.staleCheckouts |
    Where-Object { $_.flagged } |
    Group-Object -Property checked_out_by |
    ForEach-Object {
        [PSCustomObject]@{
            user_name = $_.Name
            checkout_count = $_.Count
            total_hours = ($_.Group | Measure-Object -Property checkout_duration_hours -Sum).Sum
            items = $_.Group | ForEach-Object {
                [PSCustomObject]@{
                    object_name = $_.object_name
                    object_type = $_.object_type
                    duration_hours = $_.checkout_duration_hours
                }
            }
        }
    } |
    Sort-Object -Property total_hours -Descending

Write-Host "Found $($results.resourceConflicts.Count) resource conflicts" -ForegroundColor Green
Write-Host "Found $($results.staleCheckouts.Count) stale checkouts (>72 hours)" -ForegroundColor Green
Write-Host "Identified $($results.bottleneckQueue.Count) users with stale checkouts" -ForegroundColor Green

# ========================================
# Tree Snapshot Collection
# ========================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Tree Snapshot Collection" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$treeEvidence = @()
$treeEvidenceEnabled = $false
if (Get-Command -Name New-TreeEvidenceBlock -ErrorAction SilentlyContinue) {
    $treeEvidenceEnabled = $true
} else {
    Write-Warning "Tree evidence classifier not available; tree changes will be raw."
}

$treeSnapshotDir = Join-Path (Get-Location).Path "data\\tree-snapshots"
if (-not (Test-Path $treeSnapshotDir)) {
    New-Item -ItemType Directory -Path $treeSnapshotDir -Force | Out-Null
}

$treeExportScript = Join-Path $PSScriptRoot "..\..\..\scripts\debug\export-study-tree-snapshot.ps1"
$treeDiffScript = Join-Path $PSScriptRoot "..\..\..\scripts\debug\compare-study-tree-snapshots.ps1"

if (-not (Test-Path $treeExportScript) -or -not (Test-Path $treeDiffScript)) {
    Write-Warning "Tree snapshot scripts not found; skipping tree change collection."
} else {
    $treeCheckoutMap = @{}
    $treeWriteMap = @{}
    foreach ($study in $results.studySummary) {
        $studyId = [string]$study.study_id
        if ([int]$study.checkout_working_version_id -gt 0) {
            $treeCheckoutMap[$studyId] = $true
        }

        $lastModifiedDate = Convert-StringToDateTime -Value $study.last_modified
        if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
            $treeWriteMap[$studyId] = $true
        }
    }

    foreach ($study in $results.studySummary) {
        $studyId = [string]$study.study_id
        $studyName = $study.study_name

        Write-Host "  Processing: $studyName (ID: $studyId)" -ForegroundColor Gray

        $baselineFile = Join-Path $treeSnapshotDir "study-$studyId-baseline.json"
        $currentFile = Join-Path $treeSnapshotDir "study-$studyId-current.json"
        $diffFile = Join-Path $treeSnapshotDir "study-$studyId-diff.json"

        try {
            & $treeExportScript `
                -TNSName $TNSName `
                -Schema $Schema `
                -ProjectId $ProjectId `
                -StudyId $studyId `
                -OutputDir $treeSnapshotDir | Out-Null
        } catch {
            Write-Warning "    Snapshot export failed for study ${studyId}: $_"
            continue
        }

        $latestSnapshot = Get-ChildItem -Path $treeSnapshotDir -Filter "study-tree-snapshot-$Schema-$studyId-*.json" |
            Sort-Object -Property LastWriteTime -Descending |
            Select-Object -First 1

        if (-not $latestSnapshot) {
            Write-Warning "    Snapshot export did not produce output for study ${studyId}"
            continue
        }

        try {
            Copy-Item -Path $latestSnapshot.FullName -Destination $currentFile -Force
        } catch {
            Write-Warning "    Failed to store current snapshot for study ${studyId}: $_"
            continue
        }

        if (-not (Test-Path $baselineFile)) {
            try {
                Copy-Item -Path $currentFile -Destination $baselineFile -Force
                Write-Host "    Created baseline snapshot" -ForegroundColor Yellow
            } catch {
                Write-Warning "    Failed to create baseline snapshot for study ${studyId}: $_"
            }
            continue
        }

        try {
            & $treeDiffScript `
                -BaselineSnapshot $baselineFile `
                -CurrentSnapshot $currentFile `
                -OutputFile $diffFile | Out-Null
        } catch {
            Write-Warning "    Snapshot diff failed for study ${studyId}: $_"
            continue
        }

        if (-not (Test-Path $diffFile)) {
            Write-Warning "    Diff output missing for study ${studyId}"
            continue
        }

        $diff = $null
        try {
            $diff = Get-Content $diffFile -Raw | ConvertFrom-Json
        } catch {
            Write-Warning "    Failed to parse diff for study ${studyId}: $_"
            continue
        }

        if (-not $diff -or -not $diff.changes) {
            continue
        }

        $baselineSnapshot = $null
        $currentSnapshot = $null
        try {
            $baselineSnapshot = Get-Content $baselineFile -Raw | ConvertFrom-Json
            $currentSnapshot = Get-Content $currentFile -Raw | ConvertFrom-Json
        } catch {
            # Snapshot parsing is optional for provenance lookups
        }

        $baselineNodeMap = @{}
        if ($baselineSnapshot -and $baselineSnapshot.nodes) {
            foreach ($node in $baselineSnapshot.nodes) {
                $baselineNodeMap[$node.node_id] = $node
            }
        }

        $currentNodeMap = @{}
        if ($currentSnapshot -and $currentSnapshot.nodes) {
            foreach ($node in $currentSnapshot.nodes) {
                $currentNodeMap[$node.node_id] = $node
            }
        }

        $snapshotFiles = @{
            baseline = [System.IO.Path]::GetFileName($baselineFile)
            current = [System.IO.Path]::GetFileName($currentFile)
            diff = [System.IO.Path]::GetFileName($diffFile)
        }

        $detectedAt = if ($diff.meta -and $diff.meta.comparedAt) { $diff.meta.comparedAt } else { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }

        foreach ($rename in $diff.changes.renamed) {
            $treeChange = @{
                evidence_type = "rename"
                study_id = $studyId
                study_name = $studyName
                node_id = $rename.node_id
                node_type = $rename.node_type
                old_name = $rename.old_name
                new_name = $rename.new_name
                old_provenance = $rename.old_provenance
                new_provenance = $rename.new_provenance
                detected_at = $detectedAt
                snapshot_files = $snapshotFiles
            }

            if ($treeEvidenceEnabled) {
                $block = New-TreeEvidenceBlock -TreeChange $treeChange -CheckoutData $treeCheckoutMap -WriteData $treeWriteMap
                if ($block) {
                    $treeEvidence += [PSCustomObject]$block
                }
            } else {
                $treeEvidence += [PSCustomObject]$treeChange
            }
        }

        foreach ($move in $diff.changes.moved) {
            $coordProvenance = $null
            if ($currentNodeMap.ContainsKey($move.node_id) -and $currentNodeMap[$move.node_id].coord_provenance) {
                $coordProvenance = $currentNodeMap[$move.node_id].coord_provenance
            }

            $treeChange = @{
                evidence_type = "movement"
                study_id = $studyId
                study_name = $studyName
                node_id = $move.node_id
                node_name = $move.display_name
                node_type = $move.node_type
                old_x = $move.old_x
                old_y = $move.old_y
                old_z = $move.old_z
                new_x = $move.new_x
                new_y = $move.new_y
                new_z = $move.new_z
                delta_x = $move.delta_x
                delta_y = $move.delta_y
                delta_z = $move.delta_z
                delta_mm = $move.delta_mm
                movement_type = $move.movement_type
                mapping_type = $move.mapping_type
                coord_provenance = $coordProvenance
                detected_at = $detectedAt
                snapshot_files = $snapshotFiles
            }

            if ($treeEvidenceEnabled) {
                $block = New-TreeEvidenceBlock -TreeChange $treeChange -CheckoutData $treeCheckoutMap -WriteData $treeWriteMap
                if ($block) {
                    $treeEvidence += [PSCustomObject]$block
                }
            } else {
                $treeEvidence += [PSCustomObject]$treeChange
            }
        }

        foreach ($structChange in $diff.changes.structuralChanges) {
            $nameProvenance = $null
            if ($currentNodeMap.ContainsKey($structChange.node_id) -and $currentNodeMap[$structChange.node_id].name_provenance) {
                $nameProvenance = $currentNodeMap[$structChange.node_id].name_provenance
            }

            $treeChange = @{
                evidence_type = "structure"
                change_type = $structChange.change_type
                study_id = $studyId
                study_name = $studyName
                node_id = $structChange.node_id
                node_name = $structChange.display_name
                node_type = $structChange.node_type
                old_parent_id = $structChange.old_parent_id
                new_parent_id = $structChange.new_parent_id
                name_provenance = $nameProvenance
                detected_at = $detectedAt
                snapshot_files = $snapshotFiles
            }

            if ($treeEvidenceEnabled) {
                $block = New-TreeEvidenceBlock -TreeChange $treeChange -CheckoutData $treeCheckoutMap -WriteData $treeWriteMap
                if ($block) {
                    $treeEvidence += [PSCustomObject]$block
                }
            } else {
                $treeEvidence += [PSCustomObject]$treeChange
            }
        }

        foreach ($mappingChange in $diff.changes.resourceMappingChanges) {
            $treeChange = @{
                evidence_type = "resource_mapping"
                study_id = $studyId
                study_name = $studyName
                node_id = $mappingChange.node_id
                node_name = $mappingChange.shortcut_name
                node_type = "Shortcut"
                old_resource_id = $mappingChange.old_resource_id
                old_resource_name = $mappingChange.old_resource_name
                new_resource_id = $mappingChange.new_resource_id
                new_resource_name = $mappingChange.new_resource_name
                detected_at = $detectedAt
                snapshot_files = $snapshotFiles
            }

            if ($treeEvidenceEnabled) {
                $block = New-TreeEvidenceBlock -TreeChange $treeChange -CheckoutData $treeCheckoutMap -WriteData $treeWriteMap
                if ($block) {
                    $treeEvidence += [PSCustomObject]$block
                }
            } else {
                $treeEvidence += [PSCustomObject]$treeChange
            }
        }

        foreach ($added in $diff.changes.nodesAdded) {
            $nameProvenance = $null
            if ($currentNodeMap.ContainsKey($added.node_id) -and $currentNodeMap[$added.node_id].name_provenance) {
                $nameProvenance = $currentNodeMap[$added.node_id].name_provenance
            }

            $treeChange = @{
                evidence_type = "node_added"
                study_id = $studyId
                study_name = $studyName
                node_id = $added.node_id
                node_name = $added.display_name
                node_type = $added.node_type
                parent_node_id = $added.parent_node_id
                resource_name = $added.resource_name
                name_provenance = $nameProvenance
                detected_at = $detectedAt
                snapshot_files = $snapshotFiles
            }

            if ($treeEvidenceEnabled) {
                $block = New-TreeEvidenceBlock -TreeChange $treeChange -CheckoutData $treeCheckoutMap -WriteData $treeWriteMap
                if ($block) {
                    $treeEvidence += [PSCustomObject]$block
                }
            } else {
                $treeEvidence += [PSCustomObject]$treeChange
            }
        }

        foreach ($removed in $diff.changes.nodesRemoved) {
            $nameProvenance = $null
            if ($baselineNodeMap.ContainsKey($removed.node_id) -and $baselineNodeMap[$removed.node_id].name_provenance) {
                $nameProvenance = $baselineNodeMap[$removed.node_id].name_provenance
            }

            $treeChange = @{
                evidence_type = "node_removed"
                study_id = $studyId
                study_name = $studyName
                node_id = $removed.node_id
                node_name = $removed.display_name
                node_type = $removed.node_type
                parent_node_id = $removed.parent_node_id
                resource_name = $removed.resource_name
                name_provenance = $nameProvenance
                detected_at = $detectedAt
                snapshot_files = $snapshotFiles
            }

            if ($treeEvidenceEnabled) {
                $block = New-TreeEvidenceBlock -TreeChange $treeChange -CheckoutData $treeCheckoutMap -WriteData $treeWriteMap
                if ($block) {
                    $treeEvidence += [PSCustomObject]$block
                }
            } else {
                $treeEvidence += [PSCustomObject]$treeChange
            }
        }
    }
}

$results.treeChanges = $treeEvidence
Write-Host "  Tree evidence collected: $($results.treeChanges.Count) changes" -ForegroundColor Green

# ========================================
# Evidence & Snapshot Processing
# ========================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Evidence & Snapshot Processing" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$evidenceEnabled = $false
if (Get-Command -Name New-EvidenceBlock -ErrorAction SilentlyContinue) {
    $evidenceEnabled = $true
} else {
    Write-Warning "Evidence classifier not available; evidence blocks will be empty."
}

$previousSnapshot = $null
$snapshotPath = $null
$snapshotAvailable = $false
if (Get-Command -Name Read-Snapshot -ErrorAction SilentlyContinue) {
    $snapshotPath = Get-SnapshotPath -Schema $Schema -ProjectId $ProjectId
    $previousSnapshot = Read-Snapshot -SnapshotPath $snapshotPath
    $snapshotAvailable = $true
    if ($snapshotPath) {
        $results.metadata.snapshotFile = [System.IO.Path]::GetFileName($snapshotPath)
    }
} else {
    Write-Warning "Snapshot manager not available; diffs disabled."
}

$newSnapshotRecords = @()

function Add-EventRecord {
    param(
        [string]$WorkType,
        [string]$Timestamp,
        [string]$User,
        [string]$Description,
        [string]$ObjectName,
        [string]$ObjectId,
        [string]$ObjectType,
        [hashtable]$Evidence,
        [hashtable]$Context
    )

    $safeEvidence = Ensure-EvidenceBlock -Evidence $Evidence

    $event = [ordered]@{
        timestamp = $Timestamp
        user = $User
        workType = $WorkType
        description = $Description
        objectName = $ObjectName
        objectId = $ObjectId
        objectType = $ObjectType
        evidence = $safeEvidence
    }

    if ($Context -and $Context.Count -gt 0) {
        $event.context = $Context
    }

    $results.events += [PSCustomObject]$event
}

# Project Database events
foreach ($item in $results.projectDatabase) {
    $objectId = [string]$item.object_id
    $objectType = if ($item.object_type) { $item.object_type } else { "Project" }
    $objectName = $item.object_name
    $modifiedBy = $item.modified_by
    $lastModifiedDate = Convert-StringToDateTime -Value $item.last_modified
    $writeSources = @()
    if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
        $writeSources += "COLLECTION_.MODIFICATIONDATE_DA_"
    }

    $snapshotRecord = New-SnapshotRecord `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -ModificationDate $lastModifiedDate `
        -LastModifiedBy $modifiedBy `
        -Metadata @{ objectName = $objectName }

    if ($snapshotRecord) {
        $newSnapshotRecords += $snapshotRecord
    }

    $snapshotComparison = $null
    if ($previousSnapshot) {
        $snapshotComparison = Compare-Snapshots -ObjectId $objectId -NewRecord $snapshotRecord -PreviousSnapshot $previousSnapshot
    }
    $snapshotEvidence = New-SnapshotEvidence -SnapshotComparison $snapshotComparison

    $deltaSummary = New-AllocationDeltaSummary -SnapshotComparison $snapshotComparison -NewRecord $snapshotRecord

    $evidence = @{}
    if ($evidenceEnabled) {
        $evidence = New-EvidenceBlock `
            -ObjectId $objectId `
            -ObjectType $objectType `
            -ProxyOwnerId $item.checked_out_by_user_id `
            -ProxyOwnerName $item.checked_out_by_user_name `
            -LastModifiedBy $modifiedBy `
            -CheckoutWorkingVersionId ([int]$item.checkout_working_version_id) `
            -ModificationDate $lastModifiedDate `
            -WriteSources $writeSources `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotEvidence
    }

    $normalizedWorkType = Normalize-WorkTypeSafe -WorkType "Project Database" -ObjectType $objectType
    $description = if ($item.status) { "$objectName - $($item.status)" } else { $objectName }
    $context = $null
    if (Get-Command -Name New-EventEnrichment -ErrorAction SilentlyContinue) {
        $enrichment = New-EventEnrichment `
            -WorkType $normalizedWorkType `
            -ObjectName $objectName `
            -ObjectType $objectType `
            -ObjectId $objectId `
            -Category $null `
            -Item $item `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotComparison

        if ($enrichment -and $enrichment.description) {
            $description = $enrichment.description
        }
        $context = $enrichment.context
    }
    $user = if ($modifiedBy) { $modifiedBy } else { $item.checked_out_by_user_name }

    Add-EventRecord `
        -WorkType $normalizedWorkType `
        -Timestamp $item.last_modified `
        -User $user `
        -Description $description `
        -ObjectName $objectName `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -Evidence $evidence `
        -Context $context
}

# Resource Library events
foreach ($item in $results.resourceLibrary) {
    $objectId = [string]$item.object_id
    $objectType = if ($item.object_type) { $item.object_type } else { "Resource" }
    $objectName = $item.object_name
    $modifiedBy = $item.modified_by
    $lastModifiedDate = Convert-StringToDateTime -Value $item.last_modified
    $writeSources = @()
    if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
        $writeSources += "RESOURCE_.MODIFICATIONDATE_DA_"
    }

    $snapshotRecord = New-SnapshotRecord `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -ModificationDate $lastModifiedDate `
        -LastModifiedBy $modifiedBy `
        -Metadata @{ objectName = $objectName }

    if ($snapshotRecord) {
        $newSnapshotRecords += $snapshotRecord
    }

    $snapshotComparison = $null
    if ($previousSnapshot) {
        $snapshotComparison = Compare-Snapshots -ObjectId $objectId -NewRecord $snapshotRecord -PreviousSnapshot $previousSnapshot
    }
    $snapshotEvidence = New-SnapshotEvidence -SnapshotComparison $snapshotComparison

    $deltaSummary = New-LibraryDeltaSummary -SnapshotComparison $snapshotComparison -NewRecord $snapshotRecord

    $evidence = @{}
    if ($evidenceEnabled) {
        $evidence = New-EvidenceBlock `
            -ObjectId $objectId `
            -ObjectType $objectType `
            -ProxyOwnerId $item.checked_out_by_user_id `
            -ProxyOwnerName $item.checked_out_by_user_name `
            -LastModifiedBy $modifiedBy `
            -CheckoutWorkingVersionId ([int]$item.checkout_working_version_id) `
            -ModificationDate $lastModifiedDate `
            -WriteSources $writeSources `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotEvidence
    }

    $normalizedWorkType = Normalize-WorkTypeSafe -WorkType "Resource Library" -ObjectType $objectType
    $description = if ($item.status) { "$objectName ($($item.object_type)) - $($item.status)" } else { "$objectName ($($item.object_type))" }
    $context = $null
    if (Get-Command -Name New-EventEnrichment -ErrorAction SilentlyContinue) {
        $enrichment = New-EventEnrichment `
            -WorkType $normalizedWorkType `
            -ObjectName $objectName `
            -ObjectType $objectType `
            -ObjectId $objectId `
            -Category $null `
            -Item $item `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotComparison

        if ($enrichment -and $enrichment.description) {
            $description = $enrichment.description
        }
        $context = $enrichment.context
    }
    $user = if ($modifiedBy) { $modifiedBy } else { $item.checked_out_by_user_name }

    Add-EventRecord `
        -WorkType $normalizedWorkType `
        -Timestamp $item.last_modified `
        -User $user `
        -Description $description `
        -ObjectName $objectName `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -Evidence $evidence `
        -Context $context
}

# Part Library events
foreach ($item in $results.partLibrary) {
    $objectId = [string]$item.object_id
    $objectType = if ($item.object_type) { $item.object_type } else { "Part" }
    $objectName = $item.object_name
    $modifiedBy = $item.modified_by
    $lastModifiedDate = Convert-StringToDateTime -Value $item.last_modified
    $writeSources = @()
    if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
        $writeSources += "PART_.MODIFICATIONDATE_DA_"
    }

    $snapshotRecord = New-SnapshotRecord `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -ModificationDate $lastModifiedDate `
        -LastModifiedBy $modifiedBy `
        -Metadata @{ objectName = $objectName; category = $item.category }

    if ($snapshotRecord) {
        $newSnapshotRecords += $snapshotRecord
    }

    $snapshotComparison = $null
    if ($previousSnapshot) {
        $snapshotComparison = Compare-Snapshots -ObjectId $objectId -NewRecord $snapshotRecord -PreviousSnapshot $previousSnapshot
    }
    $snapshotEvidence = New-SnapshotEvidence -SnapshotComparison $snapshotComparison

    $deltaSummary = New-LibraryDeltaSummary -SnapshotComparison $snapshotComparison -NewRecord $snapshotRecord

    $evidence = @{}
    if ($evidenceEnabled) {
        $evidence = New-EvidenceBlock `
            -ObjectId $objectId `
            -ObjectType $objectType `
            -ProxyOwnerId $item.checked_out_by_user_id `
            -ProxyOwnerName $item.checked_out_by_user_name `
            -LastModifiedBy $modifiedBy `
            -CheckoutWorkingVersionId ([int]$item.checkout_working_version_id) `
            -ModificationDate $lastModifiedDate `
            -WriteSources $writeSources `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotEvidence
    }

    $normalizedWorkType = Normalize-WorkTypeSafe -WorkType "Part/MFG Library" -ObjectType $objectType -Category $item.category
    $description = if ($item.status) { "$objectName ($($item.category)) - $($item.status)" } else { "$objectName ($($item.category))" }
    $context = $null
    if (Get-Command -Name New-EventEnrichment -ErrorAction SilentlyContinue) {
        $enrichment = New-EventEnrichment `
            -WorkType $normalizedWorkType `
            -ObjectName $objectName `
            -ObjectType $objectType `
            -ObjectId $objectId `
            -Category $item.category `
            -Item $item `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotComparison

        if ($enrichment -and $enrichment.description) {
            $description = $enrichment.description
        }
        $context = $enrichment.context
    }
    $user = if ($modifiedBy) { $modifiedBy } else { $item.checked_out_by_user_name }

    Add-EventRecord `
        -WorkType $normalizedWorkType `
        -Timestamp $item.last_modified `
        -User $user `
        -Description $description `
        -ObjectName $objectName `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -Evidence $evidence `
        -Context $context
}

# IPA Assembly events
foreach ($item in $results.ipaAssembly) {
    $objectId = [string]$item.object_id
    $objectType = if ($item.object_type) { $item.object_type } else { "TxProcessAssembly" }
    $objectName = $item.object_name
    $modifiedBy = $item.modified_by
    $lastModifiedDate = Convert-StringToDateTime -Value $item.last_modified
    $operationCount = 0
    if (-not [string]::IsNullOrWhiteSpace($item.operation_count)) {
        $operationCount = [int]$item.operation_count
    }

    $stationContext = $null
    if (Get-Command -Name Try-ResolveStationContext -ErrorAction SilentlyContinue) {
        $stationContext = Try-ResolveStationContext -Item $item -ObjectName $objectName
    }

    $stationValue = $null
    if ($stationContext -and $stationContext.station) {
        $stationValue = $stationContext.station
    }

    $allocationFingerprint = $null
    if (Get-Command -Name New-AllocationFingerprint -ErrorAction SilentlyContinue) {
        $allocationFingerprint = New-AllocationFingerprint -Station $stationValue -OperationCount $operationCount
    }

    $operationCounts = $null
    if ($operationCount -gt 0 -or $allocationFingerprint) {
        $operationCounts = @{
            operationCount = $operationCount
        }
        if ($allocationFingerprint) {
            $operationCounts.allocationFingerprint = $allocationFingerprint
        }
    }

    $writeSources = @()
    if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
        if (Get-Command -Name Get-IpaWriteSources -ErrorAction SilentlyContinue) {
            $writeSources += Get-IpaWriteSources -OperationCount $operationCount
        } else {
            $writeSources += "PART_.MODIFICATIONDATE_DA_"
        }
    }

    $joinSources = @("REL_COMMON.OBJECT_ID", "OPERATION_.OBJECT_ID")

    $metadata = @{ objectName = $objectName }
    if ($stationValue) {
        $metadata.station = $stationValue
    }

    if ($allocationFingerprint) {
        $metadata.allocationFingerprint = $allocationFingerprint
    }

    $snapshotRecord = New-SnapshotRecord `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -ModificationDate $lastModifiedDate `
        -LastModifiedBy $modifiedBy `
        -OperationCounts $operationCounts `
        -Metadata $metadata

    if ($snapshotRecord) {
        $newSnapshotRecords += $snapshotRecord
    }

    $snapshotComparison = $null
    if ($previousSnapshot) {
        $snapshotComparison = Compare-Snapshots -ObjectId $objectId -NewRecord $snapshotRecord -PreviousSnapshot $previousSnapshot
    }
    $snapshotEvidence = New-SnapshotEvidence -SnapshotComparison $snapshotComparison

    $allocationHistory = @()
    if ($snapshotComparison -and $snapshotComparison.previousRecord -and $snapshotComparison.previousRecord.PSObject.Properties['metadata']) {
        $previousMetadata = $snapshotComparison.previousRecord.metadata
        if ($previousMetadata.PSObject.Properties['allocationFingerprintHistory']) {
            $allocationHistory = @($previousMetadata.allocationFingerprintHistory)
        } elseif ($previousMetadata.PSObject.Properties['allocationFingerprint']) {
            $allocationHistory = @($previousMetadata.allocationFingerprint)
        }
    }

    if ($allocationFingerprint) {
        $allocationHistory += $allocationFingerprint
        if ($allocationHistory.Count -gt 3) {
            $allocationHistory = $allocationHistory[-3..-1]
        }
    }

    if ($snapshotRecord -and $allocationHistory.Count -gt 0) {
        if (-not $snapshotRecord.metadata) {
            $snapshotRecord.metadata = @{}
        }
        $snapshotRecord.metadata.allocationFingerprintHistory = $allocationHistory
    }

    $allocationState = $null
    if (Get-Command -Name Get-AllocationStabilityState -ErrorAction SilentlyContinue) {
        $allocationState = Get-AllocationStabilityState -FingerprintHistory $allocationHistory -Window 3
    }

    $deltaSummary = New-AllocationDeltaSummary -SnapshotComparison $snapshotComparison -NewRecord $snapshotRecord

    $evidence = @{}
    if ($evidenceEnabled) {
        $evidence = New-EvidenceBlock `
            -ObjectId $objectId `
            -ObjectType $objectType `
            -ProxyOwnerId $item.checked_out_by_user_id `
            -ProxyOwnerName $item.checked_out_by_user_name `
            -LastModifiedBy $modifiedBy `
            -CheckoutWorkingVersionId ([int]$item.checkout_working_version_id) `
            -ModificationDate $lastModifiedDate `
            -WriteSources $writeSources `
            -DeltaSummary $deltaSummary `
            -JoinSources $joinSources `
            -SnapshotComparison $snapshotEvidence
    }

    $normalizedWorkType = Normalize-WorkTypeSafe -WorkType "IPA Assembly" -ObjectType $objectType
    $description = if ($item.status) { "$objectName - $($item.status)" } else { $objectName }
    $context = $null
    if (Get-Command -Name New-EventEnrichment -ErrorAction SilentlyContinue) {
        $enrichment = New-EventEnrichment `
            -WorkType $normalizedWorkType `
            -ObjectName $objectName `
            -ObjectType $objectType `
            -ObjectId $objectId `
            -Category $null `
            -Item $item `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotComparison

        if ($enrichment -and $enrichment.description) {
            $description = $enrichment.description
        }
        $context = $enrichment.context
    }

    if ($allocationState) {
        if (-not $context) {
            $context = @{}
        }
        $context.allocationState = $allocationState
    }
    $user = if ($modifiedBy) { $modifiedBy } else { $item.checked_out_by_user_name }

    Add-EventRecord `
        -WorkType $normalizedWorkType `
        -Timestamp $item.last_modified `
        -User $user `
        -Description $description `
        -ObjectName $objectName `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -Evidence $evidence `
        -Context $context
}

# Study Summary events
foreach ($item in $results.studySummary) {
    $objectId = [string]$item.study_id
    $objectType = if ($item.study_type) { $item.study_type } else { "RobcadStudy" }
    $objectName = $item.study_name
    $modifiedBy = $item.modified_by
    $lastModifiedDate = Convert-StringToDateTime -Value $item.last_modified
    $writeSources = @()
    if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
        $writeSources += "ROBCADSTUDY_.MODIFICATIONDATE_DA_"
    }

    $snapshotRecord = New-SnapshotRecord `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -ModificationDate $lastModifiedDate `
        -LastModifiedBy $modifiedBy `
        -Metadata @{ studyName = $objectName }

    if ($snapshotRecord) {
        $newSnapshotRecords += $snapshotRecord
    }

    $snapshotComparison = $null
    if ($previousSnapshot) {
        $snapshotComparison = Compare-Snapshots -ObjectId $objectId -NewRecord $snapshotRecord -PreviousSnapshot $previousSnapshot
    }
    $snapshotEvidence = New-SnapshotEvidence -SnapshotComparison $snapshotComparison

    $evidence = @{}
    if ($evidenceEnabled) {
        $evidence = New-EvidenceBlock `
            -ObjectId $objectId `
            -ObjectType $objectType `
            -ProxyOwnerId $item.checked_out_by_user_id `
            -ProxyOwnerName $item.checked_out_by_user_name `
            -LastModifiedBy $modifiedBy `
            -CheckoutWorkingVersionId ([int]$item.checkout_working_version_id) `
            -ModificationDate $lastModifiedDate `
            -WriteSources $writeSources `
            -SnapshotComparison $snapshotEvidence
    }

    $normalizedWorkType = Normalize-WorkTypeSafe -WorkType "Study Nodes" -ObjectType $objectType
    $description = if ($item.status) { "$objectName ($($item.study_type)) - $($item.status)" } else { "$objectName ($($item.study_type))" }
    $context = $null
    if (Get-Command -Name New-EventEnrichment -ErrorAction SilentlyContinue) {
        $enrichment = New-EventEnrichment `
            -WorkType $normalizedWorkType `
            -ObjectName $objectName `
            -ObjectType $objectType `
            -ObjectId $objectId `
            -Category $null `
            -Item $item `
            -DeltaSummary $null `
            -SnapshotComparison $snapshotComparison

        if ($enrichment -and $enrichment.description) {
            $description = $enrichment.description
        }
        $context = $enrichment.context
    }
    $user = if ($modifiedBy) { $modifiedBy } else { $item.checked_out_by_user_name }

    Add-EventRecord `
        -WorkType $normalizedWorkType `
        -Timestamp $item.last_modified `
        -User $user `
        -Description $description `
        -ObjectName $objectName `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -Evidence $evidence `
        -Context $context
}

# Study Movement events
foreach ($item in $results.studyMovements) {
    $objectId = [string]$item.studylayout_id
    $objectType = "StudyLayout"
    $objectName = "StudyLayout $objectId"
    $modifiedBy = $item.modified_by
    $lastModifiedDate = Convert-StringToDateTime -Value $item.last_modified
    $writeSources = @()
    if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
        $writeSources += "STUDYLAYOUT_.MODIFICATIONDATE_DA_"
    }

    $coordinates = $null
    if (-not [string]::IsNullOrWhiteSpace($item.x_coord) -and
        -not [string]::IsNullOrWhiteSpace($item.y_coord) -and
        -not [string]::IsNullOrWhiteSpace($item.z_coord)) {
        $coordinates = @{
            x = [double]$item.x_coord
            y = [double]$item.y_coord
            z = [double]$item.z_coord
        }
    }

    $snapshotRecord = New-SnapshotRecord `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -ModificationDate $lastModifiedDate `
        -LastModifiedBy $modifiedBy `
        -Coordinates $coordinates `
        -Metadata @{ studyId = $item.studyinfo_id; locationVectorId = $item.location_vector_id }

    if ($snapshotRecord) {
        $newSnapshotRecords += $snapshotRecord
    }

    $snapshotComparison = $null
    if ($previousSnapshot) {
        $snapshotComparison = Compare-Snapshots -ObjectId $objectId -NewRecord $snapshotRecord -PreviousSnapshot $previousSnapshot
    }
    $snapshotEvidence = New-SnapshotEvidence -SnapshotComparison $snapshotComparison

    $deltaSummary = $null
    $previousRecordTable = $null
    if ($snapshotComparison -and $snapshotComparison.previousRecord) {
        $previousRecordTable = Convert-PSObjectToHashtable -InputObject $snapshotComparison.previousRecord
    }
    if ($snapshotComparison -and $previousRecordTable -and $snapshotComparison.hasDelta) {
        $deltaSummary = New-CoordinateDeltaSummary -NewRecord $snapshotRecord -PreviousRecord $previousRecordTable
    }

    $evidence = @{}
    if ($evidenceEnabled) {
        $evidence = New-EvidenceBlock `
            -ObjectId $objectId `
            -ObjectType $objectType `
            -ProxyOwnerId $item.checked_out_by_user_id `
            -ProxyOwnerName $item.checked_out_by_user_name `
            -LastModifiedBy $modifiedBy `
            -CheckoutWorkingVersionId ([int]$item.checkout_working_version_id) `
            -ModificationDate $lastModifiedDate `
            -WriteSources $writeSources `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotEvidence
    }

    $normalizedWorkType = Normalize-WorkTypeSafe -WorkType "Study Movements" -ObjectType $objectType
    $description = "Study layout update (location vector $($item.location_vector_id))"
    $context = $null
    if (Get-Command -Name New-EventEnrichment -ErrorAction SilentlyContinue) {
        $enrichment = New-EventEnrichment `
            -WorkType $normalizedWorkType `
            -ObjectName $objectName `
            -ObjectType $objectType `
            -ObjectId $objectId `
            -Category $null `
            -Item $item `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotComparison

        if ($enrichment -and $enrichment.description) {
            $description = $enrichment.description
        }
        $context = $enrichment.context
    }
    $user = if ($modifiedBy) { $modifiedBy } else { $item.checked_out_by_user_name }

    Add-EventRecord `
        -WorkType $normalizedWorkType `
        -Timestamp $item.last_modified `
        -User $user `
        -Description $description `
        -ObjectName $objectName `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -Evidence $evidence `
        -Context $context
}

# Study Operation events
foreach ($item in $results.studyOperations) {
    $objectId = [string]$item.operation_id
    $objectType = if ($item.operation_class) { $item.operation_class } else { "Operation" }
    $objectName = $item.operation_name
    $modifiedBy = $item.modified_by
    $lastModifiedDate = Convert-StringToDateTime -Value $item.last_modified
    $writeSources = @()
    if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
        $writeSources += "OPERATION_.MODIFICATIONDATE_DA_"
    }

    $snapshotRecord = New-SnapshotRecord `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -ModificationDate $lastModifiedDate `
        -LastModifiedBy $modifiedBy `
        -Metadata @{ operationName = $objectName; operationType = $item.operation_type }

    if ($snapshotRecord) {
        $newSnapshotRecords += $snapshotRecord
    }

    $snapshotComparison = $null
    if ($previousSnapshot) {
        $snapshotComparison = Compare-Snapshots -ObjectId $objectId -NewRecord $snapshotRecord -PreviousSnapshot $previousSnapshot
    }
    $snapshotEvidence = New-SnapshotEvidence -SnapshotComparison $snapshotComparison

    $deltaSummary = New-AllocationDeltaSummary -SnapshotComparison $snapshotComparison -NewRecord $snapshotRecord

    $evidence = @{}
    if ($evidenceEnabled) {
        $evidence = New-EvidenceBlock `
            -ObjectId $objectId `
            -ObjectType $objectType `
            -ProxyOwnerId $item.checked_out_by_user_id `
            -ProxyOwnerName $item.checked_out_by_user_name `
            -LastModifiedBy $modifiedBy `
            -CheckoutWorkingVersionId ([int]$item.checkout_working_version_id) `
            -ModificationDate $lastModifiedDate `
            -WriteSources $writeSources `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotEvidence
    }

    $normalizedWorkType = Normalize-WorkTypeSafe -WorkType "Study Operations" -ObjectType $objectType
    $description = if ($item.operation_category) { "$objectName - $($item.operation_category)" } else { $objectName }
    $context = $null
    if (Get-Command -Name New-EventEnrichment -ErrorAction SilentlyContinue) {
        $enrichment = New-EventEnrichment `
            -WorkType $normalizedWorkType `
            -ObjectName $objectName `
            -ObjectType $objectType `
            -ObjectId $objectId `
            -Category $null `
            -Item $item `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotComparison

        if ($enrichment -and $enrichment.description) {
            $description = $enrichment.description
        }
        $context = $enrichment.context
    }
    $user = if ($modifiedBy) { $modifiedBy } else { $item.checked_out_by_user_name }

    Add-EventRecord `
        -WorkType $normalizedWorkType `
        -Timestamp $item.last_modified `
        -User $user `
        -Description $description `
        -ObjectName $objectName `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -Evidence $evidence `
        -Context $context
}

# Study Weld events
foreach ($item in $results.studyWelds) {
    $objectId = [string]$item.operation_id
    $objectType = "WeldOperation"
    $objectName = $item.operation_name
    $modifiedBy = $item.modified_by
    $lastModifiedDate = Convert-StringToDateTime -Value $item.last_modified
    $writeSources = @()
    if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
        $writeSources += "OPERATION_.MODIFICATIONDATE_DA_"
    }

    $snapshotRecord = New-SnapshotRecord `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -ModificationDate $lastModifiedDate `
        -LastModifiedBy $modifiedBy `
        -Metadata @{ operationName = $objectName }

    if ($snapshotRecord) {
        $newSnapshotRecords += $snapshotRecord
    }

    $snapshotComparison = $null
    if ($previousSnapshot) {
        $snapshotComparison = Compare-Snapshots -ObjectId $objectId -NewRecord $snapshotRecord -PreviousSnapshot $previousSnapshot
    }
    $snapshotEvidence = New-SnapshotEvidence -SnapshotComparison $snapshotComparison

    $deltaSummary = New-AllocationDeltaSummary -SnapshotComparison $snapshotComparison -NewRecord $snapshotRecord

    $evidence = @{}
    if ($evidenceEnabled) {
        $evidence = New-EvidenceBlock `
            -ObjectId $objectId `
            -ObjectType $objectType `
            -ProxyOwnerId $item.checked_out_by_user_id `
            -ProxyOwnerName $item.checked_out_by_user_name `
            -LastModifiedBy $modifiedBy `
            -CheckoutWorkingVersionId ([int]$item.checkout_working_version_id) `
            -ModificationDate $lastModifiedDate `
            -WriteSources $writeSources `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotEvidence
    }

    $normalizedWorkType = Normalize-WorkTypeSafe -WorkType "Study Welds" -ObjectType $objectType
    $description = $objectName
    $context = $null
    if (Get-Command -Name New-EventEnrichment -ErrorAction SilentlyContinue) {
        $enrichment = New-EventEnrichment `
            -WorkType $normalizedWorkType `
            -ObjectName $objectName `
            -ObjectType $objectType `
            -ObjectId $objectId `
            -Category $null `
            -Item $item `
            -DeltaSummary $deltaSummary `
            -SnapshotComparison $snapshotComparison

        if ($enrichment -and $enrichment.description) {
            $description = $enrichment.description
        }
        $context = $enrichment.context
    }
    $user = if ($modifiedBy) { $modifiedBy } else { $item.checked_out_by_user_name }

    Add-EventRecord `
        -WorkType $normalizedWorkType `
        -Timestamp $item.last_modified `
        -User $user `
        -Description $description `
        -ObjectName $objectName `
        -ObjectId $objectId `
        -ObjectType $objectType `
        -Evidence $evidence `
        -Context $context
}

if ($snapshotAvailable -and $newSnapshotRecords.Count -gt 0) {
    try {
        Save-Snapshot -SnapshotRecords $newSnapshotRecords -OutputPath $snapshotPath -Schema $Schema -ProjectId $ProjectId | Out-Null
        Write-Host "Snapshot saved: $snapshotPath" -ForegroundColor Green
    } catch {
        Write-Warning "    Failed to save snapshot: $_"
    }
}

# Save results to JSON
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Saving Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$outputPath = [System.IO.Path]::GetFullPath($OutputFile)
$outputDir = [System.IO.Path]::GetDirectoryName($outputPath)
if ([string]::IsNullOrWhiteSpace($outputDir)) {
    $outputDir = (Get-Location).Path
}
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$outputName = [System.IO.Path]::GetFileNameWithoutExtension($outputPath)
$outputExt = [System.IO.Path]::GetExtension($outputPath)
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$tempFile = Join-Path $outputDir ("$outputName.tmp-$timestamp$outputExt")
$targetPath = $outputPath
if (Test-FileLocked -Path $outputPath) {
    $targetPath = Join-Path $outputDir ("$outputName.$timestamp$outputExt")
}

$results | ConvertTo-Json -Depth 10 | Out-File $tempFile -Encoding UTF8 -Force

$finalOutput = $tempFile
try {
    if (Test-Path $targetPath) {
        Remove-Item -Path $targetPath -Force -ErrorAction Stop
    }

    Move-Item -Path $tempFile -Destination $targetPath -ErrorAction Stop
    $finalOutput = $targetPath
} catch {
    Write-Warning "    Output file could not be replaced; keeping temp file instead."
}

Write-Host "  Results saved to: $finalOutput" -ForegroundColor Green

$scriptTimer.Stop()
Write-Host "`n  Total time: $([math]::Round($scriptTimer.Elapsed.TotalSeconds, 2))s" -ForegroundColor Cyan
Write-Host ""

# Explicitly exit with success code (0 rows is valid - means no activity in date range)
exit 0
