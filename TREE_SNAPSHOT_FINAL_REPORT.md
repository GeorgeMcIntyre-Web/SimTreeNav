# Tree Snapshot + Diff System - Final Implementation Report

**Date:** 2026-01-30
**Branch:** `feat/tree-snapshot-diff`
**Status:** ✅ Ready for Testing

---

## What Changed

### New Files Created

1. **[scripts/debug/export-study-tree-snapshot.ps1](scripts/debug/export-study-tree-snapshot.ps1)**
   - Purpose: Export deterministic snapshot of study tree structure, naming, and locations
   - Captures 3 separate trees: Operation, Resource, MFG
   - Deterministic naming resolution with provenance tracking
   - Coordinate lookup via STUDYLAYOUT_.OBJECT_ID → VEC_LOCATION_
   - Clear labeling of deterministic vs heuristic mappings

2. **[scripts/debug/compare-study-tree-snapshots.ps1](scripts/debug/compare-study-tree-snapshots.ps1)**
   - Purpose: Compare two snapshots to detect tree changes
   - Detects: rename, move, structure, resource mapping, add/remove
   - Movement classification: simple (<1000mm) vs world (>=1000mm)
   - Based on delta_mm calculation, not vector ID presence

3. **[docs/TREE_EVIDENCE_INTEGRATION.md](docs/TREE_EVIDENCE_INTEGRATION.md)**
   - Proposal for integrating tree changes into evidence model
   - Extends deltaSummary with new kinds: naming, structure, resourceMapping, topology
   - Proposes schemaVersion 1.3.0 (backward compatible)
   - Data flow diagram and testing strategy

### Documentation Updated

4. **[docs/E2E_VALIDATION_INDEX.md](docs/E2E_VALIDATION_INDEX.md)**
   - Added "Tree Snapshot + Tree Diff Validation" section
   - Test workflow documented
   - Expected results and validation checklist
   - Known limitations documented

5. **[docs/MANAGER_E2E_MEGA_SUMMARY.md](docs/MANAGER_E2E_MEGA_SUMMARY.md)**
   - Added "Tree Naming + Structure + Location Tracking Status" section
   - Manager commands for tree snapshot operations
   - Use cases and known limitations

---

## Implementation Details

### Tree Structure Captured

Process Simulate studies contain 3 separate trees (updated based on user feedback):

1. **Operation Tree**
   - Nodes: OPERATION_ table
   - Contains: weld operations, movement operations, operation groups
   - Traversal: REL_COMMON hierarchical query from study root

2. **Resource Tree**
   - Nodes: SHORTCUT_ table pointing to RESOURCE_
   - Contains: robots, fixtures, tools (via shortcuts to resource library)
   - Linking: SHORTCUT_.LINKEXTERNALID_S_ → RESOURCE_.EXTERNALID_S_

3. **MFG Tree** (Manufacturing Features)
   - Nodes: MFGFEATURE_ table
   - Contains: manufacturing features used to create locations
   - Important for location/layout tracking

4. **Collection Nodes**
   - Nodes: COLLECTION_ table (folders, containers)
   - Used for organizational structure within study

### Naming Resolution Precedence

For each node, display_name is resolved using this precedence:

1. Resource name (for shortcuts): `RESOURCE_.NAME_S_`
2. Shortcut name: `SHORTCUT_.NAME_S_`
3. Operation name: `OPERATION_.NAME_S_`
4. MFG feature name: `MFGFEATURE_.NAME_S_`
5. Collection caption: `COLLECTION_.CAPTION_S_`
6. External ID: `EXTERNALID_S_`
7. Object ID: `OBJECT_ID` (fallback)

All sources are documented in `name_provenance` field.

### Coordinate Lookup (Deterministic + Heuristic)

**Deterministic Path:**
1. StudyInfo → StudyLayout (via STUDYINFO_SR_)
2. StudyLayout.OBJECT_ID → VEC_LOCATION_ (SEQ_NUMBER 0/1/2 = X/Y/Z)

