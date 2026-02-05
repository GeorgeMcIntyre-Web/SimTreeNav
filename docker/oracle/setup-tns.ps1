# setup-tns.ps1
# Configure TNS for local Oracle database

param(
    [string]$TNSAdminPath = ""
)

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  TNS Configuration Setup" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check if TNS_ADMIN is already set
if ([string]::IsNullOrEmpty($TNSAdminPath)) {
    if ($env:TNS_ADMIN) {
        $TNSAdminPath = $env:TNS_ADMIN
        Write-Host "Using existing TNS_ADMIN: $TNSAdminPath" -ForegroundColor Green
    } else {
        # Common Oracle client locations
        $commonPaths = @(
            "C:\Oracle\instantclient_12_2\network\admin",
            "C:\Oracle\instantclient_19_9\network\admin",
            "C:\app\oracle\product\12.1.0\client_1\network\admin",
            "F:\Oracle\WINDOWS.X64_193000_db_home\network\admin"
        )

        Write-Host "Searching for Oracle client..." -ForegroundColor Yellow
        foreach ($path in $commonPaths) {
            if (Test-Path (Split-Path $path -Parent)) {
                $TNSAdminPath = $path
                Write-Host "  Found: $TNSAdminPath" -ForegroundColor Green
                break
            }
        }

        if ([string]::IsNullOrEmpty($TNSAdminPath)) {
            # Use the 19c installation we just set up
            $TNSAdminPath = "F:\Oracle\WINDOWS.X64_193000_db_home\network\admin"
            Write-Host "  Using Oracle 19c installation: $TNSAdminPath" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "TNS Admin Directory: $TNSAdminPath" -ForegroundColor Cyan

# Create directory if it doesn't exist
if (-not (Test-Path $TNSAdminPath)) {
    Write-Host "Creating TNS Admin directory..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $TNSAdminPath -Force | Out-Null
    Write-Host "  Created: $TNSAdminPath" -ForegroundColor Green
}

# Copy tnsnames.ora from template
$templatePath = Join-Path $PSScriptRoot "..\..\config\tnsnames.ora.template"
$tnsPath = Join-Path $TNSAdminPath "tnsnames.ora"

Write-Host ""
Write-Host "Copying tnsnames.ora configuration..." -ForegroundColor Yellow

if (Test-Path $tnsPath) {
    # Backup existing file
    $backupPath = "$tnsPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $tnsPath $backupPath
    Write-Host "  Backed up existing file to: $backupPath" -ForegroundColor Gray
}

Copy-Item $templatePath $tnsPath -Force
Write-Host "  Created: $tnsPath" -ForegroundColor Green

# Set TNS_ADMIN environment variable for current session
$env:TNS_ADMIN = $TNSAdminPath
Write-Host ""
Write-Host "Set TNS_ADMIN for current session: $TNSAdminPath" -ForegroundColor Green

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  TNS Configuration Complete!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Testing connection..." -ForegroundColor Yellow
Write-Host ""

# Test connection
try {
    $testResult = & tnsping ORACLE_LOCAL 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  TNS connection test successful!" -ForegroundColor Green
    } else {
        Write-Host "  TNS ping failed, but configuration is in place" -ForegroundColor Yellow
    }
} catch {
    Write-Host "  tnsping not available, but configuration is complete" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "You can now connect with:" -ForegroundColor Cyan
Write-Host "  sqlplus EMP_ADMIN/EMP_ADMIN@ORACLE_LOCAL" -ForegroundColor White
Write-Host "  sqlplus sys/change_on_install@ORACLE_LOCAL as sysdba" -ForegroundColor White
Write-Host ""
Write-Host "NOTE: If connection still fails, restart PowerShell to pick up TNS_ADMIN" -ForegroundColor Yellow
Write-Host ""
