# Icon Extraction from Oracle Database - Attempts and Issues

## Problem Statement
We need to extract icon images (BMP files) stored as BLOBs in the Oracle database table `DF_ICONS_DATA.CLASS_IMAGE` and display them in a web-based navigation tree viewer. The icons are associated with node types via `TYPE_ID` which links to `CLASS_DEFINITIONS.TYPE_ID`.

## Database Structure
- **Table**: `DF_ICONS_DATA` (schema: DESIGN12, DESIGN1, etc.)
- **Key Column**: `TYPE_ID` (links to `CLASS_DEFINITIONS.TYPE_ID`)
- **Icon Data**: `CLASS_IMAGE` (BLOB column containing BMP image data)
- **Icon Sizes**: Typically 1000-3000 bytes per icon
- **Total Icons**: ~95 TYPE_IDs have icons in the database

## What We Know Works
1. ✅ **NICE_NAME Mapping**: We have a fallback system that maps class names to icon files from `C:\Program Files\Tecnomatix_2301.0\eMPower\InitData\DefaultCust\*.bmp`
2. ✅ **TYPE_ID Querying**: We can successfully query `TYPE_ID` from `CLASS_DEFINITIONS` and pass it to JavaScript
3. ✅ **Icon File Structure**: The icons should be valid BMP files starting with 'BM' header (0x42 0x4D)
4. ✅ **JavaScript Logic**: The rendering code correctly tries to load `icon_TYPEID.bmp` files and falls back to NICE_NAME mapping

## What's Failing
❌ **Base64 Extraction**: All attempts to extract BLOB data as base64 from Oracle have failed due to SQL*Plus truncation or encoding issues.

## Attempts Made

### Attempt 1: Direct UTL_ENCODE.BASE64_ENCODE with SQL*Plus
**Query:**
```sql
SELECT 
    di.TYPE_ID || '|' ||
    LENGTH(di.CLASS_IMAGE) || '|' ||
    UTL_ENCODE.BASE64_ENCODE(di.CLASS_IMAGE)
FROM DESIGN12.DF_ICONS_DATA di
WHERE di.CLASS_IMAGE IS NOT NULL
ORDER BY di.TYPE_ID;
```

**Settings Used:**
- `SET LINESIZE 32767`
- `SET LONG 1000000`
- `SET LONGCHUNKSIZE 1000000`
- `SET PAGESIZE 0`

**Result**: ❌ Base64 output truncated at exactly 492 characters (should be ~1780 for a 1334-byte icon)

### Attempt 2: SPOOL to File
**Approach**: Used SQL*Plus SPOOL to write output directly to file to avoid console encoding issues.

**Query:**
```sql
SPOOL icons-data-DESIGN12.txt
[Same SELECT query as Attempt 1]
SPOOL OFF
```

**Result**: ❌ Still truncated at 492 characters. File size was 223,865 characters total, but each icon's base64 was incomplete.

### Attempt 3: Extract Icons One at a Time
**Approach**: Extract each TYPE_ID individually in separate SQL*Plus calls to avoid line length limits.

**Result**: ❌ Still truncated at 492 characters per icon. SQL*Plus appears to have a hard limit on base64 output length.

### Attempt 4: DBMS_LOB.SUBSTR with LISTAGG
**Approach**: Use `DBMS_LOB.SUBSTR` to get base64 in 4000-char chunks and concatenate with `LISTAGG`.

**Query:**
```sql
SELECT 
    'TYPE_ID|' ||
    LENGTH(di.CLASS_IMAGE) || '|' ||
    LISTAGG(
        DBMS_LOB.SUBSTR(
            UTL_ENCODE.BASE64_ENCODE(di.CLASS_IMAGE),
            4000,
            (LEVEL - 1) * 4000 + 1
        ),
        ''
    ) WITHIN GROUP (ORDER BY LEVEL)
FROM DESIGN12.DF_ICONS_DATA di
WHERE di.TYPE_ID = ?
CONNECT BY LEVEL <= CEIL(LENGTH(UTL_ENCODE.BASE64_ENCODE(di.CLASS_IMAGE)) / 4000)
GROUP BY di.TYPE_ID, LENGTH(di.CLASS_IMAGE);
```

