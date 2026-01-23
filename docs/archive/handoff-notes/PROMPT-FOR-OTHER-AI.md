# Prompt for Other AI - Complete Icon/Tree Node Fixes

## Context
You've made good progress on icon fixes (commit 1a2e583). The credential system (separate work by Claude Sonnet) is complete and working. We need to finish the icon/tree node work so we can merge both branches.

## Database Info
- **Server:** des-sim-db1
- **Instance:** db01
- **Schema:** DESIGN12
- **Test Project:** FORD_DEARBORN (ID: 18140190)

## What Still Needs to Be Fixed

### 1. ToolPrototype Nodes - NOT in tree
**Problem:** SQL doesn't extract these nodes

**Tables Available:**
- `DESIGN12.TOOLPROTOTYPE_`
- `DESIGN12.TOOLPROTOTYPE_EX`
- `DESIGN12.TOOLPROTOTYPEASPECT_`
- `DESIGN12.TOOLPROTOTYPEASPECT_EX`

**Action Required:**
1. Query `TOOLPROTOTYPE_` table structure to see exact columns
2. Add SQL extraction in `generate-tree-html.ps1` (after ROBCADSTUDY_ query ~line 295)
3. Use pattern similar to existing RobcadStudy extraction

**Example SQL Template (verify columns):**
```sql
-- ToolPrototype nodes
SELECT
    '999|' ||  -- High level
    [parent_column] || '|' ||
    tp.OBJECT_ID || '|' ||
    NVL(tp.[name_column], 'Unnamed Tool') || '|' ||
    NVL(tp.[name_column], 'Unnamed Tool') || '|' ||
    NVL(tp.[external_id_column], '') || '|' ||
    '0|' ||
    NVL(cd.NAME, 'class ToolPrototype') || '|' ||
    NVL(cd.NICE_NAME, 'ToolPrototype') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.TOOLPROTOTYPE_ tp
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON tp.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.COLLECTION_ c
    START WITH c.OBJECT_ID = 18140190
    CONNECT BY NOCYCLE PRIOR c.OBJECT_ID = parent_relation
    WHERE c.OBJECT_ID = [tp.parent_or_object_id]
)
ORDER BY tp.[name_column];
```

### 2. ToolInstance Nodes - NOT in tree
**Problem:** SQL doesn't extract these nodes

**Tables Available:**
- `DESIGN12.TOOLINSTANCEASPECT_`
- `DESIGN12.TOOLINSTANCEASPECT_EX`

**Action Required:**
1. Query `TOOLINSTANCEASPECT_` table structure
2. Add SQL extraction in `generate-tree-html.ps1`
3. Similar pattern to ToolPrototype

### 3. EngineeringResourceLibrary Icon (TYPE_ID 164) - WRONG icon
**Problem:** Node shows but icon is wrong

**Console Output:**
```
[ICON RENDER] Node: "EngineeringResourceLibrary" | Using DATABASE icon (Base64): TYPE_ID 164
```

**Should be:**
```
[ICON RENDER] Node: "EngineeringResourceLibrary" | Using class icon: filter_library.bmp
```

**Files to Fix:**
- `generate-full-tree-html.ps1` - Icon selection logic around line 23161

**Fix Options:**
A. Prefer class icon over DB icon for TYPE_ID 164:
```javascript
if (typeId === 164) {
    iconFile = getIconForClass(className, caption, niceName);
} else if (typeId > 0 && iconDataMap[typeId]) {
    iconFile = `icon_${typeId}.bmp`;
}
```

B. Update icon mapping for `RobcadResourceLibrary` class

### 4. Missing DB Icons - Document
**TYPE_IDs with CLASS_IMAGE length 0:**
- 72 (PmStudyFolder)
- 164 (RobcadResourceLibrary)
- 177 (RobcadStudy)

**Action:**
- Document these in commit message
- Note they require DBA to populate DF_ICONS_DATA
- Fallback icons will be used permanently

## Verification Queries

**Run these first to get table structures:**

