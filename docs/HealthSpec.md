# Study Health Specification v1

**Purpose**: Define the contract and scoring rules for Study Health metrics.

**Date**: 2026-02-03

---

## Health Contract

Each study in the `studySummary` array must include the following health fields:

### Required Fields

```json
{
  "healthScore": 85,
  "healthStatus": "Healthy",
  "healthReasons": ["root_resources"],
  "healthSignals": {
    "nodeCount": 47,
    "rootResourceCount": 2,
    "structureUnreadable": false,
    "hasResourcesLoaded": true,
    "resourceCount": 12,
    "hasPanels": true,
    "panelCount": 3,
    "hasMfg": true,
    "mfgCount": 5,
    "projectedMfgCount": 4,
    "hasLocations": true,
    "locationCount": 8,
    "assignedLocationCount": 6,
    "hasOperations": true,
    "operationCount": 15,
    "robotLinkedOperationCount": 12
  }
}
```

### Field Definitions

**`healthScore`** (integer, 0-100)
- Numeric representation of study health
- 0 = critically unhealthy
- 100 = perfect health

**`healthStatus`** (string)
- `"Healthy"` - Score >= 80
- `"Warning"` - Score 40-79
- `"Unhealthy"` - Score < 40

**`healthReasons`** (array of strings)
- Short codes explaining why the score is not 100
- Examples: `"no_nodes"`, `"root_resources"`, `"structure_unreadable"`
- Empty array if score is 100

**`healthSignals`** (object)
- Detailed counts and flags used to compute the score
- All fields are observable facts from the database or snapshots
- UI can display these for transparency
- **New fields (v1.1)**:
  - `snapshotStatus`: "ok" | "missing" | "error" | "unknown"
  - `nodeCountSource`: "snapshot" | "fallback_proxy" | "unknown"

---

## Health Scoring Rules (v1)

### Stage-Aware Philosophy

Study health reflects **evolutionary stages** of study development:

1. **Foundation**: Study exists, has nodes, has readable structure
2. **Resources**: Resources loaded into study
3. **Panels**: Panels created and assigned
4. **MFG**: Manufacturing data loaded and projected to panels
5. **Locations**: Robot/equipment locations created and assigned
6. **Operations**: Operations defined and linked to robots

**Important**: A study is not penalized for missing later-stage signals if earlier-stage signals are also missing. For example, a study with no resources loaded is not penalized for having no locations assigned.

Health scores guide sorting and highlight issues, but are not strict gates.

---

## Scoring Algorithm (v1.1 - Resilient to Missing Snapshots)

### Snapshot Resilience

**Snapshot Status Handling**
- `snapshotStatus = "ok"`: Snapshot exists and is valid
- `snapshotStatus = "missing"`: No snapshot available (not yet generated or skipped)
- `snapshotStatus = "error"`: Snapshot generation failed or file is corrupted
- `snapshotStatus = "unknown"`: Status could not be determined

**Node Count Fallback**
- If snapshot is not available (`snapshotStatus != "ok"`), use fallback proxy count
- Fallback proxy: `nodeCount = resourceCount + panelCount + operationCount`
- Set `nodeCountSource = "fallback_proxy"` when using fallback
- This provides approximate node count without requiring expensive tree traversal

### Hard Fail Rules

**Rule 1: Zero Nodes (Only with Valid Snapshot)**
- If `snapshotStatus == "ok"` AND `nodeCount == 0`, set `score = 0`, `status = "Unhealthy"`, add reason `"no_nodes"`
- This is a critical failure - study cannot function without nodes
- **Important**: Hard fail only triggers when we have confirmed zero nodes via snapshot

### Snapshot Missing/Error Handling

**Rule 1b: Snapshot Missing**
- If `snapshotStatus == "missing"`, start at score 45 (Warning range)
- Add reason: `"snapshot_missing"`
- Continue with other scoring rules from this base

**Rule 1c: Snapshot Error**
- If `snapshotStatus == "error"`, start at score 40 (Warning range)
- Add reason: `"snapshot_error"`
- Continue with other scoring rules from this base

