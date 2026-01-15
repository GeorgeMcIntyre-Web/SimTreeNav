# Tree Viewer Launcher V2 - With PC Profile Support
# Fast, user-friendly profile-based workflow

param(
    [string]$ProfileName,
    [switch]$LoadLast = $false
)

$ErrorActionPreference = "Stop"

# Import required modules
$credManagerPath = Join-Path $PSScriptRoot "..\utilities\CredentialManager.ps1"
$profileManagerPath = Join-Path $PSScriptRoot "..\utilities\PCProfileManager.ps1"

if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
} else {
    Write-Warning "Credential manager not found. Some features may not work."
}

if (Test-Path $profileManagerPath) {
    Import-Module $profileManagerPath -Force
} else {
    Write-Warning "PC Profile manager not found. Falling back to legacy mode."
    # Fall back to old launcher
    $oldLauncher = Join-Path $PSScriptRoot "tree-viewer-launcher.ps1.backup"
    if (Test-Path $oldLauncher) {
        Write-Host "Using legacy launcher..." -ForegroundColor Yellow
        & $oldLauncher @PSBoundParameters
        exit
    } else {
        Write-Error "PC Profile system not available and no backup launcher found."
        exit 1
    }
}

# ============================================================================
# Helper Functions
# ============================================================================

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Siemens Process Simulation" -ForegroundColor Yellow
    Write-Host "  Navigation Tree Viewer" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Select-PCProfile {
    <#
    .SYNOPSIS
        Interactive PC profile selection
    #>

    $profiles = Get-PCProfiles

    if ($profiles.Count -eq 0) {
        Write-Host "No PC profiles configured." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Would you like to create one now?" -ForegroundColor Yellow
        $create = Read-Host "(Y/N)"

        if ($create -eq "Y" -or $create -eq "y") {
            $initScript = Join-Path $PSScriptRoot "..\database\Initialize-PCProfile.ps1"
            if (Test-Path $initScript) {
                & $initScript
                # Reload profiles
                $profiles = Get-PCProfiles
                if ($profiles.Count -eq 0) {
                    Write-Host "No profiles created. Exiting." -ForegroundColor Red
                    exit 1
                }
            } else {
                Write-Host "Setup script not found. Please run Initialize-PCProfile.ps1" -ForegroundColor Red
                exit 1
            }
        } else {
            Write-Host "Please run Initialize-PCProfile.ps1 to create a profile first." -ForegroundColor Yellow
            exit 0
        }
    }

    # Show profiles
    Write-Host "Select PC Profile:" -ForegroundColor Yellow
    Write-Host ""

    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $profile = $profiles[$i]
        $defaultMark = if ($profile.isDefault) { " (default)" } else { "" }

        Write-Host "  $($i + 1). $($profile.name)$defaultMark" -ForegroundColor White
        Write-Host "     Host: $($profile.hostname)" -ForegroundColor Gray

        if ($profile.servers -and $profile.servers.Count -gt 0) {
            $serverNames = ($profile.servers | ForEach-Object { $_.name }) -join ", "
            Write-Host "     Servers: $serverNames" -ForegroundColor Gray
        }

        if ($profile.lastUsed) {
            $lastUsed = "$($profile.lastUsed.server)/$($profile.lastUsed.instance)/$($profile.lastUsed.schema)"
            Write-Host "     Last used: $lastUsed" -ForegroundColor DarkGray
        }

        Write-Host ""
    }

    # Get selection
    $defaultProfile = Get-DefaultPCProfile
    $defaultIndex = if ($defaultProfile) {
        $profiles.IndexOf($defaultProfile) + 1
    } else {
        1
    }

    $choice = Read-Host "Select profile (1-$($profiles.Count), or Enter for default [$defaultIndex])"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = $defaultIndex
    }

    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $profiles.Count) {
        Write-Host "Invalid selection. Using default." -ForegroundColor Yellow
        return $defaultProfile
    }

    return $profiles[$index]
}

