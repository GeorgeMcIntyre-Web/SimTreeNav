# E2E Test Proof Pack: [Study Name] on [Date]

**Date:** ___________________
**Executor:** ___________________
**Environment:** db01 / DESIGN12 / _testing

---

## Test Summary

| Metric | Value |
|--------|-------|
| Study Name | _________________ |
| Study ID | _________________ |
| User (Siemens) | _________________ |
| User (DB) | _________________ |
| Baseline Events | _________________ |
| After Events | _________________ |
| New Events | _________________ |

---

## What I Changed in Siemens UI

- [ ] **Checkout:** Checked out study (PROXY.WORKING_VERSION_ID > 0)
- [ ] **Simple Move:** Moved [object name] by [delta]mm in [axis]-axis
  - Before: x=_____, y=_____, z=_____
  - After:  x=_____, y=_____, z=_____
  - Delta: _____mm
- [ ] **World Move:** Moved [object name] by [delta]mm in [axis]-axis
  - Before: x=_____, y=_____, z=_____
  - After:  x=_____, y=_____, z=_____
  - Delta: _____mm (should be >= 1000mm)
- [ ] **Operation:** [Created new / Modified existing] operation "[operation name]"
  - Type: _________________
  - Change: _________________
- [ ] **Check In:** Checked in study (released lock)

---

## What DB Evidence Corresponds

### Checkout Evidence
- **Proof:** `PROXY.WORKING_VERSION_ID` = _____ (should be > 0 during work)
- **User:** `PROXY.OWNER_ID` → `USER_.CAPTION_S_` = _________________
- **Status:** [Detected / Not Detected]

### Modification Date Evidence
- **Proof:** `STUDYLAYOUT_.MODIFICATIONDATE_DA_` changed
  - Before: ___________________
  - After:  ___________________
- **Proof:** `OPERATION_.MODIFICATIONDATE_DA_` changed (if operation edit)
  - Before: ___________________
  - After:  ___________________
- **Status:** [Detected / Not Detected]

### Delta Evidence (Movement)
- **Proof:** `VEC_LOCATION_` values changed
  - Simple move delta: _____mm
  - World move delta: _____mm
- **Status:** [Detected / Not Detected]

### Delta Evidence (Operation)
- **Proof:** Operation count or structure changed
  - Before: ___________________
  - After:  ___________________
- **Status:** [Detected / Not Detected]

---

## What SimTreeNav Shows

### Event List

| Timestamp | User | Work Type | Description | Confidence |
|-----------|------|-----------|-------------|------------|
| _________ | ____ | _________ | ___________ | __________ |
| _________ | ____ | _________ | ___________ | __________ |
| _________ | ____ | _________ | ___________ | __________ |
| _________ | ____ | _________ | ___________ | __________ |

### Simple Move Event Details

**Event:** _________________
**Confidence:** [confirmed / likely / checkout_only / unattributed]

**Evidence:**
- `hasCheckout`: [true / false]
- `hasWrite`: [true / false]
- `hasDelta`: [true / false]
- `maxAbsDelta`: _____mm
- `attributionStrength`: [strong / medium / weak]

**Write Sources:**
- _________________

**Delta Summary:**
- Kind: movement
- Fields: [x, y, z]
- Before: { x: _____, y: _____, z: _____ }
- After:  { x: _____, y: _____, z: _____ }

### World Move Event Details

**Event:** _________________
**Confidence:** [confirmed / likely / checkout_only / unattributed]

**Evidence:**
- `hasCheckout`: [true / false]
- `hasWrite`: [true / false]
- `hasDelta`: [true / false]
- `maxAbsDelta`: _____mm (should be >= 1000mm)
- `attributionStrength`: [strong / medium / weak]

**Write Sources:**
- _________________

**Delta Summary:**
- Kind: movement
- Fields: [x, y, z]
- Before: { x: _____, y: _____, z: _____ }
- After:  { x: _____, y: _____, z: _____ }

### Operation Event Details

**Event:** _________________
**Confidence:** [confirmed / likely / checkout_only / unattributed]

