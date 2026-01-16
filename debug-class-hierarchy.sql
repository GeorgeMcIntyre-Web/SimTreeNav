SET PAGESIZE 100
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

PROMPT === Check EngineeringResourceLibrary class hierarchy ===
PROMPT === Find parent class chain for TYPE_ID 164 (RobcadResourceLibrary) ===

-- Get the class hierarchy for TYPE_ID 164
SELECT
    cd.TYPE_ID,
    cd.NAME AS CLASS_NAME,
    cd.NICE_NAME,
    cd.BASE_CLASS_ID,
    cd2.NAME AS PARENT_CLASS_NAME,
    cd2.NICE_NAME AS PARENT_NICE_NAME,
    cd2.TYPE_ID AS PARENT_TYPE_ID
FROM DESIGN12.CLASS_DEFINITIONS cd
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd2 ON cd.BASE_CLASS_ID = cd2.TYPE_ID
WHERE cd.TYPE_ID = 164;

PROMPT
PROMPT === Check which parent classes have icons ===
-- Walk up the hierarchy to find first parent with icon
WITH class_hierarchy AS (
    -- Start with TYPE_ID 164
    SELECT
        TYPE_ID,
        NAME,
        NICE_NAME,
        BASE_CLASS_ID,
        1 AS LEVEL
    FROM DESIGN12.CLASS_DEFINITIONS
    WHERE TYPE_ID = 164

    UNION ALL

    -- Recursively get parent classes
    SELECT
        cd.TYPE_ID,
        cd.NAME,
        cd.NICE_NAME,
        cd.BASE_CLASS_ID,
        ch.LEVEL + 1
    FROM DESIGN12.CLASS_DEFINITIONS cd
    INNER JOIN class_hierarchy ch ON cd.TYPE_ID = ch.BASE_CLASS_ID
    WHERE ch.LEVEL < 10  -- Prevent infinite loops
)
SELECT
    ch.LEVEL,
    ch.TYPE_ID,
    ch.NAME,
    ch.NICE_NAME,
    ch.BASE_CLASS_ID,
    CASE
        WHEN di.TYPE_ID IS NOT NULL THEN 'HAS_ICON'
        ELSE 'NO_ICON'
    END AS ICON_STATUS,
    DBMS_LOB.GETLENGTH(di.CLASS_IMAGE) AS ICON_SIZE_BYTES
FROM class_hierarchy ch
LEFT JOIN DESIGN12.DF_ICONS_DATA di ON ch.TYPE_ID = di.TYPE_ID
ORDER BY ch.LEVEL;

PROMPT
PROMPT === Check all ResourceLibrary-related classes ===
SELECT
    cd.TYPE_ID,
    cd.NAME,
    cd.NICE_NAME,
    cd.BASE_CLASS_ID,
    CASE
        WHEN di.TYPE_ID IS NOT NULL THEN 'HAS_ICON'
        ELSE 'NO_ICON'
    END AS ICON_STATUS
FROM DESIGN12.CLASS_DEFINITIONS cd
LEFT JOIN DESIGN12.DF_ICONS_DATA di ON cd.TYPE_ID = di.TYPE_ID
WHERE cd.NICE_NAME LIKE '%ResourceLibrary%'
   OR cd.NAME LIKE '%ResourceLibrary%'
ORDER BY cd.TYPE_ID;

EXIT;