function Select-Server {
    <#
    .SYNOPSIS
        Select server from profile
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Profile
    )

    if (-not $Profile.servers -or $Profile.servers.Count -eq 0) {
        Write-Host "No servers configured in this profile." -ForegroundColor Red
        Write-Host "Please run Initialize-PCProfile.ps1 to configure servers." -ForegroundColor Yellow
        return $null
    }

    if ($Profile.servers.Count -eq 1) {
        Write-Host "Using server: $($Profile.servers[0].name)" -ForegroundColor Cyan
        return $Profile.servers[0]
    }

    Write-Host "Select Database Server:" -ForegroundColor Yellow
    Write-Host ""

    for ($i = 0; $i -lt $Profile.servers.Count; $i++) {
        $server = $Profile.servers[$i]
        $instanceCount = if ($server.instances) { $server.instances.Count } else { 0 }

        Write-Host "  $($i + 1). $($server.name)" -ForegroundColor White
        Write-Host "     Instances: $instanceCount" -ForegroundColor Gray
        if ($server.defaultInstance) {
            Write-Host "     Default: $($server.defaultInstance)" -ForegroundColor Gray
        }
        Write-Host ""
    }

    $choice = Read-Host "Select server (1-$($Profile.servers.Count))"
    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $Profile.servers.Count) {
        Write-Host "Invalid selection. Using first server." -ForegroundColor Yellow
        return $Profile.servers[0]
    }

    return $Profile.servers[$index]
}

function Select-Instance {
    <#
    .SYNOPSIS
        Select instance from server
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Server
    )

    if (-not $Server.instances -or $Server.instances.Count -eq 0) {
        Write-Host "No instances configured for this server." -ForegroundColor Red
        return $null
    }

    if ($Server.instances.Count -eq 1) {
        Write-Host "Using instance: $($Server.instances[0].name)" -ForegroundColor Cyan
        return $Server.instances[0]
    }

    Write-Host "Select Database Instance:" -ForegroundColor Yellow
    Write-Host ""

    $defaultIndex = 0
    for ($i = 0; $i -lt $Server.instances.Count; $i++) {
        $instance = $Server.instances[$i]
        $defaultMark = if ($instance.name -eq $Server.defaultInstance) {
            $defaultIndex = $i + 1
            " (default)"
        } else {
            ""
        }

        Write-Host "  $($i + 1). $($instance.name)$defaultMark" -ForegroundColor White
        Write-Host "     TNS: $($instance.tnsName)" -ForegroundColor Gray
        Write-Host ""
    }

    $choice = Read-Host "Select instance (1-$($Server.instances.Count), or Enter for default [$defaultIndex])"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = $defaultIndex
    }

    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $Server.instances.Count) {
        Write-Host "Invalid selection. Using default." -ForegroundColor Yellow
        return $Server.instances[$defaultIndex - 1]
    }

    return $Server.instances[$index]
}

function Get-AvailableSchemas {
    <#
    .SYNOPSIS
        Query database for available schemas
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName
    )

    Write-Host "Querying available schemas..." -ForegroundColor Yellow

    $queryFile = "get-schemas-temp.sql"
    $query = @"
SET PAGESIZE 1000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT DISTINCT u.USERNAME
FROM DBA_USERS u
WHERE u.ACCOUNT_STATUS = 'OPEN'
  AND u.DEFAULT_TABLESPACE NOT IN ('SYSTEM', 'SYSAUX')
  AND u.USERNAME NOT LIKE '%_AQ'
  AND u.USERNAME LIKE 'DESIGN%'
ORDER BY u.USERNAME;
EXIT;
"@

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$PWD\$queryFile", $query, $utf8NoBom)

    $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

    try {
        $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
    } catch {
        Write-Warning "Failed to get credentials, using default"
        $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
    }

    $result = sqlplus -S $connectionString "@$queryFile" 2>&1

    Remove-Item $queryFile -ErrorAction SilentlyContinue

    $schemas = @()
    foreach ($line in $result) {
        $line = $line.Trim()
        if ($line -match '^\w+$' -and $line.Length -gt 0 -and $line -like "DESIGN*") {
            $schemas += $line
        }
    }

    return $schemas
}

