# PCProfileManager.ps1
# Manages PC profiles for database server configurations
# Provides fast, user-friendly server/instance selection

<#
.SYNOPSIS
    Manages PC profiles with server/instance configurations.

.DESCRIPTION
    PC profiles allow users to save their frequently used database configurations
    per machine, providing:
    - Instant profile selection (no AD/DNS discovery)
    - Default profile support (one-click workflow)
    - Cascading server → instance → schema selection
    - Last-used settings memory

.EXAMPLE
    # Get all profiles
    $profiles = Get-PCProfiles

    # Get default profile
    $default = Get-DefaultPCProfile

    # Add new profile
    Add-PCProfile -Name "My Dev PC" -SetAsDefault
#>

# Profile configuration file path
$script:ProfileConfigPath = Join-Path $PSScriptRoot "..\..\..\config\pc-profiles.json"

# ============================================================================
# Core Profile Functions
# ============================================================================

function Get-PCProfiles {
    <#
    .SYNOPSIS
        Gets all PC profiles.
    .OUTPUTS
        Array of profile objects
    #>

    if (-not (Test-Path $script:ProfileConfigPath)) {
        # Return empty array if no config exists
        return @()
    }

    try {
        $config = Get-Content $script:ProfileConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        return $config.profiles
    } catch {
        Write-Warning "Failed to load PC profiles: $_"
        return @()
    }
}

function Get-DefaultPCProfile {
    <#
    .SYNOPSIS
        Gets the default PC profile.
    .OUTPUTS
        Default profile object or $null
    #>

    $profiles = Get-PCProfiles

    # First, try to get profile marked as default
    $default = $profiles | Where-Object { $_.isDefault -eq $true } | Select-Object -First 1

    if ($default) {
        return $default
    }

    # Fallback: Get profile matching current PC
    $currentPC = $env:COMPUTERNAME
    $currentProfile = $profiles | Where-Object { $_.hostname -eq $currentPC } | Select-Object -First 1

    if ($currentProfile) {
        return $currentProfile
    }

    # Last resort: Return first profile
    if ($profiles.Count -gt 0) {
        return $profiles[0]
    }

    return $null
}

function Get-PCProfile {
    <#
    .SYNOPSIS
        Gets a specific PC profile by name.
    .PARAMETER Name
        Profile name
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    $profiles = Get-PCProfiles
    return $profiles | Where-Object { $_.name -eq $Name } | Select-Object -First 1
}

function Add-PCProfile {
    <#
    .SYNOPSIS
        Adds a new PC profile.
    .PARAMETER Name
        Profile name
    .PARAMETER Hostname
        PC hostname (default: current PC)
    .PARAMETER Description
        Profile description
    .PARAMETER SetAsDefault
        Set this profile as default
    .EXAMPLE
        Add-PCProfile -Name "My Dev PC" -Description "George's development machine" -SetAsDefault
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [string]$Hostname = $env:COMPUTERNAME,

        [string]$Description = "",

        [switch]$SetAsDefault
    )

    # Load existing config or create new
    $config = @{
        profiles = @()
        currentProfile = $Name
    }

    if (Test-Path $script:ProfileConfigPath) {
        try {
            $existingConfig = Get-Content $script:ProfileConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $config.profiles = @($existingConfig.profiles)
            $config.currentProfile = $existingConfig.currentProfile
        } catch {
            Write-Warning "Could not load existing profiles, creating new config"
        }
    }

    # Check if profile already exists
    $existing = $config.profiles | Where-Object { $_.name -eq $Name }
    if ($existing) {
        Write-Warning "Profile '$Name' already exists. Use Update-PCProfile to modify."
        return $false
    }

    # Clear existing default if setting new default
    if ($SetAsDefault) {
        foreach ($profile in $config.profiles) {
            $profile.isDefault = $false
        }
    }

    # Create new profile
    $newProfile = [PSCustomObject]@{
        name = $Name
        hostname = $Hostname
        description = $Description
        isDefault = $SetAsDefault.IsPresent
        servers = @()
        lastUsed = $null
        createdDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        updatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }

    # Add to config
    $config.profiles += $newProfile

    # Save
    Save-PCProfileConfig -Config $config

    Write-Host "Profile '$Name' created successfully" -ForegroundColor Green
    return $true
}

