# Management Dashboard Launcher
# Purpose: One-command execution to generate and launch management dashboard
# Agent: 05 (Integration & Testing)
# Date: 2026-01-22

param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ProjectId,

    [int]$DaysBack = 7,

    [switch]$AutoLaunch = $true
)

# Start overall timer
$overallTimer = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Management Dashboard Launcher" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TNS:        $TNSName" -ForegroundColor Gray
Write-Host "  Schema:     $Schema" -ForegroundColor Gray
Write-Host "  Project ID: $ProjectId" -ForegroundColor Gray
Write-Host "  Days Back:  $DaysBack" -ForegroundColor Gray
Write-Host "  Auto Launch: $AutoLaunch" -ForegroundColor Gray
Write-Host ""

# Calculate date range
$endDate = Get-Date
$startDate = $endDate.AddDays(-$DaysBack)

# Define file paths
$dataFile = "data\output\management-$Schema-$ProjectId.json"
$htmlFile = "data\output\management-dashboard-$Schema-$ProjectId.html"

# ========================================
# STEP 1: Generate JSON Data (Agent 03)
# ========================================
Write-Host "STEP 1: Generating management data..." -ForegroundColor Yellow
Write-Host "  Script: src\powershell\main\get-management-data.ps1" -ForegroundColor Gray
Write-Host ""

$step1Timer = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $dataScriptPath = "src\powershell\main\get-management-data.ps1"

    if (-not (Test-Path $dataScriptPath)) {
        Write-Error "ERROR: Data extraction script not found: $dataScriptPath"
        Write-Host ""
        Write-Host "Please ensure Agent 03's script exists in src\powershell\main\" -ForegroundColor Red
        exit 1
    }

    # Run Agent 03's script
    & $dataScriptPath `
        -TNSName $TNSName `
        -Schema $Schema `
        -ProjectId $ProjectId `
        -StartDate $startDate `
        -EndDate $endDate `
        -OutputFile $dataFile

    $dataExitCode = $LASTEXITCODE

    $step1Timer.Stop()
    $step1Time = [math]::Round($step1Timer.Elapsed.TotalSeconds, 2)

    if ($dataExitCode -ne 0) {
        Write-Error "ERROR: Data extraction failed (exit code: $dataExitCode)"
        Write-Host ""
        Write-Host "Troubleshooting:" -ForegroundColor Yellow
        Write-Host "  1. Verify database connection: sqlplus user/pass@$TNSName" -ForegroundColor Yellow
        Write-Host "  2. Check schema access: $Schema" -ForegroundColor Yellow
        Write-Host "  3. Verify project ID exists: $ProjectId" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    Write-Host "  ✓ Data extraction complete ($($step1Time)s)" -ForegroundColor Green
    Write-Host ""

} catch {
    Write-Error "ERROR: Failed to run data extraction script: $_"
    exit 1
}

# Verify JSON file exists
if (-not (Test-Path $dataFile)) {
    Write-Error "ERROR: Data file not created: $dataFile"
    exit 1
}

$dataFileSize = [math]::Round((Get-Item $dataFile).Length / 1MB, 2)
Write-Host "  Data file: $dataFile ($dataFileSize MB)" -ForegroundColor Gray
Write-Host ""

# ========================================
# STEP 2: Generate HTML Dashboard (Agent 04)
# ========================================
Write-Host "STEP 2: Generating HTML dashboard..." -ForegroundColor Yellow
Write-Host "  Script: scripts\generate-management-dashboard.ps1" -ForegroundColor Gray
Write-Host ""

$step2Timer = [System.Diagnostics.Stopwatch]::StartNew()

try {
    $dashboardScriptPath = "scripts\generate-management-dashboard.ps1"

    if (-not (Test-Path $dashboardScriptPath)) {
        Write-Error "ERROR: Dashboard generator script not found: $dashboardScriptPath"
        Write-Host ""
        Write-Host "Please ensure Agent 04's script exists in scripts\" -ForegroundColor Red
        exit 1
    }

    # Run Agent 04's script
    & $dashboardScriptPath `
        -DataFile $dataFile `
        -OutputFile $htmlFile

    $dashboardExitCode = $LASTEXITCODE

    $step2Timer.Stop()
    $step2Time = [math]::Round($step2Timer.Elapsed.TotalSeconds, 2)

    if ($dashboardExitCode -ne 0) {
        Write-Error "ERROR: Dashboard generation failed (exit code: $dashboardExitCode)"
        Write-Host ""
        Write-Host "Troubleshooting:" -ForegroundColor Yellow
        Write-Host "  1. Verify data file is valid JSON: $dataFile" -ForegroundColor Yellow
        Write-Host "  2. Check disk space for output directory" -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }

    Write-Host "  ✓ Dashboard generation complete ($($step2Time)s)" -ForegroundColor Green
    Write-Host ""

} catch {
    Write-Error "ERROR: Failed to run dashboard generator: $_"
    exit 1
}

