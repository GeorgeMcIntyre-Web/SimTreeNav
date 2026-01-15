# Generate Tree HTML for a specific project
param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,
    
    [Parameter(Mandatory=$true)]
    [string]$Schema,
    
    [Parameter(Mandatory=$true)]
    [string]$ProjectId,
    
    [Parameter(Mandatory=$true)]
    [string]$ProjectName,
    
    [string]$OutputFile = "navigation-tree.html",
    [string]$CustomIconDir = ""
)

Write-Host "Generating tree for:" -ForegroundColor Yellow
Write-Host "  TNS Name: $TNSName" -ForegroundColor Cyan
Write-Host "  Schema: $Schema" -ForegroundColor Cyan
Write-Host "  Project: $ProjectName (ID: $ProjectId)" -ForegroundColor Cyan
if ($CustomIconDir) {
    Write-Host "  Custom Icons: $CustomIconDir" -ForegroundColor Cyan
}

# Extract icons from database using RAWTOHEX (works better than base64)
Write-Host "`nExtracting icons from database using RAWTOHEX..." -ForegroundColor Yellow

# Create icons directory
$iconsDir = "icons"
if (-not (Test-Path $iconsDir)) {
    New-Item -ItemType Directory -Path $iconsDir | Out-Null
}

# Query to extract all icons as hex
$extractIconsQuery = @"
SET PAGESIZE 0
SET LINESIZE 32767
SET LONG 10000000
SET LONGCHUNKSIZE 32767
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON
SET VERIFY OFF

-- Use DBMS_LOB.SUBSTR to convert BLOB chunks to RAW, then RAWTOHEX
-- We'll extract in one piece since icons are small (< 32KB)
SELECT
    di.TYPE_ID || '|' ||
    DBMS_LOB.GETLENGTH(di.CLASS_IMAGE) || '|' ||
    RAWTOHEX(DBMS_LOB.SUBSTR(di.CLASS_IMAGE, DBMS_LOB.GETLENGTH(di.CLASS_IMAGE), 1))
FROM $Schema.DF_ICONS_DATA di
WHERE di.CLASS_IMAGE IS NOT NULL
ORDER BY di.TYPE_ID;

EXIT;
"@

$extractIconsFile = "extract-icons-${Schema}.sql"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PWD\$extractIconsFile", $extractIconsQuery, $utf8NoBom)

$iconsOutputFile = "icons-data-${Schema}.txt"
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

# Run the query
Write-Host "  Running SQL query..." -ForegroundColor Gray
$result = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$extractIconsFile" 2>&1
$result | Out-File $iconsOutputFile -Encoding UTF8

# Read and parse all icons - store in memory as Base64
$allOutput = Get-Content $iconsOutputFile -Raw -Encoding UTF8
$allLines = $allOutput -split "`r?`n" | Where-Object { $_ -match '\|' }

Write-Host "  Found $($allLines.Count) icon entries" -ForegroundColor Gray

$iconCount = 0
$extractedTypeIds = @()
$iconDataMap = @{}  # Store TYPE_ID -> Base64 data URI mapping
$invalidIconEntries = @()

