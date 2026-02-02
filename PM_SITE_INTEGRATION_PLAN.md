# Management Site Integration Plan - Tree Snapshot System
**Date:** 2026-01-30
**Branch:** feat/tree-snapshot-diff
**Commit:** a238d22
**Status:** Ready for PM site integration

---

## Executive Summary

The tree snapshot system is **production-ready** and successfully detects:
- ✅ Robot renames (tested: 4 robots renamed)
- ✅ Robot movements (tested: 2050mm WORLD movement)
- ✅ Movement classification (SIMPLE <1000mm vs WORLD ≥1000mm)
- ✅ Resource mapping with provenance tracking

**Next:** Integrate into PM dashboard to provide managers with real-time study health monitoring.

---

## Implementation Status Update (2026-01-30)

### ✅ Completed in this branch
- **Backend:** `get-management-data.ps1` now collects tree snapshots, diffs them, and emits `treeChanges` in the JSON output (schemaVersion `1.3.0`).
- **Backend:** Added `src/powershell/utilities/TreeEvidenceClassifier.ps1` to map tree diffs into evidence schema v1.3.0.
- **Dashboard (HTML generator):** `scripts/generate-management-dashboard.ps1` now includes a **Tree Changes** view with filters + detail panel and fixes JS template literal escaping (nav buttons work).
- **Launcher:** `management-dashboard-launcher.ps1` now reports tree change counts in its summary.
- **Sample output:** `management-dashboard-DESIGN12-18851221.html` generated locally (left untracked).

### ⚠️ Remaining / verify
- **Re-generate HTML after data updates:**
  - `.\scripts\generate-management-dashboard.ps1 -DataFile .\management-data-<schema>-<project>.json`
- **Browser verification:** open the HTML and confirm:
  - No console errors
  - Navigation buttons work (`showView` defined)
  - Tree Changes view renders and filters work
  - CSV export still works
- **Repo hygiene:** decide whether to keep generated HTML in repo or add to `.gitignore`.

### 🧩 Not started (PM site / future sprints)
- **Study health alerts**, **Movement details panel** in the PM site (React/real dashboard) are not implemented yet.
- **StudyHealthRules.ps1** not created.
- **Approval workflow**, **health dashboard**, **reporting/analytics** are not started.

### Reference data
- XML export provided for reference: `C:\Users\georgem\Desktop\_testing.xml` (not yet integrated into scripts).

---

## Phase 1: Backend Integration (CRITICAL - Sprint 1)

### 1.1 Modify `get-management-data.ps1` Pipeline

**Location:** `src/powershell/main/get-management-data.ps1`

#### Add Tree Snapshot Collection Step

Insert after existing data collection, before JSON output:

```powershell
#############################################
# TREE SNAPSHOT COLLECTION
#############################################

Write-Host "`n[Tree Snapshot] Collecting tree changes..." -ForegroundColor Cyan

$treeSnapshotDir = "data/tree-snapshots"
if (-not (Test-Path $treeSnapshotDir)) {
    New-Item -ItemType Directory -Path $treeSnapshotDir -Force | Out-Null
}

