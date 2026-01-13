# Oracle Database Connection Test Script
# Tests connectivity to Oracle 12c database

param(
    [string]$TnsName = "SIEMENS_PS_DB",
    [string]$Username = "sys",
    [string]$Password = "change_on_install",
    [string]$Host = "",
    [int]$Port = 1521,
    [string]$ServiceName = "",
    [switch]$AsSysdba = $true
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Oracle Database Connection Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if sqlplus is available
$sqlplusPath = Get-Command sqlplus -ErrorAction SilentlyContinue
if (-not $sqlplusPath) {
    Write-Host "ERROR: sqlplus not found in PATH" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please ensure:" -ForegroundColor Yellow
    Write-Host "1. Oracle Instant Client is installed" -ForegroundColor White
    Write-Host "2. Environment variables are set (run setup-env-vars.ps1)" -ForegroundColor White
    Write-Host "3. Your terminal/PowerShell has been restarted" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "Found sqlplus at: $($sqlplusPath.Source)" -ForegroundColor Green
Write-Host "Version:" -ForegroundColor Cyan
& sqlplus -V
Write-Host ""

# Check environment variables
Write-Host "Environment Variables:" -ForegroundColor Cyan
$oracleHome = [Environment]::GetEnvironmentVariable("ORACLE_HOME", "User")
$tnsAdmin = [Environment]::GetEnvironmentVariable("TNS_ADMIN", "User")
Write-Host "  ORACLE_HOME = $oracleHome" -ForegroundColor White
Write-Host "  TNS_ADMIN = $tnsAdmin" -ForegroundColor White
Write-Host ""

# Check for tnsnames.ora
if ($tnsAdmin -and (Test-Path $tnsAdmin)) {
    $tnsFile = Join-Path $tnsAdmin "tnsnames.ora"
    if (Test-Path $tnsFile) {
        Write-Host "Found tnsnames.ora at: $tnsFile" -ForegroundColor Green
    } else {
        Write-Host "WARNING: tnsnames.ora not found at: $tnsFile" -ForegroundColor Yellow
        Write-Host "  You can use direct connection string instead" -ForegroundColor Yellow
    }
} else {
    Write-Host "WARNING: TNS_ADMIN not set or directory doesn't exist" -ForegroundColor Yellow
}
Write-Host ""

# Build connection string
$connectionString = ""

if ($TnsName) {
    # Use TNS name
    Write-Host "Using TNS name: $TnsName" -ForegroundColor Cyan
    if (-not $Username -or -not $Password) {
        Write-Host "ERROR: Username and Password required when using TNS name" -ForegroundColor Red
        Write-Host "Usage: .\test-connection.ps1 -TnsName SIEMENS_PS_DB -Username user -Password pass" -ForegroundColor Yellow
        exit 1
    }
    if ($AsSysdba) {
        $connectionString = "$Username/$Password@$TnsName AS SYSDBA"
    } else {
        $connectionString = "$Username/$Password@$TnsName"
    }
} elseif ($Host -and $ServiceName -and $Username -and $Password) {
    # Use direct connection string
    Write-Host "Using direct connection:" -ForegroundColor Cyan
    Write-Host "  Host: $Host" -ForegroundColor White
    Write-Host "  Port: $Port" -ForegroundColor White
    Write-Host "  Service Name: $ServiceName" -ForegroundColor White
    $connectionString = "$Username/$Password@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$Host)(PORT=$Port))(CONNECT_DATA=(SERVICE_NAME=$ServiceName)))"
} else {
    Write-Host "ERROR: Insufficient connection parameters" -ForegroundColor Red
    Write-Host ""
    Write-Host "Usage examples:" -ForegroundColor Yellow
    Write-Host "  Using TNS name:" -ForegroundColor White
    Write-Host "    .\test-connection.ps1 -TnsName SIEMENS_PS_DB -Username user -Password pass" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Using direct connection:" -ForegroundColor White
    Write-Host "    .\test-connection.ps1 -Host dbhost -Port 1521 -ServiceName ORCL -Username user -Password pass" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "Testing connection..." -ForegroundColor Green
Write-Host ""

# Create a test SQL script
$testScript = @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SELECT 'Connection successful!' AS STATUS FROM DUAL;
SELECT 'Database Version: ' || BANNER FROM V\$VERSION WHERE ROWNUM = 1;
SELECT 'Current User: ' || USER FROM DUAL;
SELECT 'Current Schema: ' || SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') FROM DUAL;
EXIT;
"@

$scriptFile = Join-Path $env:TEMP "oracle_test_connection.sql"
$testScript | Out-File -FilePath $scriptFile -Encoding ASCII

try {
    # Run sqlplus with the test script
    $result = & sqlplus -S $connectionString "@$scriptFile" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "Connection Successful!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green
        Write-Host ""
        $result | ForEach-Object { Write-Host $_ -ForegroundColor White }
        Write-Host ""
    } else {
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Connection Failed!" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host ""
        $result | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host ""
        Write-Host "Error Code: $LASTEXITCODE" -ForegroundColor Red
        Write-Host ""
        Write-Host "Common issues:" -ForegroundColor Yellow
        Write-Host "  - Incorrect username/password" -ForegroundColor White
        Write-Host "  - Database host unreachable" -ForegroundColor White
        Write-Host "  - Wrong service name or SID" -ForegroundColor White
        Write-Host "  - Firewall blocking port $Port" -ForegroundColor White
        Write-Host "  - TNS configuration error" -ForegroundColor White
        Write-Host ""
    }
} catch {
    Write-Host "ERROR: Failed to execute sqlplus" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
} finally {
    # Clean up
    if (Test-Path $scriptFile) {
        Remove-Item $scriptFile -Force
    }
}

Write-Host ""
