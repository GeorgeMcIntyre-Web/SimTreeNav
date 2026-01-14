# Generate full navigation tree HTML with SEQ_NUMBER ordering
param(
    [string]$DataFile = "tree-data-full-clean.txt",
    [string]$ProjectName = "",
    [string]$ProjectId = "",
    [string]$Schema = "",
    [string]$OutputFile = "navigation-tree-full.html",
    [string]$ExtractedTypeIds = "",  # Comma-separated list of TYPE_IDs that have extracted icons
    [string]$IconDataJson = "{}",    # JSON object mapping TYPE_ID to Base64 data URI
    [string]$UserActivityJs = ""      # JavaScript object with user activity data
)

# Read data file - it should already be UTF-8 with BOM
# Read as bytes first to preserve encoding
$bytes = [System.IO.File]::ReadAllBytes("$PWD\$DataFile")

# Check for UTF-8 BOM (EF BB BF)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    # Skip BOM and read as UTF-8
    $data = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
} else {
    # No BOM, try reading as UTF-8
    $data = [System.Text.Encoding]::UTF8.GetString($bytes)
}
$data = $data.Trim()

# Escape the data for JavaScript template literal
# Need to escape backticks, backslashes, and $ signs for template literals
# But preserve all Unicode characters
# IMPORTANT: Convert line endings to actual newlines (\n) that JavaScript will interpret
# First escape backslashes, then escape other special chars, then normalize line endings
$escapedData = $data -replace '\\', '\\\\' -replace '`', '\`' -replace '\$', '\$' -replace "`"", '\"'
# Normalize all line endings to \n (JavaScript will interpret this as newline in template literal)
$escapedData = $escapedData -replace "`r`n", "`n" -replace "`r", "`n"

