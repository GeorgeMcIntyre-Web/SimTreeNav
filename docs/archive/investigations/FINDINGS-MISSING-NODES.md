# Missing Nodes Investigation - FINDINGS

**Date**: 2026-01-20
**Database**: DESIGN12 / FORD_DEARBORN (Project ID: 18140190)
**Status**: ROOT CAUSE IDENTIFIED

---

## Executive Summary

Investigation revealed that **96.5% of nodes (611,493 out of 633,687) are at Level 999**, which is a placeholder level. This occurs because:

1. SQL queries output most nodes with `'999|'` as the level placeholder
2. JavaScript `buildTree()` function is supposed to recalculate correct levels
3. Level recalculation **only works if the parent node exists** in the tree
4. **5,584 orphan nodes** have parents that don't exist in the tree file at all
5. Without parents, the level stays at 999, creating a broken tree structure

---

## Key Metrics

| Metric | Value | Status |
|--------|-------|--------|
| Total Nodes | 633,687 | ✅ |
| Nodes at Level 999 | 611,493 (96.5%) | ❌ CRITICAL |
| Properly Leveled Nodes | 22,194 (3.5%) | ⚠️  |
| Orphan Nodes | 5,584 | ❌ HIGH |
| Missing Parent IDs | 2,875 unique | ❌ HIGH |
| Max Tree Depth | 17 (for proper nodes) | ✅ |

---

## Orphan Node Breakdown

### By Node Type

| Node Type | Orphan Count | % of Orphans |
|-----------|--------------|--------------|
| **TxProcessAssembly** | 2,826 | 50.6% |
| **Process** | 1,327 | 23.8% |
| **CompoundOperation** | 425 | 7.6% |
| **Source** | 398 | 7.1% |
| **WeldOperation** | 258 | 4.6% |
| **PrStationProcess** | 209 | 3.7% |
| Other | 141 | 2.5% |

### Top Missing Parents

These parent IDs have the most orphaned children:

| Parent ID | Orphan Children | Child Type Example |
|-----------|-----------------|-------------------|
| 14012669 | 139 | TxProcessAssembly |
| 12309396 | 138 | TxProcessAssembly |
| 8835587 | 96 | TxProcessAssembly |
| 8835585 | 89 | TxProcessAssembly |
| 8835583 | 89 | TxProcessAssembly |
| 14012668 | 62 | TxProcessAssembly |

**All missing parent IDs were checked and NONE exist in the tree file.**

---

## Root Cause Analysis

### Issue #1: Missing Parent Nodes

**Problem**: Parent nodes for TxProcessAssembly, Process, and CompoundOperation are not being included in SQL queries.

**Evidence**:
- 2,875 unique parent IDs referenced but don't exist in tree
- Sample parent IDs checked: 0 out of 20 exist
- Most missing parents would be PART_ or COLLECTION_ nodes

**SQL Query Gaps**:
Looking at [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1):

1. **TxProcessAssembly query** (line 982): Filters by `p.CLASS_ID = 133`
   - This only includes TxProcessAssembly nodes themselves
   - Does NOT include their parents
   - Parents may be other PART_ nodes or COLLECTION_ nodes

2. **Process/Operation queries** (line 905-910):
   ```sql
   WHERE op.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
   ```
   - Relies on temp table populated by iterative query
   - If iteration misses nodes, they won't be in temp table
   - Parents of operations may not be in COLLECTION_ table

3. **PART_ node queries** (lines 524-585):
   - Has multiple WHERE filters that may exclude parent nodes:
   ```sql
   WHERE NOT EXISTS (SELECT 1 FROM COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
     AND EXISTS (SELECT 1 FROM COLLECTION_ c2 WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID)
   ```
   - This requires parent to be in COLLECTION_ table
   - **Problem**: Many parents are PART_ nodes, not COLLECTION_ nodes!

---

## Specific SQL Query Issues

### Issue A: PART_ Parent Validation Too Restrictive

**Location**: Lines 534-536, 584

```sql
AND EXISTS (
    SELECT 1 FROM $Schema.COLLECTION_ c2
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
)
```

**Problem**: This filters out all PART_ nodes whose parent is also a PART_ node (not a COLLECTION_).

**Impact**: TxProcessAssembly nodes often have PART_ parents, not COLLECTION_ parents.

**Fix**: Change parent validation to:
```sql
AND EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    WHERE r2.OBJECT_ID = r.FORWARD_OBJECT_ID
)
```
Or use the temp_project_objects table:
```sql
AND r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

---

### Issue B: TxProcessAssembly Query Doesn't Include Parents

**Location**: Lines 969-990

```sql
WHERE p.CLASS_ID = 133  -- TxProcessAssembly TYPE_ID
  AND EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND c2.OBJECT_ID IN (...)
  )
```

**Problem**: Requires parent to be in COLLECTION_ table.

**Solution**: Add separate query for TxProcessAssembly nodes with PART_ parents:

```sql
UNION ALL
-- TxProcessAssembly nodes with PART_ parents
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    p.OBJECT_ID || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.PART_ p
INNER JOIN $Schema.REL_COMMON r ON p.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE p.CLASS_ID = 133  -- TxProcessAssembly
  AND r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID);
