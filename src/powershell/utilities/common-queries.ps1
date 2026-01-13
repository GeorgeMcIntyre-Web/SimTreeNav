# Common queries for exploring Siemens Process Simulation Database
# Provides menu-driven access to useful queries

param(
    [int]$QueryNumber = 0
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Process Simulation DB - Common Queries" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($QueryNumber -eq 0) {
    Write-Host "Available Queries:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1. List all tables in DESIGN1 schema" -ForegroundColor White
    Write-Host "  2. List all tables in DESIGN2 schema" -ForegroundColor White
    Write-Host "  3. Show tables with most rows (top 20)" -ForegroundColor White
    Write-Host "  4. Show table columns for APPLICATION_DATA" -ForegroundColor White
    Write-Host "  5. Show table columns for COLLECTION_" -ForegroundColor White
    Write-Host "  6. Count tables per schema" -ForegroundColor White
    Write-Host "  7. Show all indexes in DESIGN1" -ForegroundColor White
    Write-Host "  8. Show table sizes (MB)" -ForegroundColor White
    Write-Host "  9. Show foreign key relationships" -ForegroundColor White
    Write-Host " 10. Show all schemas and their table counts" -ForegroundColor White
    Write-Host ""
    Write-Host "Usage: .\common-queries.ps1 -QueryNumber 1" -ForegroundColor Gray
    Write-Host "   Or: .\common-queries.ps1 (to see this menu)" -ForegroundColor Gray
    Write-Host ""
    exit 0
}

# Define queries
$queries = @{
    1 = @{
        Title = "All Tables in DESIGN1 Schema"
        Query = "SELECT table_name, num_rows, last_analyzed, tablespace_name FROM dba_tables WHERE owner='DESIGN1' ORDER BY table_name"
    }
    2 = @{
        Title = "All Tables in DESIGN2 Schema"
        Query = "SELECT table_name, num_rows, last_analyzed, tablespace_name FROM dba_tables WHERE owner='DESIGN2' ORDER BY table_name"
    }
    3 = @{
        Title = "Tables with Most Rows (Top 20)"
        Query = "SELECT owner, table_name, num_rows FROM dba_tables WHERE owner LIKE 'DESIGN%' AND num_rows > 0 ORDER BY num_rows DESC FETCH FIRST 20 ROWS ONLY"
    }
    4 = @{
        Title = "Columns in APPLICATION_DATA Table"
        Query = "SELECT column_name, data_type, data_length, nullable FROM dba_tab_columns WHERE owner='DESIGN1' AND table_name='APPLICATION_DATA' ORDER BY column_id"
    }
    5 = @{
        Title = "Columns in COLLECTION_ Table"
        Query = "SELECT column_name, data_type, data_length, nullable FROM dba_tab_columns WHERE owner='DESIGN1' AND table_name='COLLECTION_' ORDER BY column_id"
    }
    6 = @{
        Title = "Table Count per Schema"
        Query = "SELECT owner, COUNT(*) as table_count FROM dba_tables WHERE owner LIKE 'DESIGN%' GROUP BY owner ORDER BY owner"
    }
    7 = @{
        Title = "Indexes in DESIGN1 Schema"
        Query = "SELECT index_name, table_name, uniqueness, status FROM dba_indexes WHERE owner='DESIGN1' ORDER BY table_name, index_name"
    }
    8 = @{
        Title = "Table Sizes (MB)"
        Query = "SELECT owner, table_name, ROUND(bytes/1024/1024, 2) as size_mb FROM dba_segments WHERE owner LIKE 'DESIGN%' AND segment_type='TABLE' ORDER BY bytes DESC FETCH FIRST 30 ROWS ONLY"
    }
    9 = @{
        Title = "Foreign Key Relationships in DESIGN1"
        Query = "SELECT a.table_name, a.constraint_name, a.r_constraint_name, b.table_name as referenced_table FROM dba_constraints a, dba_constraints b WHERE a.owner='DESIGN1' AND a.constraint_type='R' AND a.r_owner=b.owner AND a.r_constraint_name=b.constraint_name ORDER BY a.table_name"
    }
    10 = @{
        Title = "All Schemas and Table Counts"
        Query = "SELECT owner, COUNT(*) as table_count, SUM(num_rows) as total_rows FROM dba_tables WHERE owner NOT IN ('SYS', 'SYSTEM', 'XDB', 'CTXSYS', 'MDSYS', 'OLAPSYS', 'ORDSYS', 'ORDDATA', 'WMSYS', 'LBACSYS', 'OUTLN', 'DBSNMP', 'APPQOSSYS', 'DBSFWUSER', 'GSMADMIN_INTERNAL', 'OJVMSYS', 'AUDSYS', 'GSMUSER', 'DIP', 'REMOTE_SCHEDULER_AGENT', 'SI_INFORMTN_SCHEMA', 'ORACLE_OCM', 'SYSBACKUP', 'SYSDG', 'SYSKM', 'SYSRAC') GROUP BY owner ORDER BY table_count DESC"
    }
}

if (-not $queries.ContainsKey($QueryNumber)) {
    Write-Host "ERROR: Invalid query number. Use 1-10." -ForegroundColor Red
    Write-Host ""
    exit 1
}

$selectedQuery = $queries[$QueryNumber]

Write-Host "Executing Query $QueryNumber : $($selectedQuery.Title)" -ForegroundColor Green
Write-Host ""

# Run the query
& .\query-db.ps1 -Query $selectedQuery.Query
