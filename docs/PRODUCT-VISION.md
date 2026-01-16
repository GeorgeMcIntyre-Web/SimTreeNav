# SimTreeNav Product Vision & Agent Specification

> **Document Purpose**: Comprehensive product definition, architecture, and milestone specification for AI agents working on this codebase.

---

## Executive Summary

**SimTreeNav** is a read-only, non-intrusive "version control + intelligence layer" for Process Simulate databases that continuously snapshots key hierarchical structures (resource tree, object twins, operation tree, MFG/joining library, panel metadata), computes meaningful diffs (renames, reparenting, transform deltas, adds/removes), and presents a modern UI timeline with filters/compare—optionally enhanced by an LLM that summarizes work sessions and answers natural-language questions about what changed and why.

---

## Product Definition

### What SimTreeNav Is

A tool that:
- **Reads** from Process Simulate / eMServer Oracle DB (and potentially Teamcenter-based setups)
- **Extracts** and visualizes the hierarchical "tree" structure users see in the product UI
- **Tracks** changes over time (rename events, hierarchy changes, transform/pose changes, adds/removes)
- **Provides** modern analytics, search, and reporting on top of existing simulation ecosystems

### What SimTreeNav Is NOT

- NOT hacking licensing or bypassing protections
- NOT distributing Siemens proprietary code
- NOT distributing customer data
- NOT interfering with licensing mechanisms
- NOT a replacement for Process Simulate—purely a complementary intelligence layer

### Value Proposition

| For Users | For Organizations |
|-----------|-------------------|
| Understand their simulation environment | Track work history and accountability |
| Navigate complex hierarchies efficiently | Identify patterns in workflow |
| Search across all node types | Audit changes for compliance |
| Compare states over time | Reduce time spent on "what changed?" |
| Natural language Q&A about changes | Modern UX over legacy tooling |

---

## Domain Model

### A) Resource Tree

```
┌─────────────────────────────────────────────────────────────┐
│                     RESOURCE TREE                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────┐                                     │
│  │  Compound Resources │  ← Collections of tool instances    │
│  │  (CompoundResource) │                                     │
│  └──────────┬──────────┘                                     │
│             │                                                │
│             ▼                                                │
│  ┌─────────────────────┐      ┌─────────────────────┐        │
│  │   Tool Prototypes   │──────│   Tool Instances    │        │
│  │  (ToolPrototype_)   │ 1:N  │ (ToolInstanceAspect)│        │
│  └─────────────────────┘      └─────────────────────┘        │
│                                                              │
│  Key Tables:                                                 │
│  - COLLECTION_ (main nodes)                                  │
│  - TOOLPROTOTYPE_ (tool definitions)                         │
│  - TOOLINSTANCEASPECT_ (tool instances)                      │
│  - REL_COMMON (parent-child relationships)                   │
└─────────────────────────────────────────────────────────────┘
```

**Database Tables:**
- `TOOLPROTOTYPE_` - Tool prototype definitions (37 columns)
- `TOOLINSTANCEASPECT_` - Tool instances attached via `ATTACHEDTO_SR_`
- `COLLECTION_` - Main object storage
- `REL_COMMON` - Relationship links (~8.6M rows)

### B) Object Tree "Twins"

```
┌─────────────────────────────────────────────────────────────┐
│                    OBJECT TREE TWINS                         │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────┐           ┌─────────────────┐           │
│  │  Resource View  │◄────────►│   Object View   │           │
│  │                 │   SYNC    │                 │           │
│  │  (visible in    │   BUTTON  │  (visible in    │           │
│  │   resource      │           │   object        │           │
│  │   browser)      │           │   browser)      │           │
│  └─────────────────┘           └─────────────────┘           │
│                                                              │
│  - Some entities appear in BOTH perspectives                 │
│  - Rename in one place → sync updates the twin               │
│  - Twin relationship tracked via object references           │
└─────────────────────────────────────────────────────────────┘
```

### C) Operation Data / Operation Tree

```
┌─────────────────────────────────────────────────────────────┐
│                   OPERATION TREE                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Operation = 3D transformation + metadata                    │
│                                                              │
│  ┌───────────────────┐                                       │
│  │  Weld Operations  │ ← Contains robot locations            │
│  │                   │   (fine-grain points/poses            │
│  │                   │    the robot moves through)           │
│  └─────────┬─────────┘                                       │
│            │                                                 │
│            ▼                                                 │
│  ┌───────────────────┐   ┌───────────────────┐               │
│  │ Compound          │   │  Single           │               │
│  │ Operations        │   │  Operations       │               │
│  └───────────────────┘   └───────────────────┘               │
│                                                              │
│  Tables: Various "operation" tables tied to MFG structures   │
│  - VEC_LOCATION1_ (800K+ rows)                               │
│  - VEC_ROTATION1_ (800K+ rows)                               │
│  - VEC_TOOLLOCATION_                                         │
│  - VEC_TOOLROTATION_                                         │
└─────────────────────────────────────────────────────────────┘
```

