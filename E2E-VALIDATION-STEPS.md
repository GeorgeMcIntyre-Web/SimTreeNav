# E2E Validation Workflow - _testing Project

**Date:** 2026-01-29
**Project:** _testing (ID: 18851221)
**Study:** RobcadStudy1 (ID: 18879453)
**Baseline Captured:** ✓ Complete

---

## Current Status

✅ **Baseline Run Complete:**
- File: `data/output/management-DESIGN12-18851221.json` (1.36 MB)
- Studies found: 7 (including RobcadStudy1)
- Snapshot saved for diff comparison

✅ **Phase 1 Fixes Applied:**
- Project filtering working correctly
- Dashboard shows only _testing project data

---

## Next: Perform Siemens Actions

### Step 1: Open RobcadStudy1 in Siemens Process Simulate

1. Launch Siemens Process Simulate
2. Navigate to: **_testing > Studies > StudyFolder > RobcadStudy1**
3. Double-click to open RobcadStudy1

### Step 2: Execute the 5-Step Action Sequence

**Action A: Checkout**
- Right-click RobcadStudy1 → **Check Out**
- Confirm checkout completes
- ✅ Evidence: `hasCheckout = true` (PROXY.WORKING_VERSION_ID > 0)

**Action B: Simple Move (50mm)**
- Select any robot or part in the study
- Move it **50mm** in X, Y, or Z direction
- Save the study (Ctrl+S)
- ✅ Evidence: `hasDelta = true`, movement classified as "simple" (<1000mm)

**Action C: World Move (1200mm)**
- Select the same or different object
- Move it **1200mm** in any direction
- Save the study (Ctrl+S)
- ✅ Evidence: `hasDelta = true`, movement classified as "world" (≥1000mm)

**Action D: Operation Edit**
- Open/create an operation in the study
- Make ANY change (rename, modify parameters, add/remove weld point, etc.)
- Save the study (Ctrl+S)
- ✅ Evidence: `hasWrite = true` (MODIFICATIONDATE_DA_ changed)

**Action E: Check In**
- Right-click RobcadStudy1 → **Check In**
- Add comment: "E2E validation test - 2026-01-29"
- Confirm check-in completes
- ✅ Evidence: Full evidence triangle complete

---

## Step 3: Capture "After" Snapshot

**Once you've completed all 5 Siemens actions**, run:

```powershell
pwsh .\management-dashboard-launcher.ps1 `
    -TNSName "DES_SIM_DB1_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18851221 `
    -DaysBack 30 `
    -AutoLaunch:$false
```

**Expected Results:**
- Same 7 studies found (project filtering working)
- RobcadStudy1 shows evidence blocks with:
  - `hasCheckout: true` (or was true before check-in)
  - `hasWrite: true` (MODIFICATIONDATE_DA_ changed)
  - `hasDelta: true` (coordinates or operations changed)
  - `confidence: "confirmed"` (full evidence triangle)
  - `attributionStrength: "strong"` (your username matches)

---

## Step 4: Run Verification Script

```powershell
pwsh .\scripts\debug\verify-evidence-e2e.ps1 `
    -ManagementDataFile "data\output\management-DESIGN12-18851221.json"
```

**This validates:**
- ✅ All events have evidence blocks
- ✅ Confirmed events have full triangle (checkout + write + delta)
- ✅ Movement classifications are correct (simple vs world)
- ✅ Snapshot integrity maintained
- ✅ No confidence downgrades

---

## Step 5: Review Dashboard

Open the dashboard HTML file:
```
data\output\management-dashboard-DESIGN12-18851221.html
```

**Check:**
- Evidence badges show "CONFIRMED" for RobcadStudy1 events
- Movement events classified correctly (simple/world)
- Operation changes detected
- Your username appears as the modifier
- No cross-project contamination (only _testing project data)

---

## Expected Evidence Triangle

For RobcadStudy1 after all 5 actions:

```json
{
  "hasCheckout": true,
  "hasWrite": true,
  "hasDelta": true,
  "confidence": "confirmed",
  "attributionStrength": "strong",
  "checkoutOwner": "<your_username>",
  "lastModifiedBy": "<your_username>",
  "changes": ["coordinates", "operations"]
}
```

---

## Troubleshooting

**If evidence is missing:**
- Check that you saved after each action (Ctrl+S)
- Verify check-in completed (no errors)
- Ensure you're modifying RobcadStudy1, not a different study

**If confidence is not "confirmed":**
- Verify all 3 evidence signals present (checkout, write, delta)
- Check attribution matches (PROXY.OWNER_ID = LASTMODIFIEDBY)

**If movements not detected:**
- Ensure you moved the object far enough (50mm minimum for simple, 1200mm for world)
- Check that coordinates actually changed in STUDYLAYOUT_ table

---

## Success Criteria

✅ Phase 1 fixes working (project filtering correct)
✅ Baseline captured successfully
✅ 5 Siemens actions completed in sequence
✅ "After" run captures all evidence
✅ Verification script passes all checks
✅ Dashboard shows confirmed evidence with correct classifications

**Ready to proceed with Siemens actions!**
