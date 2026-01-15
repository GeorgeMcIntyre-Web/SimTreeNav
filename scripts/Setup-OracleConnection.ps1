<#
.SYNOPSIS
    Sets up Oracle environment and TNS names for SimTreeNav
.DESCRIPTION
    Configures ORACLE_HOME, TNS_ADMIN, and ensures SIEMENS_PS_DB is available
#>

$OracleHome = "C:\Oracle\client\georgem\product\12.1.0\client_1"
$TnsAdmin = "$OracleHome\network\admin"
$OracleTnsFile = Join-Path $TnsAdmin "tnsnames.ora"
$TreeNavTnsFile = Join-Path $PSScriptRoot "..\..\..\TreeNav\tnsnames.ora"

Write-Host "`nOracle Connection Setup" -ForegroundColor Cyan
Write-Host "=====================`n" -ForegroundColor Cyan

# Set environment variables
if (-not $env:ORACLE_HOME) {
    [Environment]::SetEnvironmentVariable("ORACLE_HOME", $OracleHome, "User")
    [Environment]::SetEnvironmentVariable("TNS_ADMIN", $TnsAdmin, "User")
    $env:ORACLE_HOME = $OracleHome
    $env:TNS_ADMIN = $TnsAdmin
    Write-Host "Environment variables set (restart PowerShell to persist)`n" -ForegroundColor Green
}

# Check if SIEMENS_PS_DB exists
$oracleContent = Get-Content $OracleTnsFile -Raw
if ($oracleContent -notmatch "SIEMENS_PS_DB") {
    if (Test-Path $TreeNavTnsFile) {
        Write-Host "Adding SIEMENS_PS_DB to tnsnames.ora..." -ForegroundColor Yellow
        Copy-Item $OracleTnsFile "$OracleTnsFile.backup" -Force
        Add-Content $OracleTnsFile "`n# SIEMENS Process Simulation`n"
        Get-Content $TreeNavTnsFile | Add-Content $OracleTnsFile
        Write-Host "Success!`n" -ForegroundColor Green
    }
}

# Show available TNS names
Write-Host "Available TNS Names:" -ForegroundColor Cyan
Get-Content $OracleTnsFile | Select-String "^\w+\s*=" | ForEach-Object {
    Write-Host "  - $($_.Line -replace '\s*=.*')"
}

Write-Host "`nNext: .\src\powershell\database\Initialize-DbCredentials.ps1" -ForegroundColor Yellow
Write-Host "(Use TNS name: SIEMENS_PS_DB or SIEMENS_PS_DB_DB01)`n"
