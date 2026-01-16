# SimTreeNav Deployment Guide

> **Document Version:** 1.0  
> **Last Updated:** 2026-01-16

## Overview

This guide covers installation, configuration, and deployment of SimTreeNav for various environments.

## Prerequisites

### System Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Windows 10 | Windows 10/11, Windows Server 2019+ |
| PowerShell | 5.1 | 5.1 or PowerShell 7+ |
| Memory | 4 GB | 8 GB+ |
| Disk Space | 100 MB | 500 MB (with extracted data) |
| Browser | Chrome 90+, Edge 90+ | Latest Chrome/Edge/Firefox |

### Network Requirements

- Access to Oracle database server (port 1521 default)
- Network path to TNS name resolution
- Optional: HTTPS for TNS encryption

### Oracle Requirements

- Oracle 12c Instant Client or later
- Read access to target schemas (DESIGN1-5)
- TNS name configured for database instances

---

## Installation Methods

### Method 1: Git Clone (Recommended for Development)

```powershell
# Clone the repository
git clone https://github.com/GeorgeMcIntyre-Web/SimTreeNav.git
cd SimTreeNav

# Install Oracle Instant Client (if needed)
.\src\powershell\database\install-oracle-client.ps1

# Configure environment
.\src\powershell\database\setup-env-vars.ps1

# Test connection
.\src\powershell\database\test-connection.ps1
```

### Method 2: Release Package (Recommended for Production)

