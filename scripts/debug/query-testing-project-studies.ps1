# Query Studies in _testing Project
# Purpose: Find available studies under DESIGN12/_testing for E2E validation
# Date: 2026-01-29

param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [string]$Schema = "DESIGN12",
    [string]$ProjectName = "_testing"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Query _testing Project Studies" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TNS:        $TNSName" -ForegroundColor Gray
Write-Host "  Schema:     $Schema" -ForegroundColor Gray
Write-Host "  Project:    $ProjectName" -ForegroundColor Gray
Write-Host ""

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "..\..\src\powershell\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    . $credManagerPath
} else {
    Write-Warning "Credential manager not found at: $credManagerPath"
    Write-Error "Cannot proceed without credential manager. Please ensure the file exists."
    exit 1
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
        $tempSqlFile = Join-Path $env:TEMP "${QueryName}.sql"

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

        # Execute query with timeout
        $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop

        if ($connectionString) {
            # Use job with timeout to prevent hanging
            $timeoutSeconds = 30
            $job = Start-Job -ScriptBlock {
                param($connStr, $sqlFile)
                $result = & sqlplus -S $connStr "@$sqlFile" 2>&1
                return $result
            } -ArgumentList $connectionString, $tempSqlFile

            $completed = Wait-Job $job -Timeout $timeoutSeconds

            if (-not $completed) {
                Stop-Job $job -ErrorAction SilentlyContinue
                Remove-Job $job -Force -ErrorAction SilentlyContinue
                Write-Warning "    Query timed out after $timeoutSeconds seconds"
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

            # Parse results (pipe-delimited)
            $data = $result | Where-Object { $_ -match '\|' }

            # Cleanup
            Remove-Item $tempSqlFile -ErrorAction SilentlyContinue

            Write-Host "    ✓ Query complete" -ForegroundColor Green
            return $data
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

# QUERY 1: Find _testing project ID
Write-Host "`n[1/3] Finding _testing project..." -ForegroundColor Cyan

# Projects have CLASS_ID = 64
# Use SQL concatenation for pipe-delimited output since SET COLSEP doesn't work reliably
$query1 = @"
SELECT
    c.OBJECT_ID || '|' || c.CAPTION_S_ || '|' || c.CLASS_ID as RESULT
FROM $Schema.COLLECTION_ c
WHERE c.CAPTION_S_ = '$ProjectName'
  AND c.CLASS_ID = 64
  AND ROWNUM = 1;
"@

$projectResults = Execute-Query -QueryName "FindProject" -Query $query1

if ($projectResults.Count -eq 0) {
    Write-Warning "Project '$ProjectName' not found in schema $Schema"
    Write-Host "`nLet me show you what projects ARE available..." -ForegroundColor Cyan

    # Query for all projects - show everything to find the pattern
    $allProjectsQuery = @"
SELECT
    c.OBJECT_ID as PROJECT_ID,
    c.CAPTION_S_ as PROJECT_NAME,
    c.CLASS_ID as CLASS_ID,
    cd.NICE_NAME as TYPE_NAME
FROM $Schema.COLLECTION_ c
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE c.CAPTION_S_ IS NOT NULL
  AND c.CAPTION_S_ NOT LIKE '%icon%'
  AND c.CAPTION_S_ NOT LIKE '%Image%'
ORDER BY c.MODIFICATIONDATE_DA_ DESC
FETCH FIRST 30 ROWS ONLY;
"@

    $allProjects = Execute-Query -QueryName "AllProjects" -Query $allProjectsQuery

    if ($allProjects.Count -gt 1) {
        Write-Host "`nAvailable Projects in $Schema schema:" -ForegroundColor Green
        Write-Host "(Showing: PROJECT_ID | PROJECT_NAME | CLASS_ID | TYPE_NAME)" -ForegroundColor Gray
        Write-Host ""
        $headers = ($allProjects[0] -split '\|') | ForEach-Object { $_.Trim() }
        $projectLines = $allProjects[1..($allProjects.Count - 1)] | Where-Object { $_ -match '\d+\|' }

        $count = 0
        foreach ($line in $projectLines) {
            $count++
            $values = $line -split '\|', 4
            $projId = if ($values[0]) { $values[0].Trim() } else { "?" }
            $projName = if ($values[1]) { $values[1].Trim() } else { "(no name)" }
            $classId = if ($values[2]) { $values[2].Trim() } else { "?" }
            $typeName = if ($values.Count -gt 3 -and $values[3]) { $values[3].Trim() } else { "?" }

            Write-Host "  [$count] Name: '$projName' | Type: $typeName | ID: $projId | Class: $classId" -ForegroundColor White
        }

        Write-Host "`nPlease choose one of these projects and re-run:" -ForegroundColor Yellow
        Write-Host "  pwsh scripts/debug/query-testing-project-studies.ps1 -TNSName '$TNSName' -ProjectName 'PROJECT_NAME_HERE'" -ForegroundColor Gray
    }

    exit 1
}

# Parse project ID from first result (skip header)
$projectLine = $projectResults | Where-Object { $_ -match '\d+\|' } | Select-Object -First 1
if (-not $projectLine) {
    Write-Error "ERROR: Could not parse project ID from results"
    exit 1
}

$projectId = ($projectLine -split '\|')[0].Trim()
Write-Host "  Project ID: $projectId" -ForegroundColor Green

# QUERY 2: Find all studies under _testing project
Write-Host "`n[2/3] Finding studies under _testing..." -ForegroundColor Cyan

$query2 = @"
SELECT
    rs.OBJECT_ID || '|' ||
    rs.NAME_S_ || '|' ||
    NVL(cd.NICE_NAME, '') || '|' ||
    NVL(rs.CREATEDBY_S_, '') || '|' ||
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') || '|' ||
    NVL(p.WORKING_VERSION_ID, 0) || '|' ||
    NVL(u.CAPTION_S_, '') as RESULT
FROM $Schema.ROBCADSTUDY_ rs
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.USER_ u ON p.OWNER_ID = u.OBJECT_ID
INNER JOIN $Schema.REL_COMMON rc ON rs.OBJECT_ID = rc.OBJECT_ID
WHERE rc.FORWARD_OBJECT_ID = $projectId
  AND rs.NAME_S_ IS NOT NULL
ORDER BY rs.MODIFICATIONDATE_DA_ DESC;
"@

$studyResults = Execute-Query -QueryName "FindStudies" -Query $query2

if ($studyResults.Count -lt 2) {
    Write-Error "ERROR: No studies found under project '$ProjectName'"
    exit 1
}

# Display results
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Studies Found in _testing Project" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

# Parse and display each study (skip header line)
$headers = ($studyResults[0] -split '\|') | ForEach-Object { $_.Trim() }
$studyLines = $studyResults[1..($studyResults.Count - 1)] | Where-Object { $_ -match '\d+\|' }

$studyCount = 0
foreach ($line in $studyLines) {
    $studyCount++
    $values = $line -split '\|'

    $studyId = $values[0].Trim()
    $studyName = $values[1].Trim()
    $studyType = $values[2].Trim()
    $createdBy = $values[3].Trim()
    $lastModified = $values[4].Trim()
    $checkoutVersion = $values[5].Trim()
    $checkedOutBy = if ($values.Count -gt 6) { $values[6].Trim() } else { "" }

    Write-Host "[$studyCount] $studyName" -ForegroundColor Cyan
    Write-Host "    Study ID:        $studyId" -ForegroundColor Gray
    Write-Host "    Type:            $studyType" -ForegroundColor Gray
    Write-Host "    Created By:      $createdBy" -ForegroundColor Gray
    Write-Host "    Last Modified:   $lastModified" -ForegroundColor Gray

    if ([int]$checkoutVersion -gt 0) {
        Write-Host "    Checkout Status: CHECKED OUT by $checkedOutBy (version $checkoutVersion)" -ForegroundColor Yellow
    } else {
        Write-Host "    Checkout Status: Available" -ForegroundColor Green
    }
    Write-Host ""
}

# QUERY 3: Get layout/operation details for first available study
Write-Host "`n[3/3] Checking first available study for E2E suitability..." -ForegroundColor Cyan

# Find first study that's not checked out
$firstAvailableStudy = $null
foreach ($line in $studyLines) {
    $values = $line -split '\|'
    $checkoutVersion = $values[5].Trim()

    if ([int]$checkoutVersion -eq 0) {
        $firstAvailableStudy = @{
            studyId = $values[0].Trim()
            studyName = $values[1].Trim()
        }
        break
    }
}

if (-not $firstAvailableStudy) {
    Write-Warning "No available (unchecked-out) studies found. E2E test requires an available study."
} else {
    $targetStudyId = $firstAvailableStudy.studyId
    $targetStudyName = $firstAvailableStudy.studyName

    Write-Host "  Recommended E2E Study: $targetStudyName (ID: $targetStudyId)" -ForegroundColor Green

    # Query for layout objects and operations
    $query3 = @"
SELECT
    'LAYOUT' as ITEM_TYPE,
    sl.OBJECT_ID as ITEM_ID,
    sl.OBJECT_ID as LOCATION_VECTOR_ID,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 0 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as X_COORD,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 1 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as Y_COORD,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 2 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as Z_COORD
FROM $Schema.STUDYLAYOUT_ sl
WHERE sl.STUDYINFO_SR_ IN (
    SELECT r_info.OBJECT_ID
    FROM $Schema.REL_COMMON r_info
    WHERE r_info.FORWARD_OBJECT_ID = $targetStudyId
      AND r_info.CLASS_ID = 71
)
  AND EXISTS (
    SELECT 1 FROM $Schema.VEC_LOCATION_ vl
    WHERE vl.OBJECT_ID = sl.OBJECT_ID
)
  AND ROWNUM <= 3
UNION ALL
SELECT
    'OPERATION' as ITEM_TYPE,
    o.OBJECT_ID as ITEM_ID,
    o.NAME_S_ as ITEM_NAME,
    o.OPERATIONTYPE_S_ as OPERATION_TYPE,
    '' as UNUSED1,
    '' as UNUSED2
FROM $Schema.OPERATION_ o
INNER JOIN $Schema.REL_COMMON rc ON o.OBJECT_ID = rc.OBJECT_ID
WHERE rc.FORWARD_OBJECT_ID IN (
    SELECT pa.OBJECT_ID
    FROM $Schema.PART_ pa
    INNER JOIN $Schema.REL_COMMON rc2 ON pa.OBJECT_ID = rc2.OBJECT_ID
    WHERE rc2.FORWARD_OBJECT_ID = $targetStudyId
      AND pa.CLASS_ID = 133
)
  AND o.CLASS_ID = 141
  AND ROWNUM <= 3;
"@

    $detailResults = Execute-Query -QueryName "StudyDetails" -Query $query3

    Write-Host "  Available for E2E modification:" -ForegroundColor Gray

    if ($detailResults.Count -gt 1) {
        $detailLines = $detailResults[1..($detailResults.Count - 1)] | Where-Object { $_ -match '\|' }
        foreach ($line in $detailLines) {
            Write-Host "    - $line" -ForegroundColor Gray
        }
    } else {
        Write-Host "    (Study appears empty or has no movable objects)" -ForegroundColor Yellow
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Query Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Total Studies: $studyCount" -ForegroundColor White
Write-Host "  Project ID:    $projectId" -ForegroundColor White
if ($firstAvailableStudy) {
    Write-Host "  Recommended:   $($firstAvailableStudy.studyName) (ID: $($firstAvailableStudy.studyId))" -ForegroundColor White
}
Write-Host ""

exit 0
