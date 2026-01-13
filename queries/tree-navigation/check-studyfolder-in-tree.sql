SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Check if StudyFolder children are being included in the tree query
-- The current query uses: START WITH r.FORWARD_OBJECT_ID = 60
-- CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID

-- Find a specific StudyFolder and check if its children are reachable
PROMPT ========================================
PROMPT StudyFolder 197647 and its children
PROMPT ========================================
SELECT 
    'StudyFolder Info' as INFO,
    197647 as OBJECT_ID,
    c.CAPTION_S_,
    c.NAME1_S_
FROM DESIGN1.COLLECTION_ c
WHERE c.OBJECT_ID = 197647;

PROMPT 
PROMPT Direct children of StudyFolder 197647:
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
PROMPT Check if StudyFolder 197647 is reachable from project 60:
SELECT 
    'Path to StudyFolder' as INFO,
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
  AND PRIOR r.OBJECT_ID != 197647  -- Stop if we reach StudyFolder
HAVING c.OBJECT_ID = 197647
ORDER BY LEVEL
FETCH FIRST 1 ROWS ONLY;

PROMPT 
PROMPT Check if children of 197647 are reachable via the tree query:
SELECT 
    'Child reachability' as INFO,
    r_child.OBJECT_ID as CHILD_ID,
    c_child.CAPTION_S_ as CHILD_TYPE,
    c_child.NAME1_S_ as CHILD_NAME,
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM DESIGN1.REL_COMMON r2
            INNER JOIN DESIGN1.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
            START WITH r2.FORWARD_OBJECT_ID = 60
            CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
              AND LEVEL <= 15
            WHERE c2.OBJECT_ID = r_child.OBJECT_ID
        ) THEN 'YES'
        ELSE 'NO'
    END as IN_TREE
FROM DESIGN1.REL_COMMON r_child
INNER JOIN DESIGN1.COLLECTION_ c_child ON r_child.OBJECT_ID = c_child.OBJECT_ID
WHERE r_child.FORWARD_OBJECT_ID = 197647
ORDER BY r_child.SEQ_NUMBER
FETCH FIRST 20 ROWS ONLY;

EXIT;