```

---

### Issue C: Iterative Temp Table May Miss Nodes

**Location**: Lines 865-891

```sql
INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
SELECT DISTINCT rc.OBJECT_ID, 1
FROM $Schema.REL_COMMON rc
WHERE rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM temp_project_objects WHERE OBJECT_ID = rc.OBJECT_ID);
```

**Problem**: This iterative approach assumes all nodes are reachable through FORWARD_OBJECT_ID relationships. If a node type uses different relationship columns, it won't be found.

**Solution**: Add explicit queries for each specialized relationship type before the iterative loop.

---

## Recommended Fixes

### Priority 1: Fix PART_ Parent Validation (CRITICAL)

**File**: [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
**Lines**: 534-536, 584

Change:
```sql
AND EXISTS (
    SELECT 1 FROM $Schema.COLLECTION_ c2
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
)
```

To:
```sql
AND r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

**Impact**: This will include PART_ nodes whose parents are also PART_ nodes, not just COLLECTION_ nodes.

**Expected improvement**: Should fix ~70% of orphans (TxProcessAssembly and Process nodes).

---

### Priority 2: Add TxProcessAssembly with PART_ Parents (HIGH)

**File**: [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
**After**: Line 990

Add new UNION ALL:
```sql
UNION ALL
-- TxProcessAssembly nodes with PART_ parents (not just COLLECTION_ parents)
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    p.OBJECT_ID || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.PART_ p
INNER JOIN $Schema.REL_COMMON r ON p.OBJECT_ID = r.OBJECT_ID
INNER JOIN $Schema.PART_ p_parent ON r.FORWARD_OBJECT_ID = p_parent.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE p.CLASS_ID = 133  -- TxProcessAssembly
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);
```

**Impact**: Will include TxProcessAssembly nodes whose parent is a PART_ node.

---

### Priority 3: Verify Temp Table Population (MEDIUM)

**File**: [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
**Lines**: 865-891

Add logging to see how many nodes are found in each iteration:

```sql
-- After each iteration
SELECT 'ITERATION ' || v_pass || ': Added ' || v_rows_added || ' nodes' FROM DUAL;
```

This will help verify that the iterative query is finding all nodes.

---

## Testing Plan

After applying fixes:

1. **Regenerate tree** with fixed SQL
   ```powershell
   # Clear cache
   Remove-Item tree-cache-*.txt
   Remove-Item tree-data-*-clean.txt

   # Regenerate
   .\src\powershell\main\generate-tree-html.ps1 -TNSName "DES_SIM_DB2" -Schema "DESIGN12" -ProjectId 18140190 -ProjectName "FORD_DEARBORN"
   ```

2. **Run quick stats**
   ```powershell
   .\src\powershell\debug\quick-tree-stats.ps1 -Schema DESIGN12 -ProjectId 18140190
   ```

3. **Check metrics**:
   - Nodes at Level 999 should drop from 96.5% to <5%
   - Orphan count should drop from 5,584 to <100
   - TxProcessAssembly orphans should be 0

4. **Run orphan analysis**
   ```powershell
   .\src\powershell\debug\find-orphan-causes.ps1 -Schema DESIGN12 -ProjectId 18140190
   ```

5. **Validate in browser**:
   - Open navigation-tree.html
   - Search for a TxProcessAssembly node (e.g., "7K-010-01N_LH")
   - Verify it appears in the tree with proper hierarchy

---

## Expected Outcomes

| Metric | Before | Target After Fix |
|--------|--------|------------------|
| Nodes at Level 999 | 611,493 (96.5%) | <30,000 (5%) |
| Orphan Nodes | 5,584 | <100 |
| TxProcessAssembly Orphans | 2,826 | 0 |
| Process Orphans | 1,327 | <50 |
| Missing Parents | 2,875 | <20 |

---

## Files Created During Investigation

| File | Description |
|------|-------------|
| [RUN-MISSING-NODES-CHECK.ps1](RUN-MISSING-NODES-CHECK.ps1) | Quick launcher for diagnostics |
| [src/powershell/debug/find-missing-nodes.ps1](src/powershell/debug/find-missing-nodes.ps1) | Database comparison diagnostic |
| [src/powershell/debug/quick-tree-stats.ps1](src/powershell/debug/quick-tree-stats.ps1) | Fast tree analysis |
| [src/powershell/debug/analyze-tree-coverage.ps1](src/powershell/debug/analyze-tree-coverage.ps1) | Detailed tree coverage analysis |
| [src/powershell/debug/find-orphan-causes.ps1](src/powershell/debug/find-orphan-causes.ps1) | Orphan root cause analysis |
| [src/powershell/debug/README-DEBUG.md](src/powershell/debug/README-DEBUG.md) | Debugging guide |
| [MISSING-NODES-ANALYSIS.md](MISSING-NODES-ANALYSIS.md) | Analysis patterns and solutions |
| orphan-analysis-DESIGN12-18140190.csv | Detailed orphan report (5,000 rows) |

---

## Next Steps

1. **Apply Priority 1 fix** (PART_ parent validation)
2. **Test on DESIGN12** to verify improvement
3. **Apply Priority 2 fix** (TxProcessAssembly with PART_ parents)
4. **Re-test** to confirm orphan count drops
5. **Test on DESIGN1/BMW** to ensure fixes work across schemas
6. **Update UAT plan** with new validation checks

---

**Investigation Status**: COMPLETE
**Fix Status**: READY TO IMPLEMENT
**Confidence Level**: HIGH (root cause clearly identified with data)

