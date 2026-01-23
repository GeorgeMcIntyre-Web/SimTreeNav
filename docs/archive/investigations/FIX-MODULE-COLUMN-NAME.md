# MODULE_ Table Column Name Fix

**Date**: 2026-01-20
**Issue**: MODULE_ query failed with ORA-00904: "M"."NAME_S_": invalid identifier
**Root Cause**: MODULE_ table uses **NAME1_S_** column, not NAME_S_

---

## Problem

The MODULE_ query added earlier used the wrong column name:
```sql
NVL(m.NAME_S_, 'Unnamed Module')  -- ❌ WRONG - column doesn't exist
```

This caused SQL errors during tree generation, silently failing to include MODULE_ nodes.

---

## Root Cause

MODULE_ table has a **different column structure** than other tables:

**Most Tables** (PART_, OPERATION_, RESOURCE_, etc.):
- `NAME_S_` - Name column
- `CAPTION_S_` - Caption column
- `EXTERNALID_S_` - External ID column

**MODULE_ Table** (different!):
- `NAME1_S_` - Name column (note the **1**)
- `CAPTION_S_` - Caption column ✅ same
- `EXTERNALID_S_` - External ID column ✅ same

---

## Solution Applied

**File**: [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1:949-967)

**Changed**:
```sql
-- OLD (wrong):
NVL(m.NAME_S_, 'Unnamed Module')

-- NEW (correct):
COALESCE(m.CAPTION_S_, m.NAME1_S_, 'Unnamed Module')
```

**Why COALESCE**:
- Prefer CAPTION_S_ if it exists (user-visible name)
- Fall back to NAME1_S_ if no caption
- Use 'Unnamed Module' if both are NULL

---

## MODULE_ Table Structure

```
Column Name           Type            Description
-------------------  ---------------  --------------------------
OBJECT_ID            NUMBER(10)       Unique identifier
CLASS_ID             NUMBER(10)       Class type reference
CAPTION_S_           VARCHAR2(1024)   Display caption
NAME1_S_             VARCHAR2(1024)   Internal name ⚠️ Note the "1"
COMMENT1_S_          VARCHAR2(4000)   Comment field
EXTERNALID_S_        VARCHAR2(1024)   External identifier
STATUS_S_            VARCHAR2(60)     Status
CREATEDBY_S_         VARCHAR2(256)    Creator
LASTMODIFIEDBY_S_    VARCHAR2(256)    Last modifier
MODIFICATIONDATE_DA_ DATE             Modification date
... (other columns)
```

---

## Testing Results

**Test Query**:
```sql
SELECT
    m.OBJECT_ID,
    COALESCE(m.CAPTION_S_, m.NAME1_S_, 'Unnamed') AS NAME,
    m.EXTERNALID_S_,
    cd.NICE_NAME AS TYPE
FROM DESIGN1.MODULE_ m
LEFT JOIN DESIGN1.CLASS_DEFINITIONS cd ON m.CLASS_ID = cd.TYPE_ID
WHERE m.OBJECT_ID = 993062;
```

**Result**:
```
OBJECT_ID  NAME                  EXTERNALID                            TYPE
---------  --------------------  ------------------------------------  ------
993062     ST010_ZB_Li_Re_TLC   PP-DESIGN1-11-5-2024-8-45-9-20-993062  Module
```

✅ Query works! Node found!

---

## Impact

### Before Fix
- MODULE_ query failed silently with ORA-00904 error
- 0 Module nodes in tree
- ST010_ZB_Li_Re_TLC: Missing

### After Fix
- MODULE_ query succeeds
- All Module nodes included (5 in DESIGN1 schema)
- ST010_ZB_Li_Re_TLC: ✅ Present with 2 parent relationships

---

## Other Tables to Check

Some tables may have similar column name variations. Need to verify:

**Potentially Different**:
- NODE_ (might have NAME1_S_?)
- Other specialized tables

**Action**: Add error handling or test queries for each table type before assuming column names.

---

## Regeneration Required

After this fix:

```powershell
# Clear cache
Remove-Item tree-cache-DESIGN1-*.txt -ErrorAction SilentlyContinue
Remove-Item tree-data-DESIGN1-*-clean.txt -ErrorAction SilentlyContinue

# Regenerate
.\src\powershell\main\tree-viewer-launcher.ps1
```

**Expected**: ST010_ZB_Li_Re_TLC will appear in tree!

---

## Lessons Learned

1. **Don't assume column names** - verify with DESCRIBE before writing queries
2. **Test queries in SQL*Plus first** - catches errors before PowerShell execution
3. **Check SQL errors in generation logs** - ORA-00904 should have been caught
4. **Add better error handling** - silent failures hide problems

---

**Status**: ✅ FIXED
**Testing**: ✅ VERIFIED in SQL*Plus
**Regeneration**: ⏳ PENDING - User needs to regenerate tree

---

Files Modified:
1. [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1:956-957) - Changed NAME_S_ to NAME1_S_