### D) MFG Library (Manufacturing/Joining Data)

```
┌─────────────────────────────────────────────────────────────┐
│                     MFG LIBRARY                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────┐                                 │
│  │   Joining Definitions   │                                 │
│  │   (MFG Feature Library) │                                 │
│  └───────────┬─────────────┘                                 │
│              │                                               │
│              ▼                                               │
│  ┌─────────────────────────┐                                 │
│  │  Operation Locations    │ ← Initially follow MFG          │
│  │  (location hierarchy)   │   location hierarchy            │
│  └─────────────────────────┘                                 │
│                                                              │
│  - Defines HOW things are manufactured                       │
│  - Joining type determines panel data structure              │
└─────────────────────────────────────────────────────────────┘
```

### E) Panel Data

```
┌─────────────────────────────────────────────────────────────┐
│                     PANEL DATA                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Tied to MFG depending on joining type:                      │
│                                                              │
│  Spot Welding Examples:                                      │
│  ┌─────────────────┐   ┌─────────────────┐                   │
│  │    Two-T        │   │   Three-T       │                   │
│  │  Panel Data     │   │  Panel Data     │                   │
│  └─────────────────┘   └─────────────────┘                   │
│                                                              │
│  - Different metadata stored per joining type                │
│  - Panel configuration affects robot path planning           │
└─────────────────────────────────────────────────────────────┘
```

---

## Technical Architecture

### Current Implementation Stack

```
┌─────────────────────────────────────────────────────────────┐
│                  CURRENT ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────┐             │
│  │           PowerShell Orchestration          │             │
│  │  - tree-viewer-launcher.ps1                 │             │
│  │  - generate-tree-html.ps1                   │             │
│  │  - CredentialManager.ps1                    │             │
│  │  - PCProfileManager.ps1                     │             │
│  └──────────────────────┬──────────────────────┘             │
│                         │                                    │
│                         ▼                                    │
│  ┌─────────────────────────────────────────────┐             │
│  │           SQL Scripts & Queries             │             │
│  │  - Tree navigation (CONNECT BY NOCYCLE)     │             │
│  │  - Icon extraction (RAWTOHEX from BLOBs)    │             │
│  │  - Relationship traversal (REL_COMMON)      │             │
│  └──────────────────────┬──────────────────────┘             │
│                         │                                    │
│                         ▼                                    │
│  ┌─────────────────────────────────────────────┐             │
│  │      Oracle 12c Database (eMServer)         │             │
│  │  - DESIGN1-5 schemas                        │             │
│  │  - 20M+ rows primary schemas                │             │
│  │  - REL_COMMON: 8.6M relationships           │             │
│  └──────────────────────┬──────────────────────┘             │
│                         │                                    │
│                         ▼                                    │
│  ┌─────────────────────────────────────────────┐             │
│  │         HTML Output (Static)                │             │
│  │  - Interactive tree visualization           │             │
│  │  - Embedded Base64 icons                    │             │
│  │  - Client-side JavaScript search            │             │
│  └─────────────────────────────────────────────┘             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Target Architecture (Future State)

```
┌─────────────────────────────────────────────────────────────┐
│                   TARGET ARCHITECTURE                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────────────────────────────┐             │
│  │          Modern Web UI (React/Vue)          │             │
│  │  - Timeline slider                          │             │
│  │  - Before/after compare                     │             │
│  │  - Filter by station/tool/operation         │             │
│  │  - Natural language search                  │             │
│  └──────────────────────┬──────────────────────┘             │
│                         │                                    │
│                         ▼                                    │
│  ┌─────────────────────────────────────────────┐             │
│  │        Intelligence Layer (LLM)             │             │
│  │  - Automatic "release notes" generation     │             │
│  │  - Natural language Q&A                     │             │
│  │  - Work session clustering                  │             │
│  │  - Pattern recognition                      │             │
│  │  (DeepSeek for token economics)             │             │
│  └──────────────────────┬──────────────────────┘             │
│                         │                                    │
│                         ▼                                    │
│  ┌─────────────────────────────────────────────┐             │
│  │         Snapshot/Diff Engine                │             │
│  │  - Periodic snapshots (~5 min intervals)    │             │
│  │  - Compute meaningful diffs                 │             │
│  │  - Store history timeline                   │             │
│  │  - Non-intrusive (read-only)                │             │
│  └──────────────────────┬──────────────────────┘             │
│                         │                                    │
│                         ▼                                    │
│  ┌──────────────────┐   │   ┌──────────────────┐             │
│  │   Oracle/eMServer│◄──┴──►│  History DB      │             │
│  │   (source)       │       │  (snapshots)     │             │
│  └──────────────────┘       └──────────────────┘             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Feature: Version Control / Change Tracking

