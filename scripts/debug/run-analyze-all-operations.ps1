# Analyze All Operation Tables
$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Analyzing All OPERATION Tables" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Import-Module .\src\powershell\utilities\CredentialManager.ps1 -Force

Write-Host "Retrieving credentials..." -ForegroundColor Yellow
$connStr = Get-DbConnectionString -TNSName "DB01" -AsSysDBA

$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

Write-Host "Running analysis query..." -ForegroundColor Yellow
$outputFile = "all-operation-tables-analysis.txt"
sqlplus -S $connStr "@analyze-all-operation-tables.sql" | Out-File $outputFile -Encoding UTF8

Write-Host "Analysis complete!`n" -ForegroundColor Green
Write-Host "Output saved to: $outputFile`n" -ForegroundColor Cyan

Get-Content $outputFile

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
