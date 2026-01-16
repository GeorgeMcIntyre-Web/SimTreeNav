# Tree Viewer Launcher V3 - Large Tree Support
# Supports virtualized viewing for 50k+ nodes

param(
    [string]$ProfileName,
    [switch]$LoadLast = $false,
    [switch]$UseVirtualized = $false,  # Use virtualized viewer for large trees
    [int]$VirtualizedThreshold = 10000, # Auto-switch to virtualized above this
    [switch]$GenerateJson = $false,     # Also generate JSON output
    [switch]$CompressOutput = $false    # Gzip compress outputs
)

$ErrorActionPreference = "Stop"

# Import required modules
$credManagerPath = Join-Path $PSScriptRoot "..\utilities\CredentialManager.ps1"
$profileManagerPath = Join-Path $PSScriptRoot "..\utilities\PCProfileManager.ps1"
$perfMetricsPath = Join-Path $PSScriptRoot "..\utilities\PerformanceMetrics.ps1"

if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
}

if (Test-Path $profileManagerPath) {
    Import-Module $profileManagerPath -Force
} else {
    Write-Warning "PC Profile manager not found. Falling back to legacy mode."
    $oldLauncher = Join-Path $PSScriptRoot "tree-viewer-launcher.ps1.backup"
    if (Test-Path $oldLauncher) {
        Write-Host "Using legacy launcher..." -ForegroundColor Yellow
        & $oldLauncher @PSBoundParameters
        exit
    }
}

if (Test-Path $perfMetricsPath) {
    Import-Module $perfMetricsPath -Force
}

# ============================================================================
# Helper Functions (same as v2, condensed)
# ============================================================================

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Siemens Process Simulation" -ForegroundColor Yellow
    Write-Host "  Navigation Tree Viewer v3" -ForegroundColor Yellow
    Write-Host "  (Large Tree Support)" -ForegroundColor DarkGray
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Select-PCProfile {
    $profiles = Get-PCProfiles
    
    if ($profiles.Count -eq 0) {
        Write-Host "No PC profiles configured. Please run Initialize-PCProfile.ps1" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "Select PC Profile:" -ForegroundColor Yellow
    Write-Host ""
    
    for ($i = 0; $i -lt $profiles.Count; $i++) {
        $profile = $profiles[$i]
        $defaultMark = if ($profile.isDefault) { " (default)" } else { "" }
        Write-Host "  $($i + 1). $($profile.name)$defaultMark" -ForegroundColor White
        Write-Host "     Host: $($profile.hostname)" -ForegroundColor Gray
        Write-Host ""
    }
    
    $defaultProfile = Get-DefaultPCProfile
    $defaultIndex = if ($defaultProfile) { $profiles.IndexOf($defaultProfile) + 1 } else { 1 }
    
    $choice = Read-Host "Select profile (1-$($profiles.Count), or Enter for default [$defaultIndex])"
    
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $defaultIndex }
    $index = [int]$choice - 1
    
    if ($index -lt 0 -or $index -ge $profiles.Count) {
        return $defaultProfile
    }
    return $profiles[$index]
}

function Select-Server { param($Profile)
    if (-not $Profile.servers -or $Profile.servers.Count -eq 0) {
        Write-Host "No servers configured." -ForegroundColor Red
        return $null
    }
    if ($Profile.servers.Count -eq 1) {
        Write-Host "Using server: $($Profile.servers[0].name)" -ForegroundColor Cyan
        return $Profile.servers[0]
    }
    
    Write-Host "Select Database Server:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Profile.servers.Count; $i++) {
        Write-Host "  $($i + 1). $($Profile.servers[$i].name)" -ForegroundColor White
    }
    
    $choice = Read-Host "Select server (1-$($Profile.servers.Count))"
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $Profile.servers.Count) { return $Profile.servers[0] }
    return $Profile.servers[$index]
}

function Select-Instance { param($Server)
    if (-not $Server.instances -or $Server.instances.Count -eq 0) { return $null }
    if ($Server.instances.Count -eq 1) {
        Write-Host "Using instance: $($Server.instances[0].name)" -ForegroundColor Cyan
        return $Server.instances[0]
    }
    
    Write-Host "Select Database Instance:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $Server.instances.Count; $i++) {
        Write-Host "  $($i + 1). $($Server.instances[$i].name)" -ForegroundColor White
    }
    
    $choice = Read-Host "Select instance"
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $Server.instances.Count) { return $Server.instances[0] }
    return $Server.instances[$index]
}

