# PartInstanceLibrary Icon Fix - Finding the Correct TYPE_ID

## Problem

PartInstanceLibrary and PartLibrary are displaying the **same icon** (both using TYPE_ID 46), but they should have **different icons** as shown in the Siemens Navigation Tree.

## Root Cause

The current fix assigns TYPE_ID 46 (PartLibrary) to PartInstanceLibrary, but PartInstanceLibrary likely needs a **different TYPE_ID** that has its own unique icon in the database.

## Solution: Find the Correct TYPE_ID

### Step 1: Check What TYPE_ID PartLibrary Actually Uses

First, verify what TYPE_ID the actual PartLibrary node (OBJECT_ID 18143951) uses:

```sql
SELECT
    c.OBJECT_ID,
    c.CAPTION_S_,
    c.CLASS_ID,
    cd.TYPE_ID,
    cd.NAME,
    cd.NICE_NAME
FROM DESIGN12.COLLECTION_ c
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE c.OBJECT_ID = 18143951;  -- PartLibrary
```

**Expected Output:**
```
OBJECT_ID: 18143951
CAPTION_S_: PartLibrary
CLASS_ID: [some number]
TYPE_ID: [actual TYPE_ID - might NOT be 46!]
NAME: class PmPartLibrary (or similar)
NICE_NAME: PartLibrary
```

### Step 2: Check if PartInstanceLibrary Has Its Own Class

Search CLASS_DEFINITIONS for PartInstanceLibrary-related classes:

```sql
SELECT
    TYPE_ID,
    NAME,
    NICE_NAME,
    HARD_TABLE_NAME,
    DERIVED_FROM
FROM DESIGN12.CLASS_DEFINITIONS
WHERE UPPER(NICE_NAME) LIKE '%PARTINSTANCE%'
   OR UPPER(NAME) LIKE '%PARTINSTANCE%'
   OR UPPER(NICE_NAME) LIKE '%INSTANCE%LIBRARY%'
ORDER BY TYPE_ID;
```

**Look for:**
- `PartInstanceLibrary` (NICE_NAME)
- `PmPartInstanceLibrary` (NAME)
- Any class with "Instance" in the name

### Step 3: Check What Icon the Siemens App Uses

In the Siemens Navigation Tree, check:
1. **PartLibrary icon** - What does it look like?
2. **PartInstanceLibrary icon** - What does it look like? (should be different - reddish-brown three-pronged icon)

### Step 4: Find TYPE_IDs with Icons That Match

Query all TYPE_IDs that have icons and check their NICE_NAME:

```sql
SELECT
    di.TYPE_ID,
    cd.NICE_NAME,
    cd.NAME,
    DBMS_LOB.GETLENGTH(di.CLASS_IMAGE) AS ICON_SIZE
FROM DESIGN12.DF_ICONS_DATA di
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON di.TYPE_ID = cd.TYPE_ID
WHERE di.CLASS_IMAGE IS NOT NULL
  AND (
    UPPER(cd.NICE_NAME) LIKE '%PART%'
    OR UPPER(cd.NICE_NAME) LIKE '%INSTANCE%'
    OR UPPER(cd.NICE_NAME) LIKE '%LIBRARY%'
  )
ORDER BY di.TYPE_ID;
```

**Look for TYPE_IDs that might be:**
- PartInstanceLibrary
- PartInstance
- InstanceLibrary
- Or a related class

### Step 5: Check Class Hierarchy

If PartInstanceLibrary doesn't have its own TYPE_ID, check the class hierarchy to find a parent class with a different icon:

```sql
-- Find class hierarchy for PartLibrary (TYPE_ID 46)
SELECT
    LEVEL as LVL,
    cd.TYPE_ID,
    cd.NICE_NAME,
    cd.NAME,
    cd.DERIVED_FROM,
    CASE WHEN EXISTS (
        SELECT 1 FROM DESIGN12.DF_ICONS_DATA di WHERE di.TYPE_ID = cd.TYPE_ID
    ) THEN 'YES' ELSE 'NO' END as HAS_ICON
FROM DESIGN12.CLASS_DEFINITIONS cd
START WITH cd.TYPE_ID = 46  -- PartLibrary
CONNECT BY PRIOR cd.DERIVED_FROM = cd.TYPE_ID
ORDER BY LEVEL;
```

**Then check if PartInstanceLibrary has a different hierarchy:**

```sql
-- If you find a PartInstanceLibrary TYPE_ID, check its hierarchy
SELECT
    LEVEL as LVL,
    cd.TYPE_ID,
    cd.NICE_NAME,
    cd.NAME,
    cd.DERIVED_FROM,
    CASE WHEN EXISTS (
        SELECT 1 FROM DESIGN12.DF_ICONS_DATA di WHERE di.TYPE_ID = cd.TYPE_ID
    ) THEN 'YES' ELSE 'NO' END as HAS_ICON
FROM DESIGN12.CLASS_DEFINITIONS cd
START WITH cd.NICE_NAME = 'PartInstanceLibrary'  -- Or whatever you found
CONNECT BY PRIOR cd.DERIVED_FROM = cd.TYPE_ID
ORDER BY LEVEL;
```

### Step 6: Check REL_COMMON for CLASS_ID Clue

