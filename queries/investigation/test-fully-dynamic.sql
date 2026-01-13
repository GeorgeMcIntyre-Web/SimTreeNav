SET PAGESIZE 1000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

-- Get ALL open user schemas dynamically
-- Exclude system schemas by checking default tablespace (SYSTEM/SYSAUX are system)
-- Exclude queue schemas (_AQ suffix)
SELECT DISTINCT u.USERNAME 
FROM DBA_USERS u
WHERE u.ACCOUNT_STATUS = 'OPEN'
  AND u.DEFAULT_TABLESPACE NOT IN ('SYSTEM', 'SYSAUX')
  AND u.USERNAME NOT LIKE '%_AQ'
ORDER BY u.USERNAME;
EXIT;