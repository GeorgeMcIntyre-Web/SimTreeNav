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

<<<<<<< HEAD
function Show-ConfigurationMenu {
    param([object]$CurrentServer, [string]$CurrentSchema, [string]$CurrentCustomIconDir)
    
    try {
        Clear-Host
    } catch {
        # Ignore if non-interactive
    }
    Show-Menu
    
    Write-Host "Current Configuration:" -ForegroundColor Yellow
    if ($CurrentServer) {
        Write-Host "  Server:   " -NoNewline; Write-Host "$($CurrentServer.Name) ($($CurrentServer.TNSName))" -ForegroundColor Cyan
        Write-Host "  Instance: " -NoNewline; Write-Host $CurrentServer.Instance -ForegroundColor Cyan
    } else {
        Write-Host "  Server:   " -NoNewline; Write-Host "Not selected" -ForegroundColor Gray
        Write-Host "  Instance: " -NoNewline; Write-Host "Not selected" -ForegroundColor Gray
    }
    if ($CurrentSchema -and $CurrentSchema -ne "True" -and $CurrentSchema -ne $true) {
        Write-Host "  Schema:   " -NoNewline; Write-Host $CurrentSchema -ForegroundColor Cyan
    } else {
        Write-Host "  Schema:   " -NoNewline; Write-Host "Not selected" -ForegroundColor Gray
    }
    if ($CurrentCustomIconDir) {
        Write-Host "  Custom Icons: " -NoNewline; Write-Host $CurrentCustomIconDir -ForegroundColor Cyan
    } else {
        Write-Host "  Custom Icons: " -NoNewline; Write-Host "Not selected" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  1. Select Server" -ForegroundColor White
    Write-Host "  2. Select Schema" -ForegroundColor White
    Write-Host "  3. Set Custom Icon Directory" -ForegroundColor White
    Write-Host "  4. Load Tree (includes checkout status)" -ForegroundColor Green
    Write-Host "  5. Exit" -ForegroundColor Red
    Write-Host ""

    $choice = Read-Host "Select option (1-5)"
    return $choice
}

function Select-Server {
    $servers = Get-DatabaseServers
    
    if ($servers.Count -eq 0) {
        Write-Host "`nNo database servers found!" -ForegroundColor Red
        Write-Host "Please ensure tnsnames.ora is configured." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
        return $null
    }
    
    Write-Host "`nAvailable Database Servers:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $servers.Count; $i++) {
        $source = if ($servers[$i].Source) { " [$($servers[$i].Source)]" } else { "" }
        Write-Host "  $($i + 1). $($servers[$i].Name) - $($servers[$i].Description)$source" -ForegroundColor White
        Write-Host "     Instance: $($servers[$i].Instance) | TNS: $($servers[$i].TNSName)" -ForegroundColor Gray
    }
    
    $choice = Read-Host "`nSelect server number"
    $index = [int]$choice - 1
    
    if ($index -ge 0 -and $index -lt $servers.Count) {
        $selectedServer = $servers[$index]
        
        # Resolve TNS name first (use SIEMENS_PS_DB if auto-generated)
        $tnsToUse = $selectedServer.TNSName
        if ($tnsToUse -match '_[a-z]' -or -not $tnsToUse) {
            if (Test-Path "tnsnames.ora") {
                $tnsContent = Get-Content "tnsnames.ora" -Raw
                $tnsPattern = '(?s)^(\w+)\s*=\s*\([^)]*?HOST\s*=\s*' + [regex]::Escape($selectedServer.Name)
                if ($tnsContent -match $tnsPattern) {
                    $tnsToUse = $matches[1]
                } else {
                    $tnsToUse = "SIEMENS_PS_DB"
                }
            } else {
                $tnsToUse = "SIEMENS_PS_DB"
            }
        }
        
        # Now query and select instance
        Write-Host "`nQuerying available instances for $($selectedServer.Name)..." -ForegroundColor Yellow
        $instances = Get-DatabaseInstances -Server $selectedServer.Name -TNSName $tnsToUse
        
        if ($instances.Count -gt 1) {
            Write-Host "`nAvailable Instances:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $instances.Count; $i++) {
                Write-Host "  $($i + 1). $($instances[$i].Instance) - $($instances[$i].Description)" -ForegroundColor White
            }
            
            $instChoice = Read-Host "`nSelect instance number (or press Enter for default: $($selectedServer.Instance))"
            
            if ($instChoice -and $instChoice -match '^\d+$') {
                $instIndex = [int]$instChoice - 1
                if ($instIndex -ge 0 -and $instIndex -lt $instances.Count) {
                    $selectedServer.Instance = $instances[$instIndex].Instance
                    $selectedServer.TNSName = $instances[$instIndex].TNSName
                }
            }
        }
        
        return $selectedServer
    }
    
    return $null
}

