# Generate Management Dashboard HTML
# Purpose: Transform management.json into interactive HTML dashboard with 6 views
# Agent: 04 (Frontend)
# Date: 2026-01-22

param(
    [Parameter(Mandatory=$true)]
    [string]$DataFile,  # Path to management.json from Agent 03

    [string]$OutputFile = ""  # Auto-generated from metadata if empty
)

# Start timer
$scriptTimer = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Management Dashboard Generator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Input:  $DataFile" -ForegroundColor Gray
Write-Host ""

# Validate input file exists
if (-not (Test-Path $DataFile)) {
    Write-Error "ERROR: Data file not found: $DataFile"
    exit 1
}

# Load JSON data
Write-Host "Loading JSON data..." -ForegroundColor Yellow
try {
    $jsonContent = Get-Content $DataFile -Raw -Encoding UTF8
    $data = $jsonContent | ConvertFrom-Json
    Write-Host "  ✓ JSON loaded successfully" -ForegroundColor Green
}
catch {
    Write-Error "ERROR: Failed to parse JSON: $_"
    Write-Host ""
    Write-Host "The JSON file appears to be malformed or corrupt." -ForegroundColor Red
    Write-Host "Please regenerate the data file using get-management-data.ps1" -ForegroundColor Yellow
    exit 1
}

# Determine output file name
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $schema = if ($data.metadata.schema) { $data.metadata.schema } else { "UNKNOWN" }
    $projectId = if ($data.metadata.projectId) { $data.metadata.projectId } else { "UNKNOWN" }
    $OutputFile = "management-dashboard-$schema-$projectId.html"
}

Write-Host "Generating dashboard HTML..." -ForegroundColor Yellow
Write-Host "  Schema:     $($data.metadata.schema)" -ForegroundColor Gray
Write-Host "  Project ID: $($data.metadata.projectId)" -ForegroundColor Gray
Write-Host "  Date Range: $($data.metadata.startDate) to $($data.metadata.endDate)" -ForegroundColor Gray
Write-Host ""

# Calculate summary statistics
$stats = @{
    projectDatabase = @($data.projectDatabase).Count
    resourceLibrary = @($data.resourceLibrary).Count
    partLibrary = @($data.partLibrary).Count
    ipaAssembly = @($data.ipaAssembly).Count
    studySummary = @($data.studySummary).Count
    studyResources = @($data.studyResources).Count
    studyPanels = @($data.studyPanels).Count
    studyOperations = @($data.studyOperations).Count
    studyMovements = @($data.studyMovements).Count
    studyWelds = @($data.studyWelds).Count
    userActivity = @($data.userActivity).Count
    treeChanges = @($data.treeChanges).Count
}

Write-Host "Data Summary:" -ForegroundColor Cyan
Write-Host "  Project Database: $($stats.projectDatabase) items" -ForegroundColor Gray
Write-Host "  Resource Library: $($stats.resourceLibrary) items" -ForegroundColor Gray
Write-Host "  Part Library:     $($stats.partLibrary) items" -ForegroundColor Gray
Write-Host "  IPA Assembly:     $($stats.ipaAssembly) items" -ForegroundColor Gray
Write-Host "  Study Summary:    $($stats.studySummary) items" -ForegroundColor Gray
Write-Host "  Study Resources:  $($stats.studyResources) items" -ForegroundColor Gray
Write-Host "  Study Panels:     $($stats.studyPanels) items" -ForegroundColor Gray
Write-Host "  Study Operations: $($stats.studyOperations) items" -ForegroundColor Gray
Write-Host "  Study Movements:  $($stats.studyMovements) items" -ForegroundColor Gray
Write-Host "  Study Welds:      $($stats.studyWelds) items" -ForegroundColor Gray
Write-Host "  User Activity:    $($stats.userActivity) users" -ForegroundColor Gray
Write-Host "  Tree Changes:     $($stats.treeChanges) changes" -ForegroundColor Gray
Write-Host ""

# Embed JSON safely inside an application/json script tag (escape '<' to avoid HTML parsing)
$jsonDataForHtml = $jsonContent -replace '<', '\\u003c'

