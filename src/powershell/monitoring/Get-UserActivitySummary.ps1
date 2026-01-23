<#
.SYNOPSIS
    Aggregates user activity across all configured database servers.

.DESCRIPTION
    Queries PROXY and USER_ tables across multiple servers/schemas to provide:
    - Active checkout counts per user
    - Stale checkout detection (>72 hours)
    - Cross-server activity aggregation
    - Last activity timestamps

    Outputs JSON with comprehensive user activity data for enterprise portal.

.PARAMETER TNSNames
    List of TNS names to query (default: all from PC profiles)

.PARAMETER Schemas
    List of schemas to query (default: DESIGN1-12)

.PARAMETER OutputPath
    Path to save JSON output (default: data/output/user-activity-{timestamp}.json)

.EXAMPLE
    .\Get-UserActivitySummary.ps1

    Aggregates activity across all configured servers

.EXAMPLE
    .\Get-UserActivitySummary.ps1 -TNSNames "SIEMENS_PS_DB_DB01" -Schemas "DESIGN12"

    Queries specific server and schema

.NOTES
    Requires: Oracle Instant Client, configured credentials
#>

param(
    [string[]]$TNSNames = @(),
    [string[]]$Schemas = @("DESIGN1", "DESIGN2", "DESIGN3", "DESIGN4", "DESIGN5", "DESIGN6",
                           "DESIGN7", "DESIGN8", "DESIGN9", "DESIGN10", "DESIGN11", "DESIGN12"),
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Continue"

# Import utilities
$utilsPath = Join-Path $PSScriptRoot "..\utilities"
Import-Module (Join-Path $utilsPath "PCProfileManager.ps1") -Force
Import-Module (Join-Path $utilsPath "CredentialManager.ps1") -Force

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "User Activity Aggregator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Initialize activity data structure
$activityData = [PSCustomObject]@{
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    users = @()
    summary = [PSCustomObject]@{
        activeUsers = 0
        totalCheckouts = 0
        staleCheckouts = 0
        serversQueried = 0
        schemasQueried = 0
    }
}

# Helper function: Query user activity for a server/schema
function Get-UserActivityForSchema {
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
SET COLSEP '|'
SELECT
    u.CAPTION_S_ || '|' ||
    COUNT(DISTINCT p.OBJECT_ID) || '|' ||
    COUNT(DISTINCT CASE WHEN p.WORKING_VERSION_ID > 0 THEN p.OBJECT_ID END) || '|' ||
    MAX(c.MODIFICATIONDATE_DA_) || '|' ||
    MAX(CASE
        WHEN p.WORKING_VERSION_ID > 0 AND (SYSDATE - c.MODIFICATIONDATE_DA_) * 24 > 72 THEN
            ROUND((SYSDATE - c.MODIFICATIONDATE_DA_) * 24, 1)
        ELSE 0
    END) as activity_data
FROM $Schema.USER_ u
LEFT JOIN $Schema.PROXY p ON u.OBJECT_ID = p.OWNER_ID
LEFT JOIN $Schema.COLLECTION_ c ON p.OBJECT_ID = c.OBJECT_ID
WHERE p.OBJECT_ID IS NOT NULL
GROUP BY u.CAPTION_S_
HAVING COUNT(DISTINCT CASE WHEN p.WORKING_VERSION_ID > 0 THEN p.OBJECT_ID END) > 0;
EXIT;
"@

        $scriptFile = Join-Path $env:TEMP "user_activity_$($Schema).sql"
        $sql | Out-File -FilePath $scriptFile -Encoding ASCII

        $result = & sqlplus -S $connStr "@$scriptFile" 2>&1
        if (Test-Path $scriptFile) { Remove-Item $scriptFile -Force }

        $users = @()
        if ($result) {
            foreach ($line in $result) {
                if ($line -match '\|') {
                    $parts = $line -split '\|'
                    if ($parts.Count -ge 5) {
                        $users += [PSCustomObject]@{
                            name = $parts[0].Trim()
                            totalObjects = [int]$parts[1]
                            checkedOutItems = [int]$parts[2]
                            lastActivity = $parts[3].Trim()
                            longestCheckout = [double]$parts[4]
                            server = $TNSName
                            schema = $Schema
                        }
                    }
                }
            }
        }

        return $users

    } catch {
        Write-Warning "Failed to query user activity for $TNSName/$Schema : $_"
        return @()
    }
}