**Heuristic Path:**
- Timestamp matching: StudyInfo.MODIFICATIONDATE_DA_ = Shortcut.MODIFICATIONDATE_DA_
- Labeled as `mapping_type: "heuristic"`
- Ambiguous when multiple robots created at same timestamp

**Provenance Tracking:**
- All coordinate sources documented in `coord_provenance` field
- Example: `"STUDYLAYOUT_.OBJECT_ID -> VEC_LOCATION_ (heuristic timestamp match)"`

### Mapping Classification

- **deterministic:** Direct foreign key relationship (shortcut → resource via LINKEXTERNALID_S_)
- **deterministic+heuristic_coords:** Resource link is deterministic, coordinates are heuristic
- **heuristic:** Timestamp-based matching (StudyInfo ↔ Shortcut)
- **heuristic_ambiguous:** Multiple candidates at same timestamp (flagged for review)
- **none:** No mapping available

---

## Snapshot Output Format

```json
{
  "meta": {
    "schemaVersion": "1.0.0",
    "capturedAt": "2026-01-30 14:30:00",
    "schema": "DESIGN12",
    "projectId": 18851221,
    "studyId": 18879453,
    "studyName": "RobcadStudy1_2",
    "nodeCount": 42,
    "nodesWithNames": 42,
    "nodesWithCoords": 5,
    "deterministicMappings": 4,
    "heuristicMappings": 1,
    "ambiguousMappings": 0
  },
  "treeCounts": {
    "operationNodes": 15,
    "resourceNodes": 4,
    "mfgNodes": 8,
    "collectionNodes": 15
  },
  "nodes": [
    {
      "tree_type": "RESOURCE",
      "node_id": "18880389",
      "parent_node_id": "18879453",
      "depth": 1,
      "seq_number": "0",
      "node_type": "Shortcut",
      "class_id": "69",
      "class_name": "class PmShortcut",
      "external_id": "",
      "display_name": "r2000ic_210l_if_v02",
      "is_shortcut": true,
      "resource_id": "18880386",
      "resource_name": "r2000ic_210l_if_v02",
      "resource_type": "ToolInstance",
      "layout_id": "18880389",
      "x": 1350,
      "y": 0,
      "z": 0,
      "modified_date": "2026-01-29 15:52:26",
      "name_provenance": "RESOURCE_.NAME_S_",
      "coord_provenance": "STUDYLAYOUT_.OBJECT_ID -> VEC_LOCATION_ (heuristic timestamp match)",
      "mapping_type": "deterministic+heuristic_coords"
    }
  ]
}
```

---

## Diff Output Format

```json
{
  "meta": {
    "schemaVersion": "1.0.0",
    "comparedAt": "2026-01-30 14:35:00",
    "totalChanges": 3
  },
  "summary": {
    "renamed": 1,
    "moved": 1,
    "simple_moves": 0,
    "world_moves": 1,
    "structural_changes": 0,
    "resource_mapping_changes": 0,
    "nodes_added": 1,
    "nodes_removed": 0
  },
  "changes": {
    "renamed": [
      {
        "node_id": "18880389",
        "old_name": "r2000ic_210l_if_v02",
        "new_name": "r2000ic_210l_if_v02_renamed",
        "node_type": "Shortcut",
        "old_provenance": "RESOURCE_.NAME_S_",
        "new_provenance": "RESOURCE_.NAME_S_"
      }
    ],
    "moved": [
      {
        "node_id": "18880389",
        "display_name": "r2000ic_210l_if_v02",
        "node_type": "Shortcut",
        "old_x": 1350, "old_y": 0, "old_z": 0,
        "new_x": 2550, "new_y": 0, "new_z": 0,
        "delta_x": 1200, "delta_y": 0, "delta_z": 0,
        "delta_mm": 1200,
        "movement_type": "WORLD",
        "mapping_type": "deterministic+heuristic_coords"
      }
    ]
  }
}
```

---

## Statistics Summary Table

