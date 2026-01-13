SET PAGESIZE 10
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Get sample data from CLASS_DEFINITIONS for classes we use
SELECT TYPE_ID, NAME, NICE_NAME
FROM DESIGN12.CLASS_DEFINITIONS
WHERE NAME IN ('class PmProject', 'class PmCollection', 'class PmPartLibrary', 'class PmMfgLibrary', 'class RobcadResourceLibrary')
ORDER BY NAME;
EXIT;