# Generate HTML
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Management Dashboard - $($data.metadata.schema) - Project $($data.metadata.projectId)</title>
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
            --primary-color: #2c3e50;
            --secondary-color: #3498db;
            --accent-color: #e74c3c;
            --success-color: #27ae60;
            --warning-color: #f39c12;
            --info-color: #3498db;
            --light-bg: #ecf0f1;
            --dark-bg: #34495e;
            --text-color: #2c3e50;
            --border-color: #bdc3c7;
            --shadow: 0 2px 4px rgba(0,0,0,0.1);
            --shadow-hover: 0 4px 8px rgba(0,0,0,0.15);
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: var(--text-color);
            line-height: 1.6;
            min-height: 100vh;
            padding: 20px;
        }

        .container {
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            border-radius: 8px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }

        /* ========================================
           HEADER
           ======================================== */
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }

        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            font-weight: 700;
        }

        .header .meta {
            font-size: 0.95em;
            opacity: 0.9;
        }

        .header .meta span {
            margin: 0 15px;
        }

        /* ========================================
           NAVIGATION TABS
           ======================================== */
        .nav-tabs {
            display: flex;
            background: var(--dark-bg);
            overflow-x: auto;
            position: sticky;
            top: 0;
            z-index: 100;
        }

        .nav-tab {
            flex: 1;
            min-width: 150px;
            padding: 15px 20px;
            background: transparent;
            color: white;
            border: none;
            cursor: pointer;
            font-size: 0.9em;
            font-weight: 500;
            transition: all 0.3s ease;
            border-bottom: 3px solid transparent;
        }

        .nav-tab:hover {
            background: rgba(255,255,255,0.1);
        }

        .nav-tab.active {
            background: white;
            color: var(--primary-color);
            border-bottom-color: var(--secondary-color);
        }

        /* ========================================
           VIEW CONTAINERS
           ======================================== */
        .view-container {
            display: none;
            padding: 30px;
            animation: fadeIn 0.3s ease;
        }

        .view-container.active {
            display: block;
        }

        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(10px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .view-header {
            margin-bottom: 20px;
            padding-bottom: 15px;
            border-bottom: 2px solid var(--border-color);
        }

        .view-header h2 {
            font-size: 1.8em;
            color: var(--primary-color);
            margin-bottom: 5px;
        }

        .view-header p {
            color: #7f8c8d;
            font-size: 0.95em;
        }

        /* ========================================
           TABLES
           ======================================== */
        .data-table {
            width: 100%;
            border-collapse: collapse;
            background: white;
            box-shadow: var(--shadow);
            border-radius: 8px;
            overflow: hidden;
        }

        .data-table thead {
            background: var(--primary-color);
            color: white;
        }

        .data-table th {
            padding: 15px;
            text-align: left;
            font-weight: 600;
            cursor: pointer;
            user-select: none;
            position: relative;
        }

        .data-table th:hover {
            background: rgba(255,255,255,0.1);
        }

        .data-table th.sortable::after {
            content: '⇅';
            position: absolute;
            right: 10px;
            opacity: 0.5;
        }

        .data-table th.sorted-asc::after {
            content: '↑';
            opacity: 1;
        }

        .data-table th.sorted-desc::after {
            content: '↓';
            opacity: 1;
        }

        .data-table tbody tr {
            border-bottom: 1px solid var(--border-color);
            transition: background 0.2s ease;
        }

        .data-table tbody tr:hover {
            background: var(--light-bg);
        }

        .data-table td {
            padding: 12px 15px;
        }

        /* ========================================
           BADGES & INDICATORS
           ======================================== */
        .badge {
            display: inline-block;
            padding: 4px 12px;
            border-radius: 12px;
            font-size: 0.85em;
            font-weight: 600;
        }

        .badge-success {
            background: #d4edda;
            color: #155724;
        }

        .badge-warning {
            background: #fff3cd;
            color: #856404;
        }

        .badge-info {
            background: #d1ecf1;
            color: #0c5460;
        }

        .badge-danger {
            background: #f8d7da;
            color: #721c24;
        }

        .badge-primary {
            background: #cfe2ff;
            color: #084298;
        }

        .badge-confirmed {
            background: #d4edda;
            color: #155724;
        }

        .badge-likely {
            background: #d1ecf1;
            color: #0c5460;
        }

        .badge-checkout {
            background: #fff3cd;
            color: #856404;
        }

        .badge-unattributed {
            background: #e2e3e5;
            color: #6c757d;
        }

        .evidence-details {
            margin-top: 8px;
            font-size: 0.85em;
            color: #555;
        }

        .evidence-details summary {
            cursor: pointer;
            color: var(--secondary-color);
            font-weight: 600;
            margin-bottom: 6px;
        }

        .evidence-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 8px;
        }

        .context-line {
            font-size: 12px;
            color: #6b7280;
            margin-top: 6px;
        }

        /* Movement type indicators */
        .movement-simple {
            color: var(--success-color);
            font-weight: 600;
        }

        .movement-world {
            background: #fff3cd;
            color: #856404;
            padding: 4px 8px;
            border-radius: 4px;
            border-left: 3px solid var(--warning-color);
        }

        .movement-weld {
            color: var(--info-color);
            font-weight: 600;
        }

        .movement-rotation {
            color: #9b59b6;
            font-weight: 600;
        }

        /* ========================================
           EXPANDABLE TREE
           ======================================== */
        .tree-item {
            margin-bottom: 10px;
            border: 1px solid var(--border-color);
            border-radius: 6px;
            overflow: hidden;
            background: white;
        }

        .tree-header {
            padding: 15px;
            background: var(--light-bg);
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
            transition: background 0.2s ease;
        }

        .tree-header:hover {
            background: #d5dbdb;
        }

        .tree-header .title {
            font-weight: 600;
            color: var(--primary-color);
        }

        .tree-header .toggle {
            font-size: 1.2em;
            transition: transform 0.3s ease;
        }

        .tree-header .toggle.expanded {
            transform: rotate(90deg);
        }

        .tree-content {
            max-height: 0;
            overflow: hidden;
            transition: max-height 0.3s ease;
        }

        .tree-content.expanded {
            max-height: 2000px;
        }

        .tree-section {
            padding: 15px;
            border-top: 1px solid var(--border-color);
        }

        .tree-section h4 {
            color: var(--secondary-color);
            margin-bottom: 10px;
            font-size: 1em;
        }

        .tree-list {
            list-style: none;
            padding-left: 20px;
        }

        .tree-list li {
            padding: 5px 0;
            color: #555;
        }

        .tree-list li::before {
            content: '▪';
            color: var(--secondary-color);
            margin-right: 8px;
        }

        /* ========================================
           SEARCH & FILTERS
           ======================================== */
        .controls {
            display: flex;
            gap: 15px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }

        .search-box {
            flex: 1;
            min-width: 250px;
            padding: 12px 15px;
            border: 2px solid var(--border-color);
            border-radius: 6px;
            font-size: 1em;
            transition: border-color 0.3s ease;
        }

        .search-box:focus {
            outline: none;
            border-color: var(--secondary-color);
        }

        .filter-select {
            padding: 12px 15px;
            border: 2px solid var(--border-color);
            border-radius: 6px;
            font-size: 1em;
            background: white;
            cursor: pointer;
            min-width: 150px;
        }

        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 6px;
            font-size: 1em;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
        }

        .btn-primary {
            background: var(--secondary-color);
            color: white;
        }

        .btn-primary:hover {
            background: #2980b9;
            box-shadow: var(--shadow-hover);
        }

        .btn-success {
            background: var(--success-color);
            color: white;
        }

        .btn-success:hover {
            background: #229954;
            box-shadow: var(--shadow-hover);
        }

        /* ========================================
           BAR CHART
           ======================================== */
        .chart-container {
            margin: 20px 0;
        }

        .bar-chart {
            margin-top: 20px;
        }

        .bar-item {
            margin-bottom: 15px;
        }

        .bar-label {
            display: flex;
            justify-content: space-between;
            margin-bottom: 5px;
            font-size: 0.9em;
        }

        .bar-label .name {
            font-weight: 600;
            color: var(--primary-color);
        }

        .bar-label .value {
            color: #7f8c8d;
        }

        .bar-track {
            height: 30px;
            background: var(--light-bg);
            border-radius: 15px;
            overflow: hidden;
            position: relative;
        }

        .bar-fill {
            height: 100%;
            background: linear-gradient(90deg, var(--secondary-color), var(--info-color));
            border-radius: 15px;
            transition: width 0.5s ease;
            display: flex;
            align-items: center;
            justify-content: flex-end;
            padding-right: 10px;
            color: white;
            font-size: 0.85em;
            font-weight: 600;
        }

        /* ========================================
           TIMELINE
           ======================================== */
        .timeline {
            position: relative;
            padding-left: 30px;
        }

        .timeline::before {
            content: '';
            position: absolute;
            left: 10px;
            top: 0;
            bottom: 0;
            width: 2px;
            background: var(--border-color);
        }

        .timeline-item {
            position: relative;
            margin-bottom: 20px;
            padding: 15px;
            background: white;
            border: 1px solid var(--border-color);
            border-radius: 6px;
            box-shadow: var(--shadow);
        }

        .timeline-item::before {
            content: '';
            position: absolute;
            left: -24px;
            top: 20px;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            background: var(--secondary-color);
            border: 2px solid white;
        }

        .timeline-time {
            font-size: 0.85em;
            color: #7f8c8d;
            margin-bottom: 5px;
        }

        .timeline-content {
            color: var(--text-color);
        }

        .timeline-user {
            font-weight: 600;
            color: var(--secondary-color);
        }

        /* ========================================
           TREE CHANGES
           ======================================== */
        .tree-change-layout {
            display: grid;
            grid-template-columns: 1.4fr 1fr;
            gap: 20px;
        }

        .tree-change-list {
            min-height: 300px;
        }

        .tree-change-item {
            cursor: pointer;
            transition: border-color 0.2s ease, box-shadow 0.2s ease;
        }

        .tree-change-item.selected {
            border-color: var(--secondary-color);
            box-shadow: var(--shadow-hover);
        }

        .tree-change-details {
            border: 1px solid var(--border-color);
            border-radius: 6px;
            padding: 15px;
            background: #f9fafb;
            box-shadow: var(--shadow);
        }

        .tree-change-details h3 {
            margin-bottom: 10px;
            color: var(--primary-color);
        }

        .tree-change-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
            gap: 10px;
            margin-bottom: 10px;
            font-size: 0.9em;
        }

        .tree-change-badges {
            display: flex;
            flex-wrap: wrap;
            gap: 6px;
            margin-top: 6px;
        }

        .badge-rename {
            background: #f1c40f;
            color: #2c3e50;
        }

        .badge-move {
            background: #3498db;
            color: white;
        }

        .badge-add {
            background: #27ae60;
            color: white;
        }

        .badge-remove {
            background: #e74c3c;
            color: white;
        }

        .badge-structure {
            background: #8e44ad;
            color: white;
        }

        .badge-resource {
            background: #16a085;
            color: white;
        }

        .badge-possible {
            background: #95a5a6;
            color: white;
        }

        .tree-change-section {
            margin-top: 12px;
        }

        .tree-change-section h4 {
            margin-bottom: 6px;
            color: var(--primary-color);
            font-size: 0.95em;
        }

        .tree-change-coords {
            font-family: Consolas, 'Courier New', monospace;
            font-size: 0.9em;
            background: #ffffff;
            padding: 8px;
            border: 1px solid var(--border-color);
            border-radius: 4px;
        }

        @media (max-width: 1100px) {
            .tree-change-layout {
                grid-template-columns: 1fr;
            }
        }

        /* ========================================
           EMPTY STATE
           ======================================== */
        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: #7f8c8d;
        }

        .empty-state p {
            font-size: 1.2em;
            margin-bottom: 10px;
        }

        .empty-state .hint {
            font-size: 0.9em;
            color: #95a5a6;
        }

        /* ========================================
           ERROR STATE
           ======================================== */
        .error-state {
            text-align: center;
            padding: 60px 20px;
            background: #f8d7da;
            border: 2px solid #f5c6cb;
            border-radius: 8px;
            color: #721c24;
        }

        .error-state h3 {
            margin-bottom: 10px;
        }

        /* ========================================
           RESPONSIVE DESIGN
           ======================================== */
        @media (max-width: 768px) {
            .header h1 {
                font-size: 1.8em;
            }

            .nav-tab {
                min-width: 120px;
                padding: 12px 15px;
                font-size: 0.85em;
            }

            .view-container {
                padding: 15px;
            }

            .controls {
                flex-direction: column;
            }

            .search-box,
            .filter-select {
                width: 100%;
            }

            .data-table {
                font-size: 0.9em;
            }

            .data-table th,
            .data-table td {
                padding: 8px 10px;
            }
        }

        /* ========================================
           UTILITY CLASSES
           ======================================== */
        .text-center {
            text-align: center;
        }

        .mb-20 {
            margin-bottom: 20px;
        }

        .hidden {
            display: none !important;
        }

        .scrollable {
            overflow-x: auto;
        }

        .checkbox-group {
            display: flex;
            gap: 12px;
            flex-wrap: wrap;
            align-items: center;
            font-size: 0.9em;
        }

        .checkbox-group label {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            cursor: pointer;
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header -->
        <div class="header">
            <h1>Management Dashboard</h1>
            <div class="meta">
                <span><strong>Schema:</strong> $($data.metadata.schema)</span>
                <span><strong>Project ID:</strong> $($data.metadata.projectId)</span>
                <span><strong>Period:</strong> $($data.metadata.startDate) to $($data.metadata.endDate)</span>
                <span><strong>Generated:</strong> $($data.metadata.generatedAt)</span>
            </div>
        </div>

        <!-- Navigation Tabs -->
        <div class="nav-tabs">
            <button class="nav-tab active" onclick="showView('view1')">Work Type Summary</button>
            <button class="nav-tab" onclick="showView('view2')">Active Studies</button>
            <button class="nav-tab" onclick="showView('view3')">Movement Activity</button>
            <button class="nav-tab" onclick="showView('view9')">Tree Changes</button>
            <button class="nav-tab" onclick="showView('view4')">User Activity</button>
            <button class="nav-tab" onclick="showView('view5')">Timeline</button>
            <button class="nav-tab" onclick="showView('view6')">Activity Log</button>
            <button class="nav-tab" onclick="showView('view7')">Study Health</button>
            <button class="nav-tab" onclick="showView('view8')">Resource Conflicts</button>
        </div>

        <!-- View 1: Work Type Summary -->
        <div id="view1" class="view-container active">
            <div class="view-header">
                <h2>Work Type Summary</h2>
                <p>High-level overview of activity across all work types</p>
            </div>
            <div class="scrollable">
                <table class="data-table" id="workTypeSummaryTable">
                    <thead>
                        <tr>
                            <th class="sortable" onclick="sortTable('workTypeSummaryTable', 0)">Work Type</th>
                            <th class="sortable" onclick="sortTable('workTypeSummaryTable', 1)">Active Items</th>
                            <th class="sortable" onclick="sortTable('workTypeSummaryTable', 2)">Modified Items</th>
                            <th class="sortable" onclick="sortTable('workTypeSummaryTable', 3)">Unique Users</th>
                            <th>Change Summary</th>
                        </tr>
                    </thead>
                    <tbody id="workTypeSummaryBody">
                        <!-- Populated by JavaScript -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- View 2: Active Studies - Detailed View -->
        <div id="view2" class="view-container">
            <div class="view-header">
                <h2>Active Studies - Detailed View</h2>
                <p>Deep dive into study node activity with expandable sections</p>
            </div>
            <div id="activeStudiesContainer">
                <!-- Populated by JavaScript -->
            </div>
        </div>

        <!-- View 3: Movement/Location Activity -->
        <div id="view3" class="view-container">
            <div class="view-header">
                <h2>Movement/Location Activity</h2>
                <p>Track robot/resource position changes</p>
            </div>
            <div class="scrollable">
                <table class="data-table" id="movementActivityTable">
                    <thead>
                        <tr>
                            <th class="sortable" onclick="sortTable('movementActivityTable', 0)">Study Name</th>
                            <th class="sortable" onclick="sortTable('movementActivityTable', 1)">Movement Type</th>
                            <th class="sortable" onclick="sortTable('movementActivityTable', 2)">Modified By</th>
                            <th class="sortable" onclick="sortTable('movementActivityTable', 3)">Last Modified</th>
                        </tr>
                    </thead>
                    <tbody id="movementActivityBody">
                        <!-- Populated by JavaScript -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- View 9: Tree Changes -->
        <div id="view9" class="view-container">
            <div class="view-header">
                <h2>Tree Changes</h2>
                <p>Renames, movements, structure, and topology changes from tree snapshots</p>
            </div>
            <div class="controls">
                <input type="text" class="search-box" id="treeChangeSearch" placeholder="Search tree changes..." oninput="filterTreeChanges()">
                <select class="filter-select" id="treeChangeTypeFilter" onchange="filterTreeChanges()">
                    <option value="">All Change Types</option>
                </select>
                <select class="filter-select" id="treeChangeStudyFilter" onchange="filterTreeChanges()">
                    <option value="">All Studies</option>
                </select>
                <select class="filter-select" id="treeChangeMovementFilter" onchange="filterTreeChanges()">
                    <option value="">All Movement Classes</option>
                    <option value="SIMPLE">Simple (&lt;1000mm)</option>
                    <option value="WORLD">World (&gt;=1000mm)</option>
                </select>
                <select class="filter-select" id="treeChangeMappingFilter" onchange="filterTreeChanges()">
                    <option value="">All Mapping Types</option>
                </select>
                <div class="checkbox-group" id="treeChangeConfidenceFilters">
                    <span style="font-weight: 600;">Confidence:</span>
                    <label><input type="checkbox" value="confirmed" checked onchange="filterTreeChanges()"> Confirmed</label>
                    <label><input type="checkbox" value="likely" checked onchange="filterTreeChanges()"> Likely</label>
                    <label><input type="checkbox" value="possible" checked onchange="filterTreeChanges()"> Possible</label>
                    <label><input type="checkbox" value="unattributed" checked onchange="filterTreeChanges()"> Unattributed</label>
                </div>
            </div>
            <div class="tree-change-layout">
                <div class="tree-change-list">
                    <div class="timeline" id="treeChangesTimeline">
                        <!-- Populated by JavaScript -->
                    </div>
                </div>
                <div class="tree-change-details" id="treeChangeDetails">
                    <div class="empty-state">
                        <p>Select a tree change to view details</p>
                        <div class="hint">Details include evidence, provenance, and snapshot references.</div>
                    </div>
                </div>
            </div>
        </div>

        <!-- View 4: User Activity Breakdown -->
        <div id="view4" class="view-container">
            <div class="view-header">
                <h2>User Activity Breakdown</h2>
                <p>Individual user contributions across work types</p>
            </div>
            <div class="controls">
                <select class="filter-select" id="userSelector" onchange="renderUserActivity()">
                    <option value="">Select a user...</option>
                    <!-- Populated by JavaScript -->
                </select>
            </div>
            <div class="chart-container" id="userActivityChart">
                <div class="empty-state">
                    <p>Select a user to view their activity breakdown</p>
                </div>
            </div>
        </div>

        <!-- View 5: Recent Activity Timeline -->
        <div id="view5" class="view-container">
            <div class="view-header">
                <h2>Recent Activity Timeline</h2>
                <p>Chronological event stream (newest first)</p>
            </div>
            <div class="controls">
                <input type="text" class="search-box" id="timelineSearch" placeholder="Search timeline..." oninput="filterTimeline()">
                <select class="filter-select" id="timelineWorkTypeFilter" onchange="filterTimeline()">
                    <option value="">All Work Types</option>
                    <!-- Populated by JavaScript -->
                </select>
                <select class="filter-select" id="timelinePhaseFilter" onchange="filterTimeline()">
                    <option value="">All Workflow Phases</option>
                    <!-- Populated by JavaScript -->
                </select>
                <select class="filter-select" id="timelineUserFilter" onchange="filterTimeline()">
                    <option value="">All Users</option>
                    <!-- Populated by JavaScript -->
                </select>
                <!-- TODO: Enable when context.allocationState is populated in events
                <select class="filter-select" id="timelineAllocationStateFilter" onchange="filterTimeline()">
                    <option value="">All Allocation States</option>
                    <! Populated by JavaScript >
                </select>
                -->
                <div class="checkbox-group" id="timelineConfidenceFilters">
                    <span style="font-weight: 600;">Confidence:</span>
                    <label><input type="checkbox" value="confirmed" checked onchange="filterTimeline()"> Confirmed</label>
                    <label><input type="checkbox" value="likely" checked onchange="filterTimeline()"> Likely</label>
                    <label><input type="checkbox" value="checkout_only" checked onchange="filterTimeline()"> Checkout Only</label>
                    <label><input type="checkbox" value="unattributed" checked onchange="filterTimeline()"> Unattributed</label>
                </div>
            </div>
            <div class="timeline" id="timelineContainer">
                <!-- Populated by JavaScript -->
            </div>
        </div>

        <!-- View 6: Detailed Activity Log -->
        <div id="view6" class="view-container">
            <div class="view-header">
                <h2>Detailed Activity Log</h2>
                <p>Searchable, filterable audit trail with export capability</p>
            </div>
            <div class="controls">
                <input type="text" class="search-box" id="logSearch" placeholder="Search activity log..." oninput="filterActivityLog()">
                <select class="filter-select" id="logWorkTypeFilter" onchange="filterActivityLog()">
                    <option value="">All Work Types</option>
                    <!-- Populated by JavaScript -->
                </select>
                <select class="filter-select" id="logPhaseFilter" onchange="filterActivityLog()">
                    <option value="">All Workflow Phases</option>
                    <!-- Populated by JavaScript -->
                </select>
                <select class="filter-select" id="logUserFilter" onchange="filterActivityLog()">
                    <option value="">All Users</option>
                    <!-- Populated by JavaScript -->
                </select>
                <!-- TODO: Enable when context.allocationState is populated in events
                <select class="filter-select" id="logAllocationStateFilter" onchange="filterActivityLog()">
                    <option value="">All Allocation States</option>
                    <! Populated by JavaScript >
                </select>
                -->
                <div class="checkbox-group" id="logConfidenceFilters">
                    <span style="font-weight: 600;">Confidence:</span>
                    <label><input type="checkbox" value="confirmed" checked onchange="filterActivityLog()"> Confirmed</label>
                    <label><input type="checkbox" value="likely" checked onchange="filterActivityLog()"> Likely</label>
                    <label><input type="checkbox" value="checkout_only" checked onchange="filterActivityLog()"> Checkout Only</label>
                    <label><input type="checkbox" value="unattributed" checked onchange="filterActivityLog()"> Unattributed</label>
                </div>
                <button class="btn btn-success" onclick="exportToCSV()">Export CSV</button>
            </div>
            <div class="scrollable">
                <table class="data-table" id="activityLogTable">
                    <thead>
                        <tr>
                            <th class="sortable" onclick="sortTable('activityLogTable', 0)">Timestamp</th>
                            <th class="sortable" onclick="sortTable('activityLogTable', 1)">User</th>
                            <th class="sortable" onclick="sortTable('activityLogTable', 2)">Work Type</th>
                            <th>Object Name</th>
                            <th>Details</th>
                        </tr>
                    </thead>
                    <tbody id="activityLogBody">
                        <!-- Populated by JavaScript -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- View 7: Study Health -->
        <div id="view7" class="view-container">
            <div class="view-header">
                <h2>Study Health Analysis</h2>
                <p>Technical debt tracking for RobcadStudy naming conventions and quality</p>
            </div>

            <!-- Summary Cards -->
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin-bottom: 30px;">
                <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; box-shadow: var(--shadow);">
                    <div style="font-size: 2em; font-weight: bold;" id="totalStudiesCount">0</div>
                    <div style="font-size: 0.9em; opacity: 0.9;">Total Studies</div>
                </div>
                <div style="background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%); color: white; padding: 20px; border-radius: 8px; box-shadow: var(--shadow);">
                    <div style="font-size: 2em; font-weight: bold;" id="criticalIssuesCount">0</div>
                    <div style="font-size: 0.9em; opacity: 0.9;">Critical Issues</div>
                </div>
                <div style="background: linear-gradient(135deg, #f39c12 0%, #e67e22 100%); color: white; padding: 20px; border-radius: 8px; box-shadow: var(--shadow);">
                    <div style="font-size: 2em; font-weight: bold;" id="highIssuesCount">0</div>
                    <div style="font-size: 0.9em; opacity: 0.9;">High Priority Issues</div>
                </div>
                <div style="background: linear-gradient(135deg, #3498db 0%, #2980b9 100%); color: white; padding: 20px; border-radius: 8px; box-shadow: var(--shadow);">
                    <div style="font-size: 2em; font-weight: bold;" id="mediumIssuesCount">0</div>
                    <div style="font-size: 0.9em; opacity: 0.9;">Medium Priority</div>
                </div>
                <div style="background: linear-gradient(135deg, #95a5a6 0%, #7f8c8d 100%); color: white; padding: 20px; border-radius: 8px; box-shadow: var(--shadow);">
                    <div style="font-size: 2em; font-weight: bold;" id="lowIssuesCount">0</div>
                    <div style="font-size: 0.9em; opacity: 0.9;">Low Priority</div>
                </div>
                <div style="background: linear-gradient(135deg, #27ae60 0%, #229954 100%); color: white; padding: 20px; border-radius: 8px; box-shadow: var(--shadow);">
                    <div style="font-size: 2em; font-weight: bold;" id="healthScorePercent">0%</div>
                    <div style="font-size: 0.9em; opacity: 0.9;">Health Score</div>
                </div>
            </div>

            <!-- Filter Controls -->
            <div class="controls">
                <input type="text" class="search-box" id="healthSearch" placeholder="Search issues..." oninput="filterHealthIssues()">
                <select class="filter-select" id="healthSeverityFilter" onchange="filterHealthIssues()">
                    <option value="">All Severities</option>
                    <option value="Critical">Critical</option>
                    <option value="High">High</option>
                    <option value="Medium">Medium</option>
                    <option value="Low">Low</option>
                </select>
                <select class="filter-select" id="healthIssueTypeFilter" onchange="filterHealthIssues()">
                    <option value="">All Issue Types</option>
                    <!-- Populated by JavaScript -->
                </select>
                <button class="btn btn-success" onclick="exportHealthToCSV()">Export CSV</button>
            </div>

            <!-- Issues Table -->
            <div class="scrollable">
                <table class="data-table" id="healthIssuesTable">
                    <thead>
                        <tr>
                            <th class="sortable" onclick="sortTable('healthIssuesTable', 0)">Severity</th>
                            <th class="sortable" onclick="sortTable('healthIssuesTable', 1)">Study Name</th>
                            <th class="sortable" onclick="sortTable('healthIssuesTable', 2)">Issue Type</th>
                            <th>Details</th>
                            <th class="sortable" onclick="sortTable('healthIssuesTable', 4)">Node ID</th>
                        </tr>
                    </thead>
                    <tbody id="healthIssuesBody">
                        <!-- Populated by JavaScript -->
                    </tbody>
                </table>
            </div>
        </div>

        <!-- View 8: Resource Conflicts & Stale Checkouts -->
        <div id="view8" class="view-container">
            <div class="view-header">
                <h2>Resource Conflicts & Stale Checkouts</h2>
                <p>Track resource conflicts and identify bottlenecks from long-running checkouts</p>
            </div>

            <!-- Summary Cards -->
            <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px;">
                <div style="background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%); color: white; padding: 20px; border-radius: 8px; box-shadow: var(--shadow);">
                    <div style="font-size: 2em; font-weight: bold;" id="conflictCount">0</div>
                    <div style="font-size: 0.9em; opacity: 0.9;">Resource Conflicts</div>
                    <div style="font-size: 0.8em; margin-top: 5px; opacity: 0.8;">Resources used in 2+ studies</div>
                </div>
                <div style="background: linear-gradient(135deg, #f39c12 0%, #e67e22 100%); color: white; padding: 20px; border-radius: 8px; box-shadow: var(--shadow);">
                    <div style="font-size: 2em; font-weight: bold;" id="staleCheckoutCount">0</div>
                    <div style="font-size: 0.9em; opacity: 0.9;">Stale Checkouts</div>
                    <div style="font-size: 0.8em; margin-top: 5px; opacity: 0.8;">&gt;72 hours checked out</div>
                </div>
                <div style="background: linear-gradient(135deg, #3498db 0%, #2980b9 100%); color: white; padding: 20px; border-radius: 8px; box-shadow: var(--shadow);">
                    <div style="font-size: 2em; font-weight: bold;" id="bottleneckUserCount">0</div>
                    <div style="font-size: 0.9em; opacity: 0.9;">Users with Bottlenecks</div>
                    <div style="font-size: 0.8em; margin-top: 5px; opacity: 0.8;">Users with stale checkouts</div>
                </div>
            </div>

            <!-- Resource Conflicts Section -->
            <div style="margin-bottom: 30px;">
                <h3 style="color: var(--primary-color); margin-bottom: 15px;">Resource Conflicts</h3>
                <div class="scrollable">
                    <table class="data-table" id="conflictsTable">
                        <thead>
                            <tr>
                                <th class="sortable" onclick="sortTable('conflictsTable', 0)">Resource</th>
                                <th class="sortable" onclick="sortTable('conflictsTable', 1)">Type</th>
                                <th class="sortable" onclick="sortTable('conflictsTable', 2)">Study Count</th>
                                <th>Studies Using Resource</th>
                                <th class="sortable" onclick="sortTable('conflictsTable', 4)">Risk Level</th>
                            </tr>
                        </thead>
                        <tbody id="conflictsBody">
                            <!-- Populated by JavaScript -->
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- Stale Checkouts Section -->
            <div style="margin-bottom: 30px;">
                <h3 style="color: var(--primary-color); margin-bottom: 15px;">Stale Checkouts (&gt;72 hours)</h3>
                <div class="controls">
                    <input type="text" class="search-box" id="staleSearch" placeholder="Search checkouts..." oninput="filterStaleCheckouts()">
                    <select class="filter-select" id="staleSeverityFilter" onchange="filterStaleCheckouts()">
                        <option value="">All Severities</option>
                        <option value="Critical">Critical (7+ days)</option>
                        <option value="High">High (5-7 days)</option>
                        <option value="Medium">Medium (3-5 days)</option>
                    </select>
                    <button class="btn btn-success" onclick="exportStaleCheckoutsToCSV()">Export CSV</button>
                </div>
                <div class="scrollable">
                    <table class="data-table" id="staleCheckoutsTable">
                        <thead>
                            <tr>
                                <th class="sortable" onclick="sortTable('staleCheckoutsTable', 0)">Object</th>
                                <th class="sortable" onclick="sortTable('staleCheckoutsTable', 1)">Type</th>
                                <th class="sortable" onclick="sortTable('staleCheckoutsTable', 2)">Checked Out By</th>
                                <th class="sortable" onclick="sortTable('staleCheckoutsTable', 3)">Duration</th>
                                <th class="sortable" onclick="sortTable('staleCheckoutsTable', 4)">Last Modified</th>
                                <th class="sortable" onclick="sortTable('staleCheckoutsTable', 5)">Severity</th>
                            </tr>
                        </thead>
                        <tbody id="staleCheckoutsBody">
                            <!-- Populated by JavaScript -->
                        </tbody>
                    </table>
                </div>
            </div>

            <!-- Bottleneck Queue Section -->
            <div>
                <h3 style="color: var(--primary-color); margin-bottom: 15px;">Bottleneck Queue (By User)</h3>
                <p style="color: #7f8c8d; margin-bottom: 15px; font-size: 0.9em;">
                    Users sorted by total checkout duration. Long checkouts may indicate workflow bottlenecks.
                </p>
                <div id="bottleneckQueueContainer">
                    <!-- Populated by JavaScript -->
                </div>

            </div>
        </div>
    </div>

    <script id="dashboard-data" type="application/json">
        $jsonDataForHtml
    </script>

    <script>
        // ========================================
        // DATA LOADING
        // ========================================
        const dashboardData = JSON.parse(document.getElementById('dashboard-data').textContent || '{}');

        // Normalize data: ensure all expected arrays are actually arrays (handle single-object case)
        const arrayFields = ['projectDatabase', 'resourceLibrary', 'partLibrary', 'ipaAssembly',
                            'studySummary', 'studyResources', 'studyPanels', 'studyOperations',
                            'studyMovements', 'studyWelds', 'userActivity', 'treeChanges'];
        arrayFields.forEach(field => {
            if (dashboardData[field] && !Array.isArray(dashboardData[field])) {
                dashboardData[field] = [dashboardData[field]];
            } else if (!dashboardData[field]) {
                dashboardData[field] = [];
            }
        });

        if (!dashboardData || !dashboardData.metadata) {
            document.body.innerHTML = '<div class="error-state"><h3>Error Loading Dashboard</h3><p>Failed to load dashboard data. Please regenerate the data file.</p></div>';
            throw new Error('Failed to load dashboard data');
        }

        // ========================================
        // VIEW SWITCHING
        // ========================================
        function showView(viewId) {
            // Hide all views
            document.querySelectorAll('.view-container').forEach(view => {
                view.classList.remove('active');
            });

            // Remove active class from all tabs
            document.querySelectorAll('.nav-tab').forEach(tab => {
                tab.classList.remove('active');
            });

            // Show selected view
            document.getElementById(viewId).classList.add('active');

            // Activate corresponding tab
            event.target.classList.add('active');
        }

        // ========================================
        // TABLE SORTING
        // ========================================
        function sortTable(tableId, columnIndex) {
            const table = document.getElementById(tableId);
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));
            const th = table.querySelectorAll('th')[columnIndex];

            // Determine sort direction
            const isAsc = th.classList.contains('sorted-asc');

            // Remove sort indicators from all headers
            table.querySelectorAll('th').forEach(header => {
                header.classList.remove('sorted-asc', 'sorted-desc');
            });

            // Add sort indicator
            th.classList.add(isAsc ? 'sorted-desc' : 'sorted-asc');

            // Sort rows
            rows.sort((a, b) => {
                const aVal = a.cells[columnIndex].textContent.trim();
                const bVal = b.cells[columnIndex].textContent.trim();

                // Try numeric comparison first
                const aNum = parseFloat(aVal.replace(/[^0-9.-]/g, ''));
                const bNum = parseFloat(bVal.replace(/[^0-9.-]/g, ''));

                if (!isNaN(aNum) && !isNaN(bNum)) {
                    return isAsc ? bNum - aNum : aNum - bNum;
                }

                // Fall back to string comparison
                return isAsc ? bVal.localeCompare(aVal) : aVal.localeCompare(bVal);
            });

            // Re-append rows
            rows.forEach(row => tbody.appendChild(row));
        }

        // ========================================
        // EVENT + EVIDENCE HELPERS
        // ========================================
        function buildLegacyEvents() {
            const events = [];

            (dashboardData.projectDatabase || []).forEach(item => {
                events.push({
                    timestamp: item.last_modified || '',
                    user: item.modified_by || item.checked_out_by_user_name,
                    workType: 'Project Database',
                    description: (item.object_name || 'Unknown') + ' - ' + (item.status || 'Available'),
                    objectName: item.object_name,
                    objectId: item.object_id,
                    objectType: item.object_type,
                    evidence: item.evidence || null
                });
            });

            (dashboardData.resourceLibrary || []).forEach(item => {
                events.push({
                    timestamp: item.last_modified || '',
                    user: item.modified_by || item.checked_out_by_user_name,
                    workType: 'Resource Library',
                    description: (item.object_name || 'Unknown') + ' (' + (item.object_type || 'Resource') + ') - ' + (item.status || 'Available'),
                    objectName: item.object_name,
                    objectId: item.object_id,
                    objectType: item.object_type,
                    evidence: item.evidence || null
                });
            });

            (dashboardData.partLibrary || []).forEach(item => {
                events.push({
                    timestamp: item.last_modified || '',
                    user: item.modified_by || item.checked_out_by_user_name,
                    workType: 'Part/MFG Library',
                    description: (item.object_name || 'Unknown') + ' (' + (item.category || 'Part') + ') - ' + (item.status || 'Available'),
                    objectName: item.object_name,
                    objectId: item.object_id,
                    objectType: item.object_type,
                    evidence: item.evidence || null
                });
            });

            (dashboardData.ipaAssembly || []).forEach(item => {
                events.push({
                    timestamp: item.last_modified || '',
                    user: item.modified_by || item.checked_out_by_user_name,
                    workType: 'IPA Assembly',
                    description: (item.object_name || 'Unknown') + ' - ' + (item.status || 'Available'),
                    objectName: item.object_name,
                    objectId: item.object_id,
                    objectType: item.object_type,
                    evidence: item.evidence || null
                });
            });

            (dashboardData.studySummary || []).forEach(item => {
                events.push({
                    timestamp: item.last_modified || '',
                    user: item.modified_by || item.checked_out_by_user_name,
                    workType: 'Study Nodes',
                    description: (item.study_name || 'Unnamed Study') + ' (' + (item.study_type || 'Study') + ') - ' + (item.status || 'Idle'),
                    objectName: item.study_name,
                    objectId: item.study_id,
                    objectType: item.study_type,
                    evidence: item.evidence || null
                });
            });

            return events;
        }

        function getEventList() {
            if (Array.isArray(dashboardData.events) && dashboardData.events.length > 0) {
                return dashboardData.events.map(e => ({
                    timestamp: e.timestamp || '',
                    user: e.user || '',
                    workType: e.workType || 'Unknown',
                    description: e.description || '',
                    objectName: e.objectName || '',
                    objectId: e.objectId || '',
                    objectType: e.objectType || '',
                    evidence: e.evidence || null,
                    context: e.context || null
                }));
            }

            return buildLegacyEvents();
        }

        function normalizeEvidence(evidence) {
            const defaults = {
                hasCheckout: false,
                hasWrite: false,
                hasDelta: false,
                attributionStrength: 'weak',
                confidence: 'unattributed'
            };

            if (!evidence || typeof evidence !== 'object') {
                return defaults;
            }

            return Object.assign({}, defaults, evidence);
        }

        function normalizeContext(context) {
            if (!context || typeof context !== 'object') {
                return null;
            }
            return context;
        }

        function getAllocationState(activity) {
            if (!activity || !activity.context || !activity.context.allocationState) {
                return 'unknown';
            }
            return activity.context.allocationState;
        }

        function getWorkflowPhase(workType) {
            if (!workType) return '';
            const parts = workType.split('.');
            return parts[0] || '';
        }

        function formatPhaseLabel(phase) {
            if (!phase) return '';
            return phase.charAt(0).toUpperCase() + phase.slice(1);
        }

        function formatWorkTypeLabel(workType) {
            if (!workType) return 'Unknown';
            if (workType.indexOf('.') === -1) return workType;
            const parts = workType.split('.');
            return parts.map(part => part.replace(/([a-z])([A-Z])/g, '$1 $2')).join(' / ');
        }

        function formatContextObjectType(value) {
            if (!value) return '';
            return value.replace(/([a-z])([A-Z])/g, '$1 $2').replace(/\b\w/g, l => l.toUpperCase());
        }

        function renderContextLine(activity) {
            const context = normalizeContext(activity.context);
            const parts = [];

            if (context && context.station) {
                parts.push('Station: ' + context.station);
            }

            if (context && context.objectType) {
                parts.push('Type: ' + formatContextObjectType(context.objectType));
            }

            if (activity.objectId) {
                parts.push('ID: ' + activity.objectId);
            }

            const allocationState = getAllocationState(activity);
            if (allocationState && allocationState !== 'unknown') {
                parts.push('Allocation: ' + allocationState);
            }

            if (parts.length === 0) {
                return '';
            }

            return '<div class="context-line">' + parts.join(' / ') + '</div>';
        }

        function getSelectedConfidenceFilters(containerId) {
            const container = document.getElementById(containerId);
            if (!container) {
                return null;
            }

            const checked = Array.from(container.querySelectorAll('input[type="checkbox"]:checked'))
                .map(input => input.value);

            if (checked.length === 0) {
                return null;
            }

            return checked;
        }

        function getConfidenceValue(evidence) {
            return normalizeEvidence(evidence).confidence;
        }

        function getConfidenceBadgeClass(confidence) {
            if (confidence === 'confirmed') return 'badge-confirmed';
            if (confidence === 'likely') return 'badge-likely';
            if (confidence === 'possible') return 'badge-possible';
            if (confidence === 'checkout_only') return 'badge-checkout';
            if (confidence === 'unattributed') return 'badge-unattributed';
            return 'badge-primary';
        }

        function formatConfidenceLabel(confidence) {
            if (!confidence) return '';
            return confidence.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
        }

        function renderConfidenceBadge(evidence) {
            const confidence = getConfidenceValue(evidence);
            const badgeClass = getConfidenceBadgeClass(confidence);
            const label = formatConfidenceLabel(confidence) || 'Unattributed';
            return '<span class="badge ' + badgeClass + '">' + label + '</span>';
        }

        function renderEvidenceDetails(evidence) {
            const normalized = normalizeEvidence(evidence);

            const items = [];
            items.push('<div><strong>Confidence:</strong> ' + (formatConfidenceLabel(normalized.confidence) || 'Unattributed') + '</div>');
            items.push('<div><strong>Attribution:</strong> ' + (normalized.attributionStrength || 'weak') + '</div>');
            items.push('<div><strong>Checkout:</strong> ' + (normalized.hasCheckout ? 'Yes' : 'No') + '</div>');
            items.push('<div><strong>Write:</strong> ' + (normalized.hasWrite ? 'Yes' : 'No') + '</div>');
            items.push('<div><strong>Delta:</strong> ' + (normalized.hasDelta ? 'Yes' : 'No') + '</div>');

            if (normalized.proxyOwnerName) {
                items.push('<div><strong>Proxy Owner:</strong> ' + normalized.proxyOwnerName + '</div>');
            }

            if (normalized.lastModifiedBy) {
                items.push('<div><strong>Last Modified By:</strong> ' + normalized.lastModifiedBy + '</div>');
            }

            if (normalized.checkoutWorkingVersionId) {
                items.push('<div><strong>Working Version:</strong> ' + normalized.checkoutWorkingVersionId + '</div>');
            }

            if (normalized.writeSources && normalized.writeSources.length) {
                items.push('<div><strong>Write proof:</strong> ' + normalized.writeSources.join(', ') + '</div>');
            }

            if (normalized.joinSources && normalized.joinSources.length) {
                items.push('<div><strong>Relationships checked:</strong> ' + normalized.joinSources.join(', ') + '</div>');
            }

            if (normalized.deltaSummary) {
                const summary = normalized.deltaSummary;
                const fields = summary.fields ? summary.fields.join(', ') : '';
                let deltaText = summary.kind || 'delta';
                if (summary.maxAbsDelta !== undefined) {
                    deltaText += ' (max ' + summary.maxAbsDelta + ')';
                }
                if (fields) {
                    deltaText += ' [' + fields + ']';
                }
                items.push('<div><strong>Delta Summary:</strong> ' + deltaText + '</div>');
            }

            if (normalized.snapshotComparison && normalized.snapshotComparison.changes && normalized.snapshotComparison.changes.length) {
                items.push('<div><strong>Changes:</strong> ' + normalized.snapshotComparison.changes.join('; ') + '</div>');
            }

            return '<details class="evidence-details"><summary>Evidence</summary><div class="evidence-grid">' + items.join('') + '</div></details>';
        }

        // ========================================
        // VIEW 1: WORK TYPE SUMMARY
        // ========================================
        function renderWorkTypeSummary() {
            const tbody = document.getElementById('workTypeSummaryBody');
            tbody.innerHTML = '';

            const workTypes = [
                { name: 'Project Database', key: 'projectDatabase', items: dashboardData.projectDatabase || [] },
                { name: 'Resource Library', key: 'resourceLibrary', items: dashboardData.resourceLibrary || [] },
                { name: 'Part/MFG Library', key: 'partLibrary', items: dashboardData.partLibrary || [] },
                { name: 'IPA Assembly', key: 'ipaAssembly', items: dashboardData.ipaAssembly || [] },
                { name: 'Study Nodes', key: 'studySummary', items: dashboardData.studySummary || [] }
            ];

            workTypes.forEach(workType => {
                const items = workType.items;
                const activeCount = items.filter(item => item.status === 'Checked Out' || item.status === 'Active').length;
                const modifiedCount = items.length;
                const uniqueUsers = [...new Set(items.map(item => item.modified_by || item.checked_out_by_user_name).filter(Boolean))];

                const row = tbody.insertRow();
                row.innerHTML = ``
                    <td><strong>`${workType.name}</strong></td>
                    <td><span class="badge badge-info">`${activeCount}</span></td>
                    <td><span class="badge badge-primary">`${modifiedCount}</span></td>
                    <td>`${uniqueUsers.length}</td>
                    <td>`${modifiedCount > 0 ? modifiedCount + ' items' : 'No activity'}</td>
                ``;
            });
        }

        // ========================================
        // VIEW 2: ACTIVE STUDIES
        // ========================================
        function renderActiveStudies() {
            const container = document.getElementById('activeStudiesContainer');
            const studies = dashboardData.studySummary || [];

            if (studies.length === 0) {
                container.innerHTML = '<div class="empty-state"><p>No studies active in date range</p></div>';
                return;
            }

            container.innerHTML = '';

            studies.forEach((study, index) => {
                // Get related resources
                const resources = (dashboardData.studyResources || []).filter(r => r.study_id === study.study_id);

                // Get related panels
                const panels = (dashboardData.studyPanels || []).filter(p => p.study_id === study.study_id);

                // Get related operations
                const operations = (dashboardData.studyOperations || []).filter(o => {
                    // Match operations by timestamp proximity or other criteria
                    return true; // Simplified for now
                }).slice(0, 10);

                const treeItem = document.createElement('div');
                treeItem.className = 'tree-item';
                treeItem.innerHTML = ``
                    <div class="tree-header" onclick="toggleTreeItem(`${index})">
                        <div>
                            <div class="title">`${study.study_name || 'Unnamed Study'}</div>
                            <div style="font-size: 0.9em; color: #7f8c8d; margin-top: 5px;">
                                `${study.status === 'Active' ? '<span class="badge badge-success">Active</span>' : '<span class="badge badge-warning">Idle</span>'}
                                <span style="margin-left: 10px;">Modified by: `${study.modified_by || 'Unknown'}</span>
                                <span style="margin-left: 10px;">Last modified: `${study.last_modified || 'N/A'}</span>
                            </div>
                        </div>
                        <div class="toggle" id="toggle-`${index}">▶</div>
                    </div>
                    <div class="tree-content" id="content-`${index}">
                        `${resources.length > 0 ? ``
                        <div class="tree-section">
                            <h4>Resources Allocated (`${resources.length})</h4>
                            <ul class="tree-list">
                                `${resources.map(r => ``<li>`${r.shortcut_name || r.resource_name} - `${r.allocation_type || r.resource_type}</li>``).join('')}
                            </ul>
                        </div>
                        `` : ''}
                        `${panels.length > 0 ? ``
                        <div class="tree-section">
                            <h4>Panels Used (`${panels.length})</h4>
                            <ul class="tree-list">
                                `${panels.map(p => ``<li>`${p.shortcut_name} - `${p.panel_code}</li>``).join('')}
                            </ul>
                        </div>
                        `` : ''}
                        `${operations.length > 0 ? ``
                        <div class="tree-section">
                            <h4>Recent Operations (`${operations.length})</h4>
                            <ul class="tree-list">
                                `${operations.map(o => ``<li>`${o.operation_name} - `${o.operation_category || o.operation_class}</li>``).join('')}
                            </ul>
                        </div>
                        `` : ''}
                        `${resources.length === 0 && panels.length === 0 && operations.length === 0 ? ``
                        <div class="tree-section">
                            <p style="color: #7f8c8d;">No detailed information available for this study.</p>
                        </div>
                        `` : ''}
                    </div>
                ``;
                container.appendChild(treeItem);
            });
        }

        function toggleTreeItem(index) {
            const content = document.getElementById(``content-`${index}``);
            const toggle = document.getElementById(``toggle-`${index}``);

            if (content.classList.contains('expanded')) {
                content.classList.remove('expanded');
                toggle.classList.remove('expanded');
            } else {
                content.classList.add('expanded');
                toggle.classList.add('expanded');
            }
        }

        // ========================================
        // VIEW 3: MOVEMENT ACTIVITY
        // ========================================
        function renderMovementActivity() {
            const tbody = document.getElementById('movementActivityBody');
            const movements = dashboardData.studyMovements || [];

            if (movements.length === 0) {
                tbody.innerHTML = '<tr><td colspan="4" class="text-center">No movement activity recorded</td></tr>';
                return;
            }

            tbody.innerHTML = '';

            movements.forEach(movement => {
                const row = tbody.insertRow();

                // Determine movement type (simplified logic)
                let movementType = 'Simple Move';
                let movementClass = 'movement-simple';

                // Check if this looks like a significant change
                if (movement.location_vector_id && movement.rotation_vector_id) {
                    movementType = 'Location & Rotation Change';
                    movementClass = 'movement-world';
                } else if (movement.location_vector_id) {
                    movementType = 'Location Change';
                    movementClass = 'movement-weld';
                } else if (movement.rotation_vector_id) {
                    movementType = 'Rotation Change';
                    movementClass = 'movement-rotation';
                }

                row.innerHTML = ``
                    <td>Study Layout `${movement.studylayout_id}</td>
                    <td><span class="`${movementClass}">`${movementType}</span></td>
                    <td>`${movement.modified_by || 'Unknown'}</td>
                    <td>`${movement.last_modified || 'N/A'}</td>
                ``;
            });
        }

        // ========================================
        // VIEW 9: TREE CHANGES
        // ========================================
        function getTreeChangeConfidence(change) {
            if (!change) return 'unattributed';
            if (change.confidence) return change.confidence;
            if (change.evidence && change.evidence.confidence) return change.evidence.confidence;

            const evidence = change.evidence || null;
            if (evidence) {
                if (evidence.hasCheckout && evidence.hasWrite && evidence.hasDelta) return 'confirmed';
                if (evidence.hasWrite && evidence.hasDelta) return 'likely';
                if (evidence.hasCheckout || evidence.hasWrite || evidence.hasDelta) return 'possible';
            }

            return 'unattributed';
        }

        function normalizeTreeChange(change) {
            if (!change || typeof change !== 'object') {
                return null;
            }

            const evidence = change.evidence || null;
            const context = change.context || {};
            const deltaSummary = (evidence && evidence.deltaSummary) ? evidence.deltaSummary : (change.deltaSummary || change.delta_summary || null);

            let changeType = change.evidence_type || change.changeType || change.change_type || context.changeType || null;
            const kind = deltaSummary ? deltaSummary.kind : null;

            if (!changeType && kind) {
                if (kind === 'naming') changeType = 'rename';
                else if (kind === 'movement') changeType = 'movement';
                else if (kind === 'structure') changeType = 'structure';
                else if (kind === 'resourceMapping') changeType = 'resource_mapping';
                else if (kind === 'topology') changeType = 'topology';
            }

            if (changeType === 'resourceMapping') {
                changeType = 'resource_mapping';
            }

            if (changeType === 'topology') {
                const op = (deltaSummary && deltaSummary.operation) ? deltaSummary.operation : (context.changeType || null);
                if (op && op.toLowerCase().indexOf('add') >= 0) {
                    changeType = 'node_added';
                } else if (op && op.toLowerCase().indexOf('remove') >= 0) {
                    changeType = 'node_removed';
                }
            }

            const detectedAt = context.detectedAt || change.detected_at || change.detectedAt || change.timestamp || '';
            const studyId = context.studyId || change.study_id || '';
            const studyName = context.studyName || change.study_name || '';
            const nodeId = context.nodeId || change.node_id || '';
            const nodeName = context.nodeName || change.node_name || change.display_name || change.new_name || '';
            const nodeType = context.nodeType || change.node_type || '';
            const movementClassification = context.movementClassification || change.movement_type || '';
            const mappingType = (deltaSummary && deltaSummary.mapping_type) ? deltaSummary.mapping_type : (change.mapping_type || '');
            const snapshotFiles = context.snapshotFiles || change.snapshot_files || null;

            const oldName = change.old_name || (deltaSummary && deltaSummary.before ? deltaSummary.before.display_name : null);
            const newName = change.new_name || (deltaSummary && deltaSummary.after ? deltaSummary.after.display_name : null);
            const oldResourceName = change.old_resource_name || (deltaSummary && deltaSummary.before ? deltaSummary.before.resource_name : null);
            const newResourceName = change.new_resource_name || (deltaSummary && deltaSummary.after ? deltaSummary.after.resource_name : null);
            const oldParentId = change.old_parent_id || (deltaSummary && deltaSummary.before ? deltaSummary.before.parent_node_id : null);
            const newParentId = change.new_parent_id || (deltaSummary && deltaSummary.after ? deltaSummary.after.parent_node_id : null);
            const parentNodeId = change.parent_node_id || context.parentNodeId || null;
            const resourceName = change.resource_name || context.resourceName || null;

            const confidence = getTreeChangeConfidence({ evidence: evidence, confidence: change.confidence });

            return {
                raw: change,
                evidence: evidence,
                context: context,
                deltaSummary: deltaSummary,
                changeType: changeType,
                detectedAt: detectedAt,
                studyId: studyId,
                studyName: studyName,
                nodeId: nodeId,
                nodeName: nodeName,
                nodeType: nodeType,
                movementClassification: movementClassification,
                mappingType: mappingType,
                snapshotFiles: snapshotFiles,
                oldName: oldName,
                newName: newName,
                oldResourceName: oldResourceName,
                newResourceName: newResourceName,
                oldParentId: oldParentId,
                newParentId: newParentId,
                parentNodeId: parentNodeId,
                resourceName: resourceName,
                confidence: confidence
            };
        }

        function getTreeChangeList() {
            const raw = Array.isArray(dashboardData.treeChanges) ? dashboardData.treeChanges : [];
            return raw.map(item => normalizeTreeChange(item)).filter(Boolean);
        }

        function getTreeChangeTypeLabel(type) {
            switch (type) {
                case 'rename':
                    return 'Rename';
                case 'movement':
                    return 'Movement';
                case 'structure':
                    return 'Structure';
                case 'resource_mapping':
                    return 'Resource Mapping';
                case 'node_added':
                    return 'Node Added';
                case 'node_removed':
                    return 'Node Removed';
                default:
                    return type ? type.replace(/_/g, ' ') : 'Change';
            }
        }

        function getTreeChangeBadgeClass(type) {
            switch (type) {
                case 'rename':
                    return 'badge-rename';
                case 'movement':
                    return 'badge-move';
                case 'structure':
                    return 'badge-structure';
                case 'resource_mapping':
                    return 'badge-resource';
                case 'node_added':
                    return 'badge-add';
                case 'node_removed':
                    return 'badge-remove';
                default:
                    return 'badge-info';
            }
        }

        function formatTreeChangeSummary(change) {
            if (!change) return '';
            if (change.changeType === 'rename') {
                const beforeName = change.oldName || 'Unknown';
                const afterName = change.newName || change.nodeName || 'Unknown';
                return beforeName + ' -> ' + afterName;
            }
            if (change.changeType === 'movement') {
                const deltaValue = (change.deltaSummary && change.deltaSummary.maxAbsDelta !== undefined) ? change.deltaSummary.maxAbsDelta : '';
                const classification = change.movementClassification ? (' ' + change.movementClassification) : '';
                return 'Moved ' + (deltaValue !== '' ? (deltaValue + 'mm') : '') + classification;
            }
            if (change.changeType === 'structure') {
                return 'Parent ' + (change.oldParentId || 'N/A') + ' -> ' + (change.newParentId || 'N/A');
            }
            if (change.changeType === 'resource_mapping') {
                return (change.oldResourceName || 'Unknown') + ' -> ' + (change.newResourceName || 'Unknown');
            }
            if (change.changeType === 'node_added') {
                return 'Added node';
            }
            if (change.changeType === 'node_removed') {
                return 'Removed node';
            }
            return '';
        }

        function formatCoordValue(value) {
            if (value === null || value === undefined || value === '') return 'N/A';
            const num = Number(value);
            if (Number.isNaN(num)) return value;
            return num.toFixed(2);
        }

        function formatCoordSet(coords) {
            if (!coords) return 'N/A';
            return '(' + formatCoordValue(coords.x) + ', ' + formatCoordValue(coords.y) + ', ' + formatCoordValue(coords.z) + ')';
        }

        function renderTreeChanges() {
            const changes = getTreeChangeList();
            window.treeChangeData = changes.sort((a, b) => (b.detectedAt || '').localeCompare(a.detectedAt || ''));
            populateTreeChangeFilters(window.treeChangeData);
            filterTreeChanges();
        }

        function populateTreeChangeFilters(changes) {
            const typeFilter = document.getElementById('treeChangeTypeFilter');
            const studyFilter = document.getElementById('treeChangeStudyFilter');
            const mappingFilter = document.getElementById('treeChangeMappingFilter');

            if (!typeFilter || !studyFilter || !mappingFilter) {
                return;
            }

            const types = new Set();
            const studies = new Set();
            const mappings = new Set();

            (changes || []).forEach(change => {
                if (change.changeType) types.add(change.changeType);
                if (change.studyName) studies.add(change.studyName);
                if (change.mappingType) mappings.add(change.mappingType);
            });

            typeFilter.innerHTML = '<option value="">All Change Types</option>';
            Array.from(types).sort().forEach(type => {
                const option = document.createElement('option');
                option.value = type;
                option.textContent = getTreeChangeTypeLabel(type);
                typeFilter.appendChild(option);
            });

            studyFilter.innerHTML = '<option value="">All Studies</option>';
            Array.from(studies).sort().forEach(study => {
                const option = document.createElement('option');
                option.value = study;
                option.textContent = study;
                studyFilter.appendChild(option);
            });

            mappingFilter.innerHTML = '<option value="">All Mapping Types</option>';
            Array.from(mappings).sort().forEach(mapping => {
                const option = document.createElement('option');
                option.value = mapping;
                option.textContent = mapping;
                mappingFilter.appendChild(option);
            });
        }

        function filterTreeChanges() {
            const searchTerm = (document.getElementById('treeChangeSearch') || {}).value || '';
            const typeFilter = (document.getElementById('treeChangeTypeFilter') || {}).value || '';
            const studyFilter = (document.getElementById('treeChangeStudyFilter') || {}).value || '';
            const movementFilter = (document.getElementById('treeChangeMovementFilter') || {}).value || '';
            const mappingFilter = (document.getElementById('treeChangeMappingFilter') || {}).value || '';
            const confidenceFilters = getSelectedConfidenceFilters('treeChangeConfidenceFilters');

            let filtered = window.treeChangeData || [];
            const searchLower = searchTerm.toLowerCase();

            filtered = filtered.filter(change => {
                if (typeFilter && change.changeType !== typeFilter) return false;
                if (studyFilter && change.studyName !== studyFilter) return false;
                if (movementFilter) {
                    if (change.changeType !== 'movement') return false;
                    if (!change.movementClassification || change.movementClassification !== movementFilter) return false;
                }
                if (mappingFilter && change.mappingType !== mappingFilter) return false;
                if (confidenceFilters && confidenceFilters.length > 0 && confidenceFilters.indexOf(change.confidence || 'unattributed') === -1) return false;

                if (searchLower) {
                    const summary = formatTreeChangeSummary(change);
                    const haystack = ((change.studyName || '') + ' ' + (change.nodeName || '') + ' ' + (change.nodeId || '') + ' ' + summary).toLowerCase();
                    if (haystack.indexOf(searchLower) === -1) return false;
                }

                return true;
            });

            renderTreeChangeTimeline(filtered);
        }

        function renderTreeChangeTimeline(changes) {
            const container = document.getElementById('treeChangesTimeline');
            const detailPanel = document.getElementById('treeChangeDetails');

            if (!container) return;

            container.innerHTML = '';
            window.filteredTreeChangeData = changes || [];

            if (!changes || changes.length === 0) {
                container.innerHTML = '<div class="empty-state"><p>No tree changes detected</p><div class="hint">Run another snapshot after making changes to see results here.</div></div>';
                if (detailPanel) {
                    detailPanel.innerHTML = '<div class="empty-state"><p>Select a tree change to view details</p></div>';
                }
                return;
            }

            changes.forEach((change, index) => {
                const item = document.createElement('div');
                item.className = 'timeline-item tree-change-item';
                item.dataset.index = index;

                const typeLabel = getTreeChangeTypeLabel(change.changeType);
                const badgeClass = getTreeChangeBadgeClass(change.changeType);
                const confidenceBadge = renderConfidenceBadge({ confidence: change.confidence });
                const summary = formatTreeChangeSummary(change);

                let metaText = '';
                if (change.studyName) metaText += change.studyName;
                if (change.nodeType) metaText += (metaText ? ' | ' : '') + change.nodeType;

                item.innerHTML =
                    '<div class="timeline-time">' + (change.detectedAt || 'N/A') + '</div>' +
                    '<div class="timeline-content">' +
                        '<span class="badge ' + badgeClass + '">' + typeLabel + '</span> ' + confidenceBadge +
                        '<div style="margin-top:6px;"><strong>' + (change.nodeName || 'Unnamed Node') + '</strong>' + (summary ? ' - ' + summary : '') + '</div>' +
                        (metaText ? '<div class="context-line">' + metaText + '</div>' : '') +
                    '</div>';

                item.addEventListener('click', () => selectTreeChange(index));
                container.appendChild(item);
            });

            selectTreeChange(0);
        }

        function selectTreeChange(index) {
            const changes = window.filteredTreeChangeData || [];
            if (!changes || changes.length === 0) {
                renderTreeChangeDetails(null);
                return;
            }

            const container = document.getElementById('treeChangesTimeline');
            if (container) {
                const items = container.querySelectorAll('.tree-change-item');
                items.forEach((item, itemIndex) => {
                    if (itemIndex === index) {
                        item.classList.add('selected');
                    } else {
                        item.classList.remove('selected');
                    }
                });
            }

            renderTreeChangeDetails(changes[index]);
        }

        function renderTreeChangeDetails(change) {
            const panel = document.getElementById('treeChangeDetails');
            if (!panel) return;

            if (!change) {
                panel.innerHTML = '<div class="empty-state"><p>Select a tree change to view details</p></div>';
                return;
            }

            const typeLabel = getTreeChangeTypeLabel(change.changeType);
            const badgeClass = getTreeChangeBadgeClass(change.changeType);
            const confidenceBadge = renderConfidenceBadge({ confidence: change.confidence });

            const headerHtml = '<div class="tree-change-badges"><span class="badge ' + badgeClass + '">' + typeLabel + '</span>' + confidenceBadge + '</div>';

            const gridItems = [];
            gridItems.push('<div><strong>Study:</strong> ' + (change.studyName || 'N/A') + '</div>');
            if (change.studyId) gridItems.push('<div><strong>Study ID:</strong> ' + change.studyId + '</div>');
            if (change.nodeName) gridItems.push('<div><strong>Node:</strong> ' + change.nodeName + '</div>');
            if (change.nodeId) gridItems.push('<div><strong>Node ID:</strong> ' + change.nodeId + '</div>');
            if (change.nodeType) gridItems.push('<div><strong>Node Type:</strong> ' + change.nodeType + '</div>');
            if (change.detectedAt) gridItems.push('<div><strong>Detected:</strong> ' + change.detectedAt + '</div>');
            if (change.context && change.context.workType) gridItems.push('<div><strong>Work Type:</strong> ' + formatWorkTypeLabel(change.context.workType) + '</div>');
            if (change.movementClassification) gridItems.push('<div><strong>Movement:</strong> ' + change.movementClassification + '</div>');
            if (change.mappingType) gridItems.push('<div><strong>Mapping:</strong> ' + change.mappingType + '</div>');

            let detailSection = '';

            if (change.changeType === 'rename') {
                const oldProv = change.deltaSummary && change.deltaSummary.before ? change.deltaSummary.before.name_provenance : null;
                const newProv = change.deltaSummary && change.deltaSummary.after ? change.deltaSummary.after.name_provenance : null;
                detailSection =
                    '<div class="tree-change-section">' +
                    '<h4>Naming Change</h4>' +
                    '<div><strong>Before:</strong> ' + (change.oldName || 'N/A') + (oldProv ? ' <span class="context-line">(' + oldProv + ')</span>' : '') + '</div>' +
                    '<div><strong>After:</strong> ' + (change.newName || 'N/A') + (newProv ? ' <span class="context-line">(' + newProv + ')</span>' : '') + '</div>' +
                    '</div>';
            } else if (change.changeType === 'movement') {
                const beforeCoords = change.deltaSummary ? change.deltaSummary.before : null;
                const afterCoords = change.deltaSummary ? change.deltaSummary.after : null;
                const deltaCoords = change.deltaSummary ? change.deltaSummary.delta : null;
                const maxDelta = (change.deltaSummary && change.deltaSummary.maxAbsDelta !== undefined) ? change.deltaSummary.maxAbsDelta : null;
                const coordProv = (beforeCoords && beforeCoords.coord_provenance) ? beforeCoords.coord_provenance : (afterCoords && afterCoords.coord_provenance ? afterCoords.coord_provenance : null);

                detailSection =
                    '<div class="tree-change-section">' +
                    '<h4>Movement Details</h4>' +
                    '<div class="tree-change-coords">' +
                    '<div><strong>Before:</strong> ' + formatCoordSet(beforeCoords) + '</div>' +
                    '<div><strong>After:</strong> ' + formatCoordSet(afterCoords) + '</div>' +
                    '<div><strong>Delta:</strong> ' + formatCoordSet(deltaCoords) + '</div>' +
                    (maxDelta !== null ? '<div><strong>Max Δ:</strong> ' + maxDelta + 'mm</div>' : '') +
                    '</div>' +
                    (coordProv ? '<div class="context-line">Provenance: ' + coordProv + '</div>' : '') +
                    '</div>';
            } else if (change.changeType === 'structure') {
                detailSection =
                    '<div class="tree-change-section">' +
                    '<h4>Parent Change</h4>' +
                    '<div><strong>Before:</strong> ' + (change.oldParentId || 'N/A') + '</div>' +
                    '<div><strong>After:</strong> ' + (change.newParentId || 'N/A') + '</div>' +
                    '</div>';
            } else if (change.changeType === 'resource_mapping') {
                const beforeResId = change.deltaSummary && change.deltaSummary.before ? change.deltaSummary.before.resource_id : null;
                const afterResId = change.deltaSummary && change.deltaSummary.after ? change.deltaSummary.after.resource_id : null;
                detailSection =
                    '<div class="tree-change-section">' +
                    '<h4>Resource Mapping</h4>' +
                    '<div><strong>Before:</strong> ' + (change.oldResourceName || 'N/A') + (beforeResId ? ' (ID ' + beforeResId + ')' : '') + '</div>' +
                    '<div><strong>After:</strong> ' + (change.newResourceName || 'N/A') + (afterResId ? ' (ID ' + afterResId + ')' : '') + '</div>' +
                    '</div>';
            } else if (change.changeType === 'node_added' || change.changeType === 'node_removed') {
                const actionLabel = change.changeType === 'node_added' ? 'Added' : 'Removed';
                detailSection =
                    '<div class="tree-change-section">' +
                    '<h4>Topology Change</h4>' +
                    '<div><strong>Action:</strong> ' + actionLabel + '</div>' +
                    (change.parentNodeId ? '<div><strong>Parent ID:</strong> ' + change.parentNodeId + '</div>' : '') +
                    (change.resourceName ? '<div><strong>Resource:</strong> ' + change.resourceName + '</div>' : '') +
                    (change.context && change.context.nameProvenance ? '<div class="context-line">Name provenance: ' + change.context.nameProvenance + '</div>' : '') +
                    '</div>';
            }

            let snapshotSection = '';
            if (change.snapshotFiles) {
                const baseline = change.snapshotFiles.baseline || '';
                const current = change.snapshotFiles.current || '';
                const diff = change.snapshotFiles.diff || '';
                snapshotSection =
                    '<div class="tree-change-section">' +
                    '<h4>Snapshot Files</h4>' +
                    '<div class="tree-change-coords">' +
                    '<div><strong>Baseline:</strong> ' + baseline + '</div>' +
                    '<div><strong>Current:</strong> ' + current + '</div>' +
                    '<div><strong>Diff:</strong> ' + diff + '</div>' +
                    '</div>' +
                    '</div>';
            }

            const evidenceWithConfidence = Object.assign({}, change.evidence || {}, { confidence: change.confidence });

            panel.innerHTML =
                '<h3>Tree Change Details</h3>' +
                headerHtml +
                '<div class="tree-change-grid">' + gridItems.join('') + '</div>' +
                (detailSection || '') +
                (snapshotSection || '') +
                renderEvidenceDetails(evidenceWithConfidence);
        }

        // ========================================
        // VIEW 4: USER ACTIVITY BREAKDOWN
        // ========================================
        function renderUserActivity() {
            const userSelector = document.getElementById('userSelector');
            const chartContainer = document.getElementById('userActivityChart');
            const selectedUser = userSelector.value;

            if (!selectedUser) {
                chartContainer.innerHTML = '<div class="empty-state"><p>Select a user to view their activity breakdown</p></div>';
                return;
            }

            // Count activities per work type for this user
            const workTypes = {
                'Project Database': 0,
                'Resource Library': 0,
                'Part/MFG Library': 0,
                'IPA Assembly': 0,
                'Study Nodes': 0
            };

            // Count from each data source
            (dashboardData.projectDatabase || []).forEach(item => {
                if (item.modified_by === selectedUser || item.checked_out_by_user_name === selectedUser) {
                    workTypes['Project Database']++;
                }
            });

            (dashboardData.resourceLibrary || []).forEach(item => {
                if (item.modified_by === selectedUser || item.checked_out_by_user_name === selectedUser) {
                    workTypes['Resource Library']++;
                }
            });

            (dashboardData.partLibrary || []).forEach(item => {
                if (item.modified_by === selectedUser || item.checked_out_by_user_name === selectedUser) {
                    workTypes['Part/MFG Library']++;
                }
            });

            (dashboardData.ipaAssembly || []).forEach(item => {
                if (item.modified_by === selectedUser || item.checked_out_by_user_name === selectedUser) {
                    workTypes['IPA Assembly']++;
                }
            });

            (dashboardData.studySummary || []).forEach(item => {
                if (item.modified_by === selectedUser || item.checked_out_by_user_name === selectedUser) {
                    workTypes['Study Nodes']++;
                }
            });

            const total = Object.values(workTypes).reduce((sum, val) => sum + val, 0);

            if (total === 0) {
                chartContainer.innerHTML = '<div class="empty-state"><p>No activity found for this user</p></div>';
                return;
            }

            // Render bar chart
            chartContainer.innerHTML = '<div class="bar-chart" id="barChart"></div>';
            const barChart = document.getElementById('barChart');

            Object.entries(workTypes).forEach(([name, count]) => {
                const percentage = total > 0 ? (count / total * 100).toFixed(1) : 0;

                const barItem = document.createElement('div');
                barItem.className = 'bar-item';
                barItem.innerHTML = ``
                    <div class="bar-label">
                        <span class="name">`${name}</span>
                        <span class="value">`${count} items (`${percentage}%)</span>
                    </div>
                    <div class="bar-track">
                        <div class="bar-fill" style="width: `${percentage}%">`${percentage}%</div>
                    </div>
                ``;
                barChart.appendChild(barItem);
            });
        }

        function populateUserSelectors() {
            // Collect all unique users
            const allUsers = new Set();

            const datasets = [
                dashboardData.projectDatabase,
                dashboardData.resourceLibrary,
                dashboardData.partLibrary,
                dashboardData.ipaAssembly,
                dashboardData.studySummary,
                dashboardData.userActivity
            ];

            datasets.forEach(dataset => {
                if (Array.isArray(dataset)) {
                    dataset.forEach(item => {
                        if (item.modified_by) allUsers.add(item.modified_by);
                        if (item.checked_out_by_user_name) allUsers.add(item.checked_out_by_user_name);
                        if (item.user_name) allUsers.add(item.user_name);
                    });
                }
            });

            const eventUsers = getEventList().map(a => a.user).filter(Boolean);
            eventUsers.forEach(user => allUsers.add(user));

            const sortedUsers = Array.from(allUsers).sort();

            // Populate user selector for View 4
            const userSelector = document.getElementById('userSelector');
            userSelector.innerHTML = '<option value="">Select a user...</option>';
            sortedUsers.forEach(user => {
                const option = document.createElement('option');
                option.value = user;
                option.textContent = user;
                userSelector.appendChild(option);
            });

            // Populate user filters for Views 5 and 6
            const timelineUserFilter = document.getElementById('timelineUserFilter');
            const logUserFilter = document.getElementById('logUserFilter');
            timelineUserFilter.innerHTML = '<option value="">All Users</option>';
            logUserFilter.innerHTML = '<option value="">All Users</option>';

            sortedUsers.forEach(user => {
                const option1 = document.createElement('option');
                option1.value = user;
                option1.textContent = user;
                timelineUserFilter.appendChild(option1);

                const option2 = document.createElement('option');
                option2.value = user;
                option2.textContent = user;
                logUserFilter.appendChild(option2);
            });
        }

        // ========================================
        // VIEW 5: TIMELINE
        // ========================================
        function renderTimeline() {
            const allActivities = getEventList();

            allActivities.sort((a, b) => {
                const dateA = new Date(a.timestamp || 0);
                const dateB = new Date(b.timestamp || 0);
                return dateB - dateA;
            });

            window.timelineData = allActivities;
            renderFilteredTimeline(allActivities);

            const workTypeFilter = document.getElementById('timelineWorkTypeFilter');
            workTypeFilter.innerHTML = '<option value="">All Work Types</option>';
            const workTypes = [...new Set(allActivities.map(a => a.workType))].filter(Boolean);
            workTypes.forEach(wt => {
                const option = document.createElement('option');
                option.value = wt;
                option.textContent = formatWorkTypeLabel(wt);
                workTypeFilter.appendChild(option);
            });

            const phaseFilter = document.getElementById('timelinePhaseFilter');
            phaseFilter.innerHTML = '<option value="">All Workflow Phases</option>';
            const phases = [...new Set(allActivities.map(a => getWorkflowPhase(a.workType)).filter(Boolean))].sort();
            phases.forEach(phase => {
                const option = document.createElement('option');
                option.value = phase;
                option.textContent = formatPhaseLabel(phase);
                phaseFilter.appendChild(option);
            });

            /* TODO: Enable when context.allocationState is populated in events
            const allocationStateFilter = document.getElementById('timelineAllocationStateFilter');
            allocationStateFilter.innerHTML = '<option value="">All Allocation States</option>';
            const allocationStates = [...new Set(allActivities.map(a => getAllocationState(a)).filter(Boolean))];
            allocationStates.sort((a, b) => {
                if (a === 'unknown' && b !== 'unknown') return 1;
                if (b === 'unknown' && a !== 'unknown') return -1;
                return a.localeCompare(b);
            });
            allocationStates.forEach(state => {
                const option = document.createElement('option');
                option.value = state;
                option.textContent = state;
                allocationStateFilter.appendChild(option);
            });
            */
        }

        function renderFilteredTimeline(activities) {
            const container = document.getElementById('timelineContainer');

            if (!activities || activities.length === 0) {
                container.innerHTML = '<div class="empty-state"><p>No activity to display</p></div>';
                return;
            }

            container.innerHTML = '';

            activities.slice(0, 100).forEach(activity => {
                const item = document.createElement('div');
                item.className = 'timeline-item';
                const confidenceBadge = renderConfidenceBadge(activity.evidence);
                const evidenceDetails = renderEvidenceDetails(activity.evidence);
                const contextLine = renderContextLine(activity);
                const workTypeLabel = formatWorkTypeLabel(activity.workType || 'Unknown');

                item.innerHTML =
                    '<div class="timeline-time">' + (activity.timestamp || 'N/A') + '</div>' +
                    '<div class="timeline-content">' +
                        '<span class="timeline-user">' + (activity.user || 'Unknown') + '</span> - ' +
                        '<span class="badge badge-info">' + workTypeLabel + '</span> ' +
                        confidenceBadge + '<br>' +
                        (activity.description || '') +
                        contextLine +
                        evidenceDetails +
                    '</div>';
                container.appendChild(item);
            });

            if (activities.length > 100) {
                const moreItem = document.createElement('div');
                moreItem.className = 'timeline-item';
                moreItem.innerHTML = '<div class="text-center" style="color: #7f8c8d;">...and ' + (activities.length - 100) + ' more activities</div>';
                container.appendChild(moreItem);
            }
        }

        function filterTimeline() {
            const searchTerm = document.getElementById('timelineSearch').value.toLowerCase();
            const workTypeFilter = document.getElementById('timelineWorkTypeFilter').value;
            const phaseFilter = document.getElementById('timelinePhaseFilter').value;
            const userFilter = document.getElementById('timelineUserFilter').value;
            // const allocationStateFilter = document.getElementById('timelineAllocationStateFilter').value; // TODO: Enable when context.allocationState is populated
            const confidenceFilters = getSelectedConfidenceFilters('timelineConfidenceFilters');

            let filtered = window.timelineData || [];

            if (searchTerm) {
                filtered = filtered.filter(a =>
                    (a.description && a.description.toLowerCase().includes(searchTerm)) ||
                    (a.user && a.user.toLowerCase().includes(searchTerm)) ||
                    (a.workType && a.workType.toLowerCase().includes(searchTerm)) ||
                    (a.objectName && a.objectName.toLowerCase().includes(searchTerm)) ||
                    (a.timestamp && a.timestamp.toLowerCase().includes(searchTerm))
                );
            }

            if (workTypeFilter) {
                filtered = filtered.filter(a => a.workType === workTypeFilter);
            }

            if (phaseFilter) {
                filtered = filtered.filter(a => getWorkflowPhase(a.workType) === phaseFilter);
            }

            if (userFilter) {
                filtered = filtered.filter(a => a.user === userFilter);
            }

            /* TODO: Enable when context.allocationState is populated
            if (allocationStateFilter) {
                filtered = filtered.filter(a => getAllocationState(a) === allocationStateFilter);
            }
            */

            if (confidenceFilters && confidenceFilters.length) {
                filtered = filtered.filter(a => confidenceFilters.includes(getConfidenceValue(a.evidence)));
            }

            renderFilteredTimeline(filtered);
        }

        // ========================================
        // VIEW 6: ACTIVITY LOG
        // ========================================
        function renderActivityLog() {
            if (!window.timelineData) {
                renderTimeline();
            }

            window.activityLogData = window.timelineData || [];
            renderFilteredActivityLog(window.activityLogData);

            const logWorkTypeFilter = document.getElementById('logWorkTypeFilter');
            logWorkTypeFilter.innerHTML = '<option value="">All Work Types</option>';
            const workTypes = [...new Set(window.activityLogData.map(a => a.workType))].filter(Boolean);
            workTypes.forEach(wt => {
                const option = document.createElement('option');
                option.value = wt;
                option.textContent = formatWorkTypeLabel(wt);
                logWorkTypeFilter.appendChild(option);
            });

            const logPhaseFilter = document.getElementById('logPhaseFilter');
            logPhaseFilter.innerHTML = '<option value="">All Workflow Phases</option>';
            const phases = [...new Set(window.activityLogData.map(a => getWorkflowPhase(a.workType)).filter(Boolean))].sort();
            phases.forEach(phase => {
                const option = document.createElement('option');
                option.value = phase;
                option.textContent = formatPhaseLabel(phase);
                logPhaseFilter.appendChild(option);
            });

            /* TODO: Enable when context.allocationState is populated in events
            const logAllocationStateFilter = document.getElementById('logAllocationStateFilter');
            logAllocationStateFilter.innerHTML = '<option value="">All Allocation States</option>';
            const allocationStates = [...new Set(window.activityLogData.map(a => getAllocationState(a)).filter(Boolean))];
            allocationStates.sort((a, b) => {
                if (a === 'unknown' && b !== 'unknown') return 1;
                if (b === 'unknown' && a !== 'unknown') return -1;
                return a.localeCompare(b);
            });
            allocationStates.forEach(state => {
                const option = document.createElement('option');
                option.value = state;
                option.textContent = state;
                logAllocationStateFilter.appendChild(option);
            });
            */
        }

        function renderFilteredActivityLog(activities) {
            const tbody = document.getElementById('activityLogBody');

            if (!activities || activities.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" class="text-center">No activity found</td></tr>';
                return;
            }

            tbody.innerHTML = '';

            activities.slice(0, 200).forEach(activity => {
                const row = tbody.insertRow();
                const confidenceBadge = renderConfidenceBadge(activity.evidence);
                const evidenceDetails = renderEvidenceDetails(activity.evidence);
                const contextLine = renderContextLine(activity);
                const workTypeLabel = formatWorkTypeLabel(activity.workType || 'Unknown');

                row.innerHTML =
                    '<td>' + (activity.timestamp || 'N/A') + '</td>' +
                    '<td>' + (activity.user || 'Unknown') + '</td>' +
                    '<td><span class="badge badge-info">' + workTypeLabel + '</span> ' + confidenceBadge + '</td>' +
                    '<td>' + (activity.objectName || 'N/A') + '</td>' +
                    '<td>' + (activity.description || '') + contextLine + evidenceDetails + '</td>';
            });

            if (activities.length > 200) {
                const row = tbody.insertRow();
                row.innerHTML = '<td colspan="5" class="text-center" style="color: #7f8c8d;">Showing first 200 of ' + activities.length + ' activities. Use filters to narrow results.</td>';
            }
        }

        function filterActivityLog() {
            const searchTerm = document.getElementById('logSearch').value.toLowerCase();
            const workTypeFilter = document.getElementById('logWorkTypeFilter').value;
            const phaseFilter = document.getElementById('logPhaseFilter').value;
            const userFilter = document.getElementById('logUserFilter').value;
            // const allocationStateFilter = document.getElementById('logAllocationStateFilter').value; // TODO: Enable when context.allocationState is populated
            const confidenceFilters = getSelectedConfidenceFilters('logConfidenceFilters');

            let filtered = window.activityLogData || [];

            if (searchTerm) {
                filtered = filtered.filter(a =>
                    (a.description && a.description.toLowerCase().includes(searchTerm)) ||
                    (a.user && a.user.toLowerCase().includes(searchTerm)) ||
                    (a.workType && a.workType.toLowerCase().includes(searchTerm)) ||
                    (a.objectName && a.objectName.toLowerCase().includes(searchTerm)) ||
                    (a.timestamp && a.timestamp.toLowerCase().includes(searchTerm))
                );
            }

            if (workTypeFilter) {
                filtered = filtered.filter(a => a.workType === workTypeFilter);
            }

            if (phaseFilter) {
                filtered = filtered.filter(a => getWorkflowPhase(a.workType) === phaseFilter);
            }

            if (userFilter) {
                filtered = filtered.filter(a => a.user === userFilter);
            }

            /* TODO: Enable when context.allocationState is populated
            if (allocationStateFilter) {
                filtered = filtered.filter(a => getAllocationState(a) === allocationStateFilter);
            }
            */

            if (confidenceFilters && confidenceFilters.length) {
                filtered = filtered.filter(a => confidenceFilters.includes(getConfidenceValue(a.evidence)));
            }

            renderFilteredActivityLog(filtered);
        }

        // ========================================
        // VIEW 7: STUDY HEALTH
        // ========================================
        function renderStudyHealth() {
            const healthData = dashboardData.studyHealth || {};
            const summary = healthData.summary || {};
            const issues = healthData.issues || [];

            document.getElementById('totalStudiesCount').textContent = summary.totalStudies || 0;
            document.getElementById('criticalIssuesCount').textContent = summary.criticalIssues || 0;
            document.getElementById('highIssuesCount').textContent = summary.highIssues || 0;
            document.getElementById('mediumIssuesCount').textContent = summary.mediumIssues || 0;
            document.getElementById('lowIssuesCount').textContent = summary.lowIssues || 0;

            const totalStudies = summary.totalStudies || 1;
            const studiesWithIssues = new Set(issues.map(i => i.node_id)).size;
            const healthyStudies = totalStudies - studiesWithIssues;
            const healthScore = Math.round((healthyStudies / totalStudies) * 100);
            document.getElementById('healthScorePercent').textContent = healthScore + '%';

            window.healthIssuesData = issues;

            const issueTypes = [...new Set(issues.map(i => i.issue))].filter(Boolean).sort();
            const issueTypeFilter = document.getElementById('healthIssueTypeFilter');
            issueTypeFilter.innerHTML = '<option value="">All Issue Types</option>';
            issueTypes.forEach(type => {
                const option = document.createElement('option');
                option.value = type;
                option.textContent = type.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
                issueTypeFilter.appendChild(option);
            });

            renderFilteredHealthIssues(issues);
        }

        function renderFilteredHealthIssues(issues) {
            const tbody = document.getElementById('healthIssuesBody');

            if (!issues || issues.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" class="text-center">No issues found - all studies are healthy.</td></tr>';
                return;
            }

            tbody.innerHTML = '';

            issues.slice(0, 500).forEach(issue => {
                const row = tbody.insertRow();
                let severityBadge = 'badge-info';
                if (issue.severity === 'Critical') severityBadge = 'badge-danger';
                else if (issue.severity === 'High') severityBadge = 'badge-warning';
                else if (issue.severity === 'Medium') severityBadge = 'badge-info';
                else if (issue.severity === 'Low') severityBadge = 'badge-primary';

                const issueTypeReadable = (issue.issue || '').replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());

                row.innerHTML =
                    '<td><span class="badge ' + severityBadge + '">' + (issue.severity || 'N/A') + '</span></td>' +
                    '<td><strong>' + (issue.study_name || 'N/A') + '</strong></td>' +
                    '<td>' + issueTypeReadable + '</td>' +
                    '<td>' + (issue.details || 'No details') + '</td>' +
                    '<td>' + (issue.node_id || 'N/A') + '</td>';
            });

            if (issues.length > 500) {
                const row = tbody.insertRow();
                row.innerHTML = '<td colspan="5" class="text-center" style="color: #7f8c8d;">Showing first 500 of ' + issues.length + ' issues. Use filters to narrow results.</td>';
            }
        }

        function filterHealthIssues() {
            const searchTerm = document.getElementById('healthSearch').value.toLowerCase();
            const severityFilter = document.getElementById('healthSeverityFilter').value;
            const issueTypeFilter = document.getElementById('healthIssueTypeFilter').value;

            let filtered = window.healthIssuesData || [];

            if (searchTerm) {
                filtered = filtered.filter(i =>
                    (i.study_name && i.study_name.toLowerCase().includes(searchTerm)) ||
                    (i.issue && i.issue.toLowerCase().includes(searchTerm)) ||
                    (i.details && i.details.toLowerCase().includes(searchTerm)) ||
                    (i.node_id && i.node_id.toString().includes(searchTerm))
                );
            }

            if (severityFilter) {
                filtered = filtered.filter(i => i.severity === severityFilter);
            }

            if (issueTypeFilter) {
                filtered = filtered.filter(i => i.issue === issueTypeFilter);
            }

            renderFilteredHealthIssues(filtered);
        }

        function exportHealthToCSV() {
            const data = window.healthIssuesData || [];

            if (data.length === 0) {
                alert('No health issues to export');
                return;
            }

            let csv = 'Severity,Study Name,Issue Type,Details,Node ID\n';
            data.forEach(row => {
                const severity = (row.severity || '').replace(/,/g, ' ');
                const studyName = (row.study_name || '').replace(/,/g, ' ');
                const issue = (row.issue || '').replace(/,/g, ' ');
                const details = (row.details || '').replace(/,/g, ' ');
                const nodeId = (row.node_id || '').toString();
                csv += '"' + severity + '","' + studyName + '","' + issue + '","' + details + '","' + nodeId + '"\n';
            });

            const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
            const link = document.createElement('a');
            const url = URL.createObjectURL(blob);

            link.setAttribute('href', url);
            link.setAttribute('download', 'study-health-issues-export.csv');
            link.style.visibility = 'hidden';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }

        // ========================================
        // VIEW 8: RESOURCE CONFLICTS & STALE CHECKOUTS
        // ========================================
        function renderResourceConflicts() {
            const conflicts = dashboardData.resourceConflicts || [];
            const staleCheckouts = dashboardData.staleCheckouts || [];
            const bottleneckQueue = dashboardData.bottleneckQueue || [];

            document.getElementById('conflictCount').textContent = conflicts.length;
            document.getElementById('staleCheckoutCount').textContent = staleCheckouts.filter(c => c.flagged).length;
            document.getElementById('bottleneckUserCount').textContent = bottleneckQueue.length;

            renderConflictsTable(conflicts);

            window.staleCheckoutsData = staleCheckouts.filter(c => c.flagged);
            renderFilteredStaleCheckouts(window.staleCheckoutsData);
            renderBottleneckQueue(bottleneckQueue);
        }

        function renderConflictsTable(conflicts) {
            const tbody = document.getElementById('conflictsBody');

            if (!conflicts || conflicts.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" class="text-center">No resource conflicts detected</td></tr>';
                return;
            }

            tbody.innerHTML = '';

            conflicts.forEach(conflict => {
                const row = tbody.insertRow();
                let riskBadge = 'badge-info';
                if (conflict.risk_level === 'Critical') riskBadge = 'badge-danger';
                else if (conflict.risk_level === 'High') riskBadge = 'badge-warning';
                else if (conflict.risk_level === 'Medium') riskBadge = 'badge-info';

                row.innerHTML =
                    '<td><strong>' + (conflict.resource_name || 'N/A') + '</strong></td>' +
                    '<td>' + (conflict.resource_type || 'N/A') + '</td>' +
                    '<td><span class="badge ' + riskBadge + '">' + (conflict.study_count || 0) + '</span></td>' +
                    '<td>' + (conflict.studies || 'N/A') + '</td>' +
                    '<td><span class="badge ' + riskBadge + '">' + (conflict.risk_level || 'N/A') + '</span></td>';
            });
        }

        function renderFilteredStaleCheckouts(checkouts) {
            const tbody = document.getElementById('staleCheckoutsBody');

            if (!checkouts || checkouts.length === 0) {
                tbody.innerHTML = '<tr><td colspan="6" class="text-center">No stale checkouts detected</td></tr>';
                return;
            }

            tbody.innerHTML = '';

            checkouts.forEach(checkout => {
                const row = tbody.insertRow();
                let severityBadge = 'badge-info';
                if (checkout.severity === 'Critical') severityBadge = 'badge-danger';
                else if (checkout.severity === 'High') severityBadge = 'badge-warning';
                else if (checkout.severity === 'Medium') severityBadge = 'badge-info';

                const durationText = (checkout.checkout_duration_days >= 1)
                    ? checkout.checkout_duration_days.toFixed(1) + ' days'
                    : checkout.checkout_duration_hours.toFixed(1) + ' hours';

                row.innerHTML =
                    '<td><strong>' + (checkout.object_name || 'N/A') + '</strong></td>' +
                    '<td>' + (checkout.object_type || 'N/A') + '</td>' +
                    '<td>' + (checkout.checked_out_by || 'Unknown') + '</td>' +
                    '<td><span class="badge ' + severityBadge + '">' + durationText + '</span></td>' +
                    '<td>' + (checkout.last_modified || 'N/A') + '</td>' +
                    '<td><span class="badge ' + severityBadge + '">' + (checkout.severity || 'N/A') + '</span></td>';
            });
        }

        function filterStaleCheckouts() {
            const searchTerm = document.getElementById('staleSearch').value.toLowerCase();
            const severityFilter = document.getElementById('staleSeverityFilter').value;

            let filtered = window.staleCheckoutsData || [];

            if (searchTerm) {
                filtered = filtered.filter(c =>
                    (c.object_name && c.object_name.toLowerCase().includes(searchTerm)) ||
                    (c.object_type && c.object_type.toLowerCase().includes(searchTerm)) ||
                    (c.checked_out_by && c.checked_out_by.toLowerCase().includes(searchTerm))
                );
            }

            if (severityFilter) {
                filtered = filtered.filter(c => c.severity === severityFilter);
            }

            renderFilteredStaleCheckouts(filtered);
        }

        function renderBottleneckQueue(queue) {
            const container = document.getElementById('bottleneckQueueContainer');

            if (!queue || queue.length === 0) {
                container.innerHTML = '<div class="empty-state"><p>No bottlenecks detected</p></div>';
                return;
            }

            const maxHours = Math.max(...queue.map(q => q.total_hours || 0), 1);
            container.innerHTML = '';

            queue.forEach(user => {
                const percentage = (user.total_hours / maxHours) * 100;
                const daysText = (user.total_hours / 24).toFixed(1);

                const userItem = document.createElement('div');
                userItem.className = 'bar-item';
                userItem.style.marginBottom = '20px';
                userItem.innerHTML =
                    '<div class="bar-label">' +
                        '<span class="name">' + (user.user_name || 'Unknown') + '</span>' +
                        '<span class="value">' + (user.checkout_count || 0) + ' checkouts (' + daysText + ' days total)</span>' +
                    '</div>' +
                    '<div class="bar-track">' +
                        '<div class="bar-fill" style="width: ' + percentage + '%">' + (user.checkout_count || 0) + '</div>' +
                    '</div>' +
                    '<div style="margin-top: 5px; font-size: 0.85em; color: #7f8c8d;">' +
                        (user.items || []).map(item => item.object_name + ' (' + (item.duration_hours / 24).toFixed(1) + 'd)').join(', ') +
                    '</div>';
                container.appendChild(userItem);
            });
        }

        function exportStaleCheckoutsToCSV() {
            const data = window.staleCheckoutsData || [];

            if (data.length === 0) {
                alert('No stale checkouts to export');
                return;
            }

            let csv = 'Object,Type,Checked Out By,Duration (hours),Duration (days),Last Modified,Severity\n';
            data.forEach(row => {
                const objectName = (row.object_name || '').replace(/,/g, ' ');
                const objectType = (row.object_type || '').replace(/,/g, ' ');
                const checkedOutBy = (row.checked_out_by || '').replace(/,/g, ' ');
                const durationHours = row.checkout_duration_hours || 0;
                const durationDays = row.checkout_duration_days || 0;
                const lastModified = (row.last_modified || '').replace(/,/g, ' ');
                const severity = (row.severity || '').replace(/,/g, ' ');
                csv += '"' + objectName + '","' + objectType + '","' + checkedOutBy + '",' + durationHours + ',' + durationDays + ',"' + lastModified + '","' + severity + '"\n';
            });

            const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
            const link = document.createElement('a');
            const url = URL.createObjectURL(blob);

            link.setAttribute('href', url);
            link.setAttribute('download', 'stale-checkouts-export.csv');
            link.style.visibility = 'hidden';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }

        // ========================================
        // CSV EXPORT
        // ========================================
        function exportToCSV() {
            const data = window.activityLogData || [];

            if (data.length === 0) {
                alert('No data to export');
                return;
            }

            // Create CSV header
            let csv = 'Timestamp,User,Work Type,Object Name,Description,Confidence\n';

            // Add data rows
            data.forEach(row => {
                const timestamp = (row.timestamp || '').replace(/,/g, ' ');
                const user = (row.user || '').replace(/,/g, ' ');
                const workType = (row.workType || '').replace(/,/g, ' ');
                const objectName = (row.objectName || '').replace(/,/g, ' ');
                const description = (row.description || '').replace(/,/g, ' ');
                const confidence = getConfidenceValue(row.evidence) || '';

                csv += ``"`${timestamp}","`${user}","`${workType}","`${objectName}","`${description}","`${confidence}"\n``;
            });

            // Create download link
            const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' });
            const link = document.createElement('a');
            const url = URL.createObjectURL(blob);

            link.setAttribute('href', url);
            link.setAttribute('download', 'activity-log-export.csv');
            link.style.visibility = 'hidden';

            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }

        // ========================================
        // INITIALIZATION
        // ========================================
        document.addEventListener('DOMContentLoaded', function() {
            console.log('Dashboard initializing...');

            try {
                renderWorkTypeSummary();
                renderActiveStudies();
                renderMovementActivity();
                renderTreeChanges();
                populateUserSelectors();
                renderTimeline();
                renderActivityLog();
                renderStudyHealth();
                renderResourceConflicts();


                console.log('Dashboard initialized successfully');
            } catch (e) {
                console.error('Error initializing dashboard:', e);
                alert('Error initializing dashboard. Check browser console for details.');
            }
        });
    </script>
