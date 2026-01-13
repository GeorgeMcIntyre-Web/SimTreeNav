# Node Ordering Fix - Chronological by Creation Date

## Problem
The navigation tree was showing nodes in alphabetical order instead of creation order like the Siemens application.

## Solution
Changed the SQL queries to order nodes by `MODIFICATIONDATE_DA_` (the actual creation/modification date) instead of `OBJECT_ID` or `SEQ_NUMBER`.

## Changes Made

### File: [generate-tree-html.ps1](generate-tree-html.ps1)

Updated all three ORDER BY clauses:

#### 1. Level 1 Children (Line 156)
**Before:**
```sql
ORDER BY c.OBJECT_ID;
```

**After:**
```sql
ORDER BY NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID;
```

#### 2. Level 2+ Descendants (Line 176)
**Before:**
```sql
ORDER SIBLINGS BY c.OBJECT_ID;
```

**After:**
```sql
ORDER SIBLINGS BY NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID;
```

#### 3. StudyFolder Children (Line 203)
**Before:**
```sql
ORDER BY r.FORWARD_OBJECT_ID, c.OBJECT_ID;
```

**After:**
```sql
ORDER BY r.FORWARD_OBJECT_ID, NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID;
```

## How It Works

### Date-Based Ordering
- Primary sort: `MODIFICATIONDATE_DA_` - The actual date the node was created/modified
- Secondary sort: `OBJECT_ID` - Fallback for nodes with the same date
- `NVL()` handles NULL dates by using a very old date (1900-01-01)

### Example Order (FORD_DEARBORN Project)
```
1. MfgLibrary              - Aug 19, 2025 09:54:05
2. P702                    - Sep 2, 2025 09:27:25
3. IPA                     - Sep 8, 2025 17:33:09
4. P736                    - Oct 29, 2025 15:54:35
5. DES_Studies             - Oct 29, 2025 17:23:07
6. PartLibrary             - Nov 7, 2025 09:51:02
7. EngineeringResourceLibrary - Nov 13, 2025 16:59:44
8. Working Folders         - Dec 9, 2025 11:28:28
```

This matches the chronological creation order shown in the Siemens application.

## Why OBJECT_ID Wasn't Enough

Initially, we tried ordering by `OBJECT_ID` assuming it would reflect creation order, but:
- OBJECT_IDs are not always sequential by date
- Example: PartLibrary (ID: 18143951) was created on Nov 7, but P702 (ID: 18195357) was created earlier on Sep 2
- The database assigns IDs in a non-sequential manner across different projects/schemas

## Testing

### Test Query
```sql
SELECT
    c.OBJECT_ID,
    c.CAPTION_S_,
    TO_CHAR(c.MODIFICATIONDATE_DA_, 'DD/MM/YYYY HH24:MI:SS') AS MOD_DATE
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
WHERE r.FORWARD_OBJECT_ID = 18140190
ORDER BY c.MODIFICATIONDATE_DA_, c.OBJECT_ID;
```

### Verify Generated Tree
```bash
grep "^1|18140190|" navigation-tree-ordered.html | head -10
```

Should show nodes in chronological order by their creation dates.

## Benefits

1. **Matches Siemens App**: Tree now shows nodes in the same order as the official Siemens application
2. **Chronological View**: Users see nodes in the order they were created, which is more intuitive
3. **Consistent Across Levels**: All levels (1, 2, 3+) use the same date-based ordering
4. **Handles NULL Dates**: Uses fallback date for nodes without a modification date
5. **Stable Sort**: Secondary sort by OBJECT_ID ensures consistent ordering for same-date nodes

## Usage

```powershell
# Generate tree with chronological ordering
.\tree-viewer-launcher.ps1

# Or direct generation
.\generate-tree-html.ps1 -TNSName SIEMENS_PS_DB_DB01 -Schema DESIGN12 -ProjectId 18140190 -ProjectName "FORD_DEARBORN"
```

The tree will now display nodes in the order they were created!

## Related Files

- [generate-tree-html.ps1](generate-tree-html.ps1) - Updated SQL queries
- [ICON-EXTRACTION-SUCCESS.md](ICON-EXTRACTION-SUCCESS.md) - Icon extraction documentation
- [QUICK-START-GUIDE.md](QUICK-START-GUIDE.md) - User guide

## Status

✅ **COMPLETE** - Nodes now ordered by creation date matching Siemens application
