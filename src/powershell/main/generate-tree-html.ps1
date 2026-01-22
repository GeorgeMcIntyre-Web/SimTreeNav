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
    [string]$CustomIconDir = "",
    [switch]$AllowIconFallback
)

# Start overall timing
$scriptTimer = [System.Diagnostics.Stopwatch]::StartNew()
$phaseTimer = [System.Diagnostics.Stopwatch]::new()
$tnsSlug = ($TNSName -replace '[^A-Za-z0-9._-]', '_')

function Start-Phase {
    param([string]$Name)
    $phaseTimer.Restart()
    $script:currentPhase = $Name
}

function End-Phase {
    $phaseTimer.Stop()
    $elapsed = [math]::Round($phaseTimer.Elapsed.TotalSeconds, 2)
    Write-Host "  ⏱ Phase completed in ${elapsed}s" -ForegroundColor DarkGray
}

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "..\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
} else {
    Write-Warning "Credential manager not found. Falling back to default password."
}

# Define UTF-8 encoding objects (used throughout for file I/O)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$utf8WithBom = New-Object System.Text.UTF8Encoding $true

Write-Host "Generating tree for:" -ForegroundColor Yellow
Write-Host "  TNS Name: $TNSName" -ForegroundColor Cyan
Write-Host "  Schema: $Schema" -ForegroundColor Cyan
Write-Host "  Project: $ProjectName (ID: $ProjectId)" -ForegroundColor Cyan
if ($CustomIconDir) {
    Write-Host "  Custom Icons: $CustomIconDir" -ForegroundColor Cyan
}
if ($AllowIconFallback) {
    Write-Host "  Icon Fallback: ENABLED" -ForegroundColor Cyan
} else {
    Write-Host "  Icon Fallback: DISABLED (DB-only)" -ForegroundColor Cyan
}

# Extract icons from database using RAWTOHEX (works better than base64)
Write-Host "`nExtracting icons from database..." -ForegroundColor Yellow
Start-Phase "Icon Extraction"

# Create icons directory
$iconsDir = "icons"
if (-not (Test-Path $iconsDir)) {
    New-Item -ItemType Directory -Path $iconsDir | Out-Null
}

# Check for icon cache (saves 15-20 seconds!)
$iconCacheFile = "icon-cache-${Schema}-${tnsSlug}.json"
$iconCacheAge = if (Test-Path $iconCacheFile) {
    (Get-Date) - (Get-Item $iconCacheFile).LastWriteTime
} else {
    [TimeSpan]::MaxValue
}

$iconDataMap = @{}
$iconCount = 0
$extractedTypeIds = @()

# Use cache if less than 7 days old
if ($iconCacheAge.TotalDays -lt 7) {
    Write-Host "  Using cached icons (age: $([math]::Round($iconCacheAge.TotalDays, 1)) days) - FAST!" -ForegroundColor Green
    try {
        $cacheData = Get-Content $iconCacheFile -Raw | ConvertFrom-Json
        foreach ($prop in $cacheData.PSObject.Properties) {
            $iconDataMap[$prop.Name] = $prop.Value
            $extractedTypeIds += [int]$prop.Name
            $iconCount++
        }
        Write-Host "  Loaded $iconCount icons from cache" -ForegroundColor Green
        $usingCache = $true
    } catch {
        Write-Warning "Failed to load icon cache: $_"
        Write-Host "  Falling back to database extraction..." -ForegroundColor Yellow
        $usingCache = $false
    }
} else {
    Write-Host "  Cache not found or expired (>7 days) - extracting from database..." -ForegroundColor Yellow
    $usingCache = $false
}

# Define file names (needed for cleanup later)
$extractIconsFile = "extract-icons-${Schema}.sql"
$iconsOutputFile = "icons-data-${Schema}.txt"

# Initialize variables needed later
$invalidIconEntries = @()
$fallbackAddedTypeIds = @()

