SET PAGESIZE 5000
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

PROMPT ========================================
PROMPT Full Navigation Tree for J7337_Rosslyn (DESIGN1)
PROMPT Project ID: 60
PROMPT ========================================

PROMPT 
PROMPT Root: J7337_Rosslyn (OBJECT_ID: 60)
PROMPT ========================================

-- Recursive query to build the navigation tree
WITH nav_tree AS (
    -- Root node
    SELECT 
        0 AS LEVEL_NUM,
        60 AS OBJECT_ID,
        CAST('J7337_Rosslyn' AS VARCHAR2(4000)) AS PATH,
        CAST('J7337_Rosslyn' AS VARCHAR2(4000)) AS CAPTION,
        CAST('60' AS VARCHAR2(4000)) AS ID_PATH
    FROM DUAL
    
    UNION ALL
    
    -- Children recursively
    SELECT 
        nt.LEVEL_NUM + 1,
        c.OBJECT_ID,
        nt.PATH || ' > ' || NVL(c.CAPTION_S_, c.NAME1_S_),
        NVL(c.CAPTION_S_, c.NAME1_S_),
        nt.ID_PATH || ' > ' || TO_CHAR(c.OBJECT_ID)
    FROM nav_tree nt
    INNER JOIN DESIGN1.REL_COMMON r ON r.FORWARD_OBJECT_ID = nt.OBJECT_ID
    INNER JOIN DESIGN1.COLLECTION_ c ON c.OBJECT_ID = r.OBJECT_ID
    WHERE nt.LEVEL_NUM < 10  -- Limit depth to prevent infinite loops
)
SELECT 
    LEVEL_NUM,
    LPAD(' ', LEVEL_NUM * 2) || CAPTION AS TREE_DISPLAY,
    OBJECT_ID,
    PATH AS FULL_PATH
FROM nav_tree
ORDER BY ID_PATH;

PROMPT 
PROMPT ========================================
PROMPT Direct Children (Level 1):
PROMPT ========================================
SELECT 
    c.OBJECT_ID,
    c.CAPTION_S_ AS NAME,
    c.NAME1_S_ AS ALT_NAME,
    c.EXTERNALID_S_,
    c.CHILDREN_VR_,
    c.STATUS_S_,
    r.REL_TYPE,
    r.SEQ_NUMBER
FROM DESIGN1.REL_COMMON r
INNER JOIN DESIGN1.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
WHERE r.FORWARD_OBJECT_ID = 60
ORDER BY r.SEQ_NUMBER, c.CAPTION_S_;

PROMPT 
PROMPT ========================================
PROMPT Level 2 Children (Grandchildren):
PROMPT ========================================
SELECT 
    c2.OBJECT_ID,
    c1.CAPTION_S_ AS PARENT_NAME,
    c2.CAPTION_S_ AS CHILD_NAME,
    c2.NAME1_S_ AS ALT_NAME,
    c2.EXTERNALID_S_,
    c2.CHILDREN_VR_,
    c2.STATUS_S_
FROM DESIGN1.REL_COMMON r1
INNER JOIN DESIGN1.COLLECTION_ c1 ON r1.OBJECT_ID = c1.OBJECT_ID
INNER JOIN DESIGN1.REL_COMMON r2 ON r2.FORWARD_OBJECT_ID = c1.OBJECT_ID
INNER JOIN DESIGN1.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
WHERE r1.FORWARD_OBJECT_ID = 60
ORDER BY c1.CAPTION_S_, c2.CAPTION_S_
FETCH FIRST 100 ROWS ONLY;

EXIT;
