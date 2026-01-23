
# Generate dummy data for Enterprise Portal
param (
    [string]$BaseDataPath = "C:\Users\georgem\source\repos\SimTreeNav_Data"
)

$ServerHealthPath = Join-Path $BaseDataPath "ServerHealthPath"
$UserActivityPath = Join-Path $BaseDataPath "UserActivityPath"
$ScheduledJobsPath = Join-Path $BaseDataPath "ScheduledJobsPath"

# Ensure directories exist
New-Item -ItemType Directory -Path $ServerHealthPath -Force | Out-Null
New-Item -ItemType Directory -Path $UserActivityPath -Force | Out-Null
New-Item -ItemType Directory -Path $ScheduledJobsPath -Force | Out-Null

# 1. Server Health
$serverHealth = @{
    summary = @{
        onlineServers = 2
        totalServers = 2
        degradedServers = 0
        offlineServers = 0
        totalProjects = 15
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    servers = @(
        @{
            name = "Server1"
            instance = "Prod"
            status = "online"
            responseTime = 45
            activeSessions = 5
            schemas = @(
                @{ name = "SchemaA"; projectCount = 10 }
            )
            cacheHealth = @{
                iconCache = "fresh"
                treeCache = "fresh"
                activityCache = "fresh"
            }
        },
        @{
            name = "Server2"
            instance = "Test"
            status = "online"
            responseTime = 50
            activeSessions = 2
            schemas = @(
                @{ name = "SchemaB"; projectCount = 5 }
            )
            cacheHealth = @{
                iconCache = "fresh"
                treeCache = "fresh"
                activityCache = "fresh"
            }
        }
    )
}

$serverHealthFile = Join-Path $ServerHealthPath "server-health-dummy.json"
$serverHealth | ConvertTo-Json -Depth 10 | Out-File -FilePath $serverHealthFile -Encoding UTF8 -Force
Write-Host "Created $serverHealthFile" -ForegroundColor Green

# 2. User Activity
$userActivity = @{
    summary = @{
        activeUsers = 3
        totalCheckouts = 5
        staleCheckouts = 1
    }
    users = @(
        @{
            name = "Alice"
            checkedOutItems = 2
            servers = @("Server1")
            longestCheckout = 24
            lastActivity = (Get-Date).AddHours(-2).ToString("yyyy-MM-ddTHH:mm:ssZ")
        },
        @{
            name = "Bob"
            checkedOutItems = 3
            servers = @("Server1", "Server2")
            longestCheckout = 96
            lastActivity = (Get-Date).AddHours(-5).ToString("yyyy-MM-ddTHH:mm:ssZ")
        },
        @{
            name = "Charlie"
            checkedOutItems = 0
            servers = @()
            longestCheckout = 0
            lastActivity = (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
    )
}

$userActivityFile = Join-Path $UserActivityPath "user-activity-dummy.json"
$userActivity | ConvertTo-Json -Depth 10 | Out-File -FilePath $userActivityFile -Encoding UTF8 -Force
Write-Host "Created $userActivityFile" -ForegroundColor Green

# 3. Scheduled Jobs
$scheduledJobs = @{
    jobs = @(
        @{
            name = "NightlyBackup"
            status = "success"
            lastRun = (Get-Date).AddHours(-12).ToString("yyyy-MM-ddTHH:mm:ssZ")
            nextRun = (Get-Date).AddHours(12).ToString("yyyy-MM-ddTHH:mm:ssZ")
            state = "Ready"
            errorMessage = $null
        },
        @{
            name = "DataSync"
            status = "failed"
            lastRun = (Get-Date).AddHours(-1).ToString("yyyy-MM-ddTHH:mm:ssZ")
            nextRun = (Get-Date).AddHours(1).ToString("yyyy-MM-ddTHH:mm:ssZ")
            state = "Retrying"
            errorMessage = "Connection timeout"
        }
    )
}

$scheduledJobsFile = Join-Path $ScheduledJobsPath "scheduled-jobs-dummy.json"
$scheduledJobs | ConvertTo-Json -Depth 10 | Out-File -FilePath $scheduledJobsFile -Encoding UTF8 -Force
Write-Host "Created $scheduledJobsFile" -ForegroundColor Green