# If no TNS names specified, get all from PC profiles
if ($TNSNames.Count -eq 0) {
    Write-Host "Loading servers from PC profiles..." -ForegroundColor Cyan
    $profiles = Get-PCProfiles

    $uniqueTNS = @{}
    foreach ($profile in $profiles) {
        foreach ($server in $profile.servers) {
            foreach ($instance in $server.instances) {
                if (-not $uniqueTNS.ContainsKey($instance.tnsName)) {
                    $uniqueTNS[$instance.tnsName] = $true
                    $TNSNames += $instance.tnsName
                }
            }
        }
    }

    Write-Host "Found $($TNSNames.Count) unique server(s)" -ForegroundColor Green
}

# Aggregate user activity across all servers/schemas
$userMap = @{}

foreach ($tnsName in $TNSNames) {
    Write-Host "`nQuerying: $tnsName" -ForegroundColor Cyan

    # Get credentials
    try {
        $cred = Get-DbCredential -TNSName $tnsName
        $username = $cred.Username
        $password = $cred.GetNetworkCredential().Password
        $useSysDBA = $username -eq "sys"
    } catch {
        Write-Host "  ⚠ Credentials not found, skipping" -ForegroundColor Yellow
        continue
    }

    $activityData.summary.serversQueried++

    foreach ($schema in $Schemas) {
        Write-Host "  Schema: $schema..." -ForegroundColor Gray

        $users = Get-UserActivityForSchema -TNSName $tnsName -Schema $schema -Username $username -Password $password -AsSysDBA:$useSysDBA

        if ($users.Count -gt 0) {
            Write-Host "    Found $($users.Count) active user(s)" -ForegroundColor Green
            $activityData.summary.schemasQueried++

            # Aggregate by user name
            foreach ($user in $users) {
                if (-not $userMap.ContainsKey($user.name)) {
                    $userMap[$user.name] = [PSCustomObject]@{
                        name = $user.name
                        checkedOutItems = 0
                        servers = @()
                        schemas = @()
                        longestCheckout = 0
                        lastActivity = $null
                        details = @()
                    }
                }

                $userObj = $userMap[$user.name]
                $userObj.checkedOutItems += $user.checkedOutItems

                if (-not $userObj.servers.Contains($user.server)) {
                    $userObj.servers += $user.server
                }
                if (-not $userObj.schemas.Contains($user.schema)) {
                    $userObj.schemas += $user.schema
                }

                if ($user.longestCheckout -gt $userObj.longestCheckout) {
                    $userObj.longestCheckout = $user.longestCheckout
                }

                if ($user.lastActivity) {
                    try {
                        $activityDate = [DateTime]::ParseExact($user.lastActivity, "dd-MMM-yy", $null)
                        if (-not $userObj.lastActivity -or $activityDate -gt [DateTime]$userObj.lastActivity) {
                            $userObj.lastActivity = $activityDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
                        }
                    } catch {
                        # Ignore parsing errors
                    }
                }

                $userObj.details += [PSCustomObject]@{
                    server = $user.server
                    schema = $user.schema
                    checkedOutItems = $user.checkedOutItems
                }

                $activityData.summary.totalCheckouts += $user.checkedOutItems

                if ($user.longestCheckout -gt 72) {
                    $activityData.summary.staleCheckouts++
                }
            }
        }
    }
}

# Convert userMap to array and sort
$activityData.users = $userMap.Values | Sort-Object -Property checkedOutItems -Descending
$activityData.summary.activeUsers = $activityData.users.Count

# Output results
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Active Users:     $($activityData.summary.activeUsers)" -ForegroundColor White
Write-Host "Total Checkouts:  $($activityData.summary.totalCheckouts)" -ForegroundColor White
Write-Host "Stale Checkouts:  $($activityData.summary.staleCheckouts)" -ForegroundColor $(if ($activityData.summary.staleCheckouts -gt 0) { "Yellow" } else { "Green" })
Write-Host "Servers Queried:  $($activityData.summary.serversQueried)" -ForegroundColor White
Write-Host "Schemas Queried:  $($activityData.summary.schemasQueried)" -ForegroundColor White
Write-Host ""

if ($activityData.users.Count -gt 0) {
    Write-Host "Top 5 Active Users:" -ForegroundColor Cyan
    $activityData.users | Select-Object -First 5 | ForEach-Object {
        Write-Host "  $($_.name): $($_.checkedOutItems) items" -ForegroundColor White
    }
    Write-Host ""
}

# Save JSON output
if (-not $OutputPath) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = Join-Path $PSScriptRoot "..\..\..\data\output\user-activity-$timestamp.json"
}

# Ensure output directory exists
$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Convert to JSON and save
$json = $activityData | ConvertTo-Json -Depth 10
$json | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

Write-Host "User activity data saved to:" -ForegroundColor Green
Write-Host "  $OutputPath" -ForegroundColor Cyan
Write-Host ""

return $OutputPath