### Penalty Rules

**Rule 2: Root Resources (Minor Penalty)**
- If `rootResourceCount > 0`, subtract 10 points
- Add reason: `"root_resources"`
- Issue: Resources should be in subfolders, not at study root

**Rule 3: Structure Unreadable (Moderate Penalty)**
- If `structureUnreadable == true`, subtract 20 points
- Add reason: `"structure_unreadable"`
- Issue: Study structure doesn't follow expected naming conventions

### Stage Evolution Signals (Informational, Light Scoring)

These signals reflect study maturity but use **gentle penalties**:

**Resources Stage**
- `hasResourcesLoaded` - At least one resource instance exists
- `resourceCount` - Total resource instances
- Penalty if missing: -5 points (only if study has nodes)

**Panels Stage**
- `hasPanels` - At least one panel exists
- `panelCount` - Total panels
- Penalty if missing: -5 points (only if resources loaded)

**MFG Stage**
- `hasMfg` - At least one MFG record exists
- `mfgCount` - Total MFG records
- `projectedMfgCount` - MFG records projected to panels
- Penalty if none projected: -5 points (only if MFG exists)

**Locations Stage**
- `hasLocations` - At least one location exists
- `locationCount` - Total locations
- `assignedLocationCount` - Locations assigned to robots
- Penalty if none assigned: -5 points (only if locations exist)

**Operations Stage**
- `hasOperations` - At least one operation exists
- `operationCount` - Total operations
- `robotLinkedOperationCount` - Operations linked to robots
- Penalty if none linked: -5 points (only if operations exist)

### Scoring Summary

| Condition | Points | Reason Code |
|-----------|--------|-------------|
| Zero nodes (with valid snapshot) | 0 (hard fail) | `no_nodes` |
| Snapshot missing | 45 (base) | `snapshot_missing` |
| Snapshot error | 40 (base) | `snapshot_error` |
| Root resources > 0 | -10 | `root_resources` |
| Structure unreadable | -20 | `structure_unreadable` |
| No resources (if nodes exist) | -5 | `no_resources` |
| No panels (if resources exist) | -5 | `no_panels` |
| MFG not projected (if MFG exists) | -5 | `mfg_not_projected` |
| Locations not assigned (if locations exist) | -5 | `locations_not_assigned` |
| Operations not robot-linked (if ops exist) | -5 | `operations_not_linked` |

**Base score**: 100 (or 45/40 for missing/error snapshots)
**Final score**: `max(0, base - penalties)`

---

## Health Status Thresholds

| Score Range | Status | Meaning |
|-------------|--------|---------|
| >= 80 | `Healthy` | Study is well-structured and complete for its stage |
| 40-79 | `Warning` | Study has some issues but is usable |
| < 40 | `Unhealthy` | Study has serious structural problems |

---

## UI Display Guidelines

### Studies Tab

**Default Sort Order**:
1. `healthStatus` (Unhealthy first, then Warning, then Healthy)
2. `healthScore` (ascending - worst scores first)
3. `checkedOut` (checked out first)
4. `modifiedInRange` (modified first)

**Compact Display**:
- Status pill (colored badge): Unhealthy (red) | Warning (yellow) | Healthy (green)
- Score number next to pill
- Tooltip on hover showing:
  - Health reasons (if any)
  - Key signal counts (nodeCount, resourceCount, panelCount, etc.)

**Example Tooltip**:
```
Score: 75 (Warning)
Reasons: root_resources, mfg_not_projected
---
Nodes: 47
Resources: 12
Panels: 3
MFG: 5 (4 projected)
```

---

## Future Extensions (Not in v1)

Potential v2 enhancements:
- Weight penalties by study size/complexity
- Time-based penalties (e.g., checked out for >30 days)
- User-configurable thresholds
- Custom rules per project/team
- Trend analysis (health over time)

---

## Change History

- **2026-02-03**: v1.1 - Added snapshot resilience (snapshotStatus, nodeCountSource, fallback proxy count)
- **2026-02-03**: v1.0 - Initial specification (Phase 2 deliverable)
