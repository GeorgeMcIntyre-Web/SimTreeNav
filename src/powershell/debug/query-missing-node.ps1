# Query Missing Node from Database
# Finds a specific node in the database and shows why it might be filtered out

param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ObjectId,

    [int]$ProjectId
)

$ErrorActionPreference = "Stop"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

Write-Host "==== QUERY MISSING NODE FROM DATABASE ====" -ForegroundColor Cyan
Write-Host "TNS: $TNSName | Schema: $Schema | OBJECT_ID: $ObjectId" -ForegroundColor White
Write-Host ""

# Query 1: Find the node in all possible tables
Write-Host "[1/4] Searching for OBJECT_ID $ObjectId in database tables..." -ForegroundColor Yellow

$findNodeSql = @"
SET PAGESIZE 50
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Check COLLECTION_ table
SELECT 'COLLECTION_' AS TABLE_NAME,
       c.OBJECT_ID,
       c.CAPTION_S_ AS NAME,
       c.EXTERNALID_S_ AS EXTERNAL_ID,
       cd.NAME AS CLASS_NAME,
       cd.NICE_NAME,
       cd.TYPE_ID
FROM $Schema.COLLECTION_ c
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE c.OBJECT_ID = $ObjectId
UNION ALL
-- Check PART_ table
SELECT 'PART_' AS TABLE_NAME,
       p.OBJECT_ID,
       p.NAME_S_ AS NAME,
       p.EXTERNALID_S_ AS EXTERNAL_ID,
       cd.NAME AS CLASS_NAME,
       cd.NICE_NAME,
       cd.TYPE_ID
FROM $Schema.PART_ p
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE p.OBJECT_ID = $ObjectId
UNION ALL
-- Check OPERATION_ table
SELECT 'OPERATION_' AS TABLE_NAME,
       op.OBJECT_ID,
       op.NAME_S_ AS NAME,
       op.EXTERNALID_S_ AS EXTERNAL_ID,
       cd.NAME AS CLASS_NAME,
       cd.NICE_NAME,
       cd.TYPE_ID
FROM $Schema.OPERATION_ op
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON op.CLASS_ID = cd.TYPE_ID
WHERE op.OBJECT_ID = $ObjectId
UNION ALL
-- Check RESOURCE_ table
SELECT 'RESOURCE_' AS TABLE_NAME,
       r.OBJECT_ID,
       r.NAME_S_ AS NAME,
       r.EXTERNALID_S_ AS EXTERNAL_ID,
       cd.NAME AS CLASS_NAME,
       cd.NICE_NAME,
       cd.TYPE_ID
FROM $Schema.RESOURCE_ r
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
WHERE r.OBJECT_ID = $ObjectId
UNION ALL
-- Check ROBCADSTUDY_ table
SELECT 'ROBCADSTUDY_' AS TABLE_NAME,
       rs.OBJECT_ID,
       rs.NAME_S_ AS NAME,
       rs.EXTERNALID_S_ AS EXTERNAL_ID,
       cd.NAME AS CLASS_NAME,
       cd.NICE_NAME,
       cd.TYPE_ID
FROM $Schema.ROBCADSTUDY_ rs
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
WHERE rs.OBJECT_ID = $ObjectId;

EXIT;
"@

$findNodeFile = "find-node-${Schema}-${ObjectId}.sql"
[System.IO.File]::WriteAllText("$PWD\$findNodeFile", $findNodeSql, $utf8NoBom)

$findResult = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$findNodeFile" 2>&1
Remove-Item $findNodeFile -ErrorAction SilentlyContinue

Write-Host "Database Query Results:" -ForegroundColor Cyan
$findResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Write-Host ""

# Query 2: Find parent relationship
Write-Host "[2/4] Checking parent relationship in REL_COMMON..." -ForegroundColor Yellow

$parentSql = @"
SET PAGESIZE 50
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

SELECT
    r.FORWARD_OBJECT_ID AS PARENT_ID,
    r.OBJECT_ID AS CHILD_ID,
    r.SEQ_NUMBER,
    'Parent info:' AS SEPARATOR,
    NVL(c.CAPTION_S_, p.NAME_S_) AS PARENT_NAME,
    NVL(cd.NICE_NAME, 'Unknown') AS PARENT_TYPE
FROM $Schema.REL_COMMON r
LEFT JOIN $Schema.COLLECTION_ c ON r.FORWARD_OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.PART_ p ON r.FORWARD_OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON COALESCE(c.CLASS_ID, p.CLASS_ID) = cd.TYPE_ID
WHERE r.OBJECT_ID = $ObjectId;

EXIT;
"@

$parentFile = "find-parent-${Schema}-${ObjectId}.sql"
[System.IO.File]::WriteAllText("$PWD\$parentFile", $parentSql, $utf8NoBom)

$parentResult = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$parentFile" 2>&1
Remove-Item $parentFile -ErrorAction SilentlyContinue

Write-Host "Parent Relationship:" -ForegroundColor Cyan
$parentResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
Write-Host ""

