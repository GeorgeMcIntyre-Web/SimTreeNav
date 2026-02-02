# Export Study Tree Snapshot
# Purpose: Deterministic snapshot of study tree structure, naming, and locations
# Date: 2026-01-30

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
        }
    }
}

Write-Host "  Found $($nodes.Count) nodes in tree" -ForegroundColor Green

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
WHERE s.OBJECT_ID IN ($shortcutNodeIds);

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
WHERE c.OBJECT_ID IN ($collectionNodeIds);

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

Write-Host "`n[4/6] Resolving resource mappings for shortcuts..." -ForegroundColor Yellow

# Resolve resources for shortcuts
if ($shortcutNodeIds) {
    $sqlResources = @"
SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    'RES|' || s.OBJECT_ID || '|' ||
    NVL(res.OBJECT_ID, 0) || '|' ||
    NVL(res.NAME_S_, '') || '|' ||
    NVL(cd.NICE_NAME, '') || '|' ||
    NVL(s.LINKEXTERNALID_S_, '') || '|' ||
    NVL(res.EXTERNALID_S_, '')
FROM $Schema.SHORTCUT_ s
LEFT JOIN $Schema.RESOURCE_ res
    ON (s.LINKEXTERNALID_S_ IS NOT NULL AND s.LINKEXTERNALID_S_ = res.EXTERNALID_S_)
    OR (s.LINKEXTERNALID_S_ IS NULL AND s.NAME_S_ = res.NAME_S_)
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
WHERE s.OBJECT_ID IN ($shortcutNodeIds)
  AND res.OBJECT_ID IS NOT NULL;

EXIT;
"@

    $resRows = Invoke-SqlLines -SqlText $sqlResources
    $resourceCount = 0

    foreach ($row in $resRows) {
        if ($row -match '^RES\|') {
            $parts = $row -split '\|'
            $shortcutId = $parts[1].Trim()
            $resourceId = $parts[2].Trim()
            $resourceName = $parts[3].Trim()
            $resourceType = $parts[4].Trim()

            $node = $nodes | Where-Object { $_.node_id -eq $shortcutId } | Select-Object -First 1
            if ($node) {
                $node.resource_id = $resourceId
                $node.resource_name = $resourceName
                $node.resource_type = $resourceType
                $node.mapping_type = "deterministic"

                # Update display name to resource name (ALWAYS prefer resource name for shortcuts)
                if ($resourceName) {
                    $node.display_name = $resourceName
                    $node.name_provenance = "RESOURCE_.NAME_S_"
                }

                $resourceCount++
            }
        }
    }

    Write-Host "  Resolved $resourceCount resource mappings" -ForegroundColor Green
}

Write-Host "`n[5/6] Resolving layout coordinates..." -ForegroundColor Yellow

# Get StudyInfo -> StudyLayout mapping (deterministic)
$sqlStudyLayout = @"
SET PAGESIZE 50000
SET LINESIZE 600
SET FEEDBACK OFF
SET HEADING OFF

