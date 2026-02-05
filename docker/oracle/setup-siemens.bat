@echo off
REM setup-siemens.bat
REM Create Siemens tablespaces and roles in localdb01

SET ORACLE_HOME=F:\Oracle\WINDOWS.X64_193000_db_home
SET ORACLE_SID=localdb01
SET PATH=%ORACLE_HOME%\bin;%PATH%

echo.
echo ============================================
echo   Setting up Siemens Schema
echo ============================================
echo.
echo Database: localdb01
echo.

REM Create necessary directories
if not exist "F:\Oracle\oradata\localdb01" mkdir "F:\Oracle\oradata\localdb01"
if not exist "F:\Oracle\admin\dump" mkdir "F:\Oracle\admin\dump"
echo Created required directories
echo.

REM Create tablespaces
echo Step 1: Creating Siemens tablespaces...
echo.
sqlplus "sys/change_on_install as sysdba" @scripts\setup\01-create-tablespaces.sql

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Tablespace creation failed
    pause
    exit /b 1
)

echo.
echo Step 2: Creating Siemens roles and users...
echo.
sqlplus "sys/change_on_install as sysdba" @scripts\setup\02-after-install.sql

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERROR: Role/user creation failed
    pause
    exit /b 1
)

echo.
echo ============================================
echo   Siemens Setup Complete!
echo ============================================
echo.
echo Database: localdb01
echo SYS Password: change_on_install
echo SYSTEM Password: manager
echo EMP_ADMIN Password: EMP_ADMIN
echo.
echo Tablespaces created:
echo   - PP_DATA_128K, PP_DATA_1M, PP_DATA_10M
echo   - PP_INDEX_128K, PP_INDEX_1M, PP_INDEX_10M
echo   - AQ_DATA, PERFSTAT_DATA
echo.
echo Roles created:
echo   - empower_admin_role, ems_access_role
echo   - schema_owner_role, and others
echo.
echo Users created:
echo   - EMP_ADMIN (with all roles)
echo.
pause