1. **Download** the latest release from [GitHub Releases](https://github.com/GeorgeMcIntyre-Web/SimTreeNav/releases)

2. **Verify checksum**
   ```powershell
   $hash = (Get-FileHash SimTreeNav-0.4.0.zip -Algorithm SHA256).Hash
   Get-Content checksums.sha256
   # Verify hashes match
   ```

3. **Extract** to installation directory
   ```powershell
   Expand-Archive SimTreeNav-0.4.0.zip -DestinationPath C:\Tools\SimTreeNav
   cd C:\Tools\SimTreeNav
   ```

4. **Configure** Oracle and environment

---

## Configuration

### Step 1: Oracle Instant Client

If Oracle Instant Client is not installed:

```powershell
.\src\powershell\database\install-oracle-client.ps1
```

This script:
- Downloads Oracle Instant Client 12c Basic package
- Extracts to `C:\oracle\instantclient`
- Adds to system PATH
- Configures `ORACLE_HOME` and `TNS_ADMIN`

### Step 2: TNS Names Configuration

Create or update `tnsnames.ora`:

```powershell
# Copy template
Copy-Item config\tnsnames.ora.template $env:TNS_ADMIN\tnsnames.ora

# Edit with your database details
notepad $env:TNS_ADMIN\tnsnames.ora
```

Example `tnsnames.ora` entry:

```
DB01 =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = db-server.domain.com)(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = db01)
    )
  )
```

### Step 3: Environment Variables

```powershell
.\src\powershell\database\setup-env-vars.ps1
```

Or manually set:

```powershell
[Environment]::SetEnvironmentVariable("ORACLE_HOME", "C:\oracle\instantclient", "User")
[Environment]::SetEnvironmentVariable("TNS_ADMIN", "C:\oracle\instantclient\network\admin", "User")
$env:PATH = "C:\oracle\instantclient;$env:PATH"
```

### Step 4: Verify Installation

```powershell
.\src\powershell\database\test-connection.ps1 -TNSName "DB01"
```

---

## PC Profile Setup

### First-Time Setup

When you first run the launcher, it will create a PC profile:

```powershell
.\src\powershell\main\tree-viewer-launcher.ps1
```

Or initialize manually:

```powershell
.\src\powershell\database\Initialize-PCProfile.ps1
```

### Profile Configuration

Edit `config/pc-profiles.json` (created after first run):

```json
{
  "currentProfile": "my-workstation",
  "profiles": [
    {
      "name": "my-workstation",
      "hostname": "MY-PC-NAME",
      "description": "My development workstation",
      "isDefault": true,
      "servers": [
        {
          "name": "des-sim-db1",
          "displayName": "Production Server",
          "instances": [
            {
              "name": "db01",
              "tnsName": "DB01",
              "service": "db01"
            },
            {
              "name": "db02",
              "tnsName": "DB02",
              "service": "db02"
            }
          ],
          "defaultInstance": "db01"
        }
      ]
    }
  ]
}
```

---

## Credential Configuration

### DEV Mode (Default)

Suitable for individual workstations:

```powershell
# Credentials stored in encrypted XML files
# Location: config/.credentials/

# Initialize credentials
.\src\powershell\database\Initialize-DbCredentials.ps1
```

### PROD Mode

Suitable for shared servers:

```json
// config/credential-config.json
{
  "mode": "PROD",
  "description": "Uses Windows Credential Manager"
}
```

```powershell
# Credentials stored in Windows Credential Manager
# Access via cmdkey or Credential Manager UI
```

---

## Database User Setup

### Create Read-Only User (Recommended)

Run as DBA:

```sql
-- Create user
CREATE USER simtreenav_reader IDENTIFIED BY <secure_password>;

-- Grant connect privilege
GRANT CONNECT TO simtreenav_reader;

-- Grant read access to required tables (per schema)
GRANT SELECT ON DESIGN12.COLLECTION_ TO simtreenav_reader;
GRANT SELECT ON DESIGN12.REL_COMMON TO simtreenav_reader;
GRANT SELECT ON DESIGN12.CLASS_DEFINITIONS TO simtreenav_reader;
GRANT SELECT ON DESIGN12.DF_ICONS_DATA TO simtreenav_reader;
GRANT SELECT ON DESIGN12.ROBCADSTUDY_ TO simtreenav_reader;
GRANT SELECT ON DESIGN12.SIMUSER_ACTIVITY TO simtreenav_reader;

-- Repeat for each schema (DESIGN1-5)
```

### Use Existing Credentials

If using existing database credentials:

```powershell
# Enter credentials when prompted
.\src\powershell\database\Initialize-DbCredentials.ps1 -ServerName "des-sim-db1"
```

---

## Deployment Scenarios

### Scenario 1: Single Developer Workstation

```
Installation:
  └── C:\Tools\SimTreeNav\

Configuration:
  └── User profile
      └── DEV mode credentials
      └── Single PC profile
      └── Local tnsnames.ora
```

### Scenario 2: Team Development Environment

```
Installation:
  └── \\fileserver\tools\SimTreeNav\  (shared)

Per-User Configuration:
  └── %APPDATA%\SimTreeNav\
      └── pc-profiles.json (per user)
      └── .credentials\ (per user, encrypted)
```

### Scenario 3: Production Server

```
Installation:
  └── C:\Production\SimTreeNav\

Configuration:
  └── PROD mode credentials (Windows Credential Manager)
  └── Centrally managed PC profiles
  └── Read-only database user
  └── TNS encryption enabled
```

---

## Security Hardening

### For Production Deployments

1. **Use PROD credential mode**
   ```json
   { "mode": "PROD" }
   ```

2. **Enable TNS encryption**
   ```
   # sqlnet.ora
   SQLNET.ENCRYPTION_CLIENT = REQUIRED
   SQLNET.ENCRYPTION_TYPES_CLIENT = (AES256)
   ```

3. **Use read-only database user**

4. **Restrict file permissions**
   ```powershell
   icacls "C:\Production\SimTreeNav\config" /inheritance:r
   icacls "C:\Production\SimTreeNav\config" /grant:r "Administrators:(OI)(CI)F"
   ```

5. **Audit access**
   - Enable Windows audit logging
   - Monitor credential access

---

## Troubleshooting

### Connection Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| TNS: could not resolve | TNS_ADMIN not set | Run `setup-env-vars.ps1` |
| ORA-12541: No listener | Wrong port/host | Check `tnsnames.ora` |
| ORA-01017: Invalid login | Wrong credentials | Re-run credential init |
| ORA-28000: Account locked | Too many failures | Contact DBA |

### Permission Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Access denied to .credentials | Wrong owner | Check DPAPI encryption |
| Cannot read config files | File permissions | Reset with icacls |
| Schema access denied | Missing grants | Run SQL grants |

### Performance Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Slow tree generation | Large project | Use pagination |
| Icon extraction slow | Many icons | Normal (5-10s) |
| Browser slow | Large HTML | Use modern browser |

---

## Updating

### From Git

```powershell
cd SimTreeNav
git pull origin main
```

### From Release Package

1. Backup configuration
   ```powershell
   Copy-Item config\pc-profiles.json config\pc-profiles.backup.json
   ```

2. Extract new version
   ```powershell
   Expand-Archive SimTreeNav-0.5.0.zip -DestinationPath C:\Tools\SimTreeNav-new
   ```

3. Restore configuration
   ```powershell
   Copy-Item config\pc-profiles.backup.json C:\Tools\SimTreeNav-new\config\pc-profiles.json
   ```

4. Switch to new version

---

## Verification Checklist

After deployment, verify:

- [ ] Oracle Instant Client installed and in PATH
- [ ] TNS names resolve correctly
- [ ] Environment variables set (ORACLE_HOME, TNS_ADMIN)
- [ ] PC profile created
- [ ] Credentials cached (test with launcher)
- [ ] Tree generation works
- [ ] Icons display correctly
- [ ] Search functionality works
- [ ] Output HTML opens in browser

---

## Support

- **Documentation:** [docs/](.)
- **Issues:** [GitHub Issues](https://github.com/GeorgeMcIntyre-Web/SimTreeNav/issues)
- **Security:** See [SECURITY.md](../SECURITY.md)

---

## Related Documentation

- [Architecture](ARCHITECTURE.md) - System design
- [Features](FEATURES.md) - Feature list
- [Quick Start Guide](QUICK-START-GUIDE.md) - Getting started
- [Oracle Setup](README-ORACLE-SETUP.md) - Oracle configuration
