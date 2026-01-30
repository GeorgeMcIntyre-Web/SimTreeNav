# Project Filtering Fix Plan

**Date:** 2026-01-29
**Issue:** 10 out of 15 queries in get-management-data.ps1 return schema-wide data instead of project-scoped data
**Impact:** Management dashboard shows data from ALL projects in the schema, not just the requested project
**Root Cause:** Queries missing hierarchical project filter using REL_COMMON table

---

## Problem Summary

When running `get-management-data.ps1 -ProjectId 18851221`, the dashboard should show data ONLY for the _testing project. Currently it shows:
- **Expected:** 1 study (RobcadStudy1)
- **Actual:** 203 studies (ALL studies in DESIGN12 schema)

This makes the dashboard unusable for project-specific analysis.

---

## Correct Query Pattern

The working pattern (from generate-tree-html.ps1):

```sql
-- For ROBCADSTUDY_ queries:
FROM ##SCHEMA##.ROBCADSTUDY_ rs
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.OBJECT_ID
WHERE EXISTS (
    SELECT 1 FROM ##SCHEMA##.REL_COMMON r2
    INNER JOIN ##SCHEMA##.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM ##SCHEMA##.REL_COMMON r3
        INNER JOIN ##SCHEMA##.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = ##PROJECTID##
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  )
```

**Key Insight:**
- Studies are linked to their parent folder via `REL_COMMON` where `OBJECT_ID` = study ID
- Parent folders are linked to the project via hierarchical `CONNECT BY` traversal
- **NOT** via a simple `COLLECTIONREF_I_` or `COLLECTIONS_VR_` column

---

## Broken Queries and Fixes

### Query 5A: Study Summary
**File:** src/powershell/main/get-management-data.ps1
**Lines:** ~601-624
**Current:**
```sql
FROM ##SCHEMA##.ROBCADSTUDY_ rs
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE (rs.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  OR p.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 50
```

**Fixed:**
```sql
FROM ##SCHEMA##.ROBCADSTUDY_ rs
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.OBJECT_ID
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN ##SCHEMA##.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE EXISTS (
    SELECT 1 FROM ##SCHEMA##.REL_COMMON r2
    INNER JOIN ##SCHEMA##.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM ##SCHEMA##.REL_COMMON r3
        INNER JOIN ##SCHEMA##.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = ##PROJECTID##
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  )
  AND (rs.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
    OR p.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 50
```

**Impact:** FORD_DEARBORN shows 76 studies (was 203), _testing shows 1 study (was 203)

---

### Query 5B: Study Resources
**File:** src/powershell/main/get-management-data.ps1
**Lines:** ~629-656

**Current:** Missing project filter entirely
**Fixed:** Add same EXISTS clause as Q5A
**Impact:** Only shows resources allocated to project studies

---

### Query 5C: Study Panels
**File:** src/powershell/main/get-management-data.ps1
**Lines:** ~665-688

**Current:** Missing project filter entirely
**Fixed:** Add same EXISTS clause as Q5A
**Impact:** Only shows panel allocations for project studies

---

### Query 5D: Study Operations
**File:** src/powershell/main/get-management-data.ps1
**Lines:** ~695-726

**Current:**
```sql
FROM ##SCHEMA##.OPERATION_ o
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY p ON o.OBJECT_ID = p.OBJECT_ID
WHERE (o.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  OR p.WORKING_VERSION_ID > 0)
  AND o.CLASS_ID = 141
```

**Fixed:** Need to link operations to studies first:
```sql
FROM ##SCHEMA##.OPERATION_ o
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
LEFT JOIN ##SCHEMA##.PROXY p ON o.OBJECT_ID = p.OBJECT_ID
WHERE o.CLASS_ID = 141
  AND EXISTS (
    -- Find the study that owns this operation
    SELECT 1
    FROM ##SCHEMA##.REL_COMMON r_op
    INNER JOIN ##SCHEMA##.ROBCADSTUDY_ rs ON r_op.FORWARD_OBJECT_ID = rs.OBJECT_ID
    INNER JOIN ##SCHEMA##.REL_COMMON r_study ON rs.OBJECT_ID = r_study.OBJECT_ID
    WHERE r_op.OBJECT_ID = o.OBJECT_ID
      AND EXISTS (
        SELECT 1 FROM ##SCHEMA##.REL_COMMON r2
        INNER JOIN ##SCHEMA##.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
        WHERE c2.OBJECT_ID = r_study.FORWARD_OBJECT_ID
          AND c2.OBJECT_ID IN (
            SELECT c3.OBJECT_ID
            FROM ##SCHEMA##.REL_COMMON r3
            INNER JOIN ##SCHEMA##.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
            START WITH r3.FORWARD_OBJECT_ID = ##PROJECTID##
            CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
          )
      )
  )
  AND (o.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
    OR p.WORKING_VERSION_ID > 0)
```

**Impact:** Only shows operations that belong to studies in the project

---

### Query 5E: Study Movements
**File:** src/powershell/main/get-management-data.ps1
**Lines:** ~731-762

**Current:**
```sql
FROM ##SCHEMA##.STUDYLAYOUT_ sl
LEFT JOIN ##SCHEMA##.PROXY p ON sl.OBJECT_ID = p.OBJECT_ID
WHERE (sl.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
  OR p.WORKING_VERSION_ID > 0)
```

