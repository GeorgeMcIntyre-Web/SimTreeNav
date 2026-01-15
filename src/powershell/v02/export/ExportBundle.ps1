# ExportBundle.ps1
# Packages snapshots, diffs, and analysis into portable offline bundles
# v0.3: Self-contained viewer bundles for sharing

<#
.SYNOPSIS
    Creates portable offline viewer bundles.

.DESCRIPTION
    Packages:
    - Selected snapshots and diffs
    - Sessions, intents, compliance, drift, anomalies
    - Viewer assets (HTML, CSS, JS)
    - Index.html that loads bundled JSON

    Result is a self-contained folder (or zip) that opens offline.

.EXAMPLE
    Export-Bundle -SnapshotPaths @('./snapshots/baseline', './snapshots/current') -OutDir './bundles/demo'
#>

function Get-ViewerTemplate {
    <#
    .SYNOPSIS
        Returns the HTML template for offline viewer.
    #>
    
    @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SimTreeNav - Offline Viewer</title>
    <style>
        :root {
            --bg-primary: #1e1e2e;
            --bg-secondary: #2d2d3d;
            --bg-tertiary: #3d3d4d;
            --text-primary: #cdd6f4;
            --text-secondary: #a6adc8;
            --accent-blue: #89b4fa;
            --accent-green: #a6e3a1;
            --accent-yellow: #f9e2af;
            --accent-red: #f38ba8;
            --accent-purple: #cba6f7;
        }
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
            min-height: 100vh;
        }
        .header {
            background: var(--bg-secondary);
            padding: 1rem 2rem;
            border-bottom: 1px solid var(--bg-tertiary);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .header h1 { font-size: 1.5rem; color: var(--accent-blue); }
        .header .meta { color: var(--text-secondary); font-size: 0.875rem; }
        .container { display: flex; height: calc(100vh - 60px); }
        .sidebar {
            width: 280px;
            background: var(--bg-secondary);
            border-right: 1px solid var(--bg-tertiary);
            overflow-y: auto;
            padding: 1rem;
        }
        .sidebar h3 {
            color: var(--text-secondary);
            font-size: 0.75rem;
            text-transform: uppercase;
            letter-spacing: 0.05em;
            margin-bottom: 0.5rem;
        }
        .nav-item {
            display: block;
            padding: 0.5rem 0.75rem;
            margin-bottom: 0.25rem;
            border-radius: 4px;
            cursor: pointer;
            color: var(--text-primary);
            text-decoration: none;
        }
        .nav-item:hover { background: var(--bg-tertiary); }
        .nav-item.active { background: var(--accent-blue); color: var(--bg-primary); }
        .main { flex: 1; padding: 2rem; overflow-y: auto; }
        .panel {
            background: var(--bg-secondary);
            border-radius: 8px;
            padding: 1.5rem;
            margin-bottom: 1.5rem;
        }
        .panel h2 { margin-bottom: 1rem; color: var(--accent-blue); }
        .stat-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 1rem; }
        .stat-card {
            background: var(--bg-tertiary);
            border-radius: 4px;
            padding: 1rem;
            text-align: center;
        }
        .stat-card .value { font-size: 2rem; font-weight: bold; color: var(--accent-blue); }
        .stat-card .label { font-size: 0.75rem; color: var(--text-secondary); }
        .badge {
            display: inline-block;
            padding: 0.25rem 0.5rem;
            border-radius: 4px;
            font-size: 0.75rem;
            font-weight: 500;
        }
        .badge-added { background: rgba(166, 227, 161, 0.2); color: var(--accent-green); }
        .badge-removed { background: rgba(243, 139, 168, 0.2); color: var(--accent-red); }
        .badge-renamed { background: rgba(249, 226, 175, 0.2); color: var(--accent-yellow); }
        .badge-moved { background: rgba(137, 180, 250, 0.2); color: var(--accent-blue); }
        .badge-critical { background: var(--accent-red); color: var(--bg-primary); }
        .badge-warn { background: var(--accent-yellow); color: var(--bg-primary); }
        .badge-info { background: var(--accent-blue); color: var(--bg-primary); }
        .table {
            width: 100%;
            border-collapse: collapse;
        }
        .table th, .table td {
            padding: 0.75rem;
            text-align: left;
            border-bottom: 1px solid var(--bg-tertiary);
        }
        .table th { color: var(--text-secondary); font-weight: 500; }
        .tree-node {
            padding: 0.25rem 0;
            padding-left: calc(var(--level, 0) * 1rem);
        }
        .hidden { display: none !important; }
        .tab-buttons { display: flex; gap: 0.5rem; margin-bottom: 1rem; }
        .tab-btn {
            padding: 0.5rem 1rem;
            background: var(--bg-tertiary);
            border: none;
            border-radius: 4px;
            color: var(--text-primary);
            cursor: pointer;
        }
        .tab-btn.active { background: var(--accent-blue); color: var(--bg-primary); }
        #loading { text-align: center; padding: 2rem; }
        .score-excellent { color: var(--accent-green); }
        .score-good { color: var(--accent-blue); }
        .score-warn { color: var(--accent-yellow); }
        .score-bad { color: var(--accent-red); }
    </style>
