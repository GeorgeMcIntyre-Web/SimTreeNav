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

# Format dates for SQL
$startDateStr = $StartDate.ToString('yyyy-MM-dd')
$endDateStr = $EndDate.ToString('yyyy-MM-dd')

# Initialize results object
$results = @{
    metadata = @{
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
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON
SET VERIFY OFF
SET COLSEP '|'
SET TRIMSPOOL ON

##QUERY##

EXIT;
'@
        $sqlScript = $sqlScript.Replace('##QUERY##', $Query)

        $sqlScript | Out-File $tempSqlFile -Encoding ASCII

        # Execute query
        $outputFile = Join-Path $env:TEMP "${QueryName}-${Schema}-${ProjectId}.txt"
        $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop

        if ($connectionString) {
            $result = sqlplus -S $connectionString "@$tempSqlFile" 2>&1
            $result | Out-File $outputFile -Encoding UTF8

            # Parse results
            $data = Get-Content $outputFile -Encoding UTF8 | Where-Object { $_ -match '\|' }
            $objects = Convert-PipeDelimitedToObjects -Lines $data

            # Cleanup
            Remove-Item $tempSqlFile -ErrorAction SilentlyContinue
            Remove-Item $outputFile -ErrorAction SilentlyContinue

            Write-Host "    ??? Retrieved $($objects.Count) rows" -ForegroundColor Green
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
Write-Host "`n[1/11] Project Database Setup" -ForegroundColor Cyan
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
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status
FROM ##SCHEMA##.COLLECTION_ c
LEFT JOIN ##SCHEMA##.PROXY p ON c.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE c.OBJECT_ID = ##PROJECTID##;
'@
$query1 = $query1.Replace('##SCHEMA##', $Schema).Replace('##PROJECTID##', $ProjectId).Replace('##STARTDATE##', $startDateStr)
$results.projectDatabase = Execute-Query -QueryName "ProjectDatabase" -Query $query1

# QUERY 2: Resource Library Activity
Write-Host "`n[2/11] Resource Library" -ForegroundColor Cyan
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
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status
FROM ##SCHEMA##.RESOURCE_ r
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE r.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 100
ORDER BY r.MODIFICATIONDATE_DA_ DESC;
'@
$query2 = $query2.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.resourceLibrary = Execute-Query -QueryName "ResourceLibrary" -Query $query2

# QUERY 3: Part/MFG Library Activity
Write-Host "`n[3/11] Part/MFG Library" -ForegroundColor Cyan
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
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status
FROM ##SCHEMA##.PART_ p
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY pr ON p.OBJECT_ID = pr.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE p.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 100
ORDER BY p.MODIFICATIONDATE_DA_ DESC;
'@
$query3 = $query3.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.partLibrary = Execute-Query -QueryName "PartLibrary" -Query $query3

# QUERY 4: IPA Assembly Activity
Write-Host "`n[4/11] IPA Assembly" -ForegroundColor Cyan
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
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status
FROM ##SCHEMA##.PART_ pa
LEFT JOIN ##SCHEMA##.PROXY pr ON pa.OBJECT_ID = pr.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE pa.CLASS_ID = 133
  AND pa.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 100
ORDER BY pa.MODIFICATIONDATE_DA_ DESC;
'@
$query4 = $query4.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.ipaAssembly = Execute-Query -QueryName "IpaAssembly" -Query $query4

# QUERY 5A: Study Summary
Write-Host "`n[5/11] Study Summary" -ForegroundColor Cyan
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
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Active' ELSE 'Idle' END as status
FROM ##SCHEMA##.ROBCADSTUDY_ rs
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE rs.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 50
ORDER BY rs.MODIFICATIONDATE_DA_ DESC;
'@
$query5a = $query5a.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.studySummary = Execute-Query -QueryName "StudySummary" -Query $query5a

# QUERY 5B: Study Resources
Write-Host "`n[6/11] Study Resource Allocation" -ForegroundColor Cyan
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
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN ##SCHEMA##.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN ##SCHEMA##.RESOURCE_ res ON s.NAME_S_ = res.NAME_S_
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
WHERE rs.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 200
ORDER BY rs.NAME_S_, r.SEQ_NUMBER;
'@
$query5b = $query5b.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.studyResources = Execute-Query -QueryName "StudyResources" -Query $query5b

# QUERY 5C: Study Panels
Write-Host "`n[7/11] Study Panel Usage" -ForegroundColor Cyan
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
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN ##SCHEMA##.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE s.NAME_S_ LIKE '%\_%' ESCAPE '\'
  AND rs.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 200
ORDER BY rs.NAME_S_, s.NAME_S_;
'@
$query5c = $query5c.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.studyPanels = Execute-Query -QueryName "StudyPanels" -Query $query5c

# QUERY 5D: Study Operations
Write-Host "`n[8/11] Study Operations" -ForegroundColor Cyan
$query5d = @'
SELECT
    'STUDY_OPERATIONS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    cd.NICE_NAME as operation_class,
    NVL(o.OPERATIONTYPE_S_, '') as operation_type,
    TO_CHAR(o.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(o.LASTMODIFIEDBY_S_, '') as modified_by,
    CASE
        WHEN o.NAME_S_ LIKE 'PG%' THEN 'Weld Point Group'
        WHEN o.NAME_S_ LIKE 'MOV\_%' ESCAPE '\' THEN 'Movement Operation'
        WHEN o.NAME_S_ LIKE 'tip\_%' ESCAPE '\' THEN 'Tool Maintenance'
        WHEN o.NAME_S_ LIKE '%WELD%' THEN 'Weld Operation'
        ELSE 'Other'
    END as operation_category
FROM ##SCHEMA##.OPERATION_ o
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
WHERE o.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND o.CLASS_ID = 141
  AND ROWNUM <= 100
ORDER BY o.MODIFICATIONDATE_DA_ DESC;
'@
$query5d = $query5d.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.studyOperations = Execute-Query -QueryName "StudyOperations" -Query $query5d

# QUERY 5E: Study Movements
Write-Host "`n[9/11] Study Movement/Location Changes" -ForegroundColor Cyan
$query5e = @'
SELECT
    'STUDY_MOVEMENTS' as work_type,
    sl.OBJECT_ID as studylayout_id,
    sl.STUDYINFO_SR_ as studyinfo_id,
    TO_CHAR(sl.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(sl.LASTMODIFIEDBY_S_, '') as modified_by,
    sl.LOCATION_V_ as location_vector_id,
    sl.ROTATION_V_ as rotation_vector_id
FROM ##SCHEMA##.STUDYLAYOUT_ sl
WHERE sl.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 100
ORDER BY sl.MODIFICATIONDATE_DA_ DESC;
'@
$query5e = $query5e.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.studyMovements = Execute-Query -QueryName "StudyMovements" -Query $query5e

# QUERY 5F: Study Welds
Write-Host "`n[10/11] Study Weld Points" -ForegroundColor Cyan
$query5f = @'
SELECT
    'STUDY_WELDS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    TO_CHAR(o.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(o.LASTMODIFIEDBY_S_, '') as modified_by
FROM ##SCHEMA##.OPERATION_ o
WHERE o.CLASS_ID = 141
  AND o.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  AND ROWNUM <= 100
ORDER BY o.MODIFICATIONDATE_DA_ DESC;
'@
$query5f = $query5f.Replace('##SCHEMA##', $Schema).Replace('##STARTDATE##', $startDateStr)
$results.studyWelds = Execute-Query -QueryName "StudyWelds" -Query $query5f

# QUERY 6: User Activity
Write-Host "`n[11/11] User Activity Summary" -ForegroundColor Cyan
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

Write-Host "  ??? Results saved to: $finalOutput" -ForegroundColor Green

$scriptTimer.Stop()
Write-Host "`n  Total time: $([math]::Round($scriptTimer.Elapsed.TotalSeconds, 2))s" -ForegroundColor Cyan
Write-Host ""
