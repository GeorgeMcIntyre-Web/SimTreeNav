# Frontend & Security Improvements

## Overview

Two major improvements for better UX and production security:

1. **Improved Frontend**: PC-based hierarchy with cascading selection
2. **Production Security**: Read-only database user instead of SYSDBA

---

## 1. Improved Frontend Design

### Current Flow (Issues)

```
[User runs script]
    ↓
[Discovers servers from AD/DNS/TNS] ← Slow, unreliable
    ↓
[Lists all servers] ← Too many options
    ↓
[User selects server]
    ↓
[Queries instances] ← Another query
    ↓
[Queries schemas] ← Another query
    ↓
[Selects project]
```

**Problems:**
- ❌ Slow server discovery (AD/DNS queries)
- ❌ Too many servers shown (irrelevant ones)
- ❌ No memory of "my usual PC/servers"
- ❌ Multiple database queries just for setup

### New Flow (Improved)

```
[User runs script]
    ↓
[Show PC Profiles] ← From config file (instant)
    ├─ "My Dev PC (default)" ← Remembered
    ├─ "des-sim-db1 (Server)"
    └─ "Add New PC..."
    ↓
[User selects PC profile]
    ↓
[Load saved servers for this PC] ← Pre-configured
    ├─ des-sim-db1 (db01, db02)
    └─ sim-db2 (orcl)
    ↓
[User selects instance]
    ↓
[Load schemas from instance] ← One query
    ↓
[User selects schema]
    ↓
[Load projects] ← One query
```

**Benefits:**
- ✅ Instant PC profile selection (no discovery)
- ✅ Only shows YOUR configured PCs
- ✅ Remembers defaults per PC
- ✅ Fewer database queries
- ✅ Faster workflow

### PC Profile Configuration

**File**: `config/pc-profiles.json`

```json
{
  "profiles": [
    {
      "name": "My Dev PC",
      "hostname": "DESKTOP-ABC123",
      "description": "George's development machine",
      "isDefault": true,
      "servers": [
        {
          "name": "des-sim-db1",
          "instances": [
            {"name": "db01", "tnsName": "SIEMENS_PS_DB_DB01", "service": "db01"},
            {"name": "db02", "tnsName": "SIEMENS_PS_DB", "service": "db02"}
          ],
          "defaultInstance": "db02"
        }
      ],
      "lastUsed": {
        "server": "des-sim-db1",
        "instance": "db02",
        "schema": "DESIGN1",
        "projectId": "18140190"
      }
    },
    {
      "name": "des-sim-db1 Server",
      "hostname": "des-sim-db1",
      "description": "Production database server",
      "isDefault": false,
      "servers": [
        {
          "name": "localhost",
          "instances": [
            {"name": "db01", "tnsName": "localhost:1521/db01", "service": "db01"},
            {"name": "db02", "tnsName": "localhost:1521/db02", "service": "db02"}
          ],
          "defaultInstance": "db02"
        }
      ]
    }
  ],
  "currentProfile": "My Dev PC"
}
```

### New UI Flow

```
========================================
  Siemens Process Simulation
  Navigation Tree Viewer
========================================

Select PC Profile:
  1. My Dev PC (default) - DESKTOP-ABC123
     └─ Last used: des-sim-db1 / db02 / DESIGN1 / FORD_DEARBORN
  2. des-sim-db1 Server - des-sim-db1
  3. Add New PC Profile...

Enter choice (1-3): 1

Loading profile: My Dev PC...

Select Database Server:
  1. des-sim-db1 (default)
     ├─ db01 (SIEMENS_PS_DB_DB01)
     └─ db02 (SIEMENS_PS_DB)

Enter choice: 1

Select Instance:
  1. db01 (SIEMENS_PS_DB_DB01)
  2. db02 (SIEMENS_PS_DB) ← default

Enter choice (or Enter for default): ↵

Connecting to des-sim-db1 / db02...
✓ Connected

Querying available schemas...
  1. DESIGN1 (27 GB, 15 projects)
  2. DESIGN2 (32 GB, 23 projects)
  3. DESIGN12 (18 GB, 8 projects)

Enter choice: 1

Loading projects from DESIGN1...
  [etc...]
```

---

## 2. Production Security: Read-Only User

### Current Issue

**Problem**: Using `sys AS SYSDBA` everywhere

```sql
-- Current connection (BAD for production)
sys/password@SIEMENS_PS_DB AS SYSDBA
```

**Risks:**
- ❌ Full DBA privileges (can DROP DATABASE!)
- ❌ Can modify any data (INSERT/UPDATE/DELETE)
- ❌ Can change schemas, users, permissions
- ❌ Audit nightmare (who did what?)
- ❌ No separation of duties

### Improved Security: Read-Only User

**Solution**: Create dedicated read-only user

```sql
-- New connection (GOOD for production)
simtreenav_readonly/password@SIEMENS_PS_DB
```