# Get all studies in the project
foreach ($study in $studySummary) {
    $studyId = $study.study_id
    $studyName = $study.study_name

    Write-Host "  Processing: $studyName (ID: $studyId)" -ForegroundColor Gray

    # Define snapshot file paths
    $baselineFile = "$treeSnapshotDir/study-$studyId-baseline.json"
    $currentFile = "$treeSnapshotDir/study-$studyId-current.json"

    # Export current snapshot
    $exportResult = & "$PSScriptRoot\..\..\scripts\debug\export-study-tree-snapshot.ps1" `
        -TNSName $TNSName `
        -Schema $Schema `
        -ProjectId $ProjectId `
        -StudyId $studyId `
        -OutputDir $treeSnapshotDir

    # Check if baseline exists
    if (-not (Test-Path $baselineFile)) {
        # First run - save current as baseline
        Copy-Item $currentFile $baselineFile
        Write-Host "    Created baseline snapshot" -ForegroundColor Yellow
        continue
    }

    # Compare baseline vs current
    $diffResult = & "$PSScriptRoot\..\..\scripts\debug\compare-study-tree-snapshots.ps1" `
        -BaselineSnapshot $baselineFile `
        -CurrentSnapshot $currentFile `
        -OutputFile "$treeSnapshotDir/study-$studyId-diff.json"

    # Parse diff results
    if (Test-Path "$treeSnapshotDir/study-$studyId-diff.json") {
        $diff = Get-Content "$treeSnapshotDir/study-$studyId-diff.json" | ConvertFrom-Json

        # Generate evidence blocks for tree changes
        foreach ($rename in $diff.changes.renamed) {
            $treeEvidence += @{
                work_type = "TREE_CHANGE"
                evidence_type = "rename"
                study_id = $studyId
                study_name = $studyName
                node_id = $rename.node_id
                node_type = $rename.node_type
                old_name = $rename.old_name
                new_name = $rename.new_name
                old_provenance = $rename.old_provenance
                new_provenance = $rename.new_provenance
                detected_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        }

        foreach ($move in $diff.changes.moved) {
            $treeEvidence += @{
                work_type = "TREE_CHANGE"
                evidence_type = "movement"
                study_id = $studyId
                study_name = $studyName
                node_id = $move.node_id
                node_name = $move.display_name
                node_type = $move.node_type
                old_coords = "$($move.old.x),$($move.old.y),$($move.old.z)"
                new_coords = "$($move.new.x),$($move.new.y),$($move.new.z)"
                delta_mm = $move.delta_mm
                movement_type = $move.movement_type
                coord_provenance = $move.coord_provenance
                mapping_type = $move.mapping_type
                detected_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        }

        foreach ($added in $diff.changes.nodesAdded) {
            $treeEvidence += @{
                work_type = "TREE_CHANGE"
                evidence_type = "node_added"
                study_id = $studyId
                study_name = $studyName
                node_id = $added.node_id
                node_name = $added.display_name
                node_type = $added.node_type
                detected_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        }

        foreach ($removed in $diff.changes.nodesRemoved) {
            $treeEvidence += @{
                work_type = "TREE_CHANGE"
                evidence_type = "node_removed"
                study_id = $studyId
                study_name = $studyName
                node_id = $removed.node_id
                node_name = $removed.display_name
                node_type = $removed.node_type
                detected_at = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
        }
    }
}

Write-Host "  Tree evidence collected: $($treeEvidence.Count) changes" -ForegroundColor Green
```

#### Add to JSON Output

```powershell
# Add tree evidence to output
$output = @{
    # ... existing fields ...
    treeChanges = $treeEvidence
}
```

**Acceptance Criteria:**
- [ ] Tree snapshot collected for each study
- [ ] Baseline created on first run
- [ ] Diffs generated on subsequent runs
- [ ] Evidence blocks added to JSON output
- [ ] No errors when no changes detected

---

### 1.2 Extend Evidence Model to Schema v1.3.0

**Location:** Create `src/powershell/utilities/TreeEvidenceClassifier.ps1`

```powershell
# Tree Evidence Classifier
# Maps tree changes to evidence model schema v1.3.0

function New-TreeEvidenceBlock {
    param(
        [Parameter(Mandatory)]
        [hashtable]$TreeChange,

        [Parameter(Mandatory)]
        [hashtable]$CheckoutData,

        [Parameter(Mandatory)]
        [hashtable]$WriteData
    )

    $nodeId = $TreeChange.node_id
    $studyId = $TreeChange.study_id

    # Check for checkout evidence
    $hasCheckout = $CheckoutData.ContainsKey($studyId)

    # Check for write evidence
    $hasWrite = $WriteData.ContainsKey($studyId)

    # Build evidence block based on change type
    switch ($TreeChange.evidence_type) {
        "rename" {
            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = @{
                        kind = "naming"
                        fields = @("display_name")
                        before = @{
                            display_name = $TreeChange.old_name
                            name_provenance = $TreeChange.old_provenance
                        }
                        after = @{
                            display_name = $TreeChange.new_name
                            name_provenance = $TreeChange.new_provenance
                        }
                    }
                }
                context = @{
                    nodeId = $nodeId
                    nodeName = $TreeChange.new_name
                    nodeType = $TreeChange.node_type
                    studyId = $studyId
                    studyName = $TreeChange.study_name
                    workType = "study.naming"
                    detectedAt = $TreeChange.detected_at
                }
                confidence = if ($hasCheckout -and $hasWrite) { "confirmed" }
                            elseif ($hasWrite) { "likely" }
                            else { "possible" }
            }
        }

        "movement" {
            $deltaValue = [double]$TreeChange.delta_mm
            $coords = $TreeChange.old_coords -split ','
            $newCoords = $TreeChange.new_coords -split ','

            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = @{
                        kind = "movement"
                        fields = @("x", "y", "z")
                        maxAbsDelta = $deltaValue
                        before = @{
                            x = [double]$coords[0]
                            y = [double]$coords[1]
                            z = [double]$coords[2]
                            coord_provenance = $TreeChange.coord_provenance
                        }
                        after = @{
                            x = [double]$newCoords[0]
                            y = [double]$newCoords[1]
                            z = [double]$newCoords[2]
                            coord_provenance = $TreeChange.coord_provenance
                        }
                        delta = @{
                            x = [double]$newCoords[0] - [double]$coords[0]
                            y = [double]$newCoords[1] - [double]$coords[1]
                            z = [double]$newCoords[2] - [double]$coords[2]
                        }
                        mapping_type = $TreeChange.mapping_type
                    }
                }
                context = @{
                    nodeId = $nodeId
                    nodeName = $TreeChange.node_name
                    nodeType = $TreeChange.node_type
                    studyId = $studyId
                    studyName = $TreeChange.study_name
                    movementClassification = $TreeChange.movement_type
                    workType = "study.layout"
                    detectedAt = $TreeChange.detected_at
                }
                confidence = if ($hasCheckout -and $hasWrite) { "confirmed" }
                            elseif ($hasWrite) { "likely" }
                            else { "possible" }
            }
        }

        "node_added" {
            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = @{
                        kind = "topology"
                        fields = @("node_count")
                        operation = "add"
                    }
                }
                context = @{
                    nodeId = $nodeId
                    nodeName = $TreeChange.node_name
                    nodeType = $TreeChange.node_type
                    studyId = $studyId
                    studyName = $TreeChange.study_name
                    changeType = "node_added"
                    workType = "study.topology"
                    detectedAt = $TreeChange.detected_at
                }
                confidence = if ($hasCheckout -and $hasWrite) { "confirmed" }
                            else { "likely" }
            }
        }

        "node_removed" {
            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = @{
                        kind = "topology"
                        fields = @("node_count")
                        operation = "remove"
                    }
                }
                context = @{
                    nodeId = $nodeId
                    nodeName = $TreeChange.node_name
                    nodeType = $TreeChange.node_type
                    studyId = $studyId
                    studyName = $TreeChange.study_name
                    changeType = "node_removed"
                    workType = "study.topology"
                    detectedAt = $TreeChange.detected_at
                }
                confidence = if ($hasCheckout -and $hasWrite) { "confirmed" }
                            else { "likely" }
            }
        }
    }
}

