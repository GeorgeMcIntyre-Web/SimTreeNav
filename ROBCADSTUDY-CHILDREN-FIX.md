# RobcadStudy Node Children Fix

## Problem
RobcadStudy nodes (like "DDMP P702_8J_010_8J_060", node ID 18144811) appeared in the tree but showed **no children**, even though they should have had 51 child nodes (Collection folders, Shortcuts, RobcadStudyInfo nodes, etc.).

## Root Cause
Children of RobcadStudy nodes are stored in **specialized tables** rather than the COLLECTION_ table:
- **25 children** in `SHORTCUT_` table (CLASS_ID 68, NICE_NAME "Shortcut")
- **25 children** in `ROBCADSTUDYINFO_` table (CLASS_ID 179, NICE_NAME "RobcadStudyInfo")
- **1 child** in `COLLECTION_` table (StudyFolder)

The hierarchical query (lines 201-219 in generate-tree-html.ps1) only traverses `COLLECTION_` nodes via `CONNECT BY`, so specialized table children were excluded.

## Investigation Process

### Query 1: Check Total Children
```sql
SELECT COUNT(*) FROM DESIGN12.REL_COMMON WHERE FORWARD_OBJECT_ID = 18144811;
-- Result: 51 total children
```

### Query 2: Identify Table Distribution
```sql
SELECT
    CASE
        WHEN c.OBJECT_ID IS NOT NULL THEN 'COLLECTION_'
        WHEN rs.OBJECT_ID IS NOT NULL THEN 'ROBCADSTUDYINFO_'
        WHEN sc.OBJECT_ID IS NOT NULL THEN 'SHORTCUT_'
        ELSE 'UNKNOWN'
    END as TABLE_NAME,
    COUNT(*) as COUNT
FROM DESIGN12.REL_COMMON r
LEFT JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN DESIGN12.ROBCADSTUDYINFO_ rs ON r.OBJECT_ID = rs.OBJECT_ID
LEFT JOIN DESIGN12.SHORTCUT_ sc ON r.OBJECT_ID = sc.OBJECT_ID
WHERE r.FORWARD_OBJECT_ID = 18144811
GROUP BY ...
-- Result: 1 COLLECTION_, 25 ROBCADSTUDYINFO_, 25 SHORTCUT_
```

### Query 3: SHORTCUT_ Details
```sql
SELECT r.OBJECT_ID, sc.NAME_S_, cd.NICE_NAME
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.SHORTCUT_ sc ON r.OBJECT_ID = sc.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON sc.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = 18144811;
-- Found: 8J-010, 8J-020, 8J-022, LAYOUT, 8J-010_CMN, etc.
```

### Query 4: ROBCADSTUDYINFO_ Details
```sql
SELECT r.OBJECT_ID, rsi.NAME_S_, cd.NICE_NAME
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.ROBCADSTUDYINFO_ rsi ON r.OBJECT_ID = rsi.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON rsi.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = 18144811;
-- Found: 25 "RobcadStudyInfo" nodes
```

## Solution

Added two UNION queries to `src/powershell/main/generate-tree-html.ps1` (after line 408):

### 1. SHORTCUT_ Children Query (Lines 410-442)
```sql
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(sc.NAME_S_, 'Unnamed') || '|' ||
    NVL(sc.NAME_S_, 'Unnamed') || '|' ||
    NVL(sc.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmShortcut') || '|' ||
    NVL(cd.NICE_NAME, 'Shortcut') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.SHORTCUT_ sc ON r.OBJECT_ID = sc.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON sc.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.ROBCADSTUDY_ rs
    WHERE rs.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND EXISTS (... filter to project scope ...)
);
```

### 2. ROBCADSTUDYINFO_ Children Query (Lines 444-476)
```sql
SELECT
    '999|' ||
    r.FORWARD_OBJECT_ID || '|' ||
    r.OBJECT_ID || '|' ||
    NVL(rsi.NAME_S_, 'Unnamed') || '|' ||
    NVL(rsi.NAME_S_, 'Unnamed') || '|' ||
    NVL(rsi.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class RobcadStudyInfo') || '|' ||
    NVL(cd.NICE_NAME, 'RobcadStudyInfo') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.ROBCADSTUDYINFO_ rsi ON r.OBJECT_ID = rsi.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON rsi.CLASS_ID = cd.TYPE_ID
WHERE EXISTS (
    SELECT 1 FROM DESIGN12.ROBCADSTUDY_ rs
    WHERE rs.OBJECT_ID = r.FORWARD_OBJECT_ID
      AND EXISTS (... filter to project scope ...)
);
```

## Key Insights

1. **Shortcut Nodes**: These are navigable link nodes (CLASS_ID 68) that reference other objects in the tree. When double-clicked in the Siemens app, they navigate to the target object (e.g., a PrStation).

2. **RobcadStudyInfo Nodes**: These contain metadata/configuration information for RobcadStudy objects (CLASS_ID 179).

3. **Specialized Table Pattern**: Following the same pattern used for RobcadStudy parent nodes (lines 268-296), specialized table children need explicit UNION queries to be included in the tree.

## Result
- **Before Fix**: RobcadStudy nodes had only 1 visible child (StudyFolder in COLLECTION_)
- **After Fix**: RobcadStudy nodes now display all 51 children (1 StudyFolder + 25 Shortcuts + 25 RobcadStudyInfo nodes)
- Tree node count increased from **~20,854 to ~23,104 nodes** (+2,250 nodes across all RobcadStudy children in the project)
- Global impact: Added 1,125 Shortcuts + ~1,125 RobcadStudyInfo nodes across all RobcadStudy nodes

## Files Modified
- `src/powershell/main/generate-tree-html.ps1` (lines 410-470)

## Test Case - Node 18144811
**Node**: "DDMP P702_8J_010_8J_060" (ID: 18144811)
**Expected children**: 51 (verified via database query)
**Actual result**: 50 children now visible in tree (1 was already included via COLLECTION_ hierarchical query):
  - **25 Shortcuts**: 8J-010, 8J-020, 8J-022, 8J-027, 8J-030, 8J-040, 8J-050, 8J-060, LAYOUT, 8J-010_CMN, 8J-027_SC, 8J-030_SC, 8J-027_RC, 8J-030_RC, 8J-027_CC, 8J-030_CC, and more
  - **25 RobcadStudyInfo** metadata nodes
  - **1 StudyFolder** ("COWL & SILL SIDE") was already included via the hierarchical COLLECTION_ query

**Success**: ✅ All expected children are now visible in the generated tree
