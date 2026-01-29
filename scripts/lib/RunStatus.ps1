<#
.SYNOPSIS
    RunStatus library for tracking script execution diagnostics.

.DESCRIPTION
    Manages the creation and updates of run-status.json for operational monitoring.
    Tracks step execution, timing, errors, and provides clear exit code diagnostics.

.EXAMPLE
    Import-Module .\RunStatus.ps1
    $statusPath = New-RunStatus -OutDir ".\out" -ScriptName "dashboard-task.ps1"
    Set-RunStatusStep -StatusPath $statusPath -StepName "Initialize" -Status "completed"
    Complete-RunStatus -StatusPath $statusPath -Status "success" -ExitCode 0
#>

function New-RunStatus {
    <#
    .SYNOPSIS
        Creates a new run-status.json file.

    .PARAMETER OutDir
        Base output directory where json/ subdirectory will be created.

    .PARAMETER ScriptName
        Name of the script being executed (e.g., "dashboard-task.ps1").

    .PARAMETER SchemaVersion
        Schema version for the run-status format (default: "1.0.0").

    .OUTPUTS
        Returns the absolute path to the created run-status.json file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutDir,

        [Parameter(Mandatory=$true)]
        [string]$ScriptName,

        [string]$SchemaVersion = "1.0.0"
    )

    $ErrorActionPreference = "Stop"

    $jsonDir = Join-Path $OutDir "json"
    if (-not (Test-Path $jsonDir)) {
        New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null
    }

    $statusPath = Join-Path $jsonDir "run-status.json"

    # Get cross-platform host information
    $machineName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { hostname }
    $userName = if ($env:USERNAME) { $env:USERNAME } else { $env:USER }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

    $status = [ordered]@{
        schemaVersion = $SchemaVersion
        scriptName    = $ScriptName
        startedAt     = $timestamp
        host          = [ordered]@{
            machineName = $machineName
            user        = $userName
            psVersion   = $PSVersionTable.PSVersion.ToString()
        }
        steps         = @()
        durations     = [ordered]@{}
        status        = $null
        exitCode      = $null
        topError      = $null
        logFile       = $null
        completedAt   = $null
    }

    $status | ConvertTo-Json -Depth 10 | Set-Content -Path $statusPath -Encoding UTF8
    Write-Output $statusPath
}

function Convert-RunStatusTimestamp {
    <#
    .SYNOPSIS
        Parses run-status timestamps with or without milliseconds.
    #>
    param(
        [object]$Value
    )

    if ($Value -is [DateTime]) {
        return $Value.ToUniversalTime()
    }

    if ([string]::IsNullOrWhiteSpace([string]$Value)) {
        return [DateTime]::MinValue
    }

    $formats = @(
        "yyyy-MM-ddTHH:mm:ss.fffZ",
        "yyyy-MM-ddTHH:mm:ssZ"
    )

    foreach ($format in $formats) {
        $parsed = [DateTime]::MinValue
        if ([DateTime]::TryParseExact(
                [string]$Value,
                $format,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AdjustToUniversal,
                [ref]$parsed)) {
            return $parsed
        }
    }

    return [DateTime]::Parse([string]$Value).ToUniversalTime()
}

function Set-RunStatusStep {
    <#
    .SYNOPSIS
        Updates or adds a step in run-status.json.

    .PARAMETER StatusPath
        Absolute path to the run-status.json file.

    .PARAMETER StepName
        Name of the step (PascalCase, e.g., "Initialize", "EnvironmentChecks").

    .PARAMETER Status
        Step status: "pending", "running", "completed", "failed", or "skipped".

    .PARAMETER Error
        Error message if step failed (optional).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$StatusPath,

        [Parameter(Mandatory=$true)]
        [string]$StepName,

        [Parameter(Mandatory=$true)]
        [ValidateSet("pending","running","completed","failed","skipped")]
        [string]$Status,

        [string]$Error = $null
    )

    $ErrorActionPreference = "Stop"

    if (-not (Test-Path $StatusPath)) {
        throw "Run status file not found at $StatusPath"
    }

    $content = Get-Content -Path $StatusPath -Raw | ConvertFrom-Json

    # Find existing step or create new one
    $step = $content.steps | Where-Object { $_.name -eq $StepName } | Select-Object -First 1

    if ($null -eq $step) {
        # Create new step
        $step = [ordered]@{
            name        = $StepName
            status      = $Status
            startedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            completedAt = $null
            durationMs  = $null
            error       = $Error
        }
        $content.steps += $step
    } else {
        # Update existing step
        $stepIndex = [array]::IndexOf($content.steps.name, $StepName)
        $content.steps[$stepIndex].status = $Status

        if ($Error) {
            $content.steps[$stepIndex].error = $Error
        }

        # Calculate duration if completing or failing
        if ($Status -eq "completed" -or $Status -eq "failed") {
            $completedAt = (Get-Date).ToUniversalTime()
            $content.steps[$stepIndex].completedAt = $completedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

            # Calculate duration from startedAt
            $startedAt = Convert-RunStatusTimestamp -Value $content.steps[$stepIndex].startedAt
            $durationMs = [int](($completedAt - $startedAt).TotalMilliseconds)
            if ($durationMs -lt 0) {
                $durationMs = 0
            }
            $content.steps[$stepIndex].durationMs = $durationMs

            # Update durations map
            $durationKey = $StepName.Substring(0,1).ToLower() + $StepName.Substring(1) + "Ms"
            $content.durations | Add-Member -MemberType NoteProperty -Name $durationKey -Value $durationMs -Force
        }
    }

    # Write back to file
    $content | ConvertTo-Json -Depth 10 | Set-Content -Path $StatusPath -Encoding UTF8
}

function Complete-RunStatus {
    <#
    .SYNOPSIS
        Finalizes the run-status.json file with overall status and exit code.

    .PARAMETER StatusPath
        Absolute path to the run-status.json file.

    .PARAMETER Status
        Overall run status: "success", "failed", or "partial".

    .PARAMETER ExitCode
        Process exit code (0, 1, 2, or 3).

    .PARAMETER TopError
        First critical error message for quick diagnosis (optional).

    .PARAMETER LogFile
        Absolute path to the detailed log file (optional).
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$StatusPath,

        [Parameter(Mandatory=$true)]
        [ValidateSet("success","failed","partial")]
        [string]$Status,

        [Parameter(Mandatory=$true)]
        [int]$ExitCode,

        [string]$TopError = $null,

        [string]$LogFile = $null
    )

    $ErrorActionPreference = "Stop"

    if (-not (Test-Path $StatusPath)) {
        throw "Run status file not found at $StatusPath"
    }

    $content = Get-Content -Path $StatusPath -Raw | ConvertFrom-Json

    # Set final status fields
    $content.status = $Status
    $content.exitCode = $ExitCode
    $content.topError = $TopError
    $content.logFile = $LogFile
    $completedAt = (Get-Date).ToUniversalTime()
    $content.completedAt = $completedAt.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")

    # Calculate total duration
    $startedAt = Convert-RunStatusTimestamp -Value $content.startedAt
    $totalMs = [int](($completedAt - $startedAt).TotalMilliseconds)
    if ($totalMs -lt 0) {
        $totalMs = 0
    }
    $content.durations | Add-Member -MemberType NoteProperty -Name "totalMs" -Value $totalMs -Force

    # Write back to file
    $content | ConvertTo-Json -Depth 10 | Set-Content -Path $StatusPath -Encoding UTF8
}
