# Setup-NativeOracle.ps1
# Sets up existing Oracle 19c installation at F:\Oracle for Tecnomatix development
#
# Usage:
#   .\Setup-NativeOracle.ps1                    # Check status and guide setup
#   .\Setup-NativeOracle.ps1 -SetEnvironment    # Set ORACLE_HOME and PATH
#   .\Setup-NativeOracle.ps1 -CreateDatabase    # Launch DBCA to create database

param(
    [switch]$SetEnvironment,
    [switch]$CreateDatabase,
    [switch]$CheckOnly
)

$ErrorActionPreference = "Stop"
$OracleHome = "F:\Oracle\WINDOWS.X64_193000_db_home"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Oracle 19c Native Setup - Tecnomatix" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Check Oracle Installation
Write-Host "Checking Oracle installation..." -ForegroundColor Yellow

if (-not (Test-Path $OracleHome)) {
    Write-Host "ERROR: Oracle not found at $OracleHome" -ForegroundColor Red
    exit 1
}

Write-Host "  Oracle Home: $OracleHome" -ForegroundColor Green

# Step 2: Check Environment Variables
Write-Host ""
Write-Host "Checking environment variables..." -ForegroundColor Yellow

$envOracleHome = [System.Environment]::GetEnvironmentVariable('ORACLE_HOME', 'Machine')
$path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')

if ($envORANCLE_HOME -eq $OracleHome) {
    Write-Host "  ORACLE_HOME: Configured correctly" -ForegroundColor Green
} else {
    Write-Host "  ORACLE_HOME: NOT SET or incorrect" -ForegroundColor Red
    Write-Host "    Current: $envOracleHome" -ForegroundColor Gray
    Write-Host "    Should be: $OracleHome" -ForegroundColor Gray

    if ($SetEnvironment) {
        Write-Host "  Setting ORACLE_HOME..." -ForegroundColor Yellow
        [System.Environment]::SetEnvironmentVariable('ORACLE_HOME', $OracleHome, 'Machine')
        Write-Host "    Set to: $OracleHome" -ForegroundColor Green
    }
}

$oracleBin = "$OracleHome\bin"
if ($path -like "*$oracleBin*") {
    Write-Host "  PATH: Oracle bin is in PATH" -ForegroundColor Green
} else {
    Write-Host "  PATH: Oracle bin NOT in PATH" -ForegroundColor Red

    if ($SetEnvironment) {
        Write-Host "  Adding Oracle bin to PATH..." -ForegroundColor Yellow
        [System.Environment]::SetEnvironmentVariable('Path', "$path;$oracleBin", 'Machine')
        Write-Host "    Added: $oracleBin" -ForegroundColor Green
    }
}

if ($SetEnvironment) {
    Write-Host ""
    Write-Host "Environment variables updated!" -ForegroundColor Green
    Write-Host "IMPORTANT: Restart PowerShell for changes to take effect" -ForegroundColor Yellow
    exit 0
}

# Step 3: Check for Oracle Services
Write-Host ""
Write-Host "Checking Oracle services..." -ForegroundColor Yellow

$oracleServices = Get-Service | Where-Object {$_.Name -like "OracleService*"}

if ($oracleServices) {
    foreach ($svc in $oracleServices) {
        $statusColor = if ($svc.Status -eq "Running") { "Green" } else { "Yellow" }
        Write-Host "  $($svc.Name): $($svc.Status)" -ForegroundColor $statusColor
    }
} else {
    Write-Host "  No Oracle database services found" -ForegroundColor Red
    Write-Host "  You need to create a database instance" -ForegroundColor Yellow

    if ($CreateDatabase) {
        Write-Host ""
        Write-Host "Launching Database Configuration Assistant..." -ForegroundColor Yellow
        Start-Process "$OracleHome\bin\dbca.bat" -NoNewWindow
        exit 0
    }
}

# Step 4: Check for existing databases
Write-Host ""
Write-Host "Checking for existing databases..." -ForegroundColor Yellow

$oradataDir = "F:\Oracle\oradata"
if (Test-Path $oradataDir) {
    $databases = Get-ChildItem $oradataDir -Directory
    if ($databases) {
        foreach ($db in $databases) {
            Write-Host "  Database: $($db.Name)" -ForegroundColor Green
        }
    } else {
        Write-Host "  No databases found in $oradataDir" -ForegroundColor Yellow
    }
} else {
    Write-Host "  No oradata directory found" -ForegroundColor Yellow
}

# Step 5: Check listener
Write-Host ""
Write-Host "Checking Oracle listener..." -ForegroundColor Yellow

$listenerService = Get-Service | Where-Object {$_.Name -like "*TNSListener*"}
if ($listenerService) {
    $statusColor = if ($listenerService.Status -eq "Running") { "Green" } else { "Yellow" }
    Write-Host "  $($listenerService.Name): $($listenerService.Status)" -ForegroundColor $statusColor
} else {
    Write-Host "  No listener service found" -ForegroundColor Yellow
}

if ($CheckOnly) {
    exit 0
}

# Step 6: Next Steps
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Next Steps" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $envOracleHome -or $envOracleHome -ne $OracleHome) {
    Write-Host "1. Set environment variables:" -ForegroundColor Yellow
    Write-Host "   .\Setup-NativeOracle.ps1 -SetEnvironment" -ForegroundColor White
    Write-Host ""
}

if (-not $oracleServices) {
    Write-Host "2. Create a database:" -ForegroundColor Yellow
    Write-Host "   .\Setup-NativeOracle.ps1 -CreateDatabase" -ForegroundColor White
    Write-Host "   (or manually run: $OracleHome\bin\dbca.bat)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   Recommended settings:" -ForegroundColor Cyan
    Write-Host "     - Database Name: EMS12" -ForegroundColor White
    Write-Host "     - SID: EMS12" -ForegroundColor White
    Write-Host "     - Character Set: AL32UTF8" -ForegroundColor White
    Write-Host ""
}

if ($oracleServices -and $oracleServices[0].Status -ne "Running") {
    Write-Host "3. Start the Oracle service:" -ForegroundColor Yellow
    Write-Host "   net start $($oracleServices[0].Name)" -ForegroundColor White
    Write-Host ""
}

Write-Host "4. Create Siemens tablespaces:" -ForegroundColor Yellow
Write-Host "   sqlplus / as sysdba @scripts\setup\01-create-tablespaces.sql" -ForegroundColor White
Write-Host ""

Write-Host "5. Run Siemens after_install:" -ForegroundColor Yellow
Write-Host "   sqlplus / as sysdba @scripts\setup\02-after-install.sql" -ForegroundColor White
Write-Host ""

Write-Host "6. Import your dump file:" -ForegroundColor Yellow
Write-Host "   (See SETUP-NATIVE-ORACLE.md for details)" -ForegroundColor White
Write-Host ""

Write-Host "Full documentation: SETUP-NATIVE-ORACLE.md" -ForegroundColor Cyan
Write-Host ""