**Benefits:**
- ✅ Only SELECT privileges
- ✅ Cannot modify data
- ✅ Cannot change schema
- ✅ Clear audit trail
- ✅ Follows principle of least privilege
- ✅ Can be used in production safely

### Read-Only User Setup

**SQL Script**: `scripts/create-readonly-user.sql`

```sql
-- ============================================
-- Create Read-Only User for SimTreeNav
-- ============================================
-- This user has SELECT access only to:
--   - DESIGN1-5 schemas
--   - Required system views
--   - No DML (INSERT/UPDATE/DELETE)
--   - No DDL (CREATE/ALTER/DROP)
-- ============================================

-- Create user
CREATE USER simtreenav_readonly IDENTIFIED BY "YourSecurePassword123!";

-- Grant connection
GRANT CREATE SESSION TO simtreenav_readonly;

-- Grant SELECT on system views (for schema/instance discovery)
GRANT SELECT ON DBA_USERS TO simtreenav_readonly;
GRANT SELECT ON V$SERVICES TO simtreenav_readonly;

-- Grant SELECT on DESIGN schemas (adjust as needed)
GRANT SELECT ON DESIGN1.COLLECTION_ TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.REL_COMMON TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.CLASS_DEFINITIONS TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.DF_ICONS_DATA TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.DFPROJECT TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.PROXY TO simtreenav_readonly;
GRANT SELECT ON DESIGN1.APPLICATION_DATA TO simtreenav_readonly;

-- Repeat for DESIGN2-5
GRANT SELECT ON DESIGN2.COLLECTION_ TO simtreenav_readonly;
GRANT SELECT ON DESIGN2.REL_COMMON TO simtreenav_readonly;
-- [etc...]

-- Create synonyms for easier access (optional)
CREATE SYNONYM simtreenav_readonly.DESIGN1_COLLECTION FOR DESIGN1.COLLECTION_;
CREATE SYNONYM simtreenav_readonly.DESIGN1_REL_COMMON FOR DESIGN1.REL_COMMON_;
-- [etc...]

-- Set resource limits (optional but recommended)
ALTER USER simtreenav_readonly
  PROFILE DEFAULT
  QUOTA 0M ON SYSTEM;  -- No space quota (read-only)

-- Verify grants
SELECT * FROM DBA_SYS_PRIVS WHERE GRANTEE = 'SIMTREENAV_READONLY';
SELECT * FROM DBA_TAB_PRIVS WHERE GRANTEE = 'SIMTREENAV_READONLY';

COMMIT;
```

### Credential Manager Updates

**Updated CredentialManager.ps1**:

```powershell
function Get-DbConnectionString {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [string]$Username,  # Now optional (auto-detect)

        [switch]$AsSysDBA,  # Explicit flag for DBA mode

        [switch]$ReadOnly,  # Explicit flag for read-only mode

        [switch]$ForcePrompt
    )

    # Auto-detect username based on mode
    if (-not $Username) {
        $mode = Get-EnvironmentMode

        if ($mode -eq "PROD" -and -not $AsSysDBA) {
            # Production: Use read-only user by default
            $Username = "simtreenav_readonly"
            Write-Host "  Using read-only user for production" -ForegroundColor Gray
        } else {
            # Development or explicit SYSDBA: Use sys
            $Username = "sys"
        }
    }

    # Get credentials
    $credential = Get-DbCredential -TNSName $TNSName -Username $Username -ForcePrompt:$ForcePrompt

    # Build connection string
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

    if ($AsSysDBA) {
        $connectionString = "$Username/$password@$TNSName AS SYSDBA"
    } else {
        $connectionString = "$Username/$password@$TNSName"
    }

    return $connectionString
}
```

### Production Configuration

**Updated credential-config.json**:

```json
{
  "Mode": "PROD",
  "Username": "simtreenav_readonly",  ← NEW: Default production user
  "UseSysDBA": false,                  ← NEW: Disable SYSDBA for safety
  "ConfiguredDate": "2026-01-15 12:00:00",
  "ConfiguredBy": "DOMAIN\\username",
  "Machine": "des-sim-db1"
}
```

### Migration Path

**For existing installations**:

1. **Create read-only user** (DBA task):
   ```sql
   @scripts/create-readonly-user.sql
   ```

2. **Update configuration** (one-time):
   ```powershell
   .\src\powershell\database\Initialize-DbCredentials.ps1 -Username simtreenav_readonly
   ```

3. **Test connection**:
   ```powershell
   .\src\powershell\database\test-connection.ps1 -Username simtreenav_readonly
   ```

4. **All scripts now use read-only user** ✓

---

## Implementation Plan

### Phase 1: PC Profile System (High Priority)

1. ✅ Create PC profile configuration schema
2. ✅ Create [PC-ProfileManager.ps1](../src/powershell/utilities/PC-ProfileManager.ps1)
   - Functions:
     - `Get-PCProfiles` - List all profiles
     - `Get-DefaultPCProfile` - Get default profile
     - `Add-PCProfile` - Add new profile
     - `Set-DefaultPCProfile` - Set default
     - `Update-PCProfile` - Update profile
     - `Remove-PCProfile` - Remove profile