# Only extract from database if not using cache
if (-not $usingCache) {

# Query to extract all icons as hex
# INCLUDES automatic parent class icon lookup using DERIVED_FROM
$extractIconsQuery = @"
SET PAGESIZE 0
SET LINESIZE 32767
SET LONG 10000000
SET LONGCHUNKSIZE 32767
SET FEEDBACK OFF
SET HEADING OFF
SET TRIMSPOOL ON
SET VERIFY OFF

-- Extract icons directly from DF_ICONS_DATA
SELECT
    di.TYPE_ID || '|' ||
    DBMS_LOB.GETLENGTH(di.CLASS_IMAGE) || '|' ||
    RAWTOHEX(DBMS_LOB.SUBSTR(di.CLASS_IMAGE, DBMS_LOB.GETLENGTH(di.CLASS_IMAGE), 1))
FROM $Schema.DF_ICONS_DATA di
WHERE di.CLASS_IMAGE IS NOT NULL
UNION ALL
-- Add parent class icons for TYPE_IDs that don't have their own icon
-- Uses CONNECT BY to traverse full inheritance chain and find first ancestor with icon
-- Example: RobcadStudy(177) -> LocationalStudy(108) -> Study(70) -> ShortcutFolder(69) [HAS ICON]
SELECT DISTINCT
    child_type || '|' ||
    icon_size || '|' ||
    icon_hex
FROM (
    SELECT
        child_type,
        icon_size,
        icon_hex,
        ROW_NUMBER() OVER (PARTITION BY child_type ORDER BY path_level) AS rn
    FROM (
        SELECT
            CONNECT_BY_ROOT cd.TYPE_ID AS child_type,
            cd.TYPE_ID AS ancestor_type,
            LEVEL AS path_level,
            DBMS_LOB.GETLENGTH(di.CLASS_IMAGE) AS icon_size,
            RAWTOHEX(DBMS_LOB.SUBSTR(di.CLASS_IMAGE, DBMS_LOB.GETLENGTH(di.CLASS_IMAGE), 1)) AS icon_hex
        FROM $Schema.CLASS_DEFINITIONS cd
        LEFT JOIN $Schema.DF_ICONS_DATA di ON cd.TYPE_ID = di.TYPE_ID
        WHERE di.CLASS_IMAGE IS NOT NULL
        START WITH cd.TYPE_ID NOT IN (SELECT TYPE_ID FROM $Schema.DF_ICONS_DATA WHERE CLASS_IMAGE IS NOT NULL)
        CONNECT BY PRIOR cd.DERIVED_FROM = cd.TYPE_ID
    )
)
WHERE rn = 1
ORDER BY 1;

EXIT;
"@

# Create SQL file
[System.IO.File]::WriteAllText("$PWD\$extractIconsFile", $extractIconsQuery, $utf8NoBom)

# Set environment for Oracle
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

# Run the query
Write-Host "  Running SQL query..." -ForegroundColor Gray
try {
    $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
} catch {
    Write-Warning "Failed to get credentials, using default"
    $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
}
$result = sqlplus -S $connectionString "@$extractIconsFile" 2>&1
$result | Out-File $iconsOutputFile -Encoding UTF8

# Read and parse all icons - store in memory as Base64
$allOutput = Get-Content $iconsOutputFile -Raw -Encoding UTF8
$allLines = $allOutput -split "`r?`n" | Where-Object { $_ -match '\|' }

Write-Host "  Found $($allLines.Count) icon entries" -ForegroundColor Gray

# Reset counters for database extraction
$iconCount = 0
$extractedTypeIds = @()
$iconDataMap = @{}  # Store TYPE_ID -> Base64 data URI mapping

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

if ($AllowIconFallback) {
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

    # Add fallbacks for Part-related types that might be missing
    # PmPartInstance (55) -> use PmPartPrototype icon (54) or CompoundPart (21)
    if ($iconDataMap['54'] -and -not $iconDataMap['55']) {
        $iconDataMap['55'] = $iconDataMap['54']
        $extractedTypeIds += 55
        $iconCount++
        Write-Host "    Added fallback: TYPE_ID 55 -> 54 (PartInstance -> PartPrototype parent)" -ForegroundColor Gray
    } elseif ($iconDataMap['21'] -and -not $iconDataMap['55']) {
        $iconDataMap['55'] = $iconDataMap['21']
        $extractedTypeIds += 55
        $iconCount++
        Write-Host "    Added fallback: TYPE_ID 55 -> 21 (PartInstance -> CompoundPart)" -ForegroundColor Gray
    }

    # PmToolInstance (74) -> use PmToolPrototype icon (76)
    if ($iconDataMap['76'] -and -not $iconDataMap['74']) {
        $iconDataMap['74'] = $iconDataMap['76']
        $extractedTypeIds += 74
        $iconCount++
        Write-Host "    Added fallback: TYPE_ID 74 -> 76 (ToolInstance -> ToolPrototype parent)" -ForegroundColor Gray
    }

    # PmGenericRoboticOperation (101) -> use CompoundOperation icon (19) or Process (62)
    if ($iconDataMap['19'] -and -not $iconDataMap['101']) {
        $iconDataMap['101'] = $iconDataMap['19']
        $extractedTypeIds += 101
        $iconCount++
        Write-Host "    Added fallback: TYPE_ID 101 -> 19 (GenericRoboticOperation -> CompoundOperation)" -ForegroundColor Gray
    } elseif ($iconDataMap['62'] -and -not $iconDataMap['101']) {
        $iconDataMap['101'] = $iconDataMap['62']
        $extractedTypeIds += 101
        $iconCount++
        Write-Host "    Added fallback: TYPE_ID 101 -> 62 (GenericRoboticOperation -> Process)" -ForegroundColor Gray
    }

    Write-Host "  Total icons (with fallbacks): $iconCount" -ForegroundColor Green
} else {
    Write-Host "  Icon fallback disabled - using DB icons only" -ForegroundColor Yellow
}
if ($invalidIconEntries.Count -gt 0) {
    Write-Host "  Skipped $($invalidIconEntries.Count) icons due to invalid header or size mismatch" -ForegroundColor Yellow
}

    # Save to cache for next time (if we just extracted from database)
    Write-Host "  Saving icons to cache for next run..." -ForegroundColor Gray
    try {
        $iconDataMap | ConvertTo-Json -Compress | Out-File $iconCacheFile -Encoding UTF8
        Write-Host "  Icon cache saved: $iconCacheFile" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to save icon cache: $_"
    }

} # End of if (-not $usingCache)

