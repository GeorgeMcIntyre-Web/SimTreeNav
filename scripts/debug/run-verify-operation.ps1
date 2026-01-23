# Run Operation Parent Relationship Verification Query

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Operation Parent Verification" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import credential manager
Import-Module .\src\powershell\utilities\CredentialManager.ps1 -Force

# Get connection string
Write-Host "Retrieving credentials..." -ForegroundColor Yellow
$connStr = Get-DbConnectionString -TNSName "DB01" -AsSysDBA

# Set Oracle environment
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

# Run query
Write-Host "Running operation parent verification query..." -ForegroundColor Yellow
$outputFile = "operation-parent-verification.txt"
sqlplus -S $connStr "@verify-operation-parent.sql" | Out-File $outputFile -Encoding UTF8

Write-Host "Query complete!`n" -ForegroundColor Green
Write-Host "Output saved to: $outputFile`n" -ForegroundColor Cyan

# Display results
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Query Results" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Get-Content $outputFile

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Complete!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan
