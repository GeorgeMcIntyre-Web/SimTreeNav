# Icon/Tree Node Fixes - Current Status & Next Steps

## Summary from Other AI (Codex/Claude Work)

### ✅ Completed So Far
1. **Custom Icon Loading** - Added recursive icon loading from:
   - `data/icons`
   - `C:\Program Files\Tecnomatix_2301.0\eMPower\InitData`
   - `C:\tmp\PPRB1_Customization`
   - Via semicolon-separated `-CustomIconDir` parameter

2. **Missing Icon Logic** - Skip DB icons when `DF_ICONS_DATA` has no `CLASS_IMAGE`

3. **Improved Reporting** - Generate:
   - `missing-icons-<schema>-<project>.txt` - Missing TYPE_IDs in tree
   - `missing-icons-<schema>-<project>-db.txt` - DB verification results

4. **Launcher Menu** - Added option 3 to set/persist custom icon directory

5. **HTML Corruption Fix** - Fixed placeholder injection order

6. **Commit Created** - `1a2e583` ("Improve icon selection for missing DB icons")

### ❌ Still Broken
1. **EngineeringResourceLibrary** (Node 18153685, TYPE_ID 164)
   - Shows wrong icon
   - Console says: `[ICON RENDER] Node: "EngineeringResourceLibrary" | Using DATABASE icon (Base64): TYPE_ID 164`
   - Should use class-specific icon instead

2. **ToolPrototype Nodes** - NOT appearing in tree
   - Table exists: `TOOLPROTOTYPE_` and `TOOLPROTOTYPE_EX`
   - SQL query doesn't extract them
   - Need to add extraction query

3. **ToolInstance Nodes** - NOT appearing in tree
   - Table exists: `TOOLINSTANCEASPECT_` and `TOOLINSTANCEASPECT_EX`
   - SQL query doesn't extract them
   - Need to add extraction query

4. **Missing DB Icons** - TYPE_IDs 72, 164, 177 show `CLASS_IMAGE length 0`

## Database Schema Info

**Connection:**
- Server: `des-sim-db1`
- Instance: `db01`
- Schema: `DESIGN12`
- Test Project: `FORD_DEARBORN` (ID: 18140190)

**Available Tables (from SQL Developer screenshots):**

### Tool-Related Tables
- `TOOLPROTOTYPE_` / `TOOLPROTOTYPE_EX`
- `TOOLPROTOTYPEASPECT_` / `TOOLPROTOTYPEASPECT_EX`
- `TOOLINSTANCEASPECT_` / `TOOLINSTANCEASPECT_EX`

### Part-Related Tables
- `PARTPROTOTYPE_` / `PARTPROTOTYPE_EX`
- `PARTPROTOTYPEASPECT_` / `PARTPROTOTYPEASPECT_EX`
- `PARTINSTANCEASPECT_` / `PARTINSTANCEASPECT_EX`

### Other Important Tables
- `RESOURCE_` / `RESOURCE_EX`
- `ROBOTICPROGRAM` / `ROBOTICPROGRAM_EX`
- `OPERATION_` / `OPERATION_EX`
- `SECONDARY_EXTERNAL_ID` - Links external IDs
- `SEMANTICQUERY_` - Semantic queries

### Core Tables (Already Used)
- `COLLECTION_` / `COLLECTION_EX` ✅ Already queried
- `REL_COMMON` ✅ Already queried
- `CLASS_DEFINITIONS` ✅ Already queried
- `DF_ICONS_DATA` ✅ Already queried
- `ROBCADSTUDY_` ✅ Already added

## Required SQL Additions

### 1. ToolPrototype Extraction
Add after RobcadStudy query (~line 295+ in `generate-tree-html.ps1`):

```sql
-- ToolPrototype nodes (tools like robots, grippers, etc.)
SELECT
    '999|' ||  -- High level, JavaScript handles
    tp.OBJECT_ID || '|' ||  -- Parent is the OBJECT_ID
    tp.OBJECT_ID || '|' ||  -- This node's ID
    NVL(tp.NAME_S_, 'Unnamed Tool') || '|' ||
    NVL(tp.NAME_S_, 'Unnamed Tool') || '|' ||
    NVL(tp.EXTERNALID_S_, '') || '|' ||
    '0|' ||  -- SEQ_NUMBER (tools don't have specific order)
    NVL(cd.NAME, 'class ToolPrototype') || '|' ||
    NVL(cd.NICE_NAME, 'ToolPrototype') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.TOOLPROTOTYPE_ tp
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON tp.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    -- Only include if belongs to project tree
    SELECT 1 FROM $Schema.COLLECTION_ c
    START WITH c.OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR c.OBJECT_ID = parent_in_rel_common
    WHERE c.OBJECT_ID = tp.OBJECT_ID
)
ORDER BY tp.NAME_S_;
```

**Note:** Need to verify exact column names. From `SECONDARY_EXTERNAL_ID` screenshot, I see:
- `OBJECT_ID` - INTEGER(10,0)
- `PROJECT_ID` - INTEGER(10,0)
- `EXTERNAL_ID` - VARCHAR2(1024 BYTE)
- `CONTEXT_NAME` - VARCHAR2(1024 BYTE)

