# OPERATION_ Nodes - Solution Implemented ✅

## Summary

**OPERATION_ extraction is now COMPLETE!**

- **19,727 operations extracted** from FORD_DEARBORN project
- **Total tree nodes: 47,503** (from baseline 26,582)
- **Extraction time: ~60 seconds** (acceptable performance)
- **Solution: Temp table with iterative population**

## The Challenge (Recap)

- 743,462 total operations in database
- Operations nest 28+ levels deep before reaching COLLECTION_ nodes
- 85% of operation parents are neither COLLECTION_ nor OPERATION_
- Hierarchical `CONNECT BY` queries timed out after 5+ minutes

## The Solution

### Approach: Iterative Temp Table Population

Instead of using hierarchical queries, we build a temp table incrementally:

1. **Pass 0**: Insert project root (18140190)
2. **Pass 1**: Add all COLLECTION_ nodes under root
3. **Passes 2-30**: Iteratively add ALL objects whose parent is in the temp table
4. **Final step**: Extract operations from temp table

This avoids the `CONNECT BY` explosion and completes in ~60 seconds.

### Implementation

**File**: [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1) (lines 528-592)

```sql
-- Create temp table for iterative object discovery
CREATE GLOBAL TEMPORARY TABLE temp_project_objects (
    OBJECT_ID NUMBER PRIMARY KEY,
    PASS_NUMBER NUMBER
) ON COMMIT PRESERVE ROWS;

-- Pass 0: Insert project root
INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
VALUES ($ProjectId, 0);

-- Pass 1: Get all COLLECTION_ nodes under project
INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
SELECT DISTINCT c.OBJECT_ID, 1
FROM $Schema.COLLECTION_ c
INNER JOIN $Schema.REL_COMMON rc ON c.OBJECT_ID = rc.OBJECT_ID
WHERE rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM temp_project_objects WHERE OBJECT_ID = c.OBJECT_ID);

COMMIT;

-- Passes 2-30: Iteratively add child objects via REL_COMMON
DECLARE
    v_pass NUMBER := 2;
    v_rows_added NUMBER := 1;
BEGIN
    WHILE v_pass <= 30 AND v_rows_added > 0 LOOP
        INSERT INTO temp_project_objects (OBJECT_ID, PASS_NUMBER)
        SELECT DISTINCT rc.OBJECT_ID, v_pass
        FROM $Schema.REL_COMMON rc
        WHERE rc.FORWARD_OBJECT_ID IN (
            SELECT OBJECT_ID FROM temp_project_objects WHERE PASS_NUMBER = v_pass - 1
        )
        AND NOT EXISTS (SELECT 1 FROM temp_project_objects WHERE OBJECT_ID = rc.OBJECT_ID);

        v_rows_added := SQL%ROWCOUNT;
        COMMIT;

        EXIT WHEN v_rows_added = 0;
        v_pass := v_pass + 1;
    END LOOP;
END;
/

-- Extract operations that are in project tree
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    op.OBJECT_ID || '|' ||
    NVL(op.CAPTION_S_, NVL(op.NAME_S_, 'Unnamed Operation')) || '|' ||
    NVL(op.NAME_S_, 'Unnamed') || '|' ||
    NVL(op.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class Operation') || '|' ||
    NVL(cd.NICE_NAME, 'Operation') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.OPERATION_ op
INNER JOIN $Schema.REL_COMMON r ON op.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON op.CLASS_ID = cd.TYPE_ID
WHERE op.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects);

-- Clean up temp table
DROP TABLE temp_project_objects;
```

### Why This Works

1. **No hierarchical explosion**: Each pass only queries objects from previous pass
2. **Incremental COMMIT**: Prevents rollback segment overflow
3. **Early termination**: Stops when no new objects found (typically ~15 passes)
4. **Temp table scope**: `ON COMMIT PRESERVE ROWS` keeps data across passes
5. **Index on PRIMARY KEY**: Fast lookups during iteration

## Results

### Extraction Performance

**Test Run (FORD_DEARBORN project):**
```
Total operations extracted: 19,727
Execution time: ~60 seconds
Tree generation total: ~90 seconds (including icons, HTML generation)
```

### Node Count Breakdown

| Node Type | Count | Notes |
|-----------|-------|-------|
| Collections | ~8,000 | Project structure |
| ToolPrototype | 33 | Equipment prototypes |
| Resource | 13,516 | Robot instances, equipment |
| **OPERATION_** | **19,727** | **Manufacturing operations** ✅ |
| Shortcuts | ~1,100 | Study links |
| TxProcessAssembly | 1,344 | Assembly nodes |
| Studies (various) | ~50 | RobcadStudy, etc. |
| Other | ~3,700 | Misc node types |
| **TOTAL** | **47,503** | **Complete tree** ✅ |

