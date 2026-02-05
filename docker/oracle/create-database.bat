@echo off
REM create-database.bat
REM Wrapper script to create Oracle database with proper environment

SET ORACLE_HOME=F:\Oracle\WINDOWS.X64_193000_db_home
SET ORACLE_SID=localdb01
SET PATH=%ORACLE_HOME%\bin;%PATH%

echo.
echo ============================================
echo   Creating Oracle Database: localdb01
echo ============================================
echo.
echo ORACLE_HOME = %ORACLE_HOME%
echo ORACLE_SID = %ORACLE_SID%
echo.

REM Create response file
echo [GENERAL] > dbca_response.rsp
echo RESPONSEFILE_VERSION = "19.0.0" >> dbca_response.rsp
echo OPERATION_TYPE = "createDatabase" >> dbca_response.rsp
echo. >> dbca_response.rsp
echo [CREATEDATABASE] >> dbca_response.rsp
echo GDBNAME = "localdb01" >> dbca_response.rsp
echo SID = "localdb01" >> dbca_response.rsp
echo TEMPLATENAME = "General_Purpose.dbc" >> dbca_response.rsp
echo SYSPASSWORD = "change_on_install" >> dbca_response.rsp
echo SYSTEMPASSWORD = "manager" >> dbca_response.rsp
echo CHARACTERSET = "AL32UTF8" >> dbca_response.rsp
echo NATIONALCHARACTERSET= "AL16UTF16" >> dbca_response.rsp
echo TOTALMEMORY = "3072" >> dbca_response.rsp
echo DATABASETYPE = "MULTIPURPOSE" >> dbca_response.rsp
echo AUTOMATICMEMORYMANAGEMENT = "TRUE" >> dbca_response.rsp
echo STORAGETYPE = "FS" >> dbca_response.rsp
echo DATAFILEDESTINATION = "F:\Oracle\oradata" >> dbca_response.rsp
echo RECOVERYAREADESTINATION = "F:\Oracle\flash_recovery_area" >> dbca_response.rsp
echo LISTENERS = "LISTENER" >> dbca_response.rsp
echo EMCONFIGURATION = "DBEXPRESS" >> dbca_response.rsp
echo EMEXPRESSPORT = "5500" >> dbca_response.rsp

echo Response file created
echo.

REM Create required directories
if not exist "F:\Oracle\oradata" mkdir "F:\Oracle\oradata"
if not exist "F:\Oracle\flash_recovery_area" mkdir "F:\Oracle\flash_recovery_area"
if not exist "F:\Oracle\admin" mkdir "F:\Oracle\admin"
echo Required directories created
echo.

echo Running DBCA (this will take 10-20 minutes)...
echo Working directory: %CD%
echo Response file: %CD%\dbca_response.rsp
echo.

"%ORACLE_HOME%\bin\dbca.bat" -silent -createDatabase -responseFile "%CD%\dbca_response.rsp"

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ============================================
    echo   Database Created Successfully!
    echo ============================================
    echo.
) else (
    echo.
    echo ERROR: Database creation failed
    echo Check logs at: F:\Oracle\cfgtoollogs\dbca\localdb01
    echo.
    exit /b 1
)
