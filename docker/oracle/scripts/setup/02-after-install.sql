-- Siemens Tecnomatix Post-Installation Script (Docker Adapted)
-- Based on: after_install.sql from Database Installation Scripts 12.2.0.1
-- Run as SYS with SYSDBA privileges

-- Enable autoextend on temp files
declare
    cursor file_cur is select file_name, autoextensible from dba_temp_files;
begin
    for i in file_cur
    loop
        if i.autoextensible = 'NO'
        then
            execute immediate 'alter database tempfile ''' || i.file_name || ''' autoextend on';
        end if;
    end loop;
end;
/

-- Unlimited password lifetime for development
alter profile default limit password_life_time unlimited;

set term off
set echo off
set verify off

--------------------------------------------------------------------------
-- Create the eM-Power admin role
define empower_admin_role = empower_admin_role

BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE &empower_admin_role';
EXCEPTION
WHEN others THEN
    IF (SQLCODE = -1921) THEN
        null;
    END IF;
END;
/

GRANT CREATE USER TO &empower_admin_role;
GRANT ALTER USER TO &empower_admin_role;
GRANT CREATE ROLE TO &empower_admin_role;
GRANT CREATE TABLE TO &empower_admin_role WITH ADMIN OPTION;
GRANT CREATE VIEW TO &empower_admin_role WITH ADMIN OPTION;
GRANT CREATE TRIGGER TO &empower_admin_role WITH ADMIN OPTION;
GRANT CREATE TYPE TO &empower_admin_role WITH ADMIN OPTION;
GRANT CREATE SEQUENCE TO &empower_admin_role WITH ADMIN OPTION;
GRANT CREATE PROCEDURE TO &empower_admin_role WITH ADMIN OPTION;
GRANT CREATE SNAPSHOT TO &empower_admin_role WITH ADMIN OPTION;
GRANT CREATE SESSION TO &empower_admin_role WITH ADMIN OPTION;
GRANT CREATE SYNONYM TO &empower_admin_role WITH ADMIN OPTION;
GRANT ALTER SESSION TO &empower_admin_role WITH ADMIN OPTION;
GRANT AQ_ADMINISTRATOR_ROLE TO &empower_admin_role WITH ADMIN OPTION;

--------------------------------------------------------------------------
-- Create the access-user role
define ems_access_role = ems_access_role

BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE &ems_access_role';
EXCEPTION
WHEN others THEN
    IF (SQLCODE = -1921) THEN
        null;
    END IF;
END;
/

GRANT CREATE SESSION TO &ems_access_role;
GRANT CREATE SYNONYM TO &ems_access_role;
GRANT AQ_ADMINISTRATOR_ROLE TO &ems_access_role;
GRANT EXECUTE ON DBMS_AQADM TO &ems_access_role;
GRANT ALTER ROLLBACK SEGMENT TO &ems_access_role;
GRANT EXECUTE ON DBMS_AQ TO &ems_access_role;

----------------------------------------------------------
-- Create the schema-owner role
define schema_owner_role = schema_owner_role

BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE &schema_owner_role';
EXCEPTION
WHEN others THEN
    IF (SQLCODE = -1921) THEN
        null;
    END IF;
END;
/

GRANT AQ_ADMINISTRATOR_ROLE TO &schema_owner_role;
GRANT CREATE SESSION TO &schema_owner_role;
GRANT CREATE TABLE TO &schema_owner_role;
GRANT CREATE VIEW TO &schema_owner_role;
GRANT CREATE TRIGGER TO &schema_owner_role;
GRANT CREATE TYPE TO &schema_owner_role;
GRANT CREATE SEQUENCE TO &schema_owner_role;
GRANT CREATE PROCEDURE TO &schema_owner_role;
GRANT CREATE SYNONYM TO &schema_owner_role;
GRANT ALTER ROLLBACK SEGMENT TO &schema_owner_role;
GRANT ALTER SESSION TO &schema_owner_role;

----------------------------------------------------------
-- Create the AQ role
define aq_role = aq_role

BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE &aq_role';
EXCEPTION
WHEN others THEN
    IF (SQLCODE = -1921) THEN
        null;
    END IF;
END;
/

GRANT AQ_ADMINISTRATOR_ROLE TO &aq_role;
GRANT CREATE SESSION TO &aq_role;
GRANT CREATE TABLE TO &aq_role;
GRANT EXECUTE ON DBMS_AQADM TO &aq_role;
GRANT EXECUTE ON DBMS_AQ TO &aq_role;

----------------------------------------------------------
-- Create the reset-tables role
define reset_tables_role = reset_tables_role

BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE &reset_tables_role';
EXCEPTION
WHEN others THEN
    IF (SQLCODE = -1921) THEN
        null;
    END IF;
END;
/

----------------------------------------------------------
-- Create the schema-migration role
define schema_migration_role = schema_migration_role

BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE &schema_migration_role';
EXCEPTION
WHEN others THEN
    IF (SQLCODE = -1921) THEN
        null;
    END IF;
END;
/

GRANT CREATE SESSION TO &schema_migration_role;

----------------------------------------------------------
-- Create the archive-project role
define archive_project_role = archive_project_role

BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE &archive_project_role';
EXCEPTION
WHEN others THEN
    IF (SQLCODE = -1921) THEN
        null;
    END IF;
END;
/

----------------------------------------------------------
-- Create the data-analysis role
define data_analysis_role = data_analysis_role

BEGIN
    EXECUTE IMMEDIATE 'CREATE ROLE &data_analysis_role';
EXCEPTION
WHEN others THEN
    IF (SQLCODE = -1921) THEN
        null;
    END IF;
END;
/

----------------------------------------------------------
-- Create the eM-Power admin user (EMP_ADMIN)
define empower_admin_user = EMP_ADMIN
define empower_admin_password = EMP_ADMIN
define empower_admin_role = empower_admin_role

set serveroutput on size 1000000

CREATE USER &empower_admin_user IDENTIFIED BY &empower_admin_password;

ALTER USER &empower_admin_user DEFAULT TABLESPACE pp_data_128k;
ALTER USER &empower_admin_user TEMPORARY TABLESPACE temp;

-- Grant the admin role
GRANT &empower_admin_role TO &empower_admin_user;

-- Grant all roles to the admin user
GRANT schema_owner_role TO &empower_admin_user WITH ADMIN OPTION;
GRANT ems_access_role TO &empower_admin_user WITH ADMIN OPTION;
GRANT aq_role TO &empower_admin_user WITH ADMIN OPTION;
GRANT reset_tables_role TO &empower_admin_user WITH ADMIN OPTION;
GRANT schema_migration_role TO &empower_admin_user WITH ADMIN OPTION;
GRANT archive_project_role TO &empower_admin_user WITH ADMIN OPTION;

-- Grant AQ to admin user
GRANT EXECUTE ON DBMS_AQADM TO &empower_admin_user WITH GRANT OPTION;
GRANT EXECUTE ON DBMS_AQ TO &empower_admin_user WITH GRANT OPTION;

GRANT SELECT ON v_$session TO &empower_admin_user;

-- Verify installation
PROMPT
PROMPT === Roles Created ===
SELECT role FROM dba_roles
WHERE role IN ('EMPOWER_ADMIN_ROLE', 'EMS_ACCESS_ROLE', 'SCHEMA_OWNER_ROLE',
               'AQ_ROLE', 'RESET_TABLES_ROLE', 'SCHEMA_MIGRATION_ROLE',
               'ARCHIVE_PROJECT_ROLE', 'DATA_ANALYSIS_ROLE')
ORDER BY role;

PROMPT
PROMPT === EMP_ADMIN User ===
SELECT username, account_status, default_tablespace
FROM dba_users WHERE username = 'EMP_ADMIN';

EXIT;
