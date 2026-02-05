# CredentialManager.ps1
# Central credential management for database connections
# Supports DEV (encrypted file) and PROD (Windows Credential Manager) modes

<#
.SYNOPSIS
    Manages database credentials securely with DEV/PROD modes.

.DESCRIPTION
    DEV Mode: Encrypts credentials to file (user-specific encryption key)
              - Never prompts for password during development
              - Credentials stored in config/.credentials (gitignored)

    PROD Mode: Uses Windows Credential Manager
               - Secure, auditable credential storage
               - Integrated with Windows security
               - Suitable for production deployments

.EXAMPLE
    # Get credentials (auto-detects mode)
    $cred = Get-DbCredential -TNSName "SIEMENS_PS_DB"

    # Get connection string
    $connStr = Get-DbConnectionString -TNSName "SIEMENS_PS_DB" -AsSysDBA
#>

# Get current database target (LOCAL or REMOTE)
function Get-DatabaseTarget {
    <#
    .SYNOPSIS
        Gets the current database target from database-target.json.
    .DESCRIPTION
        Returns the configured target (LOCAL/REMOTE) and its TNS name.
        If no target is configured, defaults to REMOTE (SIEMENS_PS_DB).
    .EXAMPLE
        $target = Get-DatabaseTarget
        Write-Host "Using: $($target.TNSName)"
    #>

    $targetFile = Join-Path $PSScriptRoot "..\..\..\config\database-target.json"

    if (Test-Path $targetFile) {
        try {
            $target = Get-Content $targetFile -Raw | ConvertFrom-Json
            return $target
        } catch {
            Write-Warning "Failed to read database-target.json: $_"
        }
    }

    # Default to REMOTE if no target configured
    return [PSCustomObject]@{
        Target  = "REMOTE"
        TNSName = "SIEMENS_PS_DB"
    }
}

# Get TNS name based on configured database target
function Get-DefaultTNSName {
    <#
    .SYNOPSIS
        Returns the TNS name based on the active database target.
    .DESCRIPTION
        LOCAL target: returns ORACLE_LOCAL
        REMOTE target: returns SIEMENS_PS_DB
    .EXAMPLE
        $tns = Get-DefaultTNSName
    #>

    $target = Get-DatabaseTarget
    return $target.TNSName
}

# Determine environment mode
function Get-EnvironmentMode {
    <#
    .SYNOPSIS
        Detects whether running in DEV or PROD mode.
    #>

    $configFile = Join-Path $PSScriptRoot "..\..\..\config\credential-config.json"

    if (Test-Path $configFile) {
        try {
            $config = Get-Content $configFile -Raw | ConvertFrom-Json
            return $config.Mode
        } catch {
            Write-Warning "Failed to read credential-config.json: $_"
        }
    }

    # Default to DEV if config not found
    return "DEV"
}

# Get default username based on environment mode
function Get-DefaultUsername {
    <#
    .SYNOPSIS
        Gets the default username based on environment mode and configuration.
    .DESCRIPTION
        DEV mode: Returns 'sys' (development with SYSDBA)
        PROD mode: Returns 'simtreenav_readonly' (production read-only user)
        Can be overridden in credential-config.json
    #>

    $configFile = Join-Path $PSScriptRoot "..\..\..\config\credential-config.json"

    if (Test-Path $configFile) {
        try {
            $config = Get-Content $configFile -Raw | ConvertFrom-Json

            # Check for explicit username in config
            if ($config.Username) {
                return $config.Username
            }

            # Check if SYSDBA is disabled (production safety)
            if ($config.UseSysDBA -eq $false) {
                return "simtreenav_readonly"
            }

            # Mode-based default
            if ($config.Mode -eq "PROD") {
                return "simtreenav_readonly"
            }
        } catch {
            Write-Warning "Failed to read credential-config.json: $_"
        }
    }

    # Default to sys for DEV mode
    return "sys"
}

