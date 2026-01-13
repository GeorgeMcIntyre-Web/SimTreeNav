SET PAGESIZE 20
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Check LV_ICON_ table structure and how it links
SELECT 
    li.OBJECT_ID,
    li.CLASS_ID,
    li.FILE_,
    f.FILENAME_S_,
    cd.NAME AS CLASS_NAME
FROM DESIGN12.LV_ICON_ li
LEFT JOIN DESIGN12.FILE_ f ON li.FILE_ = f.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON li.CLASS_ID = cd.TYPE_ID
WHERE cd.NAME IN (
    'class PmProject',
    'class PmCollection',
    'class PmPartLibrary',
    'class PmMfgLibrary'
)
ORDER BY cd.NAME;
EXIT;