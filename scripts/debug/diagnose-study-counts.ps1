#Requires -Version 5.1
<#
.SYNOPSIS
    Diagnose study counts for a project using REL_COMMON + DES_Studies.

.DESCRIPTION
    Compares:
      - Total studies under project scope (REL_COMMON descendants of DES_Studies)
      - Studies modified in date range (ROBCADSTUDY_.MODIFICATIONDATE_DA_)
      - Studies checked out (PROXY.WORKING_VERSION_ID > 0)

.EXAMPLE
    .\scripts\debug\diagnose-study-counts.ps1 -TNSName PSPDV3 -Schema DESIGN12 -ProjectId 8521220 -StartDate 2026-01-27 -EndDate 2026-02-03
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$TNSName = "PSPDV3",

    [Parameter(Mandatory=$false)]
    [string]$Schema = "DESIGN12",

    [Parameter(Mandatory=$false)]
    [int]$ProjectId = 0,

    [Parameter(Mandatory=$false)]
    [DateTime]$StartDate = (Get-Date).AddDays(-7),

    [Parameter(Mandatory=$false)]
    [DateTime]$EndDate = (Get-Date)
)

$ErrorActionPreference = "Stop"

# Resolve defaults from enterprise config if ProjectId not provided
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$enterpriseConfigPath = Join-Path $repoRoot "config\enterprise-config.json"
if ($ProjectId -eq 0 -and (Test-Path $enterpriseConfigPath)) {
    $enterpriseConfig = Get-Content $enterpriseConfigPath -Raw | ConvertFrom-Json
    if ($enterpriseConfig.defaults.projectId) {
        $ProjectId = [int]$enterpriseConfig.defaults.projectId
    }
}

if ($ProjectId -eq 0) {
    throw "ProjectId is required (pass -ProjectId or set defaults in config/enterprise-config.json)."
}

# Load helpers
. "$repoRoot\src\powershell\utilities\CredentialManager.ps1"

$sqlHelperPath = Join-Path $repoRoot "src\powershell\utilities\SqlPlusHelper-Simple.ps1"
if (Test-Path $sqlHelperPath) {
    . $sqlHelperPath
} else {
    function Invoke-SqlPlusQuery {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true)]
            [string]$TNSName,

            [Parameter(Mandatory=$true)]
            [string]$Username,

            [Parameter(Mandatory=$true)]
            [string]$Password,

            [Parameter(Mandatory=$true)]
            [string]$Query,

            [Parameter(Mandatory=$false)]
            [ValidateSet("SYSDBA", "SYSOPER", "None")]
            [string]$DBAPrivilege = "None",

            [Parameter(Mandatory=$false)]
            [int]$TimeoutSeconds = 60
        )

        $connString = "${Username}/${Password}@${TNSName}"
        if ($DBAPrivilege -ne "None") {
            $connString += " as $DBAPrivilege"
        }

        $tempSql = [System.IO.Path]::GetTempFileName() + ".sql"
        $queryText = $Query.Trim()
        if (-not $queryText.EndsWith(';')) {
            $queryText += ';'
        }

        $sqlContent = @"
SET PAGESIZE 50000
SET FEEDBACK OFF
SET HEADING ON
SET LINESIZE 32767
SET COLSEP '|'
SET UNDERLINE OFF
$queryText
EXIT;
"@
        $sqlContent | Out-File $tempSql -Encoding ASCII -Force

        try {
            $job = Start-Job -ScriptBlock {
                param($ConnStr, $SqlFile)
                & sqlplus -S $ConnStr "@$SqlFile" 2>&1
            } -ArgumentList $connString, $tempSql

            $completed = Wait-Job $job -Timeout $TimeoutSeconds
            if (-not $completed) {
                Stop-Job $job
                Remove-Job $job -Force
                throw "Query timed out after ${TimeoutSeconds} seconds"
            }

            $output = Receive-Job $job
            Remove-Job $job -Force
            $outputText = ($output | Out-String).Trim()

            if ($outputText -match 'ORA-\d+' -or $outputText -match 'ERROR') {
                throw "SQL*Plus error: $outputText"
            }

            $lines = $outputText -split "`r?`n" | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -match '\|' -and
                $_ -notmatch '^[\s\-\|]+$'
            }

            if ($lines.Count -lt 1) {
                return @()
            }

            $headers = $lines[0] -split '\|' | ForEach-Object { $_.Trim() }
            $results = @()

            foreach ($line in $lines[1..($lines.Count - 1)]) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $values = $line -split '\|', $headers.Count
                $row = @{}
                for ($i = 0; $i -lt $headers.Count; $i++) {
                    $value = if ($i -lt $values.Count) { $values[$i].Trim() } else { "" }
                    $row[$headers[$i]] = $value
                }
                $results += [PSCustomObject]$row
            }

            return $results
        } finally {
            Remove-Item $tempSql -Force -ErrorAction SilentlyContinue
        }
    }
}

$credential = Get-DbCredential -TNSName $TNSName -Username "sys"
if (-not $credential) {
    throw "No database credentials available for $TNSName"
}
$password = $credential.GetNetworkCredential().Password

$startDateStr = $StartDate.ToString('yyyy-MM-dd')
$endDateStr = $EndDate.ToString('yyyy-MM-dd')

Write-Host "`n=== Study Count Diagnostics ===" -ForegroundColor Cyan
Write-Host "TNS:        $TNSName" -ForegroundColor Gray
Write-Host "Schema:     $Schema" -ForegroundColor Gray
Write-Host "Project ID: $ProjectId" -ForegroundColor Gray
Write-Host "Date Range: $startDateStr to $endDateStr" -ForegroundColor Gray
Write-Host ""