# Get encrypted credential file path
function Get-CredentialFilePath {
    <#
    .SYNOPSIS
        Returns path to encrypted credentials file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName
    )

    $credDir = Join-Path $PSScriptRoot "..\..\..\config\.credentials"

    # Create directory if it doesn't exist
    if (-not (Test-Path $credDir)) {
        New-Item -ItemType Directory -Path $credDir -Force | Out-Null
    }

    # Use machine name + username + TNS name for unique file
    $fileName = "$($env:COMPUTERNAME)_$($env:USERNAME)_$TNSName.xml"
    return Join-Path $credDir $fileName
}

# Save credentials to encrypted file (DEV mode)
function Save-CredentialToFile {
    <#
    .SYNOPSIS
        Saves credentials to encrypted file using Windows Data Protection API.
    .DESCRIPTION
        Uses ConvertFrom-SecureString which encrypts using current user's Windows account.
        Only the same user on the same machine can decrypt.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [Parameter(Mandatory=$true)]
        [PSCredential]$Credential
    )

    $credFile = Get-CredentialFilePath -TNSName $TNSName

    try {
        # Export credential object (SecureString is automatically encrypted)
        $Credential | Export-Clixml -Path $credFile -Force

        Write-Host "Success: Credentials saved securely to encrypted file" -ForegroundColor Green
        Write-Host "  Location: $credFile" -ForegroundColor Gray
        return $true
    } catch {
        Write-Warning "Failed to save credentials to file: $_"
        return $false
    }
}

# Load credentials from encrypted file (DEV mode)
function Get-CredentialFromFile {
    <#
    .SYNOPSIS
        Loads credentials from encrypted file.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName
    )

    $credFile = Get-CredentialFilePath -TNSName $TNSName

    if (-not (Test-Path $credFile)) {
        return $null
    }

    try {
        $credential = Import-Clixml -Path $credFile
        return $credential
    } catch {
        Write-Warning "Failed to load credentials from file: $_"
        return $null
    }
}

# Save credentials to Windows Credential Manager (PROD mode)
function Save-CredentialToManager {
    <#
    .SYNOPSIS
        Saves credentials to Windows Credential Manager.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [Parameter(Mandatory=$true)]
        [PSCredential]$Credential
    )

    try {
        # Target name format: SimTreeNav_<TNSName>
        $targetName = "SimTreeNav_$TNSName"

        # Convert SecureString to plain text for Windows Credential Manager API
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password)
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

        # Use cmdkey utility (built into Windows)
        $cmdkeyArgs = "/generic:$targetName /user:$($Credential.UserName) /pass:$plainPassword"
        $result = Start-Process "cmdkey" -ArgumentList $cmdkeyArgs -NoNewWindow -Wait -PassThru

        # Clear plain password from memory
        $plainPassword = $null
        [System.GC]::Collect()

        if ($result.ExitCode -eq 0) {
            Write-Host "Success: Credentials saved to Windows Credential Manager" -ForegroundColor Green
            Write-Host "  Target: $targetName" -ForegroundColor Gray
            return $true
        } else {
            Write-Warning "Failed to save credentials to Windows Credential Manager"
            return $false
        }
    } catch {
        Write-Warning "Failed to save credentials to Windows Credential Manager: $_"
        return $false
    }
}

# Load credentials from Windows Credential Manager (PROD mode)
function Get-CredentialFromManager {
    <#
    .SYNOPSIS
        Loads credentials from Windows Credential Manager.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName
    )

    try {
        $targetName = "SimTreeNav_$TNSName"

        # Query credential using cmdkey
        $cmdkeyArgs = "/list:$targetName"
        $result = cmdkey $cmdkeyArgs 2>&1

        if ($result -match "Target: $targetName") {
            # Extract username from cmdkey output
            if ($result -match "User:\s*(.+)") {
                $username = $matches[1].Trim()

                # Unfortunately, cmdkey can't retrieve passwords, only validate they exist
                # We'll need to use .NET CredentialManager or prompt once
                # For now, return username and indicate password is in credential manager

                Write-Host "  Found credentials in Windows Credential Manager" -ForegroundColor Gray
                Write-Host "  Target: $targetName | User: $username" -ForegroundColor Gray

                # Return marker that indicates we should use credential manager
                return [PSCustomObject]@{
                    UserName = $username
                    UseCredentialManager = $true
                    TargetName = $targetName
                }
            }
        }

        return $null
    } catch {
        return $null
    }
}

