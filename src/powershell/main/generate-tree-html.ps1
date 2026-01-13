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
    
    [string]$OutputFile = "navigation-tree.html"
)

Write-Host "Generating tree for:" -ForegroundColor Yellow
Write-Host "  TNS Name: $TNSName" -ForegroundColor Cyan
Write-Host "  Schema: $Schema" -ForegroundColor Cyan
Write-Host "  Project: $ProjectName (ID: $ProjectId)" -ForegroundColor Cyan

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

# Read and parse all icons
$allOutput = Get-Content $iconsOutputFile -Raw -Encoding UTF8
$allLines = $allOutput -split "`r?`n" | Where-Object { $_ -match '\|' }

Write-Host "  Found $($allLines.Count) icon entries" -ForegroundColor Gray

$iconCount = 0
$extractedTypeIds = @()

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

            # Verify BMP header
            if ($iconBytes.Length -ge 2) {
                $header = [System.Text.Encoding]::ASCII.GetString($iconBytes[0..1])

                if ($header -eq 'BM' -and $iconBytes.Length -eq $expectedSize) {
                    $iconFile = "$iconsDir\icon_${typeId}.bmp"
                    [System.IO.File]::WriteAllBytes($iconFile, $iconBytes)
                    $iconCount++
                    $extractedTypeIds += $typeId
                    Write-Host "  Extracted TYPE_ID $typeId ($expectedSize bytes)" -ForegroundColor Gray
                } else {
                    Write-Warning "Invalid icon for TYPE_ID $typeId (header: '$header', size: $($iconBytes.Length) vs $expectedSize)"
                }
            }
        } catch {
            Write-Warning "Failed to extract TYPE_ID $typeId : $_"
        }
    }
}

Write-Host "  Successfully extracted: $iconCount icons" -ForegroundColor Green

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
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
    NVL(c.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
LEFT JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
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
# Windows-1252 properly handles German characters (ö, ä, ü, ß)
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
Write-Host "  Converting encoding (Windows-1252 → UTF-8)..." -ForegroundColor Gray
$allText = $cleanLines -join "`r`n"

# Convert: Windows-1252 bytes → UTF-8 bytes → UTF-8 string
$sourceBytes = $windows1252.GetBytes($allText)
$utf8Bytes = [System.Text.Encoding]::Convert($windows1252, [System.Text.Encoding]::UTF8, $sourceBytes)
$utf8Text = [System.Text.Encoding]::UTF8.GetString($utf8Bytes)

# Write cleaned data as UTF-8 with BOM
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
[System.IO.File]::WriteAllText("$PWD\$cleanFile", $utf8Text, $utf8WithBom)

# Cleanup
if (Test-Path $tempOutputFile) { Remove-Item $tempOutputFile -Force }

# Generate HTML with extracted TYPE_IDs
Write-Host "Generating HTML with database icons..." -ForegroundColor Yellow
& ".\generate-full-tree-html.ps1" -DataFile $cleanFile -ProjectName $ProjectName -ProjectId $ProjectId -Schema $Schema -OutputFile $OutputFile -ExtractedTypeIds $extractedTypeIdsJson

# Cleanup
Remove-Item $sqlFile -ErrorAction SilentlyContinue
Remove-Item $dataFile -ErrorAction SilentlyContinue

Write-Host "`nDone! Tree saved to: $OutputFile" -ForegroundColor Green