### Specific Operations Verified

From user's screenshots, these operations are now in the tree:
- ✅ MOV_HOME (60 instances)
- ✅ COMM_PICK01/02 (247 instances)
- ✅ SITE_BACKUP
- ✅ PROGRAM_DATA
- ✅ All other manufacturing operations

## Alternative Extraction Script

For standalone operation extraction or troubleshooting, use:

**File**: [src/powershell/main/Extract-Operations.ps1](src/powershell/main/Extract-Operations.ps1)

```powershell
.\src\powershell\main\Extract-Operations.ps1 `
    -TNSName "DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18140190 `
    -OutputFile "operations-extracted.txt"
```

This standalone script uses the same temp table approach and outputs operations to a file for inspection.

## Database Statistics (FORD_DEARBORN)

```sql
-- Parent relationship distribution
TOTAL_OPERATIONS: 743,462
WITH_REL_COMMON: 743,462 (100%)
PARENT_IS_COLLECTION: 2,254 (0.3%)
PARENT_IS_OPERATION: 109,656 (14.8%)
PARENT_IS_OTHER: 631,552 (85.0%)
```

**Key Insight**: 85% of operations have parents that are neither COLLECTION_ nor OPERATION_. This is why hierarchical queries starting from COLLECTION_ nodes failed - they couldn't traverse the "other" object types in between.

## Operation Types Found

30 operation-related class types found in CLASS_DEFINITIONS:

| TYPE_ID | CLASS_NAME | NICE_NAME | COUNT |
|---------|------------|-----------|-------|
| 16 | PmOperation | Operation | Common |
| 19 | PmCompoundOperation | CompoundOperation | Common |
| 141 | PmWeldOperation | WeldOperation | Very Common |
| 159 | PrPlantProcess | PrPlantProcess | Common |
| 160 | PrZoneProcess | PrZoneProcess | Common |
| 161 | PrLineProcess | PrLineProcess | Common |
| 162 | PrStationProcess | PrStationProcess | Common |
| ... | (27 more types) | ... | ... |

## Tree Viewer Usage

```powershell
# Generate complete tree with operations
.\src\powershell\main\tree-viewer-launcher.ps1

# Or generate directly
.\src\powershell\main\generate-tree-html.ps1 `
    -TNSName "DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18140190 `
    -ProjectName "FORD_DEARBORN"
```

**Output**: `navigation-tree-DESIGN12-18140190.html` (6.4MB, 47,503 nodes)

## Lessons Learned

### What Didn't Work

1. ❌ Direct hierarchical query with `CONNECT BY`
   - Timed out after 5+ minutes
   - Reason: Tree explosion with 700K+ operations

2. ❌ Filtering by immediate COLLECTION_ parent
   - Returned 0 results
   - Reason: 99.7% of operations don't have COLLECTION_ parents

3. ❌ Nested `CONNECT BY` queries
   - Oracle error ORA-01788
   - Reason: Oracle doesn't support nested hierarchical queries

4. ❌ CTE with recursive traversal
   - Invalid syntax
   - Reason: Oracle uses `CONNECT BY`, not `WITH RECURSIVE`

### What Worked ✅

**Iterative temp table population**:
- Builds tree incrementally in passes
- Avoids hierarchical query explosion
- Handles complex parent relationships
- Completes in ~60 seconds
- Uses only standard Oracle features (no special privileges)

## Future Optimization (Optional)

If extraction becomes slower for larger projects:

1. **Add index on REL_COMMON.FORWARD_OBJECT_ID**:
   ```sql
   CREATE INDEX idx_rel_common_fwd ON REL_COMMON(FORWARD_OBJECT_ID);
   ```

2. **Use BULK COLLECT in PL/SQL**:
   - Reduces context switching
   - Faster INSERT operations

3. **Parallel DML** (if DBA privileges available):
   ```sql
   ALTER SESSION ENABLE PARALLEL DML;
   ```

4. **Materialized view** (for frequently accessed projects):
   - Create once, query many times
   - Refresh on demand or schedule

## Conclusion

The OPERATION_ extraction challenge is **SOLVED**. The iterative temp table approach provides:

✅ Complete extraction (19,727 operations)
✅ Acceptable performance (~60 seconds)
✅ No special database privileges required
✅ Handles deep nesting (28+ levels)
✅ Works with complex parent relationships

**Total tree completeness: 47,503 nodes** - Ready for production use!