function Update-PCProfile {
    <#
    .SYNOPSIS
        Updates an existing PC profile.
    .PARAMETER Name
        Profile name to update
    .PARAMETER NewName
        New profile name (optional)
    .PARAMETER Description
        New description (optional)
    .PARAMETER SetAsDefault
        Set as default profile
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [string]$NewName,

        [string]$Description,

        [switch]$SetAsDefault
    )

    $config = Load-PCProfileConfig

    $profile = $config.profiles | Where-Object { $_.name -eq $Name }
    if (-not $profile) {
        Write-Warning "Profile '$Name' not found"
        return $false
    }

    # Update fields
    if ($NewName) {
        $profile.name = $NewName
    }

    if ($Description) {
        $profile.description = $Description
    }

    if ($SetAsDefault) {
        # Clear all defaults first
        foreach ($p in $config.profiles) {
            $p.isDefault = $false
        }
        $profile.isDefault = $true
        $config.currentProfile = if ($NewName) { $NewName } else { $Name }
    }

    $profile.updatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Save-PCProfileConfig -Config $config

    Write-Host "Profile updated successfully" -ForegroundColor Green
    return $true
}

function Remove-PCProfile {
    <#
    .SYNOPSIS
        Removes a PC profile.
    .PARAMETER Name
        Profile name to remove
    .PARAMETER Force
        Skip confirmation prompt
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [switch]$Force
    )

    if (-not $Force) {
        $confirm = Read-Host "Remove profile '$Name'? (Y/N)"
        if ($confirm -ne "Y" -and $confirm -ne "y") {
            Write-Host "Cancelled" -ForegroundColor Gray
            return $false
        }
    }

    $config = Load-PCProfileConfig

    $profile = $config.profiles | Where-Object { $_.name -eq $Name }
    if (-not $profile) {
        Write-Warning "Profile '$Name' not found"
        return $false
    }

    # Remove profile
    $config.profiles = @($config.profiles | Where-Object { $_.name -ne $Name })

    # If this was default, set first profile as new default
    if ($profile.isDefault -and $config.profiles.Count -gt 0) {
        $config.profiles[0].isDefault = $true
        $config.currentProfile = $config.profiles[0].name
    }

    Save-PCProfileConfig -Config $config

    Write-Host "Profile '$Name' removed" -ForegroundColor Green
    return $true
}

function Set-DefaultPCProfile {
    <#
    .SYNOPSIS
        Sets a profile as the default.
    .PARAMETER Name
        Profile name
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    return Update-PCProfile -Name $Name -SetAsDefault
}

# ============================================================================
# Server Management Functions
# ============================================================================

function Add-ServerToProfile {
    <#
    .SYNOPSIS
        Adds a database server to a profile.
    .PARAMETER ProfileName
        Profile name
    .PARAMETER ServerName
        Database server name
    .PARAMETER Instances
        Array of instance configurations
    .PARAMETER DefaultInstance
        Default instance name
    .EXAMPLE
        $instances = @(
            @{name="db01"; tnsName="SIEMENS_PS_DB_DB01"; service="db01"},
            @{name="db02"; tnsName="SIEMENS_PS_DB"; service="db02"}
        )
        Add-ServerToProfile -ProfileName "My Dev PC" -ServerName "des-sim-db1" -Instances $instances -DefaultInstance "db02"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfileName,

        [Parameter(Mandatory=$true)]
        [string]$ServerName,

        [Parameter(Mandatory=$true)]
        [array]$Instances,

        [string]$DefaultInstance
    )

    $config = Load-PCProfileConfig

    $profile = $config.profiles | Where-Object { $_.name -eq $ProfileName }
    if (-not $profile) {
        Write-Warning "Profile '$ProfileName' not found"
        return $false
    }

    # Check if server already exists
    $existing = $profile.servers | Where-Object { $_.name -eq $ServerName }
    if ($existing) {
        Write-Warning "Server '$ServerName' already exists in profile. Use Update-ServerInProfile to modify."
        return $false
    }

    # Create server object
    $server = [PSCustomObject]@{
        name = $ServerName
        instances = $Instances
        defaultInstance = $DefaultInstance
    }

    # Add to profile
    if (-not $profile.servers) {
        $profile.servers = @()
    }
    $profile.servers += $server

    $profile.updatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Save-PCProfileConfig -Config $config

    Write-Host "Server '$ServerName' added to profile '$ProfileName'" -ForegroundColor Green
    return $true
}

