# Query script for Siemens Process Simulation Database
# Executes SQL queries in read-only mode (for understanding the database)

param(
    [string]$Query = "",
    [string]$SqlFile = "",
    [string]$Username = "sys",
    [string]$Password = "change_on_install",
    [switch]$AsSysdba = $true
)

$ErrorActionPreference = "Stop"

Write-Host "Siemens Process Simulation Database Query Tool" -ForegroundColor Cyan
Write-Host "Server: des-sim-db1 | Instance: db02" -ForegroundColor Gray
Write-Host ""

# Check if sqlplus is available
$sqlplusPath = Get-Command sqlplus -ErrorAction SilentlyContinue
if (-not $sqlplusPath) {
    Write-Host "ERROR: sqlplus not found in PATH" -ForegroundColor Red
    exit 1
}

# Build connection string
if ($AsSysdba) {
    $connectionString = "$Username/$Password@SIEMENS_PS_DB AS SYSDBA"
} else {
    $connectionString = "$Username/$Password@SIEMENS_PS_DB"
}

# Create SQL script
$sqlScript = @'
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK ON
SET VERIFY OFF
SET HEADING ON
SET ECHO OFF
'@

if ($SqlFile -and (Test-Path $SqlFile)) {
    # Execute SQL file
    Write-Host "Executing SQL file: $SqlFile" -ForegroundColor Green
    Write-Host ""
    $sqlContent = Get-Content $SqlFile -Raw
    $sqlScript += "`n$sqlContent`n"
} elseif ($Query) {
    # Execute inline query
    Write-Host "Executing query..." -ForegroundColor Green
    Write-Host ""
    $sqlScript += "`n$Query`n"
} else {
    Write-Host "ERROR: Either -Query or -SqlFile parameter is required" -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage examples:" -ForegroundColor Yellow
    Write-Host "  .\query-db.ps1 -Query 'SELECT * FROM USER_TABLES'" -ForegroundColor White
    Write-Host "  .\query-db.ps1 -SqlFile myquery.sql" -ForegroundColor White
    Write-Host ""
    exit 1
}

$sqlScript += "`nEXIT;`n"

$scriptFile = Join-Path $env:TEMP "oracle_query_$(Get-Date -Format 'yyyyMMddHHmmss').sql"
$sqlScript | Out-File -FilePath $scriptFile -Encoding ASCII

# Debug: verify file was created
if (-not (Test-Path $scriptFile)) {
    Write-Host "ERROR: SQL script file was not created: $scriptFile" -ForegroundColor Red
    exit 1
}

try {
    # Execute query - use exact same method as explore-db.ps1 which works
    # Use $scriptFile directly, not resolved path
    $result = & sqlplus -S $connectionString "@$scriptFile" 2>&1
    
    # Check exit code - match explore-db.ps1 exactly
    if ($LASTEXITCODE -eq 0) {
        # Output all results - same as explore-db.ps1
        $result | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "Query execution failed (Exit Code: $exitCode)!" -ForegroundColor Red
        if ($result.Count -gt 0) {
            $result | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
    }
} catch {
    Write-Host "ERROR: Failed to execute query" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.Exception.InnerException) {
        Write-Host $_.Exception.InnerException.Message -ForegroundColor Red
    }
} finally {
    if (Test-Path $scriptFile) {
        Remove-Item $scriptFile -Force
    }
}

Write-Host ""
