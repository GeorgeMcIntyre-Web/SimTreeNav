SET PAGESIZE 20
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Get NICE_NAME for all classes we use
SELECT cd.NAME, cd.NICE_NAME
FROM DESIGN12.CLASS_DEFINITIONS cd
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