SET PAGESIZE 50
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Get detailed info about DF_ICONS_DATA
SELECT 
    di.TYPE_ID,
    cd.NAME AS CLASS_NAME,
    cd.NICE_NAME,
    LENGTH(di.CLASS_IMAGE) AS IMAGE_SIZE_BYTES,
    SUBSTR(RAWTOHEX(SUBSTR(di.CLASS_IMAGE, 1, 2)), 1, 4) AS FIRST_BYTES_HEX
FROM DESIGN12.DF_ICONS_DATA di
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON di.TYPE_ID = cd.TYPE_ID
WHERE cd.NAME IN (
    'class Alternative',
    'class PmCollection',
    'class PmMfgLibrary',
    'class PmPartLibrary',
    'class PmProject',
    'class PmResourceLibrary'
)
ORDER BY cd.NAME;
EXIT;