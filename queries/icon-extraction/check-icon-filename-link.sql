SET PAGESIZE 20
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Check if LV_ICON_ links to FILE_ which has filename
SELECT 
    cd.TYPE_ID,
    cd.NAME,
    cd.NICE_NAME,
    li.OBJECT_ID AS ICON_OBJECT_ID,
    f.FILENAME_S_ AS ICON_FILENAME
FROM DESIGN12.CLASS_DEFINITIONS cd
LEFT JOIN DESIGN12.DF_ICONS_DATA di ON cd.TYPE_ID = di.TYPE_ID
LEFT JOIN DESIGN12.LV_ICON_ li ON di.TYPE_ID = li.CLASS_ID
LEFT JOIN DESIGN12.FILE_ f ON li.FILE_ = f.OBJECT_ID
WHERE cd.NAME IN (
    'class PmProject',
    'class PmCollection',
    'class PmPartLibrary',
    'class PmMfgLibrary',
    'class PmResourceLibrary'
)
ORDER BY cd.NAME;
EXIT;