foreach ($line in $allLines) {
    $line = $line.Trim()
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    if ($line -match '^(\d+)\|(\d+)\|([0-9A-Fa-f]+)$') {
        $typeId = $matches[1]
        $expectedSize = [int]$matches[2]
        $hexData = $matches[3]

        try {
            # Convert hex to bytes
            $iconBytes = New-Object byte[] ($hexData.Length / 2)
            for ($i = 0; $i -lt $hexData.Length; $i += 2) {
                $iconBytes[$i / 2] = [Convert]::ToByte($hexData.Substring($i, 2), 16)
            }

            # Verify header and size; support BMP/PNG/ICO
            if ($iconBytes.Length -ge 4) {
                $headerLabel = [System.Text.Encoding]::ASCII.GetString($iconBytes[0..1])
                $headerHex = ($iconBytes[0..3] | ForEach-Object { $_.ToString("X2") }) -join ''
                $mimeType = $null
                if ($headerHex.StartsWith('424D')) {
                    $mimeType = 'image/bmp'
                } elseif ($headerHex -eq '89504E47') {
                    $mimeType = 'image/png'
                } elseif ($headerHex -eq '00000100' -or $headerHex -eq '00000200') {
                    $mimeType = 'image/x-icon'
                }

                if ($mimeType -and $iconBytes.Length -eq $expectedSize) {
                    # Convert to Base64 data URI instead of saving to file
                    $base64 = [Convert]::ToBase64String($iconBytes)
                    $dataUri = "data:$mimeType;base64,$base64"
                    $iconDataMap[$typeId] = $dataUri

                    $iconCount++
                    $extractedTypeIds += $typeId
                    Write-Host "  Extracted TYPE_ID $typeId ($expectedSize bytes, $mimeType)" -ForegroundColor Gray
                } else {
                    $detail = "TYPE_ID $typeId (header: '$headerLabel' $headerHex, size: $($iconBytes.Length) vs $expectedSize)"
                    $invalidIconEntries += $detail
                    Write-Warning "Invalid icon for $detail"
                }
            } else {
                $detail = "TYPE_ID $typeId (header: '??', size: $($iconBytes.Length) vs $expectedSize)"
                $invalidIconEntries += $detail
                Write-Warning "Invalid icon for $detail"
            }
        } catch {
            $invalidIconEntries += "TYPE_ID $typeId (exception: $_)"
            Write-Warning "Failed to extract TYPE_ID $typeId : $_"
        }
    }
}

Write-Host "  Successfully extracted: $iconCount icons" -ForegroundColor Green
$dbIconTypeIds = @{}
foreach ($key in $iconDataMap.Keys) {
    $dbIconTypeIds[$key] = $true
}
$fallbackAddedTypeIds = @()
# Add fallback icons for TYPE_IDs that don't exist in database
Write-Host "  Adding fallback icons for missing TYPE_IDs..." -ForegroundColor Yellow

# TYPE_ID 72 (PmStudyFolder) -> copy from 18 (Collection - parent class)
# StudyFolder derives from Collection, use parent class icon
if ($iconDataMap['18'] -and -not $iconDataMap['72']) {
    $iconDataMap['72'] = $iconDataMap['18']
    $extractedTypeIds += 72
    $fallbackAddedTypeIds += '72'
    $iconCount++
    Write-Host "    Added fallback: TYPE_ID 72 -> 18 (StudyFolder -> Collection parent)" -ForegroundColor Gray
}

# TYPE_ID 164 (RobcadResourceLibrary) -> copy from 162 (MaterialLibrary)
if ($iconDataMap['162'] -and -not $iconDataMap['164']) {
    $iconDataMap['164'] = $iconDataMap['162']
    $extractedTypeIds += 164
    $fallbackAddedTypeIds += '164'
    $iconCount++
    Write-Host "    Added fallback: TYPE_ID 164 -> 162 (RobcadResourceLibrary -> MaterialLibrary)" -ForegroundColor Gray
}

# Study type fallbacks - use parent class icons based on class hierarchy
# RobcadStudy (177) -> ShortcutFolder (69) -> Study (70) hierarchy
# LocationalStudy (108) -> Study (70) -> ShortcutFolder (69)
# All Study types should use ShortcutFolder icon (TYPE_ID 69)
$studyFallbacks = @{
    '177' = 'RobcadStudy'
    '178' = 'LineSimulationStudy'
    '183' = 'GanttStudy'
    '181' = 'SimpleDetailedStudy'
    '108' = 'LocationalStudy'
    '70'  = 'Study'  # Base Study class also needs icon
}

foreach ($typeId in $studyFallbacks.Keys) {
    if ($iconDataMap['69'] -and -not $iconDataMap[$typeId]) {
        $iconDataMap[$typeId] = $iconDataMap['69']
        $extractedTypeIds += [int]$typeId
        $fallbackAddedTypeIds += $typeId
        $iconCount++
        Write-Host "    Added fallback: TYPE_ID $typeId -> 69 ($($studyFallbacks[$typeId]) -> ShortcutFolder parent)" -ForegroundColor Gray
    }
}

Write-Host "  Total icons (with fallbacks): $iconCount" -ForegroundColor Green
if ($invalidIconEntries.Count -gt 0) {
    Write-Host "  Skipped $($invalidIconEntries.Count) icons due to invalid header or size mismatch" -ForegroundColor Yellow
}

# Convert icon data map to JSON for passing to HTML generator
$iconDataJson = ($iconDataMap.GetEnumerator() | ForEach-Object {
    "`"$($_.Key)`": `"$($_.Value)`""
}) -join ","
$iconDataJson = "{$iconDataJson}"

