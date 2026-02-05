@echo off
REM create-database-cmd.bat
REM Create Oracle database using command-line parameters (no response file)

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

REM Create required directories
if not exist "F:\Oracle\oradata" mkdir "F:\Oracle\oradata"
if not exist "F:\Oracle\flash_recovery_area" mkdir "F:\Oracle\flash_recovery_area"
if not exist "F:\Oracle\admin" mkdir "F:\Oracle\admin"
echo Required directories created
echo.

echo Running DBCA (this will take 10-20 minutes)...
echo.

"%ORACLE_HOME%\bin\dbca.bat" ^
  -silent ^
  -ignorePreReqs ^
  -createDatabase ^
  -templateName General_Purpose.dbc ^
  -gdbName localdb01 ^
  -sid localdb01 ^
  -sysPassword change_on_install ^
  -systemPassword manager ^
  -characterSet AL32UTF8 ^
  -nationalCharacterSet AL16UTF16 ^
  -datafileDestination "F:\Oracle\oradata" ^
  -recoveryAreaDestination "F:\Oracle\flash_recovery_area" ^
  -storageType FS ^
  -initParams sga_target=2G,pga_aggregate_target=512M ^
  -emConfiguration NONE ^
  -sampleSchema false

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