-- Deterministic mapping: StudyInfo -> StudyLayout -> VEC_LOCATION_
SELECT
    'LAYOUT|' || rsi.OBJECT_ID || '|' ||
    sl.OBJECT_ID || '|' ||
    TO_CHAR(sl.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') || '|' ||
    NVL(TO_CHAR((SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 0 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID)), '') || '|' ||
    NVL(TO_CHAR((SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 1 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID)), '') || '|' ||
    NVL(TO_CHAR((SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 2 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID)), '')
FROM $Schema.ROBCADSTUDYINFO_ rsi
INNER JOIN $Schema.STUDYLAYOUT_ sl ON sl.STUDYINFO_SR_ = rsi.OBJECT_ID
WHERE rsi.STUDY_SR_ = $StudyId;

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

# Timestamp-based heuristic: match StudyInfo to Shortcuts by modification time
# This is labeled as HEURISTIC mapping
$sqlTimestampMatch = @"
SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    'MATCH|' || rsi.OBJECT_ID || '|' ||
    TO_CHAR(rsi.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') || '|' ||
    s.OBJECT_ID || '|' ||
    s.NAME_S_
FROM $Schema.ROBCADSTUDYINFO_ rsi
INNER JOIN $Schema.SHORTCUT_ s ON TO_CHAR(s.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') = TO_CHAR(rsi.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS')
INNER JOIN $Schema.REL_COMMON r ON s.OBJECT_ID = r.OBJECT_ID
WHERE rsi.STUDY_SR_ = $StudyId
  AND r.FORWARD_OBJECT_ID = $StudyId
ORDER BY rsi.MODIFICATIONDATE_DA_;

EXIT;
"@

$matchRows = Invoke-SqlLines -SqlText $sqlTimestampMatch
$heuristicMatches = @{}
$heuristicCount = 0

foreach ($row in $matchRows) {
    if ($row -match '^MATCH\|') {
        $parts = $row -split '\|'
        $studyInfoId = $parts[1].Trim()
        $timestamp = $parts[2].Trim()
        $shortcutId = $parts[3].Trim()
        $shortcutName = $parts[4].Trim()

        if (-not $heuristicMatches.ContainsKey($studyInfoId)) {
            $heuristicMatches[$studyInfoId] = @()
        }
        $heuristicMatches[$studyInfoId] += @{
            shortcut_id = $shortcutId
            shortcut_name = $shortcutName
            timestamp = $timestamp
        }
    }
}

# Apply layout data to nodes
foreach ($layoutId in $layoutMap.Keys) {
    $layout = $layoutMap[$layoutId]
    $studyInfoId = $layout.studyinfo_id

    # Try to find matching shortcuts via heuristic
    if ($heuristicMatches.ContainsKey($studyInfoId)) {
        $candidates = $heuristicMatches[$studyInfoId]

        if ($candidates.Count -eq 1) {
            # Unambiguous match
            $shortcutId = $candidates[0].shortcut_id
            $node = $nodes | Where-Object { $_.node_id -eq $shortcutId } | Select-Object -First 1
            if ($node) {
                $node.layout_id = $layoutId
                $node.x = $layout.x
                $node.y = $layout.y
                $node.z = $layout.z
                $node.coord_provenance = "STUDYLAYOUT_.OBJECT_ID -> VEC_LOCATION_ (heuristic timestamp match)"
                if ($node.mapping_type -eq "deterministic") {
                    $node.mapping_type = "deterministic+heuristic_coords"
                } else {
                    $node.mapping_type = "heuristic"
                }
                $heuristicCount++
            }
        } elseif ($candidates.Count -gt 1) {
            # Ambiguous match - attach to all candidates with warning
            foreach ($candidate in $candidates) {
                $shortcutId = $candidate.shortcut_id
                $node = $nodes | Where-Object { $_.node_id -eq $shortcutId } | Select-Object -First 1
                if ($node) {
                    $node.layout_id = "$layoutId (ambiguous)"
                    $node.x = $layout.x
                    $node.y = $layout.y
                    $node.z = $layout.z
                    $node.coord_provenance = "STUDYLAYOUT_.OBJECT_ID -> VEC_LOCATION_ (AMBIGUOUS - $($candidates.Count) candidates at same timestamp)"
                    if ($node.mapping_type -eq "deterministic") {
                        $node.mapping_type = "deterministic+heuristic_coords_ambiguous"
                    } else {
                        $node.mapping_type = "heuristic_ambiguous"
                    }
                }
            }
        }
    }
}

Write-Host "  Applied coordinates to $heuristicCount nodes (heuristic)" -ForegroundColor Yellow

Write-Host "`n[6/6] Building snapshot output..." -ForegroundColor Yellow

# Build snapshot object
$snapshot = @{
    meta = @{
        schemaVersion = "1.0.0"
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
        nodesWithNames = ($nodes | Where-Object { $_.name_provenance }).Count
        nodesWithCoords = ($nodes | Where-Object { $_.x -ne $null }).Count
        deterministicMappings = ($nodes | Where-Object { $_.mapping_type -match "^deterministic" }).Count
        heuristicMappings = ($nodes | Where-Object { $_.mapping_type -match "heuristic" }).Count
        ambiguousMappings = ($nodes | Where-Object { $_.mapping_type -match "ambiguous" }).Count
    }
    nodes = $nodes | ForEach-Object {
        [PSCustomObject]@{
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
            resource_id = $_.resource_id
            resource_name = $_.resource_name
            resource_type = $_.resource_type
            layout_id = $_.layout_id
            x = $_.x
            y = $_.y
            z = $_.z
            modified_date = $_.modified_date
            name_provenance = $_.name_provenance
            coord_provenance = $_.coord_provenance
            mapping_type = $_.mapping_type
        }
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
Write-Host "    Nodes with names:         $($snapshot.meta.nodesWithNames)" -ForegroundColor Gray
Write-Host "    Nodes with coordinates:   $($snapshot.meta.nodesWithCoords)" -ForegroundColor Gray
Write-Host "    Deterministic mappings:   $($snapshot.meta.deterministicMappings)" -ForegroundColor Green
Write-Host "    Heuristic mappings:       $($snapshot.meta.heuristicMappings)" -ForegroundColor Yellow
Write-Host "    Ambiguous mappings:       $($snapshot.meta.ambiguousMappings)" -ForegroundColor Magenta
Write-Host ""

exit 0
