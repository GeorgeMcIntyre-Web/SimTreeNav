# E2E Test Quick Reference

**Quick copy/paste commands for running E2E evidence validation.**

---

## Step 1: Find Available Study

```powershell
pwsh scripts/debug/query-testing-project-studies.ps1 -TNSName "SIEMENS_PS_DB_DB01"
```

**Note the study name and ID from output.**

---

## Step 2: Run Baseline (BEFORE Siemens Actions)

Replace `PROJECT_ID` with the ID from Step 1.

```powershell
# Clear cache
Remove-Item data\output\management-snapshot-DESIGN12-*.json -ErrorAction SilentlyContinue

# Run baseline
pwsh .\management-dashboard-launcher.ps1 `
    -TNSName "SIEMENS_PS_DB_DB01" `
    -Schema "DESIGN12" `
    -ProjectId PROJECT_ID `
    -DaysBack 30 `
    -AutoLaunch:$false
```

**Outputs:**
- `data\output\management-DESIGN12-PROJECT_ID.json`
- `data\output\management-snapshot-DESIGN12-PROJECT_ID.json`

---

## Step 3: Do Siemens Actions

1. **Checkout** the study
2. **Simple move:** Move object by 50mm, save
3. **World move:** Move object by 1200mm, save
4. **Operation edit:** Modify or create operation, save
5. **Check in** the study

---

## Step 4: Run After (AFTER Siemens Actions)

```powershell
pwsh .\management-dashboard-launcher.ps1 `
    -TNSName "SIEMENS_PS_DB_DB01" `
    -Schema "DESIGN12" `
    -ProjectId PROJECT_ID `
    -DaysBack 30 `
    -AutoLaunch:$false
```

---

## Step 5: Verify Evidence

```powershell
pwsh scripts\debug\verify-evidence-e2e.ps1 `
    -ManagementDataFile "data\output\management-DESIGN12-PROJECT_ID.json"
```

**Expected:** Exit code 0, all checks pass.

---

## Step 6: Review Dashboard

```powershell
Start-Process "data\output\management-dashboard-DESIGN12-PROJECT_ID.html"
```

**Check:**
- Timeline shows your events
- Confidence badges are correct
- Evidence details expand correctly
- Filters work

---

## What Should You See?

### Baseline Run
- Few or zero events (if _testing is unused)
- Snapshot file created
- Dashboard shows empty or minimal activity

### After Run
- 3-5 new events corresponding to your Siemens actions:
  - Simple move: `confidence=confirmed, maxAbsDelta=50`
  - World move: `confidence=confirmed, maxAbsDelta>=1000`
  - Operation: `confidence=confirmed`
  - (Optional) Checkout-only: `confidence=checkout_only`

### Verification Output
```
[1/6] Checking evidence blocks exist on all events...
  ✓ Events with evidence: 4 / 4

[2/6] Verifying evidence triangle for 'confirmed' events...
  ✓ All confirmed events have complete evidence triangle

[3/6] Analyzing movement events and delta summaries...
  Total movement events: 2
    - Simple movements (< 1000mm): 1
    - World movements (>= 1000mm): 1

  World movement details:
    [2026-01-29T14:32:00] John Smith: Layout moved (dx=1200, dy=0, dz=0)
      Max delta: 1200mm, Confidence: confirmed
      Before: x=5000, y=3200, z=1500
      After:  x=6200, y=3200, z=1500

[4/6] Finding checkout-only events...
  Checkout-only events: 0

[5/6] Checking snapshot file metadata...
  ✓ Snapshot file referenced: management-snapshot-DESIGN12-PROJECT_ID.json
  ✓ Snapshot file exists: data\output\management-snapshot-DESIGN12-PROJECT_ID.json
    Records: 25
    Generated: 2026-01-29T15:30:00Z

[6/6] Confidence distribution summary...
  Confirmed:      3
  Likely:         0
  Checkout Only:  0
  Unattributed:   0

========================================
  Verification Summary
========================================
  ✓ PASS: All verification checks passed

  Evidence Quality:
    - Events with evidence: 3 / 3
    - Confirmed events: 3
    - Movement events: 2 (Simple: 1, World: 1)
```

---

## Troubleshooting

### No events found after Siemens actions

```powershell
# Delete snapshot and re-run with wider date range
Remove-Item data\output\management-snapshot-DESIGN12-*.json
pwsh .\management-dashboard-launcher.ps1 -TNSName "SIEMENS_PS_DB_DB01" -Schema "DESIGN12" -ProjectId PROJECT_ID -DaysBack 60
```

### Events have confidence="unattributed"

**Likely cause:** Study was not checked out in Siemens.

**Solution:** Ensure you check out the study BEFORE making changes.

### Verification script fails

**Check:**
1. Data file path is correct
2. JSON is valid (open in editor to verify)
3. Events array exists in JSON

---

## Files Generated

| File | Purpose |
|------|---------|
| `management-DESIGN12-PROJECT_ID.json` | Raw event data with evidence blocks |
| `management-snapshot-DESIGN12-PROJECT_ID.json` | Snapshot for diff comparison |
| `management-dashboard-DESIGN12-PROJECT_ID.html` | Visual dashboard |
| `management-DESIGN12-PROJECT_ID-verification.json` | Verification results |

---

## Next Steps

1. Fill out proof pack template: `docs\E2E_TEST_PROOF_TEMPLATE.md`
2. Share results with team or management
3. Run regularly (weekly or before releases)
4. Extend test cases as needed
