# MODULE_ Nodes Missing - Fix Applied

**Date**: 2026-01-20
**Issue**: Module type nodes (like ST010_ZB_Li_Re_TLC) completely missing from tree
**Root Cause**: No SQL query for MODULE_ table

---

## Problem Identified

**Specific Missing Node**:
- **Name**: ST010_ZB_Li_Re_TLC
- **Type**: Module
- **OBJECT_ID**: 993062
- **External ID**: PP-DESIGN1-11-5-2024-8-45-9-20-993062
- **Visible in**: Siemens Process Simulate UI (BMW DESIGN1 schema)
- **Missing from**: Generated navigation tree

---

## Root Cause

The `MODULE_` table exists in the database but **no UNION ALL query** includes it in [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1).

**Evidence**:
- Database has MODULE_ table (confirmed from screenshot)
- `grep -c "Module" tree-data-DESIGN1-20-clean.txt` returns **0**
- Node 993062 not found in generated tree file
- `grep MODULE_ generate-tree-html.ps1` returns no SQL queries

**Impact**: ALL Module type nodes are missing from the tree across all schemas.

---

## Solution Applied

### Added MODULE_ Query

**Location**: [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1) line 949-967

**New Query Added**:
```sql
UNION ALL
-- Add MODULE_ nodes (modules/subassemblies in the tree structure)
-- Module nodes are stored in MODULE_ table and can have various parent types
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    m.OBJECT_ID || '|' ||
    NVL(m.NAME_S_, 'Unnamed Module') || '|' ||
    NVL(m.NAME_S_, 'Unnamed Module') || '|' ||
    NVL(m.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmModule') || '|' ||
    NVL(cd.NICE_NAME, 'Module') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.MODULE_ m ON r.OBJECT_ID = m.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON m.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM temp_project_objects)
  AND NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = m.OBJECT_ID);
```

**Why This Works**:
- Query runs BEFORE temp_project_objects is dropped (line 970)
- Uses temp_project_objects for parent validation (includes all reachable nodes)
- Excludes MODULE_ nodes that also exist in COLLECTION_ (avoids duplicates)
- Follows same pattern as TxProcessAssembly, MFGFEATURE_, etc.

---

## Testing Instructions

### Step 1: Clear Cache and Regenerate

```powershell
cd c:\Users\georgem\source\repos\cursor\SimTreeNav

# Clear BMW cache
Remove-Item tree-cache-DESIGN1-*.txt -ErrorAction SilentlyContinue
Remove-Item tree-data-DESIGN1-*-clean.txt -ErrorAction SilentlyContinue

# Regenerate BMW tree
.\src\powershell\main\tree-viewer-launcher.ps1
# Or directly:
.\src\powershell\main\generate-tree-html.ps1 `
    -TNSName "DES_SIM_DB2_BMW01" `
    -Schema "DESIGN1" `
    -ProjectId 20 `
    -ProjectName "J10735_Mexico"
```

### Step 2: Verify Module Nodes Appear

```powershell
# Count Module nodes in tree
grep -c "Module" tree-data-DESIGN1-20-clean.txt

# Search for specific missing node
.\src\powershell\debug\find-specific-node.ps1 `
    -Schema DESIGN1 `
    -ProjectId 20 `
    -SearchTerm "ST010_ZB_Li_Re_TLC"
```

**Expected Results**:
- Module count: **> 0** (was 0 before)
- ST010_ZB_Li_Re_TLC: **FOUND** (was NOT FOUND before)
- Node should show proper parent and level

### Step 3: Visual Verification

```powershell
# Open tree in browser
start navigation-tree-DESIGN1-20.html

# In browser, search for: ST010_ZB_Li_Re_TLC
# Should find the node with proper hierarchy
```

---

## Expected Impact

### Before Fix
- Module nodes: **0**
- ST010_ZB_Li_Re_TLC: **Missing**
- All MODULE_ table entries: **Missing**

### After Fix
- Module nodes: **Hundreds or thousands** (depends on schema)
- ST010_ZB_Li_Re_TLC: **Present with proper hierarchy**
- All MODULE_ table entries: **Included**

### Performance Impact
- **Minimal** - just one more table join
- Query runs before temp table drop, so it's fast
- Uses indexed OBJECT_ID columns

---

## Other Missing Tables?

Based on the screenshot showing database tables, we should verify these are queried:

**Tables Currently Queried** ✅:
- COLLECTION_
- PART_
- OPERATION_
- RESOURCE_
- ROBCADSTUDY_
- LINESIMULATIONSTUDY_
- GANTTSTUDY_
- SIMPLEDETAILEDSTUDY_
- LOCATIONALSTUDY_
- MFGFEATURE_
- TOOLPROTOTYPE_
- TOOLINSTANCEASPECT_
- STUDYCONFIGURATION_
- PARTPROTOTYPE_
- SHORTCUT_
- TxProcessAssembly (via PART_ with CLASS_ID filter)
- **MODULE_** ✅ (just added)

**Tables Visible in Screenshot** (may need investigation):
- NODE_ / NODE_EX
- MODULE_EX
- MATERIALFLOW_ / MATERIALFLOW_EX
- MEMBER_ARGS / MEMBER_DEFINITIONS
- OPERATIONINSTANCE / OPERATIONINSTANCE_EX
- OPERATIONROUTE_ / OPERATIONROUTE_EX
- And many more...

**Recommendation**: Check if NODE_ table should also be queried.

---

## Files Modified

1. [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
   - Added MODULE_ query (lines 949-967)

---

## Related Issues

This fix is **complementary** to the orphan node fix:
- Orphan fix: Included nodes whose parents were PART_ nodes
- MODULE_ fix: Includes entire table type that was completely missing

**Both fixes needed** for complete tree coverage!

---

## Rollback

If issues occur with MODULE_ nodes:

```powershell
# Remove the MODULE_ UNION ALL block (lines 949-967)
# Or comment it out:
-- UNION ALL
-- Add MODULE_ nodes...
-- (comment out entire block)
```

---

**Status**: ✅ FIX APPLIED - READY FOR TESTING
**Breaking Changes**: ❌ NONE - Only adds missing nodes
**Confidence**: 🟢 HIGH - Simple table query addition

---

**Next Steps**:
1. ✅ Fix applied
2. ⏳ Regenerate DESIGN1 tree
3. ⏳ Verify ST010_ZB_Li_Re_TLC appears
4. ⏳ Check NODE_ table usage
5. ⏳ Document all table types included
