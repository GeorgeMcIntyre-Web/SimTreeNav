# Quick Study Summary
# Purpose: Get concise summary of DDMP P702_8J_010_8J_060 structure

$StudyName = "DDMP P702_8J_010_8J_060"

Write-Host "`nStudy: $StudyName`n" -ForegroundColor Cyan

$query = @"
SET PAGESIZE 50
SET LINESIZE 200
SET FEEDBACK OFF

-- Summary counts
SELECT 'Total Shortcuts' as component, COUNT(*) as count
FROM DESIGN12.ROBCADSTUDY_ rs
JOIN DESIGN12.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
JOIN DESIGN12.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE rs.NAME_S_ = '$StudyName'
UNION ALL
SELECT 'Station References', COUNT(DISTINCT s.NAME_S_)
FROM DESIGN12.ROBCADSTUDY_ rs
JOIN DESIGN12.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
JOIN DESIGN12.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE rs.NAME_S_ = '$StudyName'
AND s.NAME_S_ LIKE '8J-%' AND s.NAME_S_ NOT LIKE '%\_%' ESCAPE '\'
UNION ALL
SELECT 'Panel Operations', COUNT(*)
FROM DESIGN12.ROBCADSTUDY_ rs
JOIN DESIGN12.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
JOIN DESIGN12.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE rs.NAME_S_ = '$StudyName'
AND s.NAME_S_ LIKE '%\_%' ESCAPE '\';

EXIT;
"@

$tempFile = Join-Path $env:TEMP "study-summary.sql"
$query | Out-File $tempFile -Encoding ASCII
$result = sqlplus -S sys/change_on_install@DB01 AS SYSDBA "@$tempFile" 2>&1
$result
Remove-Item $tempFile -ErrorAction SilentlyContinue
