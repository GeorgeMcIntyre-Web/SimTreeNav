# Extract-Operations.ps1
# Iterative extraction of OPERATION_ nodes using temp table approach
# Handles deep nesting (28+ levels) by building tree incrementally

param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ProjectId,

    [Parameter(Mandatory=$true)]
    [string]$OutputFile = "operations-data.txt"
)

$ErrorActionPreference = "Stop"

# Import credential manager
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $scriptDir "..\utilities\CredentialManager.ps1") -Force

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  OPERATION_ Node Extraction" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Project ID: $ProjectId" -ForegroundColor White
Write-Host "Schema: $Schema" -ForegroundColor White
Write-Host "`n"

# Get connection string
$connStr = Get-DbConnectionString -TNSName $TNSName -AsSysDBA

# Set Oracle environment
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

# Create SQL script for iterative extraction
$sqlScript = @"
SET PAGESIZE 0
SET LINESIZE 32767
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON
SET TRIMOUT ON
SET VERIFY OFF

-- Create temp table to store discovered object IDs
CREATE GLOBAL TEMPORARY TABLE temp_project_objects (
    OBJECT_ID NUMBER PRIMARY KEY,
    PASS_NUMBER NUMBER
) ON COMMIT PRESERVE ROWS;

-- Pass 0: Insert project root
INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
VALUES ($ProjectId, 0);

-- Pass 1: Get all COLLECTION_ nodes under project
INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
SELECT DISTINCT c.OBJECT_ID, 1
FROM $Schema.COLLECTION_ c
INNER JOIN $Schema.REL_COMMON rc ON c.OBJECT_ID = rc.OBJECT_ID
WHERE rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM temp_project_objects WHERE OBJECT_ID = c.OBJECT_ID);

COMMIT;

-- Pass 2-10: Iteratively add child objects via REL_COMMON
-- Each pass adds objects whose parents were found in previous passes
DECLARE
    v_pass NUMBER := 2;
    v_rows_added NUMBER := 1;
    v_total_rows NUMBER := 0;
BEGIN
    WHILE v_pass <= 30 AND v_rows_added > 0 LOOP
        -- Add objects whose parent is in temp table
        INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
        SELECT DISTINCT rc.OBJECT_ID, v_pass
        FROM $Schema.REL_COMMON rc
        WHERE rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects WHERE PASS_NUMBER = v_pass - 1)
          AND NOT EXISTS (SELECT 1 FROM temp_project_objects WHERE OBJECT_ID = rc.OBJECT_ID);

        v_rows_added := SQL%ROWCOUNT;
        v_total_rows := v_total_rows + v_rows_added;

        COMMIT;

        DBMS_OUTPUT.PUT_LINE('Pass ' || v_pass || ': Added ' || v_rows_added || ' objects (Total: ' || v_total_rows || ')');

        v_pass := v_pass + 1;

        -- Exit if no new objects added
        EXIT WHEN v_rows_added = 0;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('Iteration complete after ' || (v_pass - 1) || ' passes');
END;
/

-- Now extract OPERATION_ nodes that are in our temp table
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    op.OBJECT_ID || '|' ||
    NVL(op.CAPTION_S_, NVL(op.NAME_S_, 'Unnamed Operation')) || '|' ||
    NVL(op.NAME_S_, 'Unnamed') || '|' ||
    NVL(op.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class Operation') || '|' ||
    NVL(cd.NICE_NAME, 'Operation') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.OPERATION_ op
INNER JOIN $Schema.REL_COMMON r ON op.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON op.CLASS_ID = cd.TYPE_ID
WHERE op.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

-- Clean up
DROP TABLE temp_project_objects;

EXIT;
"@

# Save SQL script to temp file
$tempSqlFile = [System.IO.Path]::GetTempFileName() + ".sql"
$sqlScript | Out-File -FilePath $tempSqlFile -Encoding ASCII

Write-Host "Extracting operations using iterative temp table approach..." -ForegroundColor Yellow
Write-Host "(This may take 2-3 minutes for large projects)" -ForegroundColor Gray
Write-Host ""

# Execute SQL
try {
    $result = sqlplus -S $connStr "@$tempSqlFile" 2>&1

    # Filter out DBMS_OUTPUT and save operation data
    $operationLines = $result | Where-Object {
        $_ -match '^\d+\|' -and $_ -notmatch '^Pass \d+:'
    }

    $operationLines | Out-File -FilePath $OutputFile -Encoding UTF8

    $operationCount = ($operationLines | Measure-Object).Count

    Write-Host "✓ Extracted $operationCount operations" -ForegroundColor Green
    Write-Host "  Output: $OutputFile" -ForegroundColor Cyan

    # Show iteration progress
    $progressLines = $result | Where-Object { $_ -match '^Pass \d+:' }
    if ($progressLines) {
        Write-Host "`nIteration Progress:" -ForegroundColor Yellow
        $progressLines | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    }

    return $operationCount
}
finally {
    # Clean up temp file
    if (Test-Path $tempSqlFile) {
        Remove-Item $tempSqlFile -Force
    }
}
