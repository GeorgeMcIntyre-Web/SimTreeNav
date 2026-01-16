# SimTreeNav Agent Prompt

> **Use this document to onboard AI agents to the codebase. Copy-paste as context for implementation tasks.**

---

## ROLE

You are a software engineer working on **SimTreeNav**, a read-only analytics and version-control layer for Siemens Process Simulate databases. The tool extracts hierarchical tree structures from Oracle databases and will evolve into a change-tracking system with LLM-powered insights.

---

## CONTEXT

### What This Project Does

1. **Extracts** hierarchical tree data from Process Simulate Oracle DB (eMServer)
2. **Visualizes** tree structure matching the Siemens application UI
3. **Tracks** (future) changes over time: renames, moves, transforms, adds/removes
4. **Provides** (future) LLM-powered summaries and natural language Q&A

### Technology Stack

| Layer | Technology |
|-------|------------|
| Orchestration | PowerShell 5.1+ |
| Database | Oracle 12c (eMServer) |
| Queries | SQL with CONNECT BY NOCYCLE |
| Output | Static HTML with embedded JavaScript |
| Credentials | DPAPI encryption / Windows Credential Manager |
| Future UI | React/Vue SPA |
| Future Intelligence | LLM (DeepSeek or similar) |

### Repository Structure

```
/workspace/
├── src/powershell/
│   ├── main/              # Core scripts (tree generation, icon extraction)
│   ├── database/          # DB connection, credentials
│   └── utilities/         # Helper modules
├── queries/               # SQL scripts organized by function
├── docs/                  # Documentation
├── config/                # Configuration files (gitignored)
└── data/                  # Generated output (gitignored)
```

### Key Files

| File | Purpose |
|------|---------|
| `src/powershell/main/generate-tree-html.ps1` | Main tree extraction logic |
| `src/powershell/main/generate-full-tree-html.ps1` | Full HTML generation with icons |
| `src/powershell/main/tree-viewer-launcher.ps1` | Interactive launcher UI |
| `src/powershell/utilities/CredentialManager.ps1` | Secure credential handling |
| `src/powershell/utilities/PCProfileManager.ps1` | Multi-PC profile management |

---

## DATABASE SCHEMA

### Primary Tables

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `COLLECTION_` | Main node storage | OBJECT_ID, CAPTION_S_, CLASS_ID |
| `REL_COMMON` | Parent-child links | OBJECT_ID, FORWARD_OBJECT_ID |
| `CLASS_DEFINITIONS` | Type metadata | TYPE_ID, NAME, NICE_NAME |
| `DF_ICONS_DATA` | Icon BLOBs | TYPE_ID, CLASS_IMAGE |
| `TOOLPROTOTYPE_` | Tool definitions | OBJECT_ID, NAME_S_, COLLECTIONS_VR_ |
| `TOOLINSTANCEASPECT_` | Tool instances | OBJECT_ID, ATTACHEDTO_SR_ |
| `ROBCADSTUDY_` | Study data | OBJECT_ID, NAME_S_ |

### Test Environment

```
Server: des-sim-db1
Instance: db01
Schema: DESIGN12
Project: FORD_DEARBORN (ID: 18140190)
```

### Common Query Patterns

**Hierarchical tree traversal:**
```sql
SELECT LEVEL, c.OBJECT_ID, c.CAPTION_S_
FROM SCHEMA.COLLECTION_ c
JOIN SCHEMA.REL_COMMON r ON c.OBJECT_ID = r.OBJECT_ID
START WITH r.FORWARD_OBJECT_ID = @ProjectId
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
```

**Icon extraction:**
```sql
SELECT TYPE_ID, RAWTOHEX(DBMS_LOB.SUBSTR(CLASS_IMAGE, DBMS_LOB.GETLENGTH(CLASS_IMAGE), 1))
FROM SCHEMA.DF_ICONS_DATA WHERE CLASS_IMAGE IS NOT NULL
```

---

## DOMAIN MODEL

### Five Interconnected Hierarchies

1. **Resource Tree** - Compound resources, tool prototypes → tool instances
2. **Object Tree Twins** - Entities appearing in both resource and object views
3. **Operation Tree** - 3D transforms + metadata (weld ops, compound ops)
4. **MFG Library** - Manufacturing/joining definitions
5. **Panel Data** - Joining-type-specific metadata (spot weld 2T/3T)

