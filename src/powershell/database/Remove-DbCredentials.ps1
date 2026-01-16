# Remove-DbCredentials.ps1
# Cleanup script to remove all stored credentials

<#
.SYNOPSIS
    Removes all stored database credentials.

.DESCRIPTION
    Cleans up credentials from both DEV (encrypted files) and PROD (Windows Credential Manager) modes.
    Useful for:
    - Switching between DEV/PROD modes
    - Removing credentials before sharing machine
    - Troubleshooting credential issues

.PARAMETER TNSName
    Optional: Remove credentials for specific TNS name only

.PARAMETER All
    Remove all credentials and configuration

.EXAMPLE
    .\Remove-DbCredentials.ps1
    # Interactive mode - prompts for confirmation

.EXAMPLE
    .\Remove-DbCredentials.ps1 -TNSName "SIEMENS_PS_DB"
    # Remove credentials for specific database only

.EXAMPLE
    .\Remove-DbCredentials.ps1 -All
    # Remove all credentials and configuration
#>

param(
    [string]$TNSName,
    [switch]$All
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Remove Database Credentials" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Import credential manager to detect mode
$credManagerPath = Join-Path $PSScriptRoot "..\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
}

# Get current mode
$configFile = Join-Path $PSScriptRoot "..\..\..\config\credential-config.json"
$mode = "UNKNOWN"

if (Test-Path $configFile) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        $mode = $config.Mode
    } catch {
        Write-Warning "Could not read credential-config.json"
    }
}

Write-Host "Current Mode: $mode" -ForegroundColor Cyan
Write-Host ""

if ($All) {
    # Remove everything
    Write-Host "⚠️  WARNING: This will remove ALL credentials and configuration!" -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "Are you sure? Type 'YES' to confirm"

    if ($confirm -ne "YES") {
        Write-Host "Cancelled." -ForegroundColor Gray
        exit 0
    }

    Write-Host ""
    Write-Host "Removing all credentials..." -ForegroundColor Yellow

    # Remove DEV mode credentials
    $credDir = Join-Path $PSScriptRoot "..\..\..\config\.credentials"
    if (Test-Path $credDir) {
        $fileCount = (Get-ChildItem $credDir -File).Count
        Remove-Item "$credDir\*" -Force -ErrorAction SilentlyContinue
        Write-Host "  ✓ Removed $fileCount encrypted credential files (DEV mode)" -ForegroundColor Green
    }

    # Remove PROD mode credentials (scan for all SimTreeNav_* entries)
    try {
        $cmdkeyList = cmdkey /list 2>&1
        $removed = 0

        foreach ($line in $cmdkeyList) {
            if ($line -match 'Target:\s*(SimTreeNav_\w+)') {
                $targetName = $matches[1]
                cmdkey /delete:$targetName 2>&1 | Out-Null
                Write-Host "  ✓ Removed from Windows Credential Manager: $targetName" -ForegroundColor Green
                $removed++
            }
        }

        if ($removed -eq 0) {
            Write-Host "  • No credentials found in Windows Credential Manager" -ForegroundColor Gray
        }
    } catch {
        Write-Warning "Could not scan Windows Credential Manager: $_"
    }

    # Remove configuration
    if (Test-Path $configFile) {
        Remove-Item $configFile -Force
        Write-Host "  ✓ Removed credential configuration file" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "✓ All credentials removed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "To set up credentials again, run:" -ForegroundColor Yellow
    Write-Host "  .\Initialize-DbCredentials.ps1" -ForegroundColor White
    Write-Host ""

} elseif ($TNSName) {
    # Remove specific TNS credentials
    Write-Host "Removing credentials for: $TNSName" -ForegroundColor Yellow
    Write-Host ""

    $removed = $false

    # Remove from DEV mode
    if ($mode -eq "DEV" -or $mode -eq "UNKNOWN") {
        $credFile = Join-Path $PSScriptRoot "..\..\..\config\.credentials" "${env:COMPUTERNAME}_${env:USERNAME}_${TNSName}.xml"
        if (Test-Path $credFile) {
            Remove-Item $credFile -Force
            Write-Host "  ✓ Removed encrypted credential file (DEV mode)" -ForegroundColor Green
            $removed = $true
        }
    }

    # Remove from PROD mode
    if ($mode -eq "PROD" -or $mode -eq "UNKNOWN") {
        $targetName = "SimTreeNav_$TNSName"
        try {
            $cmdkeyList = cmdkey /list 2>&1
            if ($cmdkeyList -match $targetName) {
                cmdkey /delete:$targetName 2>&1 | Out-Null
                Write-Host "  ✓ Removed from Windows Credential Manager: $targetName" -ForegroundColor Green
                $removed = $true
            }
        } catch {
            Write-Warning "Could not access Windows Credential Manager: $_"
        }
    }

    if ($removed) {
        Write-Host ""
        Write-Host "✓ Credentials for $TNSName removed!" -ForegroundColor Green
    } else {
        Write-Host "  • No credentials found for $TNSName" -ForegroundColor Gray
    }

} else {
    # Interactive mode - show what would be removed
    Write-Host "Credentials to remove:" -ForegroundColor Yellow
    Write-Host ""

    $hasCredentials = $false

    # Check DEV mode
    $credDir = Join-Path $PSScriptRoot "..\..\..\config\.credentials"
    if (Test-Path $credDir) {
        $files = Get-ChildItem $credDir -File
        if ($files.Count -gt 0) {
            Write-Host "  DEV Mode (Encrypted Files):" -ForegroundColor White
            foreach ($file in $files) {
                Write-Host "    • $($file.Name)" -ForegroundColor Gray
                $hasCredentials = $true
            }
            Write-Host ""
        }
    }

    # Check PROD mode
    try {
        $cmdkeyList = cmdkey /list 2>&1
        $foundProd = $false

        foreach ($line in $cmdkeyList) {
            if ($line -match 'Target:\s*(SimTreeNav_\w+)') {
                if (-not $foundProd) {
                    Write-Host "  PROD Mode (Windows Credential Manager):" -ForegroundColor White
                    $foundProd = $true
                }
                Write-Host "    • $($matches[1])" -ForegroundColor Gray
                $hasCredentials = $true
            }
        }

        if ($foundProd) {
            Write-Host ""
        }
    } catch {
        # Ignore
    }

    if (-not $hasCredentials) {
        Write-Host "  • No credentials found" -ForegroundColor Gray
        Write-Host ""
        exit 0
    }

    # Ask for confirmation
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  1. Remove ALL credentials" -ForegroundColor White
    Write-Host "  2. Remove specific TNS credentials" -ForegroundColor White
    Write-Host "  3. Cancel" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "Enter choice (1-3)"

    if ($choice -eq "1") {
        # Recursively call with -All
        & $PSCommandPath -All
    } elseif ($choice -eq "2") {
        Write-Host ""
        $tnsInput = Read-Host "Enter TNS name"
        if ($tnsInput) {
            & $PSCommandPath -TNSName $tnsInput
        }
    } else {
        Write-Host "Cancelled." -ForegroundColor Gray
    }
}
