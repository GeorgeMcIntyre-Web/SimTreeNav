# SimTreeNav Architecture

> **Document Version:** 1.0  
> **Last Updated:** 2026-01-16

## Overview

SimTreeNav is a PowerShell-based Oracle database tree navigation system designed for Siemens Process Simulation projects. It provides secure credential management, hierarchical data extraction, and interactive HTML visualization.

## System Context

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           User Workstation                               │
│  ┌─────────────┐    ┌─────────────────┐    ┌─────────────────────────┐ │
│  │ PowerShell  │───▶│   SimTreeNav    │───▶│   HTML Tree Viewer     │ │
│  │   Console   │    │   Application   │    │   (Browser)            │ │
│  └─────────────┘    └────────┬────────┘    └─────────────────────────┘ │
│                              │                                          │
│  ┌───────────────────────────┴──────────────────────────────────────┐  │
│  │                    Local Storage                                   │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │  │
│  │  │  Encrypted   │  │  PC Profile  │  │  Generated Output    │   │  │
│  │  │  Credentials │  │  Config      │  │  (HTML, icons)       │   │  │
│  │  └──────────────┘  └──────────────┘  └──────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ Oracle TNS
                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     Oracle Database Server                               │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │  DESIGN1-5 Schemas                                               │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────────┐  │   │
│  │  │COLLECTION│ │REL_COMMON│ │DF_ICONS  │ │CLASS_DEFINITIONS │  │   │
│  │  │    _     │ │          │ │  _DATA   │ │                  │  │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### Core Components

```
src/powershell/
├── main/                      # Application Entry Points
│   ├── tree-viewer-launcher.ps1    # Interactive launcher (v2)
│   ├── generate-tree-html.ps1      # Tree generation engine
│   ├── extract-icons-hex.ps1       # Icon extraction
│   └── Extract-Operations.ps1      # Operation node handling
│
├── database/                  # Database Layer
│   ├── connect-db.ps1              # Connection management
│   ├── Initialize-DbCredentials.ps1 # Credential initialization
│   ├── Initialize-PCProfile.ps1    # Profile initialization
│   ├── test-connection.ps1         # Connection testing
│   └── install-oracle-client.ps1   # Oracle client setup
│
└── utilities/                 # Shared Utilities
    ├── CredentialManager.ps1       # Secure credential handling
    ├── PCProfileManager.ps1        # PC profile management
    ├── icon-mapping.ps1            # Icon resolution logic
    ├── common-queries.ps1          # Reusable SQL queries
    └── query-db.ps1                # Query execution
```

### Component Responsibilities

| Component | Responsibility | Dependencies |
|-----------|----------------|--------------|
| `tree-viewer-launcher.ps1` | User interaction, workflow orchestration | All utilities |
| `generate-tree-html.ps1` | Data extraction, HTML generation | database/, utilities/ |
| `CredentialManager.ps1` | Secure credential storage/retrieval | Windows DPAPI/CredMan |
| `PCProfileManager.ps1` | PC configuration management | None (file-based) |
| `connect-db.ps1` | Oracle connection handling | Oracle Instant Client |

## Data Flow

### Tree Generation Workflow