function Parse-Date {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return [datetime]::MinValue }
    [datetime]::ParseExact($Value, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Dedup-Studies {
    param([object[]]$Rows)

    if (-not $Rows) { return @() }

    $studyMap = @{}
    foreach ($row in $Rows) {
        $id = $row.STUDY_ID
        if (-not $studyMap.ContainsKey($id)) {
            $studyMap[$id] = $row
            continue
        }

        $existing = $studyMap[$id]
        $existingDate = Parse-Date $existing.LAST_MODIFIED
        $rowDate = Parse-Date $row.LAST_MODIFIED
        $existingWv = [int]$existing.WORKING_VERSION_ID
        $rowWv = [int]$row.WORKING_VERSION_ID

        if ($rowDate -gt $existingDate) {
            $existing.LAST_MODIFIED = $row.LAST_MODIFIED
        }
        if ($rowWv -gt $existingWv) {
            $existing.WORKING_VERSION_ID = $row.WORKING_VERSION_ID
        }
    }
    return $studyMap.Values
}

function Build-Counts {
    param([object[]]$Rows)

    $rows = Dedup-Studies -Rows $Rows
    $modified = @()
    $checkedOut = @()

    foreach ($study in $rows) {
        $modifiedDate = Parse-Date $study.LAST_MODIFIED
        if ($modifiedDate -ge $StartDate -and $modifiedDate -le $EndDate) {
            $modified += $study
        }
        if ([int]$study.WORKING_VERSION_ID -gt 0) {
            $checkedOut += $study
        }
    }

    return @{
        total = $rows.Count
        modified = $modified
        checkedOut = $checkedOut
        rows = $rows
    }
}

# Tree scope: REL_COMMON descendants of projectId (REL_TYPE = 4)
$treeQuery = @"
WITH tree_nodes AS (
    SELECT DISTINCT c.OBJECT_ID
    FROM $Schema.REL_COMMON r
    INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
    WHERE r.REL_TYPE = 4
    START WITH r.FORWARD_OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
),
tree_collections AS (
    SELECT OBJECT_ID FROM tree_nodes
)
SELECT DISTINCT
    rs.OBJECT_ID as STUDY_ID,
    rs.NAME_S_ as STUDY_NAME,
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as LAST_MODIFIED,
    NVL(p.WORKING_VERSION_ID, 0) as WORKING_VERSION_ID
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON r.OBJECT_ID = rs.OBJECT_ID AND r.REL_TYPE = 4
INNER JOIN tree_collections tc ON r.FORWARD_OBJECT_ID = tc.OBJECT_ID
LEFT JOIN $Schema.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID AND p.PROJECT_ID = $ProjectId
ORDER BY rs.NAME_S_
"@

$treeStudies = Invoke-SqlPlusQuery -TNSName $TNSName -Username "sys" -Password $password -Query $treeQuery -DBAPrivilege "SYSDBA" -TimeoutSeconds 300
$treeCounts = Build-Counts -Rows $treeStudies

# Proxy scope: ROBCADSTUDY_ joined to PROXY project
$proxyQuery = @"
SELECT DISTINCT
    rs.OBJECT_ID as STUDY_ID,
    rs.NAME_S_ as STUDY_NAME,
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as LAST_MODIFIED,
    NVL(p.WORKING_VERSION_ID, 0) as WORKING_VERSION_ID
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID AND p.PROJECT_ID = $ProjectId
ORDER BY rs.NAME_S_
"@

$proxyStudies = Invoke-SqlPlusQuery -TNSName $TNSName -Username "sys" -Password $password -Query $proxyQuery -DBAPrivilege "SYSDBA" -TimeoutSeconds 120
$proxyCounts = Build-Counts -Rows $proxyStudies

Write-Host "Counts (tree scope):" -ForegroundColor Cyan
Write-Host "  Total studies in scope:      $($treeCounts.total)" -ForegroundColor Gray
Write-Host "  Modified in range:           $($treeCounts.modified.Count)" -ForegroundColor Gray
Write-Host "  Checked out:                 $($treeCounts.checkedOut.Count)" -ForegroundColor Gray

Write-Host "Counts (proxy scope):" -ForegroundColor Cyan
Write-Host "  Total studies in scope:      $($proxyCounts.total)" -ForegroundColor Gray
Write-Host "  Modified in range:           $($proxyCounts.modified.Count)" -ForegroundColor Gray
Write-Host "  Checked out:                 $($proxyCounts.checkedOut.Count)" -ForegroundColor Gray

Write-Host "`nTree scope: first 20 modified in range:" -ForegroundColor Cyan
$treeCounts.modified | Select-Object -First 20 STUDY_ID, STUDY_NAME, LAST_MODIFIED | Format-Table -AutoSize

Write-Host "`nTree scope: first 20 checked out:" -ForegroundColor Cyan
$treeCounts.checkedOut | Select-Object -First 20 STUDY_ID, STUDY_NAME, WORKING_VERSION_ID | Format-Table -AutoSize

Write-Host "`nProxy scope: first 20 modified in range:" -ForegroundColor Cyan
$proxyCounts.modified | Select-Object -First 20 STUDY_ID, STUDY_NAME, LAST_MODIFIED | Format-Table -AutoSize

Write-Host "`nProxy scope: first 20 checked out:" -ForegroundColor Cyan
$proxyCounts.checkedOut | Select-Object -First 20 STUDY_ID, STUDY_NAME, WORKING_VERSION_ID | Format-Table -AutoSize

Write-Host "`nDiagnostics complete." -ForegroundColor Green
