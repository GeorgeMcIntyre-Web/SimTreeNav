<#
.SYNOPSIS
    Interactive wizard to set up a SimTreeNav PC Profile.

.DESCRIPTION
    Walks the user through creating a PC profile and adding server configurations.
    Generates the config/pc-profiles.json file automatically.

.EXAMPLE
    .\setup-pc-profile.ps1
#>

$ErrorActionPreference = "Stop"

# Import PCProfileManager
$utilsPath = Join-Path $PSScriptRoot "..\src\powershell\utilities"
$pcmModule = Join-Path $utilsPath "PCProfileManager.ps1"

if (-not (Test-Path $pcmModule)) {
    Write-Error "Could not find PCProfileManager module at $pcmModule"
    exit 1
}

Import-Module $pcmModule -Force

Clear-Host
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "      SimTreeNav PC Profile Setup Wizard" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This wizard will help you create a configuration file for your database connections."
Write-Host "You will need: Server Name, Oracle TNS Name, and Service Name."
Write-Host ""

# 1. Profile Creation
Write-Host "[1] Create Profile" -ForegroundColor Yellow
$defaultName = "My Work PC"
$profileName = Read-Host "Enter Profile Name (Press Enter for '$defaultName')"
if ([string]::IsNullOrWhiteSpace($profileName)) { $profileName = $defaultName }

$desc = Read-Host "Enter Description (Optional)"

Write-Host "Creating profile '$profileName'..." -ForegroundColor DarkGray
Add-PCProfile -Name $profileName -Description $desc -SetAsDefault -ErrorAction SilentlyContinue | Out-Null
Write-Host "  [OK] Profile created" -ForegroundColor Green
Write-Host ""

# 2. Server Configuration
Write-Host "[2] Add Database Servers" -ForegroundColor Yellow

do {
    Write-Host "--------------------" -ForegroundColor Gray
    $serverName = Read-Host "Server Friendly Name (e.g. 'Production', 'Test')"
    if ([string]::IsNullOrWhiteSpace($serverName)) {
        Write-Warning "Server name cannot be empty."
        continue
    }

    $tnsName = Read-Host "Oracle TNS Name (from tnsnames.ora, e.g. 'SIM_PROD')"
    if ([string]::IsNullOrWhiteSpace($tnsName)) {
        Write-Warning "TNS Name cannot be empty."
        continue
    }

    $serviceName = Read-Host "Service Name (e.g. 'sim_prod.corp.example.com')"
    
    # Construct instance object
    # For simplicity, we create one instance per server with the same name as the server tag in this wizard
    # Users can edit JSON later for complex multi-instance setups
    $instanceName = $serverName.ToUpper().Replace(" ", "_")
    
    $instances = @(
        @{
            name = $instanceName
            tnsName = $tnsName
            service = $serviceName
        }
    )

    Write-Host "Adding server '$serverName'..." -ForegroundColor DarkGray
    Add-ServerToProfile -ProfileName $profileName -ServerName $serverName -Instances $instances -DefaultInstance $instanceName | Out-Null
    Write-Host "  [OK] Server added" -ForegroundColor Green
    
    Write-Host ""
    $more = Read-Host "Add another server? (Y/N)"
} while ($more -eq "Y" -or $more -eq "y")

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Your configuration has been saved to config/pc-profiles.json"
Write-Host ""
Write-Host "Current Configuration:" -ForegroundColor Green

Get-PCProfiles | Select-Object Name, Hostname, IsDefault, @{Name="Servers"; Expression={$_.servers.name -join ", "}} | Format-Table -AutoSize
