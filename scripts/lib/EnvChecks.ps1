<#
.SYNOPSIS
    Environment validation library for pre-flight dependency checks.

.DESCRIPTION
    Provides functions to validate system dependencies before script execution.
    Returns structured results with clear error messages for operational troubleshooting.

.EXAMPLE
    Import-Module .\EnvChecks.ps1
    $psCheck = Test-PowerShellVersion -MinMajorVersion 7
    if (-not $psCheck.Sufficient) { throw $psCheck.Error }
#>

function Test-PowerShellVersion {
    <#
    .SYNOPSIS
        Checks if PowerShell version meets minimum requirements.

    .PARAMETER MinMajorVersion
        Minimum required major version (default: 7).

    .OUTPUTS
        Returns PSCustomObject with Sufficient, Current, and Error fields.
    #>
    param(
        [int]$MinMajorVersion = 7
    )

    $ErrorActionPreference = "Stop"

    try {
        $currentVersion = $PSVersionTable.PSVersion
        $sufficient = $currentVersion.Major -ge $MinMajorVersion

        return [PSCustomObject]@{
            Sufficient = $sufficient
            Current    = $currentVersion.ToString()
            Error      = if ($sufficient) { $null } else { "PowerShell $currentVersion is insufficient. Requires version $MinMajorVersion or higher." }
        }
    } catch {
        return [PSCustomObject]@{
            Sufficient = $false
            Current    = "Unknown"
            Error      = "Failed to check PowerShell version: $_"
        }
    }
}

function Test-SqlPlusAvailable {
    <#
    .SYNOPSIS
        Tests if SQL*Plus is available in PATH and executable.

    .OUTPUTS
        Returns PSCustomObject with Available, Version, and Error fields.
    #>
    param()

    $ErrorActionPreference = "Stop"

    try {
        # Try to locate sqlplus.exe
        $sqlplusCmd = Get-Command sqlplus -ErrorAction SilentlyContinue

        if ($null -eq $sqlplusCmd) {
            return [PSCustomObject]@{
                Available = $false
                Version   = $null
                Error     = "SQL*Plus not found in PATH. Ensure Oracle Client is installed."
            }
        }

        # Try to get version (sqlplus -version might not work on all Oracle versions, so we'll just verify it's executable)
        try {
            $versionOutput = & sqlplus -version 2>&1 | Select-Object -First 1
            $version = $versionOutput -replace "SQL\*Plus: Release ", "" -replace " .*", ""
        } catch {
            $version = "Unknown"
        }

        return [PSCustomObject]@{
            Available = $true
            Version   = $version
            Error     = $null
        }
    } catch {
        return [PSCustomObject]@{
            Available = $false
            Version   = $null
            Error     = "Failed to check SQL*Plus availability: $_"
        }
    }
}

function Test-OutDirWritable {
    <#
    .SYNOPSIS
        Tests if output directory is writable.

    .PARAMETER OutDir
        Path to output directory to test.

    .OUTPUTS
        Returns PSCustomObject with Writable and Error fields.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutDir
    )

    $ErrorActionPreference = "Stop"

    try {
        # Create output directory if it doesn't exist
        if (-not (Test-Path $OutDir)) {
            New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
        }

        # Create a test file
        $testFile = Join-Path $OutDir "test-write-$(New-Guid).tmp"

        try {
            # Write test content
            "test" | Set-Content -Path $testFile -Encoding UTF8 -ErrorAction Stop

            # Read back to verify
            $content = Get-Content -Path $testFile -Raw -ErrorAction Stop

            if ($content.Trim() -ne "test") {
                throw "Write verification failed"
            }

            # Clean up test file
            Remove-Item -Path $testFile -Force -ErrorAction SilentlyContinue

            return [PSCustomObject]@{
                Writable = $true
                Error    = $null
            }
        } catch {
            return [PSCustomObject]@{
                Writable = $false
                Error    = "Cannot write to $OutDir : $_"
            }
        }
    } catch {
        return [PSCustomObject]@{
            Writable = $false
            Error    = "Failed to test directory writability: $_"
        }
    }
}

function Test-RequiredPaths {
    <#
    .SYNOPSIS
        Checks if required paths exist and are accessible.

    .PARAMETER Paths
        Array of paths to validate.

    .OUTPUTS
        Returns PSCustomObject with AllExist, MissingPaths, and Error fields.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Paths
    )

    $ErrorActionPreference = "Stop"

    try {
        $missingPaths = @()

        foreach ($path in $Paths) {
            if (-not (Test-Path $path)) {
                $missingPaths += $path
            }
        }

        $allExist = $missingPaths.Count -eq 0

        return [PSCustomObject]@{
            AllExist     = $allExist
            MissingPaths = $missingPaths
            Error        = if ($allExist) { $null } else { "Missing paths: $($missingPaths -join ', ')" }
        }
    } catch {
        return [PSCustomObject]@{
            AllExist     = $false
            MissingPaths = @()
            Error        = "Failed to check required paths: $_"
        }
    }
}