</head>
<body>
    <div class="header">
        <h1>SimTreeNav</h1>
        <div class="meta" id="bundle-meta">Loading...</div>
    </div>
    <div class="container">
        <div class="sidebar">
            <h3>Navigation</h3>
            <a class="nav-item active" data-section="overview">Overview</a>
            <a class="nav-item" data-section="diff">Changes</a>
            <a class="nav-item" data-section="sessions">Sessions</a>
            <a class="nav-item" data-section="intents">Intents</a>
            <a class="nav-item" data-section="impact">Impact</a>
            <a class="nav-item" data-section="drift">Drift</a>
            <a class="nav-item" data-section="compliance">Compliance</a>
            <a class="nav-item" data-section="anomalies">Anomalies</a>
            <a class="nav-item" data-section="tree">Tree View</a>
        </div>
        <div class="main" id="main-content">
            <div id="loading">Loading bundle data...</div>
        </div>
    </div>
    
    <script>
        // Bundle data will be embedded here
        const BUNDLE_DATA = __BUNDLE_DATA__;
        
        // Section rendering functions
        const sections = {
            overview: renderOverview,
            diff: renderDiff,
            sessions: renderSessions,
            intents: renderIntents,
            impact: renderImpact,
            drift: renderDrift,
            compliance: renderCompliance,
            anomalies: renderAnomalies,
            tree: renderTree
        };
        
        function init() {
            document.getElementById('bundle-meta').textContent = 
                `Bundle: ${BUNDLE_DATA.meta?.name || 'Unknown'} | Created: ${BUNDLE_DATA.meta?.createdAt || 'Unknown'}`;
            
            // Set up navigation
            document.querySelectorAll('.nav-item').forEach(item => {
                item.addEventListener('click', (e) => {
                    e.preventDefault();
                    document.querySelectorAll('.nav-item').forEach(i => i.classList.remove('active'));
                    item.classList.add('active');
                    renderSection(item.dataset.section);
                });
            });
            
            // Render initial section
            renderSection('overview');
        }
        
        function renderSection(sectionName) {
            const fn = sections[sectionName];
            if (fn) {
                document.getElementById('main-content').innerHTML = fn();
            }
        }
        
        function renderOverview() {
            const meta = BUNDLE_DATA.meta || {};
            const diff = BUNDLE_DATA.diff || {};
            const anomalies = BUNDLE_DATA.anomalies || {};
            const compliance = BUNDLE_DATA.compliance || {};
            
            return `
                <div class="panel">
                    <h2>Bundle Overview</h2>
                    <div class="stat-grid">
                        <div class="stat-card">
                            <div class="value">${diff.summary?.totalChanges || 0}</div>
                            <div class="label">Total Changes</div>
                        </div>
                        <div class="stat-card">
                            <div class="value">${diff.summary?.added || 0}</div>
                            <div class="label">Added</div>
                        </div>
                        <div class="stat-card">
                            <div class="value">${diff.summary?.removed || 0}</div>
                            <div class="label">Removed</div>
                        </div>
                        <div class="stat-card">
                            <div class="value">${anomalies.criticalCount || 0}</div>
                            <div class="label">Critical Alerts</div>
                        </div>
                    </div>
                </div>
                <div class="panel">
                    <h2>Quick Stats</h2>
                    <table class="table">
                        <tr><th>Metric</th><th>Value</th></tr>
                        <tr><td>Baseline Nodes</td><td>${meta.baselineNodeCount || 'N/A'}</td></tr>
                        <tr><td>Current Nodes</td><td>${meta.currentNodeCount || 'N/A'}</td></tr>
                        <tr><td>Compliance Score</td><td class="${getScoreClass(compliance.score)}">${compliance.score !== undefined ? (compliance.score * 100).toFixed(0) + '%' : 'N/A'}</td></tr>
                        <tr><td>Sessions Detected</td><td>${BUNDLE_DATA.sessions?.length || 0}</td></tr>
                    </table>
                </div>
            `;
        }
        
        function renderDiff() {
            const diff = BUNDLE_DATA.diff || {};
            const changes = diff.changes || [];
            
            return `
                <div class="panel">
                    <h2>Changes (${changes.length})</h2>
                    <table class="table">
                        <thead>
                            <tr><th>Type</th><th>Name</th><th>Node Type</th><th>Path</th></tr>
                        </thead>
                        <tbody>
                            ${changes.slice(0, 100).map(c => `
                                <tr>
                                    <td><span class="badge badge-${c.changeType}">${c.changeType}</span></td>
                                    <td>${escapeHtml(c.nodeName || c.name || '')}</td>
                                    <td>${c.nodeType || ''}</td>
                                    <td style="font-size: 0.75rem; color: var(--text-secondary)">${escapeHtml(c.path || '')}</td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                    ${changes.length > 100 ? '<p style="margin-top: 1rem; color: var(--text-secondary)">Showing first 100 of ' + changes.length + ' changes</p>' : ''}
                </div>
            `;
        }
        
        function renderSessions() {
            const sessions = BUNDLE_DATA.sessions || [];
            
            return `
                <div class="panel">
                    <h2>Work Sessions (${sessions.length})</h2>
                    ${sessions.map(s => `
                        <div style="background: var(--bg-tertiary); padding: 1rem; border-radius: 4px; margin-bottom: 0.5rem;">
                            <strong>${s.sessionId}</strong>
                            <span style="float: right; color: var(--text-secondary)">${s.changeCount} changes</span>
                            <div style="font-size: 0.875rem; color: var(--text-secondary); margin-top: 0.5rem;">
                                Types: ${s.changeTypes?.join(', ') || 'N/A'} | 
                                Subtrees: ${s.subtrees?.length || 0}
                            </div>
                        </div>
                    `).join('')}
                </div>
            `;
        }
        
        function renderIntents() {
            const intents = BUNDLE_DATA.intents || [];
            
            return `
                <div class="panel">
                    <h2>Detected Intents (${intents.length})</h2>
                    ${intents.map(i => `
                        <div style="background: var(--bg-tertiary); padding: 1rem; border-radius: 4px; margin-bottom: 0.5rem;">
                            <strong>${i.intentType}</strong>
                            <span style="float: right;">${(i.confidence * 100).toFixed(0)}% confidence</span>
                            <p style="margin-top: 0.5rem; color: var(--text-secondary)">${escapeHtml(i.explanation)}</p>
                        </div>
                    `).join('')}
                </div>
            `;
        }
        
        function renderImpact() {
            const impact = BUNDLE_DATA.impact || {};
            const topRisk = impact.topRiskNodes || [];
            
            return `
                <div class="panel">
                    <h2>Impact Analysis</h2>
                    <div class="stat-grid">
                        <div class="stat-card">
                            <div class="value">${impact.totalDownstreamImpact || 0}</div>
                            <div class="label">Downstream Impact</div>
                        </div>
                        <div class="stat-card">
                            <div class="value">${impact.criticalRiskCount || 0}</div>
                            <div class="label">Critical Risk</div>
                        </div>
                    </div>
                </div>
                <div class="panel">
                    <h2>Top Risk Nodes</h2>
                    <table class="table">
                        <thead><tr><th>Name</th><th>Risk Score</th><th>Level</th><th>Dependents</th></tr></thead>
                        <tbody>
                            ${topRisk.map(n => `
                                <tr>
                                    <td>${escapeHtml(n.nodeName || '')}</td>
                                    <td>${(n.riskScore * 100).toFixed(0)}%</td>
                                    <td><span class="badge badge-${n.riskLevel?.toLowerCase()}">${n.riskLevel}</span></td>
                                    <td>${n.downstreamCount || 0}</td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            `;
        }
        
        function renderDrift() {
            const drift = BUNDLE_DATA.drift || {};
            
            return `
                <div class="panel">
                    <h2>Drift Analysis</h2>
                    <div class="stat-grid">
                        <div class="stat-card">
                            <div class="value">${drift.totalPairs || 0}</div>
                            <div class="label">Total Pairs</div>
                        </div>
                        <div class="stat-card">
                            <div class="value ${drift.driftedPairs > 0 ? 'score-warn' : ''}">${drift.driftedPairs || 0}</div>
                            <div class="label">Drifted</div>
                        </div>
                        <div class="stat-card">
                            <div class="value">${((drift.driftRate || 0) * 100).toFixed(1)}%</div>
                            <div class="label">Drift Rate</div>
                        </div>
                    </div>
                </div>
                ${drift.topDrifted?.length > 0 ? `
                <div class="panel">
                    <h2>Top Drifted Pairs</h2>
                    <table class="table">
                        <thead><tr><th>Source</th><th>Target</th><th>Position (mm)</th><th>Rotation (deg)</th></tr></thead>
                        <tbody>
                            ${drift.topDrifted.map(d => `
                                <tr>
                                    <td>${escapeHtml(d.sourceName || '')}</td>
                                    <td>${escapeHtml(d.targetName || '')}</td>
                                    <td>${d.positionDelta_mm?.toFixed(2) || '0'}</td>
                                    <td>${d.rotationDelta_deg?.toFixed(2) || '0'}</td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
                ` : ''}
            `;
        }
        
        function renderCompliance() {
            const c = BUNDLE_DATA.compliance || {};
            
            return `
                <div class="panel">
                    <h2>Compliance Report</h2>
                    <div class="stat-grid">
                        <div class="stat-card">
                            <div class="value ${getScoreClass(c.score)}">${c.score !== undefined ? (c.score * 100).toFixed(0) + '%' : 'N/A'}</div>
                            <div class="label">Compliance Score</div>
                        </div>
                        <div class="stat-card">
                            <div class="value">${c.level || 'Unknown'}</div>
                            <div class="label">Level</div>
                        </div>
                    </div>
                </div>
                ${c.actionItems?.length > 0 ? `
                <div class="panel">
                    <h2>Action Items</h2>
                    ${c.actionItems.map(a => `
                        <div style="background: var(--bg-tertiary); padding: 0.75rem; border-radius: 4px; margin-bottom: 0.5rem; display: flex; align-items: center;">
                            <span class="badge badge-${a.severity?.toLowerCase()}" style="margin-right: 1rem;">${a.severity}</span>
                            <span>${escapeHtml(a.description)}</span>
                        </div>
                    `).join('')}
                </div>
                ` : ''}
            `;
        }
        
        function renderAnomalies() {
            const a = BUNDLE_DATA.anomalies || {};
            const list = a.anomalies || [];
            
            return `
                <div class="panel">
                    <h2>Anomaly Detection</h2>
                    <div class="stat-grid">
                        <div class="stat-card">
                            <div class="value ${a.criticalCount > 0 ? 'score-bad' : ''}">${a.criticalCount || 0}</div>
                            <div class="label">Critical</div>
                        </div>
                        <div class="stat-card">
                            <div class="value ${a.warnCount > 0 ? 'score-warn' : ''}">${a.warnCount || 0}</div>
                            <div class="label">Warnings</div>
                        </div>
                        <div class="stat-card">
                            <div class="value">${a.infoCount || 0}</div>
                            <div class="label">Info</div>
                        </div>
                    </div>
                </div>
                ${list.length > 0 ? `
                <div class="panel">
                    <h2>Alerts</h2>
                    ${list.map(al => `
                        <div style="background: var(--bg-tertiary); padding: 1rem; border-radius: 4px; margin-bottom: 0.5rem;">
                            <span class="badge badge-${al.severity?.toLowerCase()}">${al.severity}</span>
                            <strong style="margin-left: 0.5rem;">${al.type}</strong>
                            <p style="margin-top: 0.5rem; color: var(--text-secondary)">${escapeHtml(al.description)}</p>
                        </div>
                    `).join('')}
                </div>
                ` : '<div class="panel"><p style="color: var(--text-secondary)">No anomalies detected.</p></div>'}
            `;
        }
        
        function renderTree() {
            const nodes = BUNDLE_DATA.currentNodes || BUNDLE_DATA.nodes || [];
            
            return `
                <div class="panel">
                    <h2>Tree View (${nodes.length} nodes)</h2>
                    <p style="color: var(--text-secondary); margin-bottom: 1rem;">Showing node hierarchy (top-level only for performance)</p>
                    <div>
                        ${nodes.filter(n => !n.parentId).slice(0, 50).map(n => renderTreeNode(n, nodes, 0)).join('')}
                    </div>
                    ${nodes.length > 50 ? '<p style="margin-top: 1rem; color: var(--text-secondary)">Tree view limited for performance</p>' : ''}
                </div>
            `;
        }
        
        function renderTreeNode(node, allNodes, level) {
            const children = allNodes.filter(n => n.parentId === node.nodeId);
            const hasChildren = children.length > 0;
            
            return `
                <div class="tree-node" style="--level: ${level}">
                    ${hasChildren ? '▸' : '•'} <strong>${escapeHtml(node.name || node.nodeId)}</strong>
                    <span style="color: var(--text-secondary); font-size: 0.75rem;">[${node.nodeType}]</span>
                </div>
                ${level < 2 && hasChildren ? children.slice(0, 10).map(c => renderTreeNode(c, allNodes, level + 1)).join('') : ''}
            `;
        }
        
        function getScoreClass(score) {
            if (score === undefined) return '';
            if (score >= 0.9) return 'score-excellent';
            if (score >= 0.7) return 'score-good';
            if (score >= 0.5) return 'score-warn';
            return 'score-bad';
        }
        
        function escapeHtml(str) {
            if (!str) return '';
            return String(str)
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;');
        }
        
        // Initialize
        init();
    </script>
</body>
</html>
'@
}

function Export-Bundle {
    <#
    .SYNOPSIS
        Main entry point for creating offline bundles.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutDir,
        
        [string]$Name = 'SimTreeNav Bundle',
        
        [array]$BaselineNodes = @(),
        
        [array]$CurrentNodes = @(),
        
        [PSCustomObject]$Diff = $null,
        
        [array]$Sessions = @(),
        
        [array]$Intents = @(),
        
        [PSCustomObject]$Impact = $null,
        
        [PSCustomObject]$Drift = $null,
        
        [PSCustomObject]$Compliance = $null,
        
        [PSCustomObject]$Anomalies = $null,
        
        [switch]$CreateZip
    )
    
    # Create output directory
    if (-not (Test-Path $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    
    # Build bundle data
    $bundleData = [PSCustomObject]@{
        meta = [PSCustomObject]@{
            name              = $Name
            createdAt         = (Get-Date).ToUniversalTime().ToString('o')
            version           = '0.3.0'
            baselineNodeCount = $BaselineNodes.Count
            currentNodeCount  = $CurrentNodes.Count
        }
        diff          = $Diff
        sessions      = $Sessions
        intents       = $Intents
        impact        = $Impact
        drift         = $Drift
        compliance    = $Compliance
        anomalies     = $Anomalies
        currentNodes  = $CurrentNodes | Select-Object nodeId, name, nodeType, parentId, path -First 1000
    }
    
    # Convert to JSON
    $bundleJson = $bundleData | ConvertTo-Json -Depth 15 -Compress
    
    # Get HTML template and embed data
    $htmlTemplate = Get-ViewerTemplate
    $html = $htmlTemplate -replace '__BUNDLE_DATA__', $bundleJson
    
    # Write index.html
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $OutDir 'index.html'), $html, $utf8NoBom)
    
    # Also write raw JSON files for advanced use
    $dataDir = Join-Path $OutDir 'data'
    if (-not (Test-Path $dataDir)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
    
    if ($Diff) {
        $Diff | ConvertTo-Json -Depth 10 -Compress | Set-Content (Join-Path $dataDir 'diff.json') -Encoding UTF8
    }
    if ($Sessions.Count -gt 0) {
        $Sessions | ConvertTo-Json -Depth 10 -Compress | Set-Content (Join-Path $dataDir 'sessions.json') -Encoding UTF8
    }
    if ($Intents.Count -gt 0) {
        $Intents | ConvertTo-Json -Depth 10 -Compress | Set-Content (Join-Path $dataDir 'intents.json') -Encoding UTF8
    }
    if ($Anomalies) {
        $Anomalies | ConvertTo-Json -Depth 10 -Compress | Set-Content (Join-Path $dataDir 'anomalies.json') -Encoding UTF8
    }
    
    # Create zip if requested
    if ($CreateZip) {
        $zipPath = "$OutDir.zip"
        if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
        Compress-Archive -Path $OutDir -DestinationPath $zipPath -Force
        Write-Host "Created zip: $zipPath"
    }
    
    Write-Host "Bundle created: $OutDir"
    Write-Host "Open index.html in a browser to view offline"
    
    return [PSCustomObject]@{
        path    = $OutDir
        zipPath = if ($CreateZip) { "$OutDir.zip" } else { $null }
    }
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Export-Bundle',
        'Get-ViewerTemplate'
    )
}