function Get-AvailableSchemas { param([string]$TNSName)
    Write-Host "Querying available schemas..." -ForegroundColor Yellow
    
    $query = @"
SET PAGESIZE 1000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT DISTINCT u.USERNAME FROM DBA_USERS u
WHERE u.ACCOUNT_STATUS = 'OPEN' AND u.USERNAME LIKE 'DESIGN%'
ORDER BY u.USERNAME;
EXIT;
"@
    
    $queryFile = "get-schemas-temp.sql"
    [System.IO.File]::WriteAllText("$PWD\$queryFile", $query, [System.Text.UTF8Encoding]::new($false))
    
    try { $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop }
    catch { $connectionString = "sys/change_on_install@$TNSName AS SYSDBA" }
    
    $result = sqlplus -S $connectionString "@$queryFile" 2>&1
    Remove-Item $queryFile -ErrorAction SilentlyContinue
    
    return @($result | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\w+$' -and $_ -like "DESIGN*" })
}

function Select-Schema { param([string]$TNSName, [string]$DefaultSchema)
    $schemas = Get-AvailableSchemas -TNSName $TNSName
    if ($schemas.Count -eq 0) { Write-Host "No schemas found!" -ForegroundColor Red; return $null }
    
    Write-Host "Available Schemas:" -ForegroundColor Yellow
    $defaultIndex = 1
    for ($i = 0; $i -lt $schemas.Count; $i++) {
        $mark = if ($schemas[$i] -eq $DefaultSchema) { $defaultIndex = $i + 1; " (last used)" } else { "" }
        Write-Host "  $($i + 1). $($schemas[$i])$mark" -ForegroundColor White
    }
    
    $choice = Read-Host "Select schema (Enter for default [$defaultIndex])"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $defaultIndex }
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $schemas.Count) { return $schemas[$defaultIndex - 1] }
    return $schemas[$index]
}

function Get-ProjectsForSchema { param([string]$TNSName, [string]$Schema)
    Write-Host "Loading projects from $Schema..." -ForegroundColor Yellow
    
    $query = @"
SET PAGESIZE 1000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT p.PROJECTID || '|' || NVL(c.CAPTION_S_, 'Unnamed') || '|' || NVL(c.EXTERNALID_S_, '')
FROM $Schema.DFPROJECT p
LEFT JOIN $Schema.COLLECTION_ c ON p.PROJECTID = c.OBJECT_ID
WHERE p.PROJECTID IS NOT NULL
ORDER BY c.CAPTION_S_;
EXIT;
"@
    
    $queryFile = "get-projects-temp.sql"
    [System.IO.File]::WriteAllText("$PWD\$queryFile", $query, [System.Text.UTF8Encoding]::new($false))
    
    try { $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop }
    catch { $connectionString = "sys/change_on_install@$TNSName AS SYSDBA" }
    
    $result = sqlplus -S $connectionString "@$queryFile" 2>&1
    Remove-Item $queryFile -ErrorAction SilentlyContinue
    
    $projects = @()
    foreach ($line in $result) {
        if ($line -match '^\d+\|') {
            $parts = $line -split '\|'
            $projects += [PSCustomObject]@{
                ObjectId = $parts[0]
                Caption = $parts[1]
                ExternalId = if ($parts.Length -ge 3) { $parts[2] } else { "" }
            }
        }
    }
    return $projects
}

function Select-Project { param([string]$TNSName, [string]$Schema, [string]$DefaultProjectId)
    $projects = Get-ProjectsForSchema -TNSName $TNSName -Schema $Schema
    if ($projects.Count -eq 0) { Write-Host "No projects found!" -ForegroundColor Red; return $null }
    
    Write-Host "Available Projects:" -ForegroundColor Yellow
    $defaultIndex = 1
    for ($i = 0; $i -lt $projects.Count; $i++) {
        $mark = if ($projects[$i].ObjectId -eq $DefaultProjectId) { $defaultIndex = $i + 1; " (last used)" } else { "" }
        Write-Host "  $($i + 1). $($projects[$i].Caption)$mark" -ForegroundColor White
        Write-Host "     ID: $($projects[$i].ObjectId)" -ForegroundColor Gray
    }
    
    $choice = Read-Host "Select project (Enter for default [$defaultIndex])"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = $defaultIndex }
    $index = [int]$choice - 1
    if ($index -lt 0 -or $index -ge $projects.Count) { return $projects[$defaultIndex - 1] }
    return $projects[$index]
}

