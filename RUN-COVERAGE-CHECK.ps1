# Node Type Coverage Check
# Displays counts of each node class included in the generated tree
#
# Usage:
#   .\RUN-COVERAGE-CHECK.ps1 -TNSName DESIGN1 -Schema DESIGN1 -ProjectId 20 -ProjectName "J10735_Mexico"
#
# Output:
#   - Counts of nodes by type (OPERATION_, MFGFEATURE_, MODULE_, TxProcessAssembly, etc.)
#   - Total node count
#   - Coverage summary

param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [string]$ProjectId,

    [Parameter(Mandatory=$true)]
    [string]$ProjectName
)

$ErrorActionPreference = 'Stop'

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "src\powershell\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
}

Write-Host "=== Node Type Coverage Check ===" -ForegroundColor Cyan
Write-Host "Project: $ProjectName (ID: $ProjectId)" -ForegroundColor Gray
Write-Host "Schema: $Schema | TNS: $TNSName" -ForegroundColor Gray
Write-Host ""

# Create SQL file
$coverageSqlFile = "coverage-check-${Schema}-${ProjectId}.sql"
$coverageOutputFile = "coverage-output-${Schema}-${ProjectId}.txt"

$coverageSql = @"
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

-- Count nodes by type
SELECT 'OPERATION_|' || COUNT(*)
FROM $Schema.OPERATION_ op
WHERE op.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'MFGFEATURE_|' || COUNT(*)
FROM $Schema.MFGFEATURE_ mf
WHERE mf.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'MODULE_|' || COUNT(*)
FROM $Schema.MODULE_ m
WHERE m.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'TxProcessAssembly|' || COUNT(*)
FROM $Schema.PART_ p
WHERE p.CLASS_ID = 133
  AND p.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'COLLECTION_|' || COUNT(*)
FROM $Schema.COLLECTION_ c
WHERE c.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'PART_|' || COUNT(*)
FROM $Schema.PART_ p
WHERE p.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID);

SELECT 'PARTPROTOTYPE_|' || COUNT(*)
FROM $Schema.PARTPROTOTYPE_ pp
WHERE pp.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'RESOURCE_|' || COUNT(*)
FROM $Schema.RESOURCE_ res
WHERE res.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'TOOLPROTOTYPE_|' || COUNT(*)
FROM $Schema.TOOLPROTOTYPE_ tp
WHERE tp.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'ROBCADSTUDY_|' || COUNT(*)
FROM $Schema.ROBCADSTUDY_ rs
WHERE rs.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'LINESIMULATIONSTUDY_|' || COUNT(*)
FROM $Schema.LINESIMULATIONSTUDY_ ls
WHERE ls.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'GANTTSTUDY_|' || COUNT(*)
FROM $Schema.GANTTSTUDY_ gs
WHERE gs.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'SIMPLEDETAILEDSTUDY_|' || COUNT(*)
FROM $Schema.SIMPLEDETAILEDSTUDY_ sd
WHERE sd.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'LOCATIONALSTUDY_|' || COUNT(*)
FROM $Schema.LOCATIONALSTUDY_ lc
WHERE lc.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

SELECT 'SHORTCUT_|' || COUNT(*)
FROM $Schema.SHORTCUT_ sc
WHERE sc.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

-- Total objects discovered
SELECT 'TOTAL_DISCOVERED|' || COUNT(*)
FROM temp_project_objects;

-- Cleanup
DROP TABLE temp_project_objects;

EXIT;
"@

# Write SQL file
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PWD\$coverageSqlFile", $coverageSql, $utf8NoBom)

# Run coverage check
Write-Host "Analyzing node type coverage..." -ForegroundColor Yellow
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

try {
    $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
} catch {
    Write-Warning "Failed to get credentials, using default"
    $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
}

$result = sqlplus -S $connectionString "@$coverageSqlFile" 2>&1
$result | Out-File $coverageOutputFile -Encoding UTF8

# Parse and display results
$coverage = @{}
$totalDiscovered = 0

Get-Content $coverageOutputFile | ForEach-Object {
    if ($_ -match '^([A-Z_]+)\|(\d+)') {
        $nodeType = $matches[1]
        $count = [int]$matches[2]

        if ($nodeType -eq 'TOTAL_DISCOVERED') {
            $totalDiscovered = $count
        } else {
            $coverage[$nodeType] = $count
        }
    }
}

# Display results
Write-Host ""
Write-Host "=== Coverage Results ===" -ForegroundColor Cyan
Write-Host ""

# Sort by count descending, then by name
$sortedCoverage = $coverage.GetEnumerator() | Sort-Object -Property @{Expression={$_.Value}; Descending=$true}, Name

$maxTypeLen = ($sortedCoverage | ForEach-Object { $_.Key.Length } | Measure-Object -Maximum).Maximum
foreach ($entry in $sortedCoverage) {
    $typeLabel = $entry.Key.PadRight($maxTypeLen)
    $count = $entry.Value

    if ($count -eq 0) {
        Write-Host "  $typeLabel : $count" -ForegroundColor DarkGray
    } elseif ($count -lt 10) {
        Write-Host "  $typeLabel : $count" -ForegroundColor Yellow
    } else {
        Write-Host "  $typeLabel : $count" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "  $('TOTAL_DISCOVERED'.PadRight($maxTypeLen)) : $totalDiscovered" -ForegroundColor Cyan
Write-Host ""

# Key metrics
$criticalTypes = @('OPERATION_', 'MFGFEATURE_', 'MODULE_', 'TxProcessAssembly')
$missingCritical = $criticalTypes | Where-Object { -not $coverage.ContainsKey($_) -or $coverage[$_] -eq 0 }

if ($missingCritical.Count -eq 0) {
    Write-Host "=== ALL CRITICAL NODE TYPES PRESENT ===" -ForegroundColor Green
} else {
    Write-Host "=== WARNING: Missing critical node types ===" -ForegroundColor Yellow
    foreach ($missing in $missingCritical) {
        Write-Host "  - $missing" -ForegroundColor Red
    }
}

# Cleanup
Remove-Item $coverageSqlFile -ErrorAction SilentlyContinue
Remove-Item $coverageOutputFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Coverage check complete." -ForegroundColor Cyan
