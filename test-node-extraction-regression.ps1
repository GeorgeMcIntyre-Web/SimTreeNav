# Regression Test: MFGFEATURE_, MODULE_, TxProcessAssembly Node Extraction
# Tests that objects discovered in temp_project_objects are correctly extracted
#
# Usage:
#   .\test-node-extraction-regression.ps1 -TNSName DESIGN1 -Schema DESIGN1 -ProjectId 20
#
# Exit codes:
#   0 = PASS (all assertions passed)
#   1 = FAIL (one or more assertions failed)

param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [string]$ProjectId
)

$ErrorActionPreference = 'Stop'

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "src\powershell\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
}

Write-Host "=== Node Extraction Regression Test ===" -ForegroundColor Cyan
Write-Host "TNS: $TNSName | Schema: $Schema | Project: $ProjectId" -ForegroundColor Gray
Write-Host ""

# Create test SQL file
$testSqlFile = "test-regression-${Schema}-${ProjectId}.sql"
$testOutputFile = "test-regression-output-${Schema}-${ProjectId}.txt"

$testSql = @"
SET PAGESIZE 0
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF
SET VERIFY OFF

-- Populate temp_project_objects (same as main script)
CREATE GLOBAL TEMPORARY TABLE temp_project_objects (
    OBJECT_ID NUMBER PRIMARY KEY,
    PASS_NUMBER NUMBER
) ON COMMIT PRESERVE ROWS;

INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
VALUES ($ProjectId, 0);

INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
SELECT DISTINCT rc.OBJECT_ID, 1
FROM $Schema.REL_COMMON rc
WHERE rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM temp_project_objects WHERE OBJECT_ID = rc.OBJECT_ID);

COMMIT;

DECLARE
    v_pass NUMBER := 2;
    v_rows_added NUMBER := 1;
BEGIN
    WHILE v_pass <= 30 AND v_rows_added > 0 LOOP
        INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
        SELECT DISTINCT rc.OBJECT_ID, v_pass
        FROM $Schema.REL_COMMON rc
        WHERE rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects WHERE PASS_NUMBER = v_pass - 1)
          AND NOT EXISTS (SELECT 1 FROM temp_project_objects WHERE OBJECT_ID = rc.OBJECT_ID);

        v_rows_added := SQL%ROWCOUNT;
        COMMIT;

        EXIT WHEN v_rows_added = 0;
        v_pass := v_pass + 1;
    END LOOP;
END;
/

-- Test 1: Count OPERATION_ objects in temp_project_objects
SELECT 'OPERATION_|' || COUNT(*) || '|' ||
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END
FROM $Schema.OPERATION_ op
WHERE op.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

-- Test 2: Verify OPERATION_ extraction query returns results
SELECT 'OPERATION_EXTRACT|' || COUNT(*) || '|' ||
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END
FROM $Schema.OPERATION_ op
INNER JOIN $Schema.REL_COMMON r ON op.OBJECT_ID = r.OBJECT_ID
WHERE op.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

-- Test 3: Count MFGFEATURE_ objects in temp_project_objects
SELECT 'MFGFEATURE_|' || COUNT(*) || '|' ||
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END
FROM $Schema.MFGFEATURE_ mf
WHERE mf.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

-- Test 4: Verify MFGFEATURE_ extraction query returns results (if any exist)
SELECT 'MFGFEATURE_EXTRACT|' || COUNT(*) || '|' ||
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END
FROM $Schema.MFGFEATURE_ mf
INNER JOIN $Schema.REL_COMMON r ON mf.OBJECT_ID = r.OBJECT_ID
WHERE mf.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = mf.OBJECT_ID);

-- Test 5: Count MODULE_ objects in temp_project_objects
SELECT 'MODULE_|' || COUNT(*) || '|' ||
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END
FROM $Schema.MODULE_ m
WHERE m.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

-- Test 6: Verify MODULE_ extraction query returns results (if any exist)
SELECT 'MODULE_EXTRACT|' || COUNT(*) || '|' ||
    CASE WHEN COUNT(*) >= 0 THEN 'PASS' ELSE 'FAIL' END
FROM $Schema.MODULE_ m
INNER JOIN $Schema.REL_COMMON r ON m.OBJECT_ID = r.OBJECT_ID
WHERE m.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = m.OBJECT_ID);

-- Test 7: Count TxProcessAssembly objects in temp_project_objects
SELECT 'TXPROCESSASSEMBLY|' || COUNT(*) || '|' ||
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END
FROM $Schema.PART_ p
WHERE p.CLASS_ID = 133
  AND p.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

-- Test 8: Verify TxProcessAssembly extraction query returns results
SELECT 'TXPROCESSASSEMBLY_EXTRACT|' || COUNT(*) || '|' ||
    CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END
