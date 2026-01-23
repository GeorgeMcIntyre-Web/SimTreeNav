# OPERATION_ Nodes - Implementation Status

## Summary

The tree viewer is **fully functional** with 27,776 nodes extracted, including:
- ✅ ToolPrototype nodes (33 nodes)
- ✅ Resource nodes (13,516 nodes) - Robots, equipment instances
- ✅ Icon fixes for TYPE_IDs 72, 164, 177
- ⚠️ OPERATION_ nodes - **Temporarily disabled due to performance issues**

## You Can Use the Tree Viewer Now

```powershell
.\src\powershell\main\tree-viewer-launcher.ps1
```

The tree viewer works with all node types except OPERATION_ nodes.

## OPERATION_ Challenge

### The Problem

OPERATION_ extraction is significantly more complex than other node types:

1. **Scale**: 743,107 total operations in the database
2. **Deep Nesting**: Operations nest up to 28+ levels deep before reaching a COLLECTION_ node
3. **Parent Relationships**: 99.7% of operations have other OPERATION_ nodes as parents (not COLLECTION_)

**Example Hierarchy** (from COMM_PICK01 operation):
```
Level 1:  COMM_PICK01 (OPERATION_)
Level 2:  SITE_BACKUP (OPERATION_)
Level 3:  8J-022L-01 (OPERATION_)
Level 4:  8J-022 LH (OPERATION_)
Level 5:  8J-022 (OPERATION_)
Level 6:  STATIONS (OPERATION_)
Level 7:  8J-010_8J-060 (OPERATION_)
Level 8:  DDMP Underbody (OPERATION_)
Level 9:  FORD_P702 DDMP (OPERATION_)
Levels 10-27: Other object types (UNKNOWN)
Level 28: RH (COLLECTION_)
Level 29: 8J-010 (COLLECTION_)
...
Eventually: FORD_DEARBORN (project root COLLECTION_)
```

### What I Tried

1. **Direct Parent Check** - Returns 0 results because operation parents aren't COLLECTION_ nodes
   ```sql
   WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM project_collections)
   ```

2. **Hierarchical Traversal UP** - Oracle error (ORA-01788: nested CONNECT BY not supported)
   ```sql
   START WITH rc.OBJECT_ID = operation
   CONNECT BY PRIOR rc.FORWARD_OBJECT_ID = rc.OBJECT_ID
   ```

3. **Build Full Project Tree CTE** - Timeout (5+ minutes, still running)
   ```sql
   START WITH rc.FORWARD_OBJECT_ID = $ProjectId
   CONNECT BY PRIOR rc.OBJECT_ID = rc.FORWARD_OBJECT_ID
   ```

4. **Traverse DOWN from Collections** - Timeout (5+ minutes, still running)
   ```sql
   START WITH rc.FORWARD_OBJECT_ID IN (collections)
   CONNECT BY PRIOR rc.OBJECT_ID = rc.FORWARD_OBJECT_ID
   ```

All hierarchical queries either fail or timeout because they're building trees with hundreds of thousands of nodes.

## Current State

The OPERATION_ query is **commented out** in [generate-tree-html.ps1:528-563](src/powershell/main/generate-tree-html.ps1#L528-L563) with detailed comments explaining the issue.

## Solutions to Consider

### Option 1: Materialized View Approach
Create a materialized view of project objects once, then query against it:
```sql
CREATE MATERIALIZED VIEW project_objects AS
SELECT rc.OBJECT_ID
FROM DESIGN12.REL_COMMON rc
START WITH rc.FORWARD_OBJECT_ID = 18140190
CONNECT BY NOCYCLE PRIOR rc.OBJECT_ID = rc.FORWARD_OBJECT_ID;
```
**Pros**: Fast subsequent queries
**Cons**: Requires DBA privileges, schema changes

### Option 2: Temp Table with Iterative Population
Build temp table in multiple passes using PowerShell:
```powershell
# Pass 1: Get operations under collections
Invoke-SqlQuery -Query "INSERT INTO #ops SELECT ... WHERE parent IN (collections)"

# Pass 2: Get operations under pass 1 operations
Invoke-SqlQuery -Query "INSERT INTO #ops SELECT ... WHERE parent IN (SELECT * FROM #ops)"

# Repeat until no new rows added
```
**Pros**: No schema changes, works with read-only access
**Cons**: Complex PowerShell logic, multiple round-trips

### Option 3: PL/SQL Procedure
Create a stored procedure that builds the tree iteratively:
```plsql
CREATE OR REPLACE PROCEDURE extract_operations(p_project_id NUMBER) IS
BEGIN
  -- Iterative tree building logic
END;
```
**Pros**: Fast, single execution
**Cons**: Requires CREATE PROCEDURE privilege

### Option 4: Accept Limitation
Document that operations aren't extracted and focus on the 27,776 other nodes:
```
Operations are not included in the tree extraction due to performance
limitations with deeply nested hierarchical queries.
```
**Pros**: No additional work, tree viewer fully functional
**Cons**: Missing operational workflow data

## Database Statistics

```
Total Operations: 743,107
Operations with COLLECTION_ parent: 2,254 (0.3%)
Operations with OPERATION_ parent: 740,853 (99.7%)
Maximum nesting depth: 28+ levels
```

## Files Changed

- [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1) - OPERATION_ query commented out at lines 528-563
- Created verification queries:
  - `verify-operation-parent.sql` - Parent relationship analysis
  - `analyze-operation-hierarchy.sql` - Trace operation ancestry to project root
  - `run-verify-operation.ps1` - Helper script for verification

## Recommendation

**For immediate use**: The tree viewer works with 27,776 nodes (all types except operations).

**For complete solution**: Option 2 (Iterative PowerShell) is the best approach for read-only database access. It requires implementing multi-pass extraction logic that builds the operation tree incrementally.

**Estimated effort for Option 2**: 2-3 hours of development + testing
