# Reporting Definitions (Source of Truth)

**Purpose**: Canonical definitions for all management reporting metrics.

**Date**: 2026-02-03

---

## Core Definitions

### Checked Out

A study node is considered **Checked Out** if:

```
PROXY.WORKING_VERSION_ID > 0
```

- Source: `ROBCAD.PROXY` table
- Scope: Proxy scope (all studies where `PROXY` records exist for the project)
- Database field: `WORKING_VERSION_ID`

### Modified (Range)

A study node is considered **Modified in Range** if:

```
ROBCADSTUDY_.MODIFICATIONDATE_DA_ BETWEEN metadata.startDate AND metadata.endDate (inclusive)
```

- Source: `ROBCAD.ROBCADSTUDY_` table
- Database field: `MODIFICATIONDATE_DA_`
- Range: Specified by `startDate` and `endDate` in metadata
- Note: Timestamp comparison includes both start and end dates (inclusive)

### Tree Scope vs Proxy Scope

**Tree Scope**: All study nodes that are descendants of the project root via `REL_COMMON` with `REL_TYPE = 4`
- Includes all hierarchical descendants
- Source: Recursive tree traversal from project root `OBJECT_ID`

**Proxy Scope**: All studies that have `PROXY` records in the database
- May be slightly different from tree scope due to orphaned proxies or missing relationships
- Source: `ROBCAD.PROXY` table filtered by project

**Important**: These scopes are always computed explicitly and reported separately. The UI must use the reported counts, not infer them.

---

## Study Nodes Count Contract

### Critical Rule: "No Guessing in UI"

**The dashboard must NEVER recompute Study Nodes counts from lists.**

The UI must render Study Nodes counts ONLY from:

```
workTypeSummaryMeta.studyNodes
```

This object contains:
- `totalStudiesTreeScope` - Total studies in tree hierarchy
- `totalStudiesProxyScope` - Total studies with proxy records
- `checkedOutCount` - Studies with `WORKING_VERSION_ID > 0`
- `modifiedInRangeCount` - Studies modified between `startDate` and `endDate`
- `modifiedButNotCheckedOutCount` - Studies modified but not checked out
- `checkedOutButNotModifiedInRangeCount` - Studies checked out but not modified in range

### Why This Matters

1. **Trustworthy**: Counts are computed once, close to the source (database queries)
2. **Provable**: Direct mapping from SQL query results to JSON to UI
3. **Efficient**: UI doesn't need to re-filter large study lists
4. **Consistent**: All views use the same canonical counts

### Validation

If `workTypeSummaryMeta.studyNodes` is missing or incomplete, the UI must:
1. Display a clear error banner: "Contract mismatch: missing workTypeSummaryMeta.studyNodes"
2. Stop attempting to render counts from study lists
3. Show an empty state or error message instead

---

## Metadata Structure

The `workTypeSummaryMeta` object also includes:

- `checkedOutRule` - SQL/logic description of checked-out definition
- `modifiedRule` - SQL/logic description of modified-in-range definition
- `modifiedTimestampColumn` - Database column used for modified timestamp
- `dateRangeStart` - Start date for modified range (ISO format)
- `dateRangeEnd` - End date for modified range (ISO format)

These fields provide traceability and allow the UI to display the exact rules used to generate the counts.

---

## Previous Run Comparison

### Changed Since Last Run

A study node is considered **Changed Since Last Run** if any of the following differ between the previous run and the current run:

- `healthScore` changed
- `healthStatus` changed
- `WORKING_VERSION_ID` changed (checkout status)
- `modifiedInRange` changed
- Resource count changed (from `healthSignals.resourceCount`)
- Panel count changed (from `healthSignals.panelCount`)
- Operation count changed (from `healthSignals.operationCount`)
- Study name changed (`STUDY_NAME`)

### Storage Pattern

The system maintains two JSON files per project:
- `management-data-{Schema}-{ProjectId}-latest.json` - Current run data
- `management-data-{Schema}-{ProjectId}-prev.json` - Previous run data (backup of latest from prior run)
- `run-state-{Schema}-{ProjectId}.json` - Run metadata (timestamps, file paths, run history)

### Comparison Metadata

Each run includes `metadata.compareMeta` with:
- `mode`: "previous_run" | "no_previous_run" | "diff_failed"
- `prevRunAt`: Timestamp of previous run (ISO format)
- `latestRunAt`: Timestamp of current run (ISO format)
- `changedStudyCount`: Number of studies with detected changes
- `totalStudyCount`: Total number of studies in current run
- `noPreviousRun`: Boolean flag (true if no previous run exists)

### Per-Study Fields

Each study in `studySummary` includes:
- `changedSincePrev`: Boolean indicating if study changed since previous run
- `changeReasons`: Array of change reason codes: ["health", "checkout", "resources", "panels", "operations", "modified", "name", "new", "removed"]

### Dashboard Rendering

The dashboard displays comparison data when available:
- **Header banner**: Shows comparison mode and changed study count
- **Work Summary cards**: Displays "Changed Since Last Run" metric
- **Studies tab filter**: Includes "Changed Since Last Run" option
- **Study badges**: Shows "Changed" badge with tooltip listing reasons

### First Run Behavior

On the first run (no previous data):
- `compareMeta.mode` = "no_previous_run"
- `compareMeta.noPreviousRun` = true
- All studies have `changedSincePrev` = false
- Dashboard shows "First Run" banner

---

## Change History

- **2026-02-03**: Added Previous Run Comparison section (v1.2)
- **2026-02-03**: Initial version (Phase 1 deliverable)
