SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Get direct children of StudyFolder 197647
PROMPT ========================================
PROMPT Direct children of StudyFolder 197647
PROMPT ========================================
SELECT 
    r.FORWARD_OBJECT_ID as PARENT_ID,
    r.OBJECT_ID as CHILD_ID,
    c.CAPTION_S_ as CHILD_TYPE,
    c.NAME1_S_ as CHILD_NAME,
    r.REL_TYPE,
    r.SEQ_NUMBER
FROM DESIGN1.REL_COMMON r
INNER JOIN DESIGN1.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
WHERE r.FORWARD_OBJECT_ID = 197647
ORDER BY r.SEQ_NUMBER;

-- Check if these children are reachable via the hierarchical query
PROMPT 
PROMPT ========================================
PROMPT Check if children are in hierarchical query result
PROMPT ========================================
-- The hierarchical query uses: START WITH r.FORWARD_OBJECT_ID = 60
-- CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
-- This should find all descendants, but let's verify

SELECT 
    r_child.OBJECT_ID as CHILD_ID,
    c_child.CAPTION_S_ as CHILD_TYPE,
    c_child.NAME1_S_ as CHILD_NAME,
    'Should be found' as EXPECTED
FROM DESIGN1.REL_COMMON r_child
INNER JOIN DESIGN1.COLLECTION_ c_child ON r_child.OBJECT_ID = c_child.OBJECT_ID
WHERE r_child.FORWARD_OBJECT_ID = 197647;

EXIT;
