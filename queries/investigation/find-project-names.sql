SET PAGESIZE 100
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON

PROMPT ========================================
PROMPT Looking for Project Names in DESIGN1
PROMPT ========================================

PROMPT 
PROMPT 1. DFPROJECT table structure and data:
PROMPT ========================================
SELECT * FROM DESIGN1.DFPROJECT;

PROMPT 
PROMPT 2. Collections that might be projects (checking CAPTION and NAME):
PROMPT ========================================
SELECT OBJECT_ID, EXTERNALID_S_, CAPTION_S_, NAME1_S_, STATUS_S_
FROM DESIGN1.COLLECTION_
WHERE CAPTION_S_ IS NOT NULL OR NAME1_S_ IS NOT NULL
ORDER BY OBJECT_ID
FETCH FIRST 20 ROWS ONLY;

PROMPT 
PROMPT 3. Checking for project-related tables:
PROMPT ========================================
SELECT table_name FROM dba_tables 
WHERE owner='DESIGN1' 
  AND (table_name LIKE '%PROJECT%' OR table_name LIKE '%DFPROJECT%')
ORDER BY table_name;

PROMPT 
PROMPT 4. Sample from COLLECTION_ with project-like names:
PROMPT ========================================
SELECT DISTINCT CAPTION_S_, NAME1_S_ 
FROM DESIGN1.COLLECTION_
WHERE CAPTION_S_ IS NOT NULL
ORDER BY CAPTION_S_
FETCH FIRST 30 ROWS ONLY;

EXIT;