# Verify HTML file exists
if (-not (Test-Path $htmlFile)) {
    Write-Error "ERROR: Dashboard file not created: $htmlFile"
    exit 1
}

$htmlFileSize = [math]::Round((Get-Item $htmlFile).Length / 1MB, 2)
Write-Host "  Dashboard file: $htmlFile ($htmlFileSize MB)" -ForegroundColor Gray
Write-Host ""

# ========================================
# STEP 3: Parse and Display Summary Stats
# ========================================
Write-Host "STEP 3: Analyzing dashboard data..." -ForegroundColor Yellow
Write-Host ""

try {
    $jsonContent = Get-Content $dataFile -Raw -Encoding UTF8
    $data = $jsonContent | ConvertFrom-Json

    # Count active and modified items per work type
    $projectDbActive = @($data.projectDatabase | Where-Object { $_.status -eq 'Checked Out' -or $_.status -eq 'Active' }).Count
    $projectDbModified = @($data.projectDatabase).Count

    $resourceActive = @($data.resourceLibrary | Where-Object { $_.status -eq 'Checked Out' -or $_.status -eq 'Active' }).Count
    $resourceModified = @($data.resourceLibrary).Count

    $partActive = @($data.partLibrary | Where-Object { $_.status -eq 'Checked Out' -or $_.status -eq 'Active' }).Count
    $partModified = @($data.partLibrary).Count

    $ipaActive = @($data.ipaAssembly | Where-Object { $_.status -eq 'Checked Out' -or $_.status -eq 'Active' }).Count
    $ipaModified = @($data.ipaAssembly).Count

    $studyActive = @($data.studySummary | Where-Object { $_.status -eq 'Checked Out' -or $_.status -eq 'Active' }).Count
    $studyModified = @($data.studySummary).Count

    # Count movements
    $simpleMovements = @($data.studyMovements | Where-Object { $_.location_vector_id -and !$_.rotation_vector_id }).Count
    $worldLocationChanges = @($data.studyMovements | Where-Object { $_.location_vector_id -and $_.rotation_vector_id }).Count

    Write-Host "  Activity Summary:" -ForegroundColor Cyan
    Write-Host "    - Project Database:  $projectDbActive active, $projectDbModified modified" -ForegroundColor Gray
    Write-Host "    - Resource Library:  $resourceActive active, $resourceModified modified" -ForegroundColor Gray
    Write-Host "    - Part/MFG Library:  $partActive active, $partModified modified" -ForegroundColor Gray
    Write-Host "    - IPA Assemblies:    $ipaActive active, $ipaModified modified" -ForegroundColor Gray
    Write-Host "    - Study Nodes:       $studyActive active, $studyModified modified" -ForegroundColor Gray
    Write-Host "    - Movements:         $simpleMovements simple, $worldLocationChanges world location changes" -ForegroundColor Gray
    Write-Host ""

} catch {
    Write-Warning "Could not parse summary statistics from data file"
    Write-Host "  Dashboard still generated successfully" -ForegroundColor Gray
    Write-Host ""
}

# ========================================
# STEP 4: Launch Dashboard (Optional)
# ========================================
if ($AutoLaunch) {
    Write-Host "STEP 4: Launching dashboard in browser..." -ForegroundColor Yellow
    Write-Host ""

    try {
        $fullPath = [System.IO.Path]::GetFullPath($htmlFile)
        Start-Process $fullPath
        Write-Host "  ✓ Dashboard opened in default browser" -ForegroundColor Green
        Write-Host ""
    } catch {
        Write-Warning "Could not launch browser automatically: $_"
        Write-Host "  Please open manually: $htmlFile" -ForegroundColor Yellow
        Write-Host ""
    }
} else {
    Write-Host "STEP 4: Skipped (AutoLaunch disabled)" -ForegroundColor Gray
    Write-Host ""
}

# ========================================
# COMPLETION SUMMARY
# ========================================
$overallTimer.Stop()
$totalTime = [math]::Round($overallTimer.Elapsed.TotalSeconds, 2)

Write-Host "========================================" -ForegroundColor Green
Write-Host "  Dashboard Generated Successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  File: $htmlFile" -ForegroundColor White
Write-Host "  Size: $htmlFileSize MB" -ForegroundColor Gray
Write-Host "  Total Time: $($totalTime)s" -ForegroundColor Gray
Write-Host ""
Write-Host "  Date Range: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
Write-Host ""

if (-not $AutoLaunch) {
    Write-Host "To view the dashboard, open the file in your web browser:" -ForegroundColor Yellow
    Write-Host "  $htmlFile" -ForegroundColor Cyan
    Write-Host ""
}

Write-Host "✓ All steps completed successfully" -ForegroundColor Green
Write-Host ""

exit 0
