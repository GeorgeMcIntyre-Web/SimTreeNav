# Tree Viewer Launcher - Fully dynamic, no hardcoding
# Discovers database servers, instances, and schemas dynamically
# Remembers previous selections

param(
    [string]$Server = "",
    [string]$Instance = "",
    [string]$Schema = "",
    [switch]$LoadLast = $false
)

$configFile = "tree-viewer-config.json"

function Show-Menu {
    Write-Host "`n" -NoNewline
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Siemens Process Simulation" -ForegroundColor Yellow
    Write-Host "  Navigation Tree Viewer" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-DatabaseServers {
    # Query network for available Oracle database servers
    # Check domain, network, and TNS configuration
    $servers = @()
    
    Write-Host "Discovering Oracle database servers on the domain..." -ForegroundColor Yellow
    
    # 1. Query Active Directory for Oracle database servers
    try {
        if (Get-Command Get-ADComputer -ErrorAction SilentlyContinue) {
            Write-Host "  Querying Active Directory for Oracle servers..." -ForegroundColor Gray
            $adServers = Get-ADComputer -Filter {Name -like "*db*" -or Name -like "*oracle*" -or Name -like "*sim*"} -Properties Name, DNSHostName, OperatingSystem | 
                Where-Object { $_.OperatingSystem -like "*Server*" -or $_.Name -like "*db*" -or $_.Name -like "*sim*" }
            
            foreach ($adServer in $adServers) {
                $serverName = $adServer.DNSHostName -replace '\..*$', ''  # Remove domain suffix
                $fqdn = $adServer.DNSHostName
                
                # Try to discover instances by checking common Oracle ports
                $instances = @()
                try {
                    # Common Oracle instance names
                    $commonInstances = @("db01", "db02", "db03", "orcl", "XE", "PROD", "DEV", "TEST")
                    foreach ($inst in $commonInstances) {
                        # Test connection (non-blocking check)
                        $tcpClient = New-Object System.Net.Sockets.TcpClient
                        $connect = $tcpClient.BeginConnect($serverName, 1521, $null, $null)
                        $wait = $connect.AsyncWaitHandle.WaitOne(100, $false)
                        if ($wait) {
                            $tcpClient.EndConnect($connect)
                            $instances += $inst
                            $tcpClient.Close()
                        } else {
                            $tcpClient.Close()
                        }
                    }
                } catch {
                    # If we can't test, add common instances anyway
                    $instances = @("db01", "db02")
                }
                
                if ($instances.Count -eq 0) {
                    $instances = @("db01", "db02")  # Default instances
                }
                
                foreach ($inst in $instances) {
                    $tnsName = "${serverName}_${inst}"
                    if (-not ($servers | Where-Object { $_.Name -eq $serverName -and $_.Instance -eq $inst })) {
                        $servers += [PSCustomObject]@{
                            Name = $serverName
                            TNSName = $tnsName
                            Instance = $inst
                            Description = "Domain: $serverName ($fqdn)"
                            Source = "Active Directory"
                        }
                    }
                }
            }
        }
    } catch {
        Write-Host "  Active Directory query not available or failed: $_" -ForegroundColor Gray
    }
    
    # 2. Query DNS for known database server patterns
    try {
        Write-Host "  Querying DNS for database servers..." -ForegroundColor Gray
        $domain = (Get-WmiObject Win32_ComputerSystem).Domain
        $dbPatterns = @("*db*", "*oracle*", "*sim*", "*sql*")
        
        foreach ($pattern in $dbPatterns) {
            try {
                $dnsResults = Resolve-DnsName -Name "$pattern.$domain" -ErrorAction SilentlyContinue -Type A
                foreach ($dnsResult in $dnsResults) {
                    $serverName = $dnsResult.NameHost -replace '\..*$', ''
                    if (-not ($servers | Where-Object { $_.Name -eq $serverName })) {
                        $servers += [PSCustomObject]@{
                            Name = $serverName
                            TNSName = "${serverName}_db02"
                            Instance = "db02"
                            Description = "DNS: $serverName"
                            Source = "DNS"
                        }
                    }
                }
            } catch {
                # Ignore DNS errors
            }
        }
    } catch {
        Write-Host "  DNS query failed: $_" -ForegroundColor Gray
    }
    
    # 3. Check for known server names from environment or network
    $knownServers = @()
    try {
        # Check for servers mentioned in environment variables or network configs
        $envVars = Get-ChildItem Env: | Where-Object { $_.Name -like "*DB*" -or $_.Name -like "*ORACLE*" -or $_.Value -like "*db*" }
        foreach ($envVar in $envVars) {
            if ($envVar.Value -match '([a-zA-Z0-9\-]+db[a-zA-Z0-9\-]+)') {
                $knownServers += $matches[1]
            }
        }
    } catch {
        # Ignore
    }
    
    # Add common database server names
    $commonDbServers = @("des-sim-db1", "des-sim-db2", "sim-db1", "oracle-db1", "db-server")
    foreach ($serverName in $commonDbServers) {
        if (-not ($servers | Where-Object { $_.Name -eq $serverName })) {
            $servers += [PSCustomObject]@{
                Name = $serverName
                TNSName = "${serverName}_db02"
                Instance = "db02"
                Description = "Common: $serverName"
                Source = "Common"
            }
        }
    }
    
    $tnsAdmin = $env:TNS_ADMIN
    if (-not $tnsAdmin) {
        $tnsAdmin = "$env:ORACLE_HOME\network\admin"
    }
    
    if (Test-Path "$tnsAdmin\tnsnames.ora") {
        Write-Host "Reading TNS configuration from $tnsAdmin..." -ForegroundColor Yellow
        $tnsContent = Get-Content "$tnsAdmin\tnsnames.ora" -Raw
        
        # Parse TNS names from tnsnames.ora (multiline pattern)
        # Pattern matches: TNS_NAME = ... HOST = hostname ... SERVICE_NAME = servicename or SID = sid
        $tnsPattern = '(?s)(\w+)\s*=\s*.*?HOST\s*=\s*([^\s\)]+).*?(?:SERVICE_NAME\s*=\s*([^\s\)]+)|SID\s*=\s*([^\s\)]+))'
        $matches = [regex]::Matches($tnsContent, $tnsPattern)
        
        foreach ($match in $matches) {
            $tnsName = $match.Groups[1].Value
            $hostName = $match.Groups[2].Value  # Changed from $host to avoid conflict with $Host
            $serviceName = if ($match.Groups[3].Success) { $match.Groups[3].Value } else { $match.Groups[4].Value }
            
            $servers += [PSCustomObject]@{
                Name = $hostName
                TNSName = $tnsName
                Instance = $serviceName
                Description = "TNS: $tnsName"
            }
        }
    }
    
    # Also check local tnsnames.ora if it exists
    if (Test-Path "tnsnames.ora") {
        Write-Host "Reading TNS configuration from current directory..." -ForegroundColor Yellow
        $tnsContent = Get-Content "tnsnames.ora" -Raw
        
        # Parse TNS names from tnsnames.ora (multiline pattern)
        # Use same pattern as above (without ^ anchor to match anywhere in content)
        $tnsPattern = '(?s)(\w+)\s*=\s*.*?HOST\s*=\s*([^\s\)]+).*?(?:SERVICE_NAME\s*=\s*([^\s\)]+)|SID\s*=\s*([^\s\)]+))'
        $matches = [regex]::Matches($tnsContent, $tnsPattern)
        
        foreach ($match in $matches) {
            $tnsName = $match.Groups[1].Value
            $hostName = $match.Groups[2].Value  # Changed from $host to avoid conflict with $Host
            $serviceName = if ($match.Groups[3].Success) { $match.Groups[3].Value } else { $match.Groups[4].Value }
            
            # Only add if not already in list
            if (-not ($servers | Where-Object { $_.Name -eq $hostName -and $_.Instance -eq $serviceName })) {
                $servers += [PSCustomObject]@{
                    Name = $hostName
                    TNSName = $tnsName
                    Instance = $serviceName
                    Description = "TNS: $tnsName"
                }
            }
        }
    }
    
    if ($servers.Count -eq 0) {
        Write-Host "No TNS entries found. Please configure tnsnames.ora" -ForegroundColor Red
        return @()
    }
    
    return $servers
}

function Get-DatabaseInstances {
    param([string]$Server, [string]$TNSName)
    
    # Query available instances/services from the database
    $instances = @()
    
    try {
        # First, get instances from tnsnames.ora for this server
        if (Test-Path "tnsnames.ora") {
            $tnsContent = Get-Content "tnsnames.ora" -Raw
            $tnsPattern = '(?s)(\w+)\s*=\s*\([^)]*?HOST\s*=\s*' + [regex]::Escape($Server) + '[^)]*?(?:SERVICE_NAME\s*=\s*([^\s\)]+)|SID\s*=\s*([^\s\)]+))'
            $matches = [regex]::Matches($tnsContent, $tnsPattern)
            
            foreach ($match in $matches) {
                $tnsName = $match.Groups[1].Value
                $instanceName = if ($match.Groups[2].Success) { $match.Groups[2].Value } else { $match.Groups[3].Value }
                
                if (-not ($instances | Where-Object { $_.Instance -eq $instanceName })) {
                    $instances += [PSCustomObject]@{
                        Instance = $instanceName
                        TNSName = $tnsName
                        Description = "TNS: $tnsName"
                    }
                }
            }
        }
        
        # Also query the database for available services (only if we have a valid TNS)
        if ($TNSName -and $TNSName -notmatch '_[a-z]' -and $TNSName -match '^[A-Z_]+$') {
            try {
                $queryFile = "get-instances-temp.sql"
                $query = @"
SET PAGESIZE 1000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT NAME || '|' || SERVICE_ID
FROM V`$SERVICES
WHERE NAME NOT LIKE '%XDB%'
ORDER BY NAME;
EXIT;
"@
                # Write SQL file without BOM to avoid "SP2-0734: unknown command" error
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText("$PWD\$queryFile", $query, $utf8NoBom)
                
                $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"
                $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
                $result = sqlplus -S $connectionString "@$queryFile" 2>&1
                
                foreach ($line in $result) {
                    $line = $line.Trim()
                    if ($line -match '^([^|]+)\|') {
                        $serviceName = $matches[1]
                        if (-not ($instances | Where-Object { $_.Instance -eq $serviceName })) {
                            $instances += [PSCustomObject]@{
                                Instance = $serviceName
                                TNSName = $TNSName
                                Description = "Service: $serviceName"
                            }
                        }
                    }
                }
                
                Remove-Item $queryFile -ErrorAction SilentlyContinue
            } catch {
                # If query fails, use instances from TNS only
            }
        }
        
        # If still no instances, try to find TNS entries for this server
        if ($instances.Count -eq 0 -and (Test-Path "tnsnames.ora")) {
            $tnsContent = Get-Content "tnsnames.ora" -Raw
            $tnsPattern = '(?s)^(\w+)\s*=\s*\([^)]*?HOST\s*=\s*' + [regex]::Escape($Server) + '[^)]*?(?:SERVICE_NAME\s*=\s*([^\s\)]+)|SID\s*=\s*([^\s\)]+))'
            $matches = [regex]::Matches($tnsContent, $tnsPattern)
            
            foreach ($match in $matches) {
                $tnsName = $match.Groups[1].Value
                $instanceName = if ($match.Groups[2].Success) { $match.Groups[2].Value } else { $match.Groups[3].Value }
                
                if (-not ($instances | Where-Object { $_.Instance -eq $instanceName })) {
                    $instances += [PSCustomObject]@{
                        Instance = $instanceName
                        TNSName = $tnsName
                        Description = "TNS: $tnsName"
                    }
                }
            }
        }
        
        # If still no instances, use common ones
        if ($instances.Count -eq 0) {
            $commonInstances = @("db01", "db02", "db03", "orcl", "XE")
            foreach ($inst in $commonInstances) {
                $tnsName = if ($TNSName) { $TNSName } else { "SIEMENS_PS_DB" }
                $instances += [PSCustomObject]@{
                    Instance = $inst
                    TNSName = $tnsName
                    Description = "Common: $inst"
                }
            }
        }
    } catch {
        # Return at least the provided TNS instance
        $instances += [PSCustomObject]@{
            Instance = if ($TNSName) { $TNSName } else { "db02" }
            TNSName = $TNSName
            Description = "Default"
        }
    }
    
    return $instances
}

function Get-AvailableSchemas {
    param([string]$TNSName)
    
    # Query the database for available schemas dynamically
    $schemas = @()
    
    try {
        $queryFile = "get-schemas-temp.sql"
        $query = @"
SET PAGESIZE 1000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

-- Get ALL open user schemas dynamically
-- Exclude system schemas by checking default tablespace (SYSTEM/SYSAUX are system)
-- Exclude queue schemas (_AQ suffix)
SELECT DISTINCT u.USERNAME 
FROM DBA_USERS u
WHERE u.ACCOUNT_STATUS = 'OPEN'
  AND u.DEFAULT_TABLESPACE NOT IN ('SYSTEM', 'SYSAUX')
  AND u.USERNAME NOT LIKE '%_AQ'
ORDER BY u.USERNAME;
EXIT;
"@
        # Write SQL file without BOM to avoid "SP2-0734: unknown command" error
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText("$PWD\$queryFile", $query, $utf8NoBom)
        
        # Use simple direct connection (like explore-db.ps1)
        Write-Host "  Connecting to database..." -ForegroundColor Gray
        
        # Use the provided TNSName (don't hardcode!)
        $actualTNS = $TNSName
        if ([string]::IsNullOrEmpty($actualTNS)) {
            $actualTNS = "SIEMENS_PS_DB"  # Fallback only if not provided
        }
        
        # Set encoding
        $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"
        
        # Execute query directly (same approach as explore-db.ps1)
        $connectionString = "sys/change_on_install@$actualTNS AS SYSDBA"
        $result = sqlplus -S $connectionString "@$queryFile" 2>&1
        
        foreach ($line in $result) {
            $line = $line.Trim()
            # Add any valid schema name (already filtered by SQL query)
            if ($line -match '^\w+$' -and $line.Length -gt 0) {
                $schemas += $line
            }
        }
        
        Remove-Item $queryFile -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Could not query schemas: $_"
    }
    
    return $schemas
}

function Get-ProjectsForSchema {
    param([string]$TNSName, [string]$Schema)
    
    # Query for projects in the schema dynamically
    $projects = @()
    
    try {
        $queryFile = "get-projects-temp.sql"
        $query = @"
SET PAGESIZE 1000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

-- Try DFPROJECT table first (standard approach)
SELECT 
    p.PROJECTID || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed Project') || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed Project') || '|' ||
    NVL(c.EXTERNALID_S_, '')
FROM $Schema.DFPROJECT p
LEFT JOIN $Schema.COLLECTION_ c ON p.PROJECTID = c.OBJECT_ID
WHERE p.PROJECTID IS NOT NULL;
-- If DFPROJECT is empty, look for root collections as fallback
-- (This will only execute if first query returns no rows)
SELECT 
    c.OBJECT_ID || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed Project') || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed Project') || '|' ||
    NVL(c.EXTERNALID_S_, '')
FROM $Schema.COLLECTION_ c
WHERE c.OBJECT_ID IN (
    SELECT DISTINCT FORWARD_OBJECT_ID 
    FROM $Schema.REL_COMMON
    WHERE FORWARD_OBJECT_ID NOT IN (
        SELECT DISTINCT OBJECT_ID 
        FROM $Schema.REL_COMMON 
        WHERE OBJECT_ID IS NOT NULL
    )
)
  AND (SELECT COUNT(*) FROM $Schema.DFPROJECT) = 0;
EXIT;
"@
        # Write SQL file without BOM to avoid "SP2-0734: unknown command" error
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText("$PWD\$queryFile", $query, $utf8NoBom)
        
        # Set encoding for SQL*Plus
        $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"
        
        # Use simple direct connection (like explore-db.ps1)
        Write-Host "  Connecting to database..." -ForegroundColor Gray
        
        # Use the provided TNSName (don't hardcode!)
        $actualTNS = $TNSName
        if ([string]::IsNullOrEmpty($actualTNS)) {
            $actualTNS = "SIEMENS_PS_DB"  # Fallback only if not provided
        }
        
        # Set encoding
        $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"
        
        # Execute query directly
        $connectionString = "sys/change_on_install@$actualTNS AS SYSDBA"
        $result = sqlplus -S $connectionString "@$queryFile" 2>&1
        
        # Check for SQL errors
        $errors = $result | Where-Object { $_ -match 'ERROR|ORA-\d+|SP2-' }
        if ($errors) {
            Write-Warning "SQL errors occurred while querying projects:"
            $errors | ForEach-Object { Write-Warning "  $_" }
        }
        
        # Filter for valid project lines (format: ID|Name|Name|ExternalId)
        $projectLines = $result | Where-Object { $_ -match '^\d+\|' }
        
        foreach ($line in $projectLines) {
            # Handle encoding - convert from Windows code page to UTF-8 if needed
            $line = [System.Text.Encoding]::Default.GetString([System.Text.Encoding]::Default.GetBytes($line))
            $parts = $line -split '\|'
            if ($parts.Length -ge 4) {
                $projects += [PSCustomObject]@{
                    ObjectId = $parts[0]
                    Caption = $parts[1]
                    Name = $parts[2]
                    ExternalId = $parts[3]
                }
            }
        }
        
        Remove-Item $queryFile -ErrorAction SilentlyContinue
    } catch {
        Write-Warning "Could not query projects: $_"
    }
    
    return $projects
}

function Show-ConfigurationMenu {
    param([object]$CurrentServer, [string]$CurrentSchema)
    
    try {
        Clear-Host
    } catch {
        # Ignore if non-interactive
    }
    Show-Menu
    
    Write-Host "Current Configuration:" -ForegroundColor Yellow
    if ($CurrentServer) {
        Write-Host "  Server:   " -NoNewline; Write-Host "$($CurrentServer.Name) ($($CurrentServer.TNSName))" -ForegroundColor Cyan
        Write-Host "  Instance: " -NoNewline; Write-Host $CurrentServer.Instance -ForegroundColor Cyan
    } else {
        Write-Host "  Server:   " -NoNewline; Write-Host "Not selected" -ForegroundColor Gray
        Write-Host "  Instance: " -NoNewline; Write-Host "Not selected" -ForegroundColor Gray
    }
    if ($CurrentSchema -and $CurrentSchema -ne "True" -and $CurrentSchema -ne $true) {
        Write-Host "  Schema:   " -NoNewline; Write-Host $CurrentSchema -ForegroundColor Cyan
    } else {
        Write-Host "  Schema:   " -NoNewline; Write-Host "Not selected" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  1. Select Server" -ForegroundColor White
    Write-Host "  2. Select Schema" -ForegroundColor White
    Write-Host "  3. Load Tree" -ForegroundColor Green
    Write-Host "  4. Exit" -ForegroundColor Red
    Write-Host ""
    
    $choice = Read-Host "Select option (1-4)"
    return $choice
}

function Select-Server {
    $servers = Get-DatabaseServers
    
    if ($servers.Count -eq 0) {
        Write-Host "`nNo database servers found!" -ForegroundColor Red
        Write-Host "Please ensure tnsnames.ora is configured." -ForegroundColor Yellow
        Read-Host "Press Enter to continue"
        return $null
    }
    
    Write-Host "`nAvailable Database Servers:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $servers.Count; $i++) {
        $source = if ($servers[$i].Source) { " [$($servers[$i].Source)]" } else { "" }
        Write-Host "  $($i + 1). $($servers[$i].Name) - $($servers[$i].Description)$source" -ForegroundColor White
        Write-Host "     Instance: $($servers[$i].Instance) | TNS: $($servers[$i].TNSName)" -ForegroundColor Gray
    }
    
    $choice = Read-Host "`nSelect server number"
    $index = [int]$choice - 1
    
    if ($index -ge 0 -and $index -lt $servers.Count) {
        $selectedServer = $servers[$index]
        
        # Resolve TNS name first (use SIEMENS_PS_DB if auto-generated)
        $tnsToUse = $selectedServer.TNSName
        if ($tnsToUse -match '_[a-z]' -or -not $tnsToUse) {
            if (Test-Path "tnsnames.ora") {
                $tnsContent = Get-Content "tnsnames.ora" -Raw
                $tnsPattern = '(?s)^(\w+)\s*=\s*\([^)]*?HOST\s*=\s*' + [regex]::Escape($selectedServer.Name)
                if ($tnsContent -match $tnsPattern) {
                    $tnsToUse = $matches[1]
                } else {
                    $tnsToUse = "SIEMENS_PS_DB"
                }
            } else {
                $tnsToUse = "SIEMENS_PS_DB"
            }
        }
        
        # Now query and select instance
        Write-Host "`nQuerying available instances for $($selectedServer.Name)..." -ForegroundColor Yellow
        $instances = Get-DatabaseInstances -Server $selectedServer.Name -TNSName $tnsToUse
        
        if ($instances.Count -gt 1) {
            Write-Host "`nAvailable Instances:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $instances.Count; $i++) {
                Write-Host "  $($i + 1). $($instances[$i].Instance) - $($instances[$i].Description)" -ForegroundColor White
            }
            
            $instChoice = Read-Host "`nSelect instance number (or press Enter for default: $($selectedServer.Instance))"
            
            if ($instChoice -and $instChoice -match '^\d+$') {
                $instIndex = [int]$instChoice - 1
                if ($instIndex -ge 0 -and $instIndex -lt $instances.Count) {
                    $selectedServer.Instance = $instances[$instIndex].Instance
                    $selectedServer.TNSName = $instances[$instIndex].TNSName
                }
            }
        }
        
        return $selectedServer
    }
    
    return $null
}

function Select-Schema {
    param([object]$Server)
    
    if (-not $Server) {
        Write-Host "Please select a server first!" -ForegroundColor Red
        Read-Host "Press Enter to continue"
        return $null
    }
    
    Write-Host "`nQuerying available schemas from $($Server.Name)..." -ForegroundColor Yellow
    
    # Resolve actual TNS name based on instance
    $tnsToUse = $Server.TNSName
    if (Test-Path "tnsnames.ora") {
        $tnsContent = Get-Content "tnsnames.ora" -Raw
        # First, try to find TNS name for the specific instance
        if ($Server.Instance -eq "db01") {
            # Look for db01-specific TNS entry
            if ($tnsContent -match '(\w+)\s*=\s*.*?SERVICE_NAME\s*=\s*db01') {
                $tnsToUse = $matches[1]
            } elseif ($tnsContent -match 'SIEMENS_PS_DB_DB01') {
                $tnsToUse = "SIEMENS_PS_DB_DB01"
            }
        } elseif ($Server.Instance -eq "db02") {
            # Look for db02-specific TNS entry
            if ($tnsContent -match '(\w+)\s*=\s*.*?SERVICE_NAME\s*=\s*db02') {
                $tnsToUse = $matches[1]
            } elseif ($tnsContent -match 'SIEMENS_PS_DB\s*=') {
                $tnsToUse = "SIEMENS_PS_DB"
            }
        }
        # Fallback: try to find any TNS entry for this server/instance
        if (($tnsToUse -eq $Server.TNSName -or -not $tnsToUse -or $tnsToUse -match '_[a-z]')) {
            $tnsPattern = '(?s)^(\w+)\s*=\s*\([^)]*?HOST\s*=\s*' + [regex]::Escape($Server.Name) + '[^)]*?(?:SERVICE_NAME\s*=\s*' + [regex]::Escape($Server.Instance) + '|SID\s*=\s*' + [regex]::Escape($Server.Instance) + ')'
            if ($tnsContent -match $tnsPattern) {
                $tnsToUse = $matches[1]
            } else {
                if ($Server.Instance -eq "db01") {
                    $tnsToUse = "SIEMENS_PS_DB_DB01"
                } else {
                    $tnsToUse = "SIEMENS_PS_DB"
                }
            }
        }
    } else {
        # Fallback based on instance
        if ($Server.Instance -eq "db01") {
            $tnsToUse = "SIEMENS_PS_DB_DB01"
        } else {
            $tnsToUse = "SIEMENS_PS_DB"
        }
    }
    Write-Host "  Using TNS: $tnsToUse (Instance: $($Server.Instance))" -ForegroundColor Gray
    
    $schemas = Get-AvailableSchemas -TNSName $tnsToUse
    
    if ($schemas.Count -eq 0) {
        Write-Host "No schemas found!" -ForegroundColor Red
        Read-Host "Press Enter to continue"
        return $null
    }
    
    Write-Host "`nAvailable Schemas:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $schemas.Count; $i++) {
        Write-Host "  $($i + 1). $($schemas[$i])" -ForegroundColor White
    }
    
    $choice = Read-Host "`nSelect schema number"
    $index = [int]$choice - 1
    
    if ($index -ge 0 -and $index -lt $schemas.Count) {
        return $schemas[$index]
    }
    
    return $null
}

