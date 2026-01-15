# PartInstanceLibrary Ghost Node Fix Guide

## Problem Description

**PartInstanceLibrary** (OBJECT_ID: 18143953) is a "ghost node" that:
- ✅ Exists in `REL_COMMON` as a child relationship
- ❌ Does NOT exist in `COLLECTION_` table (no data)
- ✅ Appears in Siemens Navigation Tree with correct name and icon
- ❌ Missing or showing as "Unnamed" in generated tree
- ❌ Missing or incorrect icon

## Root Cause

The node exists only in `REL_COMMON` but not in `COLLECTION_`. If your query uses:
- `INNER JOIN COLLECTION_` → Ghost node is excluded (no match)
- Missing CASE statements → Node appears as "Unnamed" with no TYPE_ID
- Missing TYPE_ID → No icon can be looked up from database

## Solution

### Step 1: Use LEFT JOIN Instead of INNER JOIN

**❌ WRONG** (excludes ghost node):
```sql
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
```

**✅ CORRECT** (includes ghost node):
```sql
FROM $Schema.REL_COMMON r
LEFT JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
```

### Step 2: Add CASE Statements for Ghost Node Data

Since the ghost node has no data in `COLLECTION_`, you must provide:
- **Name/Caption**: "PartInstanceLibrary"
- **Class Name**: "class PmPartLibrary"
- **Nice Name**: "PartLibrary"
- **TYPE_ID**: "46" (critical for icon lookup)

**Complete SQL Query Pattern:**

```sql
-- Level 1: Direct children query
SELECT
    '1|$ProjectId|' || r.OBJECT_ID || '|' ||
    COALESCE(
        c.CAPTION_S_,
        p.NAME_S_,
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'PartInstanceLibrary' END,
        'Unnamed'
    ) || '|' ||
    COALESCE(
        c.CAPTION_S_,
        p.NAME_S_,
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'PartInstanceLibrary' END,
        'Unnamed'
    ) || '|' ||
    COALESCE(c.EXTERNALID_S_, p.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    COALESCE(
        cd.NAME,
        cd_part.NAME,
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'class PmPartLibrary' END,
        'class PmNode'
    ) || '|' ||
    COALESCE(
        cd.NICE_NAME,
        cd_part.NICE_NAME,
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'PartLibrary' END,
        'Unknown'
    ) || '|' ||
    COALESCE(
        TO_CHAR(cd.TYPE_ID),
        TO_CHAR(cd_part.TYPE_ID),
        CASE WHEN r.OBJECT_ID = 18143953 THEN '46' END,  -- ⚠️ CRITICAL: TYPE_ID 46 for icon
        ''
    )
FROM $Schema.REL_COMMON r
LEFT JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd_part ON p.CLASS_ID = cd_part.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = $ProjectId;
```

### Step 3: Verify Icon Extraction Includes TYPE_ID 46

The icon for PartInstanceLibrary comes from `DF_ICONS_DATA` where `TYPE_ID = 46`.

**Icon Extraction Query** (should already include TYPE_ID 46):
```sql
SELECT
    di.TYPE_ID || '|' ||
    DBMS_LOB.GETLENGTH(di.CLASS_IMAGE) || '|' ||
    RAWTOHEX(DBMS_LOB.SUBSTR(di.CLASS_IMAGE, DBMS_LOB.GETLENGTH(di.CLASS_IMAGE), 1))
FROM $Schema.DF_ICONS_DATA di
WHERE di.CLASS_IMAGE IS NOT NULL
ORDER BY di.TYPE_ID;
```

**Verify TYPE_ID 46 is extracted:**
- Check your icon extraction output
- TYPE_ID 46 should be in the list of extracted icons
- Icon format: BMP, 16×16 pixels, ~246-1334 bytes

### Step 4: Icon Lookup in JavaScript/HTML

When rendering the tree, the icon is looked up by TYPE_ID:

```javascript
// Icon data map from database extraction
const iconDataMap = {
    "46": "data:image/bmp;base64,...",  // PartLibrary icon
    // ... other icons
};

// When node has TYPE_ID 46, use iconDataMap['46']
const iconUri = iconDataMap[node.typeId];  // Returns PartLibrary icon
```

## Complete Working Example

### Database Structure

**REL_COMMON** (relationship exists):
```
OBJECT_ID: 18143953
FORWARD_OBJECT_ID: 18140190 (project)
SEQ_NUMBER: 0
```

**COLLECTION_** (no row exists):
```
-- No row for OBJECT_ID 18143953
```

**DF_ICONS_DATA** (icon exists):
```
TYPE_ID: 46
CLASS_IMAGE: [BLOB - BMP icon data]
```

### Expected Output

After fix, the tree data should contain:
```
1|18140190|18143953|PartInstanceLibrary|PartInstanceLibrary||0|class PmPartLibrary|PartLibrary|46
```

### Icon Display

- **TYPE_ID**: 46
- **Icon Source**: `DF_ICONS_DATA.CLASS_IMAGE` where `TYPE_ID = 46`
- **Icon Format**: BMP (16×16 pixels)
- **Display**: Reddish-brown three-pronged icon (as shown in Siemens app)

## Verification Steps

### 1. Check if Ghost Node Appears in Query

