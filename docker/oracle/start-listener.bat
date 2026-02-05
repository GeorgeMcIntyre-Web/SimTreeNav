@echo off
REM start-listener.bat
REM Start Oracle Listener

SET ORACLE_HOME=F:\Oracle\WINDOWS.X64_193000_db_home
SET PATH=%ORACLE_HOME%\bin;%PATH%

echo.
echo ============================================
echo   Starting Oracle Listener
echo ============================================
echo.

echo Checking listener status...
lsnrctl status

echo.
echo Starting listener...
lsnrctl start

echo.
echo Listener status after start:
lsnrctl status

echo.
echo ============================================
echo   Listener Started
echo ============================================
echo.
pause
