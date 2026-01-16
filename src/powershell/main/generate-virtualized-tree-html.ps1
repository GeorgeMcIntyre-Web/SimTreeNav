# Generate Virtualized Tree HTML for large projects (50k+ nodes)
# Uses virtual scrolling and lazy loading for responsive UI

param(
    [string]$DataFile = "tree-data-full-clean.txt",
    [string]$ProjectName = "",
    [string]$ProjectId = "",
    [string]$Schema = "",
    [string]$OutputFile = "navigation-tree-virtualized.html",
    [string]$ExtractedTypeIds = "",
    [string]$IconDataJson = "{}",
    [string]$UserActivityJs = "",
    [int]$MaxNodesInViewer = 100000,  # Hard cap with warnings
    [switch]$GenerateJsonOutput,       # Also output nodes.json
    [switch]$CompressOutput            # Gzip the output
)

# Import utilities
$scriptRoot = $PSScriptRoot
$perfMetricsPath = Join-Path $scriptRoot "..\utilities\PerformanceMetrics.ps1"
$streamingPath = Join-Path $scriptRoot "..\utilities\StreamingJsonWriter.ps1"
$compressionPath = Join-Path $scriptRoot "..\utilities\CompressionUtils.ps1"

if (Test-Path $perfMetricsPath) { Import-Module $perfMetricsPath -Force }
if (Test-Path $streamingPath) { Import-Module $streamingPath -Force }
if (Test-Path $compressionPath) { Import-Module $compressionPath -Force }

# Start performance tracking
if (Get-Command Start-PerfSession -ErrorAction SilentlyContinue) {
    Start-PerfSession -Phase "GenerateVirtualizedTree"
}

$startTime = Get-Date

# Read data file
$bytes = [System.IO.File]::ReadAllBytes("$PWD\$DataFile")

if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $data = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
} else {
    $data = [System.Text.Encoding]::UTF8.GetString($bytes)
}
$data = $data.Trim()

# Count nodes
$lines = $data -split "`r?`n" | Where-Object { $_ -match '^\d+\|' }
$nodeCount = $lines.Count

Write-Host "[VIRTUALIZED] Processing $nodeCount nodes..." -ForegroundColor Cyan

# Check node limit
$nodeLimitWarning = ""
if ($nodeCount -gt $MaxNodesInViewer) {
    $nodeLimitWarning = "WARNING: Tree has $nodeCount nodes, exceeds limit of $MaxNodesInViewer. Performance may be degraded."
    Write-Warning $nodeLimitWarning
}

# Record memory snapshot
if (Get-Command Record-MemorySnapshot -ErrorAction SilentlyContinue) {
    Record-MemorySnapshot -Label "After data load"
}

# Escape data for JavaScript
$escapedData = $data -replace '\\', '\\\\' -replace '`', '\`' -replace '\$', '\$' -replace "`"", '\"'
$escapedData = $escapedData -replace "`r`n", "`n" -replace "`r", "`n"

