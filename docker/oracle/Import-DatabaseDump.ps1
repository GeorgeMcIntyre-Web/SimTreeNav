# Import-DatabaseDump.ps1
# Imports a Data Pump (.dmp) file into the local Oracle Docker container
#
# Usage:
#   .\Import-DatabaseDump.ps1 -DumpFile "C:\path\to\export.dmp"
#   .\Import-DatabaseDump.ps1 -DumpFile "C:\path\to\export.dmp" -Schemas DESIGN1,DESIGN2
#   .\Import-DatabaseDump.ps1 -DumpFile "C:\path\to\export.dmp" -FullImport -Parallel 4

param(
    [Parameter(Mandatory=$true)]
    [string]$DumpFile,

    [string[]]$Schemas,

    [switch]$FullImport,

    [int]$Parallel = 4,

    [ValidateSet("REPLACE", "APPEND", "SKIP", "TRUNCATE")]
    [string]$TableExistsAction = "REPLACE",

    [string]$ContainerName = "oracle-tecnomatix-12c",

    [string]$OraclePwd = "change_on_install",

    [string]$OracleSid = "EMS12"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Oracle Data Pump Import" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Validate dump file exists
if (-not (Test-Path $DumpFile)) {
    Write-Host "ERROR: Dump file not found: $DumpFile" -ForegroundColor Red
    exit 1
}

$dumpFileName = Split-Path $DumpFile -Leaf
$dumpFileSize = [math]::Round((Get-Item $DumpFile).Length / 1GB, 2)

Write-Host "  Dump File: $dumpFileName ($dumpFileSize GB)" -ForegroundColor White

# Check container is running
$containerStatus = docker ps --filter "name=$ContainerName" --format "{{.Status}}" 2>$null
if (-not $containerStatus -or $containerStatus -notmatch "Up") {
    Write-Host "ERROR: Container '$ContainerName' is not running." -ForegroundColor Red
    Write-Host "  Run Start-OracleDocker.ps1 first." -ForegroundColor Yellow
    exit 1
}

# Copy dump file to container volume
$dumpDir = Join-Path $scriptDir "..\..\docker\volumes\dump"
if (-not (Test-Path $dumpDir)) {
    New-Item -ItemType Directory -Path $dumpDir -Force | Out-Null
}

Write-Host ""
Write-Host "Copying dump file to container volume..." -ForegroundColor Yellow
Copy-Item $DumpFile -Destination $dumpDir -Force
Write-Host "  Copied to: $dumpDir\$dumpFileName" -ForegroundColor Gray

# Ensure DUMP_DIR Oracle directory exists
Write-Host ""
Write-Host "Creating Oracle directory for import..." -ForegroundColor Yellow
docker exec $ContainerName bash -c "echo `"CREATE OR REPLACE DIRECTORY DUMP_DIR AS '/opt/oracle/admin/dump'; GRANT READ, WRITE ON DIRECTORY DUMP_DIR TO SYSTEM; EXIT;`" | sqlplus -S sys/$OraclePwd@localhost:1521/$OracleSid as sysdba"

# Build impdp command
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = "import_${timestamp}.log"

$impdpArgs = @(
    "system/${OraclePwd}@localhost:1521/${OracleSid}"
    "DIRECTORY=DUMP_DIR"
    "DUMPFILE=$dumpFileName"
    "LOGFILE=$logFile"
    "TABLE_EXISTS_ACTION=$TableExistsAction"
    "PARALLEL=$Parallel"
)

if ($FullImport) {
    $impdpArgs += "FULL=Y"
    Write-Host "  Mode: FULL import" -ForegroundColor White
} elseif ($Schemas -and $Schemas.Count -gt 0) {
    $schemaList = $Schemas -join ","
    $impdpArgs += "SCHEMAS=$schemaList"
    Write-Host "  Mode: Schema import ($schemaList)" -ForegroundColor White
} else {
    $impdpArgs += "FULL=Y"
    Write-Host "  Mode: FULL import (default)" -ForegroundColor White
}

Write-Host "  Parallel: $Parallel" -ForegroundColor White
Write-Host "  Table Exists: $TableExistsAction" -ForegroundColor White
Write-Host "  Log File: $logFile" -ForegroundColor White
Write-Host ""

# Run impdp
Write-Host "Starting Data Pump import..." -ForegroundColor Yellow
Write-Host "  This may take a while for large dumps." -ForegroundColor Gray
Write-Host "  Monitor progress: docker exec $ContainerName cat /opt/oracle/admin/dump/$logFile" -ForegroundColor Gray
Write-Host ""

$impdpCmd = "impdp " + ($impdpArgs -join " ")
docker exec $ContainerName bash -c $impdpCmd

$exitCode = $LASTEXITCODE

Write-Host ""
if ($exitCode -eq 0) {
    Write-Host "Import completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Import completed with warnings or errors (exit code: $exitCode)." -ForegroundColor Yellow
    Write-Host "  Check log: docker exec $ContainerName cat /opt/oracle/admin/dump/$logFile" -ForegroundColor Gray
}

# Show import summary
Write-Host ""
Write-Host "=== Import Summary ===" -ForegroundColor Cyan
docker exec $ContainerName bash -c "echo 'SELECT owner, COUNT(*) as table_count FROM dba_tables WHERE owner LIKE '\''DESIGN%'\'' GROUP BY owner ORDER BY owner;' | sqlplus -S system/$OraclePwd@localhost:1521/$OracleSid"

Write-Host ""
Write-Host "Run Verify-LocalDatabase.ps1 for full verification." -ForegroundColor Gray
