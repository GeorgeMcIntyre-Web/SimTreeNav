# Critical Path Validation Script
# Validates that essential node relationships exist in the generated HTML tree

$htmlFile = "navigation-tree-DESIGN12-18140190.html"

Write-Host "=== Critical Path Validation ===" -ForegroundColor Cyan
Write-Host "File: $htmlFile" -ForegroundColor White

if (-not (Test-Path $htmlFile)) {
    Write-Host "`nERROR: HTML file not found! Run tree-viewer-launcher.ps1 first." -ForegroundColor Red
    exit 1
}

$allPassed = $true

# Test 1: Check total lines
Write-Host "`n1. Total lines:" -ForegroundColor Yellow
$lineCount = (Get-Content $htmlFile | Measure-Object -Line).Lines
Write-Host "   Found: $lineCount (expected: ~631,318)" -ForegroundColor White
if ($lineCount -lt 600000) {
    Write-Host "   FAIL: Line count too low!" -ForegroundColor Red
    $allPassed = $false
} elseif ($lineCount -gt 700000) {
    Write-Host "   WARN: Line count higher than expected" -ForegroundColor Yellow
} else {
    Write-Host "   PASS" -ForegroundColor Green
}

# Test 2: Check PartInstanceLibrary → P702 path
Write-Host "`n2. PartInstanceLibrary → P702 path:" -ForegroundColor Yellow
$path1 = Select-String -Path $htmlFile -Pattern "999\|18143953\|18209343\|P702" -Quiet
if ($path1) {
    Write-Host "   PASS: 18143953 → 18209343 exists" -ForegroundColor Green
} else {
    Write-Host "   FAIL: PartInstanceLibrary → P702 missing!" -ForegroundColor Red
    $allPassed = $false
}

# Test 3: Check P702 → 01 path
Write-Host "`n3. P702 → 01 path:" -ForegroundColor Yellow
$path2 = Select-String -Path $htmlFile -Pattern "999\|18209343\|18209353\|01" -Quiet
if ($path2) {
    Write-Host "   PASS: 18209343 → 18209353 exists" -ForegroundColor Green
} else {
    Write-Host "   FAIL: P702 → 01 missing!" -ForegroundColor Red
    $allPassed = $false
}

# Test 4: Check 01 → CC path
Write-Host "`n4. 01 → CC path:" -ForegroundColor Yellow
$path3 = Select-String -Path $htmlFile -Pattern "999\|18209353\|18209355\|CC" -Quiet
if ($path3) {
    Write-Host "   PASS: 18209353 → 18209355 exists" -ForegroundColor Green
} else {
    Write-Host "   FAIL: 01 → CC missing!" -ForegroundColor Red
    $allPassed = $false
}

# Test 5: Check CC → COWL_SILL_SIDE path
Write-Host "`n5. CC → COWL_SILL_SIDE path:" -ForegroundColor Yellow
$path4 = Select-String -Path $htmlFile -Pattern "999\|18209355\|18208736\|COWL_SILL_SIDE" -Quiet
if ($path4) {
    Write-Host "   PASS: 18209355 → 18208736 exists" -ForegroundColor Green
} else {
    Write-Host "   FAIL: CC → COWL_SILL_SIDE missing!" -ForegroundColor Red
    $allPassed = $false
}

# Test 6: Check all 4 PartInstance children
Write-Host "`n6. COWL_SILL_SIDE children:" -ForegroundColor Yellow
$children = @{
    "18208727" = "JL34-1610110-A-18-MBR ASY FLR SD INR FRT"
    "18208739" = "FNA11786300_2_PNL_ASY_CWL_SD_IN_RH"
    "18208716" = "FNA11786290_2_PNL_ASY_CWL_SD_IN_LH"
    "18208707" = "NL34-1610111-A-6-MBR ASY FLR SD INR FRT LH"
}
$childrenFound = 0
foreach ($childId in $children.Keys) {
    if (Select-String -Path $htmlFile -Pattern "999\|18208736\|$childId\|" -Quiet) {
        $childrenFound++
        Write-Host "   [OK] $childId - $($children[$childId])" -ForegroundColor Green
    } else {
        Write-Host "   [FAIL] $childId - $($children[$childId])" -ForegroundColor Red
        $allPassed = $false
    }
}
Write-Host "   Found: $childrenFound/4 children" -ForegroundColor $(if ($childrenFound -eq 4) { "Green" } else { "Red" })

# Test 7: Check for JavaScript cycle detection
Write-Host "`n7. Checking for cycle detection code:" -ForegroundColor Yellow
$hasVisited = Select-String -Path $htmlFile -Pattern 'visited\.has\(' -Quiet
$hasAncestor = Select-String -Path $htmlFile -Pattern 'ancestorIds\.has\(' -Quiet
if ($hasVisited -and $hasAncestor) {
    Write-Host "   PASS: Cycle detection code present" -ForegroundColor Green
} else {
    Write-Host "   FAIL: Cycle detection missing!" -ForegroundColor Red
    $allPassed = $false
}

# Test 8: Check for childMap deduplication logic
Write-Host "`n8. Checking childMap deduplication logic:" -ForegroundColor Yellow
$hasChildMap = Select-String -Path $htmlFile -Pattern 'childMap\.has\(key\)' -Quiet
$noReverseKey = -not (Select-String -Path $htmlFile -Pattern 'childMap\.has\(reverseKey\)' -Quiet)
if ($hasChildMap -and $noReverseKey) {
    Write-Host "   PASS: Correct childMap logic (no reverseKey check)" -ForegroundColor Green
} else {
    Write-Host "   WARN: childMap logic may need review" -ForegroundColor Yellow
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host "All critical tests PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests FAILED" -ForegroundColor Red
    Write-Host "Review the failures above and check your changes." -ForegroundColor Red
    exit 1
}