From `SEMANTICQUERY_` screenshot, I see columns like:
- `OBJECT_VERSION_ID`
- `OBJECT_ID`
- `CLASS_ID`
- `MODIFIED`

We need to query `TOOLPROTOTYPE_` to see exact column structure.

### 2. ToolInstance Extraction
```sql
-- ToolInstance nodes (instances of tool prototypes)
SELECT
    '999|' ||
    ti.PARENT_ID || '|' ||  -- Parent object
    ti.OBJECT_ID || '|' ||
    NVL(ti.NAME_S_, 'Unnamed Tool Instance') || '|' ||
    NVL(ti.NAME_S_, 'Unnamed Tool Instance') || '|' ||
    NVL(ti.EXTERNALID_S_, '') || '|' ||
    '0|' ||
    NVL(cd.NAME, 'class ToolInstance') || '|' ||
    NVL(cd.NICE_NAME, 'ToolInstance') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.TOOLINSTANCEASPECT_ ti
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON ti.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM $Schema.COLLECTION_ c
    START WITH c.OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR c.OBJECT_ID = parent_relation
    WHERE c.OBJECT_ID = ti.PARENT_ID
)
ORDER BY ti.NAME_S_;
```

## Icon Fix Strategy

### For TYPE_ID 164 (EngineeringResourceLibrary)
Current problem: Using DB icon (which might be generic) instead of class-specific icon

**In `generate-full-tree-html.ps1`:**
```javascript
// Around line 23161+ (icon selection logic)
if (typeId === 164 && iconDataMap[typeId]) {
    // RobcadResourceLibrary - check if DB icon is generic
    // If so, prefer class-specific icon
    iconFile = getIconForClass(className, caption, niceName);
    console.log(`[ICON DEBUG] Node: "${caption}" | TYPE_ID: ${typeId} | Using class icon: ${iconFile}`);
} else if (typeId > 0 && iconDataMap[typeId]) {
    const dbIconFile = `icon_${typeId}.bmp`;
    iconFile = dbIconFile;
    // ... rest of logic
}
```

**OR** in icon mapping, ensure `RobcadResourceLibrary` maps to correct BMP:
```javascript
'RobcadResourceLibrary': 'filter_library.bmp',  // Or correct icon name
```

### For Missing DB Icons (TYPE_IDs 72, 164, 177)
These show `CLASS_IMAGE length 0` in `DF_ICONS_DATA`.

**Options:**
1. **Request DBA to populate** - Ideal solution
2. **Use fallback permanently** - Current approach
3. **Copy from another TYPE_ID** - If similar node type exists

**Recommended:** Document these as "Known Missing" and use fallback icons permanently.

## Verification Queries Needed

To complete the SQL additions, we need to query these tables:

```sql
-- Check TOOLPROTOTYPE_ structure
SELECT COLUMN_NAME, DATA_TYPE, NULLABLE
FROM ALL_TAB_COLUMNS
WHERE TABLE_NAME = 'TOOLPROTOTYPE_'
  AND OWNER = 'DESIGN12'
ORDER BY COLUMN_ID;

-- Check TOOLINSTANCEASPECT_ structure
SELECT COLUMN_NAME, DATA_TYPE, NULLABLE
FROM ALL_TAB_COLUMNS
WHERE TABLE_NAME = 'TOOLINSTANCEASPECT_'
  AND OWNER = 'DESIGN12'
ORDER BY COLUMN_ID;

-- Sample data from TOOLPROTOTYPE_
SELECT *
FROM DESIGN12.TOOLPROTOTYPE_
WHERE ROWNUM <= 5;

-- Sample data from TOOLINSTANCEASPECT_
SELECT *
FROM DESIGN12.TOOLINSTANCEASPECT_
WHERE ROWNUM <= 5;
```

## Next Steps for Other AI

1. **Query database** to get exact column names for:
   - `TOOLPROTOTYPE_`
   - `TOOLINSTANCEASPECT_`

2. **Add SQL extractions** to `generate-tree-html.ps1` for these tables

3. **Fix TYPE_ID 164 icon** in `generate-full-tree-html.ps1`

4. **Test with custom icon directory** set to:
   ```
   C:\Program Files\Tecnomatix_2301.0\eMPower\InitData;C:\tmp\PPRB1_Customization
   ```

5. **Create comprehensive commit** with:
   - Tool node extraction
   - Icon fixes
   - Documentation of missing DB icons
   - Test results

## Files Modified by Other AI

**Files Changed:**
- `src/powershell/main/generate-full-tree-html.ps1` - Icon loading logic
- `src/powershell/main/generate-tree-html.ps1` - Missing icon reporting
- `src/powershell/main/tree-viewer-launcher.ps1` - Custom icon directory option

**Commit:** `1a2e583` ("Improve icon selection for missing DB icons")

## Integration with Credential System

**Status:** Credential system is complete and working (my work)
- PC Profile system functional
- Credentials auto-retrieved
- Oracle environment configured
- Tree viewer launcher v2 working

**Merge Strategy:** See [MERGE-STRATEGY.md](MERGE-STRATEGY.md)

**Post-Merge:** Both systems will work together:
- Credentials auto-load
- Custom icon directories configured
- All node types visible
- Correct icons displayed

---

**Document Version:** 1.0
**Last Updated:** 2026-01-15
**Status:** Waiting for other AI to complete SQL additions