```sql
SELECT
    r.OBJECT_ID,
    c.CAPTION_S_,
    cd.TYPE_ID,
    cd.NICE_NAME
FROM DESIGN12.REL_COMMON r
LEFT JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = 18140190
  AND r.OBJECT_ID = 18143953;
```

**Expected Result:**
```
OBJECT_ID: 18143953
CAPTION_S_: NULL (because no row in COLLECTION_)
TYPE_ID: NULL (because no row in COLLECTION_)
NICE_NAME: NULL
```

This confirms it's a ghost node - exists in REL_COMMON but not COLLECTION_.

### 2. Verify Icon Exists in Database

```sql
SELECT
    TYPE_ID,
    DBMS_LOB.GETLENGTH(CLASS_IMAGE) AS ICON_SIZE
FROM DESIGN12.DF_ICONS_DATA
WHERE TYPE_ID = 46;
```

**Expected Result:**
```
TYPE_ID: 46
ICON_SIZE: [246-1334 bytes]
```

### 3. Check Generated Tree Data

After generating tree, search for PartInstanceLibrary:
```bash
grep "18143953" tree-data-*.txt
```

**Expected Output:**
```
1|18140190|18143953|PartInstanceLibrary|PartInstanceLibrary||0|class PmPartLibrary|PartLibrary|46
```

### 4. Verify Icon in HTML

Open generated HTML and check:
- Node displays as "PartInstanceLibrary" (not "Unnamed")
- Icon displays correctly (reddish-brown icon)
- No missing icon indicator

## Common Mistakes

### ❌ Mistake 1: Using INNER JOIN
```sql
INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
```
**Problem**: Excludes ghost node (no match in COLLECTION_)
**Fix**: Use `LEFT JOIN`

### ❌ Mistake 2: Missing CASE Statement for TYPE_ID
```sql
COALESCE(TO_CHAR(cd.TYPE_ID), '')  -- Returns empty string for ghost node
```
**Problem**: No TYPE_ID means no icon lookup
**Fix**: Add `CASE WHEN r.OBJECT_ID = 18143953 THEN '46' END`

### ❌ Mistake 3: Missing CASE Statement for Name
```sql
COALESCE(c.CAPTION_S_, 'Unnamed')  -- Shows "Unnamed" for ghost node
```
**Problem**: Ghost node has no CAPTION_S_ (NULL)
**Fix**: Add `CASE WHEN r.OBJECT_ID = 18143953 THEN 'PartInstanceLibrary' END`

### ❌ Mistake 4: Not Extracting TYPE_ID 46 Icon
**Problem**: Icon extraction query doesn't include TYPE_ID 46, or icon data not passed to HTML
**Fix**: Ensure icon extraction includes all TYPE_IDs, verify TYPE_ID 46 is in iconDataMap

## Why TYPE_ID 46?

PartInstanceLibrary uses TYPE_ID 46 (PartLibrary) because:
- The ghost node represents a PartLibrary instance
- TYPE_ID 46 has an icon in `DF_ICONS_DATA`
- The Siemens app displays it with the PartLibrary icon
- This matches the class hierarchy: PartInstanceLibrary → PartLibrary

## Alternative: Make it Project-Specific

If PartInstanceLibrary only exists in specific projects, you can make the fix conditional:

```sql
CASE 
    WHEN r.OBJECT_ID = 18143953 AND $ProjectId = 18140190 THEN 'PartInstanceLibrary'
    WHEN r.OBJECT_ID = 18143953 THEN 'Unnamed'
    ELSE COALESCE(c.CAPTION_S_, 'Unnamed')
END
```

## Testing Checklist

- [ ] Ghost node appears in tree (not missing)
- [ ] Node displays as "PartInstanceLibrary" (not "Unnamed")
- [ ] Node has TYPE_ID 46 in tree data
- [ ] Icon displays correctly (reddish-brown icon)
- [ ] No missing icon indicator
- [ ] Node appears in correct position (after PartLibrary)

## Files to Modify

1. **Tree Generation SQL Query** (Level 1 children query)
   - Change `INNER JOIN` to `LEFT JOIN` for COLLECTION_
   - Add CASE statements for OBJECT_ID 18143953

2. **Icon Extraction** (if not already working)
   - Verify TYPE_ID 46 is extracted
   - Ensure icon data is passed to HTML

3. **JavaScript Icon Lookup** (if custom)
   - Verify iconDataMap includes TYPE_ID 46
   - Check icon lookup logic handles TYPE_ID correctly

## Summary

The fix requires three changes:
1. **LEFT JOIN** instead of INNER JOIN (to include ghost node)
2. **CASE statements** to provide name, class, and TYPE_ID for ghost node
3. **TYPE_ID 46** assignment (critical for icon lookup)

Once these are in place, PartInstanceLibrary will:
- ✅ Appear in the tree
- ✅ Display correct name
- ✅ Display correct icon from database
- ✅ Match Siemens Navigation Tree behavior

## Related Documentation

- `CUSTOM-ORDERING-SOLUTION.md` - Details about ghost node discovery
- `TREE-NODES-BUGS-REVIEW.md` - Comprehensive review of missing nodes fixes
- `ICON-FIX-SUMMARY.md` - Icon handling patterns
