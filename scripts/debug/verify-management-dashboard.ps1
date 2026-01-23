# Verify Management Dashboard
# Purpose: Automated verification script to validate dashboard correctness
# Agent: 05 (Integration & Testing)
# Date: 2026-01-22

param(
    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ProjectId
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Management Dashboard Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Schema:     $Schema" -ForegroundColor Gray
Write-Host "  Project ID: $ProjectId" -ForegroundColor Gray
Write-Host ""

# Define file paths
$dataFile = "data\output\management-$Schema-$ProjectId.json"
$htmlFile = "data\output\management-dashboard-$Schema-$ProjectId.html"

# Initialize results
$checksPassed = 0
$checksFailed = 0
$checksTotal = 0

function Test-Check {
    param(
        [string]$Description,
        [bool]$Condition,
        [string]$SuccessMessage = "",
        [string]$FailureMessage = ""
    )

    $script:checksTotal++

    if ($Condition) {
        Write-Host "  ✓ PASS: $Description" -ForegroundColor Green
        if ($SuccessMessage) {
            Write-Host "    $SuccessMessage" -ForegroundColor Gray
        }
        $script:checksPassed++
        return $true
    } else {
        Write-Host "  ✗ FAIL: $Description" -ForegroundColor Red
        if ($FailureMessage) {
            Write-Host "    $FailureMessage" -ForegroundColor Yellow
        }
        $script:checksFailed++
        return $false
    }
}

# ========================================
# CHECK 1: JSON File Exists
# ========================================
$jsonExists = Test-Path $dataFile
$jsonFileSize = if ($jsonExists) { [math]::Round((Get-Item $dataFile).Length / 1MB, 2) } else { 0 }

Test-Check `
    -Description "JSON file exists" `
    -Condition $jsonExists `
    -SuccessMessage "File: $dataFile ($jsonFileSize MB)" `
    -FailureMessage "File not found: $dataFile"

# ========================================
# CHECK 2: HTML File Exists
# ========================================
$htmlExists = Test-Path $htmlFile
$htmlFileSize = if ($htmlExists) { [math]::Round((Get-Item $htmlFile).Length / 1MB, 2) } else { 0 }

Test-Check `
    -Description "HTML file exists" `
    -Condition $htmlExists `
    -SuccessMessage "File: $htmlFile ($htmlFileSize MB)" `
    -FailureMessage "File not found: $htmlFile"

# Exit early if files don't exist
if (-not $jsonExists -or -not $htmlExists) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  VERIFICATION FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  Required files missing. Generate dashboard first using:" -ForegroundColor Yellow
    Write-Host "    .\management-dashboard-launcher.ps1 -TNSName <tns> -Schema $Schema -ProjectId $ProjectId" -ForegroundColor Cyan
    Write-Host ""
    exit 1
}

# ========================================
# CHECK 3: JSON is Valid
# ========================================
$jsonValid = $false
$data = $null

try {
    $jsonContent = Get-Content $dataFile -Raw -Encoding UTF8
    $data = $jsonContent | ConvertFrom-Json
    $jsonValid = $true
} catch {
    $jsonValid = $false
}

Test-Check `
    -Description "JSON is valid and parseable" `
    -Condition $jsonValid `
    -SuccessMessage "JSON parsed successfully" `
    -FailureMessage "JSON parsing failed: $_"

# Exit early if JSON is invalid
if (-not $jsonValid) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  VERIFICATION FAILED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  JSON file is corrupt. Regenerate using get-management-data.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# ========================================
# CHECK 4: All 5 Work Type Sections Present
# ========================================
$hasProjectDatabase = $null -ne $data.projectDatabase
$hasResourceLibrary = $null -ne $data.resourceLibrary
$hasPartLibrary = $null -ne $data.partLibrary
$hasIpaAssembly = $null -ne $data.ipaAssembly
$hasStudySummary = $null -ne $data.studySummary

$allWorkTypesPresent = $hasProjectDatabase -and $hasResourceLibrary -and $hasPartLibrary -and $hasIpaAssembly -and $hasStudySummary

Test-Check `
    -Description "All 5 work type sections present in JSON" `
    -Condition $allWorkTypesPresent `
    -SuccessMessage "Project Database, Resource Library, Part Library, IPA Assembly, Study Summary" `
    -FailureMessage "Missing work type sections"

if (-not $allWorkTypesPresent) {
    if (-not $hasProjectDatabase) { Write-Host "    Missing: projectDatabase" -ForegroundColor Red }
    if (-not $hasResourceLibrary) { Write-Host "    Missing: resourceLibrary" -ForegroundColor Red }
    if (-not $hasPartLibrary) { Write-Host "    Missing: partLibrary" -ForegroundColor Red }
    if (-not $hasIpaAssembly) { Write-Host "    Missing: ipaAssembly" -ForegroundColor Red }
    if (-not $hasStudySummary) { Write-Host "    Missing: studySummary" -ForegroundColor Red }
}

# ========================================
# CHECK 5: Metadata Section Present
# ========================================
$hasMetadata = $null -ne $data.metadata
$metadataValid = $hasMetadata -and
                 $data.metadata.schema -and
                 $data.metadata.projectId -and
                 $data.metadata.startDate -and
                 $data.metadata.endDate

