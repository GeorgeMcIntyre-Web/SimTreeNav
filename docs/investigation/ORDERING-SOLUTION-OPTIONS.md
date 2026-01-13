# Node Ordering - Solution Options

## Current Situation

After extensive database investigation, I cannot find a database field that stores the custom node ordering shown in your Siemens Navigation Tree screenshot.

### What We've Checked ✅

**REL_COMMON Table (Relationships)**:
- ❌ SEQ_NUMBER - All values are 0
- ❌ OBJECT_VERSION_ID - Different order than screenshot
- ❌ REL_TYPE - All values are 4
- ❌ FIELD_NAME - All values are "collections"
- ⚠️ ROWID - Close but not exact, and unreliable (changes with DB maintenance)

**COLLECTION_ Table (Nodes)**:
- ❌ OBJECT_ID - Not chronological
- ❌ MODIFICATIONDATE_DA_ - Chronological but different order
- ❌ COLLECTIONS_VR_ - All values are 1
- ❌ STATUS_S_ - All values are "Open"
- ❌ CHILDREN_VR_ - Not related to sibling ordering

**Other Schema Objects**:
- ❌ V_COLLECTION_ view - Same data as COLLECTION_
- ❌ LV_COLLECTION_ view - Latest version view
- ❌ DFUSERFOLDERTABLE - User folders, not project collections
- ❌ EMS_CONFIGURATION - General settings only
- ❌ No stored procedures found for ordering
- ❌ No ORDER/SORT/SEQ/INDEX related tables

### Your Screenshot Order (FORD_DEARBORN Project)
1. P702
2. P736
3. EngineeringResourceLibrary
4. PartLibrary
5. **PartInstanceLibrary** ⚠️ (Does not exist in database!)
6. MfgLibrary
7. IPA
8. DES_Studies
9. Working Folders

### Actual Database Nodes (8 nodes, not 9)
- DES_Studies
- EngineeringResourceLibrary
- IPA
- MfgLibrary
- P702
- P736
- PartLibrary
- Working Folders

## Critical Question

**The screenshot shows PartInstanceLibrary, which does NOT exist in the database as a Level 1 child of project 18140190.**

Possible explanations:
1. Screenshot is from a different project
2. Screenshot is from an older database state
3. PartInstanceLibrary exists but is hidden/deleted

## Available Ordering Strategies

Since no database field contains the Siemens order, here are our options:

### Option 1: Chronological by Creation Date (CURRENT)
**Implementation**: Already done
```sql
ORDER BY NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID
```

**Result Order**:
1. MfgLibrary (Aug 19, 2025)
2. P702 (Sep 2, 2025)
3. IPA (Sep 8, 2025)
4. P736 (Oct 29, 2025)
5. DES_Studies (Oct 29, 2025)
6. PartLibrary (Nov 7, 2025)
7. EngineeringResourceLibrary (Nov 13, 2025)
8. Working Folders (Dec 9, 2025)

**Pros**:
- True chronological creation order
- Makes logical sense
- Matches Siemens app behavior for "recently added" items

**Cons**:
- Doesn't match your screenshot

---

### Option 2: Manual Configuration File
**Implementation**: Create a JSON config file to specify custom ordering

```json
{
  "projects": {
    "18140190": {
      "name": "FORD_DEARBORN",
      "customOrder": [
        "P702",
        "P736",
        "EngineeringResourceLibrary",
        "PartLibrary",
        "MfgLibrary",
        "IPA",
        "DES_Studies",
        "Working Folders"
      ]
    }
  }
}
```

**Implementation Steps**:
1. Create `tree-ordering-config.json`
2. Modify `generate-tree-html.ps1` to read this file
3. Sort nodes according to config order
4. Fall back to chronological order if not in config

**Pros**:
- Exact control over ordering
- Can match any desired order
- Easy to modify without touching SQL

**Cons**:
- Requires manual maintenance
- Need to update config when nodes are added/removed

---