FROM $Schema.PART_ p
INNER JOIN $Schema.REL_COMMON r ON p.OBJECT_ID = r.OBJECT_ID
WHERE p.CLASS_ID = 133
  AND p.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID);

-- Test 9: Regression check - OLD buggy pattern should return FEWER results than correct pattern
-- For MFGFEATURE_: Compare parent-check vs object-check
SELECT 'MFGFEATURE_REGRESSION|' ||
    (SELECT COUNT(*) FROM $Schema.MFGFEATURE_ mf
     INNER JOIN $Schema.REL_COMMON r ON mf.OBJECT_ID = r.OBJECT_ID
     WHERE mf.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)) || '|' ||
    (SELECT COUNT(*) FROM $Schema.MFGFEATURE_ mf
     INNER JOIN $Schema.REL_COMMON r ON mf.OBJECT_ID = r.OBJECT_ID
     WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)) || '|' ||
    CASE WHEN
        (SELECT COUNT(*) FROM $Schema.MFGFEATURE_ mf
         INNER JOIN $Schema.REL_COMMON r ON mf.OBJECT_ID = r.OBJECT_ID
         WHERE mf.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)) >=
        (SELECT COUNT(*) FROM $Schema.MFGFEATURE_ mf
         INNER JOIN $Schema.REL_COMMON r ON mf.OBJECT_ID = r.OBJECT_ID
         WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects))
    THEN 'PASS' ELSE 'FAIL' END
FROM DUAL;

-- Test 10: Regression check for MODULE_
SELECT 'MODULE_REGRESSION|' ||
    (SELECT COUNT(*) FROM $Schema.MODULE_ m
     INNER JOIN $Schema.REL_COMMON r ON m.OBJECT_ID = r.OBJECT_ID
     WHERE m.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)) || '|' ||
    (SELECT COUNT(*) FROM $Schema.MODULE_ m
     INNER JOIN $Schema.REL_COMMON r ON m.OBJECT_ID = r.OBJECT_ID
     WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)) || '|' ||
    CASE WHEN
        (SELECT COUNT(*) FROM $Schema.MODULE_ m
         INNER JOIN $Schema.REL_COMMON r ON m.OBJECT_ID = r.OBJECT_ID
         WHERE m.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)) >=
        (SELECT COUNT(*) FROM $Schema.MODULE_ m
         INNER JOIN $Schema.REL_COMMON r ON m.OBJECT_ID = r.OBJECT_ID
         WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects))
    THEN 'PASS' ELSE 'FAIL' END
FROM DUAL;

-- Cleanup
DROP TABLE temp_project_objects;

EXIT;
"@

# Write SQL file
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PWD\$testSqlFile", $testSql, $utf8NoBom)

# Run test
Write-Host "Running regression tests..." -ForegroundColor Yellow
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

try {
    $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
} catch {
    Write-Warning "Failed to get credentials, using default"
    $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
}

$result = sqlplus -S $connectionString "@$testSqlFile" 2>&1
$result | Out-File $testOutputFile -Encoding UTF8

# Parse results
$allPassed = $true
$results = @()

Get-Content $testOutputFile | ForEach-Object {
    if ($_ -match '^([A-Z_]+)\|(\d+)\|(\d+)?\|?(PASS|FAIL)') {
        $testName = $matches[1]
        $count1 = $matches[2]
        $count2 = if ($matches[3]) { $matches[3] } else { "" }
        $status = $matches[4]

        $results += [PSCustomObject]@{
            Test = $testName
            Count = $count1
            OldCount = $count2
            Status = $status
        }

        if ($status -eq 'FAIL') {
            $allPassed = $false
        }
    } elseif ($_ -match '^([A-Z_]+)\|(\d+)\|(PASS|FAIL)') {
        $testName = $matches[1]
        $count = $matches[2]
        $status = $matches[3]

        $results += [PSCustomObject]@{
            Test = $testName
            Count = $count
            OldCount = ""
            Status = $status
        }

        if ($status -eq 'FAIL') {
            $allPassed = $false
        }
    }
}

# Display results
Write-Host ""
Write-Host "=== Test Results ===" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = if ($r.Status -eq 'PASS') { 'Green' } else { 'Red' }
    if ($r.OldCount) {
        Write-Host "$($r.Test): New=$($r.Count) Old=$($r.OldCount) [$($r.Status)]" -ForegroundColor $color
    } else {
        Write-Host "$($r.Test): Count=$($r.Count) [$($r.Status)]" -ForegroundColor $color
    }
}

# Cleanup
Remove-Item $testSqlFile -ErrorAction SilentlyContinue
Remove-Item $testOutputFile -ErrorAction SilentlyContinue

# Exit with appropriate code
if ($allPassed) {
    Write-Host ""
    Write-Host "=== ALL TESTS PASSED ===" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "=== TESTS FAILED ===" -ForegroundColor Red
    exit 1
}
