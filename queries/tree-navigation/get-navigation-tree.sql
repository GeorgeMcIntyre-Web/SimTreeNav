SET PAGESIZE 1000
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

PROMPT ========================================
PROMPT Navigation Tree for J7337_Rosslyn (DESIGN1)
PROMPT Project ID: 60, CHILDREN_VR_: 6
PROMPT ========================================

PROMPT 
PROMPT 1. REL_COMMON table structure:
PROMPT ========================================
SELECT column_name, data_type FROM dba_tab_columns
WHERE owner='DESIGN1' AND table_name='REL_COMMON'
ORDER BY column_id
FETCH FIRST 20 ROWS ONLY;

PROMPT 
PROMPT 2. Finding children via REL_COMMON (forward relationships from project):
PROMPT ========================================
SELECT 
    RELATIONSHIP_ID,
    FORWARD_OBJECT_ID,
    REVERSE_OBJECT_ID
FROM DESIGN1.REL_COMMON
WHERE FORWARD_OBJECT_ID = 60
FETCH FIRST 50 ROWS ONLY;

PROMPT 
PROMPT 3. Checking vector table for CHILDREN_VR_ = 6:
PROMPT ========================================
-- CHILDREN_VR_ = 6 might reference a vector table
SELECT table_name FROM dba_tables 
WHERE owner='DESIGN1' 
  AND (table_name LIKE '%VECTOR%' OR table_name LIKE '%VR%' OR table_name LIKE '%VEC%')
ORDER BY table_name;

PROMPT 
PROMPT 4. Checking SUB_TREE table structure:
PROMPT ========================================
SELECT column_name, data_type FROM dba_tab_columns
WHERE owner='DESIGN1' AND table_name='SUB_TREE'
ORDER BY column_id;

PROMPT 
PROMPT 5. Sample from SUB_TREE for project 60:
PROMPT ========================================
SELECT * FROM DESIGN1.SUB_TREE
WHERE OBJECT_ID = 60
FETCH FIRST 20 ROWS ONLY;

PROMPT 
PROMPT 6. Direct children collections (via REL_COMMON):
PROMPT ========================================
SELECT 
    c.OBJECT_ID,
    c.CAPTION_S_,
    c.NAME1_S_,
    c.EXTERNALID_S_,
    c.CHILDREN_VR_,
    c.STATUS_S_
FROM DESIGN1.COLLECTION_ c
WHERE c.OBJECT_ID IN (
    SELECT DISTINCT REVERSE_OBJECT_ID
    FROM DESIGN1.REL_COMMON
    WHERE FORWARD_OBJECT_ID = 60
)
ORDER BY c.OBJECT_ID
FETCH FIRST 50 ROWS ONLY;

EXIT;
