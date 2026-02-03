<#
.SYNOPSIS
    Oracle Database Helper using Managed DataAccess Driver

.DESCRIPTION
    Provides database connectivity using Oracle.ManagedDataAccess.dll (managed driver)
    No Oracle client installation required - fully self-contained.

.NOTES
    File Name  : DatabaseHelper.ps1
    Author     : Management Dashboard
    Requires   : PowerShell 5.1+, Oracle.ManagedDataAccess.dll in lib/
#>

# Module-level variables
$script:OracleAssemblyLoaded = $false
$script:ConnectionCache = @{}

<#
.SYNOPSIS
    Loads Oracle.ManagedDataAccess.dll assembly

.DESCRIPTION
    Loads the Oracle managed driver DLL from the lib/ directory.
    Only loads once per PowerShell session.

.EXAMPLE
    Initialize-OracleDriver
#>
function Initialize-OracleDriver {
    [CmdletBinding()]
    param()

    # Check if Oracle type is already loaded in .NET
    $typeExists = $null -ne ('Oracle.ManagedDataAccess.Client.OracleConnection' -as [Type])
    if ($typeExists) {
        Write-Verbose "Oracle.ManagedDataAccess already loaded in .NET runtime"
        $script:OracleAssemblyLoaded = $true
        return $true
    }

    if ($script:OracleAssemblyLoaded) {
        Write-Verbose "Oracle.ManagedDataAccess already loaded (cached)"
        return $true
    }

    try {
        # Get project root (3 levels up from utilities/)
        $scriptRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $oracleDllPath = Join-Path $scriptRoot "lib\Oracle.ManagedDataAccess.dll"

        if (-not (Test-Path $oracleDllPath)) {
            throw "Oracle.ManagedDataAccess.dll not found at: $oracleDllPath`nPlease see lib\README.md for setup instructions."
        }

        Write-Verbose "Loading Oracle.ManagedDataAccess.dll from: $oracleDllPath"
        Add-Type -Path $oracleDllPath -ErrorAction Stop

        $script:OracleAssemblyLoaded = $true
        Write-Verbose "Oracle.ManagedDataAccess.dll loaded successfully"
        return $true
    } catch {
        Write-Error "Failed to load Oracle.ManagedDataAccess.dll: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Gets Oracle server configuration

.DESCRIPTION
    Reads server configuration from config/servers.json

.PARAMETER ServerName
    Name of the server (e.g., "PSPDV3"). If not specified, returns default server.

.EXAMPLE
    $config = Get-OracleServerConfig -ServerName "PSPDV3"
#>
function Get-OracleServerConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$ServerName
    )

    try {
        # Get project root (3 levels up from utilities/)
        $scriptRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        $configPath = Join-Path $scriptRoot "config\servers.json"

        if (-not (Test-Path $configPath)) {
            throw "Server configuration not found: $configPath"
        }

        $config = Get-Content $configPath -Raw | ConvertFrom-Json

        if ([string]::IsNullOrWhiteSpace($ServerName)) {
            # Return default server
            $ServerName = $config.defaultServer
        }

        $server = $config.servers | Where-Object { $_.name -eq $ServerName -or $_.tns -eq $ServerName }

        if (-not $server) {
            throw "Server '$ServerName' not found in configuration"
        }

        return $server
    } catch {
        Write-Error "Failed to get server configuration: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Creates Oracle connection string

.DESCRIPTION
    Builds Oracle connection string from server configuration and credentials

.PARAMETER ServerName
    TNS name or server name from config

.PARAMETER Username
    Oracle username (schema name)

.PARAMETER Password
    Oracle password

.PARAMETER UseTnsNames
    If true, uses TNS name directly. If false, builds connection string from host/port/sid.

.PARAMETER DBAPrivilege
    DBA privilege mode: SYSDBA, SYSOPER, or None. Required when connecting as sys.

.EXAMPLE
    $connStr = New-OracleConnectionString -ServerName "PSPDV3" -Username "DESIGN12" -Password "mypass"

.EXAMPLE
    $connStr = New-OracleConnectionString -ServerName "PSPDV3" -Username "sys" -Password "mypass" -DBAPrivilege "SYSDBA"
#>
function New-OracleConnectionString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerName,

        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [Parameter(Mandatory=$false)]
        [switch]$UseTnsNames,

        [Parameter(Mandatory=$false)]
        [ValidateSet("SYSDBA", "SYSOPER", "None")]
        [string]$DBAPrivilege = "None"
    )

    try {
        # Build base connection string
        $connectionString = ""

        if ($UseTnsNames) {
            # Simple TNS names approach with timeout
            $connectionString = "User Id=$Username;Password=$Password;Data Source=$ServerName;Connection Timeout=60"
        } else {
            # Build connection string from server config
            $serverConfig = Get-OracleServerConfig -ServerName $ServerName

            if ($null -eq $serverConfig) {
                throw "Server configuration not found for: $ServerName"
            }

            # Build data source based on SID vs SERVICE_NAME
            if ($serverConfig.PSObject.Properties.Name -contains "sid" -and -not [string]::IsNullOrWhiteSpace($serverConfig.sid)) {
                $dataSource = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$($serverConfig.host))(PORT=$($serverConfig.port)))(CONNECT_DATA=(SID=$($serverConfig.sid))))"
            } elseif ($serverConfig.PSObject.Properties.Name -contains "serviceName" -and -not [string]::IsNullOrWhiteSpace($serverConfig.serviceName)) {
                $dataSource = "(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=$($serverConfig.host))(PORT=$($serverConfig.port)))(CONNECT_DATA=(SERVICE_NAME=$($serverConfig.serviceName))))"
            } else {
                throw "Server configuration must have either 'sid' or 'serviceName'"
            }

            $connectionString = "User Id=$Username;Password=$Password;Data Source=$dataSource;Connection Timeout=60"
        }

        # Add DBA privilege if specified
        if ($DBAPrivilege -ne "None") {
            $connectionString += ";DBA Privilege=$DBAPrivilege"
        }

        return $connectionString
    } catch {
        Write-Error "Failed to create connection string: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Creates Oracle database connection

.DESCRIPTION
    Opens a connection to Oracle database using managed driver

.PARAMETER ServerName
    TNS name or server name from config

.PARAMETER Username
    Oracle username (schema name)

.PARAMETER Password
    Oracle password

.PARAMETER UseTnsNames
    If true, uses TNS name directly from tnsnames.ora

.PARAMETER DBAPrivilege
    DBA privilege mode: SYSDBA, SYSOPER, or None. Required when connecting as sys.

.EXAMPLE
    $conn = New-OracleConnection -ServerName "PSPDV3" -Username "DESIGN12" -Password "mypass"
    $conn.Open()

.EXAMPLE
    $conn = New-OracleConnection -ServerName "PSPDV3" -Username "sys" -Password "mypass" -DBAPrivilege "SYSDBA"
    $conn.Open()
#>
function New-OracleConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$ServerName,

        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [Parameter(Mandatory=$false)]
        [switch]$UseTnsNames,

        [Parameter(Mandatory=$false)]
        [ValidateSet("SYSDBA", "SYSOPER", "None")]
        [string]$DBAPrivilege = "None"
    )

    try {
        # Ensure Oracle driver is loaded
        if (-not (Initialize-OracleDriver)) {
            throw "Failed to initialize Oracle driver"
        }

        # Auto-detect DBAPrivilege if connecting as sys and no privilege specified
        if ($Username -eq "sys" -and $DBAPrivilege -eq "None") {
            Write-Verbose "Auto-detecting SYSDBA privilege for sys user"
            $DBAPrivilege = "SYSDBA"
        }

        $connectionString = New-OracleConnectionString -ServerName $ServerName -Username $Username -Password $Password -UseTnsNames:$UseTnsNames -DBAPrivilege $DBAPrivilege

        if ([string]::IsNullOrWhiteSpace($connectionString)) {
            throw "Failed to create connection string"
        }

        Write-Verbose "Creating Oracle connection to: $ServerName (DBA Privilege: $DBAPrivilege)"
        $connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($connectionString)

        return $connection
    } catch {
        Write-Error "Failed to create Oracle connection: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Executes Oracle SQL query

.DESCRIPTION
    Executes SQL query and returns results as array of PowerShell objects

.PARAMETER Connection
    Open Oracle connection object

.PARAMETER Query
    SQL query to execute

.PARAMETER TimeoutSeconds
    Query timeout in seconds (default: 300)

.EXAMPLE
    $conn = New-OracleConnection -ServerName "PSPDV3" -Username "DESIGN12" -Password "pass"
    $conn.Open()
    $results = Invoke-OracleQuery -Connection $conn -Query "SELECT * FROM COLLECTION_ WHERE ROWNUM <= 10"
    $conn.Close()
#>
function Invoke-OracleQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Oracle.ManagedDataAccess.Client.OracleConnection]$Connection,

        [Parameter(Mandatory=$true)]
        [string]$Query,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 300
    )

    $command = $null
    $reader = $null

    try {
        if ($Connection.State -ne 'Open') {
            throw "Connection is not open"
        }

        Write-Verbose "Executing query (timeout: ${TimeoutSeconds}s)"

        $command = $Connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = $TimeoutSeconds

        $reader = $command.ExecuteReader()

        # Get column names
        $columns = @()
        for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $columns += $reader.GetName($i)
        }

        # Read all rows
        $results = @()
        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $value = $reader.GetValue($i)
                # Handle Oracle DBNull
                if ($value -is [System.DBNull]) {
                    $value = $null
                }
                $row[$columns[$i]] = $value
            }
            $results += [PSCustomObject]$row
        }

        Write-Verbose "Query returned $($results.Count) rows"
        return $results
    } catch {
        Write-Error "Query execution failed: $_"
        Write-Verbose "Query: $Query"
        return $null
    } finally {
        if ($null -ne $reader) {
            $reader.Close()
            $reader.Dispose()
        }
        if ($null -ne $command) {
            $command.Dispose()
        }
    }
}