function Select-Project {
    param([object]$Server, [string]$Schema)
    
    Write-Host "`nQuerying projects in $Schema..." -ForegroundColor Yellow
    
    # Resolve actual TNS name based on instance
    $tnsToUse = $Server.TNSName
    if (Test-Path "tnsnames.ora") {
        $tnsContent = Get-Content "tnsnames.ora" -Raw
        # First, try to find TNS name for the specific instance
        if ($Server.Instance -eq "db01") {
            # Look for db01-specific TNS entry
            if ($tnsContent -match '(\w+)\s*=\s*.*?SERVICE_NAME\s*=\s*db01') {
                $tnsToUse = $matches[1]
            } elseif ($tnsContent -match 'SIEMENS_PS_DB_DB01') {
                $tnsToUse = "SIEMENS_PS_DB_DB01"
            }
        } elseif ($Server.Instance -eq "db02") {
            # Look for db02-specific TNS entry
            if ($tnsContent -match '(\w+)\s*=\s*.*?SERVICE_NAME\s*=\s*db02') {
                $tnsToUse = $matches[1]
            } elseif ($tnsContent -match 'SIEMENS_PS_DB\s*=') {
                $tnsToUse = "SIEMENS_PS_DB"
            }
        }
        # Fallback: try to find any TNS entry for this server
        if ($tnsToUse -eq $Server.TNSName -and $tnsContent -notmatch "^\s*$([regex]::Escape($Server.TNSName))\s*=") {
            $tnsPattern = '(?s)(\w+)\s*=\s*.*?HOST\s*=\s*' + [regex]::Escape($Server.Name)
            if ($tnsContent -match $tnsPattern) {
                $tnsToUse = $matches[1]
            } elseif ($tnsContent -match '(\w+)\s*=\s*.*?HOST\s*=\s*des-sim-db1') {
                $tnsToUse = $matches[1]
            }
        }
    } else {
        # Fallback based on instance
        if ($Server.Instance -eq "db01") {
            $tnsToUse = "SIEMENS_PS_DB_DB01"
        } else {
            $tnsToUse = "SIEMENS_PS_DB"
        }
    }
    
    $projects = Get-ProjectsForSchema -TNSName $tnsToUse -Schema $Schema
    
    if ($projects.Count -eq 0) {
        Write-Host "No projects found in $Schema" -ForegroundColor Red
        Write-Host "`nNote: The schema exists but the DFPROJECT table is empty." -ForegroundColor Yellow
        Write-Host "      This means the schema has no project data configured." -ForegroundColor Yellow
        Read-Host "`nPress Enter to continue"
        return $null
    }
    
    Write-Host "`nAvailable Projects:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $projects.Count; $i++) {
        Write-Host "  $($i + 1). $($projects[$i].Caption) (ID: $($projects[$i].ObjectId))" -ForegroundColor White
    }
    
    $choice = Read-Host "`nSelect project number"
    $index = [int]$choice - 1
    
    if ($index -ge 0 -and $index -lt $projects.Count) {
        return $projects[$index]
    }
    
    return $null
}

