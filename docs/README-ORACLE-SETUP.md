# Oracle 12c Client Installation Guide

This guide will help you install and configure Oracle 12c Instant Client to connect to the Siemens Process Simulation database via terminal.

## Prerequisites

- Windows 10/11 (64-bit)
- PowerShell 5.1 or later
- Administrator privileges (recommended)
- Network access to the Oracle 12c database server

## Installation Steps

### Step 1: Download Oracle Instant Client

Oracle Instant Client requires manual download from Oracle's website due to license acceptance:

1. Visit: https://www.oracle.com/database/technologies/instant-client/winx64-64-downloads.html
2. Accept the license agreement
3. Download the following packages (for Oracle 12.2.0.1.0):
   - **instantclient-basic-windows.x64-12.2.0.1.0.zip** (Required)
   - **instantclient-sqlplus-windows.x64-12.2.0.1.0.zip** (Required)
   - **instantclient-tools-windows.x64-12.2.0.1.0.zip** (Optional, for additional tools)

4. Place the downloaded ZIP files in: `%TEMP%\oracle-instantclient-downloads`

### Step 2: Run Installation Script

Open PowerShell as Administrator and run:

```powershell
.\install-oracle-client.ps1
```

Or if you've already downloaded the files:

```powershell
.\install-oracle-client.ps1 -SkipDownload
```

The script will:
- Extract Oracle Instant Client to `C:\Oracle\instantclient_12_2`
- Set up environment variables (ORACLE_HOME, TNS_ADMIN)
- Add Oracle bin directory to PATH

### Step 3: Configure TNS Names (Optional but Recommended)

1. Navigate to: `C:\Oracle\instantclient_12_2\network\admin`
2. Copy `tnsnames.ora.template` to `tnsnames.ora`
3. Edit `tnsnames.ora` with your database connection details:

```ini
SIEMENS_PS_DB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = your_db_hostname)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = your_service_name)
    )
  )
```

Replace:
- `your_db_hostname` - Database server hostname or IP address
- `your_service_name` - Oracle service name (or use SID if needed)

### Step 4: Restart Terminal

Close and reopen your PowerShell/terminal window to load the new environment variables.

### Step 5: Verify Installation

Test that sqlplus is available:

```powershell
sqlplus -V
```

You should see the Oracle SQL*Plus version information.

## Connecting to the Database

### Method 1: Using TNS Name (Recommended)

If you've configured `tnsnames.ora`:

```powershell
sqlplus username/password@SIEMENS_PS_DB
```

### Method 2: Direct Connection String

```powershell
sqlplus username/password@"(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=hostname)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=servicename)))"
```

### Method 3: Using Test Script

Use the provided test script:

```powershell
# With TNS name
.\test-connection.ps1 -TnsName SIEMENS_PS_DB -Username your_user -Password your_pass

# With direct connection
.\test-connection.ps1 -Host dbhost -Port 1521 -ServiceName ORCL -Username your_user -Password your_pass
```

## Environment Variables

The installation sets the following environment variables:

- **ORACLE_HOME**: `C:\Oracle\instantclient_12_2`
- **TNS_ADMIN**: `C:\Oracle\instantclient_12_2\network\admin`
- **PATH**: Includes `C:\Oracle\instantclient_12_2\bin`

To manually update environment variables, run:

```powershell
.\setup-env-vars.ps1
```

## Troubleshooting

### sqlplus command not found

1. Verify environment variables are set:
   ```powershell
   $env:ORACLE_HOME
   $env:PATH
   ```

2. Restart your terminal/PowerShell

3. Manually run `setup-env-vars.ps1`

### Connection fails with "ORA-12154: TNS:could not resolve the connect identifier"

- Check that `tnsnames.ora` exists in `%TNS_ADMIN%`
- Verify the TNS name is spelled correctly
- Check that `TNS_ADMIN` environment variable points to the correct directory
- Try using a direct connection string instead

### Connection fails with "ORA-12541: TNS:no listener"

- Verify the database hostname/IP is correct
- Check that the port (usually 1521) is correct
- Ensure firewall allows connections to the database port
- Verify the database service is running

### Connection fails with "ORA-01017: invalid username/password"

- Double-check username and password
- Ensure the user account exists and is unlocked
- Verify you're connecting to the correct database

### Need to use SID instead of SERVICE_NAME

If your database uses SID instead of SERVICE_NAME, modify `tnsnames.ora`:

```ini
SIEMENS_PS_DB =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = hostname)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SID = your_sid)
    )
  )
```

## Files Included

- `install-oracle-client.ps1` - Main installation script
- `setup-env-vars.ps1` - Environment variable configuration
- `test-connection.ps1` - Connection testing script
- `tnsnames.ora.template` - TNS names configuration template
- `README-ORACLE-SETUP.md` - This file

## Additional Resources

- Oracle Instant Client Documentation: https://www.oracle.com/database/technologies/instant-client.html
- SQL*Plus User's Guide: https://docs.oracle.com/database/121/SQPUG/toc.htm
- Oracle Net Services Configuration: https://docs.oracle.com/database/121/NETRF/toc.htm

## Quick Connection (Pre-configured)

Your database connection details are already configured:
- **Server**: des-sim-db1
- **Instance**: db02
- **TNS Name**: SIEMENS_PS_DB

### Quick Connect Scripts

After installation, you can use these pre-configured scripts:

**Interactive connection:**
```powershell
.\connect-db.ps1
```

**Test connection:**
```powershell
.\test-connection.ps1
```

**Explore database structure:**
```powershell
.\explore-db.ps1
```

**Run custom queries:**
```powershell
.\query-db.ps1 -Query "SELECT * FROM USER_TABLES"
```

**Note**: You're connecting as SYS user with SYSDBA privileges. Use with caution - you have full database access. Since you're only exploring/understanding the database, consider using read-only queries.

## Support

For Siemens Process Simulation database-specific issues, contact your database administrator or Siemens support.
