# E2E Validation Pack: Siemens Front-End → Oracle → SimTreeNav Evidence

**Purpose:** Prove that normal Siemens Process Simulate work (checkout, move, operation edits) produces correct evidence and confidence in SimTreeNav.

**Environment:**
- Server: `db01`
- Schema: `DESIGN12`
- Project: `_testing`
- Study: *(determined in Part 1)*

---

## Prerequisites

1. Database access to `db01` with `DESIGN12` schema
2. Siemens Process Simulate installed and configured
3. SimTreeNav repository cloned and PowerShell 7+ installed
4. Credentials configured (see [CREDENTIAL-SETUP-GUIDE.md](CREDENTIAL-SETUP-GUIDE.md))

---

## Part 1: Identify the Study to Use

Run the study discovery script to find available studies in the `_testing` project:

```powershell
pwsh scripts/debug/query-testing-project-studies.ps1 -TNSName "SIEMENS_PS_DB_DB01"
```

**Expected output:**
- List of studies in `_testing` project
- Study IDs, names, types, checkout status
- Recommendation for first available (unchecked-out) study

**Action:** Note the recommended study name and ID. Example:
- Study Name: `E2E_TEST_STUDY_001`
- Study ID: `18195400`

**What to look for:**
- At least one study with "Checkout Status: Available"
- Study should have layout objects or operations that can be modified

---

## Part 2: Siemens Front-End Action Script

These are the actions YOU will perform manually in Siemens Process Simulate to generate real database changes. SimTreeNav will detect these changes and classify them with evidence.

### Action Checklist

#### A. Checkout Evidence
**Goal:** Prove that checkout creates `PROXY.WORKING_VERSION_ID > 0`

1. Open Siemens Process Simulate
2. Navigate to the `_testing` project
3. Open the study identified in Part 1 (e.g., `E2E_TEST_STUDY_001`)
4. **Checkout the study** (right-click study → Check Out)
5. **DO NOT SAVE YET** - this creates checkout evidence without write evidence

**Expected DB change:**
- `PROXY.WORKING_VERSION_ID` becomes > 0
- SimTreeNav should detect `hasCheckout = true`

---

#### B. Simple Move (Minor Movement)
**Goal:** Prove that a small move creates write + delta evidence

1. In the open study, locate a robot or station in the layout view
2. **Move the object by a small amount** (e.g., 50mm in X-axis)
   - Use the transform tool or enter coordinates manually
   - Example: Move from `x=5000` to `x=5050` (50mm delta)
3. **Save the study** (File → Save or Ctrl+S)
4. **DO NOT check in yet**

**Expected DB changes:**
- `STUDYLAYOUT_.MODIFICATIONDATE_DA_` changes
- `VEC_LOCATION_` values change (small delta ~50mm)
- SimTreeNav should detect:
  - `hasCheckout = true`
  - `hasWrite = true`
  - `hasDelta = true` with `maxAbsDelta = 50`
  - `confidence = "confirmed"`

---

#### C. World Move (Major Movement)
**Goal:** Prove that a large move creates a "world location change" delta

1. In the same study, **move the same object OR a different object by a large amount** (e.g., 1200mm in X-axis)
   - Use the transform tool or enter coordinates manually
   - Example: Move from `x=5000` to `x=6200` (1200mm delta)
2. **Save the study**
3. **DO NOT check in yet**

**Expected DB changes:**
- `STUDYLAYOUT_.MODIFICATIONDATE_DA_` changes again
- `VEC_LOCATION_` values change (large delta >=1000mm)
- SimTreeNav should detect:
  - `hasCheckout = true`
  - `hasWrite = true`
  - `hasDelta = true` with `maxAbsDelta >= 1000`
  - `confidence = "confirmed"`
  - Movement type: "WORLD" (vs "SIMPLE")

---

#### D. Operation Evidence (Choose ONE)

**Option 1: Modify an existing operation**
1. Locate an existing operation in the study (e.g., a weld group or movement operation)
2. **Modify the operation** (change name, time, or parameters)
3. **Save the study**

**Option 2: Create a new operation**
1. Create a new operation group or operation item
2. Add 1-2 items to it
3. **Save the study**

**Expected DB changes:**
- `OPERATION_.MODIFICATIONDATE_DA_` changes
- SimTreeNav should detect:
  - `hasCheckout = true`
  - `hasWrite = true`
  - `hasDelta = true` (if operation counts changed)
  - `confidence = "confirmed"`

---

#### E. Check In (Final Step)
**Goal:** Prove that check-in releases the PROXY lock

1. **Check in the study** (right-click study → Check In)
2. Close the study

**Expected DB changes:**
- `PROXY.WORKING_VERSION_ID` resets to 0
- SimTreeNav next run will NOT show checkout evidence for this study

---

### Action Summary Table

