# Guide: Finding and Adding Specialized Node Types

## Overview
Some node types in Siemens Process Simulate are stored in specialized tables instead of the main `COLLECTION_` table. These nodes require explicit UNION queries to appear in the generated navigation tree.

## Problem
The hierarchical query (`START WITH...CONNECT BY`) only traverses nodes in `COLLECTION_` table. Specialized nodes stored in other tables (like `PART_`, `ROBCADSTUDY_`, `SHORTCUT_`) are invisible to this query, even though they have relationships in `REL_COMMON`.

## Solution Pattern
Add explicit UNION queries for each specialized table to include these nodes in the tree.

## How to Find Specialized Node Types

### Step 1: Check CLASS_DEFINITIONS for Non-COLLECTION Tables
```sql
SELECT
    cd.TYPE_ID,
    cd.NICE_NAME,
    cd.NAME,
    cd.HARD_TABLE_NAME,
    cd.SOFT_TABLE_NAME
FROM DESIGN12.CLASS_DEFINITIONS cd
WHERE cd.HARD_TABLE_NAME IS NOT NULL
  AND cd.HARD_TABLE_NAME != 'COLLECTION_'
ORDER BY cd.HARD_TABLE_NAME, cd.TYPE_ID;
```

### Step 2: Check Which Specialized Nodes Exist in Your Project
```sql
-- Example: Check if TxProcessAssembly nodes exist
SELECT COUNT(*) as NODE_COUNT
FROM DESIGN12.PART_ p
INNER JOIN DESIGN12.REL_COMMON r ON p.OBJECT_ID = r.OBJECT_ID
WHERE p.CLASS_ID = 133  -- TxProcessAssembly TYPE_ID
  AND EXISTS (
    SELECT 1 FROM DESIGN12.COLLECTION_ c
    WHERE c.OBJECT_ID = r.FORWARD_OBJECT_ID
  );
```

### Step 3: Verify Node is Missing from Tree
1. Generate tree without the specialized query
2. Search tree data for the node by OBJECT_ID or name
3. If not found, add explicit query

## Currently Implemented Specialized Node Types

### 1. RobcadStudy (ROBCADSTUDY_ table)
- **TYPE_ID**: 177 (and 70, 108, 178, 181, 183 - Study variants)
- **Table**: ROBCADSTUDY_, LINESIMULATIONSTUDY_, GANTTSTUDY_, etc.
- **Query**: Lines 275-420 in `generate-tree-html.ps1`
- **Count**: ~50 nodes in FORD_DEARBORN project

### 2. Shortcut (SHORTCUT_ table)
- **TYPE_ID**: 68
- **Table**: SHORTCUT_
- **Query**: Lines 422-452 in `generate-tree-html.ps1`
- **Purpose**: Children of RobcadStudy nodes (shortcuts to other objects)
- **Count**: ~1,125 nodes in FORD_DEARBORN project

### 3. TxProcessAssembly (PART_ table)
- **TYPE_ID**: 133
- **Table**: PART_
- **Query**: Lines 454-484 in `generate-tree-html.ps1`
- **Purpose**: Assembly/process nodes within study folders
- **Count**: 1,344 nodes in FORD_DEARBORN project
- **Example**: CMN, SC, RC, CC folders under PROCESS nodes

## Query Template for Adding New Specialized Nodes

```sql
-- Add [NodeTypeName] nodes (from [TABLE_NAME], CLASS_ID [TYPE_ID])
-- [Description of what these nodes are]
-- Output: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
SELECT
    '999|' ||  -- Use level 999, JavaScript will correct it
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL([table_alias].NAME_S_, 'Unnamed') || '|' ||
    NVL([table_alias].NAME_S_, 'Unnamed') || '|' ||
    NVL([table_alias].EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class [ClassName]') || '|' ||
    NVL(cd.NICE_NAME, '[NiceName]') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.[TABLE_NAME] [table_alias] ON r.OBJECT_ID = [table_alias].OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON [table_alias].CLASS_ID = cd.TYPE_ID
WHERE [table_alias].CLASS_ID = [TYPE_ID]  -- Filter by specific TYPE_ID if needed
  AND EXISTS (
    SELECT 1 FROM $Schema.REL_COMMON r2
    INNER JOIN $Schema.COLLECTION_ c2 ON r2.OBJECT_ID = c2.OBJECT_ID
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID  -- Parent must be in COLLECTION_
      AND c2.OBJECT_ID IN (
        SELECT c3.OBJECT_ID
        FROM $Schema.REL_COMMON r3
        INNER JOIN $Schema.COLLECTION_ c3 ON r3.OBJECT_ID = c3.OBJECT_ID
        START WITH r3.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r3.OBJECT_ID = r3.FORWARD_OBJECT_ID
      )
  );
```

