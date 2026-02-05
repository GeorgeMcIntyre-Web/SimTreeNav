-- create-database-manual.sql
-- Manual database creation for localdb01
-- Run as: sqlplus / as sysdba @create-database-manual.sql

-- Set Oracle SID
-- Note: Run this in PowerShell first: $env:ORACLE_SID = "localdb01"

STARTUP NOMOUNT;

CREATE DATABASE localdb01
  USER SYS IDENTIFIED BY change_on_install
  USER SYSTEM IDENTIFIED BY manager
  LOGFILE
    GROUP 1 ('F:\Oracle\oradata\localdb01\redo01a.log') SIZE 100M,
    GROUP 2 ('F:\Oracle\oradata\localdb01\redo02a.log') SIZE 100M,
    GROUP 3 ('F:\Oracle\oradata\localdb01\redo03a.log') SIZE 100M
  CHARACTER SET AL32UTF8
  NATIONAL CHARACTER SET AL16UTF16
  DATAFILE 'F:\Oracle\oradata\localdb01\system01.dbf' SIZE 700M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED
  SYSAUX DATAFILE 'F:\Oracle\oradata\localdb01\sysaux01.dbf' SIZE 550M AUTOEXTEND ON NEXT 10M MAXSIZE UNLIMITED
  DEFAULT TABLESPACE users
    DATAFILE 'F:\Oracle\oradata\localdb01\users01.dbf' SIZE 500M AUTOEXTEND ON
  DEFAULT TEMPORARY TABLESPACE temp
    TEMPFILE 'F:\Oracle\oradata\localdb01\temp01.dbf' SIZE 100M AUTOEXTEND ON
  UNDO TABLESPACE undotbs1
    DATAFILE 'F:\Oracle\oradata\localdb01\undotbs01.dbf' SIZE 200M AUTOEXTEND ON;

-- Run catalog and catproc scripts
@?/rdbms/admin/catalog.sql
@?/rdbms/admin/catproc.sql

-- Connect as SYSTEM
CONNECT system/manager@localdb01

-- Run pupbld.sql for PRODUCT_USER_PROFILE
@?/sqlplus/admin/pupbld.sql

EXIT;
