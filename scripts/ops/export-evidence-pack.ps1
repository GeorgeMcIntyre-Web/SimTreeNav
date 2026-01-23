<#
.SYNOPSIS
    STUB: Exports evidence pack (zip + manifest).
    NOTE: This is a Phase 2 STUB. It currently does nothing but log and exit.

.DESCRIPTION
    Intended to zip up current state with manifest.
    Will exit with code 1 (Not Implemented) until Phase 2 Execution.

.PARAMETER OutDir
    Base output directory.

.PARAMETER LogDir
    Directory for log files. Defaults to OutDir\logs.

.PARAMETER RunId
    Specific RunId to export.

.PARAMETER Smoke
    Run a quick syntax/sanity check and exit 0.

.EXAMPLE
    .\export-evidence-pack.ps1 -OutDir "C:\SimTreeNav\out" -Smoke
#>

param(
    [Parameter(Position=0)]
    [string]$OutDir = ".\out",

    [Parameter(Position=1)]
    [string]$LogDir,

    [string]$RunId,

    [switch]$Smoke
)

$ErrorActionPreference = "Stop"

# Setup Logging
if ([string]::IsNullOrWhiteSpace($LogDir)) {
    $LogDir = Join-Path $OutDir "logs"
}

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

$LogFile = Join-Path $LogDir "export-evidence-pack.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log {
    param([string]$Message)
    $LogMsg = "[$Timestamp] $Message"
    Write-Output $LogMsg
    Add-Content -Path $LogFile -Value $LogMsg
}

Write-Log "Starting export-evidence-pack stub..."
Write-Log "Parameters: OutDir='$OutDir', LogDir='$LogDir', Smoke=$Smoke"

if ($Smoke) {
    Write-Log "Running Smoke Test..."
    
    # 1. Check OutDir
    if (-not (Test-Path $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
        Write-Log "Smoke: Created OutDir '$OutDir'"
    } else {
        Write-Log "Smoke: OutDir '$OutDir' exists"
    }

    # 2. Check LogDir
    if (-not (Test-Path $LogDir)) {
        Write-Log "Smoke: FAIL - LogDir '$LogDir' was not created by setup block"
        exit 1
    } else {
        Write-Log "Smoke: LogDir '$LogDir' exists"
    }

    Write-Log "Smoke test passed. Exiting 0."
    exit 0
}

Write-Log "FAIL: Feature not implemented yet (Phase 2 Stub)."
Write-Error "Feature not implemented yet (Phase 2 Stub)." -ErrorAction Continue
exit 1