# Debug: Check if TYPE_ID 64 is in the map
if ($iconDataMap['64']) {
    Write-Host "  DEBUG: TYPE_ID 64 IS in iconDataMap (length: $($iconDataMap['64'].Length) chars)" -ForegroundColor Cyan
} else {
    Write-Host "  DEBUG: TYPE_ID 64 NOT in iconDataMap!" -ForegroundColor Red
}

# Create comma-separated list of extracted TYPE_IDs to pass to JavaScript
$extractedTypeIdsJson = ($extractedTypeIds | Sort-Object | ForEach-Object { "$_" }) -join ','
Write-Host "  Extracted TYPE_IDs: $extractedTypeIdsJson" -ForegroundColor Gray

# Cleanup
Remove-Item $extractIconsFile -ErrorAction SilentlyContinue
Remove-Item $iconsOutputFile -ErrorAction SilentlyContinue

# Generate SQL query to get full tree
$sqlFile = "get-tree-${Schema}-${ProjectId}.sql"
$sqlQuery = @"
SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

-- Get full navigation tree for $ProjectName with ordering
-- Output format: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID

-- Level 0: Root
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT '0|0|$ProjectId|$ProjectName|$ProjectName|' || NVL(c.EXTERNALID_S_, '') || '|0|' || NVL(cd.NAME, 'class PmNode') || '|' || NVL(cd.NICE_NAME, 'Unknown') || '|' || TO_CHAR(cd.TYPE_ID)
FROM $Schema.COLLECTION_ c
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE c.OBJECT_ID = $ProjectId;

-- Level 1: Direct children (custom order matching Siemens app)
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '1|$ProjectId|' || r.OBJECT_ID || '|' ||
    COALESCE(
        c.CAPTION_S_,
        p.NAME_S_,
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'PartInstanceLibrary' END,
        'Unnamed'
    ) || '|' ||
    COALESCE(
        c.CAPTION_S_,
        p.NAME_S_,
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'PartInstanceLibrary' END,
        'Unnamed'
    ) || '|' ||
    COALESCE(c.EXTERNALID_S_, p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    COALESCE(
        cd.NAME,
        cd_part.NAME,
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'class PmPartLibrary' END,
        'class PmNode'
    ) || '|' ||
    COALESCE(
        cd.NICE_NAME,
        cd_part.NICE_NAME,
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'PartLibrary' END,
        'Unknown'
    ) || '|' ||
    COALESCE(
        TO_CHAR(cd.TYPE_ID),
        TO_CHAR(cd_part.TYPE_ID),
        CASE WHEN r.OBJECT_ID = 18143953 THEN '46' END,
        ''
    )
FROM $Schema.REL_COMMON r
LEFT JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd_part ON p.CLASS_ID = cd_part.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = $ProjectId
ORDER BY
    -- Custom ordering to match Siemens Navigation Tree
    CASE r.OBJECT_ID
        WHEN 18195357 THEN 1  -- P702
        WHEN 18195358 THEN 2  -- P736
        WHEN 18153685 THEN 3  -- EngineeringResourceLibrary
        WHEN 18143951 THEN 4  -- PartLibrary
        WHEN 18143953 THEN 5  -- PartInstanceLibrary (ghost node)
        WHEN 18143955 THEN 6  -- MfgLibrary
        WHEN 18143956 THEN 7  -- IPA
        WHEN 18144070 THEN 8  -- DES_Studies
        WHEN 18144071 THEN 9  -- Working Folders
        ELSE 999  -- Unknown nodes go last
    END;

-- Level 2+: All descendants using hierarchical query with NOCYCLE
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    LEVEL || '|' ||
    PRIOR c.OBJECT_ID || '|' ||
    c.OBJECT_ID || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
START WITH r.FORWARD_OBJECT_ID = $ProjectId
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
ORDER SIBLINGS BY NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID;

-- Add StudyFolder children explicitly (these are links/shortcuts to real data)
-- StudyFolder nodes are identified by their NICE_NAME in CLASS_DEFINITIONS, not CAPTION
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||  -- Use high level number, JavaScript will handle it
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.COLLECTION_ c_parent ON r.FORWARD_OBJECT_ID = c_parent.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd_parent ON c_parent.CLASS_ID = cd_parent.TYPE_ID
INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE cd_parent.NICE_NAME = 'StudyFolder'
  AND EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    START WITH r2.FORWARD_OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
    WHERE c2.OBJECT_ID = c_parent.OBJECT_ID
  )