function Select-Schema {
    <#
    .SYNOPSIS
        Select schema from available schemas
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [string]$DefaultSchema
    )

    $schemas = Get-AvailableSchemas -TNSName $TNSName

    if ($schemas.Count -eq 0) {
        Write-Host "No schemas found!" -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "Available Schemas:" -ForegroundColor Yellow
    Write-Host ""

    $defaultIndex = 1
    for ($i = 0; $i -lt $schemas.Count; $i++) {
        $schema = $schemas[$i]
        $defaultMark = if ($schema -eq $DefaultSchema) {
            $defaultIndex = $i + 1
            " (last used)"
        } else {
            ""
        }

        Write-Host "  $($i + 1). $schema$defaultMark" -ForegroundColor White
    }

    Write-Host ""
    $choice = Read-Host "Select schema (1-$($schemas.Count), or Enter for default [$defaultIndex])"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = $defaultIndex
    }

    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $schemas.Count) {
        Write-Host "Using default schema" -ForegroundColor Yellow
        return $schemas[$defaultIndex - 1]
    }

    return $schemas[$index]
}

function Get-ProjectsForSchema {
    <#
    .SYNOPSIS
        Query projects in schema
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [Parameter(Mandatory=$true)]
        [string]$Schema
    )

    Write-Host "Loading projects from $Schema..." -ForegroundColor Yellow

    $queryFile = "get-projects-temp.sql"
    $query = @"
SET PAGESIZE 1000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    p.PROJECTID || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed Project') || '|' ||
    NVL(c.EXTERNALID_S_, '')
FROM $Schema.DFPROJECT p
LEFT JOIN $Schema.COLLECTION_ c ON p.PROJECTID = c.OBJECT_ID
WHERE p.PROJECTID IS NOT NULL
ORDER BY c.CAPTION_S_;
EXIT;
"@

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$PWD\$queryFile", $query, $utf8NoBom)

    $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

    try {
        $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
    } catch {
        Write-Warning "Failed to get credentials, using default"
        $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
    }

    $result = sqlplus -S $connectionString "@$queryFile" 2>&1

    Remove-Item $queryFile -ErrorAction SilentlyContinue

    $projects = @()
    foreach ($line in $result) {
        if ($line -match '^\d+\|') {
            $parts = $line -split '\|'
            if ($parts.Length -ge 2) {
                $projects += [PSCustomObject]@{
                    ObjectId = $parts[0]
                    Caption = $parts[1]
                    ExternalId = if ($parts.Length -ge 3) { $parts[2] } else { "" }
                }
            }
        }
    }

    return $projects
}

function Select-Project {
    <#
    .SYNOPSIS
        Select project from schema
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [Parameter(Mandatory=$true)]
        [string]$Schema,

        [string]$DefaultProjectId
    )

    $projects = Get-ProjectsForSchema -TNSName $TNSName -Schema $Schema

    if ($projects.Count -eq 0) {
        Write-Host "No projects found in $Schema!" -ForegroundColor Red
        return $null
    }

    Write-Host ""
    Write-Host "Available Projects:" -ForegroundColor Yellow
    Write-Host ""

    $defaultIndex = 1
    for ($i = 0; $i -lt $projects.Count; $i++) {
        $project = $projects[$i]
        $defaultMark = if ($project.ObjectId -eq $DefaultProjectId) {
            $defaultIndex = $i + 1
            " (last used)"
        } else {
            ""
        }

        Write-Host "  $($i + 1). $($project.Caption)$defaultMark" -ForegroundColor White
        Write-Host "     ID: $($project.ObjectId)" -ForegroundColor Gray
        Write-Host ""
    }

    $choice = Read-Host "Select project (1-$($projects.Count), or Enter for default [$defaultIndex])"

    if ([string]::IsNullOrWhiteSpace($choice)) {
        $choice = $defaultIndex
    }

    $index = [int]$choice - 1

    if ($index -lt 0 -or $index -ge $projects.Count) {
        Write-Host "Using default project" -ForegroundColor Yellow
        return $projects[$defaultIndex - 1]
    }

    return $projects[$index]
}