### Design Goals

| Goal | Description |
|------|-------------|
| **Track changes over time** | Rename events, hierarchy changes (moves/re-parenting), transform/pose changes (locations moved), adds/removes |
| **Simple & intuitive** | High signal, easy to use, no learning curve |
| **Non-intrusive** | No disruption to simulators, no locks, no heavy queries that slow work |
| **Read-only** | Lightweight polling or event-driven if available |

### Snapshot Mechanism

```
┌─────────────────────────────────────────────────────────────┐
│               SNAPSHOT APPROACH                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Every ~5 minutes:                                           │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐    │
│  │  Snapshot    │───►│   Compare    │───►│   Store      │    │
│  │  Current     │    │   to Last    │    │   Delta      │    │
│  │  State       │    │   Snapshot   │    │   History    │    │
│  └──────────────┘    └──────────────┘    └──────────────┘    │
│                              │                               │
│                              ▼                               │
│                    ┌──────────────────┐                      │
│                    │  Generate Diff   │                      │
│                    │  - Renames       │                      │
│                    │  - Moves         │                      │
│                    │  - Transforms    │                      │
│                    │  - Adds/Removes  │                      │
│                    └──────────────────┘                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### "Logical Deductions" (Beyond Raw Diffs)

The system should derive **meaning**, not just raw changes:

| Raw Diff | Logical Deduction |
|----------|-------------------|
| 15 nodes renamed with pattern X | "Station X was reorganized" |
| Tool locations shifted by consistent delta | "Operations were retaught/shifted" |
| Node duplicated, children copied, name changed | "Tool set was duplicated and renamed" |
| MFG references updated | "Change relates to joining update" |
| Resource refs updated without MFG change | "Resource reshuffle only" |

---

## LLM-Powered Features

### Use Case: Automatic "Release Notes"

```
┌─────────────────────────────────────────────────────────────┐
│                    LLM SUMMARY ENGINE                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Input: Last hour/day/week of DB changes                     │
│                                                              │
│  Output:                                                     │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ ## Changes Summary - January 15, 2026                   │ │
│  │                                                         │ │
│  │ ### Station P702                                        │ │
│  │ - 3 weld operations retaught (avg shift: 2.3mm)         │ │
│  │ - Tool "GunA_v3" renamed to "GunA_v4"                   │ │
│  │                                                         │ │
│  │ ### Resource Library                                    │ │
│  │ - 2 new tool prototypes added                           │ │
│  │ - "FixtureSet_B" duplicated from "FixtureSet_A"         │ │
│  │                                                         │ │
│  │ ### User Activity                                       │ │
│  │ - john.doe: 47 changes (mostly P702)                    │ │
│  │ - jane.smith: 12 changes (Resource Library)             │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Use Case: Natural Language Q&A

Example queries the system should answer:

| Question | Expected Response |
|----------|-------------------|
| "What changed in Station X since yesterday?" | List of changes with timestamps and users |
| "Show me every tool instance rename in this study" | Filtered list of rename events |
| "Who modified the weld operations in P736 last week?" | User attribution with change counts |
| "Has the robot path for GunA changed this month?" | Transform delta analysis |
| "What work sessions happened today?" | Clustered changes grouped by user/time |

### LLM Selection Criteria

| Criterion | Consideration |
|-----------|---------------|
| **Token Economics** | DeepSeek attractive for cost-effectiveness |
| **Performance** | Must handle structured data summarization |
| **Latency** | Real-time Q&A requires fast responses |
| **Integration** | API-based, no local hosting required |

---

## Milestones & Phases

### Phase 1: Current State (Complete)
**Goal**: Static tree visualization with icon support

- [x] PowerShell orchestration framework
- [x] Oracle connectivity with credential management
- [x] Tree extraction via hierarchical SQL queries
- [x] Icon extraction from BLOB fields
- [x] Interactive HTML tree output
- [x] Search functionality
- [x] Custom node ordering
- [x] PC profile management

