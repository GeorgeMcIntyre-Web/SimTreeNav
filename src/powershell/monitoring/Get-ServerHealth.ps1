<#
.SYNOPSIS
    Monitors health status of all configured Oracle database servers.

.DESCRIPTION
    Queries all servers/instances from PC profiles and checks:
    - Connection status (online/offline/degraded)
    - Response time (SQL query latency)
    - Active session count
    - Available schemas (DESIGN1-12)
    - Project counts per schema
    - Cache freshness (icon, tree, activity caches)

    Outputs JSON with comprehensive server health data for enterprise portal.

.PARAMETER ConfigPath
    Path to pc-profiles.json (default: config/pc-profiles.json)

.PARAMETER OutputPath
    Path to save JSON output (default: data/output/server-health-{timestamp}.json)

.PARAMETER IncludeOfflineServers
    Include offline servers in output (default: true)

.EXAMPLE
    .\Get-ServerHealth.ps1

    Checks all servers from PC profiles and outputs JSON

.EXAMPLE
    .\Get-ServerHealth.ps1 -OutputPath "custom-health.json"

    Outputs to custom file path

.NOTES
    Requires: Oracle Instant Client, configured PC profiles, valid credentials
#>

param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot "..\..\..\config\pc-profiles.json"),
    [string]$OutputPath = "",
    [switch]$IncludeOfflineServers = $true
)

$ErrorActionPreference = "Continue"  # Don't stop on individual server failures

# Import utilities
$utilsPath = Join-Path $PSScriptRoot "..\utilities"
Import-Module (Join-Path $utilsPath "PCProfileManager.ps1") -Force
Import-Module (Join-Path $utilsPath "CredentialManager.ps1") -Force

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Server Health Monitor" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Initialize health data structure
$healthData = [PSCustomObject]@{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    generatedBy = $env:USERNAME
    hostname = $env:COMPUTERNAME
    servers = @()
    summary = [PSCustomObject]@{
        totalServers = 0
        onlineServers = 0
        offlineServers = 0
        degradedServers = 0
        totalSchemas = 0
        totalProjects = 0
        activeUsers = 0
        cacheIssues = 0
    }
}

# Helper function: Test database connection with timeout
function Test-OracleConnection {
    param(
        [string]$TNSName,
        [string]$Username,
        [string]$Password,
        [switch]$AsSysDBA,
        [int]$TimeoutSeconds = 5
    )

    try {
        # Build connection string
        if ($AsSysDBA) {
            $connStr = "$Username/$Password@$TNSName AS SYSDBA"
        } else {
            $connStr = "$Username/$Password@$TNSName"
        }

        # Create simple test query
        $testSQL = @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET TIMING ON
SELECT '1' FROM DUAL;
EXIT;
"@

        $scriptFile = Join-Path $env:TEMP "health_test_$($TNSName).sql"
        $testSQL | Out-File -FilePath $scriptFile -Encoding ASCII

        # Execute with timeout using Start-Process
        $startTime = Get-Date
        $process = Start-Process -FilePath "sqlplus" -ArgumentList "-S $connStr @$scriptFile" `
            -NoNewWindow -Wait -PassThru -RedirectStandardOutput "$env:TEMP\sqlplus_out.txt" `
            -RedirectStandardError "$env:TEMP\sqlplus_err.txt"

        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds

        # Clean up
        if (Test-Path $scriptFile) { Remove-Item $scriptFile -Force }

        if ($process.ExitCode -eq 0) {
            return [PSCustomObject]@{
                Success = $true
                ResponseTime = [math]::Round($duration, 0)
                Status = if ($duration -gt 1000) { "degraded" } else { "online" }
            }
        } else {
            return [PSCustomObject]@{
                Success = $false
                ResponseTime = 0
                Status = "offline"
                Error = (Get-Content "$env:TEMP\sqlplus_err.txt" -Raw)
            }
        }

    } catch {
        return [PSCustomObject]@{
            Success = $false
            ResponseTime = 0
            Status = "offline"
            Error = $_.Exception.Message
        }
    }
}

# Helper function: Query active sessions
function Get-ActiveSessions {
    param(
        [string]$TNSName,
        [string]$Username,
        [string]$Password,
        [switch]$AsSysDBA
    )

    try {
        if ($AsSysDBA) {
            $connStr = "$Username/$Password@$TNSName AS SYSDBA"
        } else {
            $connStr = "$Username/$Password@$TNSName"
        }

        $sql = @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SELECT COUNT(*) FROM V\$SESSION WHERE STATUS = 'ACTIVE';
EXIT;
"@

        $scriptFile = Join-Path $env:TEMP "sessions_$($TNSName).sql"
        $sql | Out-File -FilePath $scriptFile -Encoding ASCII

        $result = & sqlplus -S $connStr "@$scriptFile" 2>&1
        if (Test-Path $scriptFile) { Remove-Item $scriptFile -Force }

        if ($result -match '^\d+$') {
            return [int]$result
        }
        return 0

    } catch {
        Write-Warning "Failed to query sessions for $TNSName : $_"
        return 0
    }
}