# Main function: Get database credentials
function Get-DbCredential {
    <#
    .SYNOPSIS
        Gets database credentials using current environment mode.
    .DESCRIPTION
        DEV Mode: Loads from encrypted file, prompts once if not found
        PROD Mode: Loads from Windows Credential Manager, prompts once if not found
    .PARAMETER TNSName
        The TNS name for the database connection
    .PARAMETER Username
        Optional: Override default username (default: sys)
    .PARAMETER ForcePrompt
        Force credential prompt even if cached credentials exist
    .EXAMPLE
        $cred = Get-DbCredential -TNSName "SIEMENS_PS_DB"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [string]$Username = "sys",

        [switch]$ForcePrompt
    )

    $mode = Get-EnvironmentMode

    # Try to load existing credentials
    if (-not $ForcePrompt) {
        if ($mode -eq "DEV") {
            $credential = Get-CredentialFromFile -TNSName $TNSName
            if ($credential) {
                Write-Host "Success: Using cached credentials (DEV mode)" -ForegroundColor Green
                return $credential
            }
        } elseif ($mode -eq "PROD") {
            $credInfo = Get-CredentialFromManager -TNSName $TNSName
            if ($credInfo) {
                # For PROD mode, we return the credential info
                # The connection string builder will use cmdkey credentials
                return $credInfo
            }
        }
    }

    # Prompt for credentials
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Database Credentials Required" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Mode: $mode" -ForegroundColor Gray
    Write-Host "TNS:  $TNSName" -ForegroundColor Gray
    Write-Host ""

    if ($mode -eq "DEV") {
        Write-Host "DEV Mode: Credentials will be encrypted and saved locally." -ForegroundColor Yellow
        Write-Host "          You won't be prompted again on this machine." -ForegroundColor Yellow
    } else {
        Write-Host "PROD Mode: Credentials will be saved to Windows Credential Manager." -ForegroundColor Yellow
    }
    Write-Host ""

    $credential = Get-Credential -UserName $Username -Message "Enter password for $TNSName"

    if (-not $credential) {
        Write-Host "Error: No credentials provided" -ForegroundColor Red
        return $null
    }

    # Save credentials based on mode
    if ($mode -eq "DEV") {
        Save-CredentialToFile -TNSName $TNSName -Credential $credential | Out-Null
    } elseif ($mode -eq "PROD") {
        Save-CredentialToManager -TNSName $TNSName -Credential $credential | Out-Null
    }

    return $credential
}

