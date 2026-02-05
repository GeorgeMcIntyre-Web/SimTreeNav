# Execute-OracleSetup.ps1
# Automated Oracle 19c database creation and Siemens setup
# Database Name: localdb01

param(
    [switch]$SkipDbCreate,
    [switch]$SkipTablespaces,
    [switch]$SkipAfterInstall
)

$ErrorActionPreference = "Stop"
$OracleHome = "F:\Oracle\WINDOWS.X64_193000_db_home"
$DatabaseName = "localdb01"
$SID = "localdb01"

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Oracle 19c Automated Setup" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Database Name: $DatabaseName" -ForegroundColor White
Write-Host "  SID: $SID" -ForegroundColor White
Write-Host "  Oracle Home: $OracleHome" -ForegroundColor White
Write-Host ""

# Set environment for this session
Write-Host "Setting Oracle environment..." -ForegroundColor Yellow
$env:ORACLE_HOME = $OracleHome
$env:ORACLE_SID = $SID
$env:PATH = "$env:PATH;$OracleHome\bin"
Write-Host "  ORACLE_HOME = $env:ORACLE_HOME" -ForegroundColor Green
Write-Host "  ORACLE_SID = $env:ORACLE_SID" -ForegroundColor Green

# Check if database already exists
Write-Host ""
Write-Host "Checking for existing database..." -ForegroundColor Yellow
$oracleService = Get-Service -Name "OracleService$SID" -ErrorAction SilentlyContinue

if ($oracleService -and -not $SkipDbCreate) {
    Write-Host "  Database service already exists: $($oracleService.Name)" -ForegroundColor Green
    Write-Host "  Skipping database creation" -ForegroundColor Yellow
} elseif (-not $SkipDbCreate) {
    Write-Host "  No database service found" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Creating database using DBCA silent mode..." -ForegroundColor Yellow

    # Create response file for DBCA
    $responseFile = Join-Path $PSScriptRoot "dbca_response_$SID.rsp"

    @"
[GENERAL]
RESPONSEFILE_VERSION = "19.0.0"
OPERATION_TYPE = "createDatabase"

[CREATEDATABASE]
GDBNAME = "$DatabaseName"
SID = "$SID"
TEMPLATENAME = "General_Purpose.dbc"
SYSPASSWORD = "change_on_install"
SYSTEMPASSWORD = "manager"
CHARACTERSET = "AL32UTF8"
NATIONALCHARACTERSET= "AL16UTF16"
TOTALMEMORY = "3072"
DATABASETYPE = "MULTIPURPOSE"
AUTOMATICMEMORYMANAGEMENT = "TRUE"
STORAGETYPE = "FS"
DATAFILEDESTINATION = "F:\Oracle\oradata"
RECOVERYAREADESTINATION = "F:\Oracle\flash_recovery_area"
LISTENERS = "LISTENER"
EMCONFIGURATION = "DBEXPRESS"
EMEXPRESSPORT = "5500"
"@ | Set-Content $responseFile

    Write-Host "  Response file created: $responseFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Running DBCA (this may take 10-20 minutes)..." -ForegroundColor Yellow

    # Run DBCA in silent mode
    $dbcaPath = Join-Path $OracleHome "bin\dbca.bat"
    & $dbcaPath -silent -responseFile $responseFile

    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "  Database created successfully!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  ERROR: DBCA failed with exit code $LASTEXITCODE" -ForegroundColor Red
        Write-Host "  Check logs at: F:\Oracle\cfgtoollogs\dbca\$DatabaseName" -ForegroundColor Yellow
        exit 1
    }
}

# Start the Oracle service
Write-Host ""
Write-Host "Starting Oracle service..." -ForegroundColor Yellow
$oracleService = Get-Service -Name "OracleService$SID" -ErrorAction SilentlyContinue
if ($oracleService) {
    if ($oracleService.Status -ne "Running") {
        Start-Service "OracleService$SID"
        Write-Host "  Service started" -ForegroundColor Green
    } else {
        Write-Host "  Service already running" -ForegroundColor Green
    }
} else {
    Write-Host "  ERROR: Service not found" -ForegroundColor Red
    exit 1
}

# Start the listener
Write-Host ""
Write-Host "Starting Oracle listener..." -ForegroundColor Yellow
try {
    & lsnrctl start
    Write-Host "  Listener started" -ForegroundColor Green
} catch {
    Write-Host "  Listener may already be running" -ForegroundColor Yellow
}

# Wait for database to be ready
Write-Host ""
Write-Host "Waiting for database to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Test connection
Write-Host ""
Write-Host "Testing database connection..." -ForegroundColor Yellow
$testSql = Join-Path $PSScriptRoot "test_connection.sql"
@"
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
SELECT instance_name, status FROM v`$instance;
EXIT;
"@ | Set-Content $testSql

try {
    $result = & sqlplus -S "sys/change_on_install@$SID as sysdba" "@$testSql"
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Connection successful!" -ForegroundColor Green
        Write-Host "  $result" -ForegroundColor Gray
    } else {
        Write-Host "  ERROR: Cannot connect to database" -ForegroundColor Red
        exit 1
    }
} finally {
    Remove-Item $testSql -ErrorAction SilentlyContinue
}

# Create Siemens tablespaces
if (-not $SkipTablespaces) {
    Write-Host ""
    Write-Host "Creating Siemens tablespaces..." -ForegroundColor Yellow

    $tablespaceScript = Join-Path $PSScriptRoot "scripts\setup\01-create-tablespaces.sql"
    if (Test-Path $tablespaceScript) {
        & sqlplus "sys/change_on_install@$SID as sysdba" `@"$tablespaceScript"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Tablespaces created successfully!" -ForegroundColor Green
        } else {
            Write-Host "  ERROR: Tablespace creation failed" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "  ERROR: Tablespace script not found: $tablespaceScript" -ForegroundColor Red
        exit 1
    }
}

# Run after_install.sql
if (-not $SkipAfterInstall) {
    Write-Host ""
    Write-Host "Running Siemens after_install..." -ForegroundColor Yellow

    $afterInstallScript = Join-Path $PSScriptRoot "scripts\setup\02-after-install.sql"
    if (Test-Path $afterInstallScript) {
        & sqlplus "sys/change_on_install@$SID as sysdba" `@"$afterInstallScript"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Roles and users created successfully!" -ForegroundColor Green
        } else {
            Write-Host "  ERROR: after_install.sql failed" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "  ERROR: after_install script not found: $afterInstallScript" -ForegroundColor Red
        exit 1
    }
}

# Summary
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Database Details:" -ForegroundColor Cyan
Write-Host "  Name: $DatabaseName" -ForegroundColor White
Write-Host "  SID: $SID" -ForegroundColor White
Write-Host "  Port: 1521" -ForegroundColor White
Write-Host "  SYS Password: change_on_install" -ForegroundColor White
Write-Host "  SYSTEM Password: manager" -ForegroundColor White
Write-Host "  EMP_ADMIN Password: EMP_ADMIN" -ForegroundColor White
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Cyan
Write-Host "  1. Update tnsnames.ora with $SID entry" -ForegroundColor White
Write-Host "  2. Import your .dmp file" -ForegroundColor White
Write-Host "  3. Run verification queries" -ForegroundColor White
Write-Host ""
Write-Host "Connect with:" -ForegroundColor Cyan
Write-Host "  sqlplus sys/change_on_install@$SID as sysdba" -ForegroundColor Gray
Write-Host "  sqlplus EMP_ADMIN/EMP_ADMIN@$SID" -ForegroundColor Gray
Write-Host ""
