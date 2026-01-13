SET PAGESIZE 1000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING ON

-- Test 1: Does table exist?
SELECT 'Table exists' as TEST, COUNT(*) as RESULT
FROM DBA_TABLES
WHERE OWNER = 'DESIGN4' AND TABLE_NAME = 'DFPROJECT';

-- Test 2: Can we select from it?
SELECT 'Can select' as TEST, COUNT(*) as ROW_COUNT
FROM DESIGN4.DFPROJECT;

-- Test 3: What if we try to insert a test row and rollback?
-- Actually, let's not do that. Just check structure.

-- Test 4: Check if there are any constraints or triggers preventing access
SELECT CONSTRAINT_NAME, CONSTRAINT_TYPE
FROM DBA_CONSTRAINTS
WHERE OWNER = 'DESIGN4' AND TABLE_NAME = 'DFPROJECT';

EXIT;
