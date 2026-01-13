# Process Simulation Database - Query Examples

Quick reference for common queries to explore the database.

## Quick Start

**View available common queries:**
```powershell
.\common-queries.ps1
```

**Run a specific common query:**
```powershell
.\common-queries.ps1 -QueryNumber 1
```

**Run a custom query:**
```powershell
.\query-db.ps1 -Query "SELECT * FROM dba_tables WHERE owner='DESIGN1'"
```

## Common Queries

### 1. List All Tables in a Schema
```powershell
.\query-db.ps1 -Query "SELECT table_name, num_rows FROM dba_tables WHERE owner='DESIGN1' ORDER BY table_name"
```

### 2. Find Tables with Most Data
```powershell
.\query-db.ps1 -Query "SELECT owner, table_name, num_rows FROM dba_tables WHERE owner LIKE 'DESIGN%' AND num_rows > 0 ORDER BY num_rows DESC FETCH FIRST 20 ROWS ONLY"
```

### 3. View Table Structure (Columns)
```powershell
.\query-db.ps1 -Query "SELECT column_name, data_type, data_length, nullable FROM dba_tab_columns WHERE owner='DESIGN1' AND table_name='APPLICATION_DATA' ORDER BY column_id"
```

### 4. Count Tables per Schema
```powershell
.\query-db.ps1 -Query "SELECT owner, COUNT(*) as table_count FROM dba_tables WHERE owner LIKE 'DESIGN%' GROUP BY owner ORDER BY owner"
```

### 5. View Table Sizes
```powershell
.\query-db.ps1 -Query "SELECT owner, table_name, ROUND(bytes/1024/1024, 2) as size_mb FROM dba_segments WHERE owner LIKE 'DESIGN%' AND segment_type='TABLE' ORDER BY bytes DESC FETCH FIRST 30 ROWS ONLY"
```

### 6. Find Foreign Key Relationships
```powershell
.\query-db.ps1 -Query "SELECT a.table_name, a.constraint_name, b.table_name as referenced_table FROM dba_constraints a, dba_constraints b WHERE a.owner='DESIGN1' AND a.constraint_type='R' AND a.r_owner=b.owner AND a.r_constraint_name=b.constraint_name ORDER BY a.table_name"
```

### 7. View Indexes
```powershell
.\query-db.ps1 -Query "SELECT index_name, table_name, uniqueness, status FROM dba_indexes WHERE owner='DESIGN1' ORDER BY table_name, index_name"
```

### 8. Sample Data from a Table
```powershell
.\query-db.ps1 -Query "SELECT * FROM DESIGN1.APPLICATION_DATA FETCH FIRST 10 ROWS ONLY"
```

### 9. Find Tables by Name Pattern
```powershell
.\query-db.ps1 -Query "SELECT owner, table_name, num_rows FROM dba_tables WHERE owner LIKE 'DESIGN%' AND table_name LIKE '%COLLECTION%' ORDER BY owner, table_name"
```

### 10. View All Constraints
```powershell
.\query-db.ps1 -Query "SELECT owner, table_name, constraint_name, constraint_type FROM dba_constraints WHERE owner='DESIGN1' ORDER BY table_name, constraint_type"
```

## Using SQL Files

Create a SQL file (e.g., `myquery.sql`) and run it:

```powershell
.\query-db.ps1 -SqlFile myquery.sql
```

Example `myquery.sql`:
```sql
SET PAGESIZE 100
SET LINESIZE 200

SELECT table_name, num_rows 
FROM dba_tables 
WHERE owner='DESIGN1' 
ORDER BY num_rows DESC;
```

## Interactive SQL*Plus

For interactive queries, use:

```powershell
.\connect-db.ps1
```

Then you can type SQL commands directly at the `SQL>` prompt.

## Schema Information

The database contains these main schemas:
- **DESIGN1** through **DESIGN5**: Main Process Simulation schemas
- **DESIGN1_AQ** through **DESIGN5_AQ**: Advanced Queue schemas
- **EMP_ADMIN**: Employee/Admin schema

## Important Notes

- You're connected as SYS with SYSDBA privileges
- All queries are read-only (you're exploring, not modifying)
- Use `FETCH FIRST N ROWS ONLY` to limit large result sets
- Table statistics (NUM_ROWS) may need to be updated with `ANALYZE TABLE` if they seem outdated
