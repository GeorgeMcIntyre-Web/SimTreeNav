SET PAGESIZE 20
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Get sample data for classes we use
SELECT TYPE_ID, NAME, NICE_NAME, SOFT_TABLE_NAME, HARD_TABLE_NAME
FROM DESIGN12.CLASS_DEFINITIONS
WHERE NAME IN (
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
ORDER BY NAME;
EXIT;