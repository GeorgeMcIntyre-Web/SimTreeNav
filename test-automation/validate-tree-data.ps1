# Validate Tree Data against XML baseline
# Compares XML node IDs to HTML node IDs and validates counts and icon map size.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$XmlPath,

    [Parameter(Mandatory=$true)]
    [string]$HtmlPath,

    [int]$ExpectedNodeCount = 0,
    [int]$ExpectedIconCount = 0,
    [int]$NodeCountTolerancePercent = 2,
    [int]$MaxMissingSamples = 50,
    [string]$OutputReport = "test-automation/results/validate-tree-data.json"
)

function Add-Issue {
    param([string]$Message)
    $script:results.issues += $Message
    $script:results.status = "fail"
}

$startTime = Get-Date
$results = [ordered]@{
    test = "validate-tree-data"
    startedAt = $startTime.ToString("s")
    status = "pass"
    metrics = [ordered]@{}
    issues = @()
    samples = @{}
}

if (-not (Test-Path $XmlPath)) {
    Add-Issue "XML file not found: $XmlPath"
}
if (-not (Test-Path $HtmlPath)) {
    Add-Issue "HTML file not found: $HtmlPath"
}
if ($results.status -eq "fail") {
    $results.endedAt = (Get-Date).ToString("s")
    $results | ConvertTo-Json -Depth 6 | Set-Content -Encoding ASCII $OutputReport
    throw "Validation failed. See $OutputReport"
}

Write-Host "Loading XML baseline..."
try {
    [xml]$xml = Get-Content $XmlPath
} catch {
    Add-Issue "Failed to parse XML: $($_.Exception.Message)"
}

$xmlIds = New-Object System.Collections.Generic.HashSet[string]
if ($xml -and $xml.Data -and $xml.Data.Objects) {
    foreach ($element in $xml.Data.Objects.ChildNodes) {
        if ($element.NodeInfo -and $element.NodeInfo.Id) {
            [void]$xmlIds.Add([string]$element.NodeInfo.Id)
        }
    }
} else {
    Add-Issue "XML structure unexpected. Expected Data.Objects.NodeInfo.Id"
}

Write-Host "Parsing HTML tree file..."
$htmlIds = New-Object System.Collections.Generic.HashSet[string]
$iconMapKeys = New-Object System.Collections.Generic.HashSet[string]
$inIconMap = $false

Get-Content $HtmlPath -ReadCount 5000 | ForEach-Object {
    foreach ($line in $_) {
        if (-not $inIconMap -and $line -match 'const\s+iconMap\s*=\s*\{') {
            $inIconMap = $true
            continue
        }
        if ($inIconMap) {
            if ($line -match '^\s*\};') {
                $inIconMap = $false
                continue
            }
            if ($line -match '^\s*["\']([^"\']+)["\']\s*:') {
                [void]$iconMapKeys.Add($matches[1])
            }
        }

        if ($line -match '^[0-9]+\|') {
            $parts = $line -split '\|'
            if ($parts.Length -ge 3) {
                $id = $parts[2].Trim()
                if ($id) {
                    [void]$htmlIds.Add($id)
                }
            }
        }
    }
}

$xmlCount = $xmlIds.Count
$htmlCount = $htmlIds.Count
$iconCount = $iconMapKeys.Count

$results.metrics.xmlNodeCount = $xmlCount
$results.metrics.htmlNodeCount = $htmlCount
$results.metrics.iconMapCount = $iconCount

if ($ExpectedNodeCount -gt 0) {
    $min = [math]::Floor($ExpectedNodeCount * (1 - ($NodeCountTolerancePercent / 100)))
    $max = [math]::Ceiling($ExpectedNodeCount * (1 + ($NodeCountTolerancePercent / 100)))
    if ($htmlCount -lt $min -or $htmlCount -gt $max) {
        Add-Issue "HTML node count $htmlCount out of range [$min, $max]"
    }
}

if ($ExpectedIconCount -gt 0 -and $iconCount -ne $ExpectedIconCount) {
    Add-Issue "Icon map count $iconCount does not match expected $ExpectedIconCount"
}

$missing = New-Object System.Collections.Generic.List[string]
foreach ($id in $xmlIds) {
    if (-not $htmlIds.Contains($id)) {
        $missing.Add($id)
    }
}

$results.metrics.missingNodeCount = $missing.Count
if ($missing.Count -gt 0) {
    $results.samples.missingNodeIds = $missing | Select-Object -First $MaxMissingSamples
}

$results.endedAt = (Get-Date).ToString("s")

$reportDir = Split-Path $OutputReport
if ($reportDir -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
}

$results | ConvertTo-Json -Depth 6 | Set-Content -Encoding ASCII $OutputReport

Write-Host "Validation complete. Status: $($results.status)"
Write-Host "Report: $OutputReport"
if ($results.status -eq "fail") {
    exit 1
}