**Evidence:**
- `hasCheckout`: [true / false]
- `hasWrite`: [true / false]
- `hasDelta`: [true / false]
- `attributionStrength`: [strong / medium / weak]

**Write Sources:**
- _________________

---

## What This Proves (For Management)

### Real Work vs Viewing-Only

✅ **SimTreeNav distinguishes between:**
- **Viewing/browsing** a study (no evidence): [Demonstrated / Not Demonstrated]
- **Checking out** without saving (checkout-only evidence): [Demonstrated / Not Demonstrated]
- **Making and saving changes** (confirmed evidence with full triangle): [Demonstrated / Not Demonstrated]

### Checkout-Only vs Saved Modifications

✅ **SimTreeNav clarifies:**
- **Checkout-only:** Study locked but unchanged (possible stale checkout): [Demonstrated / Not Demonstrated]
- **Confirmed modifications:** Study locked AND changed with measurable delta: [Demonstrated / Not Demonstrated]

### Movement Classification

✅ **SimTreeNav categorizes movements:**
- **Simple moves** (< 1000mm): Fine-tuning, minor adjustments: [Demonstrated / Not Demonstrated]
- **World location changes** (>= 1000mm): Major layout reconfiguration: [Demonstrated / Not Demonstrated]

### User Attribution

✅ **SimTreeNav attributes work to users:**
- **Strong attribution:** PROXY owner matches LASTMODIFIEDBY: [Demonstrated / Not Demonstrated]
- **Medium attribution:** Partial or conflicting user data: [Demonstrated / Not Demonstrated]
- **Weak attribution:** No user data available: [Demonstrated / Not Demonstrated]

---

## How to Repeat

1. Open Siemens Process Simulate
2. Navigate to `DESIGN12` schema, `_testing` project
3. Open study: [study name]
4. **Checkout** the study
5. **Simple move:** Move any robot/station by 50mm and save
6. **World move:** Move same or different object by 1200mm and save
7. **Operation edit:** Modify or create an operation and save
8. **Check in** the study
9. Run SimTreeNav baseline BEFORE step 4
10. Run SimTreeNav after AFTER step 8
11. Run verification script
12. Review dashboard and evidence blocks

---

## Verification Results

### Evidence Integrity Checks

| Check | Status | Notes |
|-------|--------|-------|
| All events have evidence blocks | [PASS / FAIL] | _________________ |
| Confirmed events have complete triangle | [PASS / FAIL] | _________________ |
| Movement deltas detected correctly | [PASS / FAIL] | _________________ |
| Simple vs World categorization correct | [PASS / FAIL] | _________________ |
| Checkout-only events identified | [PASS / FAIL / N/A] | _________________ |
| Snapshot integrity maintained | [PASS / FAIL] | _________________ |

### Confidence Distribution

- **Confirmed:** _____ events
- **Likely:** _____ events
- **Checkout Only:** _____ events
- **Unattributed:** _____ events

### Overall Result

- [ ] **PASS:** All checks passed, evidence quality is good
- [ ] **FAIL:** One or more checks failed (see notes)

**Notes/Issues:**
_________________
_________________
_________________

---

## Screenshots (Optional)

### Siemens UI Before
(Insert screenshot or description)

### Siemens UI After
(Insert screenshot or description)

### SimTreeNav Dashboard - Timeline View
(Insert screenshot or description)

### SimTreeNav Dashboard - Evidence Details
(Insert screenshot or description)

---

## Sign-Off

- [ ] E2E test completed successfully
- [ ] All Siemens actions performed and saved
- [ ] SimTreeNav baseline and after runs completed
- [ ] Verification script passed
- [ ] Dashboard reviewed and evidence is correct
- [ ] Proof pack documented

**Executor:** _________________
**Reviewer:** _________________
**Date:** _________________

---

## Appendix: Raw Data Snippets

### Event JSON (Simple Move)
```json
(Paste event JSON here)
```

### Event JSON (World Move)
```json
(Paste event JSON here)
```

### Snapshot Comparison (Before/After)
```json
(Paste relevant snapshot record diff here)
```

### Verification Script Output
```
(Paste verification script output here)
```
