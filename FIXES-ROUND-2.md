# Round 2 Fixes Applied

## Issue Found from First Run

The SQL changes I made in Round 1 **did not apply correctly**. The Edit tool failed to replace the old code because the old_string didn't match exactly. This round applies the fixes correctly.

---

## Issue 1: EngineeringResourceLibrary Icon - NEW FIX

**Problem**: TYPE_ID 164 was using fallback from TYPE_ID 162 (MaterialLibrary), which looks visually identical to TYPE_ID 48 (ResourceLibrary).

**Root Cause**: Both icons came from similar library icon sets in the database.

**NEW Fix Applied**: Changed fallback source from TYPE_ID 162 to TYPE_ID 69 (ShortcutFolder)
- File: [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1:144-150)
- TYPE_ID 164 now copies icon from TYPE_ID 69 instead of 162
- This provides visual distinction between EngineeringResourceLibrary (parent) and ResourceLibrary (child)

---

## Issue 2 & 3: Missing Children - CORRECTLY FIXED NOW

**Problem**: The SQL edit in Round 1 failed to apply. The WHERE clause was not replaced.

**NEW Fix Applied**: Correctly replaced the PART_ extraction WHERE clause
- File: [get-tree-DESIGN12-18140190.sql](get-tree-DESIGN12-18140190.sql:98-134)
- Added Case 2 logic to extract children where parent is in PART_ table

**SQL Logic Now**:
```sql
WHERE NOT EXISTS (SELECT 1 FROM DESIGN12.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND (
    -- Case 1: Parent in COLLECTION_ (original)
    EXISTS (...)
    OR
    -- Case 2: Parent in PART_ and linked to project tree (NEW)
    EXISTS (
      SELECT 1 FROM DESIGN12.PART_ p_parent
      INNER JOIN DESIGN12.REL_COMMON r_parent ON p_parent.OBJECT_ID = r_parent.OBJECT_ID
      WHERE p_parent.OBJECT_ID = r.FORWARD_OBJECT_ID
        AND r_parent.FORWARD_OBJECT_ID IN (project tree)
    )
  )
```

This will now extract:
- PartPrototype children of COWL_SILL_SIDE [18208744]
- CompoundPart and PartPrototype children of PartInstanceLibrary [18143953]

---

## Files Modified (Round 2)

| File | Changes |
|------|---------|
| [get-tree-DESIGN12-18140190.sql](get-tree-DESIGN12-18140190.sql) | Fixed PART_ extraction WHERE clause (lines 98-134) |
| [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1) | Changed TYPE_ID 164 fallback from 162 to 69 (line 144-150) |

---

## Testing Instructions

### Step 1: Regenerate Tree
```powershell
.\src\powershell\main\tree-viewer-launcher.ps1
```

Or directly:
```powershell
.\src\powershell\main\generate-tree-html.ps1 -TNSName "DB01" -Schema "DESIGN12" -ProjectId "18140190" -ProjectName "FORD_DEARBORN"
```

### Step 2: Verify All Three Issues

#### Issue 1: EngineeringResourceLibrary Icon
1. Open [navigation-tree-DESIGN12-18140190.html](navigation-tree-DESIGN12-18140190.html)
2. Look at **FORD_DEARBORN → EngineeringResourceLibrary [18153685]**
3. **Expected**: Icon should look different from its child nodes (robcad_local)
4. **Visual**: Should now show ShortcutFolder icon (folder with arrow) instead of library icon

#### Issue 2: COWL_SILL_SIDE Children
1. Navigate: **PartLibrary → P702 → 01 → CC → COWL_SILL_SIDE [18208744]**
2. **Expected**: Should see 4 PartPrototype child nodes
3. Click to expand COWL_SILL_SIDE

#### Issue 3: PartInstanceLibrary Children
1. Navigate: **FORD_DEARBORN → PartInstanceLibrary [18143953]**
2. **Expected**: Should see CompoundPart and PartPrototype children
3. Click to expand PartInstanceLibrary

---

## Debug Commands (If Still Broken)

If issues persist, run this debug script:
```bash
sqlplus DESIGN12/D3s1gn12@DB01 @check-node-location.sql
```

This will show:
- Where COWL_SILL_SIDE [18208744] exists (COLLECTION_ or PART_)
- What children it has in REL_COMMON
- Where PartInstanceLibrary [18143953] exists
- What children it has in REL_COMMON

---

## What Changed from Round 1

### Round 1 Mistakes:
1. **SQL Edit Failed**: The Edit tool couldn't find the exact old_string, so changes were never applied
2. **Icon Fix Too Subtle**: TYPE_ID 162 and TYPE_ID 48 icons looked too similar

### Round 2 Corrections:
1. **SQL Properly Fixed**: Used correct old_string, changes now applied
2. **Icon More Distinct**: Using TYPE_ID 69 (folder with arrow) instead of TYPE_ID 162 (library icon)

---

Please regenerate the tree and verify all three issues are now resolved!