# Build icon type ID lookup (needed for missing icon check later)
$dbIconTypeIds = @{}
foreach ($key in $iconDataMap.Keys) {
    $dbIconTypeIds[$key] = $true
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
End-Phase

# Generate SQL query to get full tree
Start-Phase "Database Query"

# Check for tree data cache (saves ~44 seconds!)
$treeCacheFile = "tree-cache-${Schema}-${ProjectId}-${tnsSlug}.txt"
$treeCacheAge = if (Test-Path $treeCacheFile) {
    (Get-Date) - (Get-Item $treeCacheFile).LastWriteTime
} else {
    [TimeSpan]::MaxValue
}

$cleanFile = "tree-data-${Schema}-${ProjectId}-clean.txt"
$usingTreeCache = $false

# Use tree cache if less than 1 day old
if ($treeCacheAge.TotalHours -lt 24) {
    Write-Host "  Using cached tree data (age: $([math]::Round($treeCacheAge.TotalHours, 1)) hours) - FAST!" -ForegroundColor Green
    try {
        Copy-Item $treeCacheFile $cleanFile -Force
        Write-Host "  Loaded tree data from cache" -ForegroundColor Green
        $usingTreeCache = $true
    } catch {
        Write-Warning "Failed to load tree cache: $_"
        Write-Host "  Falling back to database query..." -ForegroundColor Yellow
        $usingTreeCache = $false
    }
} else {
    Write-Host "  Cache not found or expired (>24 hours) - querying database..." -ForegroundColor Yellow
    $usingTreeCache = $false
}

# Define file names (needed for cleanup later)
$sqlFile = "get-tree-${Schema}-${ProjectId}.sql"
$dataFile = "tree-data-${Schema}-${ProjectId}.txt"

# Only query database if not using cache
if (-not $usingTreeCache) {

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

-- Add PART_ table nodes (PartPrototype, CompoundPart, etc.) that are NOT in COLLECTION_
-- PART_ nodes whose parent is in COLLECTION_ table (already fetched in Level 2+ query)
-- This includes parts under libraries, collections, and other container nodes
SELECT DISTINCT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    p.OBJECT_ID || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmPart') || '|' ||
    NVL(cd.NICE_NAME, 'Part') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  -- Parent must be in COLLECTION_ table (standard hierarchy)
  AND EXISTS (
    SELECT 1 FROM $Schema.COLLECTION_ c2
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
  )
UNION ALL
-- Add PART_ children of specific library nodes (hardcoded for performance)
-- PartInstanceLibrary needs its PART_ children explicitly since it's a ghost node
-- NOTE: COWL_SILL_SIDE no longer needs hardcoding - handled by next query
SELECT DISTINCT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    p.OBJECT_ID || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmPart') || '|' ||
    NVL(cd.NICE_NAME, 'Part') || '|' ||
    TO_CHAR(NVL(cd.TYPE_ID, 21))  -- Default to TYPE_ID 21 (CompoundPart) if no mapping
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.PART_ p2 ON r.FORWARD_OBJECT_ID = p2.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd_parent ON p2.CLASS_ID = cd_parent.TYPE_ID
WHERE NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND r.FORWARD_OBJECT_ID IN (
    18143953  -- PartInstanceLibrary (ghost node)
  )
  -- Exclude reverse relationships (same filter as next query)
  AND NVL(cd_parent.TYPE_ID, 0) NOT IN (55, 56, 57, 58, 59, 60)
  AND r.FORWARD_OBJECT_ID < r.OBJECT_ID
UNION ALL
-- Add PART_ children where parent is also in PART_ table (grandchildren)
-- Get children of P702/P736 and other PART_ nodes
-- NOTE: Output all relationships, JavaScript will handle bidirectional deduplication
SELECT DISTINCT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    p.OBJECT_ID || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmPart') || '|' ||
    NVL(cd.NICE_NAME, 'Part') || '|' ||
    TO_CHAR(NVL(cd.TYPE_ID, 21))  -- Default to TYPE_ID 21 (CompoundPart) if no mapping
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
INNER JOIN $Schema.PART_ p2 ON r.FORWARD_OBJECT_ID = p2.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd_parent ON p2.CLASS_ID = cd_parent.TYPE_ID
WHERE NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID);

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

-- Add ToolPrototype nodes (equipment, layouts, units, etc.)
-- ToolPrototypes use REL_COMMON for parent relationships (not COLLECTIONS_VR_)
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    tp.OBJECT_ID || '|' ||
    NVL(tp.CAPTION_S_, NVL(tp.NAME_S_, 'Unnamed Tool')) || '|' ||
    NVL(tp.NAME_S_, 'Unnamed') || '|' ||
    NVL(tp.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class ToolPrototype') || '|' ||
    NVL(cd.NICE_NAME, 'ToolPrototype') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.TOOLPROTOTYPE_ tp
INNER JOIN $Schema.REL_COMMON r ON tp.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON tp.CLASS_ID = cd.TYPE_ID
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

-- Add ToolInstanceAspect nodes (instances attached to other objects)
-- Tool instances use ATTACHEDTO_SR_ for parent relationships
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    ti.ATTACHEDTO_SR_ || '|' ||
    ti.OBJECT_ID || '|' ||
    'Tool Instance' || '|' ||
    'Tool Instance' || '|' ||
    '' || '|' ||
    '0|' ||
    NVL(cd.NAME, 'class ToolInstanceAspect') || '|' ||
    NVL(cd.NICE_NAME, 'ToolInstanceAspect') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.TOOLINSTANCEASPECT_ ti
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON ti.CLASS_ID = cd.TYPE_ID
WHERE ti.OBJECT_ID IS NOT NULL
  AND ti.ATTACHEDTO_SR_ IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r
    INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
    WHERE c.OBJECT_ID = ti.ATTACHEDTO_SR_
      AND c.OBJECT_ID IN (
        SELECT c2.OBJECT_ID
        FROM $Schema.REL_COMMON r2
        INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
        START WITH r2.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
      )
  );

-- Add Resource nodes (robots, equipment, cables, etc. - instances under CompoundResource)
-- Resources use REL_COMMON for parent relationships, same as other nodes
-- These are the actual robot/equipment instances visible in the Siemens UI
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    res.OBJECT_ID || '|' ||
    NVL(res.CAPTION_S_, NVL(res.NAME_S_, 'Unnamed Resource')) || '|' ||
    NVL(res.NAME_S_, 'Unnamed') || '|' ||
    NVL(res.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class Resource') || '|' ||
    NVL(cd.NICE_NAME, 'Resource') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.RESOURCE_ res
INNER JOIN $Schema.REL_COMMON r ON res.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
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

-- Add Operation nodes (manufacturing operations like MOV_HOME, COMM_PICK01, etc.)
-- Operations nest up to 28+ levels deep with complex parent relationships
-- Solution: Use temp table with iterative population (avoids hierarchical query timeout)
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID

-- Create temp table for iterative object discovery
CREATE GLOBAL TEMPORARY TABLE temp_project_objects (
    OBJECT_ID NUMBER PRIMARY KEY,
    PASS_NUMBER NUMBER
) ON COMMIT PRESERVE ROWS;

-- Pass 0: Insert project root
INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
VALUES ($ProjectId, 0);

-- Pass 1: Get all direct children under project (any object type)
INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
SELECT DISTINCT rc.OBJECT_ID, 1
FROM $Schema.REL_COMMON rc
WHERE rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM temp_project_objects WHERE OBJECT_ID = rc.OBJECT_ID);

COMMIT;

-- Passes 2-30: Iteratively add child objects via REL_COMMON
DECLARE
    v_pass NUMBER := 2;
    v_rows_added NUMBER := 1;
BEGIN
    WHILE v_pass <= 30 AND v_rows_added > 0 LOOP
        INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
        SELECT DISTINCT rc.OBJECT_ID, v_pass
        FROM $Schema.REL_COMMON rc
        WHERE rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects WHERE PASS_NUMBER = v_pass - 1)
          AND NOT EXISTS (SELECT 1 FROM temp_project_objects WHERE OBJECT_ID = rc.OBJECT_ID);

        v_rows_added := SQL%ROWCOUNT;
        COMMIT;

        EXIT WHEN v_rows_added = 0;
        v_pass := v_pass + 1;
    END LOOP;
