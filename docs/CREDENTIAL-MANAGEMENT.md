# Credential Management System

## Overview

The SimTreeNav application now includes a secure credential management system with **DEV** and **PROD** modes to handle database passwords securely.

### Features

- **DEV Mode**: Encrypted file storage - set password once, never prompt again during development
- **PROD Mode**: Windows Credential Manager - secure, auditable credential storage
- **Auto-detection**: System automatically detects environment mode
- **Fallback**: Gracefully falls back to default password if credential system unavailable
- **Zero git commits**: All credential files are gitignored

---

## Quick Start

### First-Time Setup

Run the initialization script to configure credentials:

```powershell
.\src\powershell\database\Initialize-DbCredentials.ps1
```

This will:
1. Ask you to choose DEV or PROD mode
2. Prompt for your database password **once**
3. Store it securely (encrypted file or Windows Credential Manager)
4. Test the connection
5. Save configuration

### DEV Mode (Recommended for Development)

**Perfect for**: Your local development machine

**Benefits**:
- Enter password **once**, never again
- Credentials encrypted to your Windows account (DPAPI)
- Works offline
- Fast and convenient

**Storage Location**: `config/.credentials/` (gitignored)

**Security**: Only you, on this machine, can decrypt

### PROD Mode (Recommended for Servers)

**Perfect for**: Shared servers, production deployments (like des-sim-db1)

**Benefits**:
- Windows Credential Manager integration
- Auditable credential access
- System-level security
- Can be managed via Group Policy

**Storage Location**: Windows Credential Manager (`Control Panel` → `Credential Manager`)

**Security**: Windows security controls apply

---

## Usage

Once configured, all scripts automatically use the credential system. No code changes needed!

###Example 1: Tree Viewer

```powershell
.\src\powershell\main\tree-viewer-launcher.ps1
```

✓ Automatically loads credentials
✓ No password prompt
✓ Works in DEV or PROD mode

### Example 2: Generate Tree

```powershell
.\src\powershell\main\generate-tree-html.ps1 -TNSName "SIEMENS_PS_DB" -Schema "DESIGN1" -ProjectId "123" -ProjectName "MyProject"
```

✓ Credentials loaded automatically
✓ Zero interruptions

---

## Configuration Files

### credential-config.json

Located at: `config/credential-config.json`

```json
{
  "Mode": "DEV",
  "ConfiguredDate": "2026-01-15 12:00:00",
  "ConfiguredBy": "DOMAIN\\username",
  "Machine": "COMPUTERNAME"
}
```

**⚠️ IMPORTANT**: This file is gitignored by default. Don't commit it!

### Encrypted Credential Files (DEV Mode)

Located at: `config/.credentials/<MACHINE>_<USERNAME>_<TNSNAME>.xml`

**Example**: `config/.credentials/MYPC_georgem_SIEMENS_PS_DB.xml`

**Security**:
- Encrypted using Windows Data Protection API (DPAPI)
- User-specific encryption (only you can decrypt)
- Machine-specific (only on this PC)

