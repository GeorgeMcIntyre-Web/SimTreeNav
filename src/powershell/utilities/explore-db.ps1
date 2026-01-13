# Database exploration script for Siemens Process Simulation Database
# Provides useful queries to understand the database structure

param(
    [string]$Username = "sys",
    [string]$Password = "change_on_install",
    [switch]$AsSysdba = $true
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Siemens Process Simulation DB Explorer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Server: des-sim-db1 | Instance: db02" -ForegroundColor Gray
Write-Host ""

# Check if sqlplus is available
$sqlplusPath = Get-Command sqlplus -ErrorAction SilentlyContinue
if (-not $sqlplusPath) {
    Write-Host "ERROR: sqlplus not found in PATH" -ForegroundColor Red
    exit 1
}

# Build connection string
if ($AsSysdba) {
    $connectionString = "$Username/$Password@SIEMENS_PS_DB AS SYSDBA"
} else {
    $connectionString = "$Username/$Password@SIEMENS_PS_DB"
}

# Create exploration SQL script
# Using single-quote here-string to prevent PowerShell variable expansion
$exploreScript = @'
SET PAGESIZE 1000
SET LINESIZE 200
SET FEEDBACK ON
SET VERIFY OFF

PROMPT ========================================
PROMPT Database Version and Info
PROMPT ========================================
SELECT BANNER FROM V$VERSION WHERE ROWNUM <= 5;

PROMPT 
PROMPT ========================================
PROMPT Current User and Session Info
PROMPT ========================================
SELECT 
    USER AS CURRENT_USER,
    SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS CURRENT_SCHEMA,
    SYS_CONTEXT('USERENV', 'DB_NAME') AS DATABASE_NAME,
    SYS_CONTEXT('USERENV', 'INSTANCE_NAME') AS INSTANCE_NAME,
    SYS_CONTEXT('USERENV', 'SERVER_HOST') AS SERVER_HOST
FROM DUAL;

PROMPT 
PROMPT ========================================
PROMPT All Schemas/Users in Database
PROMPT ========================================
SELECT 
    USERNAME,
    ACCOUNT_STATUS,
    CREATED,
    DEFAULT_TABLESPACE,
    TEMPORARY_TABLESPACE
FROM DBA_USERS
ORDER BY USERNAME;

PROMPT 
PROMPT ========================================
PROMPT Tablespaces
PROMPT ========================================
SELECT 
    TS.TABLESPACE_NAME,
    TS.STATUS,
    TS.CONTENTS,
    ROUND(SUM(DF.BYTES)/1024/1024/1024, 2) AS SIZE_GB,
    ROUND(SUM(DF.MAXBYTES)/1024/1024/1024, 2) AS MAX_SIZE_GB
FROM DBA_TABLESPACES TS
LEFT JOIN DBA_DATA_FILES DF ON TS.TABLESPACE_NAME = DF.TABLESPACE_NAME
GROUP BY TS.TABLESPACE_NAME, TS.STATUS, TS.CONTENTS
ORDER BY TS.TABLESPACE_NAME;

PROMPT 
PROMPT ========================================
PROMPT Top 20 Schemas by Table Count
PROMPT ========================================
SELECT 
    OWNER,
    COUNT(*) AS TABLE_COUNT
FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS', 'SYSTEM', 'XDB', 'CTXSYS', 'MDSYS', 'OLAPSYS', 'ORDSYS', 'ORDDATA', 'WMSYS', 'LBACSYS', 'OUTLN', 'DBSNMP', 'APPQOSSYS', 'DBSFWUSER', 'GSMADMIN_INTERNAL', 'OJVMSYS', 'AUDSYS', 'GSMUSER', 'DIP', 'REMOTE_SCHEDULER_AGENT', 'SI_INFORMTN_SCHEMA', 'ORACLE_OCM', 'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSRAC')
GROUP BY OWNER
ORDER BY TABLE_COUNT DESC
FETCH FIRST 20 ROWS ONLY;

PROMPT 
PROMPT ========================================
PROMPT All Tables in Top Schemas (Sample)
PROMPT ========================================
SELECT 
    OWNER,
    TABLE_NAME,
    TABLESPACE_NAME,
    NUM_ROWS,
    LAST_ANALYZED
FROM DBA_TABLES
WHERE OWNER NOT IN ('SYS', 'SYSTEM', 'XDB', 'CTXSYS', 'MDSYS', 'OLAPSYS', 'ORDSYS', 'ORDDATA', 'WMSYS', 'LBACSYS', 'OUTLN', 'DBSNMP', 'APPQOSSYS', 'DBSFWUSER', 'GSMADMIN_INTERNAL', 'OJVMSYS', 'AUDSYS', 'GSMUSER', 'DIP', 'REMOTE_SCHEDULER_AGENT', 'SI_INFORMTN_SCHEMA', 'ORACLE_OCM', 'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSRAC')
ORDER BY OWNER, TABLE_NAME
FETCH FIRST 50 ROWS ONLY;

PROMPT 
PROMPT ========================================
PROMPT Database Size Summary
PROMPT ========================================
SELECT 
    ROUND(SUM(BYTES)/1024/1024/1024, 2) AS TOTAL_SIZE_GB,
    ROUND(SUM(CASE WHEN MAXBYTES > 0 THEN MAXBYTES - BYTES ELSE 0 END)/1024/1024/1024, 2) AS FREE_SPACE_GB,
    ROUND(SUM(BYTES)/1024/1024/1024, 2) AS USED_SPACE_GB
FROM DBA_DATA_FILES;

EXIT;
'@

$scriptFile = Join-Path $env:TEMP "oracle_explore_$(Get-Date -Format 'yyyyMMddHHmmss').sql"
$exploreScript | Out-File -FilePath $scriptFile -Encoding ASCII

Write-Host "Running database exploration queries..." -ForegroundColor Green
Write-Host "This may take a moment..." -ForegroundColor Yellow
Write-Host ""

try {
    $result = & sqlplus -S $connectionString "@$scriptFile" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $result | ForEach-Object { Write-Host $_ }
    } else {
        Write-Host "Exploration failed!" -ForegroundColor Red
        $result | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    }
} catch {
    Write-Host "ERROR: Failed to explore database" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
    if (Test-Path $scriptFile) {
        Remove-Item $scriptFile -Force
    }
}

Write-Host ""
Write-Host "Exploration complete!" -ForegroundColor Green
Write-Host ""