ORDER BY r.FORWARD_OBJECT_ID, NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID;

-- Add RobcadStudy nodes (from ROBCADSTUDY_ table)
-- These nodes are stored in a specialized table, not COLLECTION_
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||  -- Use high level number, JavaScript will handle it
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(rs.NAME_S_, 'Unnamed') || '|' ||
    NVL(rs.NAME_S_, 'Unnamed') || '|' ||
    NVL(rs.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class RobcadStudy') || '|' ||
    NVL(cd.NICE_NAME, 'RobcadStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.ROBCADSTUDY_ rs ON r.OBJECT_ID = rs.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM $Schema.REL_COMMON r3
        INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add LineSimulationStudy nodes (from LINESIMULATIONSTUDY_ table)
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(ls.NAME_S_, 'Unnamed') || '|' ||
    NVL(ls.NAME_S_, 'Unnamed') || '|' ||
    NVL(ls.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class LineSimulationStudy') || '|' ||
    NVL(cd.NICE_NAME, 'LineSimulationStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.LINESIMULATIONSTUDY_ ls ON r.OBJECT_ID = ls.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON ls.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM $Schema.REL_COMMON r3
        INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add GanttStudy nodes (from GANTTSTUDY_ table)
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(gs.NAME_S_, 'Unnamed') || '|' ||
    NVL(gs.NAME_S_, 'Unnamed') || '|' ||
    NVL(gs.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class GanttStudy') || '|' ||
    NVL(cd.NICE_NAME, 'GanttStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.GANTTSTUDY_ gs ON r.OBJECT_ID = gs.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON gs.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM $Schema.REL_COMMON r3
        INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add SimpleDetailedStudy nodes (from SIMPLEDETAILEDSTUDY_ table)
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(sd.NAME_S_, 'Unnamed') || '|' ||
    NVL(sd.NAME_S_, 'Unnamed') || '|' ||
    NVL(sd.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class SimpleDetailedStudy') || '|' ||
    NVL(cd.NICE_NAME, 'SimpleDetailedStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.SIMPLEDETAILEDSTUDY_ sd ON r.OBJECT_ID = sd.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON sd.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM $Schema.REL_COMMON r3
        INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add LocationalStudy nodes (from LOCATIONALSTUDY_ table)
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(lc.NAME_S_, 'Unnamed') || '|' ||
    NVL(lc.NAME_S_, 'Unnamed') || '|' ||
    NVL(lc.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class LocationalStudy') || '|' ||
    NVL(cd.NICE_NAME, 'LocationalStudy') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.LOCATIONALSTUDY_ lc ON r.OBJECT_ID = lc.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON lc.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM $Schema.REL_COMMON r3
        INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add children of RobcadStudy nodes from SHORTCUT_ table
-- Shortcuts are link nodes that reference other objects in the tree
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT DISTINCT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(sc.NAME_S_, 'Unnamed') || '|' ||
    NVL(sc.NAME_S_, 'Unnamed') || '|' ||
    NVL(sc.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmShortcut') || '|' ||
    NVL(cd.NICE_NAME, 'Shortcut') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.SHORTCUT_ sc ON r.OBJECT_ID = sc.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON sc.CLASS_ID = cd.TYPE_ID
INNER JOIN $Schema.ROBCADSTUDY_ rs_parent ON r.FORWARD_OBJECT_ID = rs_parent.OBJECT_ID
WHERE EXISTS (
    SELECT 1
    FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.FORWARD_OBJECT_ID = c2.OBJECT_ID
    WHERE r2.OBJECT_ID = rs_parent.OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM $Schema.REL_COMMON r3
        INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add TxProcessAssembly nodes (from PART_ table, CLASS_ID 133)
-- TxProcessAssembly nodes are stored in PART_ table, not COLLECTION_
-- These are assembly/process nodes that appear in the tree structure
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmTxProcessAssembly') || '|' ||
    NVL(cd.NICE_NAME, 'TxProcessAssembly') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE p.CLASS_ID = 133  -- TxProcessAssembly TYPE_ID
  AND EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM $Schema.REL_COMMON r3
        INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- NOTE: RobcadStudyInfo nodes are HIDDEN (internal metadata not shown in Siemens Navigation Tree)
-- RobcadStudyInfo contains layout configuration (LAYOUT_SR_) and study metadata for loading modes
-- Each RobcadStudyInfo is paired with a Shortcut but should not appear in the navigation tree
-- The query below is commented out to hide these internal metadata nodes

-- SELECT
--     '999|' ||
--     r.FORWARD_OBJECT_ID || '|' ||
--     r.OBJECT_ID || '|' ||
--     NVL(rsi.NAME_S_, 'Unnamed') || '|' ||
--     NVL(rsi.NAME_S_, 'Unnamed') || '|' ||
--     NVL(rsi.EXTERNALID_S_, '') || '|' ||
--     TO_CHAR(r.SEQ_NUMBER) || '|' ||
--     NVL(cd.NAME, 'class RobcadStudyInfo') || '|' ||
--     NVL(cd.NICE_NAME, 'RobcadStudyInfo') || '|' ||
--     TO_CHAR(cd.TYPE_ID)
-- FROM $Schema.REL_COMMON r
-- INNER JOIN $Schema.ROBCADSTUDYINFO_ rsi ON r.OBJECT_ID = rsi.OBJECT_ID
-- LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON rsi.CLASS_ID = cd.TYPE_ID
-- WHERE r.FORWARD_OBJECT_ID IN (
--     SELECT r2.OBJECT_ID
--     FROM $Schema.REL_COMMON r2
--     INNER JOIN $Schema.ROBCADSTUDY_ rs ON r2.OBJECT_ID = rs.OBJECT_ID
--     INNER JOIN $Schema.COLLECTION_ c2 ON r2.FORWARD_OBJECT_ID = c2.OBJECT_ID
--     WHERE c2.OBJECT_ID IN (
--         SELECT c3.OBJECT_ID
--         FROM $Schema.REL_COMMON r3
--         INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
--         START WITH r3.FORWARD_OBJECT_ID = $ProjectId
--         CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
--       )
--   );

EXIT;
"@

# Write SQL file without BOM to avoid "SP2-0734: unknown command" error
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PWD\$sqlFile", $sqlQuery, $utf8NoBom)

# Execute query with proper encoding handling
Write-Host "`nQuerying database..." -ForegroundColor Yellow
$dataFile = "tree-data-${Schema}-${ProjectId}.txt"

# Set SQL*Plus to use UTF-8 encoding
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

# Use a temporary file to capture SQL*Plus output
# SQL*Plus on Windows outputs in the console code page (usually Windows-1252)
# We need to capture it to a file and read it with the correct encoding
$tempOutputFile = "tree-data-${Schema}-${ProjectId}-raw.txt"

# Run SQL*Plus directly (simpler, more reliable)
$result = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$sqlFile" 2>&1
$result | Out-File $tempOutputFile -Encoding UTF8

# Clean the data and convert to UTF-8
Write-Host "Cleaning data and fixing encoding..." -ForegroundColor Yellow
$cleanFile = "tree-data-${Schema}-${ProjectId}-clean.txt"

# Read the output file as Windows-1252 (the standard Windows code page)
# SQL*Plus outputs in the console code page, which is typically Windows-1252
# Windows-1252 properly handles German characters (Ã¶, Ã¤, Ã¼, ÃŸ)
$windows1252 = [System.Text.Encoding]::GetEncoding(1252)
$rawContent = [System.IO.File]::ReadAllText("$PWD\$tempOutputFile", $windows1252)

# Split into lines and filter
$lines = $rawContent -split "`r?`n"
$cleanLines = $lines | Where-Object { 
    $_ -match '^\d+\|\d+\|' -and 
    $_ -notmatch 'ERROR' -and 
    $_ -notmatch 'SP2' -and
    $_ -notmatch '^SQL>' -and
    $_ -notmatch '^Connected' -and
    $_ -notmatch '^Disconnected' -and
    $_ -notmatch '^Copyright' -and
    $_ -notmatch '^Active code page'
}

# Convert from Windows-1252 to UTF-8 properly
Write-Host "  Converting encoding (Windows-1252 â†’ UTF-8)..." -ForegroundColor Gray
$allText = $cleanLines -join "`r`n"

# Convert: Windows-1252 bytes â†’ UTF-8 bytes â†’ UTF-8 string
$sourceBytes = $windows1252.GetBytes($allText)
$utf8Bytes = [System.Text.Encoding]::Convert($windows1252, [System.Text.Encoding]::UTF8, $sourceBytes)
$utf8Text = [System.Text.Encoding]::UTF8.GetString($utf8Bytes)

# Write cleaned data as UTF-8 with BOM
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText("$PWD\$cleanFile", $utf8Text, $utf8WithBom)

# Cleanup
if (Test-Path $tempOutputFile) { Remove-Item $tempOutputFile -Force }

# Report missing icons for TYPE_IDs used in the tree
Write-Host "Checking for missing icons in tree data..." -ForegroundColor Yellow
$treeTypeInfo = @{}
$missingTypeIdCount = 0

Get-Content $cleanFile | ForEach-Object {
    if ($_ -match '^\d+\|') {
        $parts = $_ -split '\|'
        if ($parts.Length -ge 10) {
            $typeId = $parts[9]
            $className = $parts[7]
            $niceName = $parts[8]
            if ($typeId -and $typeId -match '^\d+$') {
                if (-not $treeTypeInfo.ContainsKey($typeId)) {
                    $treeTypeInfo[$typeId] = [PSCustomObject]@{
                        TypeId = $typeId
                        ClassName = $className
                        NiceName = $niceName
                        Count = 0
                    }
                }
                $treeTypeInfo[$typeId].Count++
            } else {
                $missingTypeIdCount++
            }
        }
    }
}

$missingDbTypeIds = $treeTypeInfo.Keys | Where-Object { -not $dbIconTypeIds.ContainsKey($_) }
$missingTypeIds = $treeTypeInfo.Keys | Where-Object { -not $iconDataMap.ContainsKey($_) }
$missingIconReport = "missing-icons-${Schema}-${ProjectId}.txt"
$reportLines = @()
$missingDbTypeIdsJson = "[]"
if ($missingDbTypeIds.Count -gt 0) {
    $missingDbTypeIdsJson = "[" + (($missingDbTypeIds | Sort-Object | ForEach-Object { $_ }) -join ',') + "]"
}

if ($missingDbTypeIds.Count -gt 0) {
    $missingTypeSummary = ($missingDbTypeIds | Sort-Object) -join ', '
    Write-Warning "Missing DB icon data for TYPE_IDs: $missingTypeSummary (fallback will be used where possible)"
    $reportLines += "Missing TYPE_ID icons in DB extraction (fallback will be used where possible):"
    foreach ($typeId in ($missingDbTypeIds | Sort-Object)) {
        $info = $treeTypeInfo[$typeId]
        $reportLines += "$typeId|$($info.NiceName)|$($info.ClassName)|$($info.Count)"
    }
} else {
    Write-Host "  All TYPE_IDs in tree have DB icon data." -ForegroundColor Green
}

if ($missingTypeIds.Count -gt 0) {
    $missingFallbackSummary = ($missingTypeIds | Sort-Object) -join ', '
    Write-Warning "Missing icon data after fallbacks for TYPE_IDs: $missingFallbackSummary"
    $reportLines += ""
    $reportLines += "Missing TYPE_ID icons after fallback:"
    foreach ($typeId in ($missingTypeIds | Sort-Object)) {
        $info = $treeTypeInfo[$typeId]
        $reportLines += "$typeId|$($info.NiceName)|$($info.ClassName)|$($info.Count)"
    }
}

if ($fallbackAddedTypeIds.Count -gt 0) {
    $fallbackSummary = ($fallbackAddedTypeIds | Sort-Object -Unique) -join ', '
    $reportLines += ""
    $reportLines += "Fallback icons added for TYPE_IDs: $fallbackSummary"
}

if ($missingTypeIdCount -gt 0) {
    $reportLines += ""
    $reportLines += "Nodes with missing TYPE_ID field: $missingTypeIdCount"
}

if ($invalidIconEntries.Count -gt 0) {
    $reportLines += ""
    $reportLines += "Invalid icon entries (header/size mismatch or extraction error):"
    $reportLines += $invalidIconEntries
}

if ($reportLines.Count -gt 0) {
    $reportLines | Out-File $missingIconReport -Encoding UTF8
    Write-Host "  Wrote icon report to $missingIconReport" -ForegroundColor Gray
}

# Optional DB check for missing TYPE_ID icons
if ($missingDbTypeIds.Count -gt 0) {
    $missingTypeList = ($missingDbTypeIds | Sort-Object | ForEach-Object { $_ }) -join ','
    $checkMissingIconsSql = @"
SET PAGESIZE 0
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    cd.TYPE_ID || '|' ||
    NVL(DBMS_LOB.GETLENGTH(di.CLASS_IMAGE), 0) || '|' ||
    NVL(cd.NICE_NAME, '') || '|' ||
    NVL(cd.NAME, '')
FROM $Schema.CLASS_DEFINITIONS cd
LEFT JOIN $Schema.DF_ICONS_DATA di ON di.TYPE_ID = cd.TYPE_ID
WHERE cd.TYPE_ID IN ($missingTypeList)
ORDER BY cd.TYPE_ID;

EXIT;
"@

    $checkMissingIconsFile = "check-missing-icons-${Schema}-${ProjectId}.sql"
    [System.IO.File]::WriteAllText("$PWD\$checkMissingIconsFile", $checkMissingIconsSql, $utf8NoBom)
    $missingIconsDbFile = "missing-icons-${Schema}-${ProjectId}-db.txt"
    $dbCheckResult = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$checkMissingIconsFile" 2>&1
    $dbCheckResult | Out-File $missingIconsDbFile -Encoding UTF8
    Remove-Item $checkMissingIconsFile -ErrorAction SilentlyContinue
    Write-Host "  Wrote DB icon check to $missingIconsDbFile" -ForegroundColor Gray
}

# Extract user activity for checkout status
Write-Host "Extracting user activity..." -ForegroundColor Yellow
$userActivitySql = @"
SET PAGESIZE 0
SET LINESIZE 32767
SET FEEDBACK OFF
SET HEADING OFF

SELECT
    p.OBJECT_ID || '|' || NVL(u.CAPTION_S_, '') || '|' || '' || '|CHECKEDOUT' AS USER_DATA
FROM $Schema.PROXY p
LEFT JOIN $Schema.USER_ u ON u.OBJECT_ID = p.OWNER_ID
WHERE p.PROJECT_ID = $ProjectId
  AND NVL(p.WORKING_VERSION_ID, 0) > 0
  AND NVL(p.OWNER_ID, 0) > 0
ORDER BY p.OBJECT_ID;

EXIT;
"@

$userActivityFile = Join-Path $env:TEMP "get-user-activity-${Schema}-${ProjectId}.sql"
[System.IO.File]::WriteAllText($userActivityFile, $userActivitySql, $utf8NoBom)

$userActivityResult = & sqlplus -S "sys/change_on_install@$TNSName AS SYSDBA" "@$userActivityFile" 2>&1

# Parse into JavaScript object
$userActivityJs = "const userActivity = {"
foreach ($line in $userActivityResult -split "`n") {
    if ($line -match '^(\d+)\|([^|]*)\|([^|]*)\|(.*)$') {
        $objId = $matches[1]
        $usr = $matches[2] -replace "'", "\'"
        $tim = $matches[3]
        $onl = $matches[4]
        $userActivityJs += "`n  ${objId}: {user: '$usr', time: '$tim', online: '$onl'},"
    }
}
$userActivityJs += "`n};"

Remove-Item $userActivityFile -ErrorAction SilentlyContinue

# Generate HTML with in-memory icon data
Write-Host "Generating HTML with database icons..." -ForegroundColor Yellow
$fullTreeScriptPath = Join-Path $PSScriptRoot "generate-full-tree-html.ps1"
& $fullTreeScriptPath -DataFile $cleanFile -ProjectName $ProjectName -ProjectId $ProjectId -Schema $Schema -OutputFile $OutputFile -ExtractedTypeIds $extractedTypeIdsJson -IconDataJson $iconDataJson -MissingDbTypeIds $missingDbTypeIdsJson -UserActivityJs $userActivityJs -CustomIconDir $CustomIconDir

# Cleanup
Remove-Item $sqlFile -ErrorAction SilentlyContinue
Remove-Item $dataFile -ErrorAction SilentlyContinue

Write-Host "`nDone! Tree saved to: $OutputFile" -ForegroundColor Green