END;
/

-- Extract operations that are in project tree
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    op.OBJECT_ID || '|' ||
    NVL(op.CAPTION_S_, NVL(op.NAME_S_, 'Unnamed Operation')) || '|' ||
    NVL(op.NAME_S_, 'Unnamed') || '|' ||
    NVL(op.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class Operation') || '|' ||
    NVL(cd.NICE_NAME, 'Operation') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.OPERATION_ op
INNER JOIN $Schema.REL_COMMON r ON op.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON op.CLASS_ID = cd.TYPE_ID
WHERE op.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

-- Add MFGFEATURE_ nodes (weld points, fixtures, etc.) linked to project tree
-- MFGFEATURE_ table uses NAME1_S_ column (not NAME_S_)
-- CRITICAL: Filter on mf.OBJECT_ID (not r.FORWARD_OBJECT_ID) because temp_project_objects
-- contains the MFGFEATURE objects themselves (discovered during iterative population).
-- This matches the OPERATION_ pattern (line 909) which is the reference implementation.
-- Using r.FORWARD_OBJECT_ID would check the parent instead, missing objects already discovered.
SELECT DISTINCT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    mf.OBJECT_ID || '|' ||
    COALESCE(mf.CAPTION_S_, mf.NAME1_S_, 'Unnamed') || '|' ||
    COALESCE(mf.CAPTION_S_, mf.NAME1_S_, 'Unnamed') || '|' ||
    NVL(mf.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class MfgFeature') || '|' ||
    NVL(cd.NICE_NAME, 'MfgFeature') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.MFGFEATURE_ mf ON r.OBJECT_ID = mf.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON mf.CLASS_ID = cd.TYPE_ID
WHERE mf.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = mf.OBJECT_ID)
UNION ALL
-- Add TxProcessAssembly nodes that are in project tree (using temp table for object validation)
-- TxProcessAssembly (CLASS_ID 133) nodes are stored in PART_ table and may have PART_ or COLLECTION_ parents
-- CRITICAL: Filter on p.OBJECT_ID (not r.FORWARD_OBJECT_ID) because temp_project_objects
-- contains the TxProcessAssembly objects themselves (discovered during iterative population).
-- This matches the OPERATION_ pattern (line 909) which is the reference implementation.
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    p.OBJECT_ID || '|' ||
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
  AND p.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
UNION ALL
-- Add MODULE_ nodes (modules/subassemblies in the tree structure)
-- Module nodes are stored in MODULE_ table and use NAME1_S_ column (not NAME_S_)
-- CRITICAL: Filter on m.OBJECT_ID (not r.FORWARD_OBJECT_ID) because temp_project_objects
-- contains the MODULE objects themselves (discovered during iterative population).
-- This matches the OPERATION_ pattern (line 909) which is the reference implementation.
-- Using r.FORWARD_OBJECT_ID would check the parent instead, missing objects already discovered.
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    m.OBJECT_ID || '|' ||
    COALESCE(m.CAPTION_S_, m.NAME1_S_, 'Unnamed Module') || '|' ||
    COALESCE(m.CAPTION_S_, m.NAME1_S_, 'Unnamed Module') || '|' ||
    NVL(m.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmModule') || '|' ||
    NVL(cd.NICE_NAME, 'Module') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.MODULE_ m ON r.OBJECT_ID = m.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON m.CLASS_ID = cd.TYPE_ID
WHERE m.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = m.OBJECT_ID);

-- Clean up temp table
DROP TABLE temp_project_objects;

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

-- NOTE: TxProcessAssembly query moved earlier (before DROP temp_project_objects)
-- This allows using temp_project_objects for parent validation, which includes both COLLECTION_ and PART_ parents
-- OLD QUERY (commented out to avoid duplicates):
-- SELECT
--     '999|' ||
--     r.FORWARD_OBJECT_ID || '|' ||
--     r.OBJECT_ID || '|' ||
--     NVL(p.NAME_S_, 'Unnamed') || '|' ||
--     NVL(p.NAME_S_, 'Unnamed') || '|' ||
--     NVL(p.EXTERNALID_S_, '') || '|' ||
--     TO_CHAR(r.SEQ_NUMBER) || '|' ||
--     NVL(cd.NAME, 'class PmTxProcessAssembly') || '|' ||
--     NVL(cd.NICE_NAME, 'TxProcessAssembly') || '|' ||
--     TO_CHAR(cd.TYPE_ID)
-- FROM $Schema.REL_COMMON r
-- INNER JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
-- LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
-- WHERE p.CLASS_ID = 133  -- TxProcessAssembly TYPE_ID
--   AND EXISTS (
--     SELECT 1 FROM $Schema.REL_COMMON r2
--     INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
--     WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
--       AND c2.OBJECT_ID IN (
--         SELECT c3.OBJECT_ID
--         FROM $Schema.REL_COMMON r3
--         INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
--         START WITH r3.FORWARD_OBJECT_ID = $ProjectId
--         CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
--       )
--   )
UNION ALL
-- Add PART_ children of PartInstanceLibrary and COWL_SILL_SIDE
-- These nodes exist in PART_ table but not COLLECTION_, need explicit extraction
-- PartInstanceLibrary (18143953) is a ghost node, COWL_SILL_SIDE (18208744) is a COLLECTION_ node with PART_ children
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    p.OBJECT_ID || '|' ||
    NVL(p.NAME_S_, 'Unnamed Part') || '|' ||
    NVL(p.NAME_S_, 'Unnamed Part') || '|' ||
    NVL(p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class Part') || '|' ||
    NVL(cd.NICE_NAME, 'Part') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND r.FORWARD_OBJECT_ID IN (
    18143953,  -- PartInstanceLibrary (ghost node)
    18208744   -- COWL_SILL_SIDE
  );

-- Add PartPrototype nodes (from PARTPROTOTYPE_ table)
-- These are design prototypes for parts, children of COLLECTION_ nodes (like PartLibrary, COWL_SILL_SIDE)
-- PARTPROTOTYPE_ table contains 167,769 nodes that were previously missing!
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    pp.OBJECT_ID || '|' ||
    NVL(pp.NAME_S_, 'Unnamed PartPrototype') || '|' ||
    NVL(pp.NAME_S_, 'Unnamed') || '|' ||
    NVL(pp.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmPartPrototype') || '|' ||
    NVL(cd.NICE_NAME, 'PartPrototype') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.PARTPROTOTYPE_ pp
INNER JOIN $Schema.REL_COMMON r ON pp.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON pp.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM $Schema.COLLECTION_ c2
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM $Schema.REL_COMMON r3
        INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );

-- Add PartPrototype children of PART_ nodes
-- Some PartPrototypes have PART_ parents (not COLLECTION_)
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT DISTINCT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    pp.OBJECT_ID || '|' ||
    NVL(pp.NAME_S_, 'Unnamed PartPrototype') || '|' ||
    NVL(pp.NAME_S_, 'Unnamed') || '|' ||
    NVL(pp.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmPartPrototype') || '|' ||
    NVL(cd.NICE_NAME, 'PartPrototype') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.PARTPROTOTYPE_ pp
INNER JOIN $Schema.REL_COMMON r ON pp.OBJECT_ID = r.OBJECT_ID
INNER JOIN $Schema.PART_ p ON r.FORWARD_OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON pp.CLASS_ID = cd.TYPE_ID;

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
[System.IO.File]::WriteAllText("$PWD\$sqlFile", $sqlQuery, $utf8NoBom)

# Execute query with proper encoding handling
Write-Host "`nQuerying database..." -ForegroundColor Yellow

# Set SQL*Plus to use UTF-8 encoding
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

# Use a temporary file to capture SQL*Plus output
# SQL*Plus on Windows outputs in the console code page (usually Windows-1252)
# We need to capture it to a file and read it with the correct encoding
$tempOutputFile = "tree-data-${Schema}-${ProjectId}-raw.txt"

# Run SQL*Plus directly (simpler, more reliable)
try {
    $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
} catch {
    Write-Warning "Failed to get credentials, using default"
    $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
}
$result = sqlplus -S $connectionString "@$sqlFile" 2>&1
$result | Out-File $tempOutputFile -Encoding UTF8

# Clean the data and convert to UTF-8
End-Phase
Write-Host "Cleaning data and fixing encoding..." -ForegroundColor Yellow
Start-Phase "Data Processing"

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
[System.IO.File]::WriteAllText("$PWD\$cleanFile", $utf8Text, $utf8WithBom)

# Cleanup
if (Test-Path $tempOutputFile) { Remove-Item $tempOutputFile -Force }

    # Save to tree cache for next time
    Write-Host "  Saving tree data to cache for next run..." -ForegroundColor Gray
    try {
        Copy-Item $cleanFile $treeCacheFile -Force
        Write-Host "  Tree cache saved: $treeCacheFile" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to save tree cache: $_"
    }

} # End of if (-not $usingTreeCache)

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
$missingIconReport = "missing-icons-${Schema}-${ProjectId}-${tnsSlug}.txt"
$reportLines = @()
$missingDbTypeIdsJson = "[]"
if ($missingDbTypeIds.Count -gt 0) {
    $missingDbTypeIdsJson = "[" + (($missingDbTypeIds | Sort-Object | ForEach-Object { $_ }) -join ',') + "]"
}

if ($missingDbTypeIds.Count -gt 0) {
    $missingTypeSummary = ($missingDbTypeIds | Sort-Object) -join ', '
    if ($AllowIconFallback) {
        Write-Warning "Missing DB icon data for TYPE_IDs: $missingTypeSummary (fallback will be used where possible)"
        $reportLines += "Missing TYPE_ID icons in DB extraction (fallback will be used where possible):"
    } else {
        Write-Warning "Missing DB icon data for TYPE_IDs: $missingTypeSummary (DB-only mode)"
        $reportLines += "Missing TYPE_ID icons in DB extraction (DB-only mode):"
    }
    foreach ($typeId in ($missingDbTypeIds | Sort-Object)) {
        $info = $treeTypeInfo[$typeId]
        $reportLines += "$typeId|$($info.NiceName)|$($info.ClassName)|$($info.Count)"
    }
} else {
    Write-Host "  All TYPE_IDs in tree have DB icon data." -ForegroundColor Green
}

if ($AllowIconFallback -and $missingTypeIds.Count -gt 0) {
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

    $checkMissingIconsFile = "check-missing-icons-${Schema}-${ProjectId}-${tnsSlug}.sql"
    [System.IO.File]::WriteAllText("$PWD\$checkMissingIconsFile", $checkMissingIconsSql, $utf8NoBom)
    $missingIconsDbFile = "missing-icons-${Schema}-${ProjectId}-${tnsSlug}-db.txt"
    $dbCheckResult = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$checkMissingIconsFile" 2>&1
    $dbCheckResult | Out-File $missingIconsDbFile -Encoding UTF8
    Remove-Item $checkMissingIconsFile -ErrorAction SilentlyContinue
    Write-Host "  Wrote DB icon check to $missingIconsDbFile" -ForegroundColor Gray
}

# Extract user activity for checkout status
Write-Host "Extracting user activity..." -ForegroundColor Yellow

# Check for user activity cache (saves ~8-10 seconds!)
$userActivityCacheFile = "user-activity-cache-${Schema}-${ProjectId}-${tnsSlug}.js"
$userActivityCacheAge = if (Test-Path $userActivityCacheFile) {
    (Get-Date) - (Get-Item $userActivityCacheFile).LastWriteTime
} else {
    [TimeSpan]::MaxValue
}

$usingUserActivityCache = $false

# Define file name (needed for cleanup later)
$userActivityFile = Join-Path $env:TEMP "get-user-activity-${Schema}-${ProjectId}.sql"

# Use cache if less than 1 hour old
if ($userActivityCacheAge.TotalMinutes -lt 60) {
    Write-Host "  Using cached user activity (age: $([math]::Round($userActivityCacheAge.TotalMinutes, 1)) minutes) - FAST!" -ForegroundColor Green
    try {
        $userActivityJs = Get-Content $userActivityCacheFile -Raw
        Write-Host "  Loaded user activity from cache" -ForegroundColor Green
        $usingUserActivityCache = $true
    } catch {
        Write-Warning "Failed to load user activity cache: $_"
        Write-Host "  Falling back to database query..." -ForegroundColor Yellow
        $usingUserActivityCache = $false
    }
} else {
    Write-Host "  Cache not found or expired (>1 hour) - querying database..." -ForegroundColor Yellow
    $usingUserActivityCache = $false
}

# Only query database if not using cache
if (-not $usingUserActivityCache) {

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

[System.IO.File]::WriteAllText($userActivityFile, $userActivitySql, $utf8NoBom)

try {
    $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
} catch {
    Write-Warning "Failed to get credentials, using default"
    $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
}
$userActivityResult = & sqlplus -S $connectionString "@$userActivityFile" 2>&1

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

    # Save to user activity cache for next time
    Write-Host "  Saving user activity to cache for next run..." -ForegroundColor Gray
    try {
        $userActivityJs | Out-File $userActivityCacheFile -Encoding UTF8
        Write-Host "  User activity cache saved: $userActivityCacheFile" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to save user activity cache: $_"
    }

} # End of if (-not $usingUserActivityCache)

Remove-Item $userActivityFile -ErrorAction SilentlyContinue

# Generate HTML with in-memory icon data
End-Phase
Write-Host "Generating HTML with database icons..." -ForegroundColor Yellow
Start-Phase "HTML Generation"
$fullTreeScriptPath = Join-Path $PSScriptRoot "generate-full-tree-html.ps1"
& $fullTreeScriptPath -DataFile $cleanFile -ProjectName $ProjectName -ProjectId $ProjectId -Schema $Schema -OutputFile $OutputFile -ExtractedTypeIds $extractedTypeIdsJson -IconDataJson $iconDataJson -MissingDbTypeIds $missingDbTypeIdsJson -UserActivityJs $userActivityJs -CustomIconDir $CustomIconDir -AllowIconFallback:$AllowIconFallback

# Cleanup
Remove-Item $sqlFile -ErrorAction SilentlyContinue
Remove-Item $dataFile -ErrorAction SilentlyContinue
End-Phase

# Show timing summary
$scriptTimer.Stop()
Write-Host "`n=== Performance Summary ===" -ForegroundColor Cyan
Write-Host "Total generation time: $([math]::Round($scriptTimer.Elapsed.TotalSeconds, 2))s" -ForegroundColor White
Write-Host ""

Write-Host "`nDone! Tree saved to: $OutputFile" -ForegroundColor Green
