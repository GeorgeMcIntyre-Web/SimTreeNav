# Performance benchmark for tree HTML and optional generation
# Measures file read time, node count, and optional browser memory snapshot.

[CmdletBinding()]
param(
    [string]$HtmlPath = "navigation-tree.html",
    [switch]$GenerateTree,
    [string]$TNSName = "",
    [string]$Schema = "",
    [string]$ProjectId = "",
    [string]$ProjectName = "",
    [int]$ReadIterations = 3,
    [string]$BrowserProcessName = "",
    [int]$MaxCachedLoadSeconds = 5,
    [int]$MaxGenerationSeconds = 90,
    [int]$MaxBrowserMemoryMb = 100,
    [string]$OutputReport = "test-automation/results/performance-benchmark.json"
)

function Add-Issue {
    param([string]$Message)
    $script:results.issues += $Message
    $script:results.status = "fail"
}

$results = [ordered]@{
    test = "performance-benchmark"
    startedAt = (Get-Date).ToString("s")
    status = "pass"
    metrics = [ordered]@{}
    issues = @()
}

if ($GenerateTree) {
    if (-not $TNSName -or -not $Schema -or -not $ProjectId -or -not $ProjectName) {
        throw "GenerateTree requires TNSName, Schema, ProjectId, and ProjectName."
    }
    Write-Host "Generating tree HTML..."
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
    Push-Location $repoRoot
    try {
        $gen = Measure-Command {
            & ".\src\powershell\main\generate-tree-html.ps1" `
                -TNSName $TNSName -Schema $Schema -ProjectId $ProjectId -ProjectName $ProjectName
        }
    } finally {
        Pop-Location
    }
    $results.metrics.generationSeconds = [math]::Round($gen.TotalSeconds, 2)
    if ($results.metrics.generationSeconds -gt $MaxGenerationSeconds) {
        Add-Issue "Generation time $($results.metrics.generationSeconds)s exceeds $MaxGenerationSeconds s"
    }
}

if (-not (Test-Path $HtmlPath)) {
    Add-Issue "HTML file not found: $HtmlPath"
} else {
    $fileInfo = Get-Item $HtmlPath
    $results.metrics.fileSizeMb = [math]::Round($fileInfo.Length / 1MB, 2)

    $readTimes = @()
    for ($i = 1; $i -le $ReadIterations; $i++) {
        $read = Measure-Command { Get-Content -Raw $HtmlPath | Out-Null }
        $readTimes += [math]::Round($read.TotalSeconds, 2)
    }
    $results.metrics.readTimesSeconds = $readTimes
    $results.metrics.readAvgSeconds = [math]::Round(($readTimes | Measure-Object -Average).Average, 2)

    if ($results.metrics.readAvgSeconds -gt $MaxCachedLoadSeconds) {
        Add-Issue "Average read time $($results.metrics.readAvgSeconds)s exceeds $MaxCachedLoadSeconds s"
    }

    # Node count proxy
    $nodeCount = 0
    Get-Content $HtmlPath -ReadCount 5000 | ForEach-Object {
        foreach ($line in $_) {
            if ($line -match '^[0-9]+\|') {
                $nodeCount++
            }
        }
    }
    $results.metrics.nodeLineCount = $nodeCount
}

if ($BrowserProcessName) {
    $procs = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -eq $BrowserProcessName }
    if ($procs) {
        $memBytes = ($procs | Measure-Object -Property WorkingSet64 -Sum).Sum
        $results.metrics.browserMemoryMb = [math]::Round($memBytes / 1MB, 2)
        if ($results.metrics.browserMemoryMb -gt $MaxBrowserMemoryMb) {
            Add-Issue "Browser memory $($results.metrics.browserMemoryMb) MB exceeds $MaxBrowserMemoryMb MB"
        }
    } else {
        $results.metrics.browserMemoryMb = "not_measured"
    }
}

$results.endedAt = (Get-Date).ToString("s")

$reportDir = Split-Path $OutputReport
if ($reportDir -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
}

$results | ConvertTo-Json -Depth 6 | Set-Content -Encoding ASCII $OutputReport

Write-Host "Performance benchmark complete. Status: $($results.status)"
Write-Host "Report: $OutputReport"
if ($results.status -eq "fail") {
    exit 1
}
