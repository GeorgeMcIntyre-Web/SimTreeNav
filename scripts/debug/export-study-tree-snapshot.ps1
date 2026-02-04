# Export Study Tree Snapshot
# Purpose: Deterministic snapshot of study tree structure, naming, and locations
# Date: 2026-01-30
# Updated: 2026-02-04 - Expanded shortcut target resolution
#
# Shortcut Target Resolution (v1.2.0):
#   SHORTCUT_.LINKEXTERNALID_S_ can point to multiple target systems:
#   1. RESOURCE_        - via RESOURCE_.EXTERNALID_S_ (robots, fixtures, tools)
#   2. ROBOTICPROGRAM_  - via ROBOTICPROGRAM_.EXTERNALID_S_ (robot programs)
#   3. PROXY            - via PROXY.EXTERNAL_ID (PP-DESIGN* references, TxProcessAssembly)
#                         Caption resolved via DESIGN12.COLLECTION_ on PROXY.OBJECT_ID
#                         (no cross-schema dependency)
#   4. UNKNOWN          - LINKEXTERNALID_S_ present but no match in known tables
#   5. LOCAL            - no LINKEXTERNALID_S_ (local shortcut)
#
# Resolution order: RESOURCE_ > ROBOTICPROGRAM_ > PROXY > UNKNOWN

param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ProjectId,

    [Parameter(Mandatory=$true)]
    [int]$StudyId,

    [string]$OutputDir = "data/output",
    [switch]$IncludeCSV
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Study Tree Snapshot Export" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TNS:        $TNSName" -ForegroundColor Gray
Write-Host "  Schema:     $Schema" -ForegroundColor Gray
Write-Host "  Project ID: $ProjectId" -ForegroundColor Gray
Write-Host "  Study ID:   $StudyId" -ForegroundColor Gray
Write-Host ""

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "..\..\src\powershell\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
} else {
    Write-Error "Credential manager not found at: $credManagerPath"
    exit 1
}

# Validate sqlplus exists
if (-not (Get-Command sqlplus -ErrorAction SilentlyContinue)) {
    Write-Error "sqlplus not found in PATH. Please install Oracle Client."
    exit 1
}

# Create output directory
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Generate timestamp for unique snapshot file
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$baseFileName = "study-tree-snapshot-$Schema-$StudyId-$timestamp"
$jsonFile = Join-Path $OutputDir "$baseFileName.json"
$csvFile = Join-Path $OutputDir "$baseFileName.csv"