## Debugging Missing Nodes

### Symptoms
- Node visible in Siemens Navigation Tree
- Node has OBJECT_ID in database
- Node NOT in generated tree HTML

### Diagnosis Steps

1. **Check which table stores the node**:
   ```sql
   SELECT table_name
   FROM all_tab_columns
   WHERE owner = 'DESIGN12'
     AND column_name = 'OBJECT_ID'
     AND table_name NOT LIKE 'LV_%'
     AND table_name NOT LIKE 'V_%'
   ORDER BY table_name;
   ```

2. **Find the node in database**:
   ```sql
   -- Try COLLECTION_ first
   SELECT * FROM DESIGN12.COLLECTION_ WHERE OBJECT_ID = [your_object_id];

   -- Try PART_
   SELECT * FROM DESIGN12.PART_ WHERE OBJECT_ID = [your_object_id];

   -- Try other specialized tables
   SELECT * FROM DESIGN12.ROBCADSTUDY_ WHERE OBJECT_ID = [your_object_id];
   SELECT * FROM DESIGN12.SHORTCUT_ WHERE OBJECT_ID = [your_object_id];
   ```

3. **Check CLASS_DEFINITIONS**:
   ```sql
   SELECT cd.TYPE_ID, cd.NAME, cd.NICE_NAME, cd.HARD_TABLE_NAME
   FROM DESIGN12.CLASS_DEFINITIONS cd
   WHERE cd.TYPE_ID = (
     SELECT CLASS_ID FROM [table_found_above] WHERE OBJECT_ID = [your_object_id]
   );
   ```

4. **Add query using template above** if HARD_TABLE_NAME is not 'COLLECTION_'

## Icon Handling for Specialized Nodes

Specialized nodes may not have icons in `DF_ICONS_DATA`. Use parent class icons as fallback:

1. Trace class hierarchy:
   ```sql
   SELECT LEVEL as LVL, TYPE_ID, NICE_NAME, NAME, DERIVED_FROM,
          CASE WHEN EXISTS (SELECT 1 FROM DESIGN12.DF_ICONS_DATA WHERE TYPE_ID = cd.TYPE_ID)
               THEN 'YES' ELSE 'NO' END as HAS_ICON
   FROM DESIGN12.CLASS_DEFINITIONS cd
   START WITH TYPE_ID = [your_type_id]
   CONNECT BY PRIOR DERIVED_FROM = TYPE_ID
   ORDER BY LEVEL;
   ```

2. Use icon from first parent class that has an icon (see `ICON-FIX-SUMMARY.md`)

## Testing

After adding a specialized node query:

1. **Generate tree**: `pwsh generate-ford-dearborn-tree.ps1`
2. **Check node count**: Should increase
3. **Verify node in data**: `grep "[OBJECT_ID]" tree-data-*.txt`
4. **Check in browser**: Open HTML and navigate to node location
5. **Verify icon**: Should display correctly (not missing icon indicator)

## Common Specialized Tables

| Table Name | Node Type | TYPE_ID | Example Nodes |
|------------|-----------|---------|---------------|
| ROBCADSTUDY_ | RobcadStudy | 177 | Study definitions |
| LINESIMULATIONSTUDY_ | LineSimulationStudy | 178 | Line simulation studies |
| GANTTSTUDY_ | GanttStudy | 183 | Gantt studies |
| SIMPLEDETAILEDSTUDY_ | SimpleDetailedStudy | 181 | Simple detailed studies |
| LOCATIONALSTUDY_ | LocationalStudy | 108 | Locational studies |
| SHORTCUT_ | Shortcut | 68 | Shortcut/link nodes |
| PART_ | TxProcessAssembly | 133 | Assembly/process nodes |
| OPERATION_ | Various operations | Multiple | Operation nodes |

## Impact on Tree Generation

### Before Adding Specialized Queries
- **Node Count**: ~20,854
- **Missing**: RobcadStudy, Shortcut, TxProcessAssembly nodes

### After Adding Specialized Queries
- **Node Count**: ~23,254
- **Added**:
  - ~50 RobcadStudy nodes
  - ~1,125 Shortcut nodes
  - 1,344 TxProcessAssembly nodes
  - Total: **+2,400 nodes** (11% increase)

## Future Work

If new specialized node types are discovered:
1. Follow the "How to Find" steps above
2. Add query using the template
3. Test thoroughly
4. Update this documentation
5. Consider if icon fallback is needed

## References

- Icon fix documentation: `ICON-FIX-SUMMARY.md`
- RobcadStudy children fix: `ROBCADSTUDY-CHILDREN-FIX.md`
- Main generation script: `src/powershell/main/generate-tree-html.ps1`
