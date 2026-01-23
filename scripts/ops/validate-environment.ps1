<#
.SYNOPSIS
    Validates the minimal environment requirements for SimTreeNav production rollout.
    Dry-run safe by default.

.DESCRIPTION
    Checks PowerShell version, folders, time/date, hostname.
    Can optionally check Oracle presence.

.PARAMETER OutDir
    Base output directory to validate/create. Default: ./out

.PARAMETER Smoke
    Run in Smoke Test mode (Exit 0 on success, non-zero on fail, minimal output).

.PARAMETER CheckOracle
    If set, attempts to check for sqlplus or Oracle connection capabilities.

.EXAMPLE
    ./validate-environment.ps1 -OutDir D:\SimTreeNav\out -Smoke
#>

param(
    [string]$OutDir = "./out",
    [switch]$Smoke,
    [switch]$CheckOracle
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level="INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [$Level] $Message"
    Write-Host $logMsg
    if ($global:LogFile) { Add-Content -Path $global:LogFile -Value $logMsg }
}

# Setup Logging
$logDir = Join-Path $OutDir "logs"
if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
$global:LogFile = Join-Path $logDir "validate-env.log"

try {
    Write-Log "Starting Environment Validation..."

    # 1. PowerShell Version
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        throw "PowerShell 7+ is required. Found: $($PSVersionTable.PSVersion)"
    }
    Write-Log "PowerShell Version: $($PSVersionTable.PSVersion.ToString()) [OK]"

    # 2. Paths
    if (-not (Test-Path $OutDir)) {
        Write-Log "Creating output directory: $OutDir"
        New-Item -Path $OutDir -ItemType Directory -Force | Out-Null
    }
    # Check Write Access
    $testFile = Join-Path $OutDir "write_test.tmp"
    "test" | Set-Content -Path $testFile
    if (Test-Path $testFile) {
        Remove-Item $testFile
        Write-Log "Write access to $OutDir [OK]"
    } else {
        throw "Cannot write to $OutDir"
    }

    # 3. Hostname/Time
    $hostname = hostname
    $time = Get-Date
    Write-Log "Hostname: $hostname"
    Write-Log "Server Time: $time"

    # 4. Oracle (Optional)
    if ($CheckOracle) {
        try {
            $sqlplusVersion = sqlplus -version 2>&1
            Write-Log "Oracle Client Found: $sqlplusVersion"
        } catch {
            Write-Log "Oracle Client (sqlplus) not found in PATH." "WARNING"
            if (-not $Smoke) { throw "Oracle Check Failed" }
        }
    }

    Write-Log "Validation Complete. System appears ready."
    exit 0

} catch {
    Write-Log "Validation FAILED: $_" "ERROR"
    exit 1
}