The ghost node might have a CLASS_ID in REL_COMMON that gives us a hint:

```sql
SELECT
    r.OBJECT_ID,
    r.CLASS_ID,
    cd.TYPE_ID,
    cd.NAME,
    cd.NICE_NAME
FROM DESIGN12.REL_COMMON r
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
WHERE r.OBJECT_ID = 18143953;  -- PartInstanceLibrary
```

**This CLASS_ID might be the correct TYPE_ID to use!**

## Updated Fix: Use Correct TYPE_ID

Once you find the correct TYPE_ID for PartInstanceLibrary, update the CASE statement:

### Current (WRONG - uses PartLibrary icon):
```sql
CASE WHEN r.OBJECT_ID = 18143953 THEN '46' END  -- PartLibrary TYPE_ID
```

### Updated (CORRECT - uses PartInstanceLibrary icon):
```sql
CASE WHEN r.OBJECT_ID = 18143953 THEN '[CORRECT_TYPE_ID]' END
```

**Replace `[CORRECT_TYPE_ID]` with the TYPE_ID you found from the queries above.**

## Complete Updated Query

```sql
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
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'class PmPartInstanceLibrary' END,  -- Updated class name
        'class PmNode'
    ) || '|' ||
    COALESCE(
        cd.NICE_NAME,
        cd_part.NICE_NAME,
        CASE WHEN r.OBJECT_ID = 18143953 THEN 'PartInstanceLibrary' END,  -- Updated nice name
        'Unknown'
    ) || '|' ||
    COALESCE(
        TO_CHAR(cd.TYPE_ID),
        TO_CHAR(cd_part.TYPE_ID),
        TO_CHAR(r.CLASS_ID),  -- ⚠️ Try using CLASS_ID from REL_COMMON first
        CASE WHEN r.OBJECT_ID = 18143953 THEN '[CORRECT_TYPE_ID]' END,  -- Fallback to correct TYPE_ID
        ''
    )
FROM $Schema.REL_COMMON r
LEFT JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd_part ON p.CLASS_ID = cd_part.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = $ProjectId;
```

**Key Change:** Added `TO_CHAR(r.CLASS_ID)` before the CASE statement - this will use the CLASS_ID from REL_COMMON if it exists, which might be the correct TYPE_ID!

## Alternative: Use REL_COMMON.CLASS_ID Directly

The simplest fix might be to use the CLASS_ID from REL_COMMON directly:

```sql
COALESCE(
    TO_CHAR(cd.TYPE_ID),
    TO_CHAR(cd_part.TYPE_ID),
    TO_CHAR(r.CLASS_ID),  -- ⚠️ Use CLASS_ID from REL_COMMON for ghost nodes
    ''
)
```

**This will automatically use the correct TYPE_ID from REL_COMMON without needing a hardcoded CASE statement!**

## Verification Steps

### 1. Check REL_COMMON.CLASS_ID for Ghost Node

```sql
SELECT
    r.OBJECT_ID,
    r.CLASS_ID,
    cd.TYPE_ID,
    cd.NAME,
    cd.NICE_NAME,
    CASE WHEN EXISTS (
        SELECT 1 FROM DESIGN12.DF_ICONS_DATA di WHERE di.TYPE_ID = r.CLASS_ID
    ) THEN 'YES' ELSE 'NO' END as HAS_ICON
FROM DESIGN12.REL_COMMON r
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
WHERE r.OBJECT_ID = 18143953;
```

**If CLASS_ID exists and has an icon, use `TO_CHAR(r.CLASS_ID)` in your query!**

### 2. Verify Different Icons

After fix, check the generated tree data:
```bash
grep -E "(18143951|18143953)" tree-data-*.txt
```

**Expected Output:**
```
1|18140190|18143951|PartLibrary|PartLibrary||0|class PmPartLibrary|PartLibrary|46
1|18140190|18143953|PartInstanceLibrary|PartInstanceLibrary||0|class PmPartInstanceLibrary|PartInstanceLibrary|[DIFFERENT_TYPE_ID]
```

**The TYPE_IDs should be DIFFERENT!**

### 3. Verify Icons in HTML

- PartLibrary should show one icon
- PartInstanceLibrary should show a **different** icon (reddish-brown three-pronged icon)

## Quick Fix: Use REL_COMMON.CLASS_ID

**The easiest solution is to use `r.CLASS_ID` from REL_COMMON directly:**

```sql
COALESCE(
    TO_CHAR(cd.TYPE_ID),        -- From COLLECTION_ if exists
    TO_CHAR(cd_part.TYPE_ID),   -- From PART_ if exists
    TO_CHAR(r.CLASS_ID),        -- ⚠️ From REL_COMMON for ghost nodes (likely correct!)
    ''
)
```

This will automatically use the correct TYPE_ID for the ghost node without hardcoding!

## Summary

1. **Check REL_COMMON.CLASS_ID** - This is likely the correct TYPE_ID for the ghost node
2. **Use `TO_CHAR(r.CLASS_ID)`** in your COALESCE statement
3. **Verify the icon is different** from PartLibrary
4. **If CLASS_ID doesn't work**, use the investigation queries above to find the correct TYPE_ID

The key insight: **REL_COMMON.CLASS_ID might already contain the correct TYPE_ID for the ghost node!**