| Metric | Value | Notes |
|--------|-------|-------|
| **Snapshot Node Count** | Varies by study | Total nodes across all 3 trees |
| **Nodes with Names Resolved** | ~100% | All nodes get a name (fallback to OBJECT_ID) |
| **Nodes with Coords Resolved** | Depends on study | Only layout-enabled nodes (robots, fixtures) |
| **Deterministic Mappings** | Majority | Direct FK relationships (shortcut → resource) |
| **Heuristic Mappings** | Minority | Timestamp-based (StudyInfo ↔ Shortcut) |
| **Ambiguous Mappings** | Rare | Multiple robots at same timestamp |

---

## Exact Commands to Run (Validation)

### 1. Export Baseline Snapshot

```powershell
pwsh scripts/debug/export-study-tree-snapshot.ps1 `
    -TNSName "DES_SIM_DB1_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18851221 `
    -StudyId 18879453 `
    -IncludeCSV
```

**Expected Output:**
- JSON file: `data/output/study-tree-snapshot-DESIGN12-18879453-[timestamp].json`
- CSV file (if requested): `data/output/study-tree-snapshot-DESIGN12-18879453-[timestamp].csv`
- Console output showing node counts by tree type

### 2. Perform Siemens Actions (Manual)

In Process Simulate:
1. Check out RobcadStudy1_2
2. Rename a robot: `r2000ic_210l_if_v02` → `r2000ic_210l_if_v02_renamed`
3. Move a robot 1200mm in X (world move)
4. Add a new robot (e.g., `r2000ic_210l_if_v02_4`)
5. Save the study
6. Check in (optional)

### 3. Export Current Snapshot

```powershell
pwsh scripts/debug/export-study-tree-snapshot.ps1 `
    -TNSName "DES_SIM_DB1_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18851221 `
    -StudyId 18879453 `
    -IncludeCSV
```

### 4. Compare Snapshots

```powershell
pwsh scripts/debug/compare-study-tree-snapshots.ps1 `
    -BaselineSnapshot "data/output/study-tree-snapshot-DESIGN12-18879453-[baseline-timestamp].json" `
    -CurrentSnapshot "data/output/study-tree-snapshot-DESIGN12-18879453-[current-timestamp].json" `
    -ShowDetails
```

**Expected Output:**
- JSON diff file: `data/output/tree-diff-18879453-[timestamp].json`
- Console summary:
  - Renamed nodes: 1
  - Moved nodes: 1 (world move)
  - Nodes added: 1
  - Total changes: 3

### 5. Verify Deterministic Behavior (Repeatability Test)

```powershell
# Run export twice without changes
pwsh scripts/debug/export-study-tree-snapshot.ps1 `
    -TNSName "DES_SIM_DB1_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18851221 `
    -StudyId 18879453

# Compare the two identical snapshots
pwsh scripts/debug/compare-study-tree-snapshots.ps1 `
    -BaselineSnapshot "data/output/study-tree-snapshot-DESIGN12-18879453-[run1].json" `
    -CurrentSnapshot "data/output/study-tree-snapshot-DESIGN12-18879453-[run2].json"
