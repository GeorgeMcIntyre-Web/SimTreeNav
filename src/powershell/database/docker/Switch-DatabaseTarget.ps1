# Switch-DatabaseTarget.ps1
# Switches between LOCAL (Docker) and REMOTE (des-sim-db1) database targets
#
# Usage:
#   .\Switch-DatabaseTarget.ps1 -Target LOCAL     # Use Docker Oracle
#   .\Switch-DatabaseTarget.ps1 -Target REMOTE    # Use production server
#   .\Switch-DatabaseTarget.ps1 -Status            # Show current target

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("LOCAL", "REMOTE")]
    [string]$Target,

    [switch]$Status
)

$ErrorActionPreference = "Stop"
$configDir = Join-Path $PSScriptRoot "..\..\..\..\config"
$configFile = Join-Path $configDir "database-target.json"

# Target definitions
$targets = @{
    LOCAL = @{
        TNSName     = "ORACLE_LOCAL"
        Host        = "localhost"
        Port        = 1521
        SID         = "EMS12"
        Description = "Local Docker Oracle 12c"
    }
    REMOTE = @{
        TNSName     = "SIEMENS_PS_DB"
        Host        = "des-sim-db1"
        Port        = 1521
        SID         = "db02"
        Description = "Production Siemens Process Simulation DB"
    }
}

function Get-CurrentTarget {
    if (Test-Path $configFile) {
        try {
            return Get-Content $configFile -Raw | ConvertFrom-Json
        } catch {
            return $null
        }
    }
    return $null
}

function Show-Status {
    $current = Get-CurrentTarget

    Write-Host ""
    Write-Host "=== Database Target Status ===" -ForegroundColor Cyan
    Write-Host ""

    if ($current) {
        $isLocal = $current.Target -eq "LOCAL"
        $color = if ($isLocal) { "Yellow" } else { "Green" }

        Write-Host "  Active Target: $($current.Target)" -ForegroundColor $color
        Write-Host "  TNS Name:      $($current.TNSName)" -ForegroundColor White
        Write-Host "  Switched At:   $($current.SwitchedAt)" -ForegroundColor Gray
        Write-Host "  Switched By:   $($current.SwitchedBy)" -ForegroundColor Gray
    } else {
        Write-Host "  No target configured. Default: REMOTE" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Available targets:" -ForegroundColor Gray
    foreach ($key in $targets.Keys) {
        $t = $targets[$key]
        $marker = if ($current -and $current.Target -eq $key) { " <-- ACTIVE" } else { "" }
        Write-Host "    $key : $($t.TNSName) ($($t.Description))$marker" -ForegroundColor Gray
    }
    Write-Host ""
}

# Status mode
if ($Status -or (-not $Target)) {
    Show-Status
    if (-not $Target) {
        Write-Host "  Usage: .\Switch-DatabaseTarget.ps1 -Target LOCAL|REMOTE" -ForegroundColor Gray
    }
    exit 0
}

# Switch target
$targetInfo = $targets[$Target]

$config = @{
    Target      = $Target
    TNSName     = $targetInfo.TNSName
    Host        = $targetInfo.Host
    Port        = $targetInfo.Port
    SID         = $targetInfo.SID
    Description = $targetInfo.Description
    SwitchedAt  = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    SwitchedBy  = "$env:USERDOMAIN\$env:USERNAME"
    Machine     = $env:COMPUTERNAME
}

# Ensure config directory exists
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}

$config | ConvertTo-Json -Depth 3 | Out-File $configFile -Encoding UTF8

Write-Host ""
Write-Host "Database target switched to: $Target" -ForegroundColor Green
Write-Host "  TNS Name: $($targetInfo.TNSName)" -ForegroundColor Cyan
Write-Host "  Host:     $($targetInfo.Host):$($targetInfo.Port)" -ForegroundColor White
Write-Host "  SID:      $($targetInfo.SID)" -ForegroundColor White
Write-Host ""

# Verify local Docker is running if switching to LOCAL
if ($Target -eq "LOCAL") {
    $containerStatus = docker ps --filter "name=oracle-tecnomatix-12c" --format "{{.Status}}" 2>$null
    if ($containerStatus -and $containerStatus -match "Up") {
        Write-Host "  Docker container: RUNNING" -ForegroundColor Green
    } else {
        Write-Host "  WARNING: Docker container is NOT running!" -ForegroundColor Yellow
        Write-Host "  Run: docker\oracle\Start-OracleDocker.ps1" -ForegroundColor Yellow
    }
}
