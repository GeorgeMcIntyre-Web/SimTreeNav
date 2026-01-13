SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Simple check: Does StudyFolder 197647 have children and are they in the tree?
PROMPT ========================================
PROMPT StudyFolder 197647 Children
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

PROMPT 
PROMPT ========================================
PROMPT Check if child 197663 appears in tree data
PROMPT ========================================
-- Check if this child would be found by our tree query
SELECT 
    'Child 197663' as CHECK_NODE,
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM DESIGN1.REL_COMMON r2
            INNER JOIN DESIGN1.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
            START WITH r2.FORWARD_OBJECT_ID = 60
            CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
            WHERE c2.OBJECT_ID = 197663
        ) THEN 'FOUND'
        ELSE 'MISSING'
    END as STATUS
FROM DUAL;

PROMPT 
PROMPT ========================================
PROMPT Path from 60 to StudyFolder 197647
PROMPT ========================================
SELECT 
    LEVEL,
    PRIOR c.OBJECT_ID as PARENT_ID,
    c.OBJECT_ID,
    c.CAPTION_S_,
    c.NAME1_S_
FROM DESIGN1.REL_COMMON r
INNER JOIN DESIGN1.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
START WITH r.FORWARD_OBJECT_ID = 60
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
  AND LEVEL <= 10
  AND PRIOR r.OBJECT_ID != 197647
HAVING c.OBJECT_ID = 197647
FETCH FIRST 1 ROWS ONLY;

EXIT;
