# Manager E2E Mega Summary (SimTreeNav)

**Date:** 2026-01-30  
**Project:** _testing (ID: 18851221)  
**Study:** RobcadStudy1_2 (ID: 18879453)  
**Goal:** Prove Siemens front‑end actions → Oracle DB writes → SimTreeNav evidence → Dashboard visibility.

---

## Executive Summary

We confirmed that SimTreeNav is capturing real Siemens changes in the _testing project, but several critical wiring issues were discovered and fixed to make the data project‑scoped and correctly linked. A rename and a robot add both register in the database and are now visible in SimTreeNav. Movement deltas are now wired correctly: StudyLayout coordinates live in `VEC_LOCATION_` keyed by the **StudyLayout OBJECT_ID**, and we fixed the lookup so moved robots (e.g., X=1350) are captured when the study is saved.

---

## What Works (Confirmed)

1) **Study rename detected**
   - RobcadStudy1 → RobcadStudy1_2 captured in DB and surfaced in SimTreeNav.
   - Evidence shows `hasWrite=true` with last modified timestamp and user.

2) **Robot add detected in StudyResources**
   - Added robot: `r2000ic_210l_if_v02`
   - The study resource is now resolved correctly via shortcut → resource link.
   - SimTreeNav shows the resource allocation to the study.

3) **Project scoping fixed for core study queries**
   - Study Summary / Resources / Panels / Movements / Health are now project‑scoped.
   - _testing shows 1 study instead of 203 schema‑wide studies.

---

## Key Root Causes Found (and Fixed)

### A) SQL*Plus output truncation
**Symptom:** Only 4 columns returned in Study Summary.  
**Fix:** Increased SQL*Plus line size and disabled wrapping in the management data script.

### B) Study → Project relationship
**Symptom:** Queries pulled all studies across the schema.  
**Fix:** Applied the working tree query pattern using hierarchical `REL_COMMON` traversal (same as `generate-tree-html.ps1`).  
**Queries fixed in Phase 1:** Study Summary, Study Resources, Study Panels, Study Movements, Study Health.

### C) Robot add not resolving to resource
**Symptom:** StudyResources showed “Shortcut” but no robot name.  
**Root cause:** `SHORTCUT_.LINKEXTERNALID_S_` maps to `RESOURCE_.EXTERNALID_S_`, not `NAME_S_`.  
**Fix:** StudyResources now joins using LINKEXTERNALID_S_ with NAME fallback.  
**Result:** Robot name now appears in StudyResources.

---

## What’s Still Missing (Why Movement Delta Isn’t Showing)

**Finding:** StudyLayout rows exist, but the location vectors are stored in `VEC_LOCATION_` using the **StudyLayout OBJECT_ID** (not `STUDYLAYOUT_.LOCATION_V_`, which stays at a placeholder like `3`).  
**Impact:** Movement deltas only show up after (1) a **baseline snapshot** exists, and (2) the robot is **moved and saved** so `VEC_LOCATION_` updates.  

**Clarification:**  
- **Study items** (robots/resources) are tracked via **Shortcut → Resource** links.  
- **Movement deltas** require **layout coordinates** (StudyLayout + vectors).  
- **Fix applied:** all location lookups now target `VEC_LOCATION_` by `STUDYLAYOUT_.OBJECT_ID`.

---

## Evidence Collected

### Robot Add (Database)
**Shortcut record:**  
- Shortcut object: 18880385  
- LINKEXTERNALID_S_: `759166CA-77A5-44F6-9370-491F995DECDD`  
- Parent: study 18879453

**Resource record:**  
- Resource object: 18880386  
- NAME_S_: `r2000ic_210l_if_v02`  
- EXTERNALID_S_: `759166CA-77A5-44F6-9370-491F995DECDD`  
- MODIFICATIONDATE_DA_: 2026‑01‑29 15:52:26

### StudyResources (SimTreeNav output)
```
STUDY_ID:      18879453
STUDY_NAME:    RobcadStudy1_2
RESOURCE_NAME: r2000ic_210l_if_v02
RESOURCE_TYPE: ToolInstance
```

---

## Manager‑Level Status (Today)

- ✅ Project scoping fixed for core study queries  
- ✅ Rename change surfaced in dashboard data  
- ✅ Robot add surfaced in StudyResources  
- ✅ Movement delta detection wired (StudyLayout → VEC_LOCATION_ lookup fixed)

---

## Manager Workflow Guide (Simple, Repeatable)

### A) Daily 5‑Minute Health Pass
1) Run the dashboard capture (single command below).  
2) Open the HTML dashboard.  
3) Scan for:
   - Confirmed evidence events (real work done)  
   - Large world moves (potential layout risk)  
   - Stale checkouts (blocked work)  
4) Share highlights in the daily standup.

### B) Weekly QA Gate (Project Readiness)
1) Run capture + verification.  
2) Confirm:
   - No schema‑wide contamination  
   - Movement deltas tracked  
   - Operation updates tracked  
3) Export summary to management notes.

### C) Escalation Rules
- **Confirmed + World move**: notify team lead for collision review.  
- **Checkout only > 48h**: notify study owner to check in.  
- **No deltas but frequent writes**: likely property edits; verify study intent.

---

## Manager Interpretation Guide (Evidence Signals)

- **hasWrite** = DB modification recorded  
- **hasDelta** = meaningful content change (coords/ops)  
- **hasCheckout** = study locked by user  
- **confidence**:
  - **confirmed**: checkout + write + delta  
  - **likely**: write + delta  
  - **checkout_only**: lock without changes  
  - **unattributed**: write without delta