### Phase 2: Enhanced Node Coverage (In Progress)
**Goal**: Extract all node types from all relevant tables

- [x] COLLECTION_ nodes
- [x] RobcadStudy nodes (ROBCADSTUDY_ table)
- [x] ToolPrototype nodes (TOOLPROTOTYPE_ table)
- [x] ToolInstanceAspect nodes (TOOLINSTANCEASPECT_ table)
- [ ] Operation nodes (operation tables)
- [ ] MFG/Joining nodes
- [ ] Panel data nodes

### Phase 3: Snapshot Infrastructure
**Goal**: Periodic snapshots with diff computation

- [ ] Snapshot schema design (history storage)
- [ ] Lightweight polling mechanism
- [ ] Diff computation engine
- [ ] Delta storage and retrieval
- [ ] Performance optimization (non-intrusive)

### Phase 4: Modern Web UI
**Goal**: Replace static HTML with interactive SPA

- [ ] React/Vue frontend framework
- [ ] Timeline slider component
- [ ] Before/after compare view
- [ ] Advanced filtering (station/tool/operation/type)
- [ ] Diff visualization (especially 3D transforms)
- [ ] Responsive design

### Phase 5: LLM Integration
**Goal**: AI-powered summaries and search

- [ ] LLM service integration (DeepSeek or similar)
- [ ] Automatic release notes generation
- [ ] Natural language Q&A interface
- [ ] Work session clustering
- [ ] Pattern recognition (copy/paste detection, etc.)

### Phase 6: Automation & Alerting
**Goal**: Scheduled runs and notifications

- [ ] Scheduled snapshot automation
- [ ] Rollup reports (hourly/daily/weekly)
- [ ] Alert rules (large changes, specific patterns)
- [ ] Notification channels (email, Slack, Teams)

---

## Acceptance Criteria

### Per-Phase Acceptance Criteria

#### Phase 2: Enhanced Node Coverage
```
GIVEN the tree generator runs against DESIGN12 schema
WHEN extracting nodes for FORD_DEARBORN project
THEN:
  - All ToolPrototype nodes appear in tree
  - All ToolInstanceAspect nodes appear with correct parents
  - All icons display correctly (no missing icons)
  - Node count matches Siemens application
  - Performance: <30 seconds for full extraction
```

#### Phase 3: Snapshot Infrastructure
```
GIVEN the snapshot service is running
WHEN a user renames a node in Process Simulate
THEN:
  - Next snapshot captures the change within 5 minutes
  - Diff shows old name → new name with timestamp
  - No noticeable impact on Process Simulate performance
  - Change persists in history after 24 hours
```

#### Phase 4: Modern Web UI
```
GIVEN the web UI is loaded
WHEN user navigates the timeline
THEN:
  - Tree updates to show state at selected time
  - Compare view highlights differences
  - Filter controls narrow displayed nodes
  - UI responds within 200ms to interactions
```

#### Phase 5: LLM Integration
```
GIVEN change history exists for past week
WHEN user asks "What changed in Station P702 yesterday?"
THEN:
  - LLM returns human-readable summary
  - Summary includes relevant changes only
  - Response time: <5 seconds
  - Changes can be drilled into for details
```

---

## Database Reference

### Primary Tables

| Table | Purpose | Row Count (DESIGN2) |
|-------|---------|---------------------|
| REL_COMMON | Parent-child relationships | 8.6M |
| PROXY | Proxy objects | 2.8M |
| PROXY_VERSIONS | Version tracking | 2.8M |
| VEC_LOCATION1_ | Location vectors | 800K+ |
| VEC_ROTATION1_ | Rotation vectors | 800K+ |
| COLLECTION_ | Main node storage | 21K |
| TOOLPROTOTYPE_ | Tool definitions | ~284 |
| TOOLINSTANCEASPECT_ | Tool instances | ~25K |
| CLASS_DEFINITIONS | Type metadata | 527 |
| DF_ICONS_DATA | Icon BLOBs | 95+ |

### Key Queries

#### Hierarchical Tree Navigation
```sql
SELECT LEVEL, c.OBJECT_ID, c.CAPTION_S_, ...
FROM SCHEMA.REL_COMMON r
INNER JOIN SCHEMA.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
START WITH r.FORWARD_OBJECT_ID = @ProjectId
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
```

