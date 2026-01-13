SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Find all StudyFolder nodes in the tree (simplified, no recursive query)
PROMPT ========================================
PROMPT StudyFolder Nodes in Project 60
PROMPT ========================================
SELECT 
    c.OBJECT_ID,
    c.CAPTION_S_,
    c.NAME1_S_,
    c.EXTERNALID_S_,
    (SELECT COUNT(*) FROM DESIGN1.REL_COMMON r2 WHERE r2.FORWARD_OBJECT_ID = c.OBJECT_ID) as CHILD_COUNT
FROM DESIGN1.COLLECTION_ c
WHERE c.CAPTION_S_ = 'StudyFolder'
ORDER BY c.OBJECT_ID
FETCH FIRST 20 ROWS ONLY;

-- Check children of StudyFolder nodes (where StudyFolder is parent)
PROMPT 
PROMPT ========================================
PROMPT Children of StudyFolder Nodes (StudyFolder as Parent)
PROMPT ========================================
SELECT 
    r.FORWARD_OBJECT_ID as STUDYFOLDER_ID,
    c_parent.CAPTION_S_ as PARENT_TYPE,
    c_parent.NAME1_S_ as PARENT_NAME,
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

-- Check REL_TYPE to understand relationship types
PROMPT 
PROMPT ========================================
PROMPT Sample StudyFolder children with REL_TYPE
PROMPT ========================================
SELECT 
    r.FORWARD_OBJECT_ID as PARENT_ID,
    c_parent.NAME1_S_ as PARENT_NAME,
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
FETCH FIRST 50 ROWS ONLY;

-- Check REL_TYPE values for StudyFolder relationships
PROMPT 
PROMPT ========================================
PROMPT REL_TYPE values for StudyFolder relationships
PROMPT ========================================
SELECT DISTINCT 
    r.REL_TYPE,
    COUNT(*) as COUNT
FROM DESIGN1.REL_COMMON r
INNER JOIN DESIGN1.COLLECTION_ c ON r.FORWARD_OBJECT_ID = c.OBJECT_ID
WHERE c.CAPTION_S_ = 'StudyFolder'
GROUP BY r.REL_TYPE
ORDER BY r.REL_TYPE;

EXIT;
