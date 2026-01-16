# Run diagnostic query for TYPE_ID 164 class hierarchy
$ErrorActionPreference = "Stop"

# Use the same connection logic as tree-viewer-launcher
$TNSName = "DB01"
$connectionString = "sys/change_on_install@$TNSName AS SYSDBA"

Write-Host "Running diagnostic query for TYPE_ID 164 class hierarchy..." -ForegroundColor Cyan
Write-Host "Connection: $TNSName" -ForegroundColor Gray
Write-Host ""

$queryFile = "test-dynamic-lookup.sql"

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