**Result**: ❌ Query syntax errors or still truncation issues.

### Attempt 5: Validation and Error Handling
**Approach**: Added BMP header validation (`'BM'` check) and better error messages.

**Result**: ✅ Validation works correctly - catches all corrupted icons. ❌ But icons are still corrupted because base64 is truncated.

## Current State

### Working Code
1. **PowerShell Script**: `generate-tree-html.ps1` - Has icon extraction logic that:
   - Queries TYPE_IDs from `DF_ICONS_DATA`
   - Attempts to extract base64-encoded BLOBs
   - Validates BMP headers before saving
   - Creates list of successfully extracted TYPE_IDs

2. **JavaScript Code**: `generate-full-tree-html.ps1` - Has logic that:
   - Receives list of extracted TYPE_IDs
   - Only tries to load `icon_TYPEID.bmp` if TYPE_ID is in the extracted list
   - Falls back to NICE_NAME mapping if icon wasn't extracted
   - Handles icon loading errors gracefully

### Current Issue
**Root Cause**: SQL*Plus is truncating `UTL_ENCODE.BASE64_ENCODE()` output at 492 characters, regardless of:
- `SET LONG` values (tried up to 1,000,000)
- `SET LINESIZE` values (tried up to 32,767)
- SPOOL vs. direct output
- Single vs. batch extraction

**Evidence**:
- Icon size: 1334 bytes
- Expected base64 length: ~1780 characters
- Actual base64 length: 492 characters (exactly)
- Decoded result: Invalid BMP header ('?^' instead of 'BM')

## Alternative Approaches Not Yet Tried

### Option 1: Use Oracle SQL Developer or Other Tools
- Use Oracle SQL Developer's export functionality
- Use Oracle Data Pump
- Use ODP.NET or other Oracle drivers that handle BLOBs better

### Option 2: PL/SQL with UTL_FILE
- Create a PL/SQL procedure that writes BLOBs directly to files
- Requires Oracle directory object (may need DBA privileges)
- Would bypass SQL*Plus entirely

### Option 3: Use RAWTOHEX Instead of Base64
- Extract BLOB as hexadecimal string
- Convert hex to bytes in PowerShell
- Might avoid base64 encoding issues

### Option 4: Use Oracle's DBMS_LOB Package
- Use `DBMS_LOB.READ` to read BLOB in chunks
- Convert each chunk to base64 separately
- Concatenate in PowerShell

### Option 5: Use External Tool
- Use `expdp` (Data Pump) to export BLOBs
- Use Python with `cx_Oracle` or `oracledb` library
- Use Java with JDBC (better BLOB handling)

## Files Involved

1. **`generate-tree-html.ps1`** (lines ~28-130):
   - Contains icon extraction logic
   - Currently uses SQL*Plus with UTL_ENCODE.BASE64_ENCODE
   - Validates BMP headers before saving
   - Creates `extractedTypeIds` list

2. **`generate-full-tree-html.ps1`** (lines ~248-250, ~471-489, ~682-710):
   - JavaScript code that uses extracted icons
   - Has `extractedTypeIds` Set to track which icons were extracted
   - Falls back to NICE_NAME mapping

3. **`icons\` directory**:
   - Should contain `icon_TYPEID.bmp` files
   - Currently empty or contains corrupted files

## Test Queries That Work

These queries successfully return data (but base64 is truncated):

```sql
-- Get TYPE_IDs with icons
SELECT DISTINCT TO_CHAR(di.TYPE_ID)
FROM DESIGN12.DF_ICONS_DATA di
WHERE di.CLASS_IMAGE IS NOT NULL
ORDER BY di.TYPE_ID;
-- Returns: 14, 16, 18, 19, 20, 21, 22, 23, 39, 41, 42, 44, 45, 46, 47, 48, 50, 51, 52, 53, 54, 57, 58, 62, 63, 64, 65, 68, 69, 73, 76, 80, 83, 88, 90, 91, 92, 93, 94, 96, 97, 98, 103, 104, 107, 111, 113, 114, 119, 120, 121, 122, 126, 131, 133, 134, 135, 141, 157, 158, 159, 160, 161, 162, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194, 195, 197, 198, 199, 204, 206, 207, 208, 251, 321, 322