### Option 3: Alphabetical by Type, then Name
**Implementation**: Order by node class type first, then alphabetically

```sql
ORDER BY
    CASE cd.NICE_NAME
        WHEN 'Collection' THEN 1
        WHEN 'RobcadResourceLibrary' THEN 2
        WHEN 'PartLibrary' THEN 3
        WHEN 'MfgLibrary' THEN 4
        ELSE 5
    END,
    c.CAPTION_S_
```

**Result Order**:
1. DES_Studies (Collection)
2. IPA (Collection)
3. P702 (Collection)
4. P736 (Collection)
5. Working Folders (Collection)
6. EngineeringResourceLibrary (RobcadResourceLibrary)
7. PartLibrary (PartLibrary)
8. MfgLibrary (MfgLibrary)

**Pros**:
- Groups similar types together
- Predictable within each type

**Cons**:
- Still doesn't match screenshot
- Arbitrary type priority

---

### Option 4: OBJECT_VERSION_ID (Database Insert Order)
**Implementation**: Use OBJECT_VERSION_ID for ordering

```sql
ORDER BY r.OBJECT_VERSION_ID
```

**Result Order**:
1. MfgLibrary
2. P702
3. IPA
4. DES_Studies
5. P736
6. PartLibrary
7. EngineeringResourceLibrary
8. Working Folders

**Pros**:
- Database-native ordering
- Reflects database state evolution

**Cons**:
- Doesn't match screenshot
- Not intuitive to users

---

### Option 5: Hybrid Approach
**Implementation**: Combination of multiple strategies

```sql
ORDER BY
    -- Priority 1: P-folders first (P702, P736, etc.)
    CASE WHEN c.CAPTION_S_ LIKE 'P%' THEN 0 ELSE 1 END,
    -- Priority 2: Within P-folders, order by modification date
    c.MODIFICATIONDATE_DA_,
    -- Priority 3: Others by type and name
    cd.NICE_NAME,
    c.CAPTION_S_
```

**Result Order**:
1. P702 (P-folder, oldest)
2. P736 (P-folder, newer)
3. EngineeringResourceLibrary (library)
4. MfgLibrary (library)
5. PartLibrary (library)
6. DES_Studies (collection)
7. IPA (collection)
8. Working Folders (collection)

**Pros**:
- Prioritizes important P-folders
- Logical grouping
- Closer to screenshot order

**Cons**:
- Complex logic
- May not be maintainable

---

## Recommended Action

I recommend **Option 1** (current chronological ordering) or **Option 2** (manual config file) depending on your needs:

- **Choose Option 1** if: You want automatic, logical ordering that reflects when things were created
- **Choose Option 2** if: You need exact match to Siemens app order and don't mind maintaining a config file

## What I Need from You

To proceed, please clarify:

1. **Is PartInstanceLibrary important?**
   - It doesn't exist in the database - can we ignore it?

2. **Can you verify the screenshot?**
   - Is this definitely project FORD_DEARBORN (ID: 18140190)?
   - Can you take a fresh screenshot showing the current Siemens tree?

3. **What's your preference?**
   - Accept chronological ordering (Option 1)?
   - Use manual config file (Option 2)?
   - Try hybrid approach (Option 5)?
   - Something else?

## Technical Note

The fact that you said ordering is "not on the client side either" suggests it must be in the database somewhere. However, after checking:
- All columns in REL_COMMON
- All columns in COLLECTION_
- All related views and tables
- Stored procedures
- Configuration tables

I cannot find any field that stores the custom ordering. There may be:
1. A hidden/encrypted field I haven't discovered
2. Ordering stored in a BLOB or CLOB field
3. A separate Oracle schema with ordering data
4. The Siemens app using hard-coded business logic

Would you be able to share how users reorder nodes in the Siemens app? (drag-and-drop? right-click menu? properties dialog?) This might give us a clue where the ordering is stored.

## Status

🟡 **BLOCKED** - Need user input on preferred solution approach