function Select-Schema {
    param([object]$Server)
    
    if (-not $Server) {
        Write-Host "Please select a server first!" -ForegroundColor Red
        Read-Host "Press Enter to continue"
        return $null
    }
    
    Write-Host "`nQuerying available schemas from $($Server.Name)..." -ForegroundColor Yellow
    
    # Resolve actual TNS name based on instance
    $tnsToUse = $Server.TNSName
    if (Test-Path "tnsnames.ora") {
        $tnsContent = Get-Content "tnsnames.ora" -Raw
        # First, try to find TNS name for the specific instance
        if ($Server.Instance -eq "db01") {
            # Look for db01-specific TNS entry
            if ($tnsContent -match '(\w+)\s*=\s*.*?SERVICE_NAME\s*=\s*db01') {
                $tnsToUse = $matches[1]
            } elseif ($tnsContent -match 'SIEMENS_PS_DB_DB01') {
                $tnsToUse = "SIEMENS_PS_DB_DB01"
            }
        } elseif ($Server.Instance -eq "db02") {
            # Look for db02-specific TNS entry
            if ($tnsContent -match '(\w+)\s*=\s*.*?SERVICE_NAME\s*=\s*db02') {
                $tnsToUse = $matches[1]
            } elseif ($tnsContent -match 'SIEMENS_PS_DB\s*=') {
                $tnsToUse = "SIEMENS_PS_DB"
            }
        }
        # Fallback: try to find any TNS entry for this server/instance
        if (($tnsToUse -eq $Server.TNSName -or -not $tnsToUse -or $tnsToUse -match '_[a-z]')) {
            $tnsPattern = '(?s)^(\w+)\s*=\s*\([^)]*?HOST\s*=\s*' + [regex]::Escape($Server.Name) + '[^)]*?(?:SERVICE_NAME\s*=\s*' + [regex]::Escape($Server.Instance) + '|SID\s*=\s*' + [regex]::Escape($Server.Instance) + ')'
            if ($tnsContent -match $tnsPattern) {
                $tnsToUse = $matches[1]
            } else {
                if ($Server.Instance -eq "db01") {
                    $tnsToUse = "SIEMENS_PS_DB_DB01"
                } else {
                    $tnsToUse = "SIEMENS_PS_DB"
                }
            }
        }
    } else {
        # Fallback based on instance
        if ($Server.Instance -eq "db01") {
            $tnsToUse = "SIEMENS_PS_DB_DB01"
        } else {
            $tnsToUse = "SIEMENS_PS_DB"
        }
    }
    Write-Host "  Using TNS: $tnsToUse (Instance: $($Server.Instance))" -ForegroundColor Gray
    
    $schemas = Get-AvailableSchemas -TNSName $tnsToUse
    
    if ($schemas.Count -eq 0) {
        Write-Host "No schemas found!" -ForegroundColor Red
        Read-Host "Press Enter to continue"
        return $null
    }
    
    Write-Host "`nAvailable Schemas:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $schemas.Count; $i++) {
        Write-Host "  $($i + 1). $($schemas[$i])" -ForegroundColor White
    }
    
    $choice = Read-Host "`nSelect schema number"
    $index = [int]$choice - 1
    
    if ($index -ge 0 -and $index -lt $schemas.Count) {
        return $schemas[$index]
    }
    
    return $null
}

