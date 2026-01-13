SET PAGESIZE 100
SET LINESIZE 200
SET FEEDBACK OFF
SET HEADING ON

PROMPT ========================================
PROMPT Projects in DESIGN1 Schema
PROMPT ========================================
SELECT * FROM DESIGN1.DFPROJECT;

PROMPT 
PROMPT ========================================
PROMPT Project Names from DFPROJECT
PROMPT ========================================
-- Get column names first to understand structure
SELECT column_name FROM dba_tab_columns 
WHERE owner='DESIGN1' AND table_name='DFPROJECT' 
ORDER BY column_id;

EXIT;
