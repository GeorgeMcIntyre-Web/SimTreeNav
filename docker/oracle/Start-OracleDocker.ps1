# Start-OracleDocker.ps1
# Starts the local Oracle 12c Docker container for Tecnomatix development
#
# Usage:
#   .\Start-OracleDocker.ps1                  # Normal start
#   .\Start-OracleDocker.ps1 -Force           # Force recreate container
#   .\Start-OracleDocker.ps1 -SkipHealthWait  # Don't wait for Oracle to be ready

param(
    [switch]$Force,
    [switch]$SkipHealthWait,
    [int]$TimeoutSeconds = 600
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeFile = Join-Path $scriptDir "docker-compose.yml"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Oracle 12c Tecnomatix - Docker Container" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker is running
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Docker is not running. Please start Docker Desktop." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "ERROR: Docker is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

# Check if container already exists
$containerStatus = docker ps -a --filter "name=oracle-tecnomatix-12c" --format "{{.Status}}" 2>$null

if ($containerStatus) {
    if ($containerStatus -match "Up") {
        if ($Force) {
            Write-Host "Forcing container recreation..." -ForegroundColor Yellow
        } else {
            Write-Host "Container is already running." -ForegroundColor Green
            Write-Host "  Use -Force to recreate." -ForegroundColor Gray
            docker ps --filter "name=oracle-tecnomatix-12c" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
            exit 0
        }
    } else {
        Write-Host "Container exists but is stopped. Starting..." -ForegroundColor Yellow
    }
}

# Start the container
Write-Host ""
Write-Host "Starting Oracle 12c container..." -ForegroundColor Yellow

if ($Force) {
    docker-compose -f $composeFile up -d --force-recreate
} else {
    docker-compose -f $composeFile up -d
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to start container." -ForegroundColor Red
    Write-Host "  Have you logged into Oracle Container Registry?" -ForegroundColor Yellow
    Write-Host "  Run: docker login container-registry.oracle.com" -ForegroundColor Yellow
    exit 1
}

if ($SkipHealthWait) {
    Write-Host ""
    Write-Host "Container started (health check skipped)." -ForegroundColor Green
    exit 0
}

# Wait for Oracle to be healthy
Write-Host ""
Write-Host "Waiting for Oracle to initialize..." -ForegroundColor Yellow
Write-Host "  (First startup creates the database - this can take 10-15 minutes)" -ForegroundColor Gray
Write-Host ""

$elapsed = 0
$checkInterval = 15

while ($elapsed -lt $TimeoutSeconds) {
    $health = docker inspect --format='{{.State.Health.Status}}' oracle-tecnomatix-12c 2>$null

    if ($health -eq "healthy") {
        Write-Host ""
        Write-Host "Oracle 12c is READY!" -ForegroundColor Green
        Write-Host ""
        Write-Host "  Connection Details:" -ForegroundColor Cyan
        Write-Host "    Host:     localhost" -ForegroundColor White
        Write-Host "    Port:     1521" -ForegroundColor White
        Write-Host "    SID:      EMS12" -ForegroundColor White
        Write-Host "    SYS pwd:  (see docker/oracle/.env)" -ForegroundColor White
        Write-Host "    EM URL:   https://localhost:5500/em" -ForegroundColor White
        Write-Host ""
        Write-Host "  TNS Name:   ORACLE_LOCAL" -ForegroundColor Cyan
        Write-Host "  Connect:    sqlplus sys/password@ORACLE_LOCAL as sysdba" -ForegroundColor Gray
        exit 0
    }

    $statusChar = switch ($health) {
        "starting" { "[STARTING]" }
        "unhealthy" { "[CHECKING]" }
        default { "[WAITING]" }
    }

    $mins = [math]::Floor($elapsed / 60)
    $secs = $elapsed % 60
    Write-Host "  $statusChar ${mins}m ${secs}s elapsed..." -ForegroundColor Gray

    Start-Sleep -Seconds $checkInterval
    $elapsed += $checkInterval
}

Write-Host ""
Write-Host "WARNING: Timeout waiting for Oracle to be ready." -ForegroundColor Yellow
Write-Host "  The container may still be initializing. Check logs:" -ForegroundColor Gray
Write-Host "    docker logs oracle-tecnomatix-12c --tail 50" -ForegroundColor Gray
exit 1