=======
>>>>>>> e4ca279f2eae6f07d5177454c3edc2c039eb066e
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
<<<<<<< HEAD
        Write-Host "  $($i + 1). $($projects[$i].Caption) (ID: $($projects[$i].ObjectId))" -ForegroundColor White
    }
    
    $choice = Read-Host "`nSelect project number"
    $index = [int]$choice - 1
    
    if ($index -ge 0 -and $index -lt $projects.Count) {
        return $projects[$index]
    }
    
    return $null
}

function Save-Configuration {
    param(
        [object]$Server,
        [string]$Schema,
        [object]$Project,
        [string]$CustomIconDir
    )
    
    if (-not $Server -or -not $Schema) { return }
    
    $config = @{
        Server = if ($Server) { @{ Name = $Server.Name; Instance = $Server.Instance; TNSName = $Server.TNSName } } else { $null }
        Schema = $Schema
        Project = if ($Project) { @{ ObjectId = $Project.ObjectId; Caption = $Project.Caption; Name = $Project.Name } } else { $null }
        CustomIconDir = if ($CustomIconDir) { $CustomIconDir } else { $null }
        LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    $config | ConvertTo-Json -Depth 3 | Out-File $configFile -Encoding UTF8
}

function Load-Configuration {
    if (Test-Path $configFile) {
        try {
            $content = Get-Content $configFile -Raw -Encoding UTF8
            $config = $content | ConvertFrom-Json
            
            if ($config.Server) {
                $server = [PSCustomObject]@{
                    Name = $config.Server.Name
                    Instance = $config.Server.Instance
                    TNSName = $config.Server.TNSName
                }
            } else {
                $server = $null
            }
            
            return @{
                Server = $server
                Schema = $config.Schema
                Project = if ($config.Project) { [PSCustomObject]$config.Project } else { $null }
                CustomIconDir = $config.CustomIconDir
            }
        } catch {
            Write-Warning "Could not load configuration: $_"
            return $null
=======
        $project = $projects[$i]
        $defaultMark = if ($project.ObjectId -eq $DefaultProjectId) {
            $defaultIndex = $i + 1
            " (last used)"
        } else {
            ""
>>>>>>> e4ca279f2eae6f07d5177454c3edc2c039eb066e
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
<<<<<<< HEAD
        [object]$Project,
        [string]$CustomIconDir
    )
    
    Write-Host "`nGenerating navigation tree..." -ForegroundColor Yellow
    Write-Host "  Server: $($Server.Name)" -ForegroundColor Cyan
    Write-Host "  Instance: $($Server.Instance)" -ForegroundColor Cyan
    Write-Host "  Schema: $Schema" -ForegroundColor Cyan
    Write-Host "  Project: $($Project.Caption) (ID: $($Project.ObjectId))" -ForegroundColor Cyan
    Write-Host "  Note: Ghost nodes (e.g., PartInstanceLibrary) use fallback names/icons." -ForegroundColor Gray
    if ($CustomIconDir) {
        Write-Host "  Custom Icons: $CustomIconDir" -ForegroundColor Gray
    }
    
    # Generate the tree data
=======

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

>>>>>>> e4ca279f2eae6f07d5177454c3edc2c039eb066e
    $outputFile = "navigation-tree-${Schema}-$($Project.ObjectId).html"

<<<<<<< HEAD
    # Call the tree generation script (use full path from script's directory)
    $scriptPath = Join-Path $PSScriptRoot "generate-tree-html.ps1"
    & $scriptPath -TNSName $tnsToUse -Schema $Schema -ProjectId $Project.ObjectId -ProjectName $Project.Caption -OutputFile $outputFile -CustomIconDir $CustomIconDir
    
    if (Test-Path $outputFile) {
        Write-Host "`nTree generated successfully!" -ForegroundColor Green
        Write-Host "File: $outputFile" -ForegroundColor Cyan
        Write-Host "`nOpening in browser..." -ForegroundColor Yellow
        Start-Process $outputFile
    } else {
        Write-Host "`nError: Tree generation failed!" -ForegroundColor Red
    }
}

# Main execution
$selectedServer = $null
$selectedSchema = if ($Schema -and $Schema -ne "True" -and $Schema -ne $true) { $Schema } else { $null }
$selectedProject = $null
$selectedCustomIconDir = if ($CustomIconDir) { $CustomIconDir } else { $null }

# Try to load last configuration if requested or if no parameters provided
if ($LoadLast -or (-not $Server -and -not $Instance -and -not $Schema)) {
    $lastConfig = Load-Configuration
    if ($lastConfig -and $lastConfig.Server -and $lastConfig.Schema) {
        if (-not $selectedCustomIconDir -and $lastConfig.CustomIconDir) {
            $selectedCustomIconDir = $lastConfig.CustomIconDir
        }
        Write-Host "`n=== Found Previous Configuration ===" -ForegroundColor Green
        Write-Host "  Server: $($lastConfig.Server.Name)" -ForegroundColor Cyan
        Write-Host "  Instance: $($lastConfig.Server.Instance)" -ForegroundColor Cyan
        Write-Host "  Schema: $($lastConfig.Schema)" -ForegroundColor Cyan
        if ($lastConfig.Project) {
            Write-Host "  Project: $($lastConfig.Project.Caption) (ID: $($lastConfig.Project.ObjectId))" -ForegroundColor Cyan
        }
        Write-Host ""
        $useLast = Read-Host "Use this configuration? (Y/N, default: Y)"
        
        if ($useLast -ne "N" -and $useLast -ne "n") {
            $selectedServer = $lastConfig.Server
            $selectedSchema = $lastConfig.Schema
            $selectedProject = $lastConfig.Project
            
            if ($selectedProject) {
                Write-Host "`nLoading tree with saved configuration..." -ForegroundColor Yellow
                Generate-TreeHTML -Server $selectedServer -Schema $selectedSchema -Project $selectedProject -CustomIconDir $selectedCustomIconDir
                Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $selectedProject -CustomIconDir $selectedCustomIconDir
                exit
            }
        }
=======
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
>>>>>>> e4ca279f2eae6f07d5177454c3edc2c039eb066e
    }
}

# ============================================================================
# Main Workflow
# ============================================================================

<<<<<<< HEAD
if (-not $selectedServer -or -not $selectedSchema) {
    # Interactive mode
    do {
        $choice = Show-ConfigurationMenu -CurrentServer $selectedServer -CurrentSchema $selectedSchema -CurrentCustomIconDir $selectedCustomIconDir
        
        switch ($choice) {
            "1" {
                $selectedServer = Select-Server
                if ($selectedServer) {
                    Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $selectedProject -CustomIconDir $selectedCustomIconDir
                }
            }
            "2" {
                $selectedSchema = Select-Schema -Server $selectedServer
                if ($selectedSchema) {
                    Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $selectedProject -CustomIconDir $selectedCustomIconDir
                }
            }
            "3" {
                $newDir = Read-Host "Enter custom icon directory (blank to clear, separate multiple with ';')"
                if ([string]::IsNullOrWhiteSpace($newDir)) {
                    $selectedCustomIconDir = $null
                } else {
                    $selectedCustomIconDir = $newDir.Trim()
                }
                Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $selectedProject -CustomIconDir $selectedCustomIconDir
            }
            "4" {
                # Load Tree (Standard View)
                if ($selectedServer -and $selectedSchema) {
                    $project = Select-Project -Server $selectedServer -Schema $selectedSchema
                    if ($project) {
                        $selectedProject = $project
                        Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $project -CustomIconDir $selectedCustomIconDir
                        Generate-TreeHTML -Server $selectedServer -Schema $selectedSchema -Project $project -CustomIconDir $selectedCustomIconDir
                        Read-Host "`nPress Enter to continue"
                    }
                } else {
                    Write-Host "`nPlease complete all selections first!" -ForegroundColor Red
                    Read-Host "Press Enter to continue"
                }
            }
            "5" {
                Write-Host "`nExiting..." -ForegroundColor Yellow
                exit
            }
            default {
                Write-Host "`nInvalid option!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
} else {
    # Non-interactive mode - use provided parameters
    $project = Select-Project -Server $selectedServer -Schema $selectedSchema
    if ($project) {
        Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $project -CustomIconDir $selectedCustomIconDir
        Generate-TreeHTML -Server $selectedServer -Schema $selectedSchema -Project $project -CustomIconDir $selectedCustomIconDir
    }
=======
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
>>>>>>> e4ca279f2eae6f07d5177454c3edc2c039eb066e
}