| Step | Action | Expected Evidence | Confidence |
|------|--------|-------------------|------------|
| A | Checkout only | `hasCheckout=true, hasWrite=false, hasDelta=false` | `checkout_only` |
| B | Simple move (50mm) + save | `hasCheckout=true, hasWrite=true, hasDelta=true, maxAbsDelta=50` | `confirmed` |
| C | World move (1200mm) + save | `hasCheckout=true, hasWrite=true, hasDelta=true, maxAbsDelta>=1000` | `confirmed` |
| D | Operation edit + save | `hasCheckout=true, hasWrite=true, hasDelta=true` | `confirmed` |
| E | Check in | `hasCheckout=false` (next run) | N/A |

---

## Part 3: Pre/Post SimTreeNav Runs

### Baseline Run (BEFORE Siemens Actions)

Run SimTreeNav to capture the current state BEFORE you do any Siemens work:

```powershell
# Clear cache to force fresh data
Remove-Item data\output\management-snapshot-DESIGN12-*.json -ErrorAction SilentlyContinue

# Run baseline
pwsh .\management-dashboard-launcher.ps1 `
    -TNSName "SIEMENS_PS_DB_DB01" `
    -Schema "DESIGN12" `
    -ProjectId YOUR_PROJECT_ID `
    -DaysBack 30 `
    -AutoLaunch:$false
```

**Replace `YOUR_PROJECT_ID` with the project ID from Part 1.**

**Expected output:**
- `data\output\management-DESIGN12-YOUR_PROJECT_ID.json`
- `data\output\management-snapshot-DESIGN12-YOUR_PROJECT_ID.json`
- `data\output\management-dashboard-DESIGN12-YOUR_PROJECT_ID.html`

**What to check:**
- Baseline data file should exist
- Baseline snapshot file should exist
- Note the count of events (should be low or zero if _testing is unused)

---

### DO THE SIEMENS ACTIONS NOW

**ACTION REQUIRED:** Perform the Siemens UI actions described in Part 2 (Checkout → Simple Move → World Move → Operation Edit → Check In).

Take your time. Ensure each step is saved before proceeding to the next.

---

### After Run (AFTER Siemens Actions)

Run SimTreeNav again to capture the changes:

```powershell
# Run after
pwsh .\management-dashboard-launcher.ps1 `
    -TNSName "SIEMENS_PS_DB_DB01" `
    -Schema "DESIGN12" `
    -ProjectId YOUR_PROJECT_ID `
    -DaysBack 30 `
    -AutoLaunch:$false
```

**Expected output:**
- Updated `data\output\management-DESIGN12-YOUR_PROJECT_ID.json`
- Updated `data\output\management-snapshot-DESIGN12-YOUR_PROJECT_ID.json`
- Updated `data\output\management-dashboard-DESIGN12-YOUR_PROJECT_ID.html`

**What to check:**
- New events should appear corresponding to your Siemens actions
- Snapshot should show changed records
- Dashboard should display evidence and confidence

---

## Part 4: Automated Verification Checks

Run the verification script to validate evidence integrity:

```powershell
pwsh scripts\debug\verify-evidence-e2e.ps1 `
    -ManagementDataFile "data\output\management-DESIGN12-YOUR_PROJECT_ID.json"
```

**This script checks:**

1. **Evidence exists on all events**
   - Every event has an `.evidence` block
   - `.evidence.confidence` is one of: `confirmed`, `likely`, `checkout_only`, `unattributed`

2. **Confirmed implies triangle**
   - For any event where `confidence == "confirmed"`:
     - `hasCheckout == true`
     - `hasWrite == true`
     - `hasDelta == true`

3. **Delta summaries prove the movements**
   - Finds events with `deltaSummary.kind == "movement"`
   - Prints `maxAbsDelta` for simple and world moves
   - Example output:
     ```
     Simple movements (< 1000mm): 1
     World movements (>= 1000mm): 1

     World movement details:
       [2026-01-29T14:32:00] John Smith: Layout moved (dx=1200, dy=0, dz=0)
         Max delta: 1200mm, Confidence: confirmed
         Before: x=5000, y=3200, z=1500
         After:  x=6200, y=3200, z=1500
     ```

4. **Checkout-only behavior (if reproduced)**
   - Identifies events where `hasCheckout=true` but `hasWrite=false` and `hasDelta=false`
   - This occurs if you checkout but don't save (Step A above)

5. **Snapshot integrity**
   - Snapshot file exists and is referenced
   - Snapshot records have stable hashes
   - New snapshot differs from baseline

6. **Confidence distribution**
   - Counts events by confidence level
   - Example output:
     ```
     Confirmed:      4
     Likely:         0
     Checkout Only:  1
     Unattributed:   0
     ```

**Expected exit code:** 0 (pass) if all checks succeed, 1 (fail) otherwise.

---

## Part 5: Human-Readable Change Explanation

After running the verification script, generate a proof pack markdown report:

```powershell
# Create docs directory if needed
if (-not (Test-Path "docs\e2e-proofs")) {
    New-Item -ItemType Directory -Path "docs\e2e-proofs" -Force
}

