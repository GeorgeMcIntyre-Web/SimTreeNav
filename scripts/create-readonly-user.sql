-- ============================================================================
-- Create Read-Only User for SimTreeNav Application
-- ============================================================================
-- Purpose: Create a dedicated read-only database user with minimal privileges
--          for the SimTreeNav tree navigation application.
--
-- Security Benefits:
--   - SELECT-only access (no INSERT/UPDATE/DELETE)
--   - Cannot modify schema structures
--   - Cannot drop or alter objects
--   - Clear audit trail (dedicated user)
--   - Follows principle of least privilege
--
-- Prerequisites:
--   - Must be run as SYS or a user with DBA privileges
--   - Connection: sqlplus sys/password@DATABASE AS SYSDBA
--
-- Usage:
--   SQL> @scripts/create-readonly-user.sql
--
-- Post-Installation:
--   - Update SimTreeNav credentials to use this user
--   - Test connection: sqlplus simtreenav_readonly/password@DATABASE
--   - Verify grants: See verification section at end of script
--
-- Author: SimTreeNav Development Team
-- Date: 2026-01-15
-- Version: 1.0
-- ============================================================================

-- Set output formatting
SET ECHO ON
SET FEEDBACK ON
SET VERIFY ON
WHENEVER SQLERROR EXIT SQL.SQLCODE

-- Display current user (should be SYS or DBA)
SELECT USER, SYS_CONTEXT('USERENV','SESSION_USER') AS SESSION_USER FROM DUAL;

PROMPT
PROMPT ============================================================================
PROMPT Creating Read-Only User: simtreenav_readonly
PROMPT ============================================================================
PROMPT
PROMPT IMPORTANT: Change the password after creation!
PROMPT   ALTER USER simtreenav_readonly IDENTIFIED BY "YourNewPassword";
PROMPT
PAUSE Press Enter to continue or Ctrl+C to abort...

-- ============================================================================
-- Section 1: Create User
-- ============================================================================

PROMPT
PROMPT [1/6] Creating user simtreenav_readonly...
PROMPT

-- Drop user if exists (uncomment if re-running)
-- DROP USER simtreenav_readonly CASCADE;

-- Create user with temporary password (CHANGE THIS!)
CREATE USER simtreenav_readonly IDENTIFIED BY "ChangeMe123!";

-- Set account properties
ALTER USER simtreenav_readonly
  PROFILE DEFAULT
  DEFAULT TABLESPACE USERS
  TEMPORARY TABLESPACE TEMP
  QUOTA 0M ON USERS         -- No space quota (read-only user)
  ACCOUNT UNLOCK;

PROMPT ✓ User created successfully

-- ============================================================================
-- Section 2: Grant System Privileges
-- ============================================================================

PROMPT
PROMPT [2/6] Granting system privileges...
PROMPT

-- Basic connection privilege
GRANT CREATE SESSION TO simtreenav_readonly;

PROMPT ✓ System privileges granted

-- ============================================================================
-- Section 3: Grant System View Access (for schema/instance discovery)
-- ============================================================================

PROMPT
PROMPT [3/6] Granting access to system views...
PROMPT

-- Required for schema discovery (tree-viewer-launcher.ps1)
GRANT SELECT ON DBA_USERS TO simtreenav_readonly;

-- Required for instance discovery (tree-viewer-launcher.ps1)
GRANT SELECT ON V$SERVICES TO simtreenav_readonly;

-- Optional: Additional system views for enhanced functionality
-- GRANT SELECT ON DBA_TABLES TO simtreenav_readonly;
-- GRANT SELECT ON DBA_TAB_COLUMNS TO simtreenav_readonly;
-- GRANT SELECT ON DBA_OBJECTS TO simtreenav_readonly;

PROMPT ✓ System view access granted

-- ============================================================================
-- Section 4: Grant SELECT on DESIGN1 Schema
-- ============================================================================

PROMPT
PROMPT [4/6] Granting SELECT access to DESIGN1 schema...
PROMPT

-- Core tables for tree navigation
GRANT SELECT ON DESIGN1.COLLECTION_ TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.REL_COMMON TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.CLASS_DEFINITIONS TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.DF_ICONS_DATA TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.DFPROJECT TO simtreenav_readonly;

-- Additional tables for extended functionality
GRANT SELECT ON DESIGN1.PROXY TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.APPLICATION_DATA TO simtreenav_readonly;