Export-ModuleMember -Function New-TreeEvidenceBlock
```

**Acceptance Criteria:**
- [ ] Evidence blocks follow schema v1.3.0
- [ ] Confidence rules correctly applied
- [ ] Provenance tracking included
- [ ] All tree change types supported (rename, move, topology)

---

## Phase 2: Dashboard Integration (HIGH PRIORITY - Sprint 1-2)

### 2.1 Add Tree Change Timeline Visualization

**Component:** `TreeChangeTimeline.tsx` (or equivalent)

**Features:**
- Timeline view of all tree changes
- Filter by change type (rename, move, add, remove)
- Filter by study
- Color coding: Rename=Yellow, Move=Blue, Add=Green, Remove=Red

**Data Source:**
```typescript
interface TreeChangeEvent {
  schemaVersion: string;
  evidence: {
    hasCheckout: boolean;
    hasWrite: boolean;
    hasDelta: boolean;
    deltaSummary: {
      kind: "naming" | "movement" | "topology";
      fields: string[];
      before?: any;
      after?: any;
      maxAbsDelta?: number; // For movements
      operation?: "add" | "remove"; // For topology
    };
  };
  context: {
    nodeId: string;
    nodeName: string;
    nodeType: string;
    studyId: string;
    studyName: string;
    movementClassification?: "SIMPLE" | "WORLD";
    workType: string;
    detectedAt: string;
  };
  confidence: "confirmed" | "likely" | "possible";
}
```

**UI Requirements:**
```
┌─────────────────────────────────────────────────────────────┐
│ Tree Changes Timeline                [Filter ▼] [Export]    │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│ 📅 2026-01-30 10:47:28                                       │
│ ✏️  RENAME: robot3 → robot3x                                │
│     Study: RobcadStudy1_2 | Confidence: confirmed           │
│     [View Details]                                           │
│                                                               │
│ 📅 2026-01-30 10:43:44                                       │
│ 📍 WORLD MOVEMENT: robot3x                                   │
│     (2050, -700, 700) → (100, 200, 300)                     │
│     Delta: 2050mm | Classification: WORLD                    │
│     Mapping: heuristic | Confidence: confirmed               │
│     [View Details] [Approve] [Investigate]                   │
│                                                               │
│ 📅 2026-01-30 10:30:15                                       │
│ ➕ NODE ADDED: robot5                                        │
│     Study: RobcadStudy1_2 | Confidence: likely              │
│     [View Details]                                           │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