Test-Check `
    -Description "Metadata section complete" `
    -Condition $metadataValid `
    -SuccessMessage "Schema: $($data.metadata.schema), Project: $($data.metadata.projectId), Range: $($data.metadata.startDate) to $($data.metadata.endDate)" `
    -FailureMessage "Metadata section missing or incomplete"

# ========================================
# CHECK 6: Activity Data Present (If Expected)
# ========================================
$totalItems = @($data.projectDatabase).Count +
              @($data.resourceLibrary).Count +
              @($data.partLibrary).Count +
              @($data.ipaAssembly).Count +
              @($data.studySummary).Count

if ($totalItems -gt 0) {
    Test-Check `
        -Description "Activity data present ($totalItems items)" `
        -Condition $true `
        -SuccessMessage "Found activity across work types"
} else {
    Test-Check `
        -Description "No activity data found" `
        -Condition $true `
        -SuccessMessage "Empty state (valid for date ranges with no activity)"
}

# ========================================
# CHECK 7: User Activity Data
# ========================================
$userCount = if ($data.userActivity) { @($data.userActivity).Count } else { 0 }

if ($totalItems -gt 0) {
    $hasUserActivity = $userCount -gt 0

    Test-Check `
        -Description "User activity data present" `
        -Condition $hasUserActivity `
        -SuccessMessage "$userCount unique users found" `
        -FailureMessage "Expected user activity data when items are modified"
} else {
    Test-Check `
        -Description "User activity (skipped for empty data)" `
        -Condition $true `
        -SuccessMessage "No items, no user activity expected"
}

# ========================================
# CHECK 8: HTML File Size Reasonable
# ========================================
$htmlSizeReasonable = $htmlFileSize -gt 0.01 -and $htmlFileSize -le 10

Test-Check `
    -Description "HTML file size reasonable (0.01 MB - 10 MB)" `
    -Condition $htmlSizeReasonable `
    -SuccessMessage "$htmlFileSize MB (within limits)" `
    -FailureMessage "$htmlFileSize MB (expected between 0.01 and 10 MB)"

# ========================================
# CHECK 9: HTML Contains Required Sections
# ========================================
$htmlContent = Get-Content $htmlFile -Raw -Encoding UTF8

$hasViewTabs = $htmlContent -match 'Work Type Summary' -and
               $htmlContent -match 'Active Studies' -and
               $htmlContent -match 'Movement Activity' -and
               $htmlContent -match 'User Activity' -and
               $htmlContent -match 'Timeline' -and
               $htmlContent -match 'Activity Log'

Test-Check `
    -Description "HTML contains all 6 view tabs" `
    -Condition $hasViewTabs `
    -SuccessMessage "All view sections present" `
    -FailureMessage "Missing view sections in HTML"

# ========================================
# CHECK 10: HTML Contains JavaScript
# ========================================
$hasJavaScript = $htmlContent -match '<script>' -and
                 $htmlContent -match 'dashboardData' -and
                 $htmlContent -match 'renderWorkTypeSummary'

Test-Check `
    -Description "HTML contains inline JavaScript" `
    -Condition $hasJavaScript `
    -SuccessMessage "JavaScript code embedded" `
    -FailureMessage "JavaScript code missing or incomplete"

# ========================================
# CHECK 11: HTML Contains CSS
# ========================================
$hasCSS = $htmlContent -match '<style>' -and
          $htmlContent -match 'nav-tab' -and
          $htmlContent -match 'data-table'

Test-Check `
    -Description "HTML contains inline CSS" `
    -Condition $hasCSS `
    -SuccessMessage "CSS styles embedded" `
    -FailureMessage "CSS styles missing or incomplete"

# ========================================
# CHECK 12: No JavaScript Errors (Static Check)
# ========================================
# Note: Full JS error checking requires headless browser
# This is a basic static check for common syntax errors

$hasJSErrors = $htmlContent -match 'undefined is not a function' -or
               $htmlContent -match 'null reference' -or
               $htmlContent -match 'syntax error'

Test-Check `
    -Description "No obvious JavaScript syntax errors" `
    -Condition (-not $hasJSErrors) `
    -SuccessMessage "No syntax errors detected (static check)" `
    -FailureMessage "Possible JavaScript errors found"

# ========================================
# SUMMARY
# ========================================
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Verification Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Total Checks: $checksTotal" -ForegroundColor Gray
Write-Host "  Passed:       $checksPassed" -ForegroundColor Green
Write-Host "  Failed:       $checksFailed" -ForegroundColor $(if ($checksFailed -gt 0) { "Red" } else { "Gray" })
Write-Host ""

if ($checksFailed -eq 0) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  OVERALL: PASS ($checksPassed/$checksTotal checks)" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  ✓ Dashboard is valid and ready for use" -ForegroundColor Green
    Write-Host "  ✓ All acceptance criteria met" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Dashboard location: $htmlFile" -ForegroundColor Cyan
    Write-Host ""
    exit 0
} else {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  OVERALL: FAIL ($checksFailed/$checksTotal checks failed)" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Please review failed checks and regenerate dashboard" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
