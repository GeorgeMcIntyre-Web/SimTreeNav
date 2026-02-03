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

# Find DES_Studies container(s) under the project
$desQuery = @"
SELECT DISTINCT c.OBJECT_ID
FROM $Schema.COLLECTION_ c
INNER JOIN $Schema.REL_COMMON r ON c.OBJECT_ID = r.OBJECT_ID
WHERE c.NAME_S_ = 'DES_Studies'
  AND r.FORWARD_OBJECT_ID = $ProjectId
UNION
SELECT DISTINCT c.OBJECT_ID
FROM $Schema.COLLECTION_ c
INNER JOIN $Schema.REL_COMMON r ON c.OBJECT_ID = r.FORWARD_OBJECT_ID
WHERE c.NAME_S_ = 'DES_Studies'
  AND r.OBJECT_ID = $ProjectId
"@

$desNodes = Invoke-SqlPlusQuery -TNSName $TNSName -Username "sys" -Password $password -Query $desQuery -DBAPrivilege "SYSDBA" -TimeoutSeconds 60
$scopeLabel = "DES_Studies"
if (-not $desNodes -or $desNodes.Count -eq 0) {
    Write-Warning "No DES_Studies containers found under project $ProjectId. Falling back to project scope."
    $desIds = "$ProjectId"
    $scopeLabel = "Project"
} else {
    $desIds = ($desNodes | ForEach-Object { $_.OBJECT_ID }) -join ','
}

# Pull study list (REL_COMMON descendants of DES_Studies)
$studyQuery = @"
SELECT DISTINCT
    rs.OBJECT_ID as STUDY_ID,
    rs.NAME_S_ as STUDY_NAME,
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as LAST_MODIFIED,
    NVL(p.WORKING_VERSION_ID, 0) as WORKING_VERSION_ID
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r
    ON (r.OBJECT_ID = rs.OBJECT_ID AND r.FORWARD_OBJECT_ID IN ($desIds))
    OR (r.FORWARD_OBJECT_ID = rs.OBJECT_ID AND r.OBJECT_ID IN ($desIds))
LEFT JOIN $Schema.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID AND p.PROJECT_ID = $ProjectId
ORDER BY rs.NAME_S_
"@

$studies = Invoke-SqlPlusQuery -TNSName $TNSName -Username "sys" -Password $password -Query $studyQuery -DBAPrivilege "SYSDBA" -TimeoutSeconds 120

if (-not $studies -or $studies.Count -eq 0) {
    Write-Warning "No studies returned for project $ProjectId using REL_COMMON scope. Falling back to PROXY."
    $scopeLabel = "PROXY"
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
    $studies = Invoke-SqlPlusQuery -TNSName $TNSName -Username "sys" -Password $password -Query $proxyQuery -DBAPrivilege "SYSDBA" -TimeoutSeconds 120
}

if (-not $studies -or $studies.Count -eq 0) {
    Write-Warning "No studies returned for project $ProjectId."
    exit 1
}

function Parse-Date {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return [datetime]::MinValue }
    [datetime]::ParseExact($Value, 'yyyy-MM-dd HH:mm:ss', [System.Globalization.CultureInfo]::InvariantCulture)
}

# Deduplicate by STUDY_ID (retain latest modified and max working version)
$studyMap = @{}
foreach ($row in $studies) {
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
$studies = $studyMap.Values

$modified = @()
$checkedOut = @()

foreach ($study in $studies) {
    $modifiedDate = Parse-Date $study.LAST_MODIFIED
    if ($modifiedDate -ge $StartDate -and $modifiedDate -le $EndDate) {
        $modified += $study
    }
    if ([int]$study.WORKING_VERSION_ID -gt 0) {
        $checkedOut += $study
    }
}

$totalCount = $studies.Count
$modifiedCount = $modified.Count
$checkedOutCount = $checkedOut.Count

Write-Host "Counts ($scopeLabel scope):" -ForegroundColor Cyan
Write-Host "  Total studies in scope:      $totalCount" -ForegroundColor Gray
Write-Host "  Modified in range:           $modifiedCount" -ForegroundColor Gray
Write-Host "  Checked out:                 $checkedOutCount" -ForegroundColor Gray

Write-Host "`nFirst 20 modified in range:" -ForegroundColor Cyan
$modified | Select-Object -First 20 STUDY_ID, STUDY_NAME, LAST_MODIFIED | Format-Table -AutoSize

Write-Host "`nFirst 20 checked out:" -ForegroundColor Cyan
$checkedOut | Select-Object -First 20 STUDY_ID, STUDY_NAME, WORKING_VERSION_ID | Format-Table -AutoSize

Write-Host "`nDiagnostics complete." -ForegroundColor Green
