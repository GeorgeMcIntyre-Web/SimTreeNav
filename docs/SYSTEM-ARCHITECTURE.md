# SimTreeNav System Architecture

## Overview

SimTreeNav is a PowerShell-based Oracle database tree navigation system for Siemens Process Simulation projects. It combines secure credential management, PC profile configuration, and advanced icon rendering to create interactive HTML tree visualizations.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Interface                           │
├─────────────────────────────────────────────────────────────────┤
│  tree-viewer-launcher.ps1 (v2)                                  │
│  - PC Profile Selection                                          │
│  - Server/Instance Selection                                     │
│  - Schema Selection                                              │
│  - Custom Icon Directory Configuration                           │
│  - Tree Generation Orchestration                                 │
└────────────┬────────────────────────────────────────────────────┘
             │
             ├──────────────┬──────────────┬────────────────┐
             │              │              │                │
             ▼              ▼              ▼                ▼
    ┌────────────┐  ┌─────────────┐  ┌──────────┐  ┌─────────────┐
    │  PC Profile│  │ Credential  │  │  Oracle  │  │Icon/Tree    │
    │  Manager   │  │  Manager    │  │  Client  │  │ Generator   │
    └────────────┘  └─────────────┘  └──────────┘  └─────────────┘
          │               │                │              │
          │               │                │              │
          ▼               ▼                ▼              ▼
    ┌──────────────────────────────────────────────────────────┐
    │                  Persistence Layer                        │
    ├──────────────────────────────────────────────────────────┤
    │ - pc-profiles.json (gitignored)                           │
    │ - credential-config.json (gitignored)                     │
    │ - .credentials/*.xml (DPAPI encrypted, gitignored)        │
    │ - Windows Credential Manager (PROD mode)                  │
    │ - Oracle tnsnames.ora                                     │
    └──────────────────────────────────────────────────────────┘
                              │
                              │
                              ▼
                    ┌─────────────────────┐
                    │  Oracle Database    │
                    ├─────────────────────┤
                    │ - COLLECTION_       │
                    │ - REL_COMMON        │
                    │ - CLASS_DEFINITIONS │
                    │ - DF_ICONS_DATA     │
                    │ - ROBCADSTUDY_      │
                    │ - ToolPrototype_*   │
                    │ - ToolInstance_*    │
                    └─────────────────────┘
```

## Core Components

### 1. PC Profile Manager (`PCProfileManager.ps1`)

**Purpose:** Manage multiple PC configurations with server/instance mappings

**Key Functions:**
- `Get-PCProfiles` - Retrieve all profiles
- `Get-CurrentPCProfile` - Get active profile
- `Set-CurrentPCProfile` - Switch profiles
- `Add-PCProfile` - Create new profile
- `Update-PCProfileLastUsed` - Track usage

**Data Model:**
```json
{
  "currentProfile": "my-pc",
  "profiles": [
    {
      "name": "my-pc",
      "hostname": "D-DBN-VC006",
      "description": "My workstation",
      "isDefault": true,
      "servers": [
        {
          "name": "des-sim-db1",
          "instances": [
            {
              "name": "db01",
              "tnsName": "DB01",
              "service": "db01"
            }
          ],
          "defaultInstance": "db01"
        }
      ],
      "lastUsed": {
        "server": "des-sim-db1",
        "instance": "db01",
        "schema": "DESIGN12",
        "projectId": "18140190",
        "projectName": "FORD_DEARBORN",
        "timestamp": "2026-01-15 09:47:01"
      }
    }
  ]
}
```

### 2. Credential Manager (`CredentialManager.ps1`)

**Purpose:** Secure credential storage and retrieval with zero password prompts

**Modes:**

#### DEV Mode (Default)
- **Storage:** Encrypted XML files using Windows DPAPI
- **Location:** `config/.credentials/`
- **Encryption:** Tied to Windows user account
- **Use Case:** Local development workstations
- **Security:** User-specific, not portable between accounts

#### PROD Mode
- **Storage:** Windows Credential Manager
- **Location:** System-wide credential store
- **Encryption:** Windows managed
- **Use Case:** Shared servers, production deployments
- **Security:** Auditable, integrated with Windows security

**Key Functions:**
- `Get-DbConnectionString` - Retrieve connection string with cached credentials
- `Save-DbCredentials` - Securely store credentials
- `Remove-DbCredentials` - Clean up stored credentials
- `Test-DbConnection` - Validate credentials and connectivity

**Flow:**
```
User Request
    ↓
Check Cache (DEV: .xml file | PROD: CredMan)
    ↓
Found? → Return credentials
    ↓
Not Found? → Prompt user → Encrypt → Store → Return
```

### 3. Tree Viewer Launcher (`tree-viewer-launcher.ps1` v2)

**Purpose:** Interactive workflow orchestration

**Menu Structure:**
```
1. Select Server        → Choose from PC Profile
2. Select Schema        → Query available schemas
3. Load Tree           → Generate + open HTML
4. Set Custom Icon Dir → Configure custom icons (after merge)
5. Exit                → Save state and exit
```

**Workflow:**
1. Load PC Profile (auto-detect or select)
2. Load servers from profile
3. Auto-retrieve credentials for selected server
4. Query schemas dynamically
5. Remember last selection
6. Generate tree with all configured options

### 4. Tree Generator (`generate-tree-html.ps1`)

**Purpose:** Extract data from Oracle and generate interactive HTML

**Process Flow:**
```
1. Connect to Oracle (using cached credentials)
    ↓
2. Extract Icons from DF_ICONS_DATA
    - Query BLOB data as RAWTOHEX
    - Convert to Base64 data URIs
    - Add fallback icons for missing TYPE_IDs
    - Support custom icon directories (after merge)
    ↓
3. Extract Tree Data
    - Level 0: Root project
    - Level 1: Direct children (custom order)
    - Level 2+: Hierarchical query with NOCYCLE
    - StudyFolder children (special handling)
    - RobcadStudy nodes (specialized table)
    - ToolPrototype/ToolInstance (after merge)
    ↓
4. Extract User Activity (checkout status)
    - Query SIMUSER_ACTIVITY
    - Map users to objects
    ↓
5. Generate HTML
    - Embed icons as Base64
    - Embed tree data as JavaScript
    - Embed user activity data
    - Add interactive controls
    ↓
6. Open in Browser
```

**SQL Tables Queried:**
- `COLLECTION_` - Main object storage
- `REL_COMMON` - Parent-child relationships
- `CLASS_DEFINITIONS` - Object type metadata
- `DF_ICONS_DATA` - Icon BLOBs
- `ROBCADSTUDY_` - Study-specific data
- `SIMUSER_ACTIVITY` - Checkout status
- `ToolPrototype_*` *(after merge)*
- `ToolInstance_*` *(after merge)*

### 5. Icon System (After Merge)

**Purpose:** Multi-source icon loading with intelligent fallbacks

**Icon Sources (Priority Order):**
1. **Database Icons** - `DF_ICONS_DATA.CLASS_IMAGE`
2. **Custom Directories** - User-specified paths (semicolon-separated):
   - `data/icons`
   - `C:\Program Files\Tecnomatix_2301.0\eMPower\InitData`
   - `C:\tmp\PPRB1_Customization`
3. **Class-Specific BMPs** - Hardcoded mappings
4. **Fallback Icons** - Generic placeholders

**Icon Resolution Logic:**
```
For each node:
  1. Try database icon (TYPE_ID)
  2. If DB icon missing or length=0:
     a. Try custom directories (by TYPE_ID)
     b. Try class-specific BMP (by CLASS_NAME)
     c. Use fallback icon
  3. Prefer class-specific over DB if more accurate
```

**Fallback Mappings:**
- TYPE_ID 72 (StudyFolder) → 18 (Collection parent)
- TYPE_ID 164 (RobcadResourceLibrary) → 162 (MaterialLibrary)
- TYPE_ID 177, 178, 183, 181, 108, 70 (Study types) → 69 (ShortcutFolder)

## Data Flow

### Complete Workflow (Post-Merge)

```
┌─────────────┐
│   User      │
│ Starts      │
│ Launcher    │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│ Load PC Profile         │
│ - Auto-detect hostname  │
│ - Get default profile   │
│ - Load server configs   │
└──────┬──────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Select Server/Instance   │
│ - Show servers from      │
│   profile                │
│ - Show instances per     │
│   server                 │
│ - Remember last used     │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Get Credentials          │
│ - Check cache (DEV/PROD) │
│ - Auto-retrieve if found │
│ - Prompt if not found    │
│ - Encrypt and store      │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Query Schemas            │
│ - Connect to database    │
│ - List available schemas │
│ - Remember last used     │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Optional: Set Custom     │
│ Icon Directory           │
│ - Prompt for path        │
│ - Validate directory     │
│ - Save to config         │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Generate Tree            │
│ - Extract icons (DB +    │
│   custom dirs)           │
│ - Extract tree data      │
│   (all node types)       │
│ - Extract user activity  │
│ - Build HTML             │
└──────┬───────────────────┘
       │
       ▼
┌──────────────────────────┐
│ Open HTML in Browser     │
│ - Interactive tree       │
│ - Full icon support      │
│ - Checkout status        │
│ - Search functionality   │
└──────────────────────────┘
```

## Security Architecture

### Defense in Depth

**Layer 1: Encryption**
- DEV: Windows DPAPI (user-specific)
- PROD: Windows Credential Manager (system-integrated)
- All passwords encrypted at rest

**Layer 2: Access Control**
- Credentials tied to Windows user account
- Files not portable between users
- Git ignores all sensitive files

**Layer 3: Secure Transmission**
- Oracle TNS encryption (configurable)
- No passwords in command line
- No passwords in logs

**Layer 4: Least Privilege**
- Read-only database user recommended
- Minimal permissions for tree viewing
- No write access required

### Threat Model

**Threats Mitigated:**
- ✅ Plaintext password storage
- ✅ Password prompts (user fatigue)
- ✅ Credential sharing via git
- ✅ Credential theft from files
- ✅ Command-line password exposure

**Residual Risks:**
- ⚠️ Windows user account compromise
- ⚠️ Physical machine access
- ⚠️ Memory dump attacks (runtime only)

## Configuration Files

### Git-Tracked (Public)
- `src/powershell/**/*.ps1` - All scripts
- `scripts/**/*.ps1` - Setup scripts
- `docs/**/*.md` - Documentation
- `.gitignore` - Exclusion rules

### Git-Ignored (Private)
- `config/pc-profiles.json` - PC configurations
- `config/credential-config.json` - Environment mode
- `config/.credentials/*.xml` - Encrypted passwords
- `*.html` - Generated trees
- `tree-data-*.txt` - Extracted data
- `icons/` - Extracted icon files

## Extensibility

### Adding New Node Types

1. **Identify Table:** Find Oracle table storing new node type
2. **Extend SQL:** Add query to `generate-tree-html.ps1`
3. **Add Icon Mapping:** Update icon fallback logic
4. **Test:** Verify nodes appear in tree

Example (ToolPrototype):
```sql
-- Add to generate-tree-html.ps1
SELECT
    '999|' ||  -- High level, JavaScript handles
    tp.PARENT_ID || '|' ||
    tp.OBJECT_ID || '|' ||
    NVL(tp.NAME, 'Unnamed') || '|' ||
    NVL(tp.NAME, 'Unnamed') || '|' ||
    NVL(tp.EXTERNAL_ID, '') || '|' ||
    '0|' ||  -- SEQ_NUMBER
    'class ToolPrototype' || '|' ||
    'ToolPrototype' || '|' ||
    TO_CHAR(tp.TYPE_ID)
FROM $Schema.TOOLPROTOTYPE_ tp
WHERE EXISTS (
    -- Only include if parent in tree
    SELECT 1 FROM $Schema.COLLECTION_ c
    START WITH c.OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR c.OBJECT_ID = parent_relation
    WHERE c.OBJECT_ID = tp.PARENT_ID
)
ORDER BY tp.NAME;
```

### Adding New Icon Sources

1. **Add Directory:** Configure in launcher menu
2. **Update Extraction:** Modify icon loading logic
3. **Set Priority:** Define resolution order
4. **Document:** Update user guide

### Adding New Credential Modes

1. **Implement Storage:** Add to CredentialManager.ps1
2. **Add Configuration:** Update credential-config.json schema
3. **Update UI:** Add to Initialize-DbCredentials.ps1
4. **Test:** Verify encryption and retrieval

## Performance Considerations

### Database Queries
- **Hierarchical Queries:** Use `CONNECT BY NOCYCLE` to prevent infinite loops
- **Indexing:** Ensure indexes on OBJECT_ID, FORWARD_OBJECT_ID, CLASS_ID
- **Result Limiting:** Consider adding WHERE clauses for large trees

### Icon Extraction
- **Batch Processing:** Extract all icons in single query
- **Base64 Encoding:** Done in PowerShell (fast)
- **Caching:** Icons embedded in HTML (no external files)

### HTML Generation
- **Template Literals:** Use PowerShell here-strings
- **JavaScript:** Client-side rendering (responsive)
- **Tree Expansion:** Lazy loading for large trees

## Troubleshooting Guide

### Common Issues

**Issue:** "TNS:could not resolve connect identifier"
- **Cause:** ORACLE_HOME or TNS_ADMIN not set
- **Fix:** Run `.\scripts\Setup-OracleConnection.ps1`

**Issue:** "No schemas found"
- **Cause:** Wrong TNS name or incorrect instance
- **Fix:** Verify PC Profile has correct TNS name for instance

**Issue:** "Credential not found"
- **Cause:** First-time use or cache cleared
- **Fix:** Enter password once, will be cached

**Issue:** "Icons not loading"
- **Cause:** DF_ICONS_DATA missing icons or custom dir not set
- **Fix:** Set custom icon directory with fallback BMPs

**Issue:** "Nodes missing from tree"
- **Cause:** Node type not in SQL query
- **Fix:** Extend SQL to include specialized tables

## Future Enhancements

### Planned (Short-term)
- [ ] Export tree to JSON/XML
- [ ] Filter tree by node type
- [ ] Bookmark favorite projects
- [ ] Multi-project comparison view

### Proposed (Long-term)
- [ ] Web-based UI (ASP.NET Core)
- [ ] Real-time collaboration
- [ ] Change tracking and history
- [ ] Integration with Siemens APIs
- [ ] Mobile responsive design

## References

- [Credential Management Guide](CREDENTIAL-MANAGEMENT.md)
- [Setup Guide](CREDENTIAL-SETUP-GUIDE.md)
- [Merge Strategy](../MERGE-STRATEGY.md)
- [Specialized Nodes Guide](../SPECIALIZED-NODES-GUIDE.md)
- [Git Publication Checklist](../GIT-PUBLICATION-CHECKLIST.md)

---

**Document Version:** 1.0
**Last Updated:** 2026-01-15
**Authors:** Claude Sonnet 4.5 (Anthropic)
