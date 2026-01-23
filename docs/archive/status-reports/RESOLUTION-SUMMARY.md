# Missing MODULE_ Nodes - Resolution Summary

## Issue
MODULE_ nodes (including ST010_ZB_Li_Re_TLC with OBJECT_ID 993062) were not appearing in the generated navigation tree despite existing in the database.

## Timeline

### Initial Problem
- **Symptom:** User reported missing node "ST010_ZB_Li_Re_TLC" (Type: Module)
- **Impact:** All MODULE_ type nodes were missing from navigation tree
- **Context:** Node is inside an Alternative (cloned workspace) at W30_ZB Heckleuchtentopf_NCAR

### Investigation Phase 1: MODULE_ Query Missing
**Finding:** No SQL query existed for MODULE_ table
**Fix Applied:** Added MODULE_ query to [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1) (lines 949-967)

### Investigation Phase 2: Wrong Column Name (MODULE_)
**Finding:** MODULE_ query used NAME_S_ column which doesn't exist
**Error:** `ORA-00904: "M"."NAME_S_": invalid identifier`
**Fix Applied:** Changed to use NAME1_S_ column with COALESCE(CAPTION_S_, NAME1_S_, 'Unnamed')

### Investigation Phase 3: Cache Preventing Fix
**Finding:** Tree regeneration was using cached data instead of running fixed SQL
**Fix Applied:** Created cache-clearing regeneration script

### Investigation Phase 4: Still 0 MODULE_ Nodes
**Finding:** Despite all fixes being correct:
- MODULE_ query syntax was correct
- NAME1_S_ column was used
- Cache was cleared
- Standalone test query returned 3 MODULE_ nodes
- But full generation still returned 0 MODULE_ nodes

### Investigation Phase 5: Root Cause Discovered
**CRITICAL FINDING:** MFGFEATURE_ query had the SAME error (used NAME_S_ instead of NAME1_S_)

**Why This Broke Everything:**
```sql
-- This is the actual query structure:
SELECT ... FROM MFGFEATURE_ WHERE mf.NAME_S_ ...  -- ERROR: Column doesn't exist
UNION ALL
SELECT ... FROM PART_ (TxProcessAssembly) ...     -- Correct
UNION ALL
SELECT ... FROM MODULE_ WHERE m.NAME1_S_ ...      -- Correct BUT NEVER EXECUTED
```

