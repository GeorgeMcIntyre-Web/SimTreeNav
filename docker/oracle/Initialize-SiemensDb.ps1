# Initialize-SiemensDb.ps1
# Creates Siemens Tecnomatix tablespaces, roles, and EMP_ADMIN user
# in the local Oracle Docker container
#
# Usage:
#   .\Initialize-SiemensDb.ps1
#   .\Initialize-SiemensDb.ps1 -OraclePwd mypassword

param(
    [string]$ContainerName = "oracle-tecnomatix-12c",
    [string]$OraclePwd = "change_on_install",
    [string]$OracleSid = "EMS12"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Siemens Tecnomatix Database Setup" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check container is running
$containerStatus = docker ps --filter "name=$ContainerName" --format "{{.Status}}" 2>$null
if (-not $containerStatus -or $containerStatus -notmatch "Up") {
    Write-Host "ERROR: Container '$ContainerName' is not running." -ForegroundColor Red
    Write-Host "  Run Start-OracleDocker.ps1 first." -ForegroundColor Yellow
    exit 1
}

# Check health
$health = docker inspect --format='{{.State.Health.Status}}' $ContainerName 2>$null
if ($health -ne "healthy") {
    Write-Host "WARNING: Container is not yet healthy (status: $health)." -ForegroundColor Yellow
    Write-Host "  Oracle may still be initializing. Wait and try again." -ForegroundColor Yellow
    exit 1
}

$connStr = "sys/$OraclePwd@localhost:1521/$OracleSid as sysdba"

# Step 1: Create tablespaces
Write-Host "Step 1/2: Creating Siemens tablespaces..." -ForegroundColor Yellow
$tablespaceScript = Join-Path $scriptDir "scripts\setup\01-create-tablespaces.sql"
$containerScript = "/opt/oracle/scripts/setup/01-create-tablespaces.sql"

docker exec $ContainerName bash -c "sqlplus -S '$connStr' @$containerScript"

if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Tablespace creation had issues. Some may already exist." -ForegroundColor Yellow
} else {
    Write-Host "  Tablespaces created." -ForegroundColor Green
}

# Step 2: Run after_install (roles + EMP_ADMIN)
Write-Host ""
Write-Host "Step 2/2: Creating roles and EMP_ADMIN user..." -ForegroundColor Yellow
$afterInstallScript = "/opt/oracle/scripts/setup/02-after-install.sql"

docker exec $ContainerName bash -c "sqlplus -S '$connStr' @$afterInstallScript"

if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: After-install had issues. Some objects may already exist." -ForegroundColor Yellow
} else {
    Write-Host "  Roles and EMP_ADMIN created." -ForegroundColor Green
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Siemens Database Setup Complete" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "    1. Import your dump file:" -ForegroundColor White
Write-Host "       .\Import-DatabaseDump.ps1 -DumpFile 'path\to\your.dmp'" -ForegroundColor Gray
Write-Host "    2. Verify the setup:" -ForegroundColor White
Write-Host "       .\Verify-LocalDatabase.ps1" -ForegroundColor Gray
Write-Host ""