```

**Expected Result:** Total changes = 0 (except capture timestamp difference)

---

## What's Deterministic vs Heuristic

### ✅ Deterministic (Provable via FK Relationships)

1. **Tree Structure:**
   - Parent/child edges via REL_COMMON.FORWARD_OBJECT_ID → OBJECT_ID
   - Depth and sequence numbers
   - Node type via CLASS_DEFINITIONS.TYPE_ID

2. **Node Naming:**
   - Resource names via SHORTCUT_.LINKEXTERNALID_S_ → RESOURCE_.EXTERNALID_S_ → RESOURCE_.NAME_S_
   - Operation names via OPERATION_.NAME_S_
   - MFG feature names via MFGFEATURE_.NAME_S_
   - Collection captions via COLLECTION_.CAPTION_S_

3. **Resource Mapping:**
   - Shortcut → Resource via LINKEXTERNALID_S_ match

4. **Layout Coordinates (Direct):**
   - StudyLayout.OBJECT_ID → VEC_LOCATION_ direct lookup

### ⚠️ Heuristic (Timestamp-Based Inference)

1. **Layout-to-Shortcut Mapping:**
   - StudyInfo.MODIFICATIONDATE_DA_ = Shortcut.MODIFICATIONDATE_DA_
   - Fails when multiple robots created at same timestamp
   - Flagged as `heuristic` or `heuristic_ambiguous`

2. **Why Heuristic is Needed:**
   - No direct FK from StudyLayout → Shortcut in Oracle schema
   - StudyInfo table links to layout but not to specific shortcut
   - Best-effort matching based on timestamps

3. **Mitigation:**
   - Clear labeling in `mapping_type` field
   - Provenance tracking in `coord_provenance`
   - Ambiguity flagging when >1 candidate
   - Workaround: Touch robots one-by-one to create unique timestamps

---

## How This Supports Study Health

### Immediate Benefits

1. **Audit Trail:** Historical snapshots prove tree structure at specific points in time
2. **Change Detection:** Automatically detect rename, move, add, remove actions
3. **Compliance:** Prove coordinates match Process Simulate UI (via VEC_LOCATION_ direct lookup)
4. **Debugging:** Investigate naming or location discrepancies

### Future Integration with Evidence Model

1. **Automated Evidence Generation:**
   - Tree diff detects changes → generate evidence blocks
   - Map to workflow phases (study.naming, study.layout, study.topology)
   - Confidence classification based on checkout + write + delta

2. **Study Health Rules:**
   - Flag ambiguous layout mappings (critical)
   - Flag missing names (high)
   - Flag broken resource mappings (high)
   - Flag world moves without approval (medium)

3. **Manager Dashboard:**
   - Timeline of tree changes
   - Movement classification (simple vs world)
   - Topology changes (add/remove robots)

---

## Known Limitations

1. **Ambiguous Layout Mapping:**
   - Multiple robots created at same timestamp → heuristic mapping is ambiguous
   - Clearly labeled in output
   - Workaround: Touch robots one-by-one

2. **Performance:**
   - Tree export may be slow for very large studies (1000s of nodes)
   - Mitigated by hierarchical queries (CONNECT BY)

3. **Schema Dependency:**
   - Queries assume Oracle Process Simulate schema structure
   - If schema changes, queries may need updates

---

## Files Modified/Created Summary

### Created (3 scripts + 1 doc)
- ✅ `scripts/debug/export-study-tree-snapshot.ps1`
- ✅ `scripts/debug/compare-study-tree-snapshots.ps1`
- ✅ `docs/TREE_EVIDENCE_INTEGRATION.md`
- ✅ `TREE_SNAPSHOT_FINAL_REPORT.md` (this file)

### Updated (2 docs)
- ✅ `docs/E2E_VALIDATION_INDEX.md` (added tree snapshot section)
- ✅ `docs/MANAGER_E2E_MEGA_SUMMARY.md` (added tree tracking status)

### Unchanged (all existing fixes remain intact)
- ✅ Project scoping queries (REL_COMMON traversal)
- ✅ VEC_LOCATION_ coordinate lookup
- ✅ Resource linking (LINKEXTERNALID_S_ join)
- ✅ No hardcoded credentials

---

## Next Steps

1. **Testing:**
   - Run validation commands on _testing project
   - Verify rename, move, add, remove detection
   - Confirm deterministic behavior (same inputs = same outputs)

2. **Code Review:**
   - Review SQL queries for correctness
   - Validate provenance tracking logic
   - Ensure all 3 trees are captured correctly

3. **Integration (Future):**
   - Integrate tree diff into get-management-data.ps1
   - Generate evidence blocks from tree changes
   - Update dashboard to visualize tree changes

4. **Commit:**
   - Once validated, commit to `feat/tree-snapshot-diff` branch
   - Create PR for review
   - Merge to main after approval

---

**Prepared by:** Claude Code (Sonnet 4.5)
**Date:** 2026-01-30
**Branch:** feat/tree-snapshot-diff
**Status:** ✅ Ready for Testing
