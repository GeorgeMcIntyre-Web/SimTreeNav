# Search functionality test for tree HTML data
# Validates that expected search terms exist in the dataset.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$HtmlPath,

    [string]$TermsPath = "",
    [string]$OutputReport = "test-automation/results/search-functionality-test.json",
    [string]$OutputCsv = ""
)

function Add-Issue {
    param([string]$Message)
    $script:results.issues += $Message
    $script:results.status = "fail"
}

if (-not (Test-Path $HtmlPath)) {
    throw "HTML file not found: $HtmlPath"
}

$results = [ordered]@{
    test = "search-functionality-test"
    startedAt = (Get-Date).ToString("s")
    status = "pass"
    issues = @()
    results = @()
}

$defaultTerms = @(
    @{ term = "PartLibrary"; expectedMin = 1 },
    @{ term = "PartInstanceLibrary"; expectedMin = 1 },
    @{ term = "MfgLibrary"; expectedMin = 1 },
    @{ term = "EngineeringResourceLibrary"; expectedMin = 1 },
    @{ term = "RobcadStudy"; expectedMin = 1 },
    @{ term = "COWL_SILL_SIDE"; expectedMin = 1 },
    @{ term = "Robot"; expectedMin = 1 },
    @{ term = "Station"; expectedMin = 1 },
    @{ term = "Tool"; expectedMin = 1 },
    @{ term = "Fixture"; expectedMin = 1 },
    @{ term = "Weld"; expectedMin = 1 },
    @{ term = "Process"; expectedMin = 1 },
    @{ term = "Line"; expectedMin = 1 },
    @{ term = "Assembly"; expectedMin = 1 },
    @{ term = "Operation"; expectedMin = 1 },
    @{ term = "P702"; expectedMin = 1 },
    @{ term = "P703"; expectedMin = 1 },
    @{ term = "CC"; expectedMin = 1 },
    @{ term = "SOP"; expectedMin = 1 },
    @{ term = "INVALID_TERM_123"; expectedMin = 0 }
)

$terms = @()
if ($TermsPath) {
    if (-not (Test-Path $TermsPath)) {
        throw "Terms file not found: $TermsPath"
    }
    $terms = Import-Csv $TermsPath | ForEach-Object {
        $expected = if ($_.expectedMin -ne $null -and $_.expectedMin -ne "") { [int]$_.expectedMin } else { 1 }
        [pscustomobject]@{ term = $_.term; expectedMin = $expected }
    }
} else {
    $terms = $defaultTerms | ForEach-Object { [pscustomobject]$_ }
}

$termMap = @{}
foreach ($term in $terms) {
    $termMap[$term.term.ToUpperInvariant()] = [ordered]@{
        term = $term.term
        expectedMin = $term.expectedMin
        count = 0
        status = "pass"
    }
}

Write-Host "Scanning HTML for search terms..."
Get-Content $HtmlPath -ReadCount 5000 | ForEach-Object {
    foreach ($line in $_) {
        if ($line -match '^[0-9]+\|') {
            $parts = $line -split '\|'
            if ($parts.Length -ge 5) {
                $caption = $parts[3]
                $name = $parts[4]
                $haystack = ("$caption $name").ToUpperInvariant()
                foreach ($key in $termMap.Keys) {
                    if ($haystack.Contains($key)) {
                        $termMap[$key].count++
                    }
                }
            }
        }
    }
}

foreach ($key in $termMap.Keys) {
    $item = $termMap[$key]
    if ($item.count -lt $item.expectedMin) {
        $item.status = "fail"
        Add-Issue "Term '$($item.term)' count $($item.count) below expected $($item.expectedMin)"
    }
    $results.results += $item
}

$results.endedAt = (Get-Date).ToString("s")

$reportDir = Split-Path $OutputReport
if ($reportDir -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
}

$results | ConvertTo-Json -Depth 6 | Set-Content -Encoding ASCII $OutputReport

if ($OutputCsv) {
    $results.results | Select-Object term, expectedMin, count, status |
        Export-Csv -Path $OutputCsv -NoTypeInformation -Encoding ASCII
}

Write-Host "Search test complete. Status: $($results.status)"
Write-Host "Report: $OutputReport"
if ($results.status -eq "fail") {
    exit 1
}
