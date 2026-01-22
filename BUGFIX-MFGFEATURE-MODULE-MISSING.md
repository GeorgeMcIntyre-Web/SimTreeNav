# Bug Fix: Missing MFGFEATURE_, MODULE_, and TxProcessAssembly Nodes

## Issue
MFGFEATURE_, MODULE_, and TxProcessAssembly nodes that exist in Process Simulate were not appearing in the generated navigation tree due to incorrect WHERE clause filters.

## Root Cause
Three extraction queries in `generate-tree-html.ps1` were using the wrong WHERE clause condition, checking if the **parent** was in `temp_project_objects` instead of checking if the **object itself** was discovered.

**Incorrect Pattern:**
```sql
WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

This checks the parent (`r.FORWARD_OBJECT_ID`), but the objects themselves were already discovered and added to `temp_project_objects` during iterative population. They just weren't being extracted.

**Correct Pattern (from OPERATION_ query, line 909):**
```sql
WHERE op.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

This checks the object itself, which is the correct approach.

## The Fix

### 1. MFGFEATURE_ Query (line ~928)
**Changed FROM:**
```sql
WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

**Changed TO:**
```sql
WHERE mf.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

### 2. MODULE_ Query (line ~969)
**Changed FROM:**
```sql
WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

**Changed TO:**
```sql
WHERE m.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

### 3. TxProcessAssembly Query (line ~949) - NEW FIX
**Changed FROM:**
```sql
WHERE p.CLASS_ID = 133
  AND r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

**Changed TO:**
```sql
WHERE p.CLASS_ID = 133
  AND p.OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
```

## Why This Works

The `temp_project_objects` table is populated iteratively (passes 0-30) with **ALL** objects in the project tree via REL_COMMON relationships:

```sql
-- Iterative population discovers all objects, regardless of table
SELECT DISTINCT rc.OBJECT_ID, v_pass
FROM REL_COMMON rc
WHERE rc.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects WHERE PASS_NUMBER = v_pass - 1)
```

This includes objects from:
- COLLECTION_ table
- PART_ table (including TxProcessAssembly with CLASS_ID=133)
- OPERATION_ table
- **MFGFEATURE_ table** ✅
- **MODULE_ table** ✅
- And more...

The OPERATION_ query (line 909) was the **reference implementation** using the correct pattern. By aligning MFGFEATURE_, MODULE_, and TxProcessAssembly to this pattern, we ensure consistency and complete extraction.

## Evidence & Testing

### Regression Test
Run the automated regression test to verify the fix:
```powershell
.\test-node-extraction-regression.ps1 -TNSName DESIGN1 -Schema DESIGN1 -ProjectId 20
```

This test:
- Populates `temp_project_objects` identically to the main script
- Compares counts between correct pattern (object check) vs buggy pattern (parent check)
- Verifies extraction queries return expected results
- **Exit code 0 = PASS, 1 = FAIL**

### Coverage Check
View node type counts in the generated tree:
```powershell
.\RUN-COVERAGE-CHECK.ps1 -TNSName DESIGN1 -Schema DESIGN1 -ProjectId 20 -ProjectName "J10735_Mexico"
```

Output example:
```
OPERATION_        : 1344
TxProcessAssembly : 1344
COLLECTION_       : 234
MFGFEATURE_       : 12
MODULE_           : 3
...
TOTAL_DISCOVERED  : 486188
```

### Manual Verification
After applying fix:
1. Regenerate tree: `.\REGENERATE-QUICK.ps1`
2. Launch tree viewer: `.\src\powershell\main\tree-viewer-launcher.ps1`
3. Navigate to nodes (e.g., `Georgem > Imported From Engineering > Module`)
4. Confirm nodes match Process Simulate UI

## Files Modified
- [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1) - Fixed WHERE clauses for MFGFEATURE_, MODULE_, TxProcessAssembly queries with explanatory comments
- [test-node-extraction-regression.ps1](test-node-extraction-regression.ps1) - NEW: Automated regression test
- [RUN-COVERAGE-CHECK.ps1](RUN-COVERAGE-CHECK.ps1) - NEW: Node type coverage diagnostic
- [BUGFIX-MFGFEATURE-MODULE-MISSING.md](BUGFIX-MFGFEATURE-MODULE-MISSING.md) - Updated documentation

## Impact
This fix ensures **complete tree coverage** by correctly extracting MFGFEATURE_, MODULE_, and TxProcessAssembly node types that were previously missing. It also establishes:
- **Regression tests** to prevent future regressions
- **Coverage diagnostics** to validate extraction completeness
- **Guardrails** via explanatory comments referencing the OPERATION_ reference pattern

The fix closes the gap between actual database content and the generated navigation tree, ensuring parity with the Siemens Process Simulate UI.
