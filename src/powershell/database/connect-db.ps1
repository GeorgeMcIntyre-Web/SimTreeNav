# Quick connection script for Siemens Process Simulation Database
# Connects to des-sim-db1 instance db02 as SYS user

param(
    [switch]$AsSysdba = $true,
    [string]$Username = "sys",
    [string]$Password
)

$ErrorActionPreference = "Stop"

Write-Host "Connecting to Siemens Process Simulation Database..." -ForegroundColor Cyan
Write-Host "  Server: des-sim-db1" -ForegroundColor White
Write-Host "  Instance: db02" -ForegroundColor White
Write-Host "  User: $Username" -ForegroundColor White
Write-Host ""

# Prompt for password if not provided
if (-not $Password) {
    $securePassword = Read-Host "Enter password for $Username" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $Password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
}

# Check if sqlplus is available
$sqlplusPath = Get-Command sqlplus -ErrorAction SilentlyContinue
if (-not $sqlplusPath) {
    Write-Host "ERROR: sqlplus not found in PATH" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please ensure Oracle Instant Client is installed and environment variables are set." -ForegroundColor Yellow
    Write-Host "Run: .\setup-env-vars.ps1" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}

# Build connection string
if ($AsSysdba) {
    $connectionString = "$Username/$Password@SIEMENS_PS_DB AS SYSDBA"
    Write-Host "Connecting as SYSDBA..." -ForegroundColor Yellow
    Write-Host "NOTE: You are connecting as SYS user with SYSDBA privileges." -ForegroundColor Yellow
    Write-Host "      Use with caution - you have full database access." -ForegroundColor Yellow
    Write-Host ""
} else {
    $connectionString = "$Username/$Password@SIEMENS_PS_DB"
}

# Launch sqlplus
Write-Host "Launching sqlplus..." -ForegroundColor Green
Write-Host ""

& sqlplus $connectionString
