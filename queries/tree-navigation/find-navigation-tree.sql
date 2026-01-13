SET PAGESIZE 1000
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

PROMPT ========================================
PROMPT Navigation Tree for J7337_Rosslyn (DESIGN1)
PROMPT Project ID: 60
PROMPT ========================================

PROMPT 
PROMPT 1. Root Collection (Project Root):
PROMPT ========================================
SELECT 
    OBJECT_ID,
    OBJECT_VERSION_ID,
    EXTERNALID_S_,
    CAPTION_S_,
    NAME1_S_,
    STATUS_S_,
    CHILDREN_VR_,
    CREATEDBY_S_,
    LASTMODIFIEDBY_S_,
    MODIFICATIONDATE_DA_
FROM DESIGN1.COLLECTION_
WHERE OBJECT_ID = 60;

PROMPT 
PROMPT 2. Finding how children are stored - checking REL_COMMON for relationships:
PROMPT ========================================
SELECT 
    RELATIONSHIP_ID,
    FORWARD_OBJECT_ID,
    REVERSE_OBJECT_ID,
    RELATIONSHIP_TYPE
FROM DESIGN1.REL_COMMON
WHERE FORWARD_OBJECT_ID = 60
FETCH FIRST 20 ROWS ONLY;

PROMPT 
PROMPT 3. Checking for tree/hierarchy tables:
PROMPT ========================================
SELECT table_name FROM dba_tables 
WHERE owner='DESIGN1' 
  AND (table_name LIKE '%TREE%' 
       OR table_name LIKE '%HIER%'
       OR table_name LIKE '%NODE%'
       OR table_name LIKE '%PARENT%'
       OR table_name LIKE '%CHILD%')
ORDER BY table_name;

PROMPT 
PROMPT 4. Checking COLLECTIONS_VR_ reference (vector reference):
PROMPT ========================================
-- The CHILDREN_VR_ column might reference a vector table
SELECT column_name, data_type FROM dba_tab_columns
WHERE owner='DESIGN1' AND table_name='COLLECTION_'
  AND column_name LIKE '%VR%' OR column_name LIKE '%CHILD%'
ORDER BY column_id;

PROMPT 
PROMPT 5. Sample collections that might be children:
PROMPT ========================================
SELECT 
    OBJECT_ID,
    CAPTION_S_,
    NAME1_S_,
    EXTERNALID_S_,
    CHILDREN_VR_
FROM DESIGN1.COLLECTION_
WHERE OBJECT_ID IN (
    SELECT DISTINCT REVERSE_OBJECT_ID 
    FROM DESIGN1.REL_COMMON 
    WHERE FORWARD_OBJECT_ID = 60
    FETCH FIRST 50 ROWS ONLY
)
ORDER BY OBJECT_ID
FETCH FIRST 30 ROWS ONLY;

EXIT;