```
┌──────────────┐
│    User      │
│   Launch     │
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│                   tree-viewer-launcher.ps1                    │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │ Load PC Profile │───▶│ Load Servers/Instances from    │ │
│  │ (auto-detect)   │    │ pc-profiles.json               │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
│           │                                                   │
│           ▼                                                   │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │         User Selects Server → Schema → Project          │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────┬───────────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────────┐
│                   CredentialManager.ps1                       │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │  Check Cache    │───▶│ DEV: .credentials/*.xml (DPAPI) │ │
│  │  (DEV or PROD)  │    │ PROD: Windows Credential Mgr    │ │
│  └─────────────────┘    └─────────────────────────────────┘ │
│           │                                                   │
│      Found?                                                   │
│     ┌──┴──┐                                                  │
│    Yes    No ──▶ Prompt User ──▶ Encrypt ──▶ Store          │
│     │                                                         │
│     ▼                                                         │
│  Return Connection String                                     │
└──────────────┬───────────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────────┐
│                   generate-tree-html.ps1                      │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Phase 1: Extract Icons from DF_ICONS_DATA              │ │
│  │   - Query BLOB as RAWTOHEX                              │ │
│  │   - Convert to Base64 data URIs                         │ │
│  │   - Load fallback icons from custom directories         │ │
│  └─────────────────────────────────────────────────────────┘ │
│                          │                                    │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Phase 2: Extract Tree Structure                         │ │
│  │   - Root project (Level 0)                              │ │
│  │   - Direct children with custom ordering (Level 1)      │ │
│  │   - Hierarchical CONNECT BY query (Level 2+)            │ │
│  │   - Specialized nodes (RobcadStudy, ToolPrototype)      │ │
│  └─────────────────────────────────────────────────────────┘ │
│                          │                                    │
│                          ▼                                    │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Phase 3: Generate HTML                                  │ │
│  │   - Embed icons as Base64                               │ │
│  │   - Embed tree data as JavaScript object                │ │
│  │   - Include interactive controls                        │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────┬───────────────────────────────────────────────┘
               │
               ▼
┌──────────────────────────────────────────────────────────────┐
│                    Output: HTML Tree Viewer                   │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ - Embedded icons (no external dependencies)             │ │
│  │ - Expand/collapse tree navigation                       │ │
│  │ - Real-time search functionality                        │ │
│  │ - Checkout status indicators                            │ │
│  │ - Export capabilities                                   │ │
│  └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

## Database Schema

### Core Tables

```
┌─────────────────────────────────────────────────────────────────────┐
│                         COLLECTION_                                  │
├─────────────────────────────────────────────────────────────────────┤
│ OBJECT_ID (PK)  │ Unique identifier for each node                   │
│ CAPTION_S_      │ Display name                                       │
│ CLASS_ID        │ Reference to CLASS_DEFINITIONS                    │
│ STATUS          │ Node status (active, deleted, etc.)               │
│ EXTERNAL_ID     │ External system identifier                        │
│ SEQ_NUMBER      │ Ordering within parent                            │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ CLASS_ID
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       CLASS_DEFINITIONS                              │
├─────────────────────────────────────────────────────────────────────┤
│ CLASS_ID (PK)   │ Unique class identifier                           │
│ CLASS_NAME      │ Type name (e.g., "RobcadStudyFolder")             │
│ TYPE_ID         │ Reference to icon type                            │
│ PARENT_CLASS_ID │ Inheritance hierarchy                             │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    │ TYPE_ID
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         DF_ICONS_DATA                                │
├─────────────────────────────────────────────────────────────────────┤
│ TYPE_ID (PK)    │ Icon type identifier                              │
│ CLASS_IMAGE     │ BLOB containing BMP icon data                     │
│ CLASS_NAME      │ Icon description                                  │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                          REL_COMMON                                  │
├─────────────────────────────────────────────────────────────────────┤
│ OBJECT_ID (PK)  │ Child node identifier                             │
│ FORWARD_OBJECT_ID│ Parent node identifier                           │
│ REL_TYPE        │ Relationship type                                 │
└─────────────────────────────────────────────────────────────────────┘
```

### Specialized Tables

| Table | Purpose | Usage |
|-------|---------|-------|
| `ROBCADSTUDY_` | RobCAD study-specific data | Extended attributes for study nodes |
| `TOOLPROTOTYPE_*` | Tool prototype definitions | Tool templates and configurations |
| `TOOLINSTANCE_*` | Tool instance data | Instantiated tools in projects |
| `SIMUSER_ACTIVITY` | User checkout tracking | Shows who has objects checked out |

## Security Architecture

### Credential Protection Layers

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Layer 1: Encryption                             │
│  ┌──────────────────────────────┬──────────────────────────────────┐│
│  │ DEV Mode                      │ PROD Mode                        ││
│  ├──────────────────────────────┼──────────────────────────────────┤│
│  │ Windows DPAPI                 │ Windows Credential Manager       ││
│  │ User-specific key             │ System-integrated storage        ││
│  │ .credentials/*.xml            │ cmdkey stored credentials        ││
│  └──────────────────────────────┴──────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Layer 2: Access Control                           │
│  - Credentials tied to Windows user account                         │
│  - Files not portable between users                                  │
│  - Git ignores all credential files                                  │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                   Layer 3: Transmission Security                     │
│  - Oracle TNS encryption (configurable)                              │
│  - No passwords in command line                                      │
│  - No passwords in logs                                              │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Layer 4: Database Security                        │
│  - Read-only database user (recommended)                             │
│  - Schema-level access control                                       │
│  - No write operations performed                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Git Security

Files automatically excluded from version control:

```gitignore
# Credentials
config/.credentials/
config/credential-config.json
config/pc-profiles.json

# Output (may contain sensitive project data)
data/output/*.html
data/icons/*.bmp
*.html
```

## Extension Points

### Adding New Node Types

1. **Identify the Oracle table** storing the new node type
2. **Extend SQL query** in `generate-tree-html.ps1`
3. **Add icon mapping** in `icon-mapping.ps1`
4. **Update fallback logic** for missing icons

### Adding New Icon Sources

1. **Configure path** in launcher menu
2. **Update extraction logic** in icon loading
3. **Define priority order** for resolution
4. **Document mapping** in icon-mapping.ps1

### Adding New Credential Modes

1. **Implement storage backend** in `CredentialManager.ps1`
2. **Add mode detection** logic
3. **Update initialization** in `Initialize-DbCredentials.ps1`
4. **Document security properties**

## Performance Considerations

### Query Optimization

| Query Type | Optimization | Performance |
|------------|--------------|-------------|
| Hierarchical tree | `CONNECT BY NOCYCLE` | Prevents infinite loops |
| Icon extraction | `RAWTOHEX` + batch | Single query for all icons |
| Large trees | Level-based pagination | Progressive loading option |

### HTML Generation

- Icons embedded as Base64 (no file I/O at runtime)
- Tree data as JavaScript object (instant rendering)
- Lazy expansion for large trees (client-side optimization)

## Deployment Architecture

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed deployment instructions.

```
Production Deployment
├── Workstation Installation
│   ├── Oracle Instant Client 12c+
│   ├── PowerShell 5.1+
│   └── SimTreeNav scripts
│
├── Configuration
│   ├── tnsnames.ora (network paths)
│   ├── pc-profiles.json (per-user)
│   └── credential-config.json (mode selection)
│
└── Database Access
    ├── Read-only user per schema
    └── TNS encryption (recommended)
```

## Related Documentation

- [Features](FEATURES.md) - Complete feature list
- [Deployment](DEPLOYMENT.md) - Installation and configuration
- [Roadmap](ROADMAP.md) - Future development plans
- [Security](../SECURITY.md) - Security policy and practices
- [System Architecture (detailed)](SYSTEM-ARCHITECTURE.md) - Extended architecture reference