# Copy template and populate with results
Copy-Item "docs\E2E_TEST_PROOF_TEMPLATE.md" "docs\e2e-proofs\E2E_PROOF_$(Get-Date -Format 'yyyy-MM-dd').md"
```

**Edit the generated file** to fill in:
- Environment details (server, schema, project, study)
- What you changed in Siemens UI (bulleted list)
- What DB evidence corresponds (checkout, mod-date, delta, operation)
- What SimTreeNav shows (event list with timestamps and confidence labels)
- "What this proves" section for management
- "How to repeat" section

**See template:** [E2E_TEST_PROOF_TEMPLATE.md](E2E_TEST_PROOF_TEMPLATE.md)

---

## Part 6: Review Dashboard

Open the generated dashboard in your browser:

```powershell
Start-Process "data\output\management-dashboard-DESIGN12-YOUR_PROJECT_ID.html"
```

**What to verify:**

1. **Timeline view** shows your events with timestamps
2. **Confidence badges** are displayed (Confirmed, Likely, Checkout Only, Unattributed)
3. **Evidence details** expand to show:
   - Checkout status
   - Write sources (e.g., `STUDYLAYOUT_.MODIFICATIONDATE_DA_`)
   - Delta summary (coordinates before/after, max delta)
   - Attribution strength
4. **Filters work:**
   - Filter by confidence level
   - Filter by workflow phase
   - Filter by user
5. **Movement events** clearly show:
   - Simple move (< 1000mm) in green or blue
   - World move (>= 1000mm) in orange or highlighted
6. **Allocation state filter** (if IPA events present)

---

## Troubleshooting

### Issue: No events found after Siemens actions

**Possible causes:**
- Actions were not saved in Siemens
- Wrong study was modified
- Date range too narrow (increase `-DaysBack`)
- Cache not cleared (delete snapshot file and re-run)

**Solution:**
1. Verify you saved in Siemens after each action
2. Check that the study ID matches the one you modified
3. Delete snapshot file: `Remove-Item data\output\management-snapshot-DESIGN12-*.json`
4. Re-run with `-DaysBack 60`

---

### Issue: Events exist but have confidence="unattributed"

**Possible causes:**
- Study was not checked out (missing PROXY evidence)
- Modification happened outside the query time window
- User attribution is missing or mismatched

**Solution:**
1. Ensure you checked out the study in Siemens BEFORE making changes
2. Verify PROXY.WORKING_VERSION_ID > 0 while editing
3. Check that the user in Siemens matches the DB user

---

### Issue: Snapshot file exists but delta is not detected

**Possible causes:**
- Coordinate change was below epsilon threshold (1mm)
- Snapshot comparison failed due to object ID mismatch
- Previous snapshot was from a different run and doesn't have the object

**Solution:**
1. Ensure coordinate changes are significant (>10mm for simple, >1000mm for world)
2. Delete previous snapshot and run baseline again
3. Check snapshot JSON manually to verify object IDs match

---

### Issue: Verification script fails with "triangle violation"

**Possible causes:**
- Event was marked `confirmed` but missing one of: checkout, write, or delta
- Attribution strength is "weak" (should prevent `confirmed`)

**Solution:**
This is a code defect. Report it with:
- The event description
- The evidence block JSON
- Steps to reproduce

---

## Expected Results Summary

After completing this E2E test, you should have:

1. **Baseline data** (before Siemens actions)
2. **After data** (after Siemens actions) with 4-5 new events:
   - 1 checkout-only event (if step A was captured separately)
   - 1 simple move event (confidence=confirmed, maxAbsDelta=50)
   - 1 world move event (confidence=confirmed, maxAbsDelta>=1000)
   - 1 operation event (confidence=confirmed)
3. **Verification report** showing:
   - All events have evidence
   - All confirmed events have complete triangle
   - Movement deltas are correctly categorized
   - Confidence distribution is reasonable
4. **Dashboard HTML** showing:
   - Timeline with your events
   - Confidence badges
   - Evidence details (expandable)
   - Filters working
5. **Proof pack markdown** (human-readable summary for management)

---

## Next Steps

- **Share results** with team or management using the generated proof pack markdown
- **Run regular E2E tests** (weekly or before releases) to ensure evidence quality
- **Extend test cases** to cover more scenarios (e.g., library edits, IPA allocation changes)
- **Automate** this process with a scheduled task if desired

---

## References

- [WORK_ASSOCIATION.md](WORK_ASSOCIATION.md) - Evidence taxonomy and confidence rules
- [PHASE2_DASHBOARD_SPEC.md](PHASE2_DASHBOARD_SPEC.md) - Dashboard specification
- [EvidenceClassifier.ps1](../scripts/lib/EvidenceClassifier.ps1) - Evidence classifier library
- [SnapshotManager.ps1](../scripts/lib/SnapshotManager.ps1) - Snapshot diff logic