**Fixed:**
```sql
FROM ##SCHEMA##.STUDYLAYOUT_ sl
INNER JOIN ##SCHEMA##.ROBCADSTUDY_ rs ON sl.STUDYINFO_SR_ = rs.OBJECT_ID
INNER JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.OBJECT_ID
LEFT JOIN ##SCHEMA##.PROXY p ON sl.OBJECT_ID = p.OBJECT_ID
WHERE EXISTS (
    SELECT 1 FROM ##SCHEMA##.REL_COMMON r2
    INNER JOIN ##SCHEMA##.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM ##SCHEMA##.REL_COMMON r3
        INNER JOIN ##SCHEMA##.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = ##PROJECTID##
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  )
  AND (sl.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
    OR p.WORKING_VERSION_ID > 0)
```

**Impact:** Only shows movements from project studies

---

### Query 5F: Study Welds
**File:** src/powershell/main/get-management-data.ps1
**Lines:** ~767-788

**Current:** Duplicate of Q5D
**Fixed:** Same as Q5D
**Impact:** Only shows weld operations from project studies

---

### Query 7: Study Health Analysis
**File:** src/powershell/main/get-management-data.ps1
**Lines:** ~814-829

**Current:**
```sql
FROM ##SCHEMA##.ROBCADSTUDY_ rs
LEFT JOIN ##SCHEMA##.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
WHERE rs.NAME_S_ IS NOT NULL
```

**Fixed:** Add same pattern as Q5A
**Impact:** Only analyzes studies in the project

---

### Queries 8-10: Resource Conflicts, Stale Checkouts, Bottleneck Queue

These queries are more complex and may need individual attention. Recommendation:
1. Fix Q5A-Q7 first (the core study queries)
2. Test with E2E workflow
3. Then address Q8-Q10 based on actual usage

---

## Implementation Strategy

### Phase 1: Core Study Queries (HIGH PRIORITY)
1. Fix Q5A: Study Summary ✓ Pattern validated
2. Fix Q5B: Study Resources
3. Fix Q5C: Study Panels
4. Fix Q5E: Study Movements ✓ Pattern validated
5. Fix Q7: Study Health

**Estimated Impact:** ~80% of dashboard data will be project-scoped

### Phase 2: Operations (MEDIUM PRIORITY)
1. Fix Q5D: Study Operations ✓ Pattern validated
2. Fix Q5F: Study Welds

**Estimated Impact:** Evidence blocks for operations will be project-scoped

### Phase 3: Advanced Queries (LOW PRIORITY)
1. Fix Q8: Resource Conflicts
2. Fix Q9: Stale Checkouts
3. Fix Q10: Bottleneck Queue

**Estimated Impact:** Management insights will be project-scoped

---

## Testing Approach

### Before Fix (Baseline)
```powershell
# Run against _testing project
pwsh .\management-dashboard-launcher.ps1 -TNSName "DES_SIM_DB1_DB01" -Schema "DESIGN12" -ProjectId 18851221 -DaysBack 30 -AutoLaunch:$false

# Expected (broken): Shows 203 studies from entire schema
```

### After Fix (Validation)
```powershell
# Run against _testing project
pwsh .\management-dashboard-launcher.ps1 -TNSName "DES_SIM_DB1_DB01" -Schema "DESIGN12" -ProjectId 18851221 -DaysBack 30 -AutoLaunch:$false

# Expected (fixed): Shows 1 study (RobcadStudy1)
```

### Validation Criteria
- [ ] Study count matches project (1 for _testing, 76 for FORD_DEARBORN)
- [ ] All events in dashboard belong to project studies only
- [ ] Evidence blocks reference correct studies
- [ ] No cross-project contamination
- [ ] Snapshot comparison still works

---

## Risk Assessment

### Low Risk Queries (Safe to fix immediately)
- Q5A: Study Summary
- Q5B: Study Resources
- Q5C: Study Panels
- Q5E: Study Movements
- Q7: Study Health

**Why:** These are pure data retrieval, no side effects

### Medium Risk Queries (Review carefully)
- Q5D: Study Operations
- Q5F: Study Welds

**Why:** Used in evidence block generation

### High Risk Queries (Defer if needed)
- Q8: Resource Conflicts
- Q9: Stale Checkouts
- Q10: Bottleneck Queue

**Why:** Complex multi-table joins, may have dependencies

---

## Rollback Plan

All changes are in `get-management-data.ps1`. To rollback:
```bash
git checkout -- src/powershell/main/get-management-data.ps1
```

---

## Success Metrics

1. **Correctness:** Dashboard shows only project data
2. **Performance:** Query execution time remains under 15 seconds
3. **Evidence Quality:** All confidence ratings remain accurate
4. **E2E Validation:** Can detect Siemens front-end actions in correct project

---

## Next Steps

**Option A (Conservative):** Fix Phase 1 only (5 queries), test with E2E workflow, then decide on Phase 2/3
**Option B (Comprehensive):** Fix all 10 queries at once, comprehensive testing

**Recommendation:** Option A - get core functionality working first, validate with real E2E test
