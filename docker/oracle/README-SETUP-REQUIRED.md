# Oracle 19c Setup Required

## Issue

The Oracle 19c installation at `F:\Oracle\WINDOWS.X64_193000_db_home` was extracted from a ZIP file but never properly configured for Windows. This causes DBCA to fail with:

```
[FATAL] [DBT-05900] Unable to check if Oracle home user password is required or not.
```

## Solution

Run the Oracle setup wizard to properly register the installation:

### Step 1: Run Oracle Setup

```powershell
# Navigate to Oracle home
cd F:\Oracle\WINDOWS.X64_193000_db_home

# Run setup as Administrator
.\setup.exe
```

**Setup Options:**
1. Select "Set Up Software Only" (do NOT create a database yet)
2. Choose "Single instance database installation"
3. Select "Enterprise Edition"
4. Oracle base: `F:\Oracle`
5. Software location: `F:\Oracle\WINDOWS.X64_193000_db_home` (should be pre-filled)
6. Operating system groups: Use defaults
7. Complete the installation

### Step 2: After Setup Completes

Once setup finishes, run our database creation script:

```powershell
cd C:\Users\George\source\repos\SimTreeNav\docker\oracle
.\create-database-cmd.bat
```

## Alternative: Manual Database Creation (Advanced)

If you prefer not to run setup.exe, you can create the database manually using SQL commands:

1. Set environment variables:
   ```powershell
   $env:ORACLE_HOME = "F:\Oracle\WINDOWS.X64_193000_db_home"
   $env:ORACLE_SID = "localdb01"
   $env:PATH = "$env:ORACLE_HOME\bin;$env:PATH"
   ```

2. Create parameter file (F:\Oracle\WINDOWS.X64_193000_db_home\dbs\init localdb01.ora):
   ```
   db_name=localdb01
   memory_target=3G
   control_files=('F:\Oracle\oradata\localdb01\control01.ctl','F:\Oracle\oradata\localdb01\control02.ctl')
   ```

3. Create database using SQL:
   ```powershell
   # Start SQL*Plus
   sqlplus / as sysdba
   ```

   ```sql
   STARTUP NOMOUNT;

   CREATE DATABASE localdb01
     USER SYS IDENTIFIED BY change_on_install
     USER SYSTEM IDENTIFIED BY manager
     LOGFILE
       GROUP 1 ('F:\Oracle\oradata\localdb01\redo01.log') SIZE 100M,
       GROUP 2 ('F:\Oracle\oradata\localdb01\redo02.log') SIZE 100M,
       GROUP 3 ('F:\Oracle\oradata\localdb01\redo03.log') SIZE 100M
     CHARACTER SET AL32UTF8
     NATIONAL CHARACTER SET AL16UTF16
     DATAFILE 'F:\Oracle\oradata\localdb01\system01.dbf' SIZE 700M AUTOEXTEND ON
     SYSAUX DATAFILE 'F:\Oracle\oradata\localdb01\sysaux01.dbf' SIZE 550M AUTOEXTEND ON
     DEFAULT TABLESPACE users
       DATAFILE 'F:\Oracle\oradata\localdb01\users01.dbf' SIZE 500M AUTOEXTEND ON
     DEFAULT TEMPORARY TABLESPACE temp
       TEMPFILE 'F:\Oracle\oradata\localdb01\temp01.dbf' SIZE 100M AUTOEXTEND ON
     UNDO TABLESPACE undotbs1
       DATAFILE 'F:\Oracle\oradata\localdb01\undotbs01.dbf' SIZE 200M AUTOEXTEND ON;

   @?/rdbms/admin/catalog.sql
   @?/rdbms/admin/catproc.sql
   ```

## Recommended Approach

**Run setup.exe first** - this is the cleanest and most reliable method. It will:
- Register Oracle with Windows
- Create Oracle services
- Configure the Oracle home user
- Set up proper registry entries
- Enable DBCA to work correctly

After setup completes, all our automation scripts will work properly.