# Build connection string from credentials
function Get-DbConnectionString {
    <#
    .SYNOPSIS
        Builds database connection string with credentials.
    .DESCRIPTION
        Auto-detects username based on environment mode:
        - DEV mode: Uses 'sys' with SYSDBA (default)
        - PROD mode: Uses 'simtreenav_readonly' (read-only, no SYSDBA)

        Override with -Username parameter or credential-config.json
    .PARAMETER TNSName
        The TNS name for the database connection
    .PARAMETER Username
        Optional: Override default username (auto-detected from mode if not specified)
    .PARAMETER AsSysDBA
        Connect as SYSDBA (only works with sys or DBA users)
    .PARAMETER ForcePrompt
        Force credential prompt even if cached credentials exist
    .EXAMPLE
        # Auto-detect TNS from database target (LOCAL/REMOTE)
        $connStr = Get-DbConnectionString -AsSysDBA

    .EXAMPLE
        # DEV mode (auto-uses sys with SYSDBA)
        $connStr = Get-DbConnectionString -TNSName "SIEMENS_PS_DB" -AsSysDBA

    .EXAMPLE
        # PROD mode (auto-uses simtreenav_readonly, no SYSDBA)
        $connStr = Get-DbConnectionString -TNSName "SIEMENS_PS_DB"

    .EXAMPLE
        # Explicit username override
        $connStr = Get-DbConnectionString -TNSName "SIEMENS_PS_DB" -Username "simtreenav_readonly"
    #>
    param(
        [Parameter(Mandatory=$false)]
        [string]$TNSName,

        [string]$Username,  # Now optional - auto-detected

        [switch]$AsSysDBA,

        [switch]$ForcePrompt
    )

    # Auto-detect TNS name from database target if not provided
    if (-not $TNSName) {
        $TNSName = Get-DefaultTNSName
        $target = Get-DatabaseTarget
        Write-Host "  Auto-detected database target: $($target.Target) ($TNSName)" -ForegroundColor Gray
    }

    # Auto-detect username if not provided
    if (-not $Username) {
        $Username = Get-DefaultUsername
        Write-Host "  Auto-detected username: $Username" -ForegroundColor Gray
    }

    # Check for SYSDBA with non-sys users (security warning)
    if ($AsSysDBA -and $Username -ne "sys") {
        Write-Warning "Attempting to use SYSDBA with user '$Username'. This may fail if user lacks SYSDBA privileges."
    }

    # PROD mode security check: Warn if using sys in production
    $mode = Get-EnvironmentMode
    if ($mode -eq "PROD" -and $Username -eq "sys") {
        Write-Warning "Using 'sys' account in PROD mode. Consider using 'simtreenav_readonly' for better security."
        Write-Host "  To switch: Initialize-DbCredentials.ps1 -Username simtreenav_readonly" -ForegroundColor Gray
    }

    $credential = Get-DbCredential -TNSName $TNSName -Username $Username -ForcePrompt:$ForcePrompt

    if (-not $credential) {
        throw "Failed to retrieve credentials for $TNSName"
    }

    # Handle PROD mode with credential manager
    if ($credential.UseCredentialManager) {
        # For Windows Credential Manager, we still need the password
        # This is a limitation - we'll need to prompt once per session
        Write-Host "  Note: Password from Credential Manager needs to be entered once per session" -ForegroundColor Gray
        $securePassword = Read-Host "Enter password for $($credential.UserName)" -AsSecureString
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    } else {
        # Convert SecureString to plain text for connection string
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        $Username = $credential.UserName
    }

    # Build connection string
    if ($AsSysDBA) {
        $connectionString = "$Username/$password@$TNSName AS SYSDBA"
    } else {
        $connectionString = "$Username/$password@$TNSName"
    }

    return $connectionString
}

# Test credentials
function Test-DbCredential {
    <#
    .SYNOPSIS
        Tests if database credentials are working.
    .PARAMETER TNSName
        The TNS name for the database connection
    .EXAMPLE
        Test-DbCredential -TNSName "SIEMENS_PS_DB"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName
    )

    try {
        $connStr = Get-DbConnectionString -TNSName $TNSName -AsSysDBA

        # Create test SQL file
        $testFile = "test-cred-$([guid]::NewGuid()).sql"
        $testQuery = @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING OFF
SELECT 'OK' FROM DUAL;
EXIT;
"@
        $testQuery | Out-File $testFile -Encoding UTF8

        # Test connection
        $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"
        $result = sqlplus -S $connStr "@$testFile" 2>&1

        Remove-Item $testFile -ErrorAction SilentlyContinue

        if ($result -match "OK") {
            Write-Host "Success: Credentials are valid and working" -ForegroundColor Green
            return $true
        } else {
            Write-Host "Error: Credentials test failed" -ForegroundColor Red
            return $false
        }
    } catch {
        Write-Host "Error: Error testing credentials: $_" -ForegroundColor Red
        return $false
    }
}

# Functions are automatically available when imported with Import-Module