# Query 3: Check if parent is in project tree
if ($ProjectId -gt 0) {
    Write-Host "[3/4] Checking if parent is reachable from project root..." -ForegroundColor Yellow

    $reachableSql = @"
SET PAGESIZE 50
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Check if node or its parent is in temp_project_objects equivalent
SELECT
    'Node reachable:' AS STATUS,
    COUNT(*) AS IS_REACHABLE
FROM $Schema.REL_COMMON rc
WHERE rc.OBJECT_ID = $ObjectId
  AND EXISTS (
    SELECT 1
    FROM $Schema.REL_COMMON rc2
    CONNECT BY NOCYCLE PRIOR rc2.FORWARD_OBJECT_ID = rc2.OBJECT_ID
    START WITH rc2.OBJECT_ID = $ObjectId
    WHERE rc2.FORWARD_OBJECT_ID = $ProjectId
  );

-- Check parent reachability
SELECT
    'Parent reachable:' AS STATUS,
    COUNT(*) AS PARENT_REACHABLE
FROM $Schema.REL_COMMON r
WHERE r.OBJECT_ID = $ObjectId
  AND EXISTS (
    SELECT 1
    FROM $Schema.REL_COMMON rc
    WHERE rc.OBJECT_ID = r.FORWARD_OBJECT_ID
    CONNECT BY NOCYCLE PRIOR rc.FORWARD_OBJECT_ID = rc.OBJECT_ID
    START WITH rc.OBJECT_ID = r.FORWARD_OBJECT_ID
    WHERE rc.FORWARD_OBJECT_ID = $ProjectId
  );

EXIT;
"@

    $reachableFile = "check-reachable-${Schema}-${ObjectId}.sql"
    [System.IO.File]::WriteAllText("$PWD\$reachableFile", $reachableSql, $utf8NoBom)

    $reachableResult = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$reachableFile" 2>&1
    Remove-Item $reachableFile -ErrorAction SilentlyContinue

    Write-Host "Reachability from Project Root:" -ForegroundColor Cyan
    $reachableResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    Write-Host ""
}

# Query 4: Check what query SHOULD have included it
Write-Host "[4/4] Determining which SQL query should include this node..." -ForegroundColor Yellow
Write-Host ""

# Parse results to determine table
$tableFound = $null
foreach ($line in $findResult) {
    if ($line -match '^(COLLECTION_|PART_|OPERATION_|RESOURCE_|ROBCADSTUDY_)') {
        $tableFound = $matches[1]
        break
    }
}

if ($tableFound) {
    Write-Host "Node found in table: $tableFound" -ForegroundColor Green
    Write-Host ""

    switch ($tableFound) {
        'COLLECTION_' {
            Write-Host "This is a COLLECTION_ node." -ForegroundColor Cyan
            Write-Host "Should be included by:" -ForegroundColor Yellow
            Write-Host "  - Level 2+ hierarchical query (line ~495-510 in generate-tree-html.ps1)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Possible issues:" -ForegroundColor Yellow
            Write-Host "  - Parent not in COLLECTION_ table" -ForegroundColor Gray
            Write-Host "  - Cycle prevention (NOCYCLE) skipping it" -ForegroundColor Gray
            Write-Host "  - START WITH filter excluding its branch" -ForegroundColor Gray
        }
        'PART_' {
            Write-Host "This is a PART_ node." -ForegroundColor Cyan
            Write-Host "Should be included by:" -ForegroundColor Yellow
            Write-Host "  - PART_ with COLLECTION_ parent query (line ~517-536)" -ForegroundColor Gray
            Write-Host "  - PART_ with PART_ parent query (line ~577-584)" -ForegroundColor Gray
            Write-Host "  - TxProcessAssembly query (line ~928-945) if CLASS_ID=133" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Possible issues:" -ForegroundColor Yellow
            Write-Host "  - Parent validation failing (parent not in COLLECTION_ or temp_project_objects)" -ForegroundColor Gray
            Write-Host "  - Reverse relationship filter excluding it" -ForegroundColor Gray
            Write-Host "  - Node exists in COLLECTION_ table (excluded by NOT EXISTS check)" -ForegroundColor Gray
        }
        'OPERATION_' {
            Write-Host "This is an OPERATION_ node." -ForegroundColor Cyan
            Write-Host "Should be included by:" -ForegroundColor Yellow
            Write-Host "  - OPERATION_ query (line ~895-909)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Possible issues:" -ForegroundColor Yellow
            Write-Host "  - Not in temp_project_objects (iterative discovery missed it)" -ForegroundColor Gray
            Write-Host "  - Parent relationship not via REL_COMMON.FORWARD_OBJECT_ID" -ForegroundColor Gray
        }
        'RESOURCE_' {
            Write-Host "This is a RESOURCE_ node." -ForegroundColor Cyan
            Write-Host "Should be included by:" -ForegroundColor Yellow
            Write-Host "  - RESOURCE_ query (line ~822-842)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Possible issues:" -ForegroundColor Yellow
            Write-Host "  - Parent not in temp_project_objects" -ForegroundColor Gray
            Write-Host "  - Parent validation requiring COLLECTION_ parent" -ForegroundColor Gray
        }
        'ROBCADSTUDY_' {
            Write-Host "This is a ROBCADSTUDY_ node." -ForegroundColor Cyan
            Write-Host "Should be included by:" -ForegroundColor Yellow
            Write-Host "  - RobcadStudy query (line ~618-638)" -ForegroundColor Gray
            Write-Host ""
            Write-Host "Possible issues:" -ForegroundColor Yellow
            Write-Host "  - Parent not in COLLECTION_ table" -ForegroundColor Gray
            Write-Host "  - Parent not reachable from project via hierarchical query" -ForegroundColor Gray
        }
    }
} else {
    Write-Host "Node NOT FOUND in any table!" -ForegroundColor Red
    Write-Host "  - OBJECT_ID may be invalid" -ForegroundColor Gray
    Write-Host "  - Node may have been deleted" -ForegroundColor Gray
    Write-Host "  - Node may be in a specialized table not queried" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==== ANALYSIS COMPLETE ====" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Check parent OBJECT_ID exists in tree" -ForegroundColor Gray
Write-Host "2. Verify SQL query for this table type includes it" -ForegroundColor Gray
Write-Host "3. Test WHERE clause conditions against this node" -ForegroundColor Gray
Write-Host "4. Add logging to SQL to see if node is queried but filtered" -ForegroundColor Gray