function Update-LastUsedSettings {
    <#
    .SYNOPSIS
        Updates the last-used settings for a profile.
    .PARAMETER ProfileName
        Profile name
    .PARAMETER Server
        Server name
    .PARAMETER Instance
        Instance name
    .PARAMETER Schema
        Schema name
    .PARAMETER ProjectId
        Project ID
    .PARAMETER ProjectName
        Project name
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProfileName,

        [string]$Server,
        [string]$Instance,
        [string]$Schema,
        [string]$ProjectId,
        [string]$ProjectName
    )

    $config = Load-PCProfileConfig

    $profile = $config.profiles | Where-Object { $_.name -eq $ProfileName }
    if (-not $profile) {
        Write-Warning "Profile '$ProfileName' not found"
        return $false
    }

    # Update last used settings
    if (-not $profile.lastUsed) {
        $profile.lastUsed = @{}
    }

    if ($Server) { $profile.lastUsed.server = $Server }
    if ($Instance) { $profile.lastUsed.instance = $Instance }
    if ($Schema) { $profile.lastUsed.schema = $Schema }
    if ($ProjectId) { $profile.lastUsed.projectId = $ProjectId }
    if ($ProjectName) { $profile.lastUsed.projectName = $ProjectName }

    $profile.lastUsed.timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $profile.updatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Save-PCProfileConfig -Config $config

    return $true
}

# ============================================================================
# Helper Functions
# ============================================================================

function Load-PCProfileConfig {
    <#
    .SYNOPSIS
        Loads the PC profile configuration.
    #>

    if (-not (Test-Path $script:ProfileConfigPath)) {
        return @{
            profiles = @()
            currentProfile = ""
        }
    }

    try {
        return Get-Content $script:ProfileConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Warning "Failed to load PC profile config: $_"
        return @{
            profiles = @()
            currentProfile = ""
        }
    }
}

function Save-PCProfileConfig {
    <#
    .SYNOPSIS
        Saves the PC profile configuration.
    .PARAMETER Config
        Configuration object to save
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Config
    )

    # Ensure config directory exists
    $configDir = Split-Path $script:ProfileConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }

    try {
        # Convert to JSON with proper formatting
        $json = $Config | ConvertTo-Json -Depth 10
        $json | Out-File $script:ProfileConfigPath -Encoding UTF8 -Force

        return $true
    } catch {
        Write-Warning "Failed to save PC profile config: $_"
        return $false
    }
}

function Show-PCProfiles {
    <#
    .SYNOPSIS
        Displays all PC profiles in a formatted table.
    #>

    $profiles = Get-PCProfiles

    if ($profiles.Count -eq 0) {
        Write-Host "No PC profiles configured." -ForegroundColor Yellow
        Write-Host "Run Initialize-PCProfile.ps1 to create your first profile." -ForegroundColor Gray
        return
    }

    Write-Host "`nPC Profiles:" -ForegroundColor Cyan
    Write-Host ""

    $profileTable = $profiles | ForEach-Object {
        $defaultMark = if ($_.isDefault) { "Yes" } else { "" }
        $serverCount = if ($_.servers) { $_.servers.Count } else { 0 }
        $lastUsed = if ($_.lastUsed) {
            "$($_.lastUsed.server) / $($_.lastUsed.schema)"
        } else {
            "Never"
        }

        [PSCustomObject]@{
            Default = $defaultMark
            Name = $_.name
            Hostname = $_.hostname
            Servers = $serverCount
            "Last Used" = $lastUsed
            Description = $_.description
        }
    }

    $profileTable | Format-Table -AutoSize
}

# Functions are automatically available when imported with Import-Module
