-- Comprehensive Database Exploration Script
-- Siemens Process Simulation Database

SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK ON
SET VERIFY OFF

PROMPT ========================================
PROMPT 1. Tables with Most Rows (Top 20)
PROMPT ========================================
SELECT owner, table_name, num_rows 
FROM dba_tables 
WHERE owner LIKE 'DESIGN%' AND num_rows > 0 
ORDER BY num_rows DESC 
FETCH FIRST 20 ROWS ONLY;

PROMPT 
PROMPT ========================================
PROMPT 2. Table Count per Schema
PROMPT ========================================
SELECT owner, COUNT(*) as table_count, SUM(num_rows) as total_rows 
FROM dba_tables 
WHERE owner LIKE 'DESIGN%' 
GROUP BY owner 
ORDER BY owner;

PROMPT 
PROMPT ========================================
PROMPT 3. APPLICATION_DATA Table Structure
PROMPT ========================================
SELECT column_name, data_type, data_length, nullable 
FROM dba_tab_columns 
WHERE owner='DESIGN1' AND table_name='APPLICATION_DATA' 
ORDER BY column_id;

PROMPT 
PROMPT ========================================
PROMPT 4. COLLECTION_ Table Structure
PROMPT ========================================
SELECT column_name, data_type, data_length, nullable 
FROM dba_tab_columns 
WHERE owner='DESIGN1' AND table_name='COLLECTION_' 
ORDER BY column_id;

PROMPT 
PROMPT ========================================
PROMPT 5. Table Sizes (Top 30 by Size)
PROMPT ========================================
SELECT owner, table_name, ROUND(bytes/1024/1024, 2) as size_mb 
FROM dba_segments 
WHERE owner LIKE 'DESIGN%' AND segment_type='TABLE' 
ORDER BY bytes DESC 
FETCH FIRST 30 ROWS ONLY;

PROMPT 
PROMPT ========================================
PROMPT 6. Foreign Key Relationships in DESIGN1
PROMPT ========================================
SELECT a.table_name, a.constraint_name, b.table_name as referenced_table 
FROM dba_constraints a, dba_constraints b 
WHERE a.owner='DESIGN1' AND a.constraint_type='R' 
  AND a.r_owner=b.owner AND a.r_constraint_name=b.constraint_name 
ORDER BY a.table_name;

PROMPT 
PROMPT ========================================
PROMPT 7. Indexes in DESIGN1 (Sample)
PROMPT ========================================
SELECT index_name, table_name, uniqueness, status 
FROM dba_indexes 
WHERE owner='DESIGN1' 
ORDER BY table_name, index_name 
FETCH FIRST 30 ROWS ONLY;

PROMPT 
PROMPT ========================================
PROMPT 8. Tables by Name Pattern (COLLECTION, APPLICATION, etc)
PROMPT ========================================
SELECT owner, table_name, num_rows 
FROM dba_tables 
WHERE owner LIKE 'DESIGN%' 
  AND (table_name LIKE '%COLLECTION%' 
       OR table_name LIKE '%APPLICATION%'
       OR table_name LIKE '%PART%'
       OR table_name LIKE '%ASSEMBLY%')
ORDER BY owner, table_name;

PROMPT 
PROMPT ========================================
PROMPT 9. Sample Data from APPLICATION_DATA (First 5 rows)
PROMPT ========================================
SELECT * FROM DESIGN1.APPLICATION_DATA FETCH FIRST 5 ROWS ONLY;

PROMPT 
PROMPT ========================================
PROMPT 10. Sample Data from COLLECTION_ (First 5 rows)
PROMPT ========================================
SELECT * FROM DESIGN1.COLLECTION_ FETCH FIRST 5 ROWS ONLY;

EXIT;