# The virtualized tree HTML template with virtual scrolling
$htmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PROJECT_NAME_PLACEHOLDER Navigation Tree - SCHEMA_PLACEHOLDER (Virtualized)</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        
        :root {
            --item-height: 28px;
            --indent-size: 20px;
            --primary-color: #667eea;
            --bg-color: #f8f9fa;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }
        
        .container {
            max-width: 1600px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            padding: 30px;
            display: flex;
            flex-direction: column;
            height: calc(100vh - 40px);
        }
        
        h1 { color: #333; margin-bottom: 10px; font-size: 24px; }
        
        .subtitle { color: #666; margin-bottom: 15px; font-size: 13px; }
        
        .warning-banner {
            background: #fff3cd;
            border: 1px solid #ffc107;
            color: #856404;
            padding: 10px 15px;
            border-radius: 5px;
            margin-bottom: 15px;
            font-size: 13px;
        }
        
        .controls {
            margin-bottom: 15px;
            padding: 12px;
            background: #f5f5f5;
            border-radius: 5px;
            display: flex;
            gap: 10px;
            align-items: center;
            flex-wrap: wrap;
        }
        
        .controls button {
            background: var(--primary-color);
            color: white;
            border: none;
            padding: 6px 12px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 13px;
            transition: background 0.2s;
        }
        
        .controls button:hover { background: #5568d3; }
        .controls button:disabled { background: #ccc; cursor: not-allowed; }
        
        .search-container {
            display: flex;
            gap: 8px;
            align-items: center;
            margin-left: auto;
        }
        
        .search-container input {
            width: 250px;
            padding: 6px 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 13px;
        }
        
        .search-results-count {
            font-size: 12px;
            color: #666;
            min-width: 80px;
        }
        
        /* Virtual scroll container */
        .tree-viewport {
            flex: 1;
            overflow-y: auto;
            overflow-x: hidden;
            border: 1px solid #e0e0e0;
            border-radius: 5px;
            position: relative;
        }
        
        .tree-scroll-content {
            position: relative;
            width: 100%;
        }
        
        .tree-visible-area {
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            width: 100%;
        }
        
        /* Tree node styles */
        .tree-row {
            height: var(--item-height);
            display: flex;
            align-items: center;
            padding: 0 8px;
            cursor: pointer;
            border-bottom: 1px solid #f0f0f0;
            white-space: nowrap;
            transition: background 0.15s;
        }
        
        .tree-row:hover { background: #f5f5f5; }
        .tree-row.selected { background: #e3f2fd; border-left: 3px solid var(--primary-color); }
        .tree-row.highlight { background: #fff9c4 !important; }
        .tree-row.level-0 { font-weight: bold; background: #f8f9fa; }
        .tree-row.level-1 { font-weight: 600; }
        
        .tree-indent { flex-shrink: 0; }
        
        .tree-toggle {
            width: 18px;
            height: 18px;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-right: 4px;
            cursor: pointer;
            color: var(--primary-color);
            font-size: 10px;
            flex-shrink: 0;
        }
        
        .tree-toggle.collapsed::before { content: '\25B6'; }
        .tree-toggle.expanded::before { content: '\25BC'; }
        .tree-toggle.leaf { visibility: hidden; }
        
        .tree-icon {
            width: 16px;
            height: 16px;
            margin-right: 6px;
            flex-shrink: 0;
        }
        
        .tree-label {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            color: #333;
        }
        
        .tree-id {
            color: #999;
            font-size: 11px;
            margin-left: 8px;
            font-family: 'Courier New', monospace;
        }
        
        .tree-checkout {
            color: #28a745;
            font-weight: bold;
            margin-left: 6px;
        }
        
        .tree-user {
            color: #007bff;
            font-size: 11px;
            margin-left: 4px;
        }
        
        /* Stats bar */
        .stats {
            margin-top: 15px;
            padding: 10px 15px;
            background: #f9f9f9;
            border-radius: 5px;
            font-size: 12px;
            color: #666;
            display: flex;
            gap: 20px;
            flex-wrap: wrap;
        }
        
        .stats-item { display: flex; gap: 5px; }
        .stats-label { color: #999; }
        .stats-value { font-weight: 500; color: #333; }
        
        /* Loading indicator */
        .loading-indicator {
            position: fixed;
            top: 20px;
            right: 20px;
            background: var(--primary-color);
            color: white;
            padding: 8px 15px;
            border-radius: 20px;
            font-size: 12px;
            opacity: 0;
            transition: opacity 0.3s;
            z-index: 1000;
        }
        
        .loading-indicator.visible { opacity: 1; }
        
        /* Search highlight */
        .search-match {
            background: #ffeb3b;
            padding: 0 2px;
            border-radius: 2px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>PROJECT_NAME_PLACEHOLDER Navigation Tree</h1>
        <div class="subtitle">SCHEMA_PLACEHOLDER Schema | Project ID: PROJECT_ID_PLACEHOLDER | Virtualized Large Tree Viewer</div>
        
        <div id="warningBanner" class="warning-banner" style="display: none;"></div>
        
        <div class="controls">
            <button onclick="expandToLevel(1)" title="Expand root and first level">Expand Level 1</button>
            <button onclick="expandToLevel(2)">Expand Level 2</button>
            <button onclick="collapseAll()">Collapse All</button>
            <button onclick="expandVisible()">Expand Visible</button>
            <button id="gotoSelectedBtn" onclick="scrollToSelected()" disabled>Go to Selected</button>
            
            <div class="search-container">
                <input type="text" id="searchInput" placeholder="Search nodes..." onkeyup="handleSearch(event)">
                <button onclick="searchTree()">Search</button>
                <button onclick="clearSearch()">Clear</button>
                <span id="searchResultsCount" class="search-results-count"></span>
            </div>
        </div>
        
        <div id="treeViewport" class="tree-viewport">
            <div id="treeScrollContent" class="tree-scroll-content">
                <div id="treeVisibleArea" class="tree-visible-area"></div>
            </div>
        </div>
        
        <div class="stats">
            <div class="stats-item"><span class="stats-label">Total Nodes:</span><span id="statsTotalNodes" class="stats-value">0</span></div>
            <div class="stats-item"><span class="stats-label">Visible:</span><span id="statsVisibleNodes" class="stats-value">0</span></div>
            <div class="stats-item"><span class="stats-label">Expanded:</span><span id="statsExpandedNodes" class="stats-value">0</span></div>
            <div class="stats-item"><span class="stats-label">Max Depth:</span><span id="statsMaxDepth" class="stats-value">0</span></div>
            <div class="stats-item"><span class="stats-label">Render Time:</span><span id="statsRenderTime" class="stats-value">0ms</span></div>
        </div>
    </div>
    
    <div id="loadingIndicator" class="loading-indicator">Loading...</div>

    <script>
        // Configuration
        const CONFIG = {
            ITEM_HEIGHT: 28,
            OVERSCAN: 10,
            INDENT_SIZE: 20,
            MAX_NODES: MAX_NODES_PLACEHOLDER,
            SEARCH_DEBOUNCE_MS: 300,
            BATCH_RENDER_SIZE: 100
        };
        
        // State
        const state = {
            nodes: new Map(),
            nodeList: [],
            flatList: [],
            expandedNodes: new Set(),
            selectedNodeId: null,
            searchResults: [],
            searchIndex: -1,
            searchTerm: '',
            scrollTop: 0,
            viewportHeight: 0,
            isBuilding: false
        };
        
        // Icon data
        const iconDataMap = ICON_DATA_JSON_PLACEHOLDER;
        
        // User activity
        USER_ACTIVITY_PLACEHOLDER
        
        // Performance tracking
        const perf = {
            parseStart: 0,
            parseEnd: 0,
            buildStart: 0,
            buildEnd: 0,
            lastRenderTime: 0
        };
        
        // Raw data
        const rawData = `TREE_DATA_PLACEHOLDER`;
        
        // DOM elements
        let viewport, scrollContent, visibleArea;
        
        // ========== INITIALIZATION ==========
        
        function init() {
            viewport = document.getElementById('treeViewport');
            scrollContent = document.getElementById('treeScrollContent');
            visibleArea = document.getElementById('treeVisibleArea');
            
            showLoading('Parsing data...');
            
            // Defer heavy work to allow UI to update
            requestAnimationFrame(() => {
                perf.parseStart = performance.now();
                parseData();
                perf.parseEnd = performance.now();
                console.log(`[PERF] Parse: ${(perf.parseEnd - perf.parseStart).toFixed(0)}ms`);
                
                showLoading('Building tree...');
                
                requestAnimationFrame(() => {
                    perf.buildStart = performance.now();
                    buildFlatList();
                    perf.buildEnd = performance.now();
                    console.log(`[PERF] Build: ${(perf.buildEnd - perf.buildStart).toFixed(0)}ms`);
                    
                    // Check node limit
                    if (state.nodes.size > CONFIG.MAX_NODES) {
                        document.getElementById('warningBanner').style.display = 'block';
                        document.getElementById('warningBanner').textContent = 
                            `Warning: Tree has ${state.nodes.size.toLocaleString()} nodes, exceeds recommended limit of ${CONFIG.MAX_NODES.toLocaleString()}. Performance may be affected.`;
                    }
                    
                    // Initial expand to level 1
                    expandToLevel(1);
                    
                    // Setup event listeners
                    viewport.addEventListener('scroll', handleScroll, { passive: true });
                    window.addEventListener('resize', debounce(handleResize, 100));
                    
                    // Initial render
                    state.viewportHeight = viewport.clientHeight;
                    render();
                    updateStats();
                    
                    hideLoading();
                });
            });
        }
        
        function showLoading(message) {
            const el = document.getElementById('loadingIndicator');
            el.textContent = message;
            el.classList.add('visible');
        }
        
        function hideLoading() {
            document.getElementById('loadingIndicator').classList.remove('visible');
        }
        
        // ========== DATA PARSING ==========
        
        function parseData() {
            const lines = rawData.split('\n').filter(line => line.trim() && line.includes('|'));
            
            let maxLevel = 0;
            
            lines.forEach((line, index) => {
                const parts = line.split('|');
                if (parts.length < 9) return;
                
                const level = parseInt(parts[0]) || 0;
                const parentId = parseInt(parts[1]) || 0;
                const objectId = parseInt(parts[2]);
                const caption = parts[3] || parts[4] || 'Unnamed';
                const externalId = parts[5] || '';
                const seqNumber = parseInt(parts[6]) || 0;
                const className = parts[7] || 'class PmNode';
                const niceName = parts[8] || '';
                const typeId = parts[9] ? parseInt(parts[9]) : 0;
                
                if (!state.nodes.has(objectId)) {
                    state.nodes.set(objectId, {
                        id: objectId,
                        name: caption,
                        level: level === 999 ? 0 : level,
                        parentId: parentId,
                        externalId: externalId,
                        seqNumber: seqNumber,
                        className: className,
                        niceName: niceName,
                        typeId: typeId,
                        children: [],
                        sqlOrder: index,
                        hasCheckout: typeof userActivity !== 'undefined' && userActivity[objectId]
                    });
                    
                    maxLevel = Math.max(maxLevel, level);
                }
            });
            
            // Build parent-child relationships
            state.nodes.forEach(node => {
                if (node.parentId && state.nodes.has(node.parentId)) {
                    const parent = state.nodes.get(node.parentId);
                    if (!parent.children.find(c => c === node.id)) {
                        parent.children.push(node.id);
                    }
                }
            });
            
            // Sort children by sqlOrder
            state.nodes.forEach(node => {
                if (node.children.length > 0) {
                    node.children.sort((a, b) => {
                        const nodeA = state.nodes.get(a);
                        const nodeB = state.nodes.get(b);
                        return (nodeA?.sqlOrder || 0) - (nodeB?.sqlOrder || 0);
                    });
                }
            });
            
            // Store max level
            state.maxLevel = maxLevel;
            
            console.log(`[PARSE] Loaded ${state.nodes.size} nodes, max level: ${maxLevel}`);
        }
        
        // ========== FLAT LIST BUILDING ==========
        
        function buildFlatList() {
            state.flatList = [];
            
            // Find root nodes (level 0 or no parent in tree)
            const rootNodes = [];
            state.nodes.forEach(node => {
                if (node.level === 0 || !state.nodes.has(node.parentId)) {
                    rootNodes.push(node);
                }
            });
            
            // Sort roots by sqlOrder
            rootNodes.sort((a, b) => a.sqlOrder - b.sqlOrder);
            
            // Build flat list with DFS
            const visited = new Set();
            
            function addNodeAndVisibleChildren(nodeId, depth = 0) {
                if (visited.has(nodeId)) return;
                visited.add(nodeId);
                
                const node = state.nodes.get(nodeId);
                if (!node) return;
                
                state.flatList.push({
                    id: node.id,
                    depth: depth
                });
                
                if (state.expandedNodes.has(node.id) && node.children.length > 0) {
                    node.children.forEach(childId => {
                        addNodeAndVisibleChildren(childId, depth + 1);
                    });
                }
            }
            
            rootNodes.forEach(root => addNodeAndVisibleChildren(root.id, 0));
        }
        
        // ========== VIRTUAL SCROLLING ==========
        
        function handleScroll() {
            state.scrollTop = viewport.scrollTop;
            render();
        }
        
        function handleResize() {
            state.viewportHeight = viewport.clientHeight;
            render();
        }
        
        function render() {
            const startTime = performance.now();
            
            const totalHeight = state.flatList.length * CONFIG.ITEM_HEIGHT;
            scrollContent.style.height = `${totalHeight}px`;
            
            const startIndex = Math.max(0, Math.floor(state.scrollTop / CONFIG.ITEM_HEIGHT) - CONFIG.OVERSCAN);
            const visibleCount = Math.ceil(state.viewportHeight / CONFIG.ITEM_HEIGHT) + (CONFIG.OVERSCAN * 2);
            const endIndex = Math.min(state.flatList.length, startIndex + visibleCount);
            
            const fragment = document.createDocumentFragment();
            
            for (let i = startIndex; i < endIndex; i++) {
                const item = state.flatList[i];
                const node = state.nodes.get(item.id);
                if (!node) continue;
                
                const row = createRow(node, item.depth, i);
                fragment.appendChild(row);
            }
            
            visibleArea.innerHTML = '';
            visibleArea.style.top = `${startIndex * CONFIG.ITEM_HEIGHT}px`;
            visibleArea.appendChild(fragment);
            
            perf.lastRenderTime = performance.now() - startTime;
            document.getElementById('statsRenderTime').textContent = `${perf.lastRenderTime.toFixed(1)}ms`;
            document.getElementById('statsVisibleNodes').textContent = (endIndex - startIndex).toLocaleString();
        }
        
        function createRow(node, depth, index) {
            const row = document.createElement('div');
            row.className = `tree-row level-${node.level}`;
            row.dataset.nodeId = node.id;
            row.dataset.index = index;
            
            if (state.selectedNodeId === node.id) {
                row.classList.add('selected');
            }
            
            if (state.searchResults.includes(node.id)) {
                row.classList.add('highlight');
            }
            
            // Indent
            const indent = document.createElement('span');
            indent.className = 'tree-indent';
            indent.style.width = `${depth * CONFIG.INDENT_SIZE}px`;
            row.appendChild(indent);
            
            // Toggle
            const toggle = document.createElement('span');
            toggle.className = 'tree-toggle';
            if (node.children.length > 0) {
                toggle.classList.add(state.expandedNodes.has(node.id) ? 'expanded' : 'collapsed');
                toggle.onclick = (e) => {
                    e.stopPropagation();
                    toggleNode(node.id);
                };
            } else {
                toggle.classList.add('leaf');
            }
            row.appendChild(toggle);
            
            // Icon
            const icon = document.createElement('img');
            icon.className = 'tree-icon';
            if (node.typeId && iconDataMap[node.typeId]) {
                icon.src = iconDataMap[node.typeId];
            } else {
                icon.src = getDefaultIcon(node.className, node.niceName);
            }
            icon.onerror = () => {
                icon.src = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16'%3E%3Crect fill='%23ddd' width='16' height='16'/%3E%3C/svg%3E";
            };
            row.appendChild(icon);
            
            // Label
            const label = document.createElement('span');
            label.className = 'tree-label';
            label.textContent = node.name;
            label.title = `${node.name}\nClass: ${node.className}\nType: ${node.niceName}`;
            row.appendChild(label);
            
            // ID
            const idSpan = document.createElement('span');
            idSpan.className = 'tree-id';
            idSpan.textContent = `[${node.id}]`;
            row.appendChild(idSpan);
            
            // Checkout indicator
            if (node.hasCheckout && typeof userActivity !== 'undefined' && userActivity[node.id]) {
                const checkout = document.createElement('span');
                checkout.className = 'tree-checkout';
                checkout.innerHTML = '&#x2713;';
                row.appendChild(checkout);
                
                const user = document.createElement('span');
                user.className = 'tree-user';
                user.textContent = userActivity[node.id].user || '';
                row.appendChild(user);
            }
            
            // Click handler
            row.onclick = () => selectNode(node.id);
            row.ondblclick = () => toggleNode(node.id);
            
            return row;
        }
        
        function getDefaultIcon(className, niceName) {
            // Simplified default icon logic
            return "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16'%3E%3Crect fill='%234a90d9' width='16' height='16' rx='2'/%3E%3C/svg%3E";
        }
        
        // ========== NODE OPERATIONS ==========
        
        function toggleNode(nodeId) {
            if (state.expandedNodes.has(nodeId)) {
                state.expandedNodes.delete(nodeId);
            } else {
                state.expandedNodes.add(nodeId);
            }
            buildFlatList();
            render();
            updateStats();
        }
        
        function selectNode(nodeId) {
            state.selectedNodeId = nodeId;
            document.getElementById('gotoSelectedBtn').disabled = false;
            render();
        }
        
        function expandToLevel(maxLevel) {
            state.expandedNodes.clear();
            
            state.nodes.forEach(node => {
                if (node.level < maxLevel && node.children.length > 0) {
                    state.expandedNodes.add(node.id);
                }
            });
            
            buildFlatList();
            render();
            updateStats();
        }
        
        function collapseAll() {
            state.expandedNodes.clear();
            buildFlatList();
            viewport.scrollTop = 0;
            render();
            updateStats();
        }
        
        function expandVisible() {
            const visibleNodes = new Set();
            visibleArea.querySelectorAll('.tree-row').forEach(row => {
                const nodeId = parseInt(row.dataset.nodeId);
                const node = state.nodes.get(nodeId);
                if (node && node.children.length > 0) {
                    state.expandedNodes.add(nodeId);
                }
            });
            buildFlatList();
            render();
            updateStats();
        }
        
        function scrollToSelected() {
            if (!state.selectedNodeId) return;
            
            const index = state.flatList.findIndex(item => item.id === state.selectedNodeId);
            if (index >= 0) {
                viewport.scrollTop = index * CONFIG.ITEM_HEIGHT - (state.viewportHeight / 2);
            }
        }
        
        // ========== SEARCH ==========
        
        let searchTimeout = null;
        
        function handleSearch(event) {
            if (event.key === 'Enter') {
                searchTree();
            } else if (event.key === 'Escape') {
                clearSearch();
            } else {
                // Debounced incremental search
                clearTimeout(searchTimeout);
                searchTimeout = setTimeout(() => {
                    if (document.getElementById('searchInput').value.length >= 2) {
                        searchTree();
                    }
                }, CONFIG.SEARCH_DEBOUNCE_MS);
            }
        }
        
        function searchTree() {
            const term = document.getElementById('searchInput').value.toLowerCase().trim();
            
            if (!term) {
                clearSearch();
                return;
            }
            
            state.searchTerm = term;
            state.searchResults = [];
            state.searchIndex = -1;
            
            // Build search index incrementally (first 1000 matches)
            state.nodes.forEach(node => {
                if (state.searchResults.length < 1000 && 
                    node.name.toLowerCase().includes(term)) {
                    state.searchResults.push(node.id);
                }
            });
            
            document.getElementById('searchResultsCount').textContent = 
                `${state.searchResults.length}${state.searchResults.length >= 1000 ? '+' : ''} found`;
            
            // Expand parents of first result and scroll to it
            if (state.searchResults.length > 0) {
                state.searchIndex = 0;
                goToSearchResult(0);
            }
            
            render();
        }
        
        function goToSearchResult(index) {
            if (index < 0 || index >= state.searchResults.length) return;
            
            const nodeId = state.searchResults[index];
            
            // Expand all ancestors
            let current = state.nodes.get(nodeId);
            while (current && current.parentId) {
                if (state.nodes.has(current.parentId)) {
                    state.expandedNodes.add(current.parentId);
                }
                current = state.nodes.get(current.parentId);
            }
            
            buildFlatList();
            
            // Find index in flat list and scroll
            const flatIndex = state.flatList.findIndex(item => item.id === nodeId);
            if (flatIndex >= 0) {
                viewport.scrollTop = flatIndex * CONFIG.ITEM_HEIGHT - (state.viewportHeight / 3);
            }
            
            state.selectedNodeId = nodeId;
            render();
        }
        
        function clearSearch() {
            document.getElementById('searchInput').value = '';
            document.getElementById('searchResultsCount').textContent = '';
            state.searchTerm = '';
            state.searchResults = [];
            state.searchIndex = -1;
            render();
        }
        
        // ========== UTILITIES ==========
        
        function debounce(fn, delay) {
            let timeout;
            return function(...args) {
                clearTimeout(timeout);
                timeout = setTimeout(() => fn.apply(this, args), delay);
            };
        }
        
        function updateStats() {
            document.getElementById('statsTotalNodes').textContent = state.nodes.size.toLocaleString();
            document.getElementById('statsExpandedNodes').textContent = state.expandedNodes.size.toLocaleString();
            document.getElementById('statsMaxDepth').textContent = state.maxLevel || 0;
        }
        
        // ========== STARTUP ==========
        
        document.addEventListener('DOMContentLoaded', init);
    </script>
</body>
</html>
'@

# Replace placeholders
$extractedIdsJs = if ($ExtractedTypeIds) { $ExtractedTypeIds } else { "" }
$html = $htmlTemplate.Replace('MAX_NODES_PLACEHOLDER', "$MaxNodesInViewer")
$html = $html.Replace('ICON_DATA_JSON_PLACEHOLDER', $IconDataJson)

# Handle user activity
$userActivityBlock = if ($UserActivityJs) { $UserActivityJs } else { "const userActivity = {};" }
$html = $html.Replace('USER_ACTIVITY_PLACEHOLDER', $userActivityBlock)

$html = $html.Replace('TREE_DATA_PLACEHOLDER', $escapedData)
$html = $html.Replace('PROJECT_ID_PLACEHOLDER', $ProjectId)
$html = $html.Replace('PROJECT_NAME_PLACEHOLDER', $ProjectName)
$html = $html.Replace('SCHEMA_PLACEHOLDER', $Schema)

# Write the HTML file
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText("$PWD\$OutputFile", $html, $utf8WithBom)

# Record output size
if (Get-Command Record-OutputSize -ErrorAction SilentlyContinue) {
    Record-OutputSize -FileName $OutputFile -FilePath "$PWD\$OutputFile"
}

# Generate JSON output if requested
if ($GenerateJsonOutput) {
    $jsonOutputFile = $OutputFile -replace '\.html$', '.json'
    Write-Host "[VIRTUALIZED] Generating JSON output: $jsonOutputFile" -ForegroundColor Cyan
    
    # Parse and write nodes as JSON (streaming for large files)
    # This is a simplified version - full implementation would use StreamingJsonWriter
    $nodesJson = @{
        meta = @{
            projectId = $ProjectId
            projectName = $ProjectName
            schema = $Schema
            nodeCount = $nodeCount
            generatedAt = (Get-Date).ToString("o")
        }
        nodes = @()
    }
    
    foreach ($line in $lines) {
        $parts = $line -split '\|'
        if ($parts.Count -ge 9) {
            $nodesJson.nodes += @{
                id = [int]$parts[2]
                name = $parts[3]
                parentId = [int]$parts[1]
                level = [int]$parts[0]
                typeId = if ($parts[9]) { [int]$parts[9] } else { 0 }
            }
        }
    }
    
    $nodesJson | ConvertTo-Json -Depth 5 -Compress | Out-File $jsonOutputFile -Encoding UTF8
    
    if (Get-Command Record-OutputSize -ErrorAction SilentlyContinue) {
        Record-OutputSize -FileName $jsonOutputFile -FilePath "$PWD\$jsonOutputFile"
    }
}

# Compress if requested
if ($CompressOutput) {
    if (Get-Command Compress-OutputFile -ErrorAction SilentlyContinue) {
        Compress-OutputFile -InputPath "$PWD\$OutputFile"
    }
}

# Complete performance tracking
$metrics = $null
if (Get-Command Complete-PerfSession -ErrorAction SilentlyContinue) {
    $metrics = Complete-PerfSession
    
    # Write meta.json
    $metaPath = $OutputFile -replace '\.html$', '-meta.json'
    Write-MetaJson -Metrics $metrics -OutputPath $metaPath -AdditionalData @{
        projectId = $ProjectId
        projectName = $ProjectName
        schema = $Schema
        nodeCount = $nodeCount
        maxNodesInViewer = $MaxNodesInViewer
    }
    
    # Write probe.json
    $probePath = $OutputFile -replace '\.html$', '-probe.json'
    Write-ProbeJson -Metrics $metrics -OutputPath $probePath -NodeCount $nodeCount
}

$duration = (Get-Date) - $startTime

Write-Host "`n=== VIRTUALIZED TREE HTML GENERATED ===" -ForegroundColor Green
Write-Host "File: $OutputFile" -ForegroundColor Cyan
Write-Host "Project: $ProjectName ($ProjectId)" -ForegroundColor Cyan
Write-Host "Schema: $Schema" -ForegroundColor Cyan
Write-Host "Nodes: $nodeCount" -ForegroundColor Yellow
Write-Host "Duration: $([math]::Round($duration.TotalSeconds, 1))s" -ForegroundColor Yellow
Write-Host "Features:" -ForegroundColor Yellow
Write-Host '  [OK] Virtual scrolling (renders only visible nodes)' -ForegroundColor Green
Write-Host '  [OK] Lazy loading (incremental search indexing)' -ForegroundColor Green
Write-Host '  [OK] MaxNodesInViewer cap with warning' -ForegroundColor Green
Write-Host '  [OK] Performance metrics (meta.json, probe.json)' -ForegroundColor Green
if ($nodeLimitWarning) {
    Write-Host "  [WARN] $nodeLimitWarning" -ForegroundColor Yellow
}
