# Health score validation against manual expectations
# Compares expected scores from CSV to scores in a management data JSON file.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$InputJson,

    [Parameter(Mandatory=$true)]
    [string]$ExpectationsCsv,

    [string]$ScoreField = "",
    [int]$Tolerance = 3,
    [string]$OutputReport = "test/automation/results/health-score-validator.json"
)

function Add-Issue {
    param([string]$Message)
    $script:results.issues += $Message
    $script:results.status = "fail"
}

function Get-PropertyValue {
    param(
        [object]$Obj,
        [string[]]$Names
    )
    foreach ($name in $Names) {
        $prop = $Obj.PSObject.Properties | Where-Object { $_.Name -ieq $name } | Select-Object -First 1
        if ($prop) { return $prop.Value }
    }
    return $null
}

if (-not (Test-Path $InputJson)) { throw "Input JSON not found: $InputJson" }
if (-not (Test-Path $ExpectationsCsv)) { throw "Expectations CSV not found: $ExpectationsCsv" }

$results = [ordered]@{
    test = "health-score-validator"
    startedAt = (Get-Date).ToString("s")
    status = "pass"
    issues = @()
    results = @()
}

$data = Get-Content $InputJson -Raw | ConvertFrom-Json
$studyRecords = @()
if ($data.studySummary) { $studyRecords = $data.studySummary }
elseif ($data.studies) { $studyRecords = $data.studies }
elseif ($data.data) { $studyRecords = $data.data }
else { Add-Issue "No study collection found in JSON." }

$expectedRows = Import-Csv $ExpectationsCsv
$idFields = @("studyId", "study_id", "STUDY_ID", "id")
$scoreFields = if ($ScoreField) { @($ScoreField) } else { @("healthScore", "health_score", "HEALTH_SCORE", "score") }

foreach ($row in $expectedRows) {
    $expectedId = $row.studyId
    $expectedScore = [double]$row.expectedScore

    $match = $null
    foreach ($record in $studyRecords) {
        $recordId = Get-PropertyValue -Obj $record -Names $idFields
        if ($recordId -and $recordId.ToString() -eq $expectedId) {
            $match = $record
            break
        }
    }

    if (-not $match) {
        Add-Issue "Study not found: $expectedId"
        $results.results += [ordered]@{
            studyId = $expectedId
            expectedScore = $expectedScore
            actualScore = $null
            delta = $null
            status = "fail"
        }
        continue
    }

    $actualScore = Get-PropertyValue -Obj $match -Names $scoreFields
    if ($actualScore -eq $null) {
        Add-Issue "Health score missing for study: $expectedId"
        $results.results += [ordered]@{
            studyId = $expectedId
            expectedScore = $expectedScore
            actualScore = $null
            delta = $null
            status = "fail"
        }
        continue
    }

    $actualScoreNum = [double]$actualScore
    $delta = [math]::Abs($actualScoreNum - $expectedScore)
    $status = if ($delta -le $Tolerance) { "pass" } else { "fail" }
    if ($status -eq "fail") {
        Add-Issue "Study $expectedId delta $delta exceeds tolerance $Tolerance"
    }

    $results.results += [ordered]@{
        studyId = $expectedId
        expectedScore = $expectedScore
        actualScore = $actualScoreNum
        delta = $delta
        status = $status
    }
}

$results.endedAt = (Get-Date).ToString("s")

$reportDir = Split-Path $OutputReport
if ($reportDir -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
}

$results | ConvertTo-Json -Depth 6 | Set-Content -Encoding ASCII $OutputReport

Write-Host "Health score validation complete. Status: $($results.status)"
Write-Host "Report: $OutputReport"
if ($results.status -eq "fail") {
    exit 1
}
