# Test OPERATION_ Query
$ErrorActionPreference = "Stop"

Import-Module .\src\powershell\utilities\CredentialManager.ps1 -Force
$connStr = Get-DbConnectionString -TNSName "DB01" -AsSysDBA
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

Write-Host "Running OPERATION_ query test..." -ForegroundColor Yellow
sqlplus -S $connStr "@test-operation-query.sql"
