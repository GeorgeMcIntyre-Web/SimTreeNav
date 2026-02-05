# Verify-LocalDatabase.ps1
# Runs verification queries against the local Oracle Docker database
#
# Usage:
#   .\Verify-LocalDatabase.ps1
#   .\Verify-LocalDatabase.ps1 -Schema DESIGN2

param(
    [string]$Schema = "DESIGN2",
    [string]$ContainerName = "oracle-tecnomatix-12c",
    [string]$OraclePwd = "change_on_install",
    [string]$OracleSid = "EMS12"
)

$ErrorActionPreference = "Stop"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Local Oracle Database Verification" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Check container is running
$containerStatus = docker ps --filter "name=$ContainerName" --format "{{.Status}}" 2>$null
if (-not $containerStatus -or $containerStatus -notmatch "Up") {
    Write-Host "ERROR: Container '$ContainerName' is not running." -ForegroundColor Red
    exit 1
}

$connStr = "sys/$OraclePwd@localhost:1521/$OracleSid as sysdba"

function Run-OracleQuery {
    param([string]$Title, [string]$SQL)

    Write-Host ""
    Write-Host "=== $Title ===" -ForegroundColor Cyan
    $fullSQL = "SET PAGESIZE 100`nSET LINESIZE 200`nSET FEEDBACK ON`n$SQL`nEXIT;"
    docker exec $ContainerName bash -c "echo '$fullSQL' | sqlplus -S $connStr"
}

# 1. Database version
Run-OracleQuery "Database Version" "SELECT banner FROM v`$version WHERE ROWNUM = 1;"

# 2. Tablespace check
Run-OracleQuery "Tablespace Status" @"
SELECT tablespace_name, status, contents
FROM dba_tablespaces
WHERE tablespace_name LIKE 'PP_%'
   OR tablespace_name IN ('AQ_DATA', 'PERFSTAT_DATA')
ORDER BY tablespace_name;
"@

# 3. Tablespace sizes
Run-OracleQuery "Tablespace Sizes (MB)" @"
SELECT df.tablespace_name,
       ROUND(df.bytes/1024/1024, 0) AS size_mb,
       ROUND(NVL(fs.free_bytes,0)/1024/1024, 0) AS free_mb
FROM (SELECT tablespace_name, SUM(bytes) AS bytes FROM dba_data_files GROUP BY tablespace_name) df
LEFT JOIN (SELECT tablespace_name, SUM(bytes) AS free_bytes FROM dba_free_space GROUP BY tablespace_name) fs
ON df.tablespace_name = fs.tablespace_name
WHERE df.tablespace_name LIKE 'PP_%'
   OR df.tablespace_name IN ('AQ_DATA', 'PERFSTAT_DATA')
ORDER BY df.tablespace_name;
"@

# 4. Roles check
Run-OracleQuery "Siemens Roles" @"
SELECT role FROM dba_roles
WHERE role IN ('EMPOWER_ADMIN_ROLE', 'EMS_ACCESS_ROLE', 'SCHEMA_OWNER_ROLE',
               'AQ_ROLE', 'RESET_TABLES_ROLE', 'SCHEMA_MIGRATION_ROLE',
               'ARCHIVE_PROJECT_ROLE', 'DATA_ANALYSIS_ROLE')
ORDER BY role;
"@

# 5. Users/schemas
Run-OracleQuery "Database Users" @"
SELECT username, account_status, default_tablespace
FROM dba_users
WHERE username LIKE 'DESIGN%'
   OR username = 'EMP_ADMIN'
ORDER BY username;
"@

# 6. Table counts per schema
Run-OracleQuery "Tables per Schema" @"
SELECT owner, COUNT(*) AS table_count
FROM dba_tables
WHERE owner LIKE 'DESIGN%'
GROUP BY owner
ORDER BY owner;
"@

# 7. Key table row counts (if schema exists)
$schemaCheck = docker exec $ContainerName bash -c "echo 'SELECT COUNT(*) FROM dba_users WHERE username = ''$Schema'';`nEXIT;' | sqlplus -S $connStr" 2>$null

if ($schemaCheck -match "[1-9]") {
    Run-OracleQuery "Key Table Row Counts ($Schema)" @"
SELECT 'COLLECTION_' AS table_name, COUNT(*) AS row_count FROM $Schema.COLLECTION_
UNION ALL
SELECT 'REL_COMMON', COUNT(*) FROM $Schema.REL_COMMON
UNION ALL
SELECT 'CLASS_DEFINITIONS', COUNT(*) FROM $Schema.CLASS_DEFINITIONS
UNION ALL
SELECT 'DF_ICONS_DATA', COUNT(*) FROM $Schema.DF_ICONS_DATA
UNION ALL
SELECT 'PROXY', COUNT(*) FROM $Schema.PROXY
UNION ALL
SELECT 'USER_', COUNT(*) FROM $Schema.USER_;
"@
} else {
    Write-Host ""
    Write-Host "  Schema '$Schema' not found. Skipping row count checks." -ForegroundColor Yellow
    Write-Host "  (This is normal if data hasn't been imported yet)" -ForegroundColor Gray
}

# 8. Data Pump directory
Run-OracleQuery "Data Pump Directories" @"
SELECT directory_name, directory_path
FROM dba_directories
WHERE directory_name = 'DUMP_DIR';
"@

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Verification Complete" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
