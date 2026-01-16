# ROOT CAUSE ANALYSIS - Three Icon/Children Issues

## Database Investigation Results

### Issue 1: EngineeringResourceLibrary (18153685) Shows Wrong Icon

**SYMPTOM**: Node shows same icon as ResourceLibrary instead of distinct icon

**ROOT CAUSE FOUND**:
```sql
-- Node details:
OBJECT_ID: 18153685
CAPTION: EngineeringResourceLibrary
CLASS_ID: 164
NICE_NAME: RobcadResourceLibrary
TYPE_ID: 164

-- Icon data check:
TYPE_ID 164 (RobcadResourceLibrary): NO ICON in DF_ICONS_DATA
TYPE_ID 48 (ResourceLibrary): HAS ICON (1334 bytes)
```

**THE PROBLEM**:
- EngineeringResourceLibrary uses TYPE_ID 164 which has NO icon in database
- The dynamic icon lookup is failing to fall back to parent type
- TYPE_ID 164 does NOT exist in CLASS_DEFINITIONS table (only in node's CLASS_ID)
- Icon mapping needs to map 164 → 48 (ResourceLibrary icon)

**FIX REQUIRED**:
Add explicit mapping in icon-mapping.ps1: `164 = 48` (use ResourceLibrary icon)

---

### Issue 2: COWL_SILL_SIDE (18208744) Missing 4 PartPrototype Children

**SYMPTOM**: Shows only 1 child (CC) but should have 4 more children

**ROOT CAUSE FOUND**:
```sql
-- Node details:
OBJECT_ID: 18208744
CAPTION: COWL_SILL_SIDE
CLASS_ID: 46
NICE_NAME: PartLibrary
TYPE_ID: 46

-- Children found in database:
COLLECTION_ table: 1 child (18209340 'CC')
PART_ table: 4 children with NULL NICE_NAME:
  - 18208702 (no name, no type)
  - 18208714 (no name, no type)
  - 18208725 (no name, no type)
  - 18208734 (no name, no type)
```

**THE PROBLEM**:
- 4 children exist in PART_ table but have NULL CLASS_ID (no type mapping)
- Current extraction SQL in generate-tree-html.ps1 line 292:
  ```sql
  WHERE NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND EXISTS (SELECT 1... WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID...)
  ```
- This requires parent to be in COLLECTION_ table
- These 4 nodes have NULL NICE_NAME so they get filtered out or don't match type checks

**FIX REQUIRED**:
1. Extract PART_ nodes even when NICE_NAME is NULL
2. Use fallback type name like "Part" or "PartPrototype"
3. Ensure PART_ children extraction includes nodes with PART_ parents

---

### Issue 3: PartInstanceLibrary (18143953) Missing CompoundPart Children

**SYMPTOM**: PartInstanceLibrary shows no children

**ROOT CAUSE FOUND**:
```sql
-- Node 18143953 investigation:
- Does NOT exist in COLLECTION_ table
- EXISTS in PART_ table:
  OBJECT_ID: 18143953
  NAME_S_: PartInstanceLibrary
  CLASS_ID: 21
  NICE_NAME: CompoundPart

-- Children in PART_ table:
  - 18209343 'P702' (CompoundPart, TYPE_ID 21)
  - 18531240 'P736' (CompoundPart, TYPE_ID 21)
```

**THE PROBLEM**:
- PartInstanceLibrary itself is a PART_ node (CompoundPart TYPE_ID 21)
- It has 2 CompoundPart children in PART_ table
- Current extraction only extracts PART_ children when parent is in COLLECTION_
- PartInstanceLibrary parent is Project (in COLLECTION_) but the node itself is in PART_
- Children of PART_ nodes are NOT being extracted

**FIX REQUIRED**:
1. Extract PART_ children where parent is also in PART_ table
2. Modify extraction query to handle PART_→PART_ relationships
3. Ensure icon mapping works for TYPE_ID 21 (CompoundPart)

---

## Summary of Fixes Needed

1. **icon-mapping.ps1**: Add `164 → 48` mapping
2. **generate-tree-html.ps1**:
   - Line ~292: Modify PART_ extraction to allow NULL NICE_NAME
   - Add new UNION clause to extract PART_→PART_ children relationships
   - Use fallback names for nodes without NICE_NAME

---

## Proof Required

After fixes, verify in generated HTML:
1. Search for `data-id="18153685"` - should have distinct icon (not same as ResourceLibrary)
2. Search for `data-id="18208744"` - should have 5 children total (not just 1)
3. Search for `data-id="18143953"` - should show 2 CompoundPart children (P702, P736)