# Helper function to execute SQL query
function Invoke-SqlLines {
    param([string]$SqlText)
    $tempFile = Join-Path $env:TEMP "tree-snapshot-$(Get-Random).sql"
    $SqlText | Out-File $tempFile -Encoding ASCII
    try {
        $connStr = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
        $result = & sqlplus -S $connStr "@$tempFile" 2>&1
        Remove-Item $tempFile -ErrorAction SilentlyContinue

        # Validate connection
        if ($result -match "ORA-\d+") {
            Write-Error "Database error: $($result -join "`n")"
            return $null
        }

        return $result
    } catch {
        Write-Error "Failed to execute query: $_"
        Remove-Item $tempFile -ErrorAction SilentlyContinue
        return $null
    }
}

Write-Host "[1/6] Querying study metadata..." -ForegroundColor Yellow

# Get study metadata
$sqlStudyMeta = @"
SET PAGESIZE 2000
SET LINESIZE 400
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    'META|' || rs.OBJECT_ID || '|' || rs.NAME_S_ || '|' ||
    NVL(cd.NICE_NAME, '') || '|' ||
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') || '|' ||
    NVL(rs.LASTMODIFIEDBY_S_, '') || '|' ||
    NVL(rs.EXTERNALID_S_, '')
FROM $Schema.ROBCADSTUDY_ rs
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
WHERE rs.OBJECT_ID = $StudyId;

EXIT;
"@

$metaRows = Invoke-SqlLines -SqlText $sqlStudyMeta
if (-not $metaRows) {
    Write-Error "Failed to retrieve study metadata"
    exit 1
}

$metaData = $null
foreach ($row in $metaRows) {
    if ($row -match '^META\|') {
        $parts = $row -split '\|'
        $metaData = @{
            studyId = $parts[1].Trim()
            studyName = $parts[2].Trim()
            studyType = $parts[3].Trim()
            lastModified = $parts[4].Trim()
            modifiedBy = $parts[5].Trim()
            externalId = $parts[6].Trim()
        }
        break
    }
}

if (-not $metaData) {
    Write-Error "Study not found: $StudyId"
    exit 1
}

Write-Host "  Study: $($metaData.studyName) ($($metaData.studyType))" -ForegroundColor Green
Write-Host "  Last Modified: $($metaData.lastModified) by $($metaData.modifiedBy)" -ForegroundColor Gray

Write-Host "`n[2/6] Querying tree structure (nodes under study)..." -ForegroundColor Yellow

# Get all nodes under the study with parent relationships
# This uses REL_COMMON hierarchical traversal (project-scoped pattern)
$sqlTreeStructure = @"
SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

-- Get tree nodes under study with parent relationships
-- Format: NODE|object_id|parent_id|depth|seq_number|class_id|class_name|nice_name|is_shortcut|external_id|modified_date
SELECT
    'NODE|' || c.OBJECT_ID || '|' ||
    NVL(TO_CHAR(r.FORWARD_OBJECT_ID), '0') || '|' ||
    TO_CHAR(LEVEL) || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(TO_CHAR(c.CLASS_ID), '') || '|' ||
    NVL(cd.NAME, '') || '|' ||
    NVL(cd.NICE_NAME, '') || '|' ||
    'false' || '|' ||
    NVL(c.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(c.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS')
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
START WITH r.FORWARD_OBJECT_ID = $StudyId
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
UNION ALL
-- Get shortcuts under study (resources, operations, etc.)
-- Format: NODE|object_id|parent_id|depth|seq_number|class_id|class_name|nice_name|is_shortcut|external_id|modified_date
SELECT
    'NODE|' || s.OBJECT_ID || '|' ||
    TO_CHAR(r.FORWARD_OBJECT_ID) || '|' ||
    '1' || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(TO_CHAR(s.CLASS_ID), '') || '|' ||
    NVL(cd.NAME, '') || '|' ||
    NVL(cd.NICE_NAME, '') || '|' ||
    'true' || '|' ||
    NVL(s.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(s.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS')
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON s.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = $StudyId
ORDER BY 1;

EXIT;
"@

$treeRows = Invoke-SqlLines -SqlText $sqlTreeStructure
if (-not $treeRows) {
    Write-Error "Failed to retrieve tree structure"
    exit 1
}

$nodes = @()
foreach ($row in $treeRows) {
    if ($row -match '^NODE\|') {
        $parts = $row -split '\|'
        $nodes += @{
            node_id = $parts[1].Trim()
            parent_node_id = $parts[2].Trim()
            depth = [int]$parts[3].Trim()
            seq_number = $parts[4].Trim()
            class_id = $parts[5].Trim()
            class_name = $parts[6].Trim()
            nice_name = $parts[7].Trim()
            is_shortcut = $parts[8].Trim() -eq 'true'
            external_id = $parts[9].Trim()
            modified_date = $parts[10].Trim()
            # Placeholders for data added in later queries
            display_name = $null
            resource_id = $null
            resource_name = $null
            resource_type = $null
            layout_id = $null
            x = $null
            y = $null
            z = $null
            name_provenance = $null
            coord_provenance = $null
            mapping_type = "none"
            # New fields for expanded shortcut target resolution
            link_external_id = $null
            resolved_type = $null
            resolved_object_id = $null
            resolved_caption = $null
            robotic_program = $null  # Object: {object_id, class_id, caption, name, external_id}
            proxy = $null            # Object: {object_id, class_id, external_id, project_id, context_name, collection_caption}
        }
    }
}

Write-Host "  Found $($nodes.Count) raw node entries" -ForegroundColor Gray

# Deduplicate nodes by node_id (versioned tables return multiple rows per OBJECT_ID)
$seen = @{}
$uniqueNodes = @()
foreach ($node in $nodes) {
    if (-not $seen.ContainsKey($node.node_id)) {
        $seen[$node.node_id] = $true
        $uniqueNodes += $node
    }
}
$nodes = $uniqueNodes
Write-Host "  Unique nodes: $($nodes.Count)" -ForegroundColor Green

Write-Host "`n[3/6] Resolving node names..." -ForegroundColor Yellow

# Resolve names for all nodes (initial pass)
# Final precedence after resource mapping: Resource name > Shortcut name > Collection caption > External ID > Object ID
$nameQueries = @()
$shortcutNodeIds = ($nodes | Where-Object { $_.is_shortcut } | ForEach-Object { $_.node_id }) -join ','

if ($shortcutNodeIds) {
    $sqlShortcutNames = @"
SET PAGESIZE 50000
SET LINESIZE 400
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    'NAME|' || s.OBJECT_ID || '|' ||
    NVL(s.NAME_S_, '') || '|' ||
    'SHORTCUT_.NAME_S_'
FROM $Schema.SHORTCUT_ s
WHERE s.OBJECT_ID IN ($shortcutNodeIds)
  AND s.OBJECT_VERSION_ID = (SELECT MAX(s2.OBJECT_VERSION_ID) FROM $Schema.SHORTCUT_ s2 WHERE s2.OBJECT_ID = s.OBJECT_ID);

EXIT;
"@
    $nameQueries += Invoke-SqlLines -SqlText $sqlShortcutNames
}

$collectionNodeIds = ($nodes | Where-Object { -not $_.is_shortcut } | ForEach-Object { $_.node_id }) -join ','

if ($collectionNodeIds) {
    $sqlCollectionNames = @"
SET PAGESIZE 50000
SET LINESIZE 400
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    'NAME|' || c.OBJECT_ID || '|' ||
    NVL(c.CAPTION_S_, '') || '|' ||
    'COLLECTION_.CAPTION_S_'
FROM $Schema.COLLECTION_ c
WHERE c.OBJECT_ID IN ($collectionNodeIds)
  AND c.OBJECT_VERSION_ID = (SELECT MAX(c2.OBJECT_VERSION_ID) FROM $Schema.COLLECTION_ c2 WHERE c2.OBJECT_ID = c.OBJECT_ID);

EXIT;
"@
    $nameQueries += Invoke-SqlLines -SqlText $sqlCollectionNames
}

# Parse name results
$nameMap = @{}
foreach ($row in $nameQueries) {
    if ($row -match '^NAME\|') {
        $parts = $row -split '\|'
        $nodeId = $parts[1].Trim()
        $nameValue = $parts[2].Trim()
        $provenance = $parts[3].Trim()

        if ($nameValue) {
            $nameMap[$nodeId] = @{
                name = $nameValue
                provenance = $provenance
            }
        }
    }
}

# Apply names to nodes
foreach ($node in $nodes) {
    if ($nameMap.ContainsKey($node.node_id)) {
        $node.display_name = $nameMap[$node.node_id].name
        $node.name_provenance = $nameMap[$node.node_id].provenance
    } elseif ($node.external_id) {
        $node.display_name = $node.external_id
        $node.name_provenance = "EXTERNALID_S_"
    } else {
        $node.display_name = $node.node_id
        $node.name_provenance = "OBJECT_ID (fallback)"
    }
}

Write-Host "  Resolved names for $($nodes.Count) nodes" -ForegroundColor Green

Write-Host "`n[4/6] Resolving shortcut targets (RESOURCE_, ROBOTICPROGRAM_, PROXY)..." -ForegroundColor Yellow

# Resolve targets for shortcuts - expanded to check RESOURCE_, ROBOTICPROGRAM_, PROXY
# Resolution order: RESOURCE_ > ROBOTICPROGRAM_ > PROXY > UNKNOWN
# PROXY caption resolved via DESIGN12.COLLECTION_ on PROXY.OBJECT_ID; no cross-schema dependency
if ($shortcutNodeIds) {
    $sqlTargets = @"
SET PAGESIZE 50000
SET LINESIZE 800
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    'TGT|' ||
    s.OBJECT_ID || '|' ||
    NVL(s.CAPTION_S_, '') || '|' ||
    NVL(s.NAME_S_, '') || '|' ||
    NVL(s.LINKEXTERNALID_S_, '') || '|' ||
    NVL(TO_CHAR(res.OBJECT_ID), '') || '|' ||
    NVL(TO_CHAR(res.CLASS_ID), '') || '|' ||
    NVL(res.NAME_S_, '') || '|' ||
    NVL(cd_res.NICE_NAME, '') || '|' ||
    NVL(TO_CHAR(rp.OBJECT_ID), '') || '|' ||
    NVL(TO_CHAR(rp.CLASS_ID), '') || '|' ||
    NVL(rp.CAPTION_S_, '') || '|' ||
    NVL(rp.NAME_S_, '') || '|' ||
    NVL(rp.EXTERNALID_S_, '') || '|' ||
    NVL(TO_CHAR(p.OBJECT_ID), '') || '|' ||
    NVL(TO_CHAR(p.CLASS_ID), '') || '|' ||
    NVL(p.EXTERNAL_ID, '') || '|' ||
    NVL(TO_CHAR(p.PROJECT_ID), '') || '|' ||
    NVL(p.CONTEXT_NAME, '') || '|' ||
    NVL(pc.CAPTION_S_, '')
FROM $Schema.SHORTCUT_ s
LEFT JOIN $Schema.RESOURCE_ res
    ON s.LINKEXTERNALID_S_ IS NOT NULL
   AND res.EXTERNALID_S_ = s.LINKEXTERNALID_S_
   AND res.OBJECT_VERSION_ID = (SELECT MAX(r2.OBJECT_VERSION_ID) FROM $Schema.RESOURCE_ r2 WHERE r2.OBJECT_ID = res.OBJECT_ID)
LEFT JOIN $Schema.CLASS_DEFINITIONS cd_res ON res.CLASS_ID = cd_res.TYPE_ID
LEFT JOIN $Schema.ROBOTICPROGRAM_ rp
    ON s.LINKEXTERNALID_S_ IS NOT NULL
   AND rp.EXTERNALID_S_ = s.LINKEXTERNALID_S_
   AND rp.OBJECT_VERSION_ID = (SELECT MAX(rp2.OBJECT_VERSION_ID) FROM $Schema.ROBOTICPROGRAM_ rp2 WHERE rp2.OBJECT_ID = rp.OBJECT_ID)
LEFT JOIN $Schema.PROXY p
    ON s.LINKEXTERNALID_S_ IS NOT NULL
   AND p.EXTERNAL_ID = s.LINKEXTERNALID_S_
LEFT JOIN $Schema.COLLECTION_ pc
    ON p.OBJECT_ID IS NOT NULL
   AND pc.OBJECT_ID = p.OBJECT_ID
   AND pc.OBJECT_VERSION_ID = (SELECT MAX(pc2.OBJECT_VERSION_ID) FROM $Schema.COLLECTION_ pc2 WHERE pc2.OBJECT_ID = pc.OBJECT_ID)
WHERE s.OBJECT_ID IN ($shortcutNodeIds)
  AND s.OBJECT_VERSION_ID = (SELECT MAX(s2.OBJECT_VERSION_ID) FROM $Schema.SHORTCUT_ s2 WHERE s2.OBJECT_ID = s.OBJECT_ID);

EXIT;
"@

    $targetRows = Invoke-SqlLines -SqlText $sqlTargets
    $resourceCount = 0
    $roboticProgramCount = 0
    $proxyCount = 0
    $unknownCount = 0

    foreach ($row in $targetRows) {
        if ($row -match '^TGT\|') {
            $parts = $row -split '\|'
            $shortcutId = $parts[1].Trim()
            $shortcutCaption = $parts[2].Trim()
            $shortcutName = $parts[3].Trim()
            $linkExtId = $parts[4].Trim()
            # RESOURCE_ fields
            $resOid = $parts[5].Trim()
            $resClassId = $parts[6].Trim()
            $resName = $parts[7].Trim()
            $resType = $parts[8].Trim()
            # ROBOTICPROGRAM_ fields
            $rpOid = $parts[9].Trim()
            $rpClassId = $parts[10].Trim()
            $rpCaption = $parts[11].Trim()
            $rpName = $parts[12].Trim()
            $rpExtId = $parts[13].Trim()
            # PROXY fields
            $pxOid = $parts[14].Trim()
            $pxClassId = $parts[15].Trim()
            $pxExtId = $parts[16].Trim()
            $pxProjId = $parts[17].Trim()
            $pxCtx = $parts[18].Trim()
            $pxCap = $parts[19].Trim()

            $node = $nodes | Where-Object { $_.node_id -eq $shortcutId } | Select-Object -First 1
            if ($node) {
                # Store the link external ID on all shortcuts
                $node.link_external_id = $linkExtId

                # Determine resolved target type (priority: RESOURCE_ > ROBOTICPROGRAM_ > PROXY > UNKNOWN)
                if ($resOid) {
                    # RESOURCE_ match
                    $node.resolved_type = "RESOURCE_"
                    $node.resolved_object_id = $resOid
                    $node.resolved_caption = if ($resName) { $resName } else { $shortcutCaption }
                    $node.resource_id = $resOid
                    $node.resource_name = $resName
                    $node.resource_type = $resType
                    $node.mapping_type = "deterministic"
                    $node.display_name = $resName
                    $node.name_provenance = "RESOURCE_.NAME_S_"
                    $resourceCount++
                }
                elseif ($rpOid) {
                    # ROBOTICPROGRAM_ match
                    $node.resolved_type = "ROBOTICPROGRAM_"
                    $node.resolved_object_id = $rpOid
                    $node.resolved_caption = if ($rpCaption) { $rpCaption } elseif ($rpName) { $rpName } else { $shortcutCaption }
                    $node.robotic_program = @{
                        object_id = $rpOid
                        class_id = $rpClassId
                        caption = $rpCaption
                        name = $rpName
                        external_id = $rpExtId
                    }
                    $node.mapping_type = "deterministic"
                    $node.display_name = $node.resolved_caption
                    $node.name_provenance = "ROBOTICPROGRAM_.CAPTION_S_"
                    $roboticProgramCount++
                }
                elseif ($pxOid) {
                    # PROXY match - caption from COLLECTION_ via PROXY.OBJECT_ID
                    $node.resolved_type = "PROXY"
                    $node.resolved_object_id = $pxOid
                    $node.resolved_caption = if ($pxCap) { $pxCap } elseif ($shortcutCaption) { $shortcutCaption } else { $shortcutName }
                    $node.proxy = @{
                        object_id = $pxOid
                        class_id = $pxClassId
                        external_id = $pxExtId
                        project_id = $pxProjId
                        context_name = $pxCtx
                        collection_caption = $pxCap
                    }
                    $node.mapping_type = "deterministic"
                    $node.display_name = $node.resolved_caption
                    if ($pxCap) {
                        $node.name_provenance = "PROXY->COLLECTION_.CAPTION_S_"
                    } else {
                        $node.name_provenance = "SHORTCUT_.CAPTION_S_ (PROXY fallback)"
                    }
                    $proxyCount++
                }
                elseif ($linkExtId) {
                    # Has LINKEXTERNALID_S_ but no match found
                    $node.resolved_type = "UNKNOWN"
                    $node.resolved_object_id = $null
                    $node.resolved_caption = if ($shortcutCaption) { $shortcutCaption } else { $shortcutName }
                    $node.mapping_type = "unknown_target"
                    $node.display_name = $node.resolved_caption
                    $node.name_provenance = "SHORTCUT_.CAPTION_S_ (unknown target)"
                    $unknownCount++
                }
                else {
                    # No LINKEXTERNALID_S_ at all - local shortcut
                    $node.resolved_type = "LOCAL"
                    $node.resolved_object_id = $null
                    $node.resolved_caption = if ($shortcutCaption) { $shortcutCaption } else { $shortcutName }
                    $node.mapping_type = "local"
                }
            }
        }
    }

    Write-Host "  Resolved shortcut targets:" -ForegroundColor Green
    Write-Host "    RESOURCE_:       $resourceCount" -ForegroundColor Gray
    Write-Host "    ROBOTICPROGRAM_: $roboticProgramCount" -ForegroundColor Gray
    Write-Host "    PROXY:           $proxyCount" -ForegroundColor Gray
    Write-Host "    UNKNOWN:         $unknownCount" -ForegroundColor $(if ($unknownCount -gt 0) { 'Yellow' } else { 'Gray' })
}

Write-Host "`n[5/6] Resolving layout coordinates..." -ForegroundColor Yellow

# Get StudyInfo -> StudyLayout mapping (deterministic)
$sqlStudyLayout = @"
SET PAGESIZE 50000
SET LINESIZE 600
SET FEEDBACK OFF
SET HEADING OFF

-- Deterministic mapping: StudyInfo -> StudyLayout -> VEC_LOCATION_
-- Uses MAX(OBJECT_VERSION_ID) for version filtering across all versioned tables
SELECT
    'LAYOUT|' || rsi.OBJECT_ID || '|' ||
    sl.OBJECT_ID || '|' ||
    TO_CHAR(sl.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') || '|' ||
    NVL(TO_CHAR((SELECT vl.DATA FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID AND vl.SEQ_NUMBER = 0
        AND vl.OBJECT_VERSION_ID = sl.OBJECT_VERSION_ID)), '') || '|' ||
    NVL(TO_CHAR((SELECT vl.DATA FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID AND vl.SEQ_NUMBER = 1
        AND vl.OBJECT_VERSION_ID = sl.OBJECT_VERSION_ID)), '') || '|' ||
    NVL(TO_CHAR((SELECT vl.DATA FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID AND vl.SEQ_NUMBER = 2
        AND vl.OBJECT_VERSION_ID = sl.OBJECT_VERSION_ID)), '')
FROM $Schema.ROBCADSTUDYINFO_ rsi
INNER JOIN $Schema.STUDYLAYOUT_ sl ON sl.STUDYINFO_SR_ = rsi.OBJECT_ID
    AND sl.OBJECT_VERSION_ID = (SELECT MAX(sl2.OBJECT_VERSION_ID) FROM $Schema.STUDYLAYOUT_ sl2 WHERE sl2.OBJECT_ID = sl.OBJECT_ID)
WHERE rsi.STUDY_SR_ = $StudyId
  AND rsi.OBJECT_VERSION_ID = (SELECT MAX(rsi2.OBJECT_VERSION_ID) FROM $Schema.ROBCADSTUDYINFO_ rsi2 WHERE rsi2.OBJECT_ID = rsi.OBJECT_ID);

EXIT;
"@

$layoutRows = Invoke-SqlLines -SqlText $sqlStudyLayout
$layoutMap = @{}
$layoutCount = 0

foreach ($row in $layoutRows) {
    if ($row -match '^LAYOUT\|') {
        $parts = $row -split '\|'
        $studyInfoId = $parts[1].Trim()
        $layoutId = $parts[2].Trim()
        $modifiedDate = $parts[3].Trim()
        $x = if ($parts[4].Trim()) { [double]$parts[4].Trim() } else { $null }
        $y = if ($parts[5].Trim()) { [double]$parts[5].Trim() } else { $null }
        $z = if ($parts[6].Trim()) { [double]$parts[6].Trim() } else { $null }

        $layoutMap[$layoutId] = @{
            studyinfo_id = $studyInfoId
            layout_id = $layoutId
            modified_date = $modifiedDate
            x = $x
            y = $y
            z = $z
        }
        $layoutCount++
    }
}

Write-Host "  Found $layoutCount layout coordinate entries" -ForegroundColor Green

# Deterministic mapping: Match Shortcuts to StudyInfo via SEQ_NUMBER in REL_COMMON
# The study's REL_COMMON has children[seq=N] -> shortcut and info[seq=N] -> studyinfo
# Matching by seq_number gives a 1:1 deterministic mapping (no timestamp heuristic needed)
$sqlSeqMatch = @"
SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    'SEQMAP|' || c.FORWARD_OBJECT_ID || '|' || i.FORWARD_OBJECT_ID || '|' || c.SEQ_NUMBER
FROM $Schema.REL_COMMON c
JOIN $Schema.REL_COMMON i ON c.OBJECT_VERSION_ID = i.OBJECT_VERSION_ID AND c.SEQ_NUMBER = i.SEQ_NUMBER
WHERE c.OBJECT_VERSION_ID = (SELECT MAX(rs.OBJECT_VERSION_ID) FROM $Schema.ROBCADSTUDY_ rs WHERE rs.OBJECT_ID = $StudyId)
  AND c.FIELD_NAME = 'children'
  AND i.FIELD_NAME = 'info'
ORDER BY c.SEQ_NUMBER;

EXIT;
"@

$seqRows = Invoke-SqlLines -SqlText $sqlSeqMatch
$seqMap = @{}  # shortcut_id -> studyinfo_id

foreach ($row in $seqRows) {
    if ($row -match '^SEQMAP\|') {
        $parts = $row -split '\|'
        $shortcutId = $parts[1].Trim()
        $studyInfoId = $parts[2].Trim()
        $seqNum = $parts[3].Trim()
        $seqMap[$shortcutId] = $studyInfoId
    }
}

Write-Host "  Resolved $($seqMap.Count) shortcut-to-studyinfo mappings (deterministic via SEQ_NUMBER)" -ForegroundColor Green

# Apply layout data to nodes using deterministic seq mapping
$coordCount = 0
foreach ($layoutId in $layoutMap.Keys) {
    $layout = $layoutMap[$layoutId]
    $studyInfoId = $layout.studyinfo_id

    # Find the shortcut that maps to this studyinfo via seq_number
    $matchedShortcutId = $seqMap.GetEnumerator() | Where-Object { $_.Value -eq $studyInfoId } | Select-Object -First 1

    if ($matchedShortcutId) {
        $shortcutId = $matchedShortcutId.Key
        $node = $nodes | Where-Object { $_.node_id -eq $shortcutId } | Select-Object -First 1
        if ($node) {
            $node.layout_id = $layoutId
            $node.x = $layout.x
            $node.y = $layout.y
            $node.z = $layout.z
            $node.coord_provenance = "REL_COMMON[seq] -> STUDYINFO -> STUDYLAYOUT -> VEC_LOCATION_ (deterministic)"
            if ($node.mapping_type -eq "none") {
                $node.mapping_type = "deterministic"
            } elseif ($node.mapping_type -notmatch "deterministic") {
                $node.mapping_type = "deterministic+$($node.mapping_type)"
            }
            $coordCount++
        }
    }
}

Write-Host "  Applied coordinates to $coordCount nodes (deterministic)" -ForegroundColor Green

Write-Host "`n[6/6] Building snapshot output..." -ForegroundColor Yellow

# Build snapshot object
$snapshot = @{
    meta = @{
        schemaVersion = "1.2.0"  # Bumped for expanded shortcut target resolution
        capturedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        schema = $Schema
        projectId = $ProjectId
        studyId = $StudyId
        studyName = $metaData.studyName
        studyType = $metaData.studyType
        studyLastModified = $metaData.lastModified
        studyModifiedBy = $metaData.modifiedBy
        sqlplusVersion = (& sqlplus -version 2>&1 | Select-Object -First 1)
        nodeCount = $nodes.Count
        shortcutCount = ($nodes | Where-Object { $_.is_shortcut }).Count
        nodesWithNames = ($nodes | Where-Object { $_.name_provenance }).Count
        nodesWithCoords = ($nodes | Where-Object { $_.x -ne $null }).Count
        deterministicMappings = ($nodes | Where-Object { $_.mapping_type -match "^deterministic" }).Count
        heuristicMappings = ($nodes | Where-Object { $_.mapping_type -match "heuristic" }).Count
        ambiguousMappings = ($nodes | Where-Object { $_.mapping_type -match "ambiguous" }).Count
        # Shortcut target resolution breakdown
        shortcutResolution = @{
            resource = ($nodes | Where-Object { $_.resolved_type -eq "RESOURCE_" }).Count
            roboticProgram = ($nodes | Where-Object { $_.resolved_type -eq "ROBOTICPROGRAM_" }).Count
            proxy = ($nodes | Where-Object { $_.resolved_type -eq "PROXY" }).Count
            unknown = ($nodes | Where-Object { $_.resolved_type -eq "UNKNOWN" }).Count
            local = ($nodes | Where-Object { $_.resolved_type -eq "LOCAL" }).Count
        }
    }
    nodes = $nodes | ForEach-Object {
        $nodeObj = [ordered]@{
            node_id = $_.node_id
            parent_node_id = $_.parent_node_id
            depth = $_.depth
            seq_number = $_.seq_number
            node_type = $_.nice_name
            class_id = $_.class_id
            class_name = $_.class_name
            external_id = $_.external_id
            display_name = $_.display_name
            is_shortcut = $_.is_shortcut
            # Shortcut target resolution fields
            link_external_id = $_.link_external_id
            resolved_type = $_.resolved_type
            resolved_object_id = $_.resolved_object_id
            resolved_caption = $_.resolved_caption
            # Legacy resource fields (for backward compatibility)
            resource_id = $_.resource_id
            resource_name = $_.resource_name
            resource_type = $_.resource_type
            # Coordinate fields
            layout_id = $_.layout_id
            x = $_.x
            y = $_.y
            z = $_.z
            modified_date = $_.modified_date
            name_provenance = $_.name_provenance
            coord_provenance = $_.coord_provenance
            mapping_type = $_.mapping_type
        }
        # Add robotic_program object if present
        if ($_.robotic_program) {
            $nodeObj.robotic_program = $_.robotic_program
        }
        # Add proxy object if present
        if ($_.proxy) {
            $nodeObj.proxy = $_.proxy
        }
        [PSCustomObject]$nodeObj
    }
}

# Export to JSON
Write-Host "  Writing JSON: $jsonFile" -ForegroundColor Gray
$snapshot | ConvertTo-Json -Depth 10 | Out-File $jsonFile -Encoding UTF8

# Export to CSV (if requested)
if ($IncludeCSV) {
    Write-Host "  Writing CSV: $csvFile" -ForegroundColor Gray
    $snapshot.nodes | Export-Csv -Path $csvFile -NoTypeInformation -Encoding UTF8
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Snapshot Export Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Output: $jsonFile" -ForegroundColor White
if ($IncludeCSV) {
    Write-Host "  CSV:    $csvFile" -ForegroundColor White
}
Write-Host ""
Write-Host "  Statistics:" -ForegroundColor White
Write-Host "    Total nodes:              $($snapshot.meta.nodeCount)" -ForegroundColor Gray
Write-Host "    Shortcuts:                $($snapshot.meta.shortcutCount)" -ForegroundColor Gray
Write-Host "    Nodes with names:         $($snapshot.meta.nodesWithNames)" -ForegroundColor Gray
Write-Host "    Nodes with coordinates:   $($snapshot.meta.nodesWithCoords)" -ForegroundColor Gray
Write-Host "    Deterministic mappings:   $($snapshot.meta.deterministicMappings)" -ForegroundColor Green
Write-Host "    Heuristic mappings:       $($snapshot.meta.heuristicMappings)" -ForegroundColor Yellow
Write-Host "    Ambiguous mappings:       $($snapshot.meta.ambiguousMappings)" -ForegroundColor Magenta
Write-Host ""
Write-Host "  Shortcut Target Resolution:" -ForegroundColor White
Write-Host "    RESOURCE_:       $($snapshot.meta.shortcutResolution.resource)" -ForegroundColor Gray
Write-Host "    ROBOTICPROGRAM_: $($snapshot.meta.shortcutResolution.roboticProgram)" -ForegroundColor Gray
Write-Host "    PROXY:           $($snapshot.meta.shortcutResolution.proxy)" -ForegroundColor Gray
Write-Host "    UNKNOWN:         $($snapshot.meta.shortcutResolution.unknown)" -ForegroundColor $(if ($snapshot.meta.shortcutResolution.unknown -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "    LOCAL:           $($snapshot.meta.shortcutResolution.local)" -ForegroundColor Gray
Write-Host ""

exit 0
