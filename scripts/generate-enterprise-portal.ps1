<#
.SYNOPSIS
    Generates SimTreeNav Enterprise Portal HTML dashboard.

.DESCRIPTION
    Combines server health, user activity, and scheduled job data into
    a unified enterprise dashboard with 3 stakeholder views:
    - Executive View: KPIs, health maps, trends
    - Project Manager View: Navigator, actions, user activity
    - Engineer View: Detailed metrics, cache status, configuration

.PARAMETER ServerHealthPath
    Path to server-health JSON file (from Get-ServerHealth.ps1)

.PARAMETER UserActivityPath
    Path to user-activity JSON file (from Get-UserActivitySummary.ps1)

.PARAMETER ScheduledJobsPath
    Path to scheduled-jobs JSON file (from Get-ScheduledJobStatus.ps1)

.PARAMETER OutputPath
    Path to save HTML output (default: data/output/enterprise-portal.html)

.EXAMPLE
    .\generate-enterprise-portal.ps1 `
        -ServerHealthPath "data/output/server-health-20260123.json" `
        -UserActivityPath "data/output/user-activity-20260123.json" `
        -ScheduledJobsPath "data/output/scheduled-jobs-20260123.json"

.NOTES
    Generates self-contained HTML file with all data, CSS, and JavaScript embedded.
    No external dependencies required.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ServerHealthPath,

    [Parameter(Mandatory=$true)]
    [string]$UserActivityPath,

    [Parameter(Mandatory=$true)]
    [string]$ScheduledJobsPath,

    [string]$OutputPath = "data\output\enterprise-portal.html"
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Enterprise Portal Generator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Helper function to resolve paths
function Resolve-InputPath {
    param (
        [string]$Path,
        [string]$Description
    )

    if (-not (Test-Path $Path)) {
        Write-Error "ERROR: $Description path not found: $Path"
        exit 1
    }

    if (Test-Path $Path -PathType Container) {
        $latestFile = Get-ChildItem -Path $Path -Filter "*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        
        if (-not $latestFile) {
            Write-Error "ERROR: No .json files found in $Description directory: $Path"
            exit 1
        }
        
        Write-Host "  Using latest file for $Description : $($latestFile.Name)" -ForegroundColor DarkGray
        return $latestFile.FullName
    }

    return $Path
}

# Validate and resolve input files
Write-Host "Validating input files..." -ForegroundColor Cyan

$ServerHealthPath = Resolve-InputPath -Path $ServerHealthPath -Description "Server Health"
$UserActivityPath = Resolve-InputPath -Path $UserActivityPath -Description "User Activity"
$ScheduledJobsPath = Resolve-InputPath -Path $ScheduledJobsPath -Description "Scheduled Jobs"

Write-Host "  ✓ All input files resolved" -ForegroundColor Green
Write-Host ""

# Load JSON data
Write-Host "Loading JSON data..." -ForegroundColor Cyan

try {
    $serverHealthJson = Get-Content $ServerHealthPath -Raw -Encoding UTF8
    $serverHealth = $serverHealthJson | ConvertFrom-Json
    Write-Host "  ✓ Server health data loaded" -ForegroundColor Green

    $userActivityJson = Get-Content $UserActivityPath -Raw -Encoding UTF8
    $userActivity = $userActivityJson | ConvertFrom-Json
    Write-Host "  ✓ User activity data loaded" -ForegroundColor Green

    $scheduledJobsJson = Get-Content $ScheduledJobsPath -Raw -Encoding UTF8
    $scheduledJobs = $scheduledJobsJson | ConvertFrom-Json
    Write-Host "  ✓ Scheduled jobs data loaded" -ForegroundColor Green

} catch {
    Write-Error "ERROR: Failed to parse JSON: $_"
    exit 1
}

Write-Host ""

# Calculate KPIs
$onlineServers = $serverHealth.summary.onlineServers
$totalServers = $serverHealth.summary.totalServers
$uptime = if ($totalServers -gt 0) { [math]::Round(($onlineServers / $totalServers) * 100, 1) } else { 0 }
$activeUsers = $userActivity.summary.activeUsers
$totalCheckouts = $userActivity.summary.totalCheckouts
$staleCheckouts = $userActivity.summary.staleCheckouts
$totalProjects = $serverHealth.summary.totalProjects

Write-Host "Portal Statistics:" -ForegroundColor Cyan
Write-Host "  System Uptime: $uptime%" -ForegroundColor White
Write-Host "  Total Servers: $totalServers ($onlineServers online)" -ForegroundColor White
Write-Host "  Active Users:  $activeUsers" -ForegroundColor White
Write-Host "  Total Projects: $totalProjects" -ForegroundColor White
Write-Host "  Checkouts:     $totalCheckouts ($staleCheckouts stale)" -ForegroundColor White
Write-Host ""

# Generate HTML
Write-Host "Generating HTML dashboard..." -ForegroundColor Yellow

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SimTreeNav Enterprise Portal</title>
    <style>
        /* ========================================
           RESET & BASE STYLES
           ======================================== */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        :root {
            --primary-color: #1a237e;
            --secondary-color: #0d47a1;
            --accent-color: #ff6f00;
            --success-color: #2e7d32;
            --warning-color: #f57c00;
            --danger-color: #c62828;
            --light-bg: #f5f5f5;
            --card-bg: #ffffff;
            --text-primary: #212121;
            --text-secondary: #757575;
            --border-color: #e0e0e0;
            --shadow: 0 2px 4px rgba(0,0,0,0.1);
            --shadow-lg: 0 4px 12px rgba(0,0,0,0.15);
        }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: var(--light-bg);
            color: var(--text-primary);
            line-height: 1.6;
        }

        /* ========================================
           TOP NAVIGATION
           ======================================== */
        .top-nav {
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            color: white;
            padding: 15px 30px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            box-shadow: var(--shadow-lg);
            position: sticky;
            top: 0;
            z-index: 1000;
        }

        .logo {
            font-size: 1.5em;
            font-weight: bold;
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .logo::before {
            content: '🏢';
            font-size: 1.2em;
        }

        .view-switcher {
            display: flex;
            gap: 10px;
        }

        .view-switcher button {
            background: rgba(255,255,255,0.1);
            border: 1px solid rgba(255,255,255,0.3);
            color: white;
            padding: 8px 20px;
            border-radius: 20px;
            cursor: pointer;
            transition: all 0.3s;
            font-size: 0.9em;
        }

        .view-switcher button:hover {
            background: rgba(255,255,255,0.2);
            transform: translateY(-2px);
        }

        .view-switcher button.active {
            background: white;
            color: var(--primary-color);
            font-weight: bold;
        }

        .status-indicator {
            display: flex;
            flex-direction: column;
            align-items: flex-end;
            font-size: 0.85em;
        }

        .status-indicator .health {
            font-weight: bold;
            display: flex;
            align-items: center;
            gap: 5px;
        }

        .status-indicator .health.operational::before {
            content: '●';
            color: #4caf50;
            font-size: 1.2em;
        }

        .status-indicator .health.degraded::before {
            content: '●';
            color: #ff9800;
            font-size: 1.2em;
        }

        .status-indicator .health.critical::before {
            content: '●';
            color: #f44336;
            font-size: 1.2em;
        }

        .last-refresh {
            opacity: 0.8;
            font-size: 0.9em;
        }

        /* ========================================
           VIEW CONTAINERS
           ======================================== */
        .view-container {
            max-width: 1400px;
            margin: 0 auto;
            padding: 30px;
        }

        .view-container h1 {
            font-size: 2em;
            margin-bottom: 30px;
            color: var(--primary-color);
        }

        /* ========================================
           KPI CARDS (EXECUTIVE VIEW)
           ======================================== */
        .kpi-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }

        .kpi-card {
            background: var(--card-bg);
            padding: 25px;
            border-radius: 12px;
            box-shadow: var(--shadow);
            transition: transform 0.2s, box-shadow 0.2s;
        }

        .kpi-card:hover {
            transform: translateY(-4px);
            box-shadow: var(--shadow-lg);
        }

        .kpi-value {
            font-size: 2.5em;
            font-weight: bold;
            color: var(--primary-color);
            margin-bottom: 5px;
        }

        .kpi-label {
            font-size: 0.9em;
            color: var(--text-secondary);
            margin-bottom: 10px;
        }

        .kpi-trend {
            font-size: 0.85em;
            padding: 5px 10px;
            border-radius: 12px;
            display: inline-block;
        }

        .kpi-trend.up {
            background: #e8f5e9;
            color: var(--success-color);
        }

        .kpi-trend.down {
            background: #ffebee;
            color: var(--danger-color);
        }

        .kpi-trend.neutral {
            background: #f5f5f5;
            color: var(--text-secondary);
        }

        /* ========================================
           SERVER HEALTH MAP
           ======================================== */
        .server-map {
            background: var(--card-bg);
            padding: 25px;
            border-radius: 12px;
            box-shadow: var(--shadow);
            margin-bottom: 30px;
        }

        .server-map h2 {
            margin-bottom: 20px;
            color: var(--primary-color);
        }

        .server-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 15px;
        }

        .server-card {
            border: 2px solid var(--border-color);
            border-radius: 8px;
            padding: 20px;
            transition: all 0.3s;
        }

        .server-card:hover {
            box-shadow: var(--shadow-lg);
            transform: translateY(-2px);
        }

        .server-card.status-online {
            border-color: var(--success-color);
            background: linear-gradient(135deg, #e8f5e9 0%, #ffffff 100%);
        }

        .server-card.status-degraded {
            border-color: var(--warning-color);
            background: linear-gradient(135deg, #fff3e0 0%, #ffffff 100%);
        }

        .server-card.status-offline {
            border-color: var(--danger-color);
            background: linear-gradient(135deg, #ffebee 0%, #ffffff 100%);
        }

        .server-icon {
            font-size: 2em;
            margin-bottom: 10px;
        }

        .server-name {
            font-weight: bold;
            font-size: 1.1em;
            margin-bottom: 5px;
        }

        .server-status {
            font-size: 0.9em;
            margin-bottom: 10px;
            font-weight: 500;
        }

        .server-status.online { color: var(--success-color); }
        .server-status.degraded { color: var(--warning-color); }
        .server-status.offline { color: var(--danger-color); }

        .server-metrics {
            font-size: 0.85em;
            color: var(--text-secondary);
            display: flex;
            flex-direction: column;
            gap: 3px;
        }

        /* ========================================
           TABLES
           ======================================== */
        .data-table {
            width: 100%;
            background: var(--card-bg);
            border-radius: 8px;
            overflow: hidden;
            box-shadow: var(--shadow);
            margin-bottom: 20px;
        }

        .data-table table {
            width: 100%;
            border-collapse: collapse;
        }

        .data-table thead {
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            color: white;
        }

        .data-table th {
            padding: 15px;
            text-align: left;
            font-weight: 600;
            cursor: pointer;
            user-select: none;
        }

        .data-table th:hover {
            background: rgba(255,255,255,0.1);
        }

        .data-table td {
            padding: 12px 15px;
            border-bottom: 1px solid var(--border-color);
        }

        .data-table tr:hover {
            background: #f5f5f5;
        }

        .data-table tr:last-child td {
            border-bottom: none;
        }

        /* Status badges */
        .status-badge {
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.85em;
            font-weight: 500;
            display: inline-block;
        }

        .status-badge.success {
            background: #e8f5e9;
            color: var(--success-color);
        }

        .status-badge.warning {
            background: #fff3e0;
            color: var(--warning-color);
        }

        .status-badge.danger {
            background: #ffebee;
            color: var(--danger-color);
        }

        /* ========================================
           QUICK ACTIONS
           ======================================== */
        .quick-actions {
            display: flex;
            gap: 15px;
            margin-bottom: 25px;
            flex-wrap: wrap;
        }

        .quick-actions button {
            background: linear-gradient(135deg, var(--primary-color), var(--secondary-color));
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 6px;
            cursor: pointer;
            font-size: 0.95em;
            transition: all 0.3s;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .quick-actions button:hover {
            transform: translateY(-2px);
            box-shadow: var(--shadow-lg);
        }

        /* ========================================
           NAVIGATOR (PM VIEW)
           ======================================== */
        .navigator {
            background: var(--card-bg);
            padding: 25px;
            border-radius: 12px;
            box-shadow: var(--shadow);
            margin-bottom: 25px;
        }

        .server-list {
            margin-top: 15px;
        }

        .server-item {
            border: 1px solid var(--border-color);
            border-radius: 8px;
            margin-bottom: 10px;
            overflow: hidden;
        }

        .server-header {
            padding: 15px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: background 0.2s;
        }

        .server-header:hover {
            background: #f5f5f5;
        }

        .expand-icon {
            transition: transform 0.3s;
            display: inline-block;
        }

        .expand-icon.expanded {
            transform: rotate(90deg);
        }

        .server-details {
            padding: 0 15px 15px 35px;
            display: none;
        }

        .server-details.visible {
            display: block;
        }

        .schema-list {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        .schema-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 10px;
            background: #f9f9f9;
            border-radius: 6px;
        }

        .schema-name {
            font-weight: 500;
        }

        .project-count {
            color: var(--text-secondary);
            font-size: 0.9em;
        }

        /* ========================================
           RESPONSIVE DESIGN
           ======================================== */
        @media (max-width: 768px) {
            .top-nav {
                flex-direction: column;
                gap: 15px;
            }

            .view-switcher {
                flex-wrap: wrap;
                justify-content: center;
            }

            .kpi-grid {
                grid-template-columns: 1fr;
            }

            .server-grid {
                grid-template-columns: 1fr;
            }

            .view-container {
                padding: 15px;
            }
        }

        /* ========================================
           UTILITY CLASSES
           ======================================== */
        .hidden {
            display: none !important;
        }

        .text-success { color: var(--success-color); }
        .text-warning { color: var(--warning-color); }
        .text-danger { color: var(--danger-color); }
        .text-muted { color: var(--text-secondary); }
    </style>
</head>
<body>
    <!-- Top Navigation -->
    <nav class="top-nav">
        <div class="logo">SimTreeNav Enterprise Portal</div>
        <div class="view-switcher">
            <button onclick="switchView('executive')" class="active" id="btn-executive">Executive</button>
            <button onclick="switchView('manager')" id="btn-manager">Project Manager</button>
            <button onclick="switchView('engineer')" id="btn-engineer">Engineer</button>
        </div>
        <div class="status-indicator">
            <span class="health operational" id="overall-health">All Systems Operational</span>
            <span class="last-refresh" id="last-refresh">Updated: Just now</span>
        </div>
    </nav>

    <!-- Executive View -->
    <div id="executive-view" class="view-container">
        <h1>Executive Dashboard</h1>

        <!-- KPI Cards -->
        <div class="kpi-grid">
            <div class="kpi-card">
                <div class="kpi-value">$uptime%</div>
                <div class="kpi-label">System Uptime</div>
                <div class="kpi-trend neutral">$onlineServers of $totalServers servers</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-value">$totalProjects</div>
                <div class="kpi-label">Active Projects</div>
                <div class="kpi-trend neutral">Across all servers</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-value">$activeUsers</div>
                <div class="kpi-label">Active Engineers</div>
                <div class="kpi-trend neutral">Working now</div>
            </div>
            <div class="kpi-card">
                <div class="kpi-value">$totalCheckouts</div>
                <div class="kpi-label">Items Checked Out</div>
                <div class="kpi-trend $(if ($staleCheckouts -gt 0) { 'down' } else { 'neutral' })">$staleCheckouts stale (>72h)</div>
            </div>
        </div>

        <!-- Server Health Map -->
        <div class="server-map">
            <h2>Infrastructure Health</h2>
            <div class="server-grid" id="exec-server-grid">
                <!-- Populated by JavaScript -->
            </div>
        </div>

        <!-- Scheduled Jobs Summary -->
        <div class="server-map">
            <h2>Scheduled Jobs</h2>
            <div class="data-table">
                <table>
                    <thead>
                        <tr>
                            <th>Job Name</th>
                            <th>Status</th>
                            <th>Last Run</th>
                            <th>Next Run</th>
                        </tr>
                    </thead>
                    <tbody id="exec-jobs-table">
                        <!-- Populated by JavaScript -->
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <!-- Project Manager View -->
    <div id="manager-view" class="view-container hidden">
        <h1>Project Manager Dashboard</h1>

        <!-- Quick Actions -->
        <div class="quick-actions">
            <button onclick="alert('Feature coming soon!')">📊 Generate Latest Dashboard</button>
            <button onclick="alert('Feature coming soon!')">⚠️ View Stale Checkouts ($staleCheckouts)</button>
            <button onclick="exportReport()">📥 Export Status Report</button>
        </div>

        <!-- Database Navigator -->
        <div class="navigator">
            <h2>Database Navigator</h2>
            <div class="server-list" id="pm-server-list">
                <!-- Populated by JavaScript -->
            </div>
        </div>

        <!-- User Activity Table -->
        <div class="server-map">
            <h2>Active Users</h2>
            <div class="data-table">
                <table>
                    <thead>
                        <tr>
                            <th onclick="sortTable('user')">User</th>
                            <th onclick="sortTable('checkouts')">Checkouts</th>
                            <th onclick="sortTable('servers')">Servers</th>
                            <th onclick="sortTable('longest')">Longest Checkout</th>
                            <th onclick="sortTable('activity')">Last Activity</th>
                        </tr>
                    </thead>
                    <tbody id="pm-users-table">
                        <!-- Populated by JavaScript -->
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <!-- Engineer View -->
    <div id="engineer-view" class="view-container hidden">
        <h1>Engineer Dashboard</h1>

        <!-- Technical Quick Actions -->
        <div class="quick-actions">
            <button onclick="alert('Feature coming soon!')">🌳 Run Tree Generator</button>
            <button onclick="alert('Feature coming soon!')">🔄 Refresh All Caches</button>
            <button onclick="alert('Feature coming soon!')">🔌 Test All Connections</button>
            <button onclick="alert('Feature coming soon!')">📋 View Generation Logs</button>
        </div>

        <!-- Detailed Server Metrics -->
        <div class="server-map">
            <h2>Server Performance Metrics</h2>
            <div class="data-table">
                <table>
                    <thead>
                        <tr>
                            <th>Server</th>
                            <th>Instance</th>
                            <th>Status</th>
                            <th>Response Time</th>
                            <th>Active Sessions</th>
                            <th>Schemas</th>
                            <th>Projects</th>
                        </tr>
                    </thead>
                    <tbody id="eng-servers-table">
                        <!-- Populated by JavaScript -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Cache Health -->
        <div class="server-map">
            <h2>Cache Status</h2>
            <div class="data-table">
                <table>
                    <thead>
                        <tr>
                            <th>Server</th>
                            <th>Icon Cache (7d TTL)</th>
                            <th>Tree Cache (24h TTL)</th>
                            <th>Activity Cache (1h TTL)</th>
                        </tr>
                    </thead>
                    <tbody id="eng-cache-table">
                        <!-- Populated by JavaScript -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- Scheduled Jobs Detailed -->
        <div class="server-map">
            <h2>Scheduled Jobs Status</h2>
            <div class="data-table">
                <table>
                    <thead>
                        <tr>
                            <th>Job Name</th>
                            <th>Status</th>
                            <th>Last Run</th>
                            <th>Next Run</th>
                            <th>State</th>
                            <th>Error</th>
                        </tr>
                    </thead>
                    <tbody id="eng-jobs-table">
                        <!-- Populated by JavaScript -->
                    </tbody>
                </table>
            </div>
        </div>
    </div>

    <!-- Embedded Data -->
    <script>
        const portalData = {
            serverHealth: $serverHealthJson,
            userActivity: $userActivityJson,
            scheduledJobs: $scheduledJobsJson
        };

        // View switching
        function switchView(view) {
            // Hide all views
            document.querySelectorAll('.view-container').forEach(v => v.classList.add('hidden'));

            // Show selected view
            document.getElementById(view + '-view').classList.remove('hidden');

            // Update button states
            document.querySelectorAll('.view-switcher button').forEach(b => b.classList.remove('active'));
            document.getElementById('btn-' + view).classList.add('active');
        }

        // Initialize Executive View
        function initExecutiveView() {
            const serverGrid = document.getElementById('exec-server-grid');
            serverGrid.innerHTML = '';

            portalData.serverHealth.servers.forEach(server => {
                const statusClass = 'status-' + server.status;
                const statusIcon = server.status === 'online' ? '🟢' : (server.status === 'degraded' ? '🟡' : '🔴');

                const card = document.createElement('div');
                card.className = 'server-card ' + statusClass;
                card.innerHTML = ``
                    <div class="server-icon">`${statusIcon}</div>
                    <div class="server-name">`${server.name} (`${server.instance})</div>
                    <div class="server-status `${server.status}">`${server.status.toUpperCase()}</div>
                    <div class="server-metrics">
                        <span>Response: `${server.responseTime}ms</span>
                        <span>Sessions: `${server.activeSessions}</span>
                        <span>Schemas: `${server.schemas.length}</span>
                    </div>
                ``;
                serverGrid.appendChild(card);
            });

            // Populate jobs table
            const jobsTable = document.getElementById('exec-jobs-table');
            jobsTable.innerHTML = '';

            if (portalData.scheduledJobs.jobs.length === 0) {
                jobsTable.innerHTML = '<tr><td colspan="4" style="text-align:center;color:#999;">No scheduled jobs configured</td></tr>';
            } else {
                portalData.scheduledJobs.jobs.forEach(job => {
                    const statusClass = job.status === 'success' ? 'success' : (job.status === 'failed' ? 'danger' : 'warning');
                    const row = document.createElement('tr');
                    row.innerHTML = ``
                        <td>`${job.name}</td>
                        <td><span class="status-badge `${statusClass}">`${job.status}</span></td>
                        <td>`${job.lastRun || 'Never'}</td>
                        <td>`${job.nextRun || 'Not scheduled'}</td>
                    ``;
                    jobsTable.appendChild(row);
                });
            }
        }

        // Initialize Project Manager View
        function initManagerView() {
            const serverList = document.getElementById('pm-server-list');
            serverList.innerHTML = '';

            portalData.serverHealth.servers.forEach((server, idx) => {
                const div = document.createElement('div');
                div.className = 'server-item';
                div.innerHTML = ``
                    <div class="server-header" onclick="toggleServer('server`${idx}')">
                        <div>
                            <span class="expand-icon" id="icon-server`${idx}">▶</span>
                            <span class="server-name">`${server.name} (`${server.instance})</span>
                        </div>
                        <span class="server-status `${server.status}">● `${server.status.toUpperCase()} (`${server.responseTime}ms)</span>
                    </div>
                    <div id="server`${idx}" class="server-details">
                        <div class="schema-list">
                            `${server.schemas.map(s => ``
                                <div class="schema-item">
                                    <span class="schema-name">`${s.name}</span>
                                    <span class="project-count">`${s.projectCount} projects</span>
                                </div>
                            ``).join('')}
                        </div>
                    </div>
                ``;
                serverList.appendChild(div);
            });

            // Populate users table
            const usersTable = document.getElementById('pm-users-table');
            usersTable.innerHTML = '';

            if (portalData.userActivity.users.length === 0) {
                usersTable.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#999;">No active users</td></tr>';
            } else {
                portalData.userActivity.users.forEach(user => {
                    const row = document.createElement('tr');
                    const staleClass = user.longestCheckout > 72 ? 'text-danger' : '';
                    row.innerHTML = ``
                        <td>`${user.name}</td>
                        <td>`${user.checkedOutItems}</td>
                        <td>`${user.servers.join(', ')}</td>
                        <td class="`${staleClass}">`${user.longestCheckout} hours</td>
                        <td>`${user.lastActivity || 'Unknown'}</td>
                    ``;
                    usersTable.appendChild(row);
                });
            }
        }

        // Initialize Engineer View
        function initEngineerView() {
            // Servers table
            const serversTable = document.getElementById('eng-servers-table');
            serversTable.innerHTML = '';

            portalData.serverHealth.servers.forEach(server => {
                const totalProjects = server.schemas.reduce((sum, s) => sum + s.projectCount, 0);
                const statusClass = server.status === 'online' ? 'text-success' : (server.status === 'degraded' ? 'text-warning' : 'text-danger');

                const row = document.createElement('tr');
                row.innerHTML = ``
                    <td>`${server.name}</td>
                    <td>`${server.instance}</td>
                    <td class="`${statusClass}">`${server.status.toUpperCase()}</td>
                    <td>`${server.responseTime}ms</td>
                    <td>`${server.activeSessions}</td>
                    <td>`${server.schemas.length}</td>
                    <td>`${totalProjects}</td>
                ``;
                serversTable.appendChild(row);
            });

            // Cache table
            const cacheTable = document.getElementById('eng-cache-table');
            cacheTable.innerHTML = '';

            portalData.serverHealth.servers.forEach(server => {
                const row = document.createElement('tr');
                const iconStatus = server.cacheHealth.iconCache === 'fresh' ? '✓ Fresh' : (server.cacheHealth.iconCache === 'stale' ? '⚠ Stale' : '✗ Missing');
                const treeStatus = server.cacheHealth.treeCache === 'fresh' ? '✓ Fresh' : (server.cacheHealth.treeCache === 'stale' ? '⚠ Stale' : '✗ Missing');
                const activityStatus = server.cacheHealth.activityCache === 'fresh' ? '✓ Fresh' : (server.cacheHealth.activityCache === 'stale' ? '⚠ Stale' : '✗ Missing');

                row.innerHTML = ``
                    <td>`${server.name}</td>
                    <td>`${iconStatus}</td>
                    <td>`${treeStatus}</td>
                    <td>`${activityStatus}</td>
                ``;
                cacheTable.appendChild(row);
            });

            // Jobs table
            const jobsTable = document.getElementById('eng-jobs-table');
            jobsTable.innerHTML = '';

            if (portalData.scheduledJobs.jobs.length === 0) {
                jobsTable.innerHTML = '<tr><td colspan="6" style="text-align:center;color:#999;">No scheduled jobs configured</td></tr>';
            } else {
                portalData.scheduledJobs.jobs.forEach(job => {
                    const statusClass = job.status === 'success' ? 'success' : (job.status === 'failed' ? 'danger' : 'warning');
                    const row = document.createElement('tr');
                    row.innerHTML = ``
                        <td>`${job.name}</td>
                        <td><span class="status-badge `${statusClass}">`${job.status}</span></td>
                        <td>`${job.lastRun || 'Never'}</td>
                        <td>`${job.nextRun || 'Not scheduled'}</td>
                        <td>`${job.state}</td>
                        <td class="text-danger">`${job.errorMessage || '-'}</td>
                    ``;
                    jobsTable.appendChild(row);
                });
            }
        }

        // Toggle server expansion in PM view
        function toggleServer(serverId) {
            const details = document.getElementById(serverId);
            const icon = document.getElementById('icon-' + serverId);

            if (details.classList.contains('visible')) {
                details.classList.remove('visible');
                icon.classList.remove('expanded');
            } else {
                details.classList.add('visible');
                icon.classList.add('expanded');
            }
        }

        // Export report
        function exportReport() {
            const report = {
                timestamp: new Date().toISOString(),
                servers: portalData.serverHealth,
                users: portalData.userActivity,
                jobs: portalData.scheduledJobs
            };

            const blob = new Blob([JSON.stringify(report, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'simtreenav-status-report-' + new Date().toISOString().split('T')[0] + '.json';
            a.click();
            URL.revokeObjectURL(url);
        }

        // Update overall health status
        function updateOverallHealth() {
            const health = document.getElementById('overall-health');
            const degraded = portalData.serverHealth.summary.degradedServers;
            const offline = portalData.serverHealth.summary.offlineServers;

            if (offline > 0) {
                health.className = 'health critical';
                health.textContent = offline + ' Server(s) Offline';
            } else if (degraded > 0) {
                health.className = 'health degraded';
                health.textContent = degraded + ' Server(s) Degraded';
            } else {
                health.className = 'health operational';
                health.textContent = 'All Systems Operational';
            }
        }

        // Update last refresh time
        function updateRefreshTime() {
            const refresh = document.getElementById('last-refresh');
            const timestamp = new Date(portalData.serverHealth.timestamp);
            const now = new Date();
            const diffMs = now - timestamp;
            const diffMins = Math.floor(diffMs / 60000);

            if (diffMins < 1) {
                refresh.textContent = 'Updated: Just now';
            } else if (diffMins === 1) {
                refresh.textContent = 'Updated: 1 minute ago';
            } else if (diffMins < 60) {
                refresh.textContent = 'Updated: ' + diffMins + ' minutes ago';
            } else {
                const diffHours = Math.floor(diffMins / 60);
                refresh.textContent = 'Updated: ' + diffHours + ' hour(s) ago';
            }
        }

        // Initialize on page load
        window.addEventListener('DOMContentLoaded', function() {
            initExecutiveView();
            initManagerView();
            initEngineerView();
            updateOverallHealth();
            updateRefreshTime();

            // Update refresh time every minute
            setInterval(updateRefreshTime, 60000);
        });
    </script>
</body>
</html>
"@

# Ensure output directory exists
$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Write HTML file
$html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

$fileSize = (Get-Item $OutputPath).Length / 1KB

Write-Host "========================================" -ForegroundColor Green
Write-Host "  Portal Generated Successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output File: $OutputPath" -ForegroundColor Cyan
Write-Host "File Size:   $([math]::Round($fileSize, 1)) KB" -ForegroundColor Cyan
Write-Host ""
Write-Host "Portal Features:" -ForegroundColor Yellow
Write-Host "  ✓ Executive Dashboard (KPIs, server health, jobs)" -ForegroundColor Green
Write-Host "  ✓ Project Manager Dashboard (navigator, users, actions)" -ForegroundColor Green
Write-Host "  ✓ Engineer Dashboard (metrics, cache status, detailed jobs)" -ForegroundColor Green
Write-Host ""

return $OutputPath
