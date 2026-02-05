# Setup Guide: Using Existing Oracle 19c at F:\Oracle

You have Oracle 19c installed at `F:\Oracle\WINDOWS.X64_193000_db_home`. Here's how to set it up for Tecnomatix development.

---

## Step 1: Set Environment Variables

Run these commands in PowerShell **as Administrator**:

```powershell
# Set ORACLE_HOME (system-wide)
[System.Environment]::SetEnvironmentVariable('ORACLE_HOME', 'F:\Oracle\WINDOWS.X64_193000_db_home', 'Machine')

# Add Oracle bin to PATH
$currentPath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
$oracleBin = 'F:\Oracle\WINDOWS.X64_193000_db_home\bin'
if ($currentPath -notlike "*$oracleBin*") {
    [System.Environment]::SetEnvironmentVariable('Path', "$currentPath;$oracleBin", 'Machine')
}

# Restart PowerShell for changes to take effect
```

Close and reopen PowerShell, then verify:
```powershell
$env:ORACLE_HOME
sqlplus -v
```

---

## Step 2: Check for Existing Database

```powershell
# Check if a database already exists
Get-Service | Where-Object {$_.Name -like "OracleService*"}

# Check oradata directory
ls F:\Oracle\oradata
```

If you see a service like `OracleServiceORCL` or `OracleServiceXE`, you already have a database!

---

## Step 3: Create Database (if needed)

If no database exists, create one:

###Option A: Database Configuration Assistant (GUI - Recommended)

```powershell
# Launch DBCA
F:\Oracle\WINDOWS.X64_193000_db_home\bin\dbca.bat
```

**Settings:**
- Database Name: `EMS12`
- SID: `EMS12`
- Character Set: `AL32UTF8`
- Installation Type: Custom Database
- Add Siemens tablespaces after creation

### Option B: Use Siemens DBCA Template

Copy the Siemens template and use it:

```powershell
# Copy Siemens template
Copy-Item "C:\Users\George\source\repos\SimTreeNav\docker\oracle\siemens-scripts\dbca_EMSDB12_12201_win.dbt" `
          -Destination "F:\Oracle\WINDOWS.X64_193000_db_home\assistants\dbca\templates\"

# Launch DBCA and select the Siemens template
F:\Oracle\WINDOWS.X64_193000_db_home\bin\dbca.bat
```

---

## Step 4: Start Oracle Database

```powershell
# Start the Oracle service
net start OracleServiceEMS12

# Start the listener
lsnrctl start

# Connect to verify
sqlplus / as sysdba
```

In SQL*Plus:
```sql
SELECT instance_name, status FROM v$instance;
EXIT;
```

---

## Step 5: Create Siemens Tablespaces

Use the SQL script we created:

```powershell
# Set Oracle SID
$env:ORACLE_SID = "EMS12"

# Run tablespace creation
sqlplus / as sysdba @"C:\Users\George\source\repos\SimTreeNav\docker\oracle\scripts\setup\01-create-tablespaces.sql"
```

---

## Step 6: Run Siemens after_install.sql

```powershell
# Run Siemens post-install setup
sqlplus / as sysdba @"C:\Users\George\source\repos\SimTreeNav\docker\oracle\scripts\setup\02-after-install.sql"
```

This creates:
- 8 Siemens roles
- EMP_ADMIN user
- Required grants

---

## Step 7: Import Your Dump File

```powershell
# Create dump directory
mkdir F:\Oracle\admin\EMS12\dpdump -Force

# In SQL*Plus, create directory object
sqlplus / as sysdba
```

```sql
CREATE OR REPLACE DIRECTORY DUMP_DIR AS 'F:\Oracle\admin\EMS12\dpdump';
GRANT READ, WRITE ON DIRECTORY DUMP_DIR TO SYSTEM;
EXIT;
```

```powershell
# Copy your .dmp file to the dump directory
Copy-Item "path\to\your\file.dmp" -Destination "F:\Oracle\admin\EMS12\dpdump\"

# Run Data Pump import
impdp system/manager DIRECTORY=DUMP_DIR DUMPFILE=your_file.dmp FULL=Y PARALLEL=4
```

---

## Step 8: Update TNS Configuration

The existing `ORACLE_LOCAL` TNS entry should work. Update if needed:

**File:** `C:\Oracle\instantclient_12_2\network\admin\tnsnames.ora`

```
EMS12_LOCAL =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = localhost)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SID = EMS12)
    )
  )
```

---

## Step 9: Test Connection

```powershell
# Test with SQL*Plus
sqlplus system/manager@EMS12_LOCAL

# Or use the existing SimTreeNav switch
.\src\powershell\database\docker\Switch-DatabaseTarget.ps1 -Target LOCAL
```

---

## Verification

Run the verification queries:

```powershell
cd C:\Users\George\source\repos\SimTreeNav

# Verify tablespaces
sqlplus / as sysdba @-<<'EOF'
SELECT tablespace_name, status FROM dba_tablespaces WHERE tablespace_name LIKE 'PP_%';
EXIT;
EOF

# Verify roles
sqlplus / as sysdba @-<<'EOF'
SELECT role FROM dba_roles WHERE role LIKE '%EMPOWER%' OR role LIKE '%EMS%';
EXIT;
EOF
```

---

## Troubleshooting

### Oracle Service won't start
```powershell
# Check event viewer
Get-EventLog -LogName Application -Source Oracle* -Newest 10

# Check alert log
Get-Content "F:\Oracle\diag\rdbms\ems12\EMS12\trace\alert_EMS12.log" -Tail 50
```

### Can't connect
```powershell
# Check listener status
lsnrctl status

# Check TNS configuration
$env:TNS_ADMIN
Get-Content $env:TNS_ADMIN\tnsnames.ora
```

### Wrong character set
```sql
-- Check current character set
SELECT * FROM nls_database_parameters WHERE parameter = 'NLS_CHARACTERSET';

-- Should be: AL32UTF8
```

---

## Quick Reference

| Component | Location |
|-----------|----------|
| ORACLE_HOME | F:\Oracle\WINDOWS.X64_193000_db_home |
| Database Files | F:\Oracle\oradata\EMS12 |
| Admin Directory | F:\Oracle\admin\EMS12 |
| Dump Directory | F:\Oracle\admin\EMS12\dpdump |
| Alert Log | F:\Oracle\diag\rdbms\ems12\EMS12\trace\alert_EMS12.log |

| Service | Command |
|---------|---------|
| Start Database | `net start OracleServiceEMS12` |
| Stop Database | `net stop OracleServiceEMS12` |
| Start Listener | `lsnrctl start` |
| Stop Listener | `lsnrctl stop` |

---

## Next Steps After Setup

1. Switch database target to LOCAL
2. Run your existing SimTreeNav scripts
3. They'll automatically use the local Oracle 19c database

```powershell
# Switch to local
.\src\powershell\database\docker\Switch-DatabaseTarget.ps1 -Target LOCAL

# Generate tree (will use local database)
.\src\powershell\main\generate-tree-html.ps1 -Schema DESIGN2
```

---

## Notes

- **Oracle 19c vs 12c:** Your client is 12.1.0.2, server is 19c - this is compatible
- **Siemens Scripts:** Designed for 12.2 but work fine with 19c
- **Character Set:** AL32UTF8 is required for Siemens/Tecnomatix
- **Tablespaces:** PP_DATA_* and PP_INDEX_* are Siemens-specific
