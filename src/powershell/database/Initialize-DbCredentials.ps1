# Initialize-DbCredentials.ps1
# First-time setup and credential configuration

<#
.SYNOPSIS
    Initializes database credentials for SimTreeNav application.

.DESCRIPTION
    Interactive setup wizard that:
    1. Detects or sets environment mode (DEV/PROD)
    2. Configures database connection settings
    3. Stores credentials securely
    4. Tests the connection

.PARAMETER Mode
    Environment mode: DEV or PROD
    DEV: Encrypted file storage (no prompts during development)
    PROD: Windows Credential Manager (secure, auditable)

.PARAMETER TNSName
    The TNS name for database connection

.PARAMETER Username
    Database username (default: sys)

.PARAMETER Force
    Force reconfiguration even if credentials exist

.EXAMPLE
    .\Initialize-DbCredentials.ps1
    # Interactive mode - prompts for all settings

.EXAMPLE
    .\Initialize-DbCredentials.ps1 -Mode DEV -TNSName "SIEMENS_PS_DB" -Username sys
    # Quick setup with parameters
#>

param(
    [ValidateSet("DEV", "PROD")]
    [string]$Mode,

    [string]$TNSName,

    [string]$Username = "sys",

    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "..\utilities\CredentialManager.ps1"
Import-Module $credManagerPath -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SimTreeNav Credential Setup" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Determine environment mode
if (-not $Mode) {
    Write-Host "Select Environment Mode:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. DEV  - Development mode (encrypted file, no prompts)" -ForegroundColor White
    Write-Host "           Perfect for: Your local machine, daily development work" -ForegroundColor Gray
    Write-Host "           Credentials: Encrypted to your Windows account" -ForegroundColor Gray
    Write-Host "           Location: config/.credentials/ (gitignored)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. PROD - Production mode (Windows Credential Manager)" -ForegroundColor White
    Write-Host "           Perfect for: Shared servers, production deployments" -ForegroundColor Gray
    Write-Host "           Credentials: Stored in Windows Credential Manager" -ForegroundColor Gray
    Write-Host "           Security: Auditable, integrated with Windows" -ForegroundColor Gray
    Write-Host ""

    $modeChoice = Read-Host "Enter choice (1 or 2)"

    if ($modeChoice -eq "1") {
        $Mode = "DEV"
    } elseif ($modeChoice -eq "2") {
        $Mode = "PROD"
    } else {
        Write-Host "Error: Invalid choice. Defaulting to DEV mode." -ForegroundColor Yellow
        $Mode = "DEV"
    }
}

Write-Host ""
Write-Host "Selected Mode: $Mode" -ForegroundColor Cyan
Write-Host ""

# Step 2: Save mode to config file
$configDir = Join-Path $PSScriptRoot "..\..\..\config"
$configFile = Join-Path $configDir "credential-config.json"

$config = @{
    Mode = $Mode
    ConfiguredDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    ConfiguredBy = "$env:USERDOMAIN\$env:USERNAME"
    Machine = $env:COMPUTERNAME
}

$config | ConvertTo-Json | Out-File $configFile -Encoding UTF8 -Force

Write-Host "Success: Configuration saved" -ForegroundColor Green
Write-Host "  File: $configFile" -ForegroundColor Gray
Write-Host ""

# Step 3: Get TNS name
if (-not $TNSName) {
    Write-Host "Enter Database TNS Name:" -ForegroundColor Yellow
    Write-Host "  Examples: SIEMENS_PS_DB, ORACLE_DB, PRODUCTION_DB" -ForegroundColor Gray
    Write-Host ""
    $TNSName = Read-Host "TNS Name"

    if ([string]::IsNullOrWhiteSpace($TNSName)) {
        Write-Host "Error: TNS name is required" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "Database: $TNSName" -ForegroundColor Cyan
Write-Host ""

# Step 4: Check if credentials already exist
$existingCred = $null
if (-not $Force) {
    if ($Mode -eq "DEV") {
        $existingCred = Get-CredentialFromFile -TNSName $TNSName
    } elseif ($Mode -eq "PROD") {
        $existingCred = Get-CredentialFromManager -TNSName $TNSName
    }

    if ($existingCred) {
        Write-Host "Warning: Credentials already exist for $TNSName" -ForegroundColor Yellow
        $overwrite = Read-Host "Overwrite existing credentials? (Y/N)"

        if ($overwrite -ne "Y" -and $overwrite -ne "y") {
            Write-Host "Success: Keeping existing credentials" -ForegroundColor Green
            Write-Host ""
            Write-Host "To test credentials, run:" -ForegroundColor Yellow
            Write-Host "  .\Test-DbCredentials.ps1 -TNSName $TNSName" -ForegroundColor White
            Write-Host ""
            exit 0
        }
    }
}

# Step 5: Prompt for credentials
Write-Host "Enter Database Credentials:" -ForegroundColor Yellow
Write-Host ""

if ($Mode -eq "DEV") {
    Write-Host "These credentials will be encrypted and saved locally." -ForegroundColor Gray
    Write-Host "You won't be prompted again on this machine." -ForegroundColor Gray
} else {
    Write-Host "These credentials will be saved to Windows Credential Manager." -ForegroundColor Gray
    Write-Host "They can be viewed/managed in Windows Credential Manager." -ForegroundColor Gray
}
Write-Host ""

$credential = Get-Credential -UserName $Username -Message "Enter password for $TNSName"

if (-not $credential) {
    Write-Host "Error: No credentials provided" -ForegroundColor Red
    exit 1
}

# Step 6: Save credentials
Write-Host ""
Write-Host "Saving credentials..." -ForegroundColor Yellow

if ($Mode -eq "DEV") {
    $saved = Save-CredentialToFile -TNSName $TNSName -Credential $credential
} elseif ($Mode -eq "PROD") {
    $saved = Save-CredentialToManager -TNSName $TNSName -Credential $credential
}

if (-not $saved) {
    Write-Host "Error: Failed to save credentials" -ForegroundColor Red
    exit 1
}

# Step 7: Test connection
Write-Host ""
Write-Host "Testing database connection..." -ForegroundColor Yellow

# Create test SQL file
$testFile = "test-connection-init.sql"
$testQuery = @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SELECT 'CONNECTION_OK' FROM DUAL;
EXIT;
"@
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PWD\$testFile", $testQuery, $utf8NoBom)

# Get connection string
try {
    $connStr = Get-DbConnectionString -TNSName $TNSName -Username $credential.UserName -AsSysDBA

    # Test connection
    $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"
    $result = sqlplus -S $connStr "@$testFile" 2>&1

    Remove-Item $testFile -ErrorAction SilentlyContinue

    if ($result -match "CONNECTION_OK") {
        Write-Host "Success: Database connection successful!" -ForegroundColor Green
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  Setup Complete!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Configuration Summary:" -ForegroundColor Yellow
        Write-Host "  Mode:     $Mode" -ForegroundColor White
        Write-Host "  TNS Name: $TNSName" -ForegroundColor White
        Write-Host "  Username: $($credential.UserName)" -ForegroundColor White

        if ($Mode -eq "DEV") {
            Write-Host "  Storage:  Encrypted file (config/.credentials/)" -ForegroundColor White
        } else {
            Write-Host "  Storage:  Windows Credential Manager" -ForegroundColor White
        }

        Write-Host ""
        Write-Host "You can now use the application without entering credentials!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next Steps:" -ForegroundColor Yellow
        Write-Host "  1. Run the tree viewer:" -ForegroundColor White
        Write-Host "     .\src\powershell\main\tree-viewer-launcher.ps1" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  2. Generate a specific tree:" -ForegroundColor White
        Write-Host "     .\src\powershell\main\generate-tree-html.ps1 -TNSName $TNSName -Schema DESIGN1 -ProjectId 123 -ProjectName 'MyProject'" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  3. Update credentials:" -ForegroundColor White
        Write-Host "     .\src\powershell\database\Initialize-DbCredentials.ps1 -Force" -ForegroundColor Gray
        Write-Host ""
    } else {
        Write-Host "Error: Database connection failed!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Output:" -ForegroundColor Yellow
        $result | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "Please check:" -ForegroundColor Yellow
        Write-Host "  - TNS name is correct: $TNSName" -ForegroundColor White
        Write-Host "  - Username/password are correct" -ForegroundColor White
        Write-Host "  - Database is accessible from this machine" -ForegroundColor White
        Write-Host "  - Oracle Instant Client is installed" -ForegroundColor White
        Write-Host ""
        exit 1
    }
} catch {
    Write-Host "Error: Error testing connection: $_" -ForegroundColor Red
    Remove-Item $testFile -ErrorAction SilentlyContinue
    exit 1
}