function Get-EstimatedNodeCount { param([string]$TNSName, [string]$Schema, [string]$ProjectId)
    Write-Host "Estimating node count..." -ForegroundColor Yellow
    
    $query = @"
SET PAGESIZE 0
SET LINESIZE 100
SET FEEDBACK OFF
SET HEADING OFF

SELECT COUNT(*) FROM (
    SELECT c.OBJECT_ID FROM $Schema.REL_COMMON r
    INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
    START WITH r.FORWARD_OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
);
EXIT;
"@
    
    $queryFile = "count-nodes-temp.sql"
    [System.IO.File]::WriteAllText("$PWD\$queryFile", $query, [System.Text.UTF8Encoding]::new($false))
    
    try { $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop }
    catch { $connectionString = "sys/change_on_install@$TNSName AS SYSDBA" }
    
    $result = sqlplus -S $connectionString "@$queryFile" 2>&1
    Remove-Item $queryFile -ErrorAction SilentlyContinue
    
    $count = ($result | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
    return [int]$count
}

function Generate-TreeHTML { param([string]$TNSName, [string]$Schema, $Project, [bool]$UseVirtualized, [bool]$GenerateJson, [bool]$CompressOutput)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Generating Navigation Tree" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  TNS:     $TNSName" -ForegroundColor White
    Write-Host "  Schema:  $Schema" -ForegroundColor White
    Write-Host "  Project: $($Project.Caption) (ID: $($Project.ObjectId))" -ForegroundColor White
    Write-Host "  Mode:    $(if ($UseVirtualized) { 'Virtualized (large tree)' } else { 'Standard' })" -ForegroundColor White
    Write-Host ""
    
    # Start performance tracking
    if (Get-Command Start-PerfSession -ErrorAction SilentlyContinue) {
        Start-PerfSession -Phase "TreeGeneration"
    }
    
    $outputFile = "navigation-tree-${Schema}-$($Project.ObjectId).html"
    
    if ($UseVirtualized) {
        $generateScript = Join-Path $PSScriptRoot "generate-virtualized-tree-html.ps1"
        if (-not (Test-Path $generateScript)) {
            Write-Warning "Virtualized generator not found, falling back to standard"
            $generateScript = Join-Path $PSScriptRoot "generate-tree-html.ps1"
        }
    } else {
        $generateScript = Join-Path $PSScriptRoot "generate-tree-html.ps1"
    }
    
    if (-not (Test-Path $generateScript)) {
        Write-Host "Generator script not found: $generateScript" -ForegroundColor Red
        return $false
    }
    
    $params = @{
        TNSName = $TNSName
        Schema = $Schema
        ProjectId = $Project.ObjectId
        ProjectName = $Project.Caption
        OutputFile = $outputFile
    }
    
    if ($UseVirtualized) {
        $params.GenerateJsonOutput = $GenerateJson
        $params.CompressOutput = $CompressOutput
    }
    
    & $generateScript @params
    
    # Complete performance tracking
    if (Get-Command Complete-PerfSession -ErrorAction SilentlyContinue) {
        $metrics = Complete-PerfSession
    }
    
    if (Test-Path $outputFile) {
        $fileSize = [math]::Round((Get-Item $outputFile).Length / 1MB, 2)
        Write-Host ""
        Write-Host "Tree generated successfully!" -ForegroundColor Green
        Write-Host "  File: $outputFile (${fileSize}MB)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Opening in browser..." -ForegroundColor Yellow
        Start-Process $outputFile
        return $true
    } else {
        Write-Host "Tree generation failed!" -ForegroundColor Red
        return $false
    }
}

# ============================================================================
# Main Workflow
# ============================================================================

Show-Header

# Step 1: Select PC Profile
$profile = if ($ProfileName) { Get-PCProfile -Name $ProfileName } else { Select-PCProfile }
if (-not $profile) { Write-Host "No profile selected. Exiting." -ForegroundColor Red; exit 1 }
Write-Host "Using profile: $($profile.name)" -ForegroundColor Green

# Step 2: Select Server
$server = Select-Server -Profile $profile
if (-not $server) { exit 1 }

# Step 3: Select Instance
$instance = Select-Instance -Server $server
if (-not $instance) { exit 1 }
Write-Host "TNS Name: $($instance.tnsName)" -ForegroundColor Cyan

# Step 4: Select Schema
$defaultSchema = if ($profile.lastUsed) { $profile.lastUsed.schema } else { $null }
$schema = Select-Schema -TNSName $instance.tnsName -DefaultSchema $defaultSchema
if (-not $schema) { exit 1 }

# Step 5: Select Project
$defaultProjectId = if ($profile.lastUsed) { $profile.lastUsed.projectId } else { $null }
$project = Select-Project -TNSName $instance.tnsName -Schema $schema -DefaultProjectId $defaultProjectId
if (-not $project) { exit 1 }

# Step 6: Estimate node count and decide on viewer mode
$estimatedNodes = Get-EstimatedNodeCount -TNSName $instance.tnsName -Schema $schema -ProjectId $project.ObjectId
Write-Host "Estimated nodes: $($estimatedNodes.ToString('N0'))" -ForegroundColor Cyan

$useVirtualizedMode = $UseVirtualized
if (-not $UseVirtualized -and $estimatedNodes -gt $VirtualizedThreshold) {
    Write-Host ""
    Write-Host "Large tree detected ($($estimatedNodes.ToString('N0')) nodes)." -ForegroundColor Yellow
    Write-Host "Virtualized viewer is recommended for better performance." -ForegroundColor Yellow
    $response = Read-Host "Use virtualized viewer? (Y/n)"
    $useVirtualizedMode = ($response -ne 'n' -and $response -ne 'N')
}

# Step 7: Update last used settings
Update-LastUsedSettings -ProfileName $profile.name -Server $server.name -Instance $instance.name -Schema $schema -ProjectId $project.ObjectId -ProjectName $project.Caption

# Step 8: Generate tree
$success = Generate-TreeHTML -TNSName $instance.tnsName -Schema $schema -Project $project -UseVirtualized $useVirtualizedMode -GenerateJson $GenerateJson -CompressOutput $CompressOutput

if ($success) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
} else {
    Write-Host "Please check the errors above and try again." -ForegroundColor Yellow
    exit 1
}
