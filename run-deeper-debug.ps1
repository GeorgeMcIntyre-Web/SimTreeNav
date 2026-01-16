$ErrorActionPreference = "Stop"

$TNSName = "DB01"
$connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
$queryFile = "debug-deeper.sql"

Write-Host "Running deeper investigation..." -ForegroundColor Cyan

$result = & sqlplus -S $connectionString "@$queryFile" 2>&1
$result | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Investigation completed." -ForegroundColor Green
