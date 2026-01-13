SET PAGESIZE 100
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON

PROMPT ========================================
PROMPT Process Simulation Project Names in DESIGN1
PROMPT ========================================

-- Get project names by matching DFPROJECT.PROJECTID with COLLECTION_.OBJECT_ID
SELECT 
    p.PROJECTID,
    c.CAPTION_S_ AS PROJECT_NAME,
    c.NAME1_S_ AS PROJECT_NAME_ALT,
    c.EXTERNALID_S_ AS EXTERNAL_ID,
    c.STATUS_S_ AS STATUS
FROM DESIGN1.DFPROJECT p
LEFT JOIN DESIGN1.COLLECTION_ c ON p.PROJECTID = c.OBJECT_ID
ORDER BY p.PROJECTID;

PROMPT 
PROMPT ========================================
PROMPT Alternative: All top-level collections (potential projects)
PROMPT ========================================
SELECT DISTINCT
    OBJECT_ID,
    CAPTION_S_ AS PROJECT_NAME,
    NAME1_S_,
    EXTERNALID_S_
FROM DESIGN1.COLLECTION_
WHERE CAPTION_S_ IS NOT NULL
ORDER BY OBJECT_ID
FETCH FIRST 10 ROWS ONLY;

EXIT;