# Helper function: Get available schemas
function Get-AvailableSchemas {
    param(
        [string]$TNSName,
        [string]$Username,
        [string]$Password,
        [switch]$AsSysDBA
    )

    try {
        if ($AsSysDBA) {
            $connStr = "$Username/$Password@$TNSName AS SYSDBA"
        } else {
            $connStr = "$Username/$Password@$TNSName"
        }

        $sql = @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING OFF
SELECT USERNAME FROM DBA_USERS
WHERE ACCOUNT_STATUS = 'OPEN'
  AND USERNAME LIKE 'DESIGN%'
ORDER BY USERNAME;
EXIT;
"@

        $scriptFile = Join-Path $env:TEMP "schemas_$($TNSName).sql"
        $sql | Out-File -FilePath $scriptFile -Encoding ASCII

        $result = & sqlplus -S $connStr "@$scriptFile" 2>&1
        if (Test-Path $scriptFile) { Remove-Item $scriptFile -Force }

        if ($result) {
            return ($result | Where-Object { $_ -match '^DESIGN\d+$' })
        }
        return @()

    } catch {
        Write-Warning "Failed to query schemas for $TNSName : $_"
        return @()
    }
}

# Helper function: Count projects in schema
function Get-ProjectCount {
    param(
        [string]$TNSName,
        [string]$Schema,
        [string]$Username,
        [string]$Password,
        [switch]$AsSysDBA
    )

    try {
        if ($AsSysDBA) {
            $connStr = "$Username/$Password@$TNSName AS SYSDBA"
        } else {
            $connStr = "$Username/$Password@$TNSName"
        }

        $sql = @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING OFF
SELECT COUNT(*) FROM $Schema.DFPROJECT WHERE PROJECTID IS NOT NULL;
EXIT;
"@

        $scriptFile = Join-Path $env:TEMP "projects_$($Schema).sql"
        $sql | Out-File -FilePath $scriptFile -Encoding ASCII

        $result = & sqlplus -S $connStr "@$scriptFile" 2>&1
        if (Test-Path $scriptFile) { Remove-Item $scriptFile -Force }

        if ($result -match '^\d+$') {
            return [int]$result
        }
        return 0

    } catch {
        return 0
    }
}

# Helper function: Check cache file freshness
function Get-CacheHealth {
    param(
        [string]$TNSName,
        [string]$Schema
    )

    $dataPath = Join-Path $PSScriptRoot "..\..\..\data"
    $cacheHealth = [PSCustomObject]@{
        iconCache = "missing"
        treeCache = "missing"
        activityCache = "missing"
    }

    # Check icon cache (7-day TTL)
    $iconCache = Get-ChildItem -Path $dataPath -Filter "icon-cache-$Schema-*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($iconCache) {
        $age = (Get-Date) - $iconCache.LastWriteTime
        if ($age.TotalDays -lt 7) {
            $cacheHealth.iconCache = "fresh"
        } else {
            $cacheHealth.iconCache = "stale"
        }
    }

    # Check tree cache (24-hour TTL)
    $treeCache = Get-ChildItem -Path $dataPath -Filter "tree-cache-$Schema-*-*.txt" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($treeCache) {
        $age = (Get-Date) - $treeCache.LastWriteTime
        if ($age.TotalHours -lt 24) {
            $cacheHealth.treeCache = "fresh"
        } else {
            $cacheHealth.treeCache = "stale"
        }
    }

    # Check activity cache (1-hour TTL)
    $activityCache = Get-ChildItem -Path $dataPath -Filter "user-activity-cache-$Schema-*-*.js" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($activityCache) {
        $age = (Get-Date) - $activityCache.LastWriteTime
        if ($age.TotalHours -lt 1) {
            $cacheHealth.activityCache = "fresh"
        } else {
            $cacheHealth.activityCache = "stale"
        }
    }

    return $cacheHealth
}

# Load PC profiles
Write-Host "Loading PC profiles..." -ForegroundColor Cyan

if (-not (Test-Path $ConfigPath)) {
    Write-Host "ERROR: PC profiles not found at: $ConfigPath" -ForegroundColor Red
    Write-Host "Run Initialize-PCProfile.ps1 to create profiles" -ForegroundColor Yellow
    exit 1
}

$profiles = Get-PCProfiles

