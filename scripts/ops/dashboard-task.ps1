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

# Import libraries
. "$ScriptRoot\..\lib\RunStatus.ps1"
. "$ScriptRoot\..\lib\EnvChecks.ps1"

# 1. Setup Logging
$LogDir = Join-Path $OutDir "logs"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir "dashboard-task.log"

function Write-Log {
    param([string]$Message, [string]$Level="INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
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

# STEP 1: Initialize
$statusPath = $null
try {
    Write-Log "Starting Dashboard Task"
    $statusPath = New-RunStatus -OutDir $OutDir -ScriptName "dashboard-task.ps1" -SchemaVersion "1.0.0"
    Set-RunStatusStep -StatusPath $statusPath -StepName "Initialize" -Status "completed"
} catch {
    Write-Log "Initialization failed: $_" "ERROR"
    exit 3  # Unknown error (couldn't create status file)
}

# STEP 2: EnvironmentChecks
Set-RunStatusStep -StatusPath $statusPath -StepName "EnvironmentChecks" -Status "running"
try {
    $psCheck = Test-PowerShellVersion -MinMajorVersion 7
    if (-not $psCheck.Sufficient) {
        throw "PowerShell $($psCheck.Current) insufficient. Requires 7+"
    }

    $sqlCheck = Test-SqlPlusAvailable
    if (-not $sqlCheck.Available) {
        throw "SQL*Plus not found: $($sqlCheck.Error)"
    }

    $outCheck = Test-OutDirWritable -OutDir $OutDir
    if (-not $outCheck.Writable) {
        throw "Output directory not writable: $($outCheck.Error)"
    }

    Write-Log "Environment checks passed"
    Set-RunStatusStep -StatusPath $statusPath -StepName "EnvironmentChecks" -Status "completed"
} catch {
    Write-Log "Environment check failed: $_" "ERROR"
    Set-RunStatusStep -StatusPath $statusPath -StepName "EnvironmentChecks" -Status "failed" -Error $_.ToString()
    Complete-RunStatus -StatusPath $statusPath -Status "failed" -ExitCode 2 -TopError $_.ToString() -LogFile $LogFile
    exit 2  # Dependency failure
}

# STEP 3: ValidateConfig
Set-RunStatusStep -StatusPath $statusPath -StepName "ValidateConfig" -Status "running"
try {
    if (-not [string]::IsNullOrWhiteSpace($Config)) {
        if (-not (Test-Path $Config)) {
            throw "Config file not found: $Config"
        }
        Write-Log "Using Config: $Config"
    } else {
        Write-Log "No Config specified, using defaults"
    }
    Set-RunStatusStep -StatusPath $statusPath -StepName "ValidateConfig" -Status "completed"
} catch {
    Write-Log "Config validation failed: $_" "ERROR"
    Set-RunStatusStep -StatusPath $statusPath -StepName "ValidateConfig" -Status "failed" -Error $_.ToString()
    Complete-RunStatus -StatusPath $statusPath -Status "failed" -ExitCode 1 -TopError $_.ToString() -LogFile $LogFile
    exit 1
}

# STEP 4: GenerateDashboard
Set-RunStatusStep -StatusPath $statusPath -StepName "GenerateDashboard" -Status "running"
try {
    $GeneratorScript = Join-Path $ScriptRoot "..\generate-management-dashboard.ps1"
    if (-not (Test-Path $GeneratorScript)) {
        throw "Generator script not found at $GeneratorScript"
    }

    Write-Log "Invoking dashboard generation..."
    $ArgsList = @("-OutDir", $OutDir)
    if ($DryRun) { $ArgsList += "-DryRun" }

    & $GeneratorScript @ArgsList
    if ($LASTEXITCODE -ne 0) {
        throw "Generator script exited with code $LASTEXITCODE"
    }

    Write-Log "Dashboard generation completed"
    Set-RunStatusStep -StatusPath $statusPath -StepName "GenerateDashboard" -Status "completed"
} catch {
    Write-Log "Dashboard generation failed: $_" "ERROR"
    Set-RunStatusStep -StatusPath $statusPath -StepName "GenerateDashboard" -Status "failed" -Error $_.ToString()
    Complete-RunStatus -StatusPath $statusPath -Status "failed" -ExitCode 1 -TopError $_.ToString() -LogFile $LogFile
    exit 1
}

# STEP 5: Finalize
try {
    Write-Log "Dashboard Task Completed Successfully"
    Complete-RunStatus -StatusPath $statusPath -Status "success" -ExitCode 0 -LogFile $LogFile
    exit 0
} catch {
    Write-Log "Finalization warning: $_" "WARNING"
    exit 0  # Don't fail on finalization if work succeeded
}
