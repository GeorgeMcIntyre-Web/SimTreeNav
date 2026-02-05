# Local Oracle Database Setup for SimTreeNav

Complete setup documentation for running Oracle with Siemens Tecnomatix schema for fast local development.

## 📋 Quick Links

- **Native Windows Setup** (Recommended - What we use): [Native Setup Guide](#-native-windows-setup-recommended)
- **Docker Setup** (Alternative): [Docker Setup Guide](#-docker-setup-alternative)
- [Troubleshooting](#-troubleshooting)
- [Files Reference](#-files-reference)

---

## 🎯 Overview

Two approaches for local Oracle database:

| Approach | Pros | Cons | Status |
|----------|------|------|--------|
| **Native Windows** | ✅ Faster<br>✅ No Docker overhead<br>✅ Direct access | ❌ Requires Oracle installation<br>❌ Windows-specific | **✅ Current Setup** |
| **Docker** | ✅ Isolated<br>✅ Easy cleanup<br>✅ Cross-platform | ❌ Requires Docker<br>❌ Oracle registry login | 📦 Alternative |

### Current Configuration
- **Database Name**: localdb01
- **SID**: localdb01
- **Location**: F:\Oracle\WINDOWS.X64_193000_db_home
- **Character Set**: AL32UTF8 (Siemens requirement)
- **Memory**: 2GB SGA + 512MB PGA
- **Oracle Version**: 19c Enterprise Edition (19.3.0.0.0)

---

## 🚀 Native Windows Setup (Recommended)

### Prerequisites

- **Oracle 19c Enterprise** installed at `F:\Oracle\WINDOWS.X64_193000_db_home`
- **PowerShell 5.1+** with Administrator access
- **Windows 10/11 (64-bit)**
- **31GB RAM** (database uses ~2.5GB)

### Quick Start

```powershell
# Navigate to setup directory (run as Administrator)
cd C:\Users\George\source\repos\SimTreeNav\docker\oracle

# 1. Create database (10-20 minutes, one-time)
.\create-database-cmd.bat

# 2. Set up Siemens schema
.\setup-siemens.bat

# 3. Configure TNS
.\setup-tns.ps1

# 4. Start listener
.\start-listener.bat

# 5. Test connection
sqlplus EMP_ADMIN/EMP_ADMIN@ORACLE_LOCAL
```

### Daily Usage

```powershell
# Start listener (if needed)
.\start-listener.bat

# Connect
sqlplus EMP_ADMIN/EMP_ADMIN@ORACLE_LOCAL

# Or without TNS (direct connection)
$env:ORACLE_HOME = "F:\Oracle\WINDOWS.X64_193000_db_home"
$env:ORACLE_SID = "localdb01"
sqlplus EMP_ADMIN/EMP_ADMIN
```

### No Dump? Use Seed Schema

If you don't have a Data Pump dump, you can still run the tree viewer locally using a **minimal seed schema**:

```powershell
.\Run-SeedSchema.ps1
```

This creates schema **DESIGN1** with one project ("Local Dev Project", ID 100) and a small tree. Then:

1. `.\src\powershell\database\docker\Switch-DatabaseTarget.ps1 -Target LOCAL`
2. Run tree launcher; choose schema **DESIGN1**, project **Local Dev Project**

See [scripts/seed/README.md](scripts/seed/README.md) for details.

### Files Created

| File | Purpose | Location |
|------|---------|----------|
| Database files | Datafiles, control files, redo logs | `F:\Oracle\oradata\localdb01\` |
| TNS configuration | Connection aliases | `F:\Oracle\WINDOWS.X64_193000_db_home\network\admin\` |
| Dump directory | Data Pump imports | `F:\Oracle\admin\dump\` |
| Logs | Alert logs, listener logs | `F:\Oracle\app\George\diag\` |

### Oracle Installation (If Needed)

If Oracle 19c isn't installed:

1. **Extract** `WINDOWS.X64_193000_db_home.zip` to `F:\Oracle\`
2. **Run** `F:\Oracle\WINDOWS.X64_193000_db_home\setup.exe` as Administrator
3. **Select** "Set Up Software Only"
4. **Choose** Single instance → Enterprise Edition
5. **Use** Virtual Account for Oracle Home User
6. **Complete** installation (registers with Windows)

Then run the quick start steps above.

---

## 📦 Docker Setup (Alternative)

<details>
<summary>Click to expand Docker setup instructions</summary>

### Prerequisites

- Docker Desktop with WSL2 backend
- Oracle Container Registry account
- Login: `docker login container-registry.oracle.com`
- Minimum 32GB RAM, 100GB disk

### Quick Start

```powershell
# Complete one-command setup:
.\Setup-LocalOracle.ps1

# Or manual step-by-step:
.\Start-OracleDocker.ps1
.\Initialize-SiemensDb.ps1
.\Import-DatabaseDump.ps1 -DumpFile "path\to\your.dmp"
.\Verify-LocalDatabase.ps1
```

### Docker Architecture

```
Container: oracle-tecnomatix-12c
├─ Image: container-registry.oracle.com/database/enterprise:12.2.0.1
├─ SID: EMS12
├─ Port: 1521 (Oracle)
├─ Port: 5500 (Enterprise Manager)
├─ Character Set: AL32UTF8
└─ Volumes:
   ├─ oradata (persistent database files)
   ├─ scripts/setup (tablespaces + after_install.sql)
   ├─ siemens-scripts (Siemens installation reference)
   └─ volumes/dump (Data Pump imports)
```

</details>

---

## 💾 Database Configuration

### Tablespaces

| Tablespace | Size | Extent | Purpose |
|------------|------|--------|---------|
| PP_DATA_128K | 200MB → 32GB | 128KB | Small data objects |
| PP_DATA_1M | 300MB → 32GB | 1MB | Medium data objects |
| PP_DATA_10M | 500MB → 32GB | 10MB | Large data (REL_COMMON) |
| PP_INDEX_128K | 200MB → 32GB | 128KB | Small indexes |
| PP_INDEX_1M | 300MB → 32GB | 1MB | Medium indexes |
| PP_INDEX_10M | 500MB → 32GB | 10MB | Large indexes |
| AQ_DATA | 200MB → 32GB | 128KB | Advanced Queuing |
| PERFSTAT_DATA | 200MB → 32GB | Auto | Performance statistics |

All tablespaces:
- **AUTOEXTEND**: ON
- **MAX SIZE**: 32GB
- **LOGGING**: Enabled
- **Segment Management**: AUTO

### Roles & Users

**Roles Created:**
- `empower_admin_role` - Full administrative access
- `ems_access_role` - Standard user access
- `schema_owner_role` - Schema management
- `aq_role` - Advanced Queuing operations
- `reset_tables_role` - Table reset operations
- `schema_migration_role` - Schema migrations
- `archive_project_role` - Project archival
- `data_analysis_role` - Data analysis

**Admin User:**
- **Username**: EMP_ADMIN
- **Password**: EMP_ADMIN (development only!)
- **Default Tablespace**: PP_DATA_128K
- **Roles**: All Siemens roles granted

**System Users:**
- **SYS**: change_on_install
- **SYSTEM**: manager

### Memory Configuration

```sql
-- Current settings (optimized for 31GB system RAM)
sga_target = 2G
pga_aggregate_target = 512M
memory_management = ASMM (Automatic Shared Memory Management)
```

---

## 🔄 Data Import

### Import Dump File (Native)

```powershell
# 1. Copy dump file
Copy-Item "path\to\your.dmp" "F:\Oracle\admin\dump\"

# 2. Import with Data Pump
$env:ORACLE_HOME = "F:\Oracle\WINDOWS.X64_193000_db_home"
$env:ORACLE_SID = "localdb01"
$env:PATH = "$env:ORACLE_HOME\bin;$env:PATH"

impdp system/manager directory=DUMP_DIR dumpfile=your_file.dmp full=y logfile=import.log

# 3. Monitor progress
Get-Content "F:\Oracle\admin\dump\import.log" -Wait
```

### Import Options

```powershell
# Specific schemas
impdp system/manager directory=DUMP_DIR `
  dumpfile=your_file.dmp `
  schemas=DESIGN1,DESIGN2 `
  logfile=import_schemas.log

# With parallel processing
impdp system/manager directory=DUMP_DIR `
  dumpfile=your_file.dmp `
  full=y `
  parallel=4 `
  logfile=import_parallel.log

# Remap schema
impdp system/manager directory=DUMP_DIR `
  dumpfile=your_file.dmp `
  remap_schema=OLDSCHEMA:NEWSCHEMA
```

---

## 🔧 Troubleshooting

### Database Won't Start (Native)

```powershell
# Check Oracle service
Get-Service OracleService* | Format-Table -AutoSize

# Start service
Start-Service OracleServicelocaldb01

# Check alert log
Get-Content "F:\Oracle\app\George\diag\rdbms\localdb01\localdb01\trace\alert_localdb01.log" -Tail 50
```

### Listener Issues

```powershell
# Check listener
cd F:\Oracle\WINDOWS.X64_193000_db_home\bin
.\lsnrctl.exe status

# Restart listener
.\lsnrctl.exe stop
.\lsnrctl.exe start

# Or use script
cd C:\Users\George\source\repos\SimTreeNav\docker\oracle
.\start-listener.bat
```

### TNS Connection Errors

**ORA-12154: TNS:could not resolve**
```powershell
# Re-run TNS setup
.\setup-tns.ps1

# Or manually check
$env:TNS_ADMIN
Get-Content "F:\Oracle\WINDOWS.X64_193000_db_home\network\admin\tnsnames.ora"
```

**ORA-12541: TNS:no listener**
```powershell
# Start listener
.\start-listener.bat
```

**ORA-12505: TNS:listener does not know of SID**
```sql
-- Wait 30 seconds or force registration
sqlplus / as sysdba
ALTER SYSTEM REGISTER;
EXIT;
```

### Docker Troubleshooting

<details>
<summary>Click for Docker-specific troubleshooting</summary>

```powershell
# Check Docker
docker ps -a

# View logs
docker logs oracle-tecnomatix-12c --tail 100

# Login to Oracle registry
docker login container-registry.oracle.com

# Restart container
docker-compose restart
```

</details>

---

## 🔗 Connection Information

### Native Windows (Current)

| Property | Value |
|----------|-------|
| **Host** | localhost |
| **Port** | 1521 |
| **SID** | localdb01 |
| **TNS Name** | ORACLE_LOCAL |
| **Service Name** | localdb01 |
| **SYS Password** | change_on_install |
| **SYSTEM Password** | manager |
| **EMP_ADMIN** | EMP_ADMIN/EMP_ADMIN |
| **Character Set** | AL32UTF8 |

### Connection Strings

```sql
-- SQL*Plus
sqlplus EMP_ADMIN/EMP_ADMIN@ORACLE_LOCAL
sqlplus sys/change_on_install@ORACLE_LOCAL as sysdba

-- JDBC
jdbc:oracle:thin:@localhost:1521:localdb01

-- ODP.NET
Data Source=ORACLE_LOCAL;User Id=EMP_ADMIN;Password=EMP_ADMIN;

-- PowerShell (with CredentialManager.ps1)
$conn = Get-DbConnectionString -TNSName "ORACLE_LOCAL"
```

---

## 🔄 Database Target Switching

```powershell
# Switch to local database
cd ..\..\src\powershell\database\docker
.\Switch-DatabaseTarget.ps1 -Target LOCAL

# Switch back to remote (production)
.\Switch-DatabaseTarget.ps1 -Target REMOTE

# Check current target
Get-Content "..\..\..\..\config\database-target.json" | ConvertFrom-Json
```

The `CredentialManager.ps1` auto-detects the active target from `config/database-target.json`.

---

## 📁 Files Reference

### Native Setup Scripts

| File | Purpose | Requires Admin |
|------|---------|----------------|
| `create-database-cmd.bat` | Creates Oracle 19c database | ✅ Yes |
| `setup-siemens.bat` | Creates tablespaces & roles | ✅ Yes |
| `setup-tns.ps1` | Configures TNS | ❌ No |
| `start-listener.bat` | Starts Oracle listener | ❌ No |

### Docker Setup Scripts

| File | Purpose |
|------|---------|
| `Setup-LocalOracle.ps1` | Master Docker setup |
| `Start-OracleDocker.ps1` | Start container |
| `Stop-OracleDocker.ps1` | Stop container |
| `Initialize-SiemensDb.ps1` | Create schema in Docker |
| `Import-DatabaseDump.ps1` | Data Pump import (Docker) |

### SQL Scripts

| File | Purpose |
|------|---------|
| `scripts/setup/01-create-tablespaces.sql` | Creates 8 Siemens tablespaces |
| `scripts/setup/02-after-install.sql` | Creates roles and EMP_ADMIN user |

### Configuration Files

| File | Purpose |
|------|---------|
| `../../config/tnsnames.ora.template` | TNS names configuration |
| `../../config/database-target.json` | Current database target (LOCAL/REMOTE) |
| `.env` | Docker credentials (gitignored) |
| `docker-compose.yml` | Docker orchestration |

---

## 📊 Verification Queries

```sql
-- Connect first
sqlplus EMP_ADMIN/EMP_ADMIN@ORACLE_LOCAL

-- Check database info
SELECT instance_name, version, status, host_name
FROM v$instance;

-- Check tablespaces
SELECT tablespace_name, status, contents, extent_management
FROM dba_tablespaces
WHERE tablespace_name LIKE 'PP_%'
   OR tablespace_name IN ('AQ_DATA', 'PERFSTAT_DATA')
ORDER BY tablespace_name;

-- Check roles
SELECT granted_role FROM dba_role_privs
WHERE grantee = 'EMP_ADMIN'
ORDER BY granted_role;

-- Check datafiles
SELECT file_name, tablespace_name,
       ROUND(bytes/1024/1024, 2) as size_mb
FROM dba_data_files
ORDER BY tablespace_name;

-- Check memory
SELECT * FROM v$memory_target_advice
WHERE memory_size <= 3072;

EXIT;
```

---

## 🔐 Security Notes

### Development Environment

⚠️ **This configuration is for LOCAL DEVELOPMENT ONLY**

- Simple passwords used for convenience
- No encryption on network connections
- Default ports exposed to localhost
- Password complexity disabled

### Production Recommendations

```sql
-- Change all passwords
ALTER USER sys IDENTIFIED BY "ComplexPassword123!";
ALTER USER system IDENTIFIED BY "AnotherSecurePass456!";
ALTER USER EMP_ADMIN IDENTIFIED BY "SecurePassword789!";

-- Enable password policies
ALTER PROFILE DEFAULT LIMIT
  PASSWORD_LIFE_TIME 90
  FAILED_LOGIN_ATTEMPTS 5
  PASSWORD_LOCK_TIME 1;

-- Enable encryption
ALTER SYSTEM SET ENCRYPTION WALLET OPEN IDENTIFIED BY "wallet_password";
```

---

## 📝 Maintenance

### Daily Operations

```powershell
# Check status
Get-Service OracleService* | Format-Table
.\start-listener.bat  # If needed
```

### Weekly Maintenance

```sql
-- Connect as SYSDBA
sqlplus sys/change_on_install@ORACLE_LOCAL as sysdba

-- Gather statistics
EXEC DBMS_STATS.GATHER_DATABASE_STATS(cascade=>TRUE);

-- Check invalid objects
SELECT owner, object_name, object_type, status
FROM dba_objects
WHERE status = 'INVALID'
ORDER BY owner, object_type, object_name;

-- Check tablespace usage
SELECT tablespace_name,
       ROUND(used_percent, 2) as used_pct,
       ROUND(used_space * 8192/1024/1024, 2) as used_mb,
       ROUND(tablespace_size * 8192/1024/1024, 2) as total_mb
FROM dba_tablespace_usage_metrics
WHERE tablespace_name LIKE 'PP_%'
ORDER BY used_percent DESC;
```

### Backup (Native)

```powershell
# Export full database
$env:ORACLE_HOME = "F:\Oracle\WINDOWS.X64_193000_db_home"
$env:ORACLE_SID = "localdb01"
$env:PATH = "$env:ORACLE_HOME\bin;$env:PATH"

$date = Get-Date -Format "yyyyMMdd"
expdp system/manager directory=DUMP_DIR `
  dumpfile="backup_$date.dmp" `
  logfile="backup_$date.log" `
  full=y

# Copy to backup location
Copy-Item "F:\Oracle\admin\dump\backup_$date.dmp" "\\backup-server\oracle\"
```

---

## 🐛 Known Issues

### Native Windows

**Issue**: Listener doesn't auto-start after reboot
**Workaround**: Run `.\start-listener.bat` or set listener service to auto-start

**Issue**: TNS-12505 on first connection after database start
**Solution**: Wait 30 seconds or run `ALTER SYSTEM REGISTER;`

**Issue**: ORA-01109: database not open
**Solution**: Start database manually: `sqlplus / as sysdba` → `STARTUP;`

### Docker

**Issue**: Container health check takes 10-15 minutes
**Solution**: This is normal for first startup - wait patiently

**Issue**: Out of disk space
**Solution**: `docker system prune -a` and increase Docker disk allocation

---

## 📚 Additional Resources

- [Oracle 19c Documentation](https://docs.oracle.com/en/database/oracle/oracle-database/19/)
- [Data Pump Guide](https://docs.oracle.com/en/database/oracle/oracle-database/19/sutil/oracle-data-pump.html)
- [Siemens Tecnomatix Docs](https://docs.plm.automation.siemens.com/)
- [Project Memory](.claude/projects/.../memory/MEMORY.md)

---

**Version**: 2.0
**Last Updated**: February 5, 2026
**Setup Type**: Native Windows Oracle 19c (Primary) + Docker 12c (Alternative)
**Database**: Oracle 19c Enterprise Edition (19.3.0.0.0)
**Authors**: Claude + George