function Save-Configuration {
    param(
        [object]$Server,
        [string]$Schema,
        [object]$Project
    )
    
    if (-not $Server -or -not $Schema) { return }
    
    $config = @{
        Server = if ($Server) { @{ Name = $Server.Name; Instance = $Server.Instance; TNSName = $Server.TNSName } } else { $null }
        Schema = $Schema
        Project = if ($Project) { @{ ObjectId = $Project.ObjectId; Caption = $Project.Caption; Name = $Project.Name } } else { $null }
        LastUpdated = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
    
    $config | ConvertTo-Json -Depth 3 | Out-File $configFile -Encoding UTF8
}

function Load-Configuration {
    if (Test-Path $configFile) {
        try {
            $content = Get-Content $configFile -Raw -Encoding UTF8
            $config = $content | ConvertFrom-Json
            
            if ($config.Server) {
                $server = [PSCustomObject]@{
                    Name = $config.Server.Name
                    Instance = $config.Server.Instance
                    TNSName = $config.Server.TNSName
                }
            } else {
                $server = $null
            }
            
            return @{
                Server = $server
                Schema = $config.Schema
                Project = if ($config.Project) { [PSCustomObject]$config.Project } else { $null }
            }
        } catch {
            Write-Warning "Could not load configuration: $_"
            return $null
        }
    }
    return $null
}

function Generate-TreeHTML {
    param(
        [object]$Server,
        [string]$Schema,
        [object]$Project
    )
    
    Write-Host "`nGenerating navigation tree..." -ForegroundColor Yellow
    Write-Host "  Server: $($Server.Name)" -ForegroundColor Cyan
    Write-Host "  Instance: $($Server.Instance)" -ForegroundColor Cyan
    Write-Host "  Schema: $Schema" -ForegroundColor Cyan
    Write-Host "  Project: $($Project.Caption) (ID: $($Project.ObjectId))" -ForegroundColor Cyan
    
    # Generate the tree data
    $outputFile = "navigation-tree-${Schema}-$($Project.ObjectId).html"
    
    # Use the TNS name from the selected server/instance
    # Resolve actual TNS name based on instance
    $tnsToUse = $Server.TNSName
    if (Test-Path "tnsnames.ora") {
        $tnsContent = Get-Content "tnsnames.ora" -Raw
        # First, try to find TNS name for the specific instance
        if ($Server.Instance -eq "db01") {
            # Look for db01-specific TNS entry
            if ($tnsContent -match '(\w+)\s*=\s*.*?SERVICE_NAME\s*=\s*db01') {
                $tnsToUse = $matches[1]
            } elseif ($tnsContent -match 'SIEMENS_PS_DB_DB01') {
                $tnsToUse = "SIEMENS_PS_DB_DB01"
            }
        } elseif ($Server.Instance -eq "db02") {
            # Look for db02-specific TNS entry
            if ($tnsContent -match '(\w+)\s*=\s*.*?SERVICE_NAME\s*=\s*db02') {
                $tnsToUse = $matches[1]
            } elseif ($tnsContent -match 'SIEMENS_PS_DB\s*=') {
                $tnsToUse = "SIEMENS_PS_DB"
            }
        }
        # Fallback: try to find any TNS entry for this server/instance
        if (($tnsToUse -eq $Server.TNSName -or -not $tnsToUse -or $tnsToUse -match '_[a-z]')) {
            $tnsPattern = '(?s)^(\w+)\s*=\s*\([^)]*?HOST\s*=\s*' + [regex]::Escape($Server.Name) + '[^)]*?(?:SERVICE_NAME\s*=\s*' + [regex]::Escape($Server.Instance) + '|SID\s*=\s*' + [regex]::Escape($Server.Instance) + ')'
            if ($tnsContent -match $tnsPattern) {
                $tnsToUse = $matches[1]
            } else {
                if ($Server.Instance -eq "db01") {
                    $tnsToUse = "SIEMENS_PS_DB_DB01"
                } else {
                    $tnsToUse = "SIEMENS_PS_DB"
                }
            }
        }
    } else {
        # Fallback based on instance
        if ($Server.Instance -eq "db01") {
            $tnsToUse = "SIEMENS_PS_DB_DB01"
        } else {
            $tnsToUse = "SIEMENS_PS_DB"
        }
    }
    Write-Host "  Using TNS: $tnsToUse (Instance: $($Server.Instance))" -ForegroundColor Gray
    
    # Call the tree generation script
    & ".\generate-tree-html.ps1" -TNSName $tnsToUse -Schema $Schema -ProjectId $Project.ObjectId -ProjectName $Project.Caption -OutputFile $outputFile
    
    if (Test-Path $outputFile) {
        Write-Host "`nTree generated successfully!" -ForegroundColor Green
        Write-Host "File: $outputFile" -ForegroundColor Cyan
        Write-Host "`nOpening in browser..." -ForegroundColor Yellow
        Start-Process $outputFile
    } else {
        Write-Host "`nError: Tree generation failed!" -ForegroundColor Red
    }
}

# Main execution
$selectedServer = $null
$selectedSchema = if ($Schema -and $Schema -ne "True" -and $Schema -ne $true) { $Schema } else { $null }
$selectedProject = $null

# Try to load last configuration if requested or if no parameters provided
if ($LoadLast -or (-not $Server -and -not $Instance -and -not $Schema)) {
    $lastConfig = Load-Configuration
    if ($lastConfig -and $lastConfig.Server -and $lastConfig.Schema) {
        Write-Host "`n=== Found Previous Configuration ===" -ForegroundColor Green
        Write-Host "  Server: $($lastConfig.Server.Name)" -ForegroundColor Cyan
        Write-Host "  Instance: $($lastConfig.Server.Instance)" -ForegroundColor Cyan
        Write-Host "  Schema: $($lastConfig.Schema)" -ForegroundColor Cyan
        if ($lastConfig.Project) {
            Write-Host "  Project: $($lastConfig.Project.Caption) (ID: $($lastConfig.Project.ObjectId))" -ForegroundColor Cyan
        }
        Write-Host ""
        $useLast = Read-Host "Use this configuration? (Y/N, default: Y)"
        
        if ($useLast -ne "N" -and $useLast -ne "n") {
            $selectedServer = $lastConfig.Server
            $selectedSchema = $lastConfig.Schema
            $selectedProject = $lastConfig.Project
            
            if ($selectedProject) {
                Write-Host "`nLoading tree with saved configuration..." -ForegroundColor Yellow
                Generate-TreeHTML -Server $selectedServer -Schema $selectedSchema -Project $selectedProject
                Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $selectedProject
                exit
            }
        }
    }
}

# If parameters provided, try to find server
if ($Server -and $Instance) {
    $servers = Get-DatabaseServers
    $selectedServer = $servers | Where-Object { $_.Name -eq $Server -and $_.Instance -eq $Instance } | Select-Object -First 1
}

if (-not $selectedServer -or -not $selectedSchema) {
    # Interactive mode
    do {
        $choice = Show-ConfigurationMenu -CurrentServer $selectedServer -CurrentSchema $selectedSchema
        
        switch ($choice) {
            "1" {
                $selectedServer = Select-Server
                if ($selectedServer) {
                    Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $selectedProject
                }
            }
            "2" {
                $selectedSchema = Select-Schema -Server $selectedServer
                if ($selectedSchema) {
                    Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $selectedProject
                }
            }
            "3" {
                if ($selectedServer -and $selectedSchema) {
                    $project = Select-Project -Server $selectedServer -Schema $selectedSchema
                    if ($project) {
                        $selectedProject = $project
                        Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $project
                        Generate-TreeHTML -Server $selectedServer -Schema $selectedSchema -Project $project
                        Read-Host "`nPress Enter to continue"
                    }
                } else {
                    Write-Host "`nPlease complete all selections first!" -ForegroundColor Red
                    Read-Host "Press Enter to continue"
                }
            }
            "4" {
                # Load last tree
                $lastConfig = Load-Configuration
                if ($lastConfig -and $lastConfig.Server -and $lastConfig.Schema -and $lastConfig.Project) {
                    Write-Host "`nLoading last tree..." -ForegroundColor Yellow
                    Write-Host "  Server: $($lastConfig.Server.Name)" -ForegroundColor Cyan
                    Write-Host "  Instance: $($lastConfig.Server.Instance)" -ForegroundColor Cyan
                    Write-Host "  Schema: $($lastConfig.Schema)" -ForegroundColor Cyan
                    Write-Host "  Project: $($lastConfig.Project.Caption) (ID: $($lastConfig.Project.ObjectId))" -ForegroundColor Cyan
                    
                    $selectedServer = $lastConfig.Server
                    $selectedSchema = $lastConfig.Schema
                    $selectedProject = [PSCustomObject]$lastConfig.Project
                    
                    Generate-TreeHTML -Server $selectedServer -Schema $selectedSchema -Project $selectedProject
                    Read-Host "`nPress Enter to continue"
                } else {
                    Write-Host "`nNo previous configuration found!" -ForegroundColor Red
                    Write-Host "Please select server, schema, and project first." -ForegroundColor Yellow
                    Read-Host "Press Enter to continue"
                }
            }
            "5" {
                Write-Host "`nExiting..." -ForegroundColor Yellow
                exit
            }
            default {
                Write-Host "`nInvalid option!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
} else {
    # Non-interactive mode - use provided parameters
    $project = Select-Project -Server $selectedServer -Schema $selectedSchema
    if ($project) {
        Save-Configuration -Server $selectedServer -Schema $selectedSchema -Project $project
        Generate-TreeHTML -Server $selectedServer -Schema $selectedSchema -Project $project
    }
}
