# Initialize-PCProfile.ps1
# Interactive wizard to create and configure PC profiles

<#
.SYNOPSIS
    Creates and configures a PC profile for database server access.

.DESCRIPTION
    Interactive wizard that:
    1. Detects current PC
    2. Prompts for profile name and description
    3. Configures database servers and instances
    4. Sets as default (optional)

.PARAMETER ProfileName
    Optional: Profile name (prompted if not provided)

.PARAMETER SetAsDefault
    Set this profile as the default

.EXAMPLE
    .\Initialize-PCProfile.ps1
    # Interactive mode

.EXAMPLE
    .\Initialize-PCProfile.ps1 -ProfileName "My Dev PC" -SetAsDefault
    # Quick setup with defaults
#>

param(
    [string]$ProfileName,
    [switch]$SetAsDefault
)

$ErrorActionPreference = "Stop"

# Import PC Profile Manager
$profileManagerPath = Join-Path $PSScriptRoot "..\utilities\PCProfileManager.ps1"
if (-not (Test-Path $profileManagerPath)) {
    Write-Host "Error: PCProfileManager.ps1 not found!" -ForegroundColor Red
    Write-Host "  Expected: $profileManagerPath" -ForegroundColor Gray
    exit 1
}

Import-Module $profileManagerPath -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PC Profile Setup Wizard" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Detect current PC
$currentPC = $env:COMPUTERNAME
$currentUser = $env:USERNAME
$currentDomain = $env:USERDOMAIN

Write-Host "Detected PC Information:" -ForegroundColor Yellow
Write-Host "  Computer: $currentPC" -ForegroundColor Cyan
Write-Host "  User:     $currentDomain\$currentUser" -ForegroundColor Cyan
Write-Host ""

# Step 2: Check for existing profiles
$existingProfiles = Get-PCProfiles

if ($existingProfiles.Count -gt 0) {
    Write-Host "Existing Profiles:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $existingProfiles.Count; $i++) {
        $profile = $existingProfiles[$i]
        $defaultMark = if ($profile.isDefault) { " (default)" } else { "" }
        Write-Host "  $($i + 1). $($profile.name)$defaultMark - $($profile.hostname)" -ForegroundColor White
    }
    Write-Host ""

    $createNew = Read-Host "Create new profile? (Y/N)"
    if ($createNew -ne "Y" -and $createNew -ne "y") {
        Write-Host "Setup cancelled." -ForegroundColor Gray
        exit 0
    }
    Write-Host ""
}

# Step 3: Get profile name
if (-not $ProfileName) {
    Write-Host "Enter Profile Information:" -ForegroundColor Yellow
    Write-Host "  Suggested names:" -ForegroundColor Gray
    Write-Host "    - My Dev PC" -ForegroundColor Gray
    Write-Host "    - $currentPC" -ForegroundColor Gray
    Write-Host "    - George's Workstation" -ForegroundColor Gray
    Write-Host ""

    $ProfileName = Read-Host "Profile Name"

    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        $ProfileName = "$currentUser's PC"
        Write-Host "  Using default name: $ProfileName" -ForegroundColor Gray
    }
}

# Step 4: Get description
Write-Host ""
$description = Read-Host "Description (optional, press Enter to skip)"

if ([string]::IsNullOrWhiteSpace($description)) {
    if ($currentPC -match "DESKTOP|LAPTOP") {
        $description = "Personal development machine"
    } elseif ($currentPC -match "SERVER|SRV") {
        $description = "Database server"
    } else {
        $description = "Workstation for $currentUser"
    }
    Write-Host "  Using default: $description" -ForegroundColor Gray
}

# Step 5: Set as default?
if (-not $SetAsDefault) {
    Write-Host ""
    if ($existingProfiles.Count -eq 0) {
        Write-Host "This will be your first profile (set as default automatically)" -ForegroundColor Yellow
        $SetAsDefault = $true
    } else {
        $setDefaultInput = Read-Host "Set as default profile? (Y/N)"
        $SetAsDefault = ($setDefaultInput -eq "Y" -or $setDefaultInput -eq "y")
    }
}

# Step 6: Create profile
Write-Host ""
Write-Host "Creating profile..." -ForegroundColor Yellow

$created = Add-PCProfile -Name $ProfileName -Hostname $currentPC -Description $description -SetAsDefault:$SetAsDefault

if (-not $created) {
    Write-Host "Error: Failed to create profile" -ForegroundColor Red
    exit 1
}

# Step 7: Configure database servers
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Configure Database Servers" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$addServers = $true

