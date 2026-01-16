# Run comprehensive debug for all three issues using Oracle
$ErrorActionPreference = "Stop"

$TNSName = "DB01"
$connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
$queryFile = "debug-all-issues-proof.sql"

Write-Host "Running comprehensive debug query..." -ForegroundColor Cyan
Write-Host "Connection: $TNSName" -ForegroundColor Gray
Write-Host ""

if (-not (Test-Path $queryFile)) {
    Write-Error "Query file not found: $queryFile"
    exit 1
}

# Run the query
$result = & sqlplus -S $connectionString "@$queryFile" 2>&1

# Display results
$result | ForEach-Object { Write-Host $_ }

Write-Host ""
Write-Host "Query completed." -ForegroundColor Green