#### Icon Extraction
```sql
SELECT
    di.TYPE_ID,
    RAWTOHEX(DBMS_LOB.SUBSTR(di.CLASS_IMAGE, DBMS_LOB.GETLENGTH(di.CLASS_IMAGE), 1))
FROM SCHEMA.DF_ICONS_DATA di
WHERE di.CLASS_IMAGE IS NOT NULL
```

---

## Constraints & Non-Functional Requirements

### Critical Constraints

| Constraint | Requirement |
|------------|-------------|
| **Non-intrusive** | Must not slow down simulators or lock resources |
| **Read-only** | No writes to production database |
| **Windows compatibility** | PowerShell 5.1+, Oracle Instant Client 12c |
| **Network aware** | Handle disconnections gracefully |

### Security Requirements

| Requirement | Implementation |
|-------------|----------------|
| Credential storage | DPAPI encryption (DEV) or Windows Credential Manager (PROD) |
| No plaintext passwords | All passwords encrypted at rest |
| Git-safe | Credentials excluded via .gitignore |
| Least privilege | Read-only database user |

### Performance Targets

| Operation | Target |
|-----------|--------|
| Full tree extraction | <30 seconds |
| Icon extraction (95 icons) | <10 seconds |
| UI interaction response | <200ms |
| Snapshot duration | <60 seconds |
| LLM query response | <5 seconds |

---

## Licensing & IP Considerations

### Project License
- **License**: MIT
- **Intent**: Open source the tooling, transparent about third-party licenses

### IP Boundaries

| Included | Excluded |
|----------|----------|
| Custom PowerShell scripts | Siemens proprietary code |
| SQL queries for public schema patterns | Customer data |
| HTML/JavaScript visualization | Licensing bypass mechanisms |
| Documentation | Siemens internal documentation |

### Commercialization Path

The tool is designed to potentially become a **subscription product** that adds a modern analytics layer on top of existing ecosystems. Value is in:
- UX improvements
- Grouping and reporting
- Insights and change tracking
- NOT in copying Siemens internals

---

## Agent Task Templates

### Task: Add New Node Type Extraction

```markdown
## Task: Extract [NODE_TYPE] Nodes

### Objective
Add SQL extraction for [NODE_TYPE] from [TABLE_NAME] table.

### Steps
1. Query table structure:
   ```sql
   SELECT COLUMN_NAME, DATA_TYPE, NULLABLE
   FROM ALL_TAB_COLUMNS
   WHERE TABLE_NAME = '[TABLE_NAME]' AND OWNER = 'DESIGN12'
   ORDER BY COLUMN_ID;
   ```

2. Identify parent relationship column (REL_COMMON, COLLECTIONS_VR_, or ATTACHEDTO_SR_)

3. Add extraction query to `src/powershell/main/generate-tree-html.ps1`

4. Add icon handling if needed in `src/powershell/main/generate-full-tree-html.ps1`

5. Test with FORD_DEARBORN project (ID: 18140190)

### Acceptance Criteria
- [ ] Nodes appear in tree hierarchy
- [ ] Icons display correctly
- [ ] Parent-child relationships correct
- [ ] No console errors
```

### Task: Implement Snapshot Diff

```markdown
## Task: Implement [ENTITY] Diff Detection

### Objective
Detect and record changes to [ENTITY] between snapshots.

### Steps
1. Define snapshot schema for [ENTITY]
2. Implement extraction query
3. Implement comparison logic
4. Store delta in history
5. Add to diff report

### Acceptance Criteria
- [ ] Changes detected within 5 minutes
- [ ] Diff shows before/after values
- [ ] Performance impact: <1% CPU on DB server
- [ ] History retention: 30 days
```

---

## Glossary

| Term | Definition |
|------|------------|
| **eMServer** | Siemens Process Simulate server tier (Oracle-based) |
| **Teamcenter** | Alternative Siemens PLM backend (SQL Server-based) |
| **CONNECT BY NOCYCLE** | Oracle hierarchical query syntax |
| **DPAPI** | Windows Data Protection API for credential encryption |
| **TNS** | Oracle Transparent Network Substrate (connection naming) |
| **Compound Resource** | Collection of tool instances in resource tree |
| **Twin** | Entity appearing in both resource and object views |
| **MFG** | Manufacturing feature library |

---

## Contact & Attribution

**Project**: SimTreeNav  
**Repository**: Process Simulation Tree Viewer  
**Primary Technologies**: PowerShell, Oracle 12c, HTML/JavaScript  

---

**Document Version**: 1.0  
**Last Updated**: January 15, 2026  
**Status**: Living Document - Update as requirements evolve