<#
.SYNOPSIS
    Executes SQL file

.DESCRIPTION
    Reads SQL from file and executes it, handling multiple statements

.PARAMETER Connection
    Open Oracle connection object

.PARAMETER SqlFilePath
    Path to SQL file

.PARAMETER TimeoutSeconds
    Query timeout in seconds (default: 300)

.EXAMPLE
    $conn = New-OracleConnection -ServerName "PSPDV3" -Username "DESIGN12" -Password "pass"
    $conn.Open()
    $results = Invoke-OracleSqlFile -Connection $conn -SqlFilePath "c:\queries\report.sql"
    $conn.Close()
#>
function Invoke-OracleSqlFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Oracle.ManagedDataAccess.Client.OracleConnection]$Connection,

        [Parameter(Mandatory=$true)]
        [string]$SqlFilePath,

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 300
    )

    try {
        if (-not (Test-Path $SqlFilePath)) {
            throw "SQL file not found: $SqlFilePath"
        }

        Write-Verbose "Reading SQL from: $SqlFilePath"
        $sqlContent = Get-Content $SqlFilePath -Raw

        # Remove SQL*Plus specific commands
        $sqlContent = $sqlContent -replace "(?m)^SET\s+.*$", ""
        $sqlContent = $sqlContent -replace "(?m)^SPOOL\s+.*$", ""
        $sqlContent = $sqlContent -replace "(?m)^@.*$", ""

        # Execute query
        return Invoke-OracleQuery -Connection $Connection -Query $sqlContent -TimeoutSeconds $TimeoutSeconds
    } catch {
        Write-Error "Failed to execute SQL file: $_"
        return $null
    }
}

# Functions are automatically exported when dot-sourced or imported
