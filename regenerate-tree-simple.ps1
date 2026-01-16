# Simple regeneration script
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Regenerating Navigation Tree" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Project details from last used profile
$projectName = "FORD_DEARBORN"
$projectId = "18140190"
$schema = "DESIGN12"
$tnsName = "DB01"

# SQL query file
$queryFile = "get-tree-$schema-$projectId.sql"

if (-not (Test-Path $queryFile)) {
    Write-Error "Query file not found: $queryFile"
    exit 1
}

Write-Host "Project: $projectName" -ForegroundColor Green
Write-Host "Project ID: $projectId" -ForegroundColor Green
Write-Host "Schema: $schema" -ForegroundColor Green
Write-Host "Query File: $queryFile" -ForegroundColor Green
Write-Host ""

# Skip SQL execution - generate-tree-html.ps1 will do it
Write-Host "Preparing to generate HTML (SQL execution will happen inside generate-tree-html.ps1)..." -ForegroundColor Cyan
Write-Host ""

# Generate HTML
Write-Host "Generating HTML..." -ForegroundColor Cyan
$outputFile = "navigation-tree-$schema-$projectId.html"

# Call generate-tree-html.ps1 with correct parameters
& ".\src\powershell\main\generate-tree-html.ps1" `
    -TNSName $tnsName `
    -ProjectName $projectName `
    -ProjectId $projectId `
    -Schema $schema `
    -OutputFile $outputFile

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  SUCCESS!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "HTML file generated: $outputFile" -ForegroundColor Yellow
    Write-Host ""
}

exit $LASTEXITCODE