</body>
</html>
"@

# Write HTML file
Write-Host "Writing HTML file..." -ForegroundColor Yellow
try {
    $outputPath = [System.IO.Path]::GetFullPath($OutputFile)
    $outputDir = [System.IO.Path]::GetDirectoryName($outputPath)

    if (![string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Use UTF-8 encoding without BOM for better browser compatibility
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($outputPath, $html, $utf8NoBom)

    $fileSize = [math]::Round((Get-Item $outputPath).Length / 1MB, 2)

    Write-Host "  ✓ Dashboard generated successfully" -ForegroundColor Green
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Dashboard Complete" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Output File: $outputPath" -ForegroundColor Green
    Write-Host "  File Size:   $fileSize MB" -ForegroundColor Gray

    $scriptTimer.Stop()
    $elapsed = [math]::Round($scriptTimer.Elapsed.TotalSeconds, 2)
    Write-Host "  Total Time:  $($elapsed)s" -ForegroundColor Gray
    Write-Host ""

    Write-Host "Dashboard generated successfully!" -ForegroundColor Green
    Write-Host "Open the HTML file in your browser to view the interactive dashboard." -ForegroundColor Yellow
    Write-Host ""

    exit 0
}
catch {
    Write-Error "ERROR: Failed to write HTML file: $_"
    exit 1
}