### Key Relationships

```
Project (COLLECTION_)
  └── ResourceLibrary (COLLECTION_)
        └── CompoundResource (COLLECTION_)
              └── ToolPrototype (TOOLPROTOTYPE_)
                    └── ToolInstance (TOOLINSTANCEASPECT_)
```

---

## CURRENT TASKS

### Phase 2: Enhanced Node Coverage

| Task | Status | Table |
|------|--------|-------|
| COLLECTION_ nodes | Done | COLLECTION_ |
| RobcadStudy nodes | Done | ROBCADSTUDY_ |
| ToolPrototype nodes | Done | TOOLPROTOTYPE_ |
| ToolInstanceAspect nodes | Done | TOOLINSTANCEASPECT_ |
| Operation nodes | TODO | Various operation tables |
| MFG/Joining nodes | TODO | MFG-related tables |
| Panel data nodes | TODO | Panel-related tables |

### Phase 3: Snapshot Infrastructure

| Task | Status |
|------|--------|
| Design snapshot schema | TODO |
| Implement polling mechanism | TODO |
| Build diff computation engine | TODO |
| Create history storage | TODO |

---

## CONSTRAINTS

### Critical Rules

1. **NON-INTRUSIVE**: Never slow down or lock the production database
2. **READ-ONLY**: No writes to source database
3. **NO CREDENTIALS IN CODE**: Use CredentialManager.ps1
4. **WINDOWS COMPATIBLE**: PowerShell 5.1+, Oracle Instant Client 12c

### Performance Targets

| Operation | Target |
|-----------|--------|
| Full tree extraction | <30 seconds |
| Icon extraction | <10 seconds |
| Snapshot duration | <60 seconds |

---

## HOW TO TEST

```powershell
# 1. Launch interactive viewer
.\src\powershell\main\tree-viewer-launcher.ps1

# 2. Select: des-sim-db1 → db01 → DESIGN12

# 3. Optional: Set custom icon directory
# C:\Program Files\Tecnomatix_2301.0\eMPower\InitData;C:\tmp\PPRB1_Customization

# 4. Load tree for FORD_DEARBORN (18140190)

# 5. Verify in browser:
#    - All nodes appear
#    - Icons load correctly
#    - No console errors
```

---

## ACCEPTANCE CRITERIA TEMPLATE

```gherkin
Feature: [Feature Name]

  Scenario: [Scenario Description]
    Given [precondition]
    When [action]
    Then [expected result]
    And [additional verification]
    And performance: [metric] < [threshold]
```

---

## COMMIT MESSAGE FORMAT

```
feat|fix|docs|refactor: Short description

Detailed explanation of changes

Changes:
- Bullet point 1
- Bullet point 2

Testing:
- How it was tested

Files Modified:
- file1.ps1
- file2.ps1
```

---

## FUTURE VISION

### Change Tracking System

```
Every ~5 minutes:
  1. Snapshot current state
  2. Compare to last snapshot
  3. Compute meaningful diff
  4. Store in history
  5. Generate logical deductions:
     - "Station X reorganized"
     - "Operations retaught"
     - "Tool set duplicated"
```

### LLM Features

| Feature | Description |
|---------|-------------|
| Auto release notes | Summarize last hour/day/week of changes |
| Natural language Q&A | "What changed in Station X yesterday?" |
| Work session clustering | Group related changes by user/time |
| Pattern recognition | Detect copy/paste, reteach, reorganize |

---

## QUICK REFERENCE

### Database Connection

```powershell
# Import credential manager
. .\src\powershell\utilities\CredentialManager.ps1

# Get connection string (auto-prompts if needed)
$connStr = Get-DbConnectionString -TNSName "DB01" -Schema "DESIGN12"
```

### Execute SQL

```powershell
# Import query utility
. .\src\powershell\utilities\query-db.ps1

# Run query
$results = Invoke-SqlQuery -ConnectionString $connStr -Query $sql
```

### Add New Node Type

1. Query table structure
2. Identify parent relationship column
3. Add extraction SQL to `generate-tree-html.ps1`
4. Add icon handling if needed
5. Test with FORD_DEARBORN project
6. Commit with comprehensive message

---

**Document Version**: 1.0  
**For**: AI Agent Onboarding  
**Project**: SimTreeNav
