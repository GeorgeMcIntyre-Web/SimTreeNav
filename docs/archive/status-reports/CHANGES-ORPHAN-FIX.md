# Orphan Node Fix - Changes Applied

**Date**: 2026-01-20
**Issue**: 96.5% of nodes stuck at Level 999 due to 5,584 orphan nodes with missing parents
**Root Cause**: TxProcessAssembly and other nodes had parents filtered out by restrictive WHERE clauses

---

## Changes Made to generate-tree-html.ps1

### Change #1: Moved TxProcessAssembly Query (Priority 2 Fix)

**Location**: After line 927 (before DROP TABLE temp_project_objects)

**What Changed**: Added new UNION ALL query for TxProcessAssembly that uses temp_project_objects for parent validation

**Old Behavior**:
- TxProcessAssembly query came after temp_project_objects was dropped (line 985+)
- Could only validate parents that were in COLLECTION_ table
- Used slow hierarchical query for parent validation
- Missed TxProcessAssembly nodes with PART_ parents

**New Behavior**:
- TxProcessAssembly query now runs BEFORE temp_project_objects is dropped
- Uses temp_project_objects which includes both COLLECTION_ and PART_ nodes
- Much faster parent validation (simple IN clause)
- Includes TxProcessAssembly nodes with any parent type

**Code Added**:
```sql
UNION ALL
-- Add TxProcessAssembly nodes that are in project tree (using temp table for parent validation)
-- TxProcessAssembly (CLASS_ID 133) nodes may have PART_ or COLLECTION_ parents
-- This query includes ALL TxProcessAssembly nodes whose parents were found during iteration
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    p.OBJECT_ID || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmTxProcessAssembly') || '|' ||
    NVL(cd.NICE_NAME, 'TxProcessAssembly') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE p.CLASS_ID = 133  -- TxProcessAssembly TYPE_ID
  AND r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID);
```

---

### Change #2: Commented Out Old TxProcessAssembly Query

**Location**: Lines 985-1014 (formerly 964+)

**What Changed**: Commented out the old TxProcessAssembly query to avoid duplicates

**Reason**: The new query (above) is a superset of the old query. The old query:
- Only found TxProcessAssembly with COLLECTION_ parents
- Used slow hierarchical EXISTS query
- Couldn't use temp_project_objects (already dropped)

The new query includes all nodes the old query found, PLUS additional nodes with PART_ parents.

**Safety**: Commented out (not deleted) so it can be restored if needed.

---

### Change #3: Added UNION ALL Connector

**Location**: Line 1015

**What Changed**: Added `UNION ALL` before the next SELECT to maintain query chain

**Reason**: When the old TxProcessAssembly query was commented out, it left a gap in the SQL UNION chain. The UNION ALL connects the previous query (SHORTCUT_) to the next query (PART_ children).

---

## Impact Analysis

### Expected Improvements

| Metric | Before | Expected After |
|--------|--------|----------------|
| Nodes at Level 999 | 611,493 (96.5%) | <30,000 (5%) |
| Orphan Nodes | 5,584 | <100 |
| TxProcessAssembly Orphans | 2,826 | 0 |
| Process Orphans | 1,327 | <50 |
| Missing Parent IDs | 2,875 | <20 |

### Performance Impact

**No Performance Degradation Expected**:
- New query uses simple IN clause with temp table (fast)
- Old query used hierarchical CONNECT BY (slow)
- Net result: Should be FASTER

**Memory Impact**: Minimal
- temp_project_objects already existed
- Just querying it one more time before DROP

---

## Breaking Change Analysis

### ✅ Non-Breaking Changes

1. **TxProcessAssembly nodes now included**: Previously missing nodes will appear
2. **Parent relationships preserved**: All existing valid relationships maintained
3. **No schema changes**: Only SQL query logic changed
4. **No JavaScript changes**: Tree building logic unchanged
5. **Backward compatible**: Works with existing cache files (when regenerated)

### ⚠️ Potential Impacts

1. **Node count will increase**: Tree will have more nodes than before
   - This is CORRECT behavior - previously missing nodes now included
   - May impact tree rendering performance slightly (more nodes to display)

2. **Duplicate detection**: Minimal risk
   - Old query commented out (not running)
   - New query has same `NOT EXISTS` check to avoid COLLECTION_ duplicates
   - UNION ALL may create duplicates if node appears in multiple queries
   - JavaScript buildTree() handles this by updating existing nodes

3. **Icon assignment**: No impact
   - Same TYPE_ID and CLASS_ID used
   - Icon lookup logic unchanged

4. **Level calculation**: FIXED
   - JavaScript recalculates levels when parents exist
   - With parents now included, level calculation will work correctly

---

## Testing Checklist

- [ ] Tree regenerates without SQL errors
- [ ] Node count increases (expected)
- [ ] Orphan count decreases significantly
- [ ] Nodes at Level 999 drops to <5%
- [ ] TxProcessAssembly orphans = 0
- [ ] No duplicate OBJECT_IDs in tree file
- [ ] HTML opens in browser without errors
- [ ] Search for "7K-010-01N_LH" (sample TxProcessAssembly) finds node
- [ ] Node hierarchy displays correctly
- [ ] Icons display correctly for TxProcessAssembly nodes

---

## Rollback Plan

If issues occur, rollback is simple:

1. **Revert generate-tree-html.ps1**:
   ```powershell
   git checkout src/powershell/main/generate-tree-html.ps1
   ```

2. **Clear cache**:
   ```powershell
   rm tree-cache-*.txt tree-data-*-clean.txt
   ```

3. **Regenerate**:
   ```powershell
   .\src\powershell\main\generate-tree-html.ps1 -TNSName "DES_SIM_DB2" -Schema "DESIGN12" -ProjectId 18140190 -ProjectName "FORD_DEARBORN"
   ```

---

## Files Modified

1. [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
   - Added new TxProcessAssembly query (after line 927)
   - Commented out old TxProcessAssembly query (lines 985-1014)
   - Added UNION ALL connector (line 1015)

---

## Next Steps

1. ✅ Apply fixes to generate-tree-html.ps1
2. ⏳ Test regeneration on DESIGN12
3. ⏳ Run diagnostics to verify improvement
4. ⏳ Validate in browser
5. ⏳ Test on DESIGN1/BMW
6. ⏳ Commit changes if successful

---

**Status**: CHANGES APPLIED - TESTING IN PROGRESS
**Confidence**: HIGH (surgical fix, non-breaking)