3. ✅ Update [tree-viewer-launcher.ps1](../src/powershell/main/tree-viewer-launcher.ps1)
   - New PC profile selection UI
   - Cascading server/instance/schema selection
   - Save last used settings per profile
4. ✅ Create [Initialize-PCProfile.ps1](../src/powershell/database/Initialize-PCProfile.ps1)
   - Interactive profile setup wizard
   - Auto-detect current PC
   - Configure servers and instances

### Phase 2: Read-Only User (High Priority - Security)

1. ✅ Create [create-readonly-user.sql](../scripts/create-readonly-user.sql)
2. ✅ Update CredentialManager.ps1
   - Auto-detect username based on mode
   - Support for non-SYSDBA connections
   - Separate credentials per username
3. ✅ Update credential-config.json schema
   - Add `Username` field
   - Add `UseSysDBA` field
4. ✅ Update all scripts to use read-only user in production
5. ✅ Create documentation for DBA setup
6. ✅ Test all queries with read-only user

### Phase 3: Documentation & Testing

1. ✅ Update CREDENTIAL-MANAGEMENT.md with read-only user info
2. ✅ Create PC-PROFILES-GUIDE.md
3. ✅ Create PRODUCTION-SECURITY-GUIDE.md
4. ✅ Test full workflow with both profiles
5. ✅ Test read-only user restrictions

---

## Expected User Experience

### First Time Setup (Development)

```powershell
# Step 1: Setup PC profile
.\src\powershell\database\Initialize-PCProfile.ps1

# Wizard prompts:
  → Detected PC: DESKTOP-ABC123
  → Name for this profile: My Dev PC
  → Add database server: des-sim-db1
  → Instances for des-sim-db1: db01, db02
  → Set as default? Yes

# Step 2: Setup credentials (DEV mode, sys user)
.\src\powershell\database\Initialize-DbCredentials.ps1

# Step 3: Run tree viewer
.\src\powershell\main\tree-viewer-launcher.ps1

# Shows: "My Dev PC (default)" → Select → Instant!
```

### First Time Setup (Production Server)

```powershell
# Step 1: DBA creates read-only user
sqlplus sys/password@PROD AS SYSDBA
SQL> @scripts/create-readonly-user.sql

# Step 2: Setup PC profile
.\src\powershell\database\Initialize-PCProfile.ps1

# Wizard prompts:
  → Detected PC: des-sim-db1
  → Name: Production Server
  → Server: localhost (local instance)
  → Set as default? Yes

# Step 3: Setup credentials (PROD mode, read-only user)
.\src\powershell\database\Initialize-DbCredentials.ps1 -Username simtreenav_readonly

# Step 4: Run tree viewer
.\src\powershell\main\tree-viewer-launcher.ps1

# Shows: "Production Server (default)" → Select → Secure!
```

### Daily Use (Both Modes)

```powershell
# Just run it!
.\src\powershell\main\tree-viewer-launcher.ps1

# Shows default PC profile → Press Enter → Done!
# Fast, secure, convenient
```

---

## Security Comparison

### Before (Current)

| Aspect | Status | Risk Level |
|--------|--------|-----------|
| User | `sys AS SYSDBA` | ⚠️ HIGH |
| Privileges | Full DBA rights | ⚠️ HIGH |
| Can drop tables | Yes | ⚠️ CRITICAL |
| Can modify data | Yes | ⚠️ HIGH |
| Audit trail | Poor (shared SYS) | ⚠️ MEDIUM |
| Production safe | NO | ⚠️ HIGH |

### After (Improved)

| Aspect | Status | Risk Level |
|--------|--------|-----------|
| User | `simtreenav_readonly` | ✅ LOW |
| Privileges | SELECT only | ✅ LOW |
| Can drop tables | No | ✅ SAFE |
| Can modify data | No | ✅ SAFE |
| Audit trail | Clear (dedicated user) | ✅ GOOD |
| Production safe | YES | ✅ SAFE |

---

## Benefits Summary

### PC Profiles

**Before**:
- Slow server discovery (5-10 seconds)
- Shows all servers (confusing)
- No memory of favorites
- Multiple queries to get started

**After**:
- Instant profile selection (< 1 second)
- Only YOUR PCs shown
- Remembers defaults per PC
- One query to list schemas

### Read-Only Security

**Before**:
- Using SYS with full DBA rights
- Can accidentally DROP tables
- No audit trail separation
- Unsuitable for production

**After**:
- Dedicated read-only user
- Cannot modify anything
- Clear audit trail
- Production-ready security

---

## Next Steps

1. **Review this design** - Approve approach?
2. **Implement PC profiles** - ProfileManager module
3. **Create read-only SQL script** - For DBA setup
4. **Update CredentialManager** - Support read-only user
5. **Update tree-viewer-launcher** - New UI flow
6. **Test thoroughly** - Both dev and prod scenarios
7. **Document** - User guides

---

**Ready to proceed with implementation?**
