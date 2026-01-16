SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON

PROMPT ========================================
PROMPT TOOLPROTOTYPE_ Table Structure
PROMPT ========================================

SELECT
    COLUMN_NAME,
    DATA_TYPE,
    DATA_LENGTH,
    NULLABLE,
    COLUMN_ID
FROM ALL_TAB_COLUMNS
WHERE TABLE_NAME = 'TOOLPROTOTYPE_'
  AND OWNER = 'DESIGN12'
ORDER BY COLUMN_ID;

PROMPT
PROMPT ========================================
PROMPT TOOLPROTOTYPE_ Sample Data
PROMPT ========================================

SELECT *
FROM DESIGN12.TOOLPROTOTYPE_
WHERE ROWNUM <= 3;

PROMPT
PROMPT ========================================
PROMPT TOOLINSTANCEASPECT_ Table Structure
PROMPT ========================================

SELECT
    COLUMN_NAME,
    DATA_TYPE,
    DATA_LENGTH,
    NULLABLE,
    COLUMN_ID
FROM ALL_TAB_COLUMNS
WHERE TABLE_NAME = 'TOOLINSTANCEASPECT_'
  AND OWNER = 'DESIGN12'
ORDER BY COLUMN_ID;

PROMPT
PROMPT ========================================
PROMPT TOOLINSTANCEASPECT_ Sample Data
PROMPT ========================================

SELECT *
FROM DESIGN12.TOOLINSTANCEASPECT_
WHERE ROWNUM <= 3;

PROMPT
PROMPT ========================================
PROMPT Tool Count in FORD_DEARBORN Project
PROMPT ========================================

SELECT
    'ToolPrototype' as NODE_TYPE,
    COUNT(*) as COUNT
FROM DESIGN12.TOOLPROTOTYPE_ tp
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.COLLECTION_ c
    START WITH c.OBJECT_ID = 18140190
    CONNECT BY NOCYCLE PRIOR c.OBJECT_ID = parent_in_rel_common
    WHERE c.OBJECT_ID = tp.OBJECT_ID
)
UNION ALL
SELECT
    'ToolInstanceAspect' as NODE_TYPE,
    COUNT(*) as COUNT
FROM DESIGN12.TOOLINSTANCEASPECT_ ti
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.COLLECTION_ c
    START WITH c.OBJECT_ID = 18140190
    CONNECT BY NOCYCLE PRIOR c.OBJECT_ID = parent_in_rel_common
    WHERE c.OBJECT_ID = ti.OBJECT_ID
);

PROMPT
PROMPT ========================================
PROMPT Related Tool Tables Available
PROMPT ========================================

SELECT TABLE_NAME
FROM ALL_TABLES
WHERE OWNER = 'DESIGN12'
  AND (TABLE_NAME LIKE 'TOOL%' OR TABLE_NAME LIKE '%TOOL%')
ORDER BY TABLE_NAME;

PROMPT
PROMPT ========================================
PROMPT TYPE_ID 164 Icon Data Check
PROMPT ========================================

SELECT
    di.TYPE_ID,
    DBMS_LOB.GETLENGTH(di.CLASS_IMAGE) as ICON_LENGTH,
    cd.NAME as CLASS_NAME,
    cd.NICE_NAME
FROM DESIGN12.DF_ICONS_DATA di
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON di.TYPE_ID = cd.TYPE_ID
WHERE di.TYPE_ID IN (72, 164, 177)
ORDER BY di.TYPE_ID;

EXIT;