function Generate-TreeHTML {
    <#
    .SYNOPSIS
        Generate and display tree HTML
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [Parameter(Mandatory=$true)]
        [string]$Schema,

        [Parameter(Mandatory=$true)]
        $Project
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Generating Navigation Tree" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  TNS:     $TNSName" -ForegroundColor White
    Write-Host "  Schema:  $Schema" -ForegroundColor White
    Write-Host "  Project: $($Project.Caption) (ID: $($Project.ObjectId))" -ForegroundColor White
    Write-Host ""

    $outputFile = "navigation-tree-${Schema}-$($Project.ObjectId).html"

    $generateScript = Join-Path $PSScriptRoot "generate-tree-html.ps1"
    if (-not (Test-Path $generateScript)) {
        Write-Host "✗ generate-tree-html.ps1 not found!" -ForegroundColor Red
        return $false
    }

    & $generateScript -TNSName $TNSName -Schema $Schema -ProjectId $Project.ObjectId -ProjectName $Project.Caption -OutputFile $outputFile

    if (Test-Path $outputFile) {
        Write-Host ""
        Write-Host "✓ Tree generated successfully!" -ForegroundColor Green
        Write-Host "  File: $outputFile" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Opening in browser..." -ForegroundColor Yellow
        Start-Process $outputFile
        return $true
    } else {
        Write-Host ""
        Write-Host "✗ Tree generation failed!" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# Main Workflow
# ============================================================================

Show-Header

# Step 1: Select PC Profile
$profile = if ($ProfileName) {
    Get-PCProfile -Name $ProfileName
} else {
    Select-PCProfile
}

if (-not $profile) {
    Write-Host "No profile selected. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Using profile: $($profile.name)" -ForegroundColor Green
Write-Host ""

# Step 2: Select Server
$server = Select-Server -Profile $profile

if (-not $server) {
    Write-Host "No server selected. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Selected server: $($server.name)" -ForegroundColor Green
Write-Host ""

# Step 3: Select Instance
$instance = Select-Instance -Server $server

if (-not $instance) {
    Write-Host "No instance selected. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Selected instance: $($instance.name)" -ForegroundColor Green
Write-Host "TNS Name: $($instance.tnsName)" -ForegroundColor Cyan
Write-Host ""

# Step 4: Select Schema
$defaultSchema = if ($profile.lastUsed) { $profile.lastUsed.schema } else { $null }
$schema = Select-Schema -TNSName $instance.tnsName -DefaultSchema $defaultSchema

if (-not $schema) {
    Write-Host "No schema selected. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Selected schema: $schema" -ForegroundColor Green
Write-Host ""

# Step 5: Select Project
$defaultProjectId = if ($profile.lastUsed) { $profile.lastUsed.projectId } else { $null }
$project = Select-Project -TNSName $instance.tnsName -Schema $schema -DefaultProjectId $defaultProjectId

if (-not $project) {
    Write-Host "No project selected. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Selected project: $($project.Caption)" -ForegroundColor Green
Write-Host ""

# Step 6: Update last used settings
Update-LastUsedSettings -ProfileName $profile.name -Server $server.name -Instance $instance.name -Schema $schema -ProjectId $project.ObjectId -ProjectName $project.Caption

# Step 7: Generate tree
$success = Generate-TreeHTML -TNSName $instance.tnsName -Schema $schema -Project $project

if ($success) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  ✓ Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "Please check the errors above and try again." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
