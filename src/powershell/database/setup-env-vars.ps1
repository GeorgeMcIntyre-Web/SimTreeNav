# Environment Variables Setup Script for Oracle Client
# Run this script to set/update Oracle environment variables

param(
    [string]$OracleHome = "C:\Oracle\instantclient_12_2",
    [string]$TnsAdmin = ""
)

$ErrorActionPreference = "Stop"

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ([string]::IsNullOrEmpty($TnsAdmin)) {
    $TnsAdmin = Join-Path $OracleHome "network\admin"
}

Write-Host "Setting Oracle Environment Variables..." -ForegroundColor Cyan
Write-Host ""

# Verify Oracle Home exists
if (-not (Test-Path $OracleHome)) {
    Write-Host "ERROR: Oracle Home directory not found: $OracleHome" -ForegroundColor Red
    Write-Host "Please run install-oracle-client.ps1 first or specify correct path." -ForegroundColor Yellow
    exit 1
}

# Set ORACLE_HOME
Write-Host "Setting ORACLE_HOME = $OracleHome" -ForegroundColor Green
[Environment]::SetEnvironmentVariable("ORACLE_HOME", $OracleHome, "Process")
[Environment]::SetEnvironmentVariable("ORACLE_HOME", $OracleHome, "User")
if ($isAdmin) {
    [Environment]::SetEnvironmentVariable("ORACLE_HOME", $OracleHome, "Machine")
}

# Set TNS_ADMIN
if (Test-Path $TnsAdmin) {
    Write-Host "Setting TNS_ADMIN = $TnsAdmin" -ForegroundColor Green
    [Environment]::SetEnvironmentVariable("TNS_ADMIN", $TnsAdmin, "Process")
    [Environment]::SetEnvironmentVariable("TNS_ADMIN", $TnsAdmin, "User")
    if ($isAdmin) {
        [Environment]::SetEnvironmentVariable("TNS_ADMIN", $TnsAdmin, "Machine")
    }
} else {
    Write-Host "WARNING: TNS_ADMIN directory not found: $TnsAdmin" -ForegroundColor Yellow
    Write-Host "Creating directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $TnsAdmin | Out-Null
    [Environment]::SetEnvironmentVariable("TNS_ADMIN", $TnsAdmin, "Process")
    [Environment]::SetEnvironmentVariable("TNS_ADMIN", $TnsAdmin, "User")
    if ($isAdmin) {
        [Environment]::SetEnvironmentVariable("TNS_ADMIN", $TnsAdmin, "Machine")
    }
}

# Add Oracle bin to PATH
$binPath = Join-Path $OracleHome "bin"
if (Test-Path $binPath) {
    Write-Host "Adding $binPath to PATH" -ForegroundColor Green
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$binPath*") {
        $newPath = "$currentPath;$binPath"
        [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
        Write-Host "  Added to User PATH" -ForegroundColor Gray
    } else {
        Write-Host "  Already in User PATH" -ForegroundColor Gray
    }
    
    if ($isAdmin) {
        $currentPathMachine = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPathMachine -notlike "*$binPath*") {
            $newPathMachine = "$currentPathMachine;$binPath"
            [Environment]::SetEnvironmentVariable("PATH", $newPathMachine, "Machine")
            Write-Host "  Added to System PATH" -ForegroundColor Gray
        } else {
            Write-Host "  Already in System PATH" -ForegroundColor Gray
        }
    }
    
    # Update current session
    if ($env:PATH -notlike "*$binPath*") {
        $env:PATH = "$env:PATH;$binPath"
    }
} else {
    Write-Host "WARNING: Oracle bin directory not found: $binPath" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Environment variables set successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "Current values:" -ForegroundColor Cyan
Write-Host "  ORACLE_HOME = $([Environment]::GetEnvironmentVariable('ORACLE_HOME', 'User'))" -ForegroundColor White
Write-Host "  TNS_ADMIN = $([Environment]::GetEnvironmentVariable('TNS_ADMIN', 'User'))" -ForegroundColor White
Write-Host ""
Write-Host "NOTE: You may need to restart your terminal for changes to take effect." -ForegroundColor Yellow
Write-Host ""
