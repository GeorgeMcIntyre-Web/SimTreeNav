# Node Ordering Fix - Summary

## Problem Solved
Navigation tree nodes were appearing in OBJECT_ID (creation) order instead of matching the user-defined order shown in Process Simulate when users manually reordered nodes via drag-and-drop.

## Root Cause
Process Simulate stores parent-child relationships **twice** in the REL_COMMON table:

1. **Forward relationship** (Child → Parent):
   - OBJECT_ID = child, FORWARD_OBJECT_ID = parent
   - FIELD_NAME = 'collections'
   - SEQ_NUMBER = 0 (not useful for ordering)

2. **Reverse relationship** (Parent → Child):
   - OBJECT_ID = parent, FORWARD_OBJECT_ID = child
   - FIELD_NAME = 'children'
   - **SEQ_NUMBER = user-defined order** (this is what we needed!)

The tree generation SQL was only using the forward relationship, which had SEQ_NUMBER=0 for all nodes.

## Solution Implemented

### Code Changes
Updated `src/powershell/main/generate-tree-html.ps1`:

1. **Level 1 query** (lines 477-496): Added LEFT JOIN to reverse REL_COMMON relationship
   ```sql
   LEFT JOIN $Schema.REL_COMMON r_order ON r_order.OBJECT_ID = r.FORWARD_OBJECT_ID
       AND r_order.FORWARD_OBJECT_ID = r.OBJECT_ID
       AND r_order.FIELD_NAME = 'children'
   ORDER BY NVL(r_order.SEQ_NUMBER, 999), ...
   ```

2. **Level 2+ query** (lines 498-520): Added same LEFT JOIN pattern
   ```sql
   LEFT JOIN $Schema.REL_COMMON r_order ON r_order.OBJECT_ID = r.FORWARD_OBJECT_ID
       AND r_order.FORWARD_OBJECT_ID = r.OBJECT_ID
       AND r_order.FIELD_NAME = 'children'
   ORDER SIBLINGS BY NVL(r_order.SEQ_NUMBER, 999999), c.OBJECT_ID;
   ```

### Additional Enhancement
Also added `-NoCache` parameter to `tree-viewer-launcher.ps1` to allow forcing fresh data from database (bypass 24-hour cache).

## Verification

### Test Case: testorder Folder
Created a test folder with nodes 1, 2, 3, 4, 5 and reordered to 5, 4, 3, 2, 1.

**Database Check:**
```sql
SELECT r2.FORWARD_OBJECT_ID, c.CAPTION_S_, r2.SEQ_NUMBER
FROM REL_COMMON r2
INNER JOIN COLLECTION_ c ON r2.FORWARD_OBJECT_ID = c.OBJECT_ID
WHERE r2.OBJECT_ID = 18851404 AND r2.FIELD_NAME = 'children'
ORDER BY r2.SEQ_NUMBER;
```

Result:
```
FORWARD_OBJECT_ID  NAME  SEQ_NUMBER
18851409           5     0
18851408           4     1
18851407           3     2
18851406           2     3
18851405           1     4
```

**Generated Tree:** Now correctly shows **5, 4, 3, 2, 1** - matching Process Simulate exactly!

## Impact

This fix ensures:
- Generated navigation tree matches Process Simulate's display order exactly
- User-defined manual ordering (drag-and-drop reordering) is preserved
- Multi-user consistency (ordering persists across sessions after check-in)
- Works for all node types at all levels of the tree hierarchy

## Files Modified

1. `src/powershell/main/generate-tree-html.ps1`
   - Added r_order LEFT JOIN to both Level 1 and Level 2+ queries
   - Updated ORDER BY clauses to use r_order.SEQ_NUMBER

2. `src/powershell/main/tree-viewer-launcher.ps1`
   - Added -NoCache parameter
   - Pass-through to generate-tree-html.ps1

## Commits

1. `2c9109e` - fix: use correct SEQ_NUMBER from reverse REL_COMMON for node ordering
2. `73dde4d` - chore: remove temporary debugging and test files

## Status

✅ **COMPLETE** - Ordering fix verified and working correctly
✅ **TESTED** - Confirmed with testorder folder (5, 4, 3, 2, 1 order)
✅ **COMMITTED** - Changes committed to git
✅ **CLEANED UP** - Temporary debugging files removed

## Next Steps

Ready to push to origin/main when you're ready.