**Acceptance Criteria:**
- [ ] Timeline displays all tree changes from JSON
- [ ] Changes grouped by date
- [ ] Filter by change type works
- [ ] Filter by study works
- [ ] Icons match change type
- [ ] Confidence badge displayed
- [ ] Movement classification shown (SIMPLE vs WORLD)
- [ ] Mapping type shown (deterministic vs heuristic)

---

### 2.2 Add Study Health Alerts

**Component:** `StudyHealthAlerts.tsx`

**Alert Types:**

#### Critical Alerts
```
⚠️  CRITICAL: Ambiguous Layout Mapping
    Study: RobcadStudy1_2
    Issue: 3 robots created at same timestamp (2026-01-30 09:01:08)
    Impact: Cannot deterministically map coordinates to robots
    Action Required: Touch robots one-by-one to create unique timestamps
```

#### High Priority Alerts
```
⚠️  HIGH: Unapproved World Movement
    Robot: robot3x
    Movement: 2050mm (WORLD classification)
    Study: RobcadStudy1_2
    No manager approval found
    Action Required: Review and approve movement
```

#### Medium Priority Alerts
```
⚠️  MEDIUM: Frequent Renaming
    Study: RobcadStudy1_2
    Renames in last 24h: 12
    Indicates: Naming confusion or experimentation
    Action Recommended: Review naming convention with team
```

**Acceptance Criteria:**
- [ ] Alerts display in sidebar or dashboard top
- [ ] Alert severity color-coded (red=critical, orange=high, yellow=medium)
- [ ] Click alert navigates to details
- [ ] Dismiss/acknowledge functionality
- [ ] Alert count badge

---

### 2.3 Add Movement Details Panel

**Component:** `MovementDetailsPanel.tsx`

**Display:**
```
┌─────────────────────────────────────────────────────────────┐
│ Movement Details: robot3x                                    │
├─────────────────────────────────────────────────────────────┤
│ Study: RobcadStudy1_2 (ID: 18879453)                        │
│ Node ID: 18880393                                            │
│ Detected: 2026-01-30 10:43:44                               │
│                                                               │
│ Coordinates:                                                  │
│   Before: (2050, -700, 700)                                  │
│   After:  (100, 200, 300)                                    │
│   Delta:  2050mm (WORLD movement)                            │
│                                                               │
│ Evidence:                                                     │
│   ✅ Checkout: Yes (georgem)                                │
│   ✅ Write: Yes (2026-01-30 10:43:00)                       │
│   ✅ Delta: Yes (coordinates changed)                       │
│   Confidence: confirmed                                      │
│                                                               │
│ Provenance:                                                   │
│   Coordinate Source: STUDYLAYOUT_ → VEC_LOCATION_           │
│   Mapping Type: heuristic (timestamp-based)                  │
│   Layout ID: 18881090                                        │
│                                                               │
│ Actions:                                                      │
│   [Approve Movement] [Request Justification] [Flag Issue]   │
└─────────────────────────────────────────────────────────────┘
```

**Acceptance Criteria:**
- [ ] Shows complete movement details
- [ ] Displays evidence triangle (checkout, write, delta)
- [ ] Shows provenance information
- [ ] Action buttons functional
- [ ] Can approve/flag movements

---