-- Optional: Grant access to all tables in DESIGN1 (if needed)
-- This is more permissive but ensures compatibility
/*
BEGIN
  FOR t IN (SELECT table_name FROM dba_tables WHERE owner = 'DESIGN1') LOOP
    EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN1.' || t.table_name || ' TO simtreenav_readonly';
  END LOOP;
END;
/
*/

PROMPT ✓ DESIGN1 schema access granted

-- ============================================================================
-- Section 5: Grant SELECT on DESIGN2 Schema
-- ============================================================================

PROMPT
PROMPT [5/6] Granting SELECT access to DESIGN2 schema...
PROMPT

-- Core tables for tree navigation
GRANT SELECT ON DESIGN2.COLLECTION_ TO simtreenav_readonly;
GRANT SELECT ON DESIGN2.REL_COMMON TO simtreenav_readonly;
GRANT SELECT ON DESIGN2.CLASS_DEFINITIONS TO simtreenav_readonly;
GRANT SELECT ON DESIGN2.DF_ICONS_DATA TO simtreenav_readonly;
GRANT SELECT ON DESIGN2.DFPROJECT TO simtreenav_readonly;

-- Additional tables
GRANT SELECT ON DESIGN2.PROXY TO simtreenav_readonly;
GRANT SELECT ON DESIGN2.APPLICATION_DATA TO simtreenav_readonly;

PROMPT ✓ DESIGN2 schema access granted

-- ============================================================================
-- Section 5b: Grant SELECT on DESIGN3-5 Schemas (if they exist)
-- ============================================================================

PROMPT
PROMPT [5b/6] Granting SELECT access to DESIGN3-5 schemas (if present)...
PROMPT

-- DESIGN3 (may be empty but grant anyway)
BEGIN
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN3.COLLECTION_ TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN3.REL_COMMON TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN3.CLASS_DEFINITIONS TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN3.DF_ICONS_DATA TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN3.DFPROJECT TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN3.PROXY TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN3.APPLICATION_DATA TO simtreenav_readonly';
  DBMS_OUTPUT.PUT_LINE('  ✓ DESIGN3 access granted');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  ⚠ DESIGN3 schema not accessible (may not exist)');
END;
/

-- DESIGN4
BEGIN
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN4.COLLECTION_ TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN4.REL_COMMON TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN4.CLASS_DEFINITIONS TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN4.DF_ICONS_DATA TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN4.DFPROJECT TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN4.PROXY TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN4.APPLICATION_DATA TO simtreenav_readonly';
  DBMS_OUTPUT.PUT_LINE('  ✓ DESIGN4 access granted');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  ⚠ DESIGN4 schema not accessible (may not exist)');
END;
/

-- DESIGN5
BEGIN
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN5.COLLECTION_ TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN5.REL_COMMON TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN5.CLASS_DEFINITIONS TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN5.DF_ICONS_DATA TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN5.DFPROJECT TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN5.PROXY TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN5.APPLICATION_DATA TO simtreenav_readonly';
  DBMS_OUTPUT.PUT_LINE('  ✓ DESIGN5 access granted');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  ⚠ DESIGN5 schema not accessible (may not exist)');
END;
/

-- DESIGN12 (your specific schema)
BEGIN
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN12.COLLECTION_ TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN12.REL_COMMON TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN12.CLASS_DEFINITIONS TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN12.DF_ICONS_DATA TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN12.DFPROJECT TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN12.PROXY TO simtreenav_readonly';
  EXECUTE IMMEDIATE 'GRANT SELECT ON DESIGN12.APPLICATION_DATA TO simtreenav_readonly';
  DBMS_OUTPUT.PUT_LINE('  ✓ DESIGN12 access granted');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('  ⚠ DESIGN12 schema not accessible (may not exist)');
END;
/

-- ============================================================================
-- Section 6: Create Synonyms (Optional but Recommended)
-- ============================================================================

PROMPT
PROMPT [6/6] Creating synonyms for easier access (optional)...
PROMPT

-- This allows queries like "SELECT * FROM DESIGN1_COLLECTION"
-- instead of "SELECT * FROM DESIGN1.COLLECTION_"