while ($addServers) {
    Write-Host "Add Database Server:" -ForegroundColor Yellow
    Write-Host "  Examples:" -ForegroundColor Gray
    Write-Host "    - des-sim-db1" -ForegroundColor Gray
    Write-Host "    - localhost (if running on database server)" -ForegroundColor Gray
    Write-Host "    - sim-db2" -ForegroundColor Gray
    Write-Host ""

    $serverName = Read-Host "Server hostname (or Enter to skip)"

    if ([string]::IsNullOrWhiteSpace($serverName)) {
        Write-Host "  Skipping server configuration" -ForegroundColor Gray
        break
    }

    # Configure instances for this server
    Write-Host ""
    Write-Host "Configure instances for $serverName" -ForegroundColor Yellow
    Write-Host "  Common instances: db01, db02, orcl, XE" -ForegroundColor Gray
    Write-Host ""

    $instances = @()
    $addInstances = $true

    while ($addInstances) {
        $instanceName = Read-Host "Instance name (or Enter when done)"

        if ([string]::IsNullOrWhiteSpace($instanceName)) {
            if ($instances.Count -eq 0) {
                # Default instances
                Write-Host "  Adding default instances: db01, db02" -ForegroundColor Gray
                $instances += @{
                    name = "db01"
                    tnsName = "SIEMENS_PS_DB_DB01"
                    service = "db01"
                }
                $instances += @{
                    name = "db02"
                    tnsName = "SIEMENS_PS_DB"
                    service = "db02"
                }
            }
            break
        }

        # Get TNS name for this instance
        Write-Host "  TNS name for $instanceName" -ForegroundColor Gray
        Write-Host "    Suggested: SIEMENS_PS_DB (for db02) or SIEMENS_PS_DB_DB01 (for db01)" -ForegroundColor Gray

        $tnsName = Read-Host "  TNS Name"

        if ([string]::IsNullOrWhiteSpace($tnsName)) {
            if ($instanceName -eq "db01") {
                $tnsName = "SIEMENS_PS_DB_DB01"
            } else {
                $tnsName = "SIEMENS_PS_DB"
            }
            Write-Host "  Using default: $tnsName" -ForegroundColor Gray
        }

        # Add instance
        $instances += @{
            name = $instanceName
            tnsName = $tnsName
            service = $instanceName
        }

        Write-Host "  Success: Instance '$instanceName' added" -ForegroundColor Green
        Write-Host ""
    }

    # Set default instance
    $defaultInstance = $instances[0].name
    if ($instances.Count -gt 1) {
        Write-Host ""
        Write-Host "Select default instance:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $instances.Count; $i++) {
            Write-Host "  $($i + 1). $($instances[$i].name)" -ForegroundColor White
        }

        $defaultChoice = Read-Host "Choice (or Enter for first)"

        if ($defaultChoice -and $defaultChoice -match '^\d+$') {
            $index = [int]$defaultChoice - 1
            if ($index -ge 0 -and $index -lt $instances.Count) {
                $defaultInstance = $instances[$index].name
            }
        }
    }

    # Add server to profile
    $serverAdded = Add-ServerToProfile -ProfileName $ProfileName -ServerName $serverName -Instances $instances -DefaultInstance $defaultInstance

    if ($serverAdded) {
        Write-Host "Success: Server '$serverName' configured successfully" -ForegroundColor Green
    }

    # Ask if user wants to add more servers
    Write-Host ""
    $addMore = Read-Host "Add another server? (Y/N)"
    $addServers = ($addMore -eq "Y" -or $addMore -eq "y")
    Write-Host ""
}

# Step 8: Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Profile Created Successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Profile Summary:" -ForegroundColor Yellow
Write-Host "  Name:        $ProfileName" -ForegroundColor White
Write-Host "  Hostname:    $currentPC" -ForegroundColor White
Write-Host "  Description: $description" -ForegroundColor White
Write-Host "  Default:     $SetAsDefault" -ForegroundColor White

$profile = Get-PCProfile -Name $ProfileName
if ($profile.servers) {
    Write-Host "  Servers:     $($profile.servers.Count) configured" -ForegroundColor White
    foreach ($server in $profile.servers) {
        Write-Host "    - $($server.name) ($($server.instances.Count) instances)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Next Steps" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "1. Configure database credentials:" -ForegroundColor White
Write-Host "   .\Initialize-DbCredentials.ps1" -ForegroundColor Gray
Write-Host ""

Write-Host "2. Run tree viewer:" -ForegroundColor White
Write-Host "   .\tree-viewer-launcher.ps1" -ForegroundColor Gray
Write-Host "   (Will use your new profile automatically!)" -ForegroundColor Gray
Write-Host ""

Write-Host "3. View all profiles:" -ForegroundColor White
Write-Host "   Import-Module .\src\powershell\utilities\PCProfileManager.ps1" -ForegroundColor Gray
Write-Host "   Show-PCProfiles" -ForegroundColor Gray
Write-Host ""

# Ask if user wants to configure credentials now
$configureCreds = Read-Host "Configure database credentials now? (Y/N)"

if ($configureCreds -eq "Y" -or $configureCreds -eq "y") {
    Write-Host ""
    Write-Host "Launching credential setup..." -ForegroundColor Yellow
    Write-Host ""

    $credScript = Join-Path $PSScriptRoot "Initialize-DbCredentials.ps1"
    if (Test-Path $credScript) {
        & $credScript
    } else {
        Write-Warning "Initialize-DbCredentials.ps1 not found at: $credScript"
    }
}

Write-Host ""
Write-Host "Success: PC Profile setup complete!" -ForegroundColor Green
Write-Host ""
