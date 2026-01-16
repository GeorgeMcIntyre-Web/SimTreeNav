# PartInstanceLibrary Children Investigation

## Current Status
✅ Icon fixes committed and pushed
✅ P702 and P736 ARE being extracted from database
❌ PartInstanceLibrary shows no expand arrow in tree view
❌ P702 and P736 appear as root-level children instead of under PartInstanceLibrary

## Database Investigation Results

### PartInstanceLibrary (18143953) Relationships
```sql
-- PartInstanceLibrary has MULTIPLE parents:
OBJECT_ID: 18143953
PARENTS:
  - 18140190 (FORD_DEARBORN Project) ✓
  - 18143954 (unknown)
  - 18531240 (P736 - CIRCULAR!)
  - 18209343 (P702 - CIRCULAR!)
```

### P702 and P736 Relationships
```sql
-- P702 (18209343) has MULTIPLE parents:
  - 18143953 (PartInstanceLibrary) ✓
  - 18209344
  - 18209353
  - 18667740

-- P736 (18531240) has MULTIPLE parents:
  - 18143953 (PartInstanceLibrary) ✓
  - 18531245
  - 18531247
  - 18531249
  - 18767129
  - 18531241
```

**FINDING**: This is a BIDIRECTIONAL/CIRCULAR relationship. P702 and P736 are both CHILDREN and PARENTS of PartInstanceLibrary!

## Extraction Status

### In navigation-tree.html:

1. **PartInstanceLibrary appears TWICE:**
   ```
   1|18140190|18143953|PartInstanceLibrary|...     (Level 1 - from hierarchy)
   999|18140190|18143953|PartInstanceLibrary|...   (Level 999 - from PART_ extraction)
   ```

2. **P702 extracted with multiple parents:**
   ```
   999|18143953|18209343|P702|...  (parent=PartInstanceLibrary) ✓
   999|18667740|18209343|P702|...  (parent=18667740)
   999|18209353|18209343|P702|...  (parent=18209353)
   ```

3. **P736 extracted with multiple parents:**
   ```
   999|18143953|18531240|P736|...  (parent=PartInstanceLibrary) ✓
   999|18531249|18531240|P736|...  (parent=18531249)
   999|18531247|18531240|P736|...  (parent=18531247)
   999|18531245|18531240|P736|...  (parent=18531245)
   999|18767129|18531240|P736|...  (parent=18767129)
   ```

## Root Cause

The JavaScript tree builder is showing P702 and P736 at root level because:
1. They have MULTIPLE parent relationships in the database
2. Some of those parent nodes may not be in the extracted tree
3. The tree builder defaults to showing nodes at the highest level where a valid parent exists
4. Since they also appear as children of 18140190 (project) indirectly, they show at root

## Possible Solutions

### Option 1: Filter duplicate parents in SQL
Only extract the FIRST parent relationship (18143953) for these nodes:
```sql
WHERE p.OBJECT_ID IN (18209343, 18531240)
  AND r.FORWARD_OBJECT_ID = 18143953  -- Only PartInstanceLibrary parent
```

### Option 2: Modify JavaScript tree builder
Make it prefer specific parent relationships over others (lowest level parent wins)

### Option 3: Accept current behavior
P702 and P736 showing at root level might be intentional since they have multiple parent relationships. They're accessible from multiple locations in the tree.

## Recommendation

Try **Option 1** first - modify the hardcoded extraction to only get the PartInstanceLibrary parent relationship:

```sql
-- In generate-tree-html.ps1 around line 310
WHERE NOT EXISTS (SELECT 1 FROM $Schema.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND p.OBJECT_ID IN (18208702, 18208714, 18208725, 18208734, 18209343, 18531240)
  AND r.FORWARD_OBJECT_ID IN (18208744, 18143953)  -- Only specific parents
```

This ensures:
- COWL_SILL_SIDE children (18208702, 18208714, 18208725, 18208734) only extracted with parent 18208744
- PartInstanceLibrary children (18209343, 18531240) only extracted with parent 18143953
