# SimTreeNav Codebase Map

**Purpose**: Quick navigation guide for AI agents and human developers.

**Date**: 2026-02-03

---

## Entry Scripts

### `update-dashboard.ps1` (Root Orchestrator)
- **What**: Main entry point for dashboard generation
- **Does**: Calls `get-management-data.ps1` → `generate-management-dashboard.ps1`
- **Parameters**: TNSName, Schema, ProjectId, StartDate, EndDate, Mode, ForceRefresh
- **Output**: HTML dashboard + JSON data cache
- **Location**: Repository root

### `src/powershell/main/get-management-data.ps1` (Data Collector)
- **What**: Queries Oracle database for all management reporting data
- **Does**: 
  - Executes 14 parallel database queries
  - Computes `workTypeSummaryMeta` counts
  - Computes Study Health fields (v1)
  - Exports JSON to `cache/` directory
- **Output**: `management-data-{Schema}-{ProjectId}.json`
- **Key Functions**: `Compute-StudyHealth` (local function)

### `scripts/generate-management-dashboard.ps1` (HTML Generator)
- **What**: Reads JSON and generates interactive HTML dashboard
- **Does**:
  - Validates `workTypeSummaryMeta.studyNodes` contract
  - Renders 5 tabs: Overview, Studies, Resources, Panels, Changes
  - Sorts Studies tab by health
  - Displays health scores/status/tooltips
- **Output**: HTML file in `output/` directory
- **Key Functions**: JavaScript `renderActiveStudies()`, `buildHealthIndex()`

### `scripts/debug/diagnose-study-counts.ps1` (Diagnostic)
- **What**: Validates JSON counts against direct database queries
- **Does**: Compares reported counts with fresh DB queries for parity
- **Use**: Testing and troubleshooting count accuracy

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│  update-dashboard.ps1 (orchestrator)                        │
└──────────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┴──────────────────┐
         │                                    │
         ▼                                    ▼
┌──────────────────────────┐      ┌──────────────────────────┐
│ get-management-data.ps1  │      │  (uses cached JSON if    │
│  - Query Oracle DB       │      │   not ForceRefresh)      │
│  - Compute Health        │      │                          │
│  - Write JSON cache      │      └──────────────────────────┘
└──────────────┬───────────┘
               │
               ▼
      ┌────────────────┐
      │  JSON cache    │
      │  (source of    │
      │   truth)       │
      └────────┬───────┘
               │
               ▼
┌──────────────────────────┐
│ generate-management-     │
│   dashboard.ps1          │
│  - Validate contract     │
│  - Render HTML           │
│  - Sort by health        │
└──────────────┬───────────┘
               │
               ▼
      ┌────────────────┐
      │  HTML output   │
      └────────────────┘
```

---

## Study Health (v1)

### Where It's Computed
**File**: `src/powershell/main/get-management-data.ps1`
**Function**: `Compute-StudyHealth` (local function, defined inline)
**When**: After all database queries complete, before JSON export
**Inputs**: Study data + counts from resources/panels/MFG/locations/operations collections

### Where It's Rendered
**File**: `scripts/generate-management-dashboard.ps1`
**Function**: `renderActiveStudies()` (JavaScript)
**How**: 
- Reads `healthScore`, `healthStatus`, `healthReasons` from each study object
- Sorts by health status → score → checkout → modified
- Displays status pill + score + tooltip with reasons

### Health Fields in JSON
Each study in `studySummary` includes:
- `healthScore` (0-100)
- `healthStatus` ("Healthy" | "Warning" | "Unhealthy")
- `healthReasons` (array of reason codes)
- `healthSignals` (object with counts used to compute score)

---

## Key Contracts

### `workTypeSummaryMeta.studyNodes`
**Producer**: `get-management-data.ps1` (lines ~1398-1415)
**Consumer**: `generate-management-dashboard.ps1` (lines ~1919-1920, ~3064+)
**Spec**: See `docs/ReportingDefinitions.md`

### Study Health Fields
**Producer**: `get-management-data.ps1` (via `Compute-StudyHealth` function)
**Consumer**: `generate-management-dashboard.ps1` (JavaScript `renderActiveStudies()`)
**Spec**: See `docs/HealthSpec.md`

---

## Supporting Modules

### `src/powershell/utilities/DatabaseHelper.ps1`
- Query execution with parallelization
- Connection management
- Error handling

### `src/powershell/utilities/TreeEvidenceClassifier.ps1`
- Classifies tree structure changes
- Used for "Tree Changes" view

### `src/powershell/utilities/CredentialManager.ps1`
- Manages Oracle credentials
- Used by all database scripts

---

## Quick Lookup: "Where is X produced?"

| JSON Field | Produced In | Line Range (approx) |
|------------|-------------|---------------------|
| `studySummary` | get-management-data.ps1 | ~1198 (from query) |
| `workTypeSummaryMeta.studyNodes` | get-management-data.ps1 | ~1398-1415 |
| `healthScore` (per study) | get-management-data.ps1 | `Compute-StudyHealth` function |
| `studyResources` | get-management-data.ps1 | ~1199 (from query) |
| `studyPanels` | get-management-data.ps1 | ~1200 (from query) |
| `studyOperations` | get-management-data.ps1 | ~1201 (from query) |
| `treeChanges` | get-management-data.ps1 | ~1749 (from tree snapshots) |

---

## Quick Lookup: "Where is X rendered?"

| UI Element | Rendered In | Function/Line |
|------------|-------------|---------------|
| Studies tab | generate-management-dashboard.ps1 | `renderActiveStudies()` ~1944 |
| Study health status pill | generate-management-dashboard.ps1 | JavaScript in `renderActiveStudies()` |
| Study counts (header) | generate-management-dashboard.ps1 | ~1919-1920, ~3064+ |
| Contract validation | generate-management-dashboard.ps1 | (to be added) |

---

## For AI Agents

**If you need to**:
- Change how study health is computed → Edit `get-management-data.ps1` (find `Compute-StudyHealth`)
- Change how health is displayed → Edit `generate-management-dashboard.ps1` (`renderActiveStudies()`)
- Add new database queries → Edit `get-management-data.ps1` (add to parallel jobs section)
- Add new UI tabs → Edit `generate-management-dashboard.ps1` (add tab button + view div + render function)
- Validate counts → Run `diagnose-study-counts.ps1`

**Read these specs first**:
- `docs/ReportingDefinitions.md` - What counts mean and where they come from
- `docs/HealthSpec.md` - How health scoring works