# Read the HTML template (using single quotes to prevent variable expansion, we'll replace placeholders)
$htmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PROJECT_NAME_PLACEHOLDER Navigation Tree - Full - SCHEMA_PLACEHOLDER</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
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
        }
        
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        
        .subtitle {
            color: #666;
            margin-bottom: 20px;
            font-size: 14px;
        }
        
        .controls {
            margin-bottom: 20px;
            padding: 15px;
            background: #f5f5f5;
            border-radius: 5px;
        }
        
        .controls button {
            background: #667eea;
            color: white;
            border: none;
            padding: 8px 16px;
            margin-right: 10px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
        }
        
        .controls button:hover {
            background: #5568d3;
        }
        
        .search-box {
            margin-top: 10px;
        }
        
        .search-box input {
            width: 300px;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
        }
        
        .tree {
            font-size: 13px;
            line-height: 1.5;
            max-height: 80vh;
            overflow-y: auto;
        }
        
        .tree-node {
            margin: 1px 0;
        }
        
        .tree-node-content {
            display: flex;
            align-items: center;
            padding: 4px 6px;
            cursor: pointer;
            border-radius: 3px;
            transition: background 0.2s;
        }
        
        .tree-node-content:hover {
            background: #f0f0f0;
        }
        
        .tree-node-content.selected {
            background: #e3f2fd;
            border-left: 3px solid #667eea;
        }
        
        .tree-toggle {
            width: 18px;
            height: 18px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            margin-right: 4px;
            cursor: pointer;
            user-select: none;
            font-weight: bold;
            color: #667eea;
            flex-shrink: 0;
        }
        
        .tree-toggle::before {
            content: '\25B6';
            font-size: 10px;
            transition: transform 0.2s;
            display: inline-block;
        }
        
        .tree-node.expanded > .tree-node-content > .tree-toggle::before {
            content: '\25BC';
            transform: none;
        }
        
        .tree-node.leaf > .tree-node-content > .tree-toggle {
            visibility: hidden;
        }
        
        .tree-icon {
            width: 16px;
            height: 16px;
            margin-right: 6px;
            flex-shrink: 0;
            display: inline-block;
            vertical-align: middle;
        }
        
        .tree-label {
            flex: 1;
            color: #333;
            font-weight: 500;
        }
        
        .tree-id {
            color: #999;
            font-size: 11px;
            margin-left: 8px;
            font-family: 'Courier New', monospace;
        }
        
        .tree-children {
            margin-left: 20px;
            border-left: 2px solid #e0e0e0;
            padding-left: 8px;
            display: none;
        }
        
        .tree-node.expanded > .tree-children {
            display: block;
        }
        
        .level-0 > .tree-node-content {
            font-weight: bold;
            font-size: 16px;
            color: #667eea;
            background: #f5f5f5;
        }
        
        .level-1 > .tree-node-content {
            font-weight: 600;
        }
        
        .stats {
            margin-top: 20px;
            padding: 15px;
            background: #f9f9f9;
            border-radius: 5px;
            font-size: 14px;
            color: #666;
        }
        
        .highlight {
            background: yellow !important;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>&#127795; PROJECT_NAME_PLACEHOLDER Navigation Tree - Full</h1>
        <div class="subtitle">SCHEMA_PLACEHOLDER Schema | Project ID: PROJECT_ID_PLACEHOLDER | Complete Tree with Siemens App Ordering</div>
        
        <div class="controls">
            <button onclick="expandAll()">Expand All</button>
            <button onclick="collapseAll()">Collapse All</button>
            <button onclick="expandToLevel(1)">Expand Root + Level 1</button>
            <button onclick="expandToLevel(2)">Expand to Level 2</button>
            <div class="search-box">
                <input type="text" id="searchInput" placeholder="Search nodes..." onkeyup="searchTree(this.value)">
            </div>
        </div>
        
        <div id="treeContainer" class="tree"></div>
        
        <div class="stats" id="stats"></div>
    </div>

    <script>
        // List of TYPE_IDs that have extracted icon files (from icon extraction)
        const extractedTypeIds = new Set([EXTRACTED_TYPE_IDS_PLACEHOLDER]);

        // Icon data map: TYPE_ID -> Base64 data URI (embedded in memory, no file I/O)
        const iconDataMap = ICON_DATA_JSON_PLACEHOLDER;

        // Debug: Check if TYPE_ID 64 is in the map
        console.log('[ICON MAP DEBUG] iconDataMap keys:', Object.keys(iconDataMap).sort((a, b) => parseInt(a) - parseInt(b)).join(', '));
        if (iconDataMap['64']) {
            console.log('[ICON MAP DEBUG] TYPE_ID 64 IS in iconDataMap (length:', iconDataMap['64'].length, 'chars)');
        } else {
            console.error('[ICON MAP DEBUG] TYPE_ID 64 NOT in iconDataMap!');
        }

        // Parse the tree data from the file
        const rawData = `TREE_DATA_PLACEHOLDER`;
        
        // Icon mapping function - maps class names to icon files
        // Uses NICE_NAME from database when available (more reliable)
        // Defined OUTSIDE buildTree so it can be used by verifyIconMappings
        function getIconForClass(className, caption, niceName) {
                if (!className) className = 'class PmNode';
                
                // PREFER NICE_NAME from database if available (it's more readable)
                if (niceName && niceName !== 'Unknown' && niceName !== '') {
                    const niceNameMap = {
                        'Project': 'LogProject.bmp',
                        'Collection': 'filter_library.bmp',
                        'PartLibrary': 'AssemblyPart.bmp',
                        'MfgLibrary': 'filter_library.bmp',
                        'ResourceLibrary': 'filter_library.bmp',
                        'StudyFolder': 'filter_library.bmp',
                        'VariantFilterLibrary': 'filter_library.bmp',
                        'VariantSetLibrary': 'set_library.bmp',
                        'RobcadResourceLibrary': 'filter_library.bmp',
                        'Alternative': 'Alternative.bmp'
                    };
                    if (niceNameMap[niceName]) {
                        return niceNameMap[niceName];
                    }
                }
                
                // Fallback to className parsing if NICE_NAME not available
                // Remove "class " prefix if present
                let cleanClass = className.replace(/^class\s+/, '');
                
                // IMPORTANT: Check non-Pm classes FIRST (like RobcadResourceLibrary)
                // before checking Pm* classes to ensure correct mapping
                if (cleanClass === 'RobcadResourceLibrary') {
                    return 'filter_library.bmp';  // Resource library icon
                }
                if (cleanClass === 'Alternative') {
                    return 'Alternative.bmp';
                }
                
                // Direct class name mappings
                const iconMap = {
                    'AssemblyPlaceholder': 'AssemblyPlaceholder.bmp',
                    'IntermediateAssembly': 'IntermediateAssembly.bmp',
                    'ProcessAssembly': 'ProcessAssembly.bmp',
                    'Plant': 'Plant.bmp',
                    'Zone': 'Zone.bmp',
                    'Line': 'Line.bmp',
                    'Station': 'Station.bmp',
                    'Cell': 'Cell.bmp',
                    'PrPlant': 'PrPlant.bmp',
                    'PrZone': 'PrZone.bmp',
                    'PrLine': 'PrLine.bmp',
                    'PrStation': 'PrStation.bmp',
                    'PrPlantProcess': 'PrPlantProcess.bmp',
                    'PrZoneProcess': 'PrZoneProcess.bmp',
                    'PrLineProcess': 'PrLineProcess.bmp',
                    'PrStationProcess': 'PrStationProcess.bmp',
                    'Clamp': 'Clamp.bmp',
                    'Container': 'Container.bmp',
                    'Conveyer': 'Conveyer.bmp',
                    'Device': 'Device.bmp',
                    'Dock_System': 'Dock_System.bmp',
                    'Fixture': 'Fixture.bmp',
                    'Flange': 'Flange.bmp',
                    'Gripper': 'Gripper.bmp',
                    'Gun': 'Gun.bmp',
                    'Human': 'Human.bmp',
                    'Robot': 'Robot.bmp',
                    'Turn_Table': 'Turn_Table.bmp',
                    'Work_Table': 'Work_Table.bmp',
                    'IntermediatePart': 'IntermediatePart.bmp',
                    'Task': 'Task.bmp',
                    'PLCProgram': 'PLCProgram.bmp',
                    'SweptVolume': 'SweptVolume.bmp',
                    'desource': 'desource.bmp',
                    'filter_library': 'filter_library.bmp',
                    'set_library': 'set_library.bmp',
                    'set_library_1': 'set_library_1.bmp',
                    'set_1': 'set_1.bmp',
                    'TaskLibrary': 'TaskLibrary.bmp',
                    'AssemblyPart': 'AssemblyPart.bmp',
                    'GenericPart': 'GenericPart.bmp'
                };
                
                // Check direct mapping
                if (iconMap[cleanClass]) {
                    return iconMap[cleanClass];
                }
                
                // Check if it's a Pm* class and try to map to base type
                if (cleanClass.match(/^Pm/)) {
                    const baseType = cleanClass.replace(/^Pm/, '');
                    const pmMap = {
                        // Projects and Collections
                        'Project': 'LogProject.bmp',  // Project root - use LogProject icon
                        'Collection': 'filter_library.bmp',  // Collections/folders
                        'StudyFolder': 'filter_library.bmp',  // Study folders
                        
                        // Libraries - differentiate by type with specific icons
                        'MfgLibrary': 'filter_library.bmp',  // Manufacturing library
                        'ResourceLibrary': 'filter_library.bmp',  // Resource library
                        'PartLibrary': 'AssemblyPart.bmp',  // Part library - use AssemblyPart icon
                        'OperationLibrary': 'TaskLibrary.bmp',  // Operation library - use TaskLibrary icon
                        'VariantFilterLibrary': 'filter_library.bmp',  // Variant filter library
                        'VariantSetLibrary': 'set_library.bmp',  // Variant set library
                        
                        // Resources
                        'CompoundResource': 'Cell.bmp',
                        'Resource': 'Device.bmp',
                        'ToolPrototype': 'Device.bmp',
                        'ProcessResource': 'PrLine.bmp',
                        
                        // Parts and Assemblies
                        'CompoundPart': 'IntermediatePart.bmp',
                        'PartPrototype': 'IntermediatePart.bmp',
                        'CompoundAssembly': 'IntermediateAssembly.bmp',
                        'Assembly': 'AssemblyPlaceholder.bmp',
                        
                        // Processes and Operations
                        'Process': 'PrLineProcess.bmp',
                        'Operation': 'Task.bmp',
                        'Study': 'Task.bmp',
                        'LocationalStudy': 'Task.bmp',
                        
                        // Default
                        'Node': 'Device.bmp'
                    };
                    if (pmMap[baseType]) {
                        return pmMap[baseType];
                    }
                }
                
                
                // Try to match caption to icon name (case-insensitive)
                if (caption) {
                    const captionClean = caption.replace(/[^a-zA-Z0-9_]/g, '');
                    // Check exact match first
                    if (iconMap[captionClean]) {
                        return iconMap[captionClean];
                    }
                    // Check case-insensitive
                    for (let key in iconMap) {
                        if (key.toLowerCase() === captionClean.toLowerCase()) {
                            return iconMap[key];
                        }
                    }
                }
                
                // Default based on caption patterns
                if (caption) {
                    const captionLower = caption.toLowerCase();
                    if (captionLower.match(/study|folder|library/)) {
                        return 'filter_library.bmp';
                    } else if (captionLower.match(/project|plant|factory/)) {
                        return 'Plant.bmp';
                    } else if (captionLower.match(/line/)) {
                        return 'Line.bmp';
                    } else if (captionLower.match(/station/)) {
                        return 'Station.bmp';
                    } else if (captionLower.match(/cell/)) {
                        return 'Cell.bmp';
                    } else if (captionLower.match(/zone/)) {
                        return 'Zone.bmp';
                    }
                }
                
                // Ultimate default
                // Log unmapped class for debugging
                if (cleanClass && cleanClass !== 'PmNode' && cleanClass !== 'Node') {
                    console.warn(`[ICON WARN] Unmapped class: "${cleanClass}" (caption: "${caption}") - using default Device.bmp`);
                }
                return 'Device.bmp';
        }
        
        // Icon mapping verification function - logs all mappings
        // Defined OUTSIDE buildTree so it can be called before building tree
        function verifyIconMappings() {
            const testClasses = [
                'class Alternative',
                'class PmCollection',
                'class PmMfgLibrary',
                'class PmPartLibrary',
                'class PmProject',
                'class PmResourceLibrary',
                'class PmStudyFolder',
                'class PmVariantFilterLibrary',
                'class PmVariantSetLibrary',
                'class RobcadResourceLibrary'
            ];
            console.log('[ICON VERIFICATION] Testing all class mappings:');
            testClasses.forEach(cls => {
                const icon = getIconForClass(cls, '', '');
                console.log(`  ${cls} -> ${icon}`);
            });
        }
        
        // Build tree structure with SEQ_NUMBER ordering
        function buildTree(data) {
            const nodes = {};
            const rootId = PROJECT_ID_PLACEHOLDER;
            const rootName = 'PROJECT_NAME_PLACEHOLDER';
            // Create root node with defaults (will be updated from data if TYPE_ID is available)
            const root = { id: rootId, name: rootName, level: 0, parent: null, children: [], externalId: '', seqNumber: 0, className: 'class PmProject', niceName: 'Project', typeId: 0, iconFile: 'LogProject.bmp' };
            nodes[rootId] = root;
            
            // First pass: create all nodes
            const nodeData = [];
            let lineIndex = 0; // Track the order from SQL query (chronological by date)
            data.forEach(line => {
                if (!line || !line.includes('|')) return;
                const parts = line.split('|');
                if (parts.length < 9) return; // Need at least 9 fields: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID

                const level = parseInt(parts[0]);
                const parentId = parseInt(parts[1]) || 0;
                const objectId = parseInt(parts[2]);
                const caption = parts[3] || parts[4] || 'Unnamed';
                const externalId = parts[5] || '';
                const seqNumber = parseInt(parts[6]) || 0;
                const className = parts[7] || 'class PmNode'; // CLASS_NAME (8th field)
                const niceName = parts[8] || ''; // NICE_NAME (9th field)
                const typeId = parts[9] ? parseInt(parts[9]) : 0; // TYPE_ID (10th field) - use to find extracted icon file!
                const sqlOrder = lineIndex++; // Preserve SQL query order (chronological by creation date)
                
                if (!nodes[objectId]) {
                    // PREFER icon from database (extracted as icon_TYPEID.bmp) if available, otherwise use NICE_NAME mapping
                    let iconFile = '';
                    // Check if we have an extracted icon file for this TYPE_ID
                    if (typeId > 0) {
                        const dbIconFile = `icon_${typeId}.bmp`;
                        // Note: We can't check file existence in JavaScript, so we'll try it and fallback on error
                        iconFile = dbIconFile;
                        if (level <= 1) {
                            console.log(`[ICON DEBUG] Node: "${caption}" | TYPE_ID: ${typeId} | Trying database icon: ${dbIconFile}`);
                        }
                    } else {
                        // Fallback to NICE_NAME mapping
                        iconFile = getIconForClass(className, caption, niceName);
                    }
                    // Debug: log all first-level nodes to console
                    if (level <= 1) {
                        console.log(`[ICON DEBUG] Node: "${caption}" | Class: "${className}" | NiceName: "${niceName}" | TYPE_ID: ${typeId} | Icon: "${iconFile}" | ID: ${objectId} | Parts length: ${parts.length}`);
                        if (parts.length < 9) {
                            console.error(`[ICON ERROR] Node "${caption}" has ${parts.length} parts, expected at least 9! Line: ${line.substring(0, 100)}`);
                        }
                    }
                    nodes[objectId] = {
                        id: objectId,
                        name: caption,
                        level: level,
                        parent: parentId,
                        children: [],
                        externalId: externalId,
                        seqNumber: seqNumber,
                        sqlOrder: sqlOrder, // Preserve SQL order (chronological by date)
                        className: className,
                        niceName: niceName,
                        typeId: typeId,  // TYPE_ID for database icon lookup
                        iconFile: iconFile  // Icon filename (from database or fallback)
                    };
                } else {
                    // Node already exists (this happens for root node which is pre-created)
                    // Update root node properties from data if this is level 0
                    if (level === 0 && objectId === rootId) {
                        nodes[objectId].typeId = typeId;
                        nodes[objectId].niceName = niceName;
                        nodes[objectId].className = className;
                        nodes[objectId].externalId = externalId;
                        // Update iconFile if we have a TYPE_ID
                        if (typeId > 0) {
                            nodes[objectId].iconFile = `icon_${typeId}.bmp`;
                            console.log(`[ICON DEBUG] Root node updated: TYPE_ID ${typeId} | Icon: icon_${typeId}.bmp`);
                        }
                    } else if (level <= 1) {
                        console.warn(`[ICON WARN] Node "${caption}" (ID: ${objectId}) already exists! Current iconFile: ${nodes[objectId].iconFile}`);
                    }
                }
                
                nodeData.push({
                    level: level,
                    parentId: parentId,
                    objectId: objectId,
                    seqNumber: seqNumber,
                    sqlOrder: sqlOrder // Preserve SQL order
                });
            });
            
            // Fix level 999 (StudyFolder children placeholder) - correct levels after all nodes created
            nodeData.forEach(item => {
                if (item.level === 999 && item.parentId > 0 && nodes[item.parentId]) {
                    const parent = nodes[item.parentId];
                    item.level = parent.level + 1;
                    if (nodes[item.objectId]) {
                        nodes[item.objectId].level = item.level;
                    }
                }
            });
            
            // Second pass: build parent-child relationships
            // IMPORTANT: Sort by sqlOrder to preserve chronological order from SQL query
            nodeData.sort((a, b) => {
                // First sort by parent ID (so we process all children of same parent together)
                if (a.parentId !== b.parentId) {
                    return a.parentId - b.parentId;
                }
                // Then sort by SQL order (chronological by creation date)
                return a.sqlOrder - b.sqlOrder;
            });
            
            // Handle bidirectional relationships by only keeping one direction
            // BUT: Allow StudyFolder children (links/shortcuts) even if they're duplicates
            const childMap = new Map(); // Track which relationships we've added
            nodeData.forEach(item => {
                const node = nodes[item.objectId];
                const parent = nodes[item.parentId];
                if (parent && node && node.id !== parent.id) {
                    const key = `${parent.id}-${node.id}`;
                    const reverseKey = `${node.id}-${parent.id}`;
                    
                    // Check if parent is a StudyFolder (links/shortcuts should always be shown)
                    // StudyFolder nodes have name "StudyFolder" (from CAPTION_S_)
                    const isStudyFolderParent = parent.name === 'StudyFolder';
                    
                    // For StudyFolder children, always add them (they're links/shortcuts)
                    // For other relationships, check for duplicates and reverse relationships
                    if (isStudyFolderParent) {
                        // StudyFolder children are links - always add them even if duplicate
                        if (!parent.children.find(c => c.id === node.id)) {
                            parent.children.push(node);
                        }
                    } else {
                        // Regular relationships: only add if we haven't added this relationship or its reverse
                        if (!childMap.has(key) && !childMap.has(reverseKey)) {
                            if (!parent.children.find(c => c.id === node.id)) {
                                parent.children.push(node);
                                childMap.set(key, true);
                            }
                        }
                    }
                }
            });
            
            // Sort children by SEQ_NUMBER, then by name (iterative to avoid stack overflow)
            function sortChildrenIterative(rootNode) {
                const stack = [rootNode];
                const visited = new Set();
                
                while (stack.length > 0) {
                    const node = stack.pop();
                    if (!node || !node.children || visited.has(node.id)) {
                        continue;
                    }
                    visited.add(node.id);
                    
                    // Sort this node's children by SQL order (chronological by creation date)
                    node.children.sort((a, b) => {
                        return a.sqlOrder - b.sqlOrder;
                    });
                    
                    // Add children to stack (in reverse order so we process them in correct order)
                    for (let i = node.children.length - 1; i >= 0; i--) {
                        if (!visited.has(node.children[i].id)) {
                            stack.push(node.children[i]);
                        }
                    }
                }
            }
            sortChildrenIterative(root);
            
            return root;
        }
        
        // Parse tree data
        // The data should now have actual newline characters after the escaping fix
        // Split by newline and filter empty/invalid lines
        const lines = rawData.split('\n').filter(line => line.trim() && line.includes('|'));
        console.log(`[DATA PARSE] Total lines: ${lines.length}`);
        if (lines.length > 0) {
            const firstLineParts = lines[0].split('|');
            console.log(`[DATA PARSE] First line has ${firstLineParts.length} parts`);
            if (firstLineParts.length >= 8) {
                console.log(`[DATA PARSE] First line class: ${firstLineParts[7]}`);
            }
        }
        
        // Verify icon mappings before building tree
        verifyIconMappings();
        
        const rootNode = buildTree(lines);
        console.log(`[BUILD TREE] Root node iconFile: ${rootNode.iconFile}`);
        if (rootNode.children && rootNode.children.length > 0) {
            console.log(`[BUILD TREE] First child: "${rootNode.children[0].name}" iconFile: ${rootNode.children[0].iconFile}`);
        }
        
        // Collect all unique class names and their icon mappings for verification
        const classIconMap = new Map();
        function collectClassIcons(node) {
            if (node.className && node.iconFile) {
                if (!classIconMap.has(node.className)) {
                    classIconMap.set(node.className, node.iconFile);
                }
            }
            if (node.children) {
                node.children.forEach(child => collectClassIcons(child));
            }
        }
        collectClassIcons(rootNode);
        console.log('[ICON SUMMARY] All class-to-icon mappings found in tree:');
        Array.from(classIconMap.entries()).sort().forEach(([cls, icon]) => {
            console.log(`  ${cls} -> ${icon}`);
        });
        
        // Render tree
        function renderTree(node, container, level = 0) {
            const nodeDiv = document.createElement('div');
            nodeDiv.className = `tree-node level-${level} ${node.children.length > 0 ? '' : 'leaf'}`;
            nodeDiv.dataset.nodeId = node.id;
            
            const content = document.createElement('div');
            content.className = 'tree-node-content';
            
            const toggle = document.createElement('span');
            toggle.className = 'tree-toggle';
            if (node.children.length > 0) {
                toggle.onclick = (e) => {
                    e.stopPropagation();
                    e.preventDefault();
                    nodeDiv.classList.toggle('expanded');
                    updateStats();
                };
            } else {
                toggle.style.display = 'none';
            }
            
            const icon = document.createElement('img');
            icon.className = 'tree-icon';
            let iconFileName = node.iconFile || 'Device.bmp';
            let iconPath = '';
            let cacheBuster = '';

            // PREFER icon from database (embedded as Base64 data URI) if TYPE_ID is available
            if (node.typeId && node.typeId > 0 && iconDataMap[node.typeId]) {
                // Use Base64 data URI directly (no file I/O, embedded in HTML)
                icon.src = iconDataMap[node.typeId];
                iconFileName = `icon_${node.typeId}.bmp`;
                if (level <= 1) {
                    console.log(`[ICON RENDER] Node: "${node.name}" | Using DATABASE icon (Base64): TYPE_ID ${node.typeId}`);
                }
                // If data URI fails (shouldn't happen), fallback to mapped icon
                icon.onerror = function() {
                    // Prevent infinite loop
                    if (this.src.startsWith('data:image/svg')) {
                        return;
                    }
                    console.warn(`[ICON WARN] Database icon data URI failed for TYPE_ID ${node.typeId}, falling back to mapped icon for node: ${node.name}`);
                    const fallbackIcon = getIconForClass(node.className, node.name, node.niceName);
                    cacheBuster = '?v=' + Date.now() + '&r=' + Math.random();
                    iconPath = `icons/${fallbackIcon}${cacheBuster}`;
                    // Add nested error handler for when fallback file also fails
                    this.onerror = function() {
                        if (this.src.startsWith('data:image/svg')) return;
                        console.warn(`[ICON WARN] Fallback icon file not found: ${fallbackIcon} - showing missing icon indicator`);
                        this.src = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'%3E%3Crect width='16' height='16' fill='%23ffcccc'/%3E%3Ctext x='8' y='12' font-size='12' text-anchor='middle' fill='%23cc0000'%3E%3F%3C/text%3E%3C/svg%3E";
                    };
                    this.src = iconPath;
                    iconFileName = fallbackIcon;
                };
            } else {
                // Use mapped icon (NICE_NAME or className mapping) from icons directory
                // Either no TYPE_ID, or TYPE_ID doesn't have embedded icon data
                cacheBuster = '?v=' + Date.now() + '&r=' + Math.random();
                iconPath = `icons/${iconFileName}${cacheBuster}`;
                icon.src = iconPath;
                if (level <= 1) {
                    const reason = !node.typeId ? "no TYPE_ID" : (!iconDataMap[node.typeId] ? "icon not in data map" : "using mapped icon");
                    console.log(`[ICON RENDER] Node: "${node.name}" | Icon Path: "${iconPath}" | IconFile: "${iconFileName}" | Reason: ${reason}`);
                }
            }
            
            icon.alt = node.name;
            icon.title = `${node.className || ''} | NiceName: ${node.niceName || ''} | Icon: ${iconFileName}`;
            icon.style.width = '16px';
            icon.style.height = '16px';
            icon.style.objectFit = 'contain';
            icon.style.display = 'inline-block';
            
            // Only add onerror if not already set (for database icons with fallback)
            if (!icon.onerror || icon.onerror.toString().indexOf('falling back to mapped icon') === -1) {
                icon.onerror = function() {
                    // Prevent infinite loop - check if already showing missing icon indicator
                    if (this.src.startsWith('data:image/svg')) {
                        return;
                    }
                    console.warn(`[ICON WARN] Icon not found: ${iconPath} for node: ${node.name} (${node.className}) - showing missing icon indicator`);
                    // Show a "missing icon" indicator (red question mark in light red box)
                    this.src = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'%3E%3Crect width='16' height='16' fill='%23ffcccc'/%3E%3Ctext x='8' y='12' font-size='12' text-anchor='middle' fill='%23cc0000'%3E%3F%3C/text%3E%3C/svg%3E";
                };
            }
            icon.onload = function() {
                // Log successful icon load for debugging
                if (level <= 1) {
                    console.log(`[ICON LOAD] Successfully loaded icon: ${iconFileName} for node: ${node.name}`);
                }
            };
            
            const label = document.createElement('span');
            label.className = 'tree-label';
            label.textContent = node.name;
            
            const idSpan = document.createElement('span');
            idSpan.className = 'tree-id';
            idSpan.textContent = `[${node.id}]`;
            
            content.appendChild(toggle);
            content.appendChild(icon);
            content.appendChild(label);
            content.appendChild(idSpan);

            // Add checkout status (green tick + username) - only show for CHECKEDOUT nodes
            if (typeof userActivity !== 'undefined' && userActivity[node.id] && userActivity[node.id].online === 'CHECKEDOUT') {
                const activity = userActivity[node.id];
                const checkoutTick = document.createElement('span');
                checkoutTick.style.cssText = 'color: #28a745; font-size: 14px; font-weight: bold; margin-left: 6px;';
                checkoutTick.innerHTML = '&#x2713;';  // Unicode checkmark
                checkoutTick.title = 'Checked out';

                const userInfo = document.createElement('span');
                userInfo.style.cssText = 'color: #007bff; font-size: 11px; font-weight: 500; margin-left: 4px;';
                userInfo.textContent = activity.user;
                userInfo.title = 'Checked out by ' + activity.user + (activity.time ? ' on ' + activity.time : '');

                content.appendChild(checkoutTick);
                content.appendChild(userInfo);
            }

            // Clicking on label, icon, or ID should toggle expansion if node has children
            if (node.children.length > 0) {
                const handleClick = (e) => {
                    e.stopPropagation();
                    nodeDiv.classList.toggle('expanded');
                    updateStats();
                    // Update selection
                    document.querySelectorAll('.tree-node-content').forEach(el => el.classList.remove('selected'));
                    content.classList.add('selected');
                };
                
                label.onclick = handleClick;
                icon.onclick = handleClick;
                idSpan.onclick = handleClick;
            }
            
            // Clicking on content area (but not toggle/label/icon) just selects
            content.onclick = (e) => {
                // Only handle if not clicking on toggle, label, icon, or idSpan
                if (e.target !== toggle && e.target !== label && e.target !== icon && e.target !== idSpan) {
                    document.querySelectorAll('.tree-node-content').forEach(el => el.classList.remove('selected'));
                    content.classList.add('selected');
                }
            };
            
            nodeDiv.appendChild(content);
            
            if (node.children.length > 0) {
                const childrenDiv = document.createElement('div');
                childrenDiv.className = 'tree-children';
                
                node.children.forEach(child => {
                    renderTree(child, childrenDiv, level + 1);
                });
                
                nodeDiv.appendChild(childrenDiv);
                
                // Auto-expand root and level 1 (matching Siemens app)
                if (level < 1) {
                    nodeDiv.classList.add('expanded');
                }
            }
            
            container.appendChild(nodeDiv);
        }
        
        // Initialize tree
        const container = document.getElementById('treeContainer');
        renderTree(rootNode, container);
        
        // Update stats
        function updateStats() {
            const totalNodes = document.querySelectorAll('.tree-node').length;
            const expandedNodes = document.querySelectorAll('.tree-node.expanded').length;
            const maxLevel = Math.max(...Array.from(document.querySelectorAll('.tree-node')).map(n => {
                const match = n.className.match(/level-(\d+)/);
                return match ? parseInt(match[1]) : 0;
            }));
            document.getElementById('stats').textContent = 
                `Total Nodes: ${totalNodes.toLocaleString()} | Expanded: ${expandedNodes.toLocaleString()} | Max Depth: ${maxLevel} levels`;
        }
        updateStats();
        
        // Control functions
        function expandAll() {
            document.querySelectorAll('.tree-node').forEach(node => {
                if (node.querySelector('.tree-children')) {
                    node.classList.add('expanded');
                }
            });
            updateStats();
        }
        
        function collapseAll() {
            document.querySelectorAll('.tree-node').forEach(node => {
                node.classList.remove('expanded');
            });
            updateStats();
        }
        
        function expandToLevel(maxLevel) {
            document.querySelectorAll('.tree-node').forEach(node => {
                const level = parseInt(node.className.match(/level-(\d+)/)?.[1] || '0');
                if (level < maxLevel && node.querySelector('.tree-children')) {
                    node.classList.add('expanded');
                } else {
                    node.classList.remove('expanded');
                }
            });
            updateStats();
        }
        
        function searchTree(query) {
            const searchTerm = query.toLowerCase();
            document.querySelectorAll('.tree-label').forEach(label => {
                const nodeContent = label.closest('.tree-node-content');
                if (searchTerm === '' || label.textContent.toLowerCase().includes(searchTerm)) {
                    nodeContent.classList.remove('highlight');
                    if (searchTerm !== '') {
                        nodeContent.classList.add('highlight');
                        // Expand parents to show result
                        let parent = label.closest('.tree-node').parentElement;
                        while (parent && parent.classList.contains('tree-children')) {
                            parent.previousElementSibling?.classList.add('expanded');
                            parent = parent.parentElement?.parentElement;
                        }
                    }
                } else {
                    nodeContent.classList.remove('highlight');
                }
            });
        }
    </script>
</body>
</html>
'@

# Replace placeholders with actual data
# Use .NET string Replace() method to preserve Unicode encoding
# Replace extracted TYPE_IDs placeholder
$extractedIdsJs = if ($ExtractedTypeIds) { $ExtractedTypeIds } else { "" }
$html = $htmlTemplate.Replace('EXTRACTED_TYPE_IDS_PLACEHOLDER', $extractedIdsJs)
$html = $html.Replace('ICON_DATA_JSON_PLACEHOLDER', $IconDataJson)

# Inject user activity data before tree data
if ($UserActivityJs) {
    $dataWithActivity = "$UserActivityJs`n`nconst rawData = ``TREE_DATA_PLACEHOLDER``;"
    $html = $html.Replace('const rawData = `TREE_DATA_PLACEHOLDER`;', $dataWithActivity)
}

$html = $html.Replace('TREE_DATA_PLACEHOLDER', $escapedData)
$html = $html.Replace('PROJECT_ID_PLACEHOLDER', $ProjectId)
$html = $html.Replace('PROJECT_NAME_PLACEHOLDER', $ProjectName)
$html = $html.Replace('SCHEMA_PLACEHOLDER', $Schema)

# Write the HTML file with UTF-8 BOM to ensure proper browser interpretation
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText("$PWD\$OutputFile", $html, $utf8WithBom)

Write-Host "`n=== FULL NAVIGATION TREE HTML GENERATED ===" -ForegroundColor Green
Write-Host "File: $OutputFile" -ForegroundColor Cyan
Write-Host "Project: $ProjectName ($ProjectId)" -ForegroundColor Cyan
Write-Host "Schema: $Schema" -ForegroundColor Cyan
$nodeCount = (Get-Content $DataFile | Measure-Object -Line).Lines
Write-Host "Nodes: ~$nodeCount" -ForegroundColor Yellow
Write-Host "Features:" -ForegroundColor Yellow
Write-Host '  [OK] Complete tree (all levels)' -ForegroundColor Green
Write-Host '  [OK] Siemens app ordering (SEQ_NUMBER)' -ForegroundColor Green
Write-Host '  [OK] Root + Level 1 auto-expanded' -ForegroundColor Green
Write-Host '  [OK] Search functionality' -ForegroundColor Green