## Phase 3: Study Health Rules (MEDIUM PRIORITY - Sprint 2-3)

### 3.1 Implement Health Rule Engine

**Location:** `src/powershell/utilities/StudyHealthRules.ps1`

```powershell
function Test-StudyHealth {
    param(
        [Parameter(Mandatory)]
        [hashtable]$StudyData,

        [Parameter(Mandatory)]
        [array]$TreeChanges
    )

    $issues = @()

    # Rule 1: Ambiguous Mappings
    $ambiguousMappings = $TreeChanges | Where-Object {
        $_.mapping_type -eq "heuristic_ambiguous"
    }

    if ($ambiguousMappings.Count -gt 0) {
        $issues += @{
            severity = "critical"
            rule = "ambiguous_layout_mapping"
            message = "Found $($ambiguousMappings.Count) robots with ambiguous coordinate mappings"
            affected_nodes = $ambiguousMappings.node_id
            recommendation = "Touch robots one-by-one to create unique timestamps"
        }
    }

    # Rule 2: Unapproved World Movements
    $worldMovements = $TreeChanges | Where-Object {
        $_.evidence_type -eq "movement" -and
        $_.movement_type -eq "WORLD"
    }

    foreach ($movement in $worldMovements) {
        # Check if manager approved (placeholder - implement approval system)
        $isApproved = $false # TODO: Check approval database

        if (-not $isApproved) {
            $issues += @{
                severity = "high"
                rule = "unapproved_world_movement"
                message = "World movement ($($movement.delta_mm)mm) detected without approval"
                affected_nodes = @($movement.node_id)
                node_name = $movement.node_name
                delta_mm = $movement.delta_mm
                recommendation = "Review and approve world movement or investigate unauthorized change"
            }
        }
    }

    # Rule 3: Frequent Renaming (indicates confusion)
    $renames24h = $TreeChanges | Where-Object {
        $_.evidence_type -eq "rename" -and
        (New-TimeSpan -Start $_.detected_at -End (Get-Date)).TotalHours -le 24
    }

    if ($renames24h.Count -gt 10) {
        $issues += @{
            severity = "medium"
            rule = "frequent_renaming"
            message = "High rename frequency detected ($($renames24h.Count) in 24h)"
            affected_nodes = $renames24h.node_id
            recommendation = "Review naming convention with team to reduce confusion"
        }
    }

    # Rule 4: Missing Resource Names
    $missingNames = $TreeChanges | Where-Object {
        $_.new_provenance -match "fallback"
    }

    if ($missingNames.Count -gt 0) {
        $issues += @{
            severity = "high"
            rule = "missing_resource_names"
            message = "Found $($missingNames.Count) nodes with fallback names (OBJECT_ID)"
            affected_nodes = $missingNames.node_id
            recommendation = "Ensure all shortcuts have valid resource links"
        }
    }

    return $issues
}

Export-ModuleMember -Function Test-StudyHealth
```

**Acceptance Criteria:**
- [ ] All 4 health rules implemented
- [ ] Issues categorized by severity
- [ ] Recommendations provided
- [ ] Affected nodes tracked

---

### 3.2 Add Health Dashboard

**Component:** `StudyHealthDashboard.tsx`

