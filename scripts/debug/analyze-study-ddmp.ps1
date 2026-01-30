# Analyze Study: DDMP P702_8J_010_8J_060
# Purpose: Deep dive into all components that make up a study
# Date: 2026-01-19

param(
    [string]$Schema = "DESIGN12",
    [string]$StudyName = "DDMP P702_8J_010_8J_060"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Study Analysis: $StudyName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Import credential manager
$credPath = Join-Path $PSScriptRoot "src\powershell\utilities\CredentialManager.ps1"
if (Test-Path $credPath) {
    Import-Module $credPath -Force
}

# Query 1: Basic Study Information
Write-Host "[1/8] Basic Study Information" -ForegroundColor Yellow
$query1 = @"
SET PAGESIZE 100
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

SELECT
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    cd.NICE_NAME as study_type,
    rs.CLASS_ID as class_id,
    rs.CREATEDBY_S_ as created_by,
    TO_CHAR(rs.CREATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as created_date,
    rs.LASTMODIFIEDBY_S_ as modified_by,
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as modified_date,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user,
    p.WORKING_VERSION_ID as version_id,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Active' ELSE 'Idle' END as status
FROM $Schema.ROBCADSTUDY_ rs
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE rs.NAME_S_ = '$StudyName';

EXIT;
"@

$tempFile1 = Join-Path $env:TEMP "study-basic-info.sql"
$query1 | Out-File $tempFile1 -Encoding ASCII
$result1 = sqlplus -S sys/change_on_install@DB01 AS SYSDBA "@$tempFile1" 2>&1
Write-Host $result1
Write-Host ""
Remove-Item $tempFile1 -ErrorAction SilentlyContinue

# Query 2: All Shortcuts (Resources and Operations)
Write-Host "[2/8] Shortcuts (Resources & Operation References)" -ForegroundColor Yellow
$query2 = @"
SET PAGESIZE 200
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

SELECT
    s.OBJECT_ID as shortcut_id,
    s.NAME_S_ as shortcut_name,
    cd.NICE_NAME as shortcut_type,
    r.SEQ_NUMBER as sequence,
    CASE
        WHEN s.NAME_S_ = 'LAYOUT' THEN 'Layout Configuration'
        WHEN s.NAME_S_ LIKE '8J-%' AND s.NAME_S_ NOT LIKE '%\_%' ESCAPE '\' THEN 'Station Reference'
        WHEN s.NAME_S_ LIKE '%\_CMN' ESCAPE '\' THEN 'Common Operations'
        WHEN s.NAME_S_ LIKE '%\_SC' ESCAPE '\' THEN 'Spot Coat Operations'
        WHEN s.NAME_S_ LIKE '%\_RC' ESCAPE '\' THEN 'Robot Coat Operations'
        WHEN s.NAME_S_ LIKE '%\_CC' ESCAPE '\' THEN 'Cell Coat Operations'
        ELSE 'Other'
    END as category
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN $Schema.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON s.CLASS_ID = cd.TYPE_ID
WHERE rs.NAME_S_ = '$StudyName'
ORDER BY r.SEQ_NUMBER;

EXIT;
"@

$tempFile2 = Join-Path $env:TEMP "study-shortcuts.sql"
$query2 | Out-File $tempFile2 -Encoding ASCII
$result2 = sqlplus -S sys/change_on_install@DB01 AS SYSDBA "@$tempFile2" 2>&1
Write-Host $result2
Write-Host ""
Remove-Item $tempFile2 -ErrorAction SilentlyContinue

# Query 3: Panel Codes Used
Write-Host "[3/8] Panel Codes (CC, RC, SC, CMN)" -ForegroundColor Yellow
$query3 = @"
SET PAGESIZE 200
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

SELECT
    s.NAME_S_ as shortcut_name,
    CASE
        WHEN s.NAME_S_ LIKE '%\_CC' ESCAPE '\' THEN 'CC (Cell Coat)'
        WHEN s.NAME_S_ LIKE '%\_RC' ESCAPE '\' THEN 'RC (Robot Coat)'
        WHEN s.NAME_S_ LIKE '%\_SC' ESCAPE '\' THEN 'SC (Spot Coat)'
        WHEN s.NAME_S_ LIKE '%\_CMN' ESCAPE '\' THEN 'CMN (Common)'
        ELSE 'N/A'
    END as panel_code,
    SUBSTR(s.NAME_S_, 1, INSTR(s.NAME_S_, '_') - 1) as station,
    r.SEQ_NUMBER as sequence
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN $Schema.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE rs.NAME_S_ = '$StudyName'
  AND s.NAME_S_ LIKE '%\_%' ESCAPE '\'
ORDER BY s.NAME_S_;

EXIT;
"@

$tempFile3 = Join-Path $env:TEMP "study-panels.sql"
$query3 | Out-File $tempFile3 -Encoding ASCII
$result3 = sqlplus -S sys/change_on_install@DB01 AS SYSDBA "@$tempFile3" 2>&1
Write-Host $result3
Write-Host ""
Remove-Item $tempFile3 -ErrorAction SilentlyContinue

# Query 4: Station References (Resources)
Write-Host "[4/8] Station References" -ForegroundColor Yellow
$query4 = @"
SET PAGESIZE 200
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

SELECT
    s.NAME_S_ as station_shortcut,
    res.OBJECT_ID as resource_id,
    res.NAME_S_ as resource_name,
    cd.NICE_NAME as resource_type
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN $Schema.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN $Schema.RESOURCE_ res ON s.NAME_S_ = res.NAME_S_
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
WHERE rs.NAME_S_ = '$StudyName'
  AND s.NAME_S_ LIKE '8J-%'
  AND s.NAME_S_ NOT LIKE '%\_%' ESCAPE '\'
ORDER BY s.NAME_S_;

EXIT;
"@

$tempFile4 = Join-Path $env:TEMP "study-stations.sql"
$query4 | Out-File $tempFile4 -Encoding ASCII
$result4 = sqlplus -S sys/change_on_install@DB01 AS SYSDBA "@$tempFile4" 2>&1
Write-Host $result4
Write-Host ""
Remove-Item $tempFile4 -ErrorAction SilentlyContinue

# Query 5: ROBCADSTUDYINFO and LAYOUT relationship
Write-Host "[5/8] Study Info & Layout" -ForegroundColor Yellow
$query5 = @"
SET PAGESIZE 100
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

SELECT
    rsi.OBJECT_ID as studyinfo_id,
    rsi.NAME_S_ as studyinfo_name,
    rsi.STUDY_SR_ as study_ref,
    rsi.LAYOUT_SR_ as layout_ref,
    TO_CHAR(rsi.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as modified_date
FROM $Schema.ROBCADSTUDY_ rs
LEFT JOIN $Schema.ROBCADSTUDYINFO_ rsi ON rs.OBJECT_ID = rsi.STUDY_SR_
WHERE rs.NAME_S_ = '$StudyName';

EXIT;
"@

$tempFile5 = Join-Path $env:TEMP "study-info.sql"
$query5 | Out-File $tempFile5 -Encoding ASCII
$result5 = sqlplus -S sys/change_on_install@DB01 AS SYSDBA "@$tempFile5" 2>&1
Write-Host $result5
Write-Host ""
Remove-Item $tempFile5 -ErrorAction SilentlyContinue

# Query 6: STUDYLAYOUT (Location/Rotation tracking)
Write-Host "[6/8] Study Layout (Location & Rotation Vectors)" -ForegroundColor Yellow
$query6 = @"
SET PAGESIZE 100
SET LINESIZE 400
SET FEEDBACK OFF
SET HEADING ON

SELECT
    sl.OBJECT_ID as studylayout_id,
    sl.STUDYINFO_SR_ as studyinfo_ref,
    sl.OBJECT_ID as location_vector_id,
    sl.OBJECT_ID as rotation_vector_id,
    TO_CHAR(sl.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as modified_date,
    sl.LASTMODIFIEDBY_S_ as modified_by,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 0 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as x_coord,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 1 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as y_coord,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 2 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as z_coord
FROM $Schema.ROBCADSTUDY_ rs
LEFT JOIN $Schema.ROBCADSTUDYINFO_ rsi ON rs.OBJECT_ID = rsi.STUDY_SR_
LEFT JOIN $Schema.STUDYLAYOUT_ sl ON rsi.OBJECT_ID = sl.STUDYINFO_SR_
WHERE rs.NAME_S_ = '$StudyName';

EXIT;
"@

$tempFile6 = Join-Path $env:TEMP "study-layout.sql"
$query6 | Out-File $tempFile6 -Encoding ASCII
$result6 = sqlplus -S sys/change_on_install@DB01 AS SYSDBA "@$tempFile6" 2>&1
Write-Host $result6
Write-Host ""
Remove-Item $tempFile6 -ErrorAction SilentlyContinue

# Query 7: Operations (if any directly under study)
Write-Host "[7/8] Operations (Weld Points, Movements)" -ForegroundColor Yellow
$query7 = @"
SET PAGESIZE 200
SET LINESIZE 400
SET FEEDBACK OFF
SET HEADING ON

SELECT
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    cd.NICE_NAME as operation_class,
    o.OPERATIONTYPE_S_ as operation_type,
    o.ALLOCATEDTIME_D_ as allocated_time,
    o.CALCULATEDTIME_D_ as calculated_time,
    TO_CHAR(o.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as modified_date,
    CASE
        WHEN o.NAME_S_ LIKE 'PG%' THEN 'Weld Point Group'
        WHEN o.NAME_S_ LIKE 'MOV\_%' ESCAPE '\' THEN 'Movement Operation'
        WHEN o.NAME_S_ LIKE 'tip\_%' ESCAPE '\' THEN 'Tool Maintenance'
        ELSE 'Other'
    END as category
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN $Schema.OPERATION_ o ON r.OBJECT_ID = o.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
WHERE rs.NAME_S_ = '$StudyName'
  AND ROWNUM <= 50
ORDER BY o.MODIFICATIONDATE_DA_ DESC;

EXIT;
"@

$tempFile7 = Join-Path $env:TEMP "study-operations.sql"
$query7 | Out-File $tempFile7 -Encoding ASCII
$result7 = sqlplus -S sys/change_on_install@DB01 AS SYSDBA "@$tempFile7" 2>&1
Write-Host $result7
Write-Host ""
Remove-Item $tempFile7 -ErrorAction SilentlyContinue

# Query 8: Summary Statistics
Write-Host "[8/8] Summary Statistics" -ForegroundColor Yellow
$query8 = @"
SET PAGESIZE 100
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

SELECT
    'Total Shortcuts' as metric,
    COUNT(*) as count
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN $Schema.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE rs.NAME_S_ = '$StudyName'

UNION ALL

SELECT
    'Station References' as metric,
    COUNT(*) as count
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN $Schema.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE rs.NAME_S_ = '$StudyName'
  AND s.NAME_S_ LIKE '8J-%'
  AND s.NAME_S_ NOT LIKE '%\_%' ESCAPE '\'

UNION ALL

SELECT
    'Panel Operations' as metric,
    COUNT(*) as count
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN $Schema.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE rs.NAME_S_ = '$StudyName'
  AND s.NAME_S_ LIKE '%\_%' ESCAPE '\'

UNION ALL

SELECT
    'Operations' as metric,
    COUNT(*) as count
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN $Schema.OPERATION_ o ON r.OBJECT_ID = o.OBJECT_ID
WHERE rs.NAME_S_ = '$StudyName'

UNION ALL

SELECT
    'Layout Entries' as metric,
    COUNT(*) as count
FROM $Schema.ROBCADSTUDY_ rs
LEFT JOIN $Schema.ROBCADSTUDYINFO_ rsi ON rs.OBJECT_ID = rsi.STUDY_SR_
LEFT JOIN $Schema.STUDYLAYOUT_ sl ON rsi.OBJECT_ID = sl.STUDYINFO_SR_
WHERE rs.NAME_S_ = '$StudyName';

EXIT;
"@

$tempFile8 = Join-Path $env:TEMP "study-summary.sql"
$query8 | Out-File $tempFile8 -Encoding ASCII
$result8 = sqlplus -S sys/change_on_install@DB01 AS SYSDBA "@$tempFile8" 2>&1
Write-Host $result8
Write-Host ""
Remove-Item $tempFile8 -ErrorAction SilentlyContinue

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Analysis Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
