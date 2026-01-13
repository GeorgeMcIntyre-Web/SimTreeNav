SET PAGESIZE 1
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

-- Check what the actual first bytes of the BLOB are
SELECT 
    'TYPE_ID: ' || di.TYPE_ID || ' | ' ||
    'Size: ' || LENGTH(di.CLASS_IMAGE) || ' | ' ||
    'First 2 bytes (hex): ' || RAWTOHEX(SUBSTR(di.CLASS_IMAGE, 1, 2)) || ' | ' ||
    'First 2 bytes (should be 424D for BM): ' || CASE 
        WHEN RAWTOHEX(SUBSTR(di.CLASS_IMAGE, 1, 2)) = '424D' THEN 'YES - VALID BMP'
        ELSE 'NO - NOT BMP FORMAT'
    END
FROM DESIGN12.DF_ICONS_DATA di
WHERE di.TYPE_ID = 64
  AND di.CLASS_IMAGE IS NOT NULL;
EXIT;