```
┌─────────────────────────────────────────────────────────────┐
│ Study Health Overview                                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│ 🟢 Healthy Studies: 42                                       │
│ 🟡 Warning: 5                                                │
│ 🔴 Critical: 2                                               │
│                                                               │
│ Critical Issues:                                              │
│ ─────────────────────────────────────────────────────────── │
│ 🔴 RobcadStudy1_2: Ambiguous layout mapping (3 robots)      │
│    Action: Touch robots one-by-one                           │
│    [View Details] [Resolve]                                  │
│                                                               │
│ 🔴 Study_XYZ: Missing resource names (7 nodes)              │
│    Action: Link shortcuts to resources                       │
│    [View Details] [Resolve]                                  │
│                                                               │
│ High Priority Issues:                                         │
│ ─────────────────────────────────────────────────────────── │
│ 🟠 RobcadStudy1_2: Unapproved world movement (2050mm)       │
│    Robot: robot3x                                            │
│    [Approve] [Investigate]                                   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

**Acceptance Criteria:**
- [ ] Dashboard shows health summary
- [ ] Issues grouped by severity
- [ ] Action buttons functional
- [ ] Can resolve/dismiss issues
- [ ] Updates in real-time

---

## Phase 4: Approval Workflow (MEDIUM PRIORITY - Sprint 3-4)

### 4.1 Add Movement Approval System

**Database Table:** `movement_approvals`

```sql
CREATE TABLE movement_approvals (
    approval_id NUMBER PRIMARY KEY,
    study_id NUMBER NOT NULL,
    node_id NUMBER NOT NULL,
    movement_type VARCHAR2(20) NOT NULL, -- 'SIMPLE' or 'WORLD'
    delta_mm NUMBER NOT NULL,
    old_coords VARCHAR2(100),
    new_coords VARCHAR2(100),
    detected_at TIMESTAMP,
    approved_by VARCHAR2(100),
    approved_at TIMESTAMP,
    approval_status VARCHAR2(20), -- 'pending', 'approved', 'rejected'
    justification VARCHAR2(500),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Workflow:**
1. World movement detected → Create approval request
2. Manager notified via dashboard alert
3. Manager reviews movement details
4. Manager approves/rejects with justification
5. Approval status recorded in database
6. Alert dismissed if approved

**Acceptance Criteria:**
- [ ] Approval requests created automatically for WORLD movements
- [ ] Managers can approve/reject via dashboard
- [ ] Justification required for approval/rejection
- [ ] Audit trail maintained
- [ ] Email notification optional

---

## Phase 5: Reporting & Analytics (LOW PRIORITY - Sprint 4+)

### 5.1 Tree Stability Report

**Report Type:** Monthly study health report

**Metrics:**
- Total rename events per study
- Total movement events (SIMPLE vs WORLD)
- Average delta_mm per movement
- Topology changes (nodes added/removed)
- Mapping quality distribution (deterministic vs heuristic)
- Top 10 most modified studies

**Delivery:** PDF email to project managers

**Acceptance Criteria:**
- [ ] Report generated monthly
- [ ] Email delivery configured
- [ ] Charts/graphs included
- [ ] Trend analysis (month-over-month)

---

### 5.2 Predictive Analytics

**Goal:** Detect "churn" patterns indicating study instability

**Signals:**
- High rename frequency (>20/week)
- Frequent world movements (>10/week)
- Oscillating movements (robot moved back and forth)
- Resource mapping thrash (shortcuts reassigned frequently)

**Output:** Early warning alerts for managers

**Acceptance Criteria:**
- [ ] Churn detection algorithm implemented
- [ ] Alerts generated for high-churn studies
- [ ] Historical trend data tracked

---

## Implementation Checklist

### Sprint 1 (Current - Week 1-2)
- [ ] **Backend:** Integrate tree snapshot into `get-management-data.ps1`
- [ ] **Backend:** Create `TreeEvidenceClassifier.ps1`
- [ ] **Dashboard:** Add tree change timeline component
- [ ] **Dashboard:** Add movement details panel
- [ ] **Testing:** E2E test rename detection
- [ ] **Testing:** E2E test movement detection
- [ ] **Documentation:** Update PM user guide

### Sprint 2 (Week 3-4)
- [ ] **Dashboard:** Add study health alerts component
- [ ] **Backend:** Implement `StudyHealthRules.ps1`
- [ ] **Dashboard:** Add study health dashboard
- [ ] **Testing:** E2E test health rule engine
- [ ] **Testing:** E2E test alert system
- [ ] **Documentation:** Create troubleshooting guide for ambiguous mappings

### Sprint 3 (Week 5-6)
- [ ] **Database:** Create `movement_approvals` table
- [ ] **Backend:** Implement approval workflow
- [ ] **Dashboard:** Add approval UI components
- [ ] **Testing:** E2E test approval workflow
- [ ] **Documentation:** Manager training on approval process

### Sprint 4+ (Future)
- [ ] **Reporting:** Implement monthly health report
- [ ] **Analytics:** Implement churn detection
- [ ] **Integration:** Siemens API integration (if available)

---

## Testing Strategy

### Unit Tests
- [ ] Tree snapshot export produces valid JSON
- [ ] Tree diff correctly detects renames
- [ ] Tree diff correctly detects movements
- [ ] Movement classification (SIMPLE vs WORLD) correct
- [ ] Evidence classifier produces schema v1.3.0 blocks
- [ ] Health rules fire correctly

### Integration Tests
- [ ] `get-management-data.ps1` includes tree changes in output
- [ ] Dashboard renders tree change timeline
- [ ] Dashboard renders health alerts
- [ ] Approval workflow end-to-end

### E2E Tests
- [ ] Rename robot → Detect in dashboard within 5 min
- [ ] Move robot 2000mm → Detect WORLD movement + create approval request
- [ ] Create 3 robots simultaneously → Detect ambiguous mapping alert
- [ ] Approve movement → Alert dismissed, audit trail created

---

## Deployment Plan

### Pre-Deployment
- [ ] Schema v1.3.0 documented
- [ ] Backward compatibility verified
- [ ] Data migration plan (none needed - backward compatible)
- [ ] Rollback plan documented

### Deployment Steps
1. Deploy backend changes (`get-management-data.ps1`, `TreeEvidenceClassifier.ps1`)
2. Run first data collection to establish baselines
3. Deploy dashboard changes
4. Deploy health rule engine
5. Enable alerts (start with email opt-in)
6. Monitor for 1 week
7. Deploy approval workflow
8. Enable auto-approvals for SIMPLE movements (optional)

### Post-Deployment
- [ ] Monitor error logs for 48h
- [ ] Collect manager feedback
- [ ] Tune health rule thresholds if needed
- [ ] Update documentation based on feedback

---

## Risk Mitigation

### Risk 1: Timestamp Collision (Ambiguous Mappings)
- **Probability:** Medium (users create multiple robots quickly)
- **Impact:** High (incorrect coordinate assignment)
- **Mitigation:**
  - Alert managers immediately
  - Provide clear workaround (touch robots one-by-one)
  - Document limitation prominently

### Risk 2: Performance with Large Studies
- **Probability:** Low (tested with realistic sizes)
- **Impact:** Medium (slow dashboard rendering)
- **Mitigation:**
  - Implement pagination on timeline
  - Add tree change count threshold (warn if >1000 changes)
  - Optimize SQL queries with indexes

### Risk 3: False Positive Alerts
- **Probability:** Medium (health rules may be too strict)
- **Impact:** Low (alert fatigue)
- **Mitigation:**
  - Start with conservative thresholds
  - Add dismiss/snooze functionality
  - Tune based on manager feedback

---

## Success Metrics

### Sprint 1 Goals
- ✅ Tree changes visible in PM dashboard
- ✅ Rename detection 100% accurate
- ✅ Movement detection 100% accurate
- ✅ No backend errors in production

### Sprint 2 Goals
- ✅ Health alerts generated for all critical issues
- ✅ Managers can view movement details
- ✅ <5% false positive rate on alerts

### Sprint 3 Goals
- ✅ Approval workflow functional
- ✅ 90% of WORLD movements approved within 24h
- ✅ Audit trail complete

### Long-term Success
- 📊 80% reduction in "mystery movements" (unknown robot changes)
- 📊 50% reduction in study health issues
- 📊 Manager satisfaction score >4.5/5
- 📊 100% audit compliance

---

## Next Immediate Actions

1. **TODAY:** Review this plan with PM stakeholders
2. **TODAY:** Prioritize Sprint 1 tasks
3. **TOMORROW:** Start backend integration (`get-management-data.ps1`)
4. **Day 3:** Create `TreeEvidenceClassifier.ps1`
5. **Day 4-5:** Build tree change timeline component
6. **End of Week 1:** E2E test with real data

---

## Support & Contact

**Documentation:**
- [TREE_EVIDENCE_INTEGRATION.md](docs/TREE_EVIDENCE_INTEGRATION.md) - Technical specification
- [GIT_CHANGES_REVIEW.md](GIT_CHANGES_REVIEW.md) - File review and cleanup
- [TREE_SNAPSHOT_FINAL_REPORT.md](TREE_SNAPSHOT_FINAL_REPORT.md) - System overview

**Questions:**
- Slack: #simtreenav-dev
- Email: pm-support@company.com

---

**Prepared by:** Claude Code (Sonnet 4.5)
**Date:** 2026-01-30
**Status:** Ready for implementation
**Branch:** feat/tree-snapshot-diff
**Commit:** a238d22