if ($profiles.Count -eq 0) {
    Write-Host "ERROR: No PC profiles configured" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($profiles.Count) profile(s)" -ForegroundColor Green
Write-Host ""

# Iterate through all profiles and servers
foreach ($profile in $profiles) {
    Write-Host "Profile: $($profile.name)" -ForegroundColor Cyan

    foreach ($server in $profile.servers) {
        foreach ($instance in $server.instances) {
            $healthData.summary.totalServers++

            $tnsName = $instance.tnsName
            Write-Host "  Checking: $($server.name) / $($instance.name) ($tnsName)..." -ForegroundColor White

            # Get credentials
            try {
                $cred = Get-DbCredential -TNSName $tnsName
                $username = $cred.Username
                $password = $cred.GetNetworkCredential().Password
                $useSysDBA = $username -eq "sys"

            } catch {
                Write-Host "    ⚠ Credentials not found" -ForegroundColor Yellow

                $serverData = [PSCustomObject]@{
                    name = $server.name
                    instance = $instance.name
                    tnsName = $tnsName
                    status = "offline"
                    statusReason = "No credentials configured"
                    responseTime = 0
                    activeSessions = 0
                    schemas = @()
                    cacheHealth = Get-CacheHealth -TNSName $tnsName -Schema "DESIGN12"
                    lastChecked = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                }

                $healthData.servers += $serverData
                $healthData.summary.offlineServers++
                continue
            }

            # Test connection
            $connTest = Test-OracleConnection -TNSName $tnsName -Username $username -Password $password -AsSysDBA:$useSysDBA

            if ($connTest.Success) {
                Write-Host "    ✓ $($connTest.Status) ($($connTest.ResponseTime)ms)" -ForegroundColor Green

                # Get active sessions
                $sessions = Get-ActiveSessions -TNSName $tnsName -Username $username -Password $password -AsSysDBA:$useSysDBA
                Write-Host "    Sessions: $sessions active" -ForegroundColor Gray

                # Get available schemas
                Write-Host "    Querying schemas..." -ForegroundColor Gray
                $schemas = Get-AvailableSchemas -TNSName $tnsName -Username $username -Password $password -AsSysDBA:$useSysDBA

                $schemaData = @()
                foreach ($schema in $schemas) {
                    $projectCount = Get-ProjectCount -TNSName $tnsName -Schema $schema -Username $username -Password $password -AsSysDBA:$useSysDBA
                    $schemaData += [PSCustomObject]@{
                        name = $schema
                        projectCount = $projectCount
                        lastActivity = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                    }
                    $healthData.summary.totalProjects += $projectCount
                }

                $healthData.summary.totalSchemas += $schemas.Count

                # Get cache health
                $cacheHealth = Get-CacheHealth -TNSName $tnsName -Schema "DESIGN12"

                # Create server health data
                $serverData = [PSCustomObject]@{
                    name = $server.name
                    instance = $instance.name
                    tnsName = $tnsName
                    status = $connTest.Status
                    statusReason = ""
                    responseTime = $connTest.ResponseTime
                    activeSessions = $sessions
                    schemas = $schemaData
                    cacheHealth = $cacheHealth
                    lastChecked = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                }

                $healthData.servers += $serverData

                if ($connTest.Status -eq "online") {
                    $healthData.summary.onlineServers++
                } else {
                    $healthData.summary.degradedServers++
                }

                # Count cache issues
                if ($cacheHealth.iconCache -eq "stale" -or $cacheHealth.treeCache -eq "stale" -or $cacheHealth.activityCache -eq "stale") {
                    $healthData.summary.cacheIssues++
                }

            } else {
                Write-Host "    ✗ Offline" -ForegroundColor Red
                if ($connTest.Error) {
                    Write-Host "    Error: $($connTest.Error)" -ForegroundColor Red
                }

                $serverData = [PSCustomObject]@{
                    name = $server.name
                    instance = $instance.name
                    tnsName = $tnsName
                    status = "offline"
                    statusReason = $connTest.Error
                    responseTime = 0
                    activeSessions = 0
                    schemas = @()
                    cacheHealth = Get-CacheHealth -TNSName $tnsName -Schema "DESIGN12"
                    lastChecked = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                }

                $healthData.servers += $serverData
                $healthData.summary.offlineServers++
            }
        }
    }
}

# Filter out offline servers if requested
if (-not $IncludeOfflineServers) {
    $healthData.servers = $healthData.servers | Where-Object { $_.status -ne "offline" }
}

# Output results
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Servers:    $($healthData.summary.totalServers)" -ForegroundColor White
Write-Host "Online:           $($healthData.summary.onlineServers)" -ForegroundColor Green
Write-Host "Degraded:         $($healthData.summary.degradedServers)" -ForegroundColor Yellow
Write-Host "Offline:          $($healthData.summary.offlineServers)" -ForegroundColor Red
Write-Host "Total Schemas:    $($healthData.summary.totalSchemas)" -ForegroundColor White
Write-Host "Total Projects:   $($healthData.summary.totalProjects)" -ForegroundColor White
Write-Host "Cache Issues:     $($healthData.summary.cacheIssues)" -ForegroundColor $(if ($healthData.summary.cacheIssues -gt 0) { "Yellow" } else { "Green" })
Write-Host ""

# Save JSON output
if (-not $OutputPath) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $PSScriptRoot "..\..\..\data\output\server-health-$timestamp.json"
}

# Ensure output directory exists
$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Convert to JSON and save
$json = $healthData | ConvertTo-Json -Depth 10
$json | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

Write-Host "Health data saved to:" -ForegroundColor Green
Write-Host "  $OutputPath" -ForegroundColor Cyan
Write-Host ""

return $OutputPath