```sql
-- Get TOOLPROTOTYPE_ columns
SELECT COLUMN_NAME, DATA_TYPE, NULLABLE, DATA_LENGTH
FROM ALL_TAB_COLUMNS
WHERE TABLE_NAME = 'TOOLPROTOTYPE_'
  AND OWNER = 'DESIGN12'
ORDER BY COLUMN_ID;

-- Get TOOLINSTANCEASPECT_ columns
SELECT COLUMN_NAME, DATA_TYPE, NULLABLE, DATA_LENGTH
FROM ALL_TAB_COLUMNS
WHERE TABLE_NAME = 'TOOLINSTANCEASPECT_'
  AND OWNER = 'DESIGN12'
ORDER BY COLUMN_ID;

-- Sample tool prototype data
SELECT *
FROM DESIGN12.TOOLPROTOTYPE_
WHERE ROWNUM <= 3;

-- Sample tool instance data
SELECT *
FROM DESIGN12.TOOLINSTANCEASPECT_
WHERE ROWNUM <= 3;

-- Verify which tools exist in the test project
SELECT COUNT(*) as TOOL_PROTO_COUNT
FROM DESIGN12.TOOLPROTOTYPE_ tp
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.COLLECTION_ c
    START WITH c.OBJECT_ID = 18140190
    CONNECT BY NOCYCLE PRIOR c.OBJECT_ID = parent_relation
    WHERE c.OBJECT_ID = tp.OBJECT_ID
);
```

## Test Process

1. **Add SQL queries** for tool nodes
2. **Fix TYPE_ID 164 icon** selection
3. **Run launcher:**
   ```powershell
   .\src\powershell\main\tree-viewer-launcher.ps1
   ```
4. **Set custom icon directory** (option 3):
   ```
   C:\Program Files\Tecnomatix_2301.0\eMPower\InitData;C:\tmp\PPRB1_Customization
   ```
5. **Generate tree** for FORD_DEARBORN
6. **Verify in browser:**
   - EngineeringResourceLibrary has correct icon
   - ToolPrototype nodes appear (if any exist in project)
   - ToolInstance nodes appear (if any exist in project)
   - All icons load correctly

## Comprehensive Commit

**When complete, create commit:**

**Title:**
```
feat: Add tool node extraction and fix resource library icon
```

**Body:**
```
Complete tool prototype/instance node extraction and fix icon issues

Node Extraction:
- Add ToolPrototype SQL query to extract tool nodes from TOOLPROTOTYPE_ table
- Add ToolInstance SQL query to extract instances from TOOLINSTANCEASPECT_ table
- Tool nodes now appear in tree hierarchy with correct class types

Icon Fixes:
- Fix EngineeringResourceLibrary (TYPE_ID 164) to use class-specific icon
- Prefer class-based icons over generic DB icons for TYPE_ID 164
- Update icon selection logic in generate-full-tree-html.ps1

Database Investigation:
- TYPE_IDs 72, 164, 177 have CLASS_IMAGE length 0 in DF_ICONS_DATA
- Documented as known missing - require DBA to populate icon data
- Fallback icons (filter_library.bmp, etc.) used as permanent solution

Testing:
- Verified with FORD_DEARBORN project (18140190) on DESIGN12 schema
- Custom icon directories: InitData + PPRB1_Customization
- All node types now visible with correct icons

Related Work:
- Integrates with credential system (separate branch)
- See MERGE-STRATEGY.md for integration plan
- See ICON-TREE-NODE-STATUS.md for detailed status

Files Modified:
- src/powershell/main/generate-tree-html.ps1 (add tool queries)
- src/powershell/main/generate-full-tree-html.ps1 (fix icon logic)

Co-authored-by: Claude Sonnet 4.5 <noreply@anthropic.com>
```

## Success Criteria

✅ ToolPrototype nodes appear in tree (if any exist in project)
✅ ToolInstance nodes appear in tree (if any exist in project)
✅ EngineeringResourceLibrary shows correct icon
✅ No console errors in browser
✅ missing-icons-*-db.txt generated with accurate report
✅ All icons load successfully (no ? icons)
✅ Commit created with comprehensive message

## Questions to Answer

Before you proceed, can you:
1. **Query TOOLPROTOTYPE_ table** and paste column names?
2. **Query TOOLINSTANCEASPECT_ table** and paste column names?
3. **Run the verification query** to see if tool nodes exist in FORD_DEARBORN project?

Once you have this info, you can complete the SQL additions accurately.

---

**Status:** Ready for completion
**Blocked By:** Need table structure queries
**Estimated:** 2-3 hours once table structure known
