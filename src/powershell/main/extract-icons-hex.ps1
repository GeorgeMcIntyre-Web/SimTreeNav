#!/usr/bin/env pwsh
# Extract icons from Oracle database using RAWTOHEX instead of base64
# This avoids SQL*Plus truncation issues with base64 encoding

param(
    [string]$Schema = "DESIGN12",
    [string]$TNSName = "SIEMENS_PS_DB_DB01"
)

Write-Host "Testing icon extraction using RAWTOHEX approach" -ForegroundColor Cyan
Write-Host "  Schema: $Schema" -ForegroundColor Cyan
Write-Host "  TNS: $TNSName" -ForegroundColor Cyan

# Set NLS_LANG for UTF8
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

# Create icons directory
$iconsDir = "icons"
if (-not (Test-Path $iconsDir)) {
    New-Item -ItemType Directory -Path $iconsDir | Out-Null
    Write-Host "Created icons directory: $iconsDir" -ForegroundColor Gray
}

# First, test with a single icon (TYPE_ID = 64)
Write-Host "`nStep 1: Testing with single icon (TYPE_ID = 64)..." -ForegroundColor Yellow

$testQuery = @"
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
WHERE di.TYPE_ID = 64;

EXIT;
"@

$testFile = "test-icon-hex.sql"
$testOutput = "test-icon-hex-output.txt"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText("$PWD\$testFile", $testQuery, $utf8NoBom)

# Run the query
Write-Host "  Running SQL query..." -ForegroundColor Gray
$result = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$testFile" 2>&1
$result | Out-File $testOutput -Encoding UTF8

# Read the output
$output = Get-Content $testOutput -Raw -Encoding UTF8
Write-Host "  Query completed, output length: $($output.Length) characters" -ForegroundColor Gray

# Parse the output
$lines = $output -split "`r?`n" | Where-Object { $_ -match '\|' }

if ($lines.Count -eq 0) {
    Write-Host "  ERROR: No data returned from query" -ForegroundColor Red
    Write-Host "  Raw output:" -ForegroundColor Red
    Write-Host $output -ForegroundColor DarkGray
    exit 1
}

$line = $lines[0].Trim()
if ($line -match '^(\d+)\|(\d+)\|([0-9A-Fa-f]+)$') {
    $typeId = $matches[1]
    $expectedSize = [int]$matches[2]
    $hexData = $matches[3]

    Write-Host "  TYPE_ID: $typeId" -ForegroundColor Gray
    Write-Host "  Expected size: $expectedSize bytes" -ForegroundColor Gray
    Write-Host "  Hex data length: $($hexData.Length) characters (should be $($expectedSize * 2))" -ForegroundColor Gray

    # Convert hex to bytes
    $iconBytes = New-Object byte[] ($hexData.Length / 2)
    for ($i = 0; $i -lt $hexData.Length; $i += 2) {
        $iconBytes[$i / 2] = [Convert]::ToByte($hexData.Substring($i, 2), 16)
    }

    Write-Host "  Converted to $($iconBytes.Length) bytes" -ForegroundColor Gray

    # Verify BMP header
    if ($iconBytes.Length -ge 2) {
        $header = [System.Text.Encoding]::ASCII.GetString($iconBytes[0..1])
        Write-Host "  BMP header: '$header' (should be 'BM')" -ForegroundColor $(if ($header -eq 'BM') { 'Green' } else { 'Red' })

        if ($header -eq 'BM') {
            $iconFile = "$iconsDir\icon_${typeId}.bmp"
            [System.IO.File]::WriteAllBytes($iconFile, $iconBytes)
            Write-Host "  SUCCESS: Saved icon to $iconFile" -ForegroundColor Green

            # Verify file
            $fileSize = (Get-Item $iconFile).Length
            Write-Host "  File size on disk: $fileSize bytes" -ForegroundColor Gray

            if ($fileSize -eq $expectedSize) {
                Write-Host "  File size matches expected size!" -ForegroundColor Green
            } else {
                Write-Host "  WARNING: File size mismatch!" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ERROR: Invalid BMP header" -ForegroundColor Red
        }
    }
} else {
    Write-Host "  ERROR: Could not parse output line: $line" -ForegroundColor Red
}

# Step 2: Extract all icons
Write-Host "`nStep 2: Extracting all icons from database..." -ForegroundColor Yellow

$allIconsQuery = @"
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

$allIconsFile = "extract-all-icons-hex.sql"
$allIconsOutput = "all-icons-hex-output.txt"
[System.IO.File]::WriteAllText("$PWD\$allIconsFile", $allIconsQuery, $utf8NoBom)

# Run the query
Write-Host "  Running SQL query for all icons..." -ForegroundColor Gray
$result = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$allIconsFile" 2>&1
$result | Out-File $allIconsOutput -Encoding UTF8

# Read and parse all icons
$allOutput = Get-Content $allIconsOutput -Raw -Encoding UTF8
$allLines = $allOutput -split "`r?`n" | Where-Object { $_ -match '\|' }

Write-Host "  Found $($allLines.Count) icon entries" -ForegroundColor Gray

$successCount = 0
$failCount = 0
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
                    $successCount++
                    $extractedTypeIds += $typeId
                    Write-Host "  Extracted TYPE_ID $typeId ($expectedSize bytes)" -ForegroundColor Gray
                } else {
                    Write-Warning "Invalid icon for TYPE_ID $typeId (header: '$header', size: $($iconBytes.Length) vs $expectedSize)"
                    $failCount++
                }
            }
        } catch {
            Write-Warning "Failed to extract TYPE_ID $typeId : $_"
            $failCount++
        }
    }
}

Write-Host "`nExtraction Summary:" -ForegroundColor Cyan
Write-Host "  Successfully extracted: $successCount icons" -ForegroundColor Green
Write-Host "  Failed: $failCount icons" -ForegroundColor $(if ($failCount -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Extracted TYPE_IDs: $($extractedTypeIds -join ', ')" -ForegroundColor Gray

# Save list of extracted TYPE_IDs to a file for use by other scripts
$extractedTypeIds | ConvertTo-Json | Out-File "extracted-type-ids.json" -Encoding UTF8
Write-Host "`nSaved extracted TYPE_IDs to extracted-type-ids.json" -ForegroundColor Cyan

# Cleanup
Remove-Item $testFile -ErrorAction SilentlyContinue
Remove-Item $allIconsFile -ErrorAction SilentlyContinue

Write-Host "`nDone! Icons saved to $iconsDir directory" -ForegroundColor Green
