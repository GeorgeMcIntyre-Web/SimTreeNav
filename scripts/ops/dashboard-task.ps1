<#
.SYNOPSIS
    Orchestrates the daily dashboard generation task.
    Wraps 'generate-management-dashboard.ps1' with logging, config validation, and error handling.

.PARAMETER Config
    Path to the JSON configuration file.

.PARAMETER DryRun
    If set, runs in dry-run mode (no data changes, no email).

.PARAMETER OutDir
    Base output directory.

.PARAMETER Smoke
    Run a quick syntax/sanity check and exit 0.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$Config,
    
    [switch]$DryRun,
    
    [string]$OutDir = "..\..\out",

    [switch]$Smoke
)

$ErrorActionPreference = "Stop"
$ScriptRoot = Split-Path $MyInvocation.MyCommand.Path

# 1. Setup Logging
$LogDir = Join-Path $OutDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "dashboard-task.log"
$Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log {
    param([string]$Message, [string]$Level="INFO")
    $LogMsg = "[$Timestamp] [$Level] $Message"
    Write-Output $LogMsg
    Add-Content -Path $LogFile -Value $LogMsg
}

# 2. Smoke Test
if ($Smoke) {
    Write-Log "Running Smoke Test..."
    if (-not (Test-Path $ScriptRoot)) { 
        Write-Log "FAIL: ScriptRoot not found" "ERROR"
        exit 1 
    }
    Write-Log "Smoke Test Passed"
    exit 0
}

try {
    Write-Log "Starting Dashboard Task"
    
    # 3. Validation
    if (-not [string]::IsNullOrWhiteSpace($Config)) {
        if (-not (Test-Path $Config)) {
            Write-Log "Config file not found: $Config" "ERROR"
            exit 1
        }
        Write-Log "Using Config: $Config"
    } else {
        Write-Log "No Config specified, using defaults"
    }

    # 4. Call Generator
    $GeneratorScript = Join-Path $ScriptRoot "..\generate-management-dashboard.ps1"
    if (-not (Test-Path $GeneratorScript)) {
        Write-Log "Generator script not found at $GeneratorScript" "ERROR"
        exit 1
    }

    Write-Log "Invoking dashboard generation..."
    
    $ArgsList = @("-OutDir", $OutDir)
    if ($DryRun) { $ArgsList += "-DryRun" }
    
    # Execute
    & $GeneratorScript @ArgsList
    if ($LASTEXITCODE -ne 0) {
        throw "Generator script exited with code $LASTEXITCODE"
    }

    Write-Log "Dashboard Task Completed Successfully"
    exit 0

} catch {
    Write-Log "Task Failed: $_" "ERROR"
    exit 1
}
