# CRITICAL FIX: MFGFEATURE_ Column Name Error

## Date
2026-01-20 14:45

## Severity
**CRITICAL** - This bug caused 0 MODULE_ nodes to appear in tree despite query being correct

## Root Cause

The MFGFEATURE_ query in [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1) used the wrong column name:

**INCORRECT (lines 916-917):**
```sql
NVL(mf.NAME_S_, 'Unnamed') || '|' ||
NVL(mf.NAME_S_, 'Unnamed') || '|' ||
```

**Problem:** MFGFEATURE_ table uses `NAME1_S_` column, NOT `NAME_S_`

**SQL Error:** `ORA-00904: "MF"."NAME_S_": invalid identifier`

## Why This Broke MODULE_ Nodes

The MFGFEATURE_ query is part of a UNION ALL chain:

```sql
-- Line 912-928: MFGFEATURE_ query (HAD ERROR)
SELECT DISTINCT ... FROM MFGFEATURE_ ...
UNION ALL
-- Line 932-948: TxProcessAssembly query
SELECT ... FROM PART_ ...
UNION ALL
-- Line 952-967: MODULE_ query (CORRECT BUT NEVER EXECUTED)
SELECT ... FROM MODULE_ ...;
```

**Critical Issue:**
- When ANY part of a UNION ALL has a SQL error, the ENTIRE query fails
- MFGFEATURE_ error caused SQL*Plus to return 0 rows for the entire UNION ALL
- MODULE_ query was correct but never produced output
- Result: 0 MODULE_ nodes, 0 MFGFEATURE_ nodes in generated tree

## Investigation Path

1. **Initial symptom:** MODULE_ nodes missing (ST010_ZB_Li_Re_TLC not found)
2. **First fix:** Added MODULE_ query (lines 949-967) ✓
3. **Second fix:** Changed MODULE_ to use NAME1_S_ instead of NAME_S_ ✓
4. **Regeneration attempt:** Still 0 MODULE_ nodes despite fixes being correct
5. **Deep investigation:** Created debug scripts to test temp_project_objects population
6. **Breakthrough:** Standalone MODULE_ query worked perfectly (returned 3 nodes)
7. **Root cause:** Tested full UNION ALL chain and found MFGFEATURE_ error
8. **Discovery:** MFGFEATURE_ also uses NAME1_S_ (not NAME_S_)

## Database Schema Confirmation

```sql
SQL> DESC DESIGN1.MFGFEATURE_;

NAME1_S_          VARCHAR2(1024)  -- CORRECT column
CAPTION_S_        VARCHAR2(1024)  -- Alternative column
-- NAME_S_ does NOT exist
```

Similar schema to MODULE_:
- Both use NAME1_S_ (not NAME_S_)
- Both have CAPTION_S_ as alternative
- Both have EXTERNALID_S_

## Fix Applied

**File:** [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
**Lines:** 916-918

**CORRECTED:**
```sql
-- Add MFGFEATURE_ nodes (weld points, fixtures, etc.) linked to project tree
-- MFGFEATURE_ table uses NAME1_S_ column (not NAME_S_)
SELECT DISTINCT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    mf.OBJECT_ID || '|' ||
    COALESCE(mf.CAPTION_S_, mf.NAME1_S_, 'Unnamed') || '|' ||
    COALESCE(mf.CAPTION_S_, mf.NAME1_S_, 'Unnamed') || '|' ||
    NVL(mf.EXTERNALID_S_, '') || '|' ||
    ...
```

**Changes:**
1. Changed `NVL(mf.NAME_S_, 'Unnamed')` → `COALESCE(mf.CAPTION_S_, mf.NAME1_S_, 'Unnamed')`
2. Added comment documenting NAME1_S_ requirement
3. Used COALESCE for consistent pattern with MODULE_ query

## Testing

### Standalone Test
```sql
-- test-union-all-with-module.sql
-- Tests the full MFGFEATURE+TxProcessAssembly+MODULE UNION ALL

RESULT BEFORE FIX:
ORA-00904: "MF"."NAME_S_": invalid identifier
0 rows returned

RESULT AFTER FIX:
Expected to return MFGFEATURE nodes + 3 MODULE nodes including ST010_ZB_Li_Re_TLC
```

### Full Regeneration
```powershell
# REGENERATE-WITH-MFGFEATURE-FIX.ps1
# - Clears cache
# - Verifies both MFGFEATURE_ and MODULE_ fixes
# - Runs generation
# - Checks for MODULE_ nodes in output
```

## Expected Outcome

After this fix:
- ✓ MFGFEATURE_ query executes without error
- ✓ UNION ALL completes successfully
- ✓ MODULE_ nodes appear in tree (3 nodes expected)
- ✓ ST010_ZB_Li_Re_TLC appears (OBJECT_ID: 993062)
- ✓ MfgFeature nodes also appear

## Lessons Learned

1. **Column naming inconsistency**: Different tables use different column names (NAME_S_ vs NAME1_S_)
2. **UNION ALL error propagation**: SQL error in one query breaks entire UNION ALL chain
3. **Testing isolation**: Test each UNION ALL component separately to catch errors
4. **Silent failures**: SQL*Plus may not show clear error messages when used via PowerShell
5. **Cache masking**: Cache can hide SQL errors - always test with cache cleared

## Related Issues

- **FIX-MODULE-NODES.md** - Initial MODULE_ query addition
- **FIX-MODULE-COLUMN-NAME.md** - MODULE_ NAME1_S_ fix
- **FINDINGS-MISSING-NODES.md** - Original investigation

## Files Modified

- [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1) (lines 911-928)

## Files Created

- REGENERATE-WITH-MFGFEATURE-FIX.ps1
- FIX-MFGFEATURE-COLUMN-NAME.md (this file)
- describe-mfgfeature.sql
- test-union-all-with-module.sql

## Next Steps

1. Run REGENERATE-WITH-MFGFEATURE-FIX.ps1
2. Verify MODULE_ nodes appear
3. Check for any other tables using NAME1_S_ pattern
4. Consider creating schema validation script

## Technical Notes

**Why COALESCE instead of NVL?**
- COALESCE can handle multiple fallback values
- Pattern: COALESCE(CAPTION_S_, NAME1_S_, 'default')
- More readable than nested NVL
- Consistent with MODULE_ query fix

**Why NAME1_S_?**
- Siemens Process Simulate schema uses NAME1_S_ for certain object types
- CAPTION_S_ is preferred display name when available
- NAME1_S_ is fallback identifier
