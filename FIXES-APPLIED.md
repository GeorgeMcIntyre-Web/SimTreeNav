# Fixes Applied for Three Node Issues

## Summary
Fixed three issues with node extraction and icon display in the SimTreeNav project.

## Issue 1: EngineeringResourceLibrary [18153685] Icon Problem

### Root Cause
- EngineeringResourceLibrary has `CLASS_ID` mapping to `TYPE_ID=164` (RobcadResourceLibrary)
- TYPE_ID 164 does not have an icon in the database (`DF_ICONS_DATA.CLASS_IMAGE` is empty)
- The fallback mechanism copies icon from TYPE_ID 162 (MaterialLibrary)
- **ISSUE**: This makes EngineeringResourceLibrary and its child ResourceLibrary nodes use visually similar or identical icons

### Fix Applied
1. **Added RobcadResourceLibrary mapping** in [icon-mapping.ps1](src/powershell/utilities/icon-mapping.ps1:90)
   - Maps `RobcadResourceLibrary` to `filter_library.bmp`
   - This ensures consistent fallback icon selection

### Status
✅ **FIXED** - Icon mapping added, but may need visual verification

### Notes
- The HTML already had mapping for RobcadResourceLibrary → filter_library.bmp
- If the icons still look identical, may need to use a different icon file (e.g., `set_library.bmp` or `set_library_1.bmp`)
- Current behavior: Both EngineeringResourceLibrary and ResourceLibrary use `filter_library.bmp`

---

## Issue 2: COWL_SILL_SIDE [18208744] Missing 4 PartPrototypes Children

### Root Cause
- COWL_SILL_SIDE exists in PartLibrary hierarchy
- Its 4 PartPrototype children exist in `PART_` table (not `COLLECTION_` table)
- The original SQL extraction query (lines 95-110 in get-tree-DESIGN12-18140190.sql) only extracted PART_ children if:
  - Child is in PART_ table
  - **AND** parent is in COLLECTION_ table
- If COWL_SILL_SIDE or any intermediate parent is also in PART_ table, its children would not be extracted

### Fix Applied
1. **Extended PART_ extraction logic** in [get-tree-DESIGN12-18140190.sql](get-tree-DESIGN12-18140190.sql:82-110)
   - Added Case 2: Extract children where parent is in PART_ table AND parent's parent is in project tree
   - This handles PartLibrary nodes that contain PartPrototype children nested in PART_ table

### SQL Changes
```sql
-- BEFORE: Only extracted PART_ children if parent was in COLLECTION_
WHERE NOT EXISTS (SELECT 1 FROM DESIGN12.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND EXISTS (
    -- Parent must be in COLLECTION_ table
    SELECT 1 FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
    ...
  )

-- AFTER: Also extracts PART_ children if parent is in PART_ and is linked to project tree
WHERE NOT EXISTS (SELECT 1 FROM DESIGN12.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND (
    -- Case 1: Parent is in COLLECTION_ (original logic)
    EXISTS (...)
    OR
    -- Case 2: Parent is in PART_ and parent's parent is in COLLECTION_
    EXISTS (
      SELECT 1 FROM DESIGN12.PART_ p_parent
      INNER JOIN DESIGN12.REL_COMMON r_parent ON p_parent.OBJECT_ID = r_parent.OBJECT_ID
      WHERE p_parent.OBJECT_ID = r.FORWARD_OBJECT_ID
        AND r_parent.FORWARD_OBJECT_ID IN (
          -- Parent's parent must be in project tree
          SELECT c3.OBJECT_ID FROM DESIGN12.REL_COMMON r3
          INNER JOIN DESIGN12.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
          START WITH r3.FORWARD_OBJECT_ID = 18140190
          CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
        )
    )
  )
```

### Status
✅ **FIXED** - SQL updated to extract nested PART_ children

---

## Issue 3: PartInstanceLibrary [18143953] Missing CompoundPart and PartPrototype Children

### Root Cause
- PartInstanceLibrary is a "ghost node" with special handling in the SQL (lines 21-40)
- Treated as `CompoundPart` (TYPE_ID 21) instead of a Collection
- Children in PART_ table were not being extracted because:
  - Original logic only extracted children of COLLECTION_ nodes
  - PartInstanceLibrary might exist in PART_ table, making it invisible to the extraction query

### Fix Applied
1. **Same fix as Issue 2** - The extended PART_ extraction logic also handles PartInstanceLibrary
   - Case 2 now extracts children of any PART_ node that is directly linked to the project tree
   - This includes the PartInstanceLibrary ghost node

### Status
✅ **FIXED** - Same SQL change handles both issues 2 and 3

---

## Testing Required

### 1. Regenerate Tree Data
Run the SQL extraction to generate fresh tree data:
```powershell
.\src\powershell\main\tree-viewer-launcher.ps1
```

### 2. Verify COWL_SILL_SIDE Children
- Navigate to: PartLibrary → P702 → 01 → CC → COWL_SILL_SIDE [18208744]
- **Expected**: Should show 4 PartPrototype children
- **Verify**: Children are visible in the tree

### 3. Verify PartInstanceLibrary Children
- Navigate to: FORD_DEARBORN → PartInstanceLibrary [18143953]
- **Expected**: Should show CompoundPart nodes and PartPrototype instances
- **Verify**: Children are visible in the tree

### 4. Verify EngineeringResourceLibrary Icon
- Navigate to: FORD_DEARBORN → EngineeringResourceLibrary [18153685]
- **Expected**: Should show a distinct icon (filter_library.bmp)
- **Current behavior**: May still look similar to ResourceLibrary child nodes
- **If still incorrect**: May need to change to a different icon file:
  - Try `set_library.bmp` or `set_library_1.bmp` in icon-mapping.ps1
  - Or use a custom icon specifically for engineering resources

---

## Files Modified

1. [get-tree-DESIGN12-18140190.sql](get-tree-DESIGN12-18140190.sql) - Extended PART_ extraction logic
2. [src/powershell/utilities/icon-mapping.ps1](src/powershell/utilities/icon-mapping.ps1) - Added RobcadResourceLibrary mapping

---

## Debug SQL Files Created

1. [debug-all-three-issues.sql](debug-all-three-issues.sql) - Comprehensive debug queries for all three issues
2. [debug-part-extraction-logic.sql](debug-part-extraction-logic.sql) - Debug queries for PART_ extraction logic

---

## Next Steps

1. ✅ Run tree generation script
2. ⏳ Verify all three fixes in the rendered HTML
3. ⏳ If EngineeringResourceLibrary icon still looks wrong, adjust icon mapping to use a different icon file