**⚠️ DO NOT**:
- Copy to another machine (won't decrypt)
- Commit to git (gitignored automatically)
- Share with others (they can't use it)

---

## Management Commands

### Update Credentials

To change your password:

```powershell
.\src\powershell\database\Initialize-DbCredentials.ps1 -Force
```

This will:
- Prompt for new password
- Update stored credentials
- Test connection

### Switch Modes (DEV ↔ PROD)

1. **Delete existing credentials**:
   ```powershell
   # DEV mode
   Remove-Item config\.credentials\* -Force

   # PROD mode
   cmdkey /delete:SimTreeNav_SIEMENS_PS_DB
   ```

2. **Re-run initialization**:
   ```powershell
   .\src\powershell\database\Initialize-DbCredentials.ps1
   ```

3. **Choose new mode** when prompted

### View Stored Credentials

**DEV Mode**:
```powershell
# List credential files
Get-ChildItem config\.credentials\
```

**PROD Mode**:
```powershell
# Open Windows Credential Manager
control /name Microsoft.CredentialManager

# Or via command line
cmdkey /list | Select-String "SimTreeNav"
```

### Remove Credentials

**DEV Mode**:
```powershell
Remove-Item config\.credentials\* -Recurse -Force
```

**PROD Mode**:
```powershell
cmdkey /delete:SimTreeNav_SIEMENS_PS_DB
```

### Test Credentials

```powershell
# Import credential manager
Import-Module .\src\powershell\utilities\CredentialManager.ps1

# Test credentials
Test-DbCredential -TNSName "SIEMENS_PS_DB"
```

---

## How It Works

### Architecture

```
[PowerShell Script]
        ↓
[CredentialManager.ps1]
        ↓
    ┌───────┴──────────┐
    ↓                  ↓
[DEV Mode]        [PROD Mode]
Encrypted File    Windows Credential Manager
(DPAPI)           (System Integration)
```

### Credential Flow

1. **Script starts** → Imports `CredentialManager.ps1`
2. **Get credentials** → Calls `Get-DbConnectionString`
3. **Check mode** → Reads `credential-config.json`
4. **Load credentials**:
   - **DEV**: Import encrypted XML file
   - **PROD**: Query Windows Credential Manager
5. **Build connection string** → `username/password@tnsname AS SYSDBA`
6. **Execute SQL** → Connect to database

### Security Features

#### DEV Mode (Encrypted File)

**Encryption**: Windows Data Protection API (DPAPI)
- Uses your Windows login credentials as encryption key
- Encrypted data includes:
  - Username
  - SecureString password
  - Metadata

**Protection Level**: User + Machine
- Only YOU on THIS MACHINE can decrypt
- Different user on same machine: **Cannot decrypt**
- Same user on different machine: **Cannot decrypt**

**File Format**: XML (Export-Clixml)
```xml
<Objs>
  <Obj RefId="0">
    <PSCredential>
      <UserName>sys</UserName>
      <Password>01000000d08c9ddf0115d1118c7a00c04fc297eb...</Password>
    </PSCredential>
  </Obj>
</Objs>
```

#### PROD Mode (Windows Credential Manager)

**Storage**: Windows Credential Store
- Target Name: `SimTreeNav_<TNSName>`
- Type: Generic Credential
- Persistence: Enterprise (if domain-joined)

**Security Controls**:
- Windows access control lists (ACLs)
- Group Policy support
- Audit logging available
- Remote management via PowerShell

**Access**:
- Only administrators and credential owner
- Can be managed via Group Policy

---

## Troubleshooting

### Issue: "Failed to get credentials, using default"

**Cause**: Credential manager not found or credentials not initialized

**Solution**:
```powershell
.\src\powershell\database\Initialize-DbCredentials.ps1
```

### Issue: "Import-Module: File not found"

**Cause**: Script path mismatch or `CredentialManager.ps1` missing

**Solution**:
1. Verify file exists:
   ```powershell
   Test-Path .\src\powershell\utilities\CredentialManager.ps1
   ```
2. Run from repository root
3. Check file wasn't deleted

### Issue: "Cannot decrypt credential file"

**Cause**: Trying to use credential file from another user/machine

**Solution**:
1. Delete invalid credential files:
   ```powershell
   Remove-Item config\.credentials\* -Force
   ```
2. Re-run initialization:
   ```powershell
   .\src\powershell\database\Initialize-DbCredentials.ps1
   ```

### Issue: Oracle connection fails

**Cause**: Wrong password, network issue, or Oracle not installed

**Solution**:
1. Test credential system:
   ```powershell
   Import-Module .\src\powershell\utilities\CredentialManager.ps1
   Test-DbCredential -TNSName "SIEMENS_PS_DB"
   ```
2. Test Oracle connectivity:
   ```powershell
   sqlplus -V  # Check Oracle client installed
   tnsping SIEMENS_PS_DB  # Check TNS configuration
   ```
3. Update password:
   ```powershell
   .\src\powershell\database\Initialize-DbCredentials.ps1 -Force
   ```

### Issue: Prompts for password every time (PROD mode)

**Cause**: Windows Credential Manager limitation - password must be entered once per PowerShell session

**Workaround**: Use DEV mode for development machines
```powershell
# Switch to DEV mode
Remove-Item config\credential-config.json
.\src\powershell\database\Initialize-DbCredentials.ps1
# Select DEV mode
```

---

## Migration Guide

### Migrating from Hardcoded Passwords

If you have existing scripts with `sys/change_on_install`, follow these steps:

1. **Run initialization**:
   ```powershell
   .\src\powershell\database\Initialize-DbCredentials.ps1
   ```

2. **Enter your REAL password** (not `change_on_install`)

3. **Test the connection**:
   ```powershell
   .\src\powershell\main\tree-viewer-launcher.ps1
   ```

4. **Done!** All scripts now use secure credentials

### Deploying to des-sim-db1 (Windows Server 2016)

1. **Copy repository** to server:
   ```powershell
   xcopy \\local-pc\SimTreeNav C:\Tools\SimTreeNav /E /I
   ```

2. **Run initialization as Administrator**:
   ```powershell
   cd C:\Tools\SimTreeNav
   .\src\powershell\database\Initialize-DbCredentials.ps1
   ```

3. **Choose PROD mode** when prompted

4. **Enter database password**

5. **Test**:
   ```powershell
   .\src\powershell\main\tree-viewer-launcher.ps1
   ```

6. **Configure scheduled tasks** (optional):
   - Scheduled tasks will use Windows Credential Manager
   - No password in task configuration needed

---

## Best Practices

### For Development (DEV Mode)

✅ **DO**:
- Use DEV mode on your personal development machine
- Set password once and forget it
- Keep `config/.credentials/` in `.gitignore`

❌ **DON'T**:
- Commit credential files to git
- Copy credential files to other machines
- Share credential files with team members

### For Production (PROD Mode)

✅ **DO**:
- Use PROD mode on shared servers
- Use PROD mode for scheduled tasks
- Document credential target names
- Use Group Policy for enterprise deployments

❌ **DON'T**:
- Use PROD mode on development machines (unnecessary prompts)
- Hardcode passwords anywhere
- Share Administrator access to Credential Manager

### Security

✅ **DO**:
- Use strong database passwords
- Rotate passwords regularly
- Audit credential access on production servers
- Use read-only database accounts where possible

❌ **DON'T**:
- Use `sys` with SYSDBA for production scripts (create read-only user)
- Store passwords in plain text files
- Commit `credential-config.json` to git
- Email or chat passwords

---

## API Reference

See [CredentialManager.ps1](../src/powershell/utilities/CredentialManager.ps1) for full API documentation.

### Key Functions

#### Get-DbCredential
```powershell
$cred = Get-DbCredential -TNSName "SIEMENS_PS_DB" [-Username "sys"] [-ForcePrompt]
```

#### Get-DbConnectionString
```powershell
$connStr = Get-DbConnectionString -TNSName "SIEMENS_PS_DB" [-AsSysDBA] [-ForcePrompt]
```

#### Test-DbCredential
```powershell
Test-DbCredential -TNSName "SIEMENS_PS_DB"
```

---

## FAQ

### Q: Do I need to update my scripts?

**A**: No! All existing scripts automatically use the credential system with fallback to default password.

### Q: What happens if credential system fails?

**A**: Scripts fallback to `change_on_install` default password (which you should change on your database).

### Q: Can I use both DEV and PROD mode?

**A**: No, one mode per machine. Choose based on your use case.

### Q: How do I know which mode I'm in?

**A**: Check `config/credential-config.json` or run initialization script.

### Q: Is this secure?

**A**: Yes!
- **DEV**: DPAPI encryption (Windows-standard)
- **PROD**: Windows Credential Manager (enterprise-grade)
- Both are secure for their intended use cases

### Q: Can I use this with multiple databases?

**A**: Yes! Each TNS name gets its own credential entry.

---

## Support

- **Issues**: See [README.md](../README.md#troubleshooting)
- **Questions**: Open a GitHub issue
- **Security Concerns**: Contact repository administrator

---

**Last Updated**: 2026-01-15
**Version**: 1.0
**Credential System**: DEV/PROD dual-mode
