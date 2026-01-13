SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Find all StudyFolder nodes and their children
-- Then check which children are NOT in the tree

PROMPT ========================================
PROMPT All StudyFolder children
PROMPT ========================================
SELECT 
    r.FORWARD_OBJECT_ID as STUDYFOLDER_ID,
    r.OBJECT_ID as CHILD_ID,
    c_child.CAPTION_S_ as CHILD_TYPE,
    c_child.NAME1_S_ as CHILD_NAME,
    r.REL_TYPE,
    r.SEQ_NUMBER
FROM DESIGN1.REL_COMMON r
INNER JOIN DESIGN1.COLLECTION_ c_parent ON r.FORWARD_OBJECT_ID = c_parent.OBJECT_ID
INNER JOIN DESIGN1.COLLECTION_ c_child ON r.OBJECT_ID = c_child.OBJECT_ID
WHERE c_parent.CAPTION_S_ = 'StudyFolder'
ORDER BY r.FORWARD_OBJECT_ID, r.SEQ_NUMBER
FETCH FIRST 100 ROWS ONLY;

EXIT;