-- Get icon size
SELECT LENGTH(di.CLASS_IMAGE) AS ICON_SIZE
FROM DESIGN12.DF_ICONS_DATA di
WHERE di.TYPE_ID = 64;
-- Returns: 1334 bytes (typical size)

-- Check if BLOB starts with 'BM' (BMP header)
SELECT 
    CASE 
        WHEN RAWTOHEX(SUBSTR(di.CLASS_IMAGE, 1, 2)) = '424D' THEN 'YES - VALID BMP'
        ELSE 'NO - NOT BMP FORMAT'
    END AS IS_BMP
FROM DESIGN12.DF_ICONS_DATA di
WHERE di.TYPE_ID = 64;
-- (This query hasn't been successfully run yet - need to verify)
```

## Recommended Next Steps

1. **Verify BLOB Format**: First confirm that the BLOBs actually contain valid BMP data by checking the first 2 bytes (should be 0x42 0x4D = 'BM').

2. **Try RAWTOHEX Approach**: Instead of base64, extract as hexadecimal:
   ```sql
   SELECT RAWTOHEX(di.CLASS_IMAGE) FROM DF_ICONS_DATA WHERE TYPE_ID = 64;
   ```
   Then convert hex to bytes in PowerShell.

3. **Use Python with oracledb**: Python's `oracledb` library handles BLOBs much better than SQL*Plus:
   ```python
   import oracledb
   conn = oracledb.connect(user="sys", password="...", dsn="...", mode=oracledb.SYSDBA)
   cursor = conn.cursor()
   cursor.execute("SELECT CLASS_IMAGE FROM DESIGN12.DF_ICONS_DATA WHERE TYPE_ID = 64")
   blob_data = cursor.fetchone()[0].read()
   with open('icon_64.bmp', 'wb') as f:
       f.write(blob_data)
   ```

4. **Use PL/SQL with UTL_FILE** (if directory object exists):
   ```sql
   DECLARE
       v_file UTL_FILE.FILE_TYPE;
       v_blob BLOB;
       v_buffer RAW(32767);
       v_amount BINARY_INTEGER := 32767;
       v_pos INTEGER := 1;
   BEGIN
       SELECT CLASS_IMAGE INTO v_blob FROM DF_ICONS_DATA WHERE TYPE_ID = 64;
       v_file := UTL_FILE.FOPEN('ICONS_DIR', 'icon_64.bmp', 'WB', 32767);
       WHILE v_pos <= DBMS_LOB.GETLENGTH(v_blob) LOOP
           v_amount := LEAST(32767, DBMS_LOB.GETLENGTH(v_blob) - v_pos + 1);
           DBMS_LOB.READ(v_blob, v_amount, v_pos, v_buffer);
           UTL_FILE.PUT_RAW(v_file, v_buffer, TRUE);
           v_pos := v_pos + v_amount;
       END LOOP;
       UTL_FILE.FCLOSE(v_file);
   END;
   ```

5. **Fallback Solution**: If extraction continues to fail, enhance the NICE_NAME mapping to cover all node types. The mapping currently works but may not cover all custom icons.

## Environment Details
- **OS**: Windows 10
- **Database**: Oracle (version unknown, accessed via TNS: SIEMENS_PS_DB_DB01)
- **Connection**: SQL*Plus with SYSDBA privileges
- **Schema**: DESIGN12 (and others: DESIGN1, DESIGN4, etc.)
- **PowerShell Version**: 7.x
- **Encoding**: UTF-8 (NLS_LANG = AMERICAN_AMERICA.UTF8)

## Key Learnings
1. SQL*Plus has limitations with large base64 strings, even with `SET LONG` set high
2. The truncation happens at exactly 492 characters consistently
3. SPOOL doesn't help - the truncation happens before spooling
4. BMP header validation works correctly and catches all corrupted files
5. The JavaScript fallback system works well - nodes display with NICE_NAME-mapped icons when database icons fail

## Current Workaround
The system currently works by:
1. Attempting to extract icons (fails silently)
2. Using NICE_NAME mapping for all icons
3. No database icons are displayed, but all nodes have appropriate icons from the file system

This is functional but not ideal - users want to see their custom database icons.