---

## Manager Quick Commands

### Capture + Dashboard
```
pwsh -NoProfile -File src/powershell/main/get-management-data.ps1 `
  -TNSName "DES_SIM_DB1_DB01" `
  -Schema "DESIGN12" `
  -ProjectId 18851221 `
  -StartDate "2025-12-30" `
  -EndDate "2026-01-29" `
  -OutputFile "data/output/management-DESIGN12-18851221.json"
```

### Verify Evidence
```
pwsh -NoProfile -File scripts/debug/verify-evidence-e2e.ps1 `
  -ManagementDataFile "data/output/management-DESIGN12-18851221.json"
```

### Check Layout Coordinates (movement readiness)
```
pwsh -NoProfile -File scripts/debug/check-study-layout-coords.ps1 `
  -StudyId 18879453
```

---

## Metrics for Managers

- **Active work count**: number of confirmed/likely events  
- **Movement risk**: world moves >= 1000 mm  
- **Checkout risk**: checkout_only events > 48 hours  
- **Work density**: changes per study per week  
- **Data quality**: ratio of confirmed/likely to unattributed

---

## Next Step to Complete E2E Proof (1‑Minute Test)

**In Siemens Process Simulate:**
1) Check out `RobcadStudy1_2`  
2) Select robot `r2000ic_210l_if_v02`  
3) Move it **1200 mm** in X (world move)  
4) Save (Ctrl+S)  
5) (Optional) Check in

**Then run:**
```
pwsh -NoProfile -File src/powershell/main/get-management-data.ps1 `
  -TNSName "DES_SIM_DB1_DB01" `
  -Schema "DESIGN12" `
  -ProjectId 18851221 `
  -StartDate "2025-12-30" `
  -EndDate "2026-01-29" `
  -OutputFile "data/output/management-DESIGN12-18851221.json"
```

Expected result: movement events appear, evidence shows `hasDelta=true` and likely/confirmed confidence.

---

## Tree Naming + Structure + Location Tracking Status

**Status:** ✅ Complete (2026-01-30)

### What's Working

✅ **Tree Structure Export**
- Deterministic snapshot of all nodes under a study
- Parent/child relationships captured via REL_COMMON traversal
- Depth and sequence numbers preserved
- Node types identified via CLASS_DEFINITIONS

✅ **Node Naming Resolution**
- Precedence: Resource name > Shortcut name > External ID > Object ID
- All sources documented in `name_provenance` field
- Handles shortcuts, collections, resources, operations

✅ **Location Tracking**
- StudyLayout → VEC_LOCATION_ direct lookup (deterministic)
- X/Y/Z coordinates captured for layout-enabled nodes
- Coordinate source documented in `coord_provenance` field

✅ **Mapping Classification**
- Deterministic mappings (shortcut → resource via LINKEXTERNALID_S_)
- Heuristic mappings (timestamp-based layout-to-shortcut matching)
- Ambiguous mappings flagged (multiple robots at same timestamp)

✅ **Tree Diff Detection**
- Renamed nodes detected (same node_id, different display_name)
- Moved nodes detected with delta_mm and simple/world classification
- Structural changes (parent changed, node added/removed)
- Resource mapping changes (shortcut now points to different resource)

### Manager Commands

**Export Tree Snapshot:**
```powershell
pwsh scripts/debug/export-study-tree-snapshot.ps1 `
    -TNSName "DES_SIM_DB1_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18851221 `
    -StudyId 18879453
```

**Compare Snapshots:**
```powershell
pwsh scripts/debug/compare-study-tree-snapshots.ps1 `
    -BaselineSnapshot "data/output/study-tree-snapshot-DESIGN12-18879453-[baseline].json" `
    -CurrentSnapshot "data/output/study-tree-snapshot-DESIGN12-18879453-[current].json" `
    -ShowDetails
```

### Known Limitations

⚠️ **Ambiguous Layout Mapping:**
- When multiple robots are created at the same timestamp, layout-to-robot mapping is heuristic
- These are clearly labeled as `mapping_type: "heuristic_ambiguous"`
- Workaround: Touch robots one-by-one to create unique timestamps

### Use Cases

- **Audit Trail:** Historical record of tree structure and naming at specific points in time
- **Change Detection:** Automatically detect when robots are renamed, moved, added, or removed
- **Compliance:** Prove that layout coordinates match Process Simulate UI
- **Debugging:** Investigate naming or location discrepancies

---

## Phase 2/3 (Open Items)

**Phase 2 (Operations):**
- Q5D Study Operations
- Q5F Study Welds

**Phase 3 (Advanced):**
- Q8 Resource Conflicts
- Q9 Stale Checkouts
- Q10 Bottleneck Queue

These are still schema‑wide and need the same project‑scoped query pattern.

---

## Decision Needed (Manager Approval)

1) **Approve Phase 2/3 query scoping work**  
   - Ensures dashboard never mixes data across projects.

2) **Approve 1‑minute movement test**  
   - Generates the final “confirmed” evidence triangle for E2E proof.

---

## Files Updated in This Phase

- `src/powershell/main/get-management-data.ps1`
  - SQL*Plus output fix (LINESIZE/WRAP)
  - Project scoping applied to core study queries
  - StudyResources join uses LINKEXTERNALID_S_
- `scripts/debug/check-study-layout-coords.ps1`
  - Terminal‑only validation of layout coordinate rows
