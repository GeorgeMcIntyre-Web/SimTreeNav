# SimTreeNav Features

> **Document Version:** 1.0  
> **Last Updated:** 2026-01-16

## Feature Overview

SimTreeNav provides comprehensive tree navigation capabilities for Siemens Process Simulation databases. This document details all features and their capabilities.

## Core Features

### 🌳 Interactive Tree Viewer

**Description:** Full hierarchical visualization of Process Simulation project structures with expand/collapse functionality.

**Capabilities:**
- Complete tree extraction from Oracle database
- Unlimited nesting levels supported
- Expand/collapse individual nodes or entire branches
- Preserves node ordering matching Siemens application
- Displays node metadata (type, status, external ID)

**Usage:**
```powershell
.\src\powershell\main\tree-viewer-launcher.ps1
```

**Performance:**
- Tested with 20,000+ nodes
- Tree generation: 10-30 seconds
- Browser rendering: Instant (client-side JavaScript)

---

### 🎨 Icon Extraction & Display

**Description:** Automatic extraction and display of 95+ custom icons from database BLOB fields.

**Capabilities:**
- Extracts icons from `DF_ICONS_DATA` table
- Handles BMP format icons of various sizes
- Fallback icon resolution for missing types
- Custom icon directory support
- Icons embedded as Base64 (no external dependencies)

**Icon Sources (Priority Order):**
1. Database icons (`DF_ICONS_DATA.CLASS_IMAGE`)
2. Custom directories (user-specified paths)
3. Class-specific fallback BMPs
4. Generic placeholder icons

**Technical Details:**
- Uses `RAWTOHEX` encoding to avoid SQL*Plus truncation
- Base64 encoding for HTML embedding
- Automatic BMP-to-data-URI conversion

---

### 🔍 Real-Time Search

**Description:** Instant search across all tree nodes with highlighting.

**Capabilities:**
- Search by node caption
- Search by external ID
- Case-insensitive matching
- Partial matching support
- Auto-expands matching branches
- Highlights search matches

**Usage:** Type in the search box at the top of the HTML viewer.

---

### 🔐 Secure Credential Management

**Description:** Enterprise-grade credential storage with zero password prompts after initial setup.

**Modes:**

| Mode | Storage | Encryption | Use Case |
|------|---------|------------|----------|
| DEV | Encrypted XML files | Windows DPAPI | Development workstations |
| PROD | Windows Credential Manager | System-integrated | Shared servers, production |

**Capabilities:**
- One-time credential entry
- Automatic credential caching
- Per-server credential storage
- Credential refresh on demand
- Secure credential removal

**Configuration:**
```powershell
# Initialize credentials for a server
.\src\powershell\database\Initialize-DbCredentials.ps1 -ServerName "des-sim-db1"
```

---

### 👤 PC Profile Management

**Description:** Multi-workstation configuration support with server and instance mappings.

**Capabilities:**
- Multiple PC profiles per workstation
- Server/instance mapping per profile
- Auto-detection by hostname
- Last-used selection memory
- Profile switching on-the-fly

**Profile Structure:**
```json
{
  "name": "my-workstation",
  "hostname": "D-DBN-VC006",
  "servers": [
    {
      "name": "des-sim-db1",
      "instances": [
        { "name": "db01", "tnsName": "DB01" },
        { "name": "db02", "tnsName": "DB02" }
      ]
    }
  ]
}
```

---

### 📊 Multi-Schema Support

**Description:** Works seamlessly with DESIGN1-5 schemas and custom schemas.

**Capabilities:**
- Dynamic schema discovery
- Schema selection at runtime
- Multiple projects per schema
- Cross-schema project comparison (planned)

**Supported Schemas:**
- DESIGN1, DESIGN2, DESIGN3, DESIGN4, DESIGN5
- Custom schemas with standard table structure

---

### 🔧 Custom Node Ordering

**Description:** Matches Siemens Navigation Tree application node ordering exactly.

**Approach:**
After extensive database investigation, SimTreeNav implements custom ordering logic that replicates the exact order shown in the Siemens application.

**Technical Details:**
- Level 1 children use explicit ordering map
- Level 2+ children use `SEQ_NUMBER` ordering
- Fallback to alphabetical for unmapped nodes

---

### 📄 Specialized Node Types

**Description:** Full support for specialized node types beyond standard `COLLECTION_` entries.

**Supported Types:**

| Node Type | Source Table | Description |
|-----------|--------------|-------------|
| RobcadStudy | `ROBCADSTUDY_` | Study-specific attributes |
| ToolPrototype | `TOOLPROTOTYPE_*` | Tool template definitions |
| ToolInstance | `TOOLINSTANCE_*` | Instantiated tool data |
| StudyFolder | `COLLECTION_` | Container for studies |
| ResourceLibrary | `COLLECTION_` | Resource collections |

---

### 👥 User Activity Tracking

**Description:** Shows which users have objects checked out.

**Capabilities:**
- Queries `SIMUSER_ACTIVITY` table
- Displays checkout user on node
- Visual indicators for checked-out items
- Filter by checkout status (planned)

---

## Installation Features

### 🚀 Oracle Client Auto-Installation

**Description:** Automated Oracle Instant Client setup for new workstations.

**Script:** `.\src\powershell\database\install-oracle-client.ps1`

**Capabilities:**
- Downloads Oracle Instant Client 12c
- Configures PATH environment
- Sets up TNS_ADMIN
- Verifies installation

---

### ⚙️ Connection Configuration

**Description:** Guided database connection setup.

**Scripts:**
- `Setup-OracleConnection.ps1` - Environment configuration
- `setup-env-vars.ps1` - Environment variable setup
- `test-connection.ps1` - Connection verification

---

## Output Features

### 📊 HTML Tree Export

**Description:** Self-contained HTML file with full tree visualization.

**Features:**
- No external dependencies
- Embedded icons
- Embedded CSS/JavaScript
- Works offline
- Shareable via email/file share

**Output Location:** `data/output/navigation-tree.html`

---

### 📝 SQL Query Library

**Description:** 130+ SQL queries organized by category.

**Categories:**
| Category | Count | Description |
|----------|-------|-------------|
| icon-extraction/ | 18 | Icon extraction research |
| tree-navigation/ | 9 | Tree traversal queries |
| analysis/ | 55 | Database analysis |
| investigation/ | 50 | Research and exploration |

---

## Coming Soon

Features planned for future releases:

- [ ] JSON/XML export formats
- [ ] Node diff/comparison between projects
- [ ] Real-time database sync
- [ ] Cross-platform support (PowerShell Core)
- [ ] Web-based interface
- [ ] Filter by node type
- [ ] Bookmark favorite projects

See [ROADMAP.md](ROADMAP.md) for the complete development roadmap.

---

## Feature Comparison

| Feature | SimTreeNav | Siemens Navigation Tree |
|---------|------------|------------------------|
| Tree visualization | ✅ | ✅ |
| Icon display | ✅ | ✅ |
| Search | ✅ | ✅ |
| Offline access | ✅ | ❌ |
| Custom exports | ✅ | Limited |
| Multi-server | ✅ | Manual |
| Read-only | ✅ (safe) | Read/Write |
| Custom ordering | ✅ | ✅ |

---

## Related Documentation

- [Architecture](ARCHITECTURE.md) - System architecture
- [Deployment](DEPLOYMENT.md) - Installation guide
- [Roadmap](ROADMAP.md) - Future plans
- [Quick Start Guide](QUICK-START-GUIDE.md) - Getting started
