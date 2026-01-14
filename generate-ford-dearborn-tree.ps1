#!/usr/bin/env pwsh
# Quick launcher for generating FORD_DEARBORN tree

Write-Host "Generating FORD_DEARBORN tree with all study nodes..." -ForegroundColor Cyan
Write-Host ""

& "$PSScriptRoot\src\powershell\main\generate-tree-html.ps1" `
    -TNSName "SIEMENS_PS_DB_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18140190 `
    -ProjectName "FORD_DEARBORN" `
    -OutputFile "navigation-tree-DESIGN12-18140190.html"

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "SUCCESS! Tree generated." -ForegroundColor Green
    Write-Host "File: navigation-tree-DESIGN12-18140190.html" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Open the HTML file in your browser" -ForegroundColor White
    Write-Host "  2. If root icon shows '?', press Ctrl+F5 to hard refresh" -ForegroundColor White
    Write-Host "  3. Verify 'DDMP P702_8J_010_8J_060' appears under 'COWL & SILL SIDE'" -ForegroundColor White
}
