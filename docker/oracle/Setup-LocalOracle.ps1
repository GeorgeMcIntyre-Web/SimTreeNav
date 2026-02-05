# Setup-LocalOracle.ps1
# Master setup script for local Oracle 12c Tecnomatix development environment
#
# This script performs the complete setup:
#   1. Validates prerequisites (Docker, Oracle Container Registry login)
#   2. Starts Oracle 12c Docker container
#   3. Creates Siemens tablespaces
#   4. Runs after_install.sql (roles + EMP_ADMIN)
#   5. Optionally imports a dump file
#   6. Switches database target to LOCAL
#   7. Runs verification
#
# Usage:
#   .\Setup-LocalOracle.ps1
#   .\Setup-LocalOracle.ps1 -DumpFile "C:\path\to\export.dmp"
#   .\Setup-LocalOracle.ps1 -SkipImport

param(
    [string]$DumpFile,
    [switch]$SkipImport,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Local Oracle 12c Tecnomatix - Complete Setup" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This will set up a complete local Oracle 12c database" -ForegroundColor White
Write-Host "  with the Siemens Tecnomatix schema structure." -ForegroundColor White
Write-Host ""

# ==========================================
# Step 1: Prerequisites
# ==========================================
Write-Host "STEP 1: Checking prerequisites..." -ForegroundColor Yellow
Write-Host "  [1/3] Docker Desktop..." -NoNewline
try {
    $dockerVersion = docker version --format '{{.Server.Version}}' 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host " OK (v$dockerVersion)" -ForegroundColor Green
    } else {
        throw "Docker not running"
    }
} catch {
    Write-Host " FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "  ERROR: Docker Desktop is not running or not installed." -ForegroundColor Red
    Write-Host "  Install from: https://www.docker.com/products/docker-desktop" -ForegroundColor Gray
    exit 1
}

Write-Host "  [2/3] Oracle Container Registry login..." -NoNewline
# Check if we can pull from Oracle registry (cached check)
$imageExists = docker images --format "{{.Repository}}:{{.Tag}}" | Select-String "container-registry.oracle.com/database/enterprise:12.2.0.1"
if ($imageExists) {
    Write-Host " OK (image cached)" -ForegroundColor Green
} else {
    Write-Host " (will verify during pull)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  If pull fails, run:" -ForegroundColor Gray
    Write-Host "    docker login container-registry.oracle.com" -ForegroundColor Gray
    Write-Host "  (requires Oracle SSO account)" -ForegroundColor Gray
}

Write-Host "  [3/3] Disk space..." -NoNewline
$drive = (Get-Item $scriptDir).PSDrive
$freeGB = [math]::Round($drive.Free / 1GB, 1)
if ($freeGB -gt 50) {
    Write-Host " OK (${freeGB}GB free)" -ForegroundColor Green
} elseif ($freeGB -gt 30) {
    Write-Host " WARNING (${freeGB}GB free - recommend 50GB+)" -ForegroundColor Yellow
} else {
    Write-Host " LOW (${freeGB}GB free - need at least 30GB)" -ForegroundColor Red
    exit 1
}

Write-Host ""

# ==========================================
# Step 2: Start Docker Container
# ==========================================
Write-Host "STEP 2: Starting Oracle 12c container..." -ForegroundColor Yellow
& (Join-Path $scriptDir "Start-OracleDocker.ps1") -Force:$Force

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to start Oracle container." -ForegroundColor Red
    exit 1
}

Write-Host ""

# ==========================================
# Step 3: Initialize Siemens Database
# ==========================================
Write-Host "STEP 3: Initializing Siemens database structure..." -ForegroundColor Yellow
& (Join-Path $scriptDir "Initialize-SiemensDb.ps1")

if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Database initialization had issues. Continuing..." -ForegroundColor Yellow
}

Write-Host ""

# ==========================================
# Step 4: Import Dump (optional)
# ==========================================
if (-not $SkipImport) {
    if (-not $DumpFile) {
        Write-Host "STEP 4: Data Pump Import" -ForegroundColor Yellow
        Write-Host ""
        $DumpFile = Read-Host "  Enter path to .dmp file (or press Enter to skip)"
    }

    if ($DumpFile -and (Test-Path $DumpFile)) {
        Write-Host "STEP 4: Importing dump file..." -ForegroundColor Yellow
        & (Join-Path $scriptDir "Import-DatabaseDump.ps1") -DumpFile $DumpFile -FullImport

        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Import had issues. Check logs." -ForegroundColor Yellow
        }
    } elseif ($DumpFile) {
        Write-Host "  WARNING: Dump file not found: $DumpFile" -ForegroundColor Yellow
        Write-Host "  Skipping import. You can import later with Import-DatabaseDump.ps1" -ForegroundColor Gray
    } else {
        Write-Host "STEP 4: Import skipped." -ForegroundColor Gray
    }
} else {
    Write-Host "STEP 4: Import skipped (-SkipImport)." -ForegroundColor Gray
}

Write-Host ""

# ==========================================
# Step 5: Switch Database Target
# ==========================================
Write-Host "STEP 5: Switching database target to LOCAL..." -ForegroundColor Yellow
$switchScript = Join-Path $scriptDir "..\..\src\powershell\database\docker\Switch-DatabaseTarget.ps1"
if (Test-Path $switchScript) {
    & $switchScript -Target LOCAL
} else {
    # Fallback: create config directly
    $configDir = Join-Path $scriptDir "..\..\config"
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    $config = @{
        Target      = "LOCAL"
        TNSName     = "ORACLE_LOCAL"
        Host        = "localhost"
        Port        = 1521
        SID         = "EMS12"
        Description = "Local Docker Oracle 12c"
        SwitchedAt  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        SwitchedBy  = "$env:USERDOMAIN\$env:USERNAME"
    }
    $config | ConvertTo-Json -Depth 3 | Out-File (Join-Path $configDir "database-target.json") -Encoding UTF8
    Write-Host "  Target set to LOCAL (ORACLE_LOCAL)" -ForegroundColor Green
}

Write-Host ""

# ==========================================
# Step 6: Verification
# ==========================================
Write-Host "STEP 6: Running verification..." -ForegroundColor Yellow
& (Join-Path $scriptDir "Verify-LocalDatabase.ps1")

Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Your local Oracle 12c Tecnomatix database is ready." -ForegroundColor White
Write-Host ""
Write-Host "  Quick Reference:" -ForegroundColor Cyan
Write-Host "    Start:    .\docker\oracle\Start-OracleDocker.ps1" -ForegroundColor Gray
Write-Host "    Stop:     .\docker\oracle\Stop-OracleDocker.ps1" -ForegroundColor Gray
Write-Host "    Import:   .\docker\oracle\Import-DatabaseDump.ps1 -DumpFile 'path.dmp'" -ForegroundColor Gray
Write-Host "    Verify:   .\docker\oracle\Verify-LocalDatabase.ps1" -ForegroundColor Gray
Write-Host "    Switch:   .\src\powershell\database\docker\Switch-DatabaseTarget.ps1 -Target LOCAL|REMOTE" -ForegroundColor Gray
Write-Host ""
Write-Host "  Connect via SQL*Plus:" -ForegroundColor Cyan
Write-Host "    sqlplus sys/change_on_install@ORACLE_LOCAL as sysdba" -ForegroundColor Gray
Write-Host ""
