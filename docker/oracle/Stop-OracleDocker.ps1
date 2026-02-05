# Stop-OracleDocker.ps1
# Stops the local Oracle 12c Docker container
#
# Usage:
#   .\Stop-OracleDocker.ps1                  # Stop container (preserves data)
#   .\Stop-OracleDocker.ps1 -RemoveVolumes   # Stop and delete all data

param(
    [switch]$RemoveVolumes
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeFile = Join-Path $scriptDir "docker-compose.yml"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Oracle 12c Tecnomatix - Stop Container" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check if container exists
$containerStatus = docker ps -a --filter "name=oracle-tecnomatix-12c" --format "{{.Status}}" 2>$null

if (-not $containerStatus) {
    Write-Host "No Oracle container found." -ForegroundColor Yellow
    exit 0
}

if ($RemoveVolumes) {
    Write-Host "WARNING: This will DELETE all database data!" -ForegroundColor Red
    $confirm = Read-Host "Type 'YES' to confirm"
    if ($confirm -ne "YES") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }

    Write-Host "Stopping container and removing volumes..." -ForegroundColor Yellow
    docker-compose -f $composeFile down -v
} else {
    Write-Host "Stopping container (data preserved)..." -ForegroundColor Yellow
    docker-compose -f $composeFile down
}

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "Container stopped." -ForegroundColor Green
    if (-not $RemoveVolumes) {
        Write-Host "  Data is preserved. Run Start-OracleDocker.ps1 to restart." -ForegroundColor Gray
    }
} else {
    Write-Host "ERROR: Failed to stop container." -ForegroundColor Red
    exit 1
}
