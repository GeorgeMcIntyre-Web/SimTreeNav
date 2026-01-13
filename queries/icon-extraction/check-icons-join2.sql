SET PAGESIZE 30
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Join DF_ICONS_DATA with CLASS_DEFINITIONS using TYPE_ID
SELECT cd.TYPE_ID, cd.NAME, cd.NICE_NAME, 
       CASE WHEN di.TYPE_ID IS NOT NULL THEN 'YES' ELSE 'NO' END AS HAS_ICON
FROM DESIGN12.CLASS_DEFINITIONS cd
LEFT JOIN DESIGN12.DF_ICONS_DATA di ON cd.TYPE_ID = di.TYPE_ID
WHERE cd.NAME IN (
    'class Alternative',
    'class PmCollection',
    'class PmMfgLibrary',
    'class PmPartLibrary',
    'class PmProject',
    'class PmResourceLibrary',
    'class PmStudyFolder',
    'class PmVariantFilterLibrary',
    'class PmVariantSetLibrary',
    'class RobcadResourceLibrary'
)
ORDER BY cd.NAME;
EXIT;