/*
-- Uncomment to create synonyms
CREATE SYNONYM simtreenav_readonly.DESIGN1_COLLECTION FOR DESIGN1.COLLECTION_;
CREATE SYNONYM simtreenav_readonly.DESIGN1_REL_COMMON FOR DESIGN1.REL_COMMON;
CREATE SYNONYM simtreenav_readonly.DESIGN1_CLASS_DEFINITIONS FOR DESIGN1.CLASS_DEFINITIONS;
CREATE SYNONYM simtreenav_readonly.DESIGN1_DF_ICONS_DATA FOR DESIGN1.DF_ICONS_DATA;
CREATE SYNONYM simtreenav_readonly.DESIGN1_DFPROJECT FOR DESIGN1.DFPROJECT;

-- Repeat for DESIGN2-5 as needed
*/

PROMPT ⚠ Synonyms not created (optional feature - uncomment if needed)

-- ============================================================================
-- Section 7: Verification
-- ============================================================================

PROMPT
PROMPT ============================================================================
PROMPT Verification: Checking Granted Privileges
PROMPT ============================================================================
PROMPT

-- System privileges
PROMPT System Privileges:
SELECT * FROM DBA_SYS_PRIVS
WHERE GRANTEE = 'SIMTREENAV_READONLY'
ORDER BY PRIVILEGE;

PROMPT
PROMPT Table Privileges (showing first 20):
SELECT * FROM (
  SELECT OWNER, TABLE_NAME, PRIVILEGE, GRANTABLE
  FROM DBA_TAB_PRIVS
  WHERE GRANTEE = 'SIMTREENAV_READONLY'
  ORDER BY OWNER, TABLE_NAME
)
WHERE ROWNUM <= 20;

PROMPT
PROMPT Total table privileges granted:
SELECT OWNER, COUNT(*) AS GRANT_COUNT
FROM DBA_TAB_PRIVS
WHERE GRANTEE = 'SIMTREENAV_READONLY'
GROUP BY OWNER
ORDER BY OWNER;

-- ============================================================================
-- Section 8: Test Connection
-- ============================================================================

PROMPT
PROMPT ============================================================================
PROMPT Test Connection (Optional)
PROMPT ============================================================================
PROMPT
PROMPT To test the new user, run:
PROMPT   sqlplus simtreenav_readonly/ChangeMe123!@DATABASE
PROMPT   SQL> SELECT COUNT(*) FROM DESIGN1.COLLECTION_;
PROMPT
PROMPT If successful, you should see row count without errors.
PROMPT

-- ============================================================================
-- Section 9: Post-Installation Steps
-- ============================================================================

PROMPT
PROMPT ============================================================================
PROMPT POST-INSTALLATION STEPS
PROMPT ============================================================================
PROMPT
PROMPT 1. CHANGE THE PASSWORD (CRITICAL!)
PROMPT    SQL> ALTER USER simtreenav_readonly IDENTIFIED BY "YourSecurePassword";
PROMPT
PROMPT 2. Test the connection:
PROMPT    sqlplus simtreenav_readonly/YourPassword@DATABASE
PROMPT
PROMPT 3. Update SimTreeNav credentials:
PROMPT    PS> .\src\powershell\database\Initialize-DbCredentials.ps1 -Username simtreenav_readonly
PROMPT
PROMPT 4. Test tree viewer:
PROMPT    PS> .\src\powershell\main\tree-viewer-launcher.ps1
PROMPT
PROMPT 5. Verify read-only restrictions (should fail):
PROMPT    SQL> DELETE FROM DESIGN1.COLLECTION_ WHERE ROWNUM = 1;
PROMPT    (Should get: ORA-01031: insufficient privileges)
PROMPT
PROMPT ============================================================================
PROMPT ✓ Read-Only User Creation Complete!
PROMPT ============================================================================
PROMPT

-- Commit all changes
COMMIT;

-- Optional: Generate a report of all grants
SPOOL simtreenav_readonly_grants.txt
SELECT 'System Privileges:' AS GRANT_TYPE FROM DUAL;
SELECT PRIVILEGE FROM DBA_SYS_PRIVS WHERE GRANTEE = 'SIMTREENAV_READONLY';
SELECT 'Table Privileges:' AS GRANT_TYPE FROM DUAL;
SELECT OWNER || '.' || TABLE_NAME AS OBJECT, PRIVILEGE
FROM DBA_TAB_PRIVS
WHERE GRANTEE = 'SIMTREENAV_READONLY'
ORDER BY OWNER, TABLE_NAME;
SPOOL OFF

PROMPT
PROMPT Grant report saved to: simtreenav_readonly_grants.txt
PROMPT

EXIT;