**Impact Chain:**
1. MFGFEATURE_ query throws ORA-00904 error (NAME_S_ doesn't exist)
2. SQL error in UNION ALL causes **entire query to fail**
3. SQL*Plus returns 0 rows for the whole UNION ALL
4. MODULE_ query is syntactically correct but never produces output
5. Result: 0 MFGFEATURE_, 0 TxProcessAssembly, 0 MODULE_ nodes

## Root Cause

**File:** [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
**Lines:** 916-917 (MFGFEATURE_ query)

**Problem:** Used non-existent column `NAME_S_` instead of `NAME1_S_`

```sql
-- INCORRECT:
NVL(mf.NAME_S_, 'Unnamed')  -- NAME_S_ doesn't exist in MFGFEATURE_

-- CORRECT:
COALESCE(mf.CAPTION_S_, mf.NAME1_S_, 'Unnamed')  -- NAME1_S_ exists
```

## Schema Pattern

Multiple Siemens tables use NAME1_S_ instead of NAME_S_:
- **MODULE_** - Uses NAME1_S_ ✓ Fixed
- **MFGFEATURE_** - Uses NAME1_S_ ✓ Fixed
- Other tables may have similar pattern (needs investigation)

## Fixes Applied

### Fix 1: MFGFEATURE_ Column Name
**File:** [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
**Lines:** 911-928

Changed from:
```sql
NVL(mf.NAME_S_, 'Unnamed')
```

To:
```sql
COALESCE(mf.CAPTION_S_, mf.NAME1_S_, 'Unnamed')
```

### Fix 2: MODULE_ Query (Already Applied Previously)
**File:** [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
**Lines:** 949-967

Uses correct column:
```sql
COALESCE(m.CAPTION_S_, m.NAME1_S_, 'Unnamed Module')
```

## Testing

### Database Verification
```sql
DESC DESIGN1.MFGFEATURE_;
-- NAME1_S_   VARCHAR2(1024)  ✓ Exists
-- NAME_S_    Does NOT exist

DESC DESIGN1.MODULE_;
-- NAME1_S_   VARCHAR2(1024)  ✓ Exists
-- NAME_S_    Does NOT exist
```

### Standalone SQL Test
```sql
-- test-union-all-with-module.sql
-- Tests complete UNION ALL chain

BEFORE FIX:
- ORA-00904 error
- 0 rows returned

AFTER FIX (Expected):
- Query executes successfully
- Returns MFGFEATURE + TxProcessAssembly + MODULE_ nodes
- ST010_ZB_Li_Re_TLC appears (OBJECT_ID 993062)
```

### Full Regeneration Test
```powershell
# REGENERATE-WITH-MFGFEATURE-FIX.ps1
# Running now - verifies:
# - Cache is cleared
# - Both MFGFEATURE_ and MODULE_ use NAME1_S_
# - Tree generation completes
# - MODULE_ nodes appear in output
```

## Expected Outcome

After regeneration:
- ✓ MFGFEATURE_ query executes without error
- ✓ UNION ALL completes successfully
- ✓ 3 MODULE_ nodes appear:
  - ST010_ZB_Li_Re_TLC (OBJECT_ID: 993062) ← User's requested node
  - ST010_ZB_Li_Re_CD_Pillar (OBJECT_ID: 993084)
  - Module (OBJECT_ID: 974698)
- ✓ MFGFEATURE_ nodes also appear
- ✓ TxProcessAssembly nodes continue to work

## Lessons Learned

1. **UNION ALL Error Propagation**
   - SQL error in ANY part of UNION ALL breaks the ENTIRE query
   - Silent failure - no error message visible to user
   - Debugging required isolating each UNION component

2. **Schema Assumptions**
   - Cannot assume all tables use same column names
   - Need to verify column existence before writing queries
   - DESC table first, then write SQL

3. **Testing Isolation**
   - Test each UNION ALL component separately
   - Standalone tests can miss integration errors
   - Full end-to-end test required

4. **Cache Masking**
   - Cache can hide SQL errors for extended periods
   - Always clear cache when debugging SQL issues
   - Verify cache invalidation works

5. **Error Visibility**
   - SQL*Plus errors may not surface through PowerShell
   - Need better error logging/trapping
   - Consider adding -ErrorAction Stop

## Related Files

### Documentation
- [FIX-MFGFEATURE-COLUMN-NAME.md](FIX-MFGFEATURE-COLUMN-NAME.md) - Detailed technical analysis
- [FIX-MODULE-NODES.md](FIX-MODULE-NODES.md) - Initial MODULE_ query addition
- [FIX-MODULE-COLUMN-NAME.md](FIX-MODULE-COLUMN-NAME.md) - MODULE_ NAME1_S_ fix
- [FINDINGS-MISSING-NODES.md](FINDINGS-MISSING-NODES.md) - Original investigation
- [CHANGES-ORPHAN-FIX.md](CHANGES-ORPHAN-FIX.md) - TxProcessAssembly parent fix

### Scripts
- REGENERATE-WITH-MFGFEATURE-FIX.ps1 - Full regeneration with verification
- test-union-all-with-module.sql - Standalone UNION ALL test
- describe-mfgfeature.sql - Schema verification
- debug-module-query-corrected.sql - temp_project_objects debugging

### Modified Code
- [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
  - Lines 911-928: MFGFEATURE_ query fix
  - Lines 949-967: MODULE_ query (correct)

## Next Steps

1. ✓ Regeneration running (REGENERATE-WITH-MFGFEATURE-FIX.ps1)
2. ⏳ Verify MODULE_ nodes appear in output
3. ⏳ Confirm ST010_ZB_Li_Re_TLC is found
4. [ ] Check other tables for NAME1_S_ pattern
5. [ ] Add schema validation to prevent future issues
6. [ ] Improve error logging in PowerShell script
7. [ ] Test on DESIGN12 schema

## Status

**REGENERATION IN PROGRESS**

Waiting for tree generation to complete (~90 seconds expected)
