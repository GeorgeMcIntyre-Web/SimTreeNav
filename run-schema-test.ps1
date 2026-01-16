$ErrorActionPreference = "Stop"

$TNSName = "DB01"
$connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
$queryFile = "test-schema-access.sql"

Write-Host "Testing schema access..." -ForegroundColor Cyan

$result = & sqlplus -S $connectionString "@$queryFile" 2>&1
$result | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Test completed." -ForegroundColor Green
