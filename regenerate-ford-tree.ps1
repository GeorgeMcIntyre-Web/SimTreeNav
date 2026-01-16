# Regenerate FORD_DEARBORN tree with all fixes
$ErrorActionPreference = "Stop"

$TNSName = "DB01"
$Schema = "DESIGN12"
$ProjectId = "18140190"
$ProjectName = "FORD_DEARBORN"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "Regenerating tree with ALL FIXES" -ForegroundColor Yellow
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Fixes applied:" -ForegroundColor Green
Write-Host "  1. EngineeringResourceLibrary icon (TYPE_ID 164 -> 48 fallback)" -ForegroundColor Gray
Write-Host "  2. COWL_SILL_SIDE missing PART_ children extraction" -ForegroundColor Gray
Write-Host "  3. PartInstanceLibrary PART_->PART_ children extraction" -ForegroundColor Gray
Write-Host ""

$generateScript = "src\powershell\main\generate-tree-html.ps1"

if (-not (Test-Path $generateScript)) {
    Write-Error "Generate script not found: $generateScript"
    exit 1
}

Write-Host "Running tree generation..." -ForegroundColor Cyan
& $generateScript -TNSName $TNSName -Schema $Schema -ProjectId $ProjectId -ProjectName $ProjectName

Write-Host ""
Write-Host "Tree regeneration complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Open the generated HTML file" -ForegroundColor Gray
Write-Host "  2. Search for node 18153685 (EngineeringResourceLibrary) - verify icon" -ForegroundColor Gray
Write-Host "  3. Search for node 18208744 (COWL_SILL_SIDE) - verify 4+ children" -ForegroundColor Gray
Write-Host "  4. Search for node 18143953 (PartInstanceLibrary) - verify children P702, P736" -ForegroundColor Gray
