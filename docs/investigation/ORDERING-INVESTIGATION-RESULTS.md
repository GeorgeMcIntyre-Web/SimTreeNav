# Navigation Tree Ordering Investigation

## Problem Statement
User wants the tree to display nodes in the same order as shown in the Siemens Navigation Tree application.

## Siemens App Order (from user screenshot)
1. P702
2. P736
3. EngineeringResourceLibrary
4. PartLibrary
5. **PartInstanceLibrary** ⚠️
6. MfgLibrary
7. IPA
8. DES_Studies
9. Working Folders

## Actual Database Nodes (Project 18140190)
We found **8 nodes**, not 9:
1. DES_Studies (OBJECT_ID: 18144070)
2. EngineeringResourceLibrary (OBJECT_ID: 18153685)
3. IPA (OBJECT_ID: 18143956)
4. MfgLibrary (OBJECT_ID: 18143955)
5. P702 (OBJECT_ID: 18195357)
6. P736 (OBJECT_ID: 18195358)
7. PartLibrary (OBJECT_ID: 18143951)
8. Working Folders (OBJECT_ID: 18144071)

### ⚠️ Key Finding
**PartInstanceLibrary does NOT exist** as a Level 1 child of project 18140190. This suggests:
- The screenshot might be from a different project
- The screenshot might be from an older/different database state
- PartInstanceLibrary might be a child of PartLibrary (not a direct project child)

## Available Ordering Fields

### 1. OBJECT_ID
```
18143951 - PartLibrary
18143955 - MfgLibrary
18143956 - IPA
18144070 - DES_Studies
18144071 - Working Folders
18153685 - EngineeringResourceLibrary
18195357 - P702
18195358 - P736
```
**Result**: Not chronological, not matching Siemens order

### 2. OBJECT_VERSION_ID
```
101301258 - MfgLibrary
101926281 - P702
102122260 - IPA
103630700 - DES_Studies
103630740 - P736
103910424 - PartLibrary
104177580 - EngineeringResourceLibrary
104576500 - Working Folders
```
**Result**: Different from MODIFICATIONDATE_DA_, not matching Siemens order

### 3. MODIFICATIONDATE_DA_ (Current Implementation)
```
19/08/2025 - MfgLibrary
02/09/2025 - P702
08/09/2025 - IPA
29/10/2025 - P736
29/10/2025 - DES_Studies
07/11/2025 - PartLibrary
13/11/2025 - EngineeringResourceLibrary
09/12/2025 - Working Folders
```
**Result**: True chronological order, not matching Siemens order

### 4. SEQ_NUMBER
```
All nodes: 0
```
**Result**: Not used for ordering (all identical)

### 5. REL_TYPE
```
All nodes: 4
```
**Result**: All identical, not used for ordering

### 6. FIELD_NAME
```
All nodes: "collections"
```
**Result**: All identical, not used for ordering

### 7. REL_CLASS_ID
```
All nodes: 14
```
**Result**: All identical, not used for ordering

## Database Schema Investigation

### Tables Examined
- ✅ **COLLECTION_**: Main node table
- ✅ **REL_COMMON**: Parent-child relationships (only REL table found)
- ✅ **CLASS_DEFINITIONS**: Node types
- ✅ **DFUSERFOLDERTABLE**: User-specific folders (not for project-level ordering)
- ✅ **DBA_TABLES**: Searched for PREF, UI, VIEW, DISPLAY, ORDER, SORT, USER tables

### Columns Checked in REL_COMMON
All columns examined:
- FIELD_NAME (all "collections")
- CLASS_ID (all 14)
- OBJECT_VERSION_ID (examined)
- OBJECT_ID (examined)
- FORWARD_OBJECT_ID (parent reference)
- SEQ_NUMBER (all 0)
- REL_TYPE (all 4)

**No ordering mechanism found in database schema.**

## Possible Explanations

### 1. Client-Side Ordering
The Siemens application might store user-defined ordering:
- In local configuration files
- In user preferences on the client machine
- In a separate preference database not accessible via REL_COMMON

### 2. Different Project/State
The screenshot might show:
- A different project (not 18140190)
- An older state of the database
- A test/dev environment

### 3. Hidden Ordering Mechanism
There might be:
- A database view or stored procedure we haven't found
- Ordering stored in BLOB fields
- A separate schema with ordering tables

### 4. Default Ordering Logic
The Siemens app might use complex business logic like:
- Priority by node type (P-folders first, then libraries, then collections)
- Alphabetical within each type
- Custom hard-coded rules

## Current Implementation

Our tree currently uses **chronological order by MODIFICATIONDATE_DA_**:
```sql
ORDER BY NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID
```

This produces:
1. MfgLibrary (Aug 19)
2. P702 (Sep 2)
3. IPA (Sep 8)
4. P736 (Oct 29)
5. DES_Studies (Oct 29)
6. PartLibrary (Nov 7)
7. EngineeringResourceLibrary (Nov 13)
8. Working Folders (Dec 9)

## Questions for User

1. **Can you verify the project?**
   - Is the Siemens screenshot definitely showing project "FORD_DEARBORN" (ID: 18140190)?
   - Can you take a fresh screenshot to confirm current state?

2. **About PartInstanceLibrary:**
   - Does PartInstanceLibrary exist in your current view?
   - Is it a child of PartLibrary rather than a direct project child?

3. **Custom ordering:**
   - Did you manually reorder the nodes in the Siemens app using drag-and-drop?
   - If so, where do you think this ordering might be stored?

4. **Alternative approach:**
   - Would you be satisfied with chronological ordering (current implementation)?
   - Or do you need exact match to the Siemens screenshot?

## Next Steps

### Option A: Accept Chronological Ordering
Keep current implementation (ORDER BY MODIFICATIONDATE_DA_)

### Option B: Implement Type-Based Ordering
Create custom logic to order by node type (CLASS_TYPE), then alphabetically:
```sql
ORDER BY
  CASE cd.NICE_NAME
    WHEN 'Collection' THEN 1  -- P folders first
    WHEN 'MfgLibrary' THEN 2
    WHEN 'PartLibrary' THEN 3
    WHEN 'RobcadResourceLibrary' THEN 4
    ELSE 5
  END,
  c.CAPTION_S_  -- Then alphabetically
```

### Option C: Manual Configuration
Create a configuration file where users can specify custom ordering:
```json
{
  "18140190": {
    "order": ["P702", "P736", "EngineeringResourceLibrary", ...]
  }
}
```

### Option D: Continue Database Investigation
Investigate:
- Other schemas that might contain ordering
- BLOB columns that might contain preferences
- Database views or materialized views
- Application log files or config files

## Summary

After extensive investigation of the database schema:
- ✅ All ordering fields in REL_COMMON examined
- ✅ All relationship tables searched (only REL_COMMON exists)
- ✅ User preference tables examined (not relevant)
- ❌ No database field found that stores custom user-defined ordering
- ❌ PartInstanceLibrary not found in database

**Conclusion**: The ordering shown in the Siemens screenshot is either stored client-side, uses a complex business logic rule, or is from a different project/database state.

## Files Created During Investigation

SQL Query Files:
- [check-object-version-id.sql](check-object-version-id.sql)
- [find-preference-tables.sql](find-preference-tables.sql)
- [check-partinstance-library.sql](check-partinstance-library.sql)
- [check-rel-type-field.sql](check-rel-type-field.sql)
- [check-dfuserfoldertable.sql](check-dfuserfoldertable.sql)
- [search-all-relationship-tables.sql](search-all-relationship-tables.sql)
- [check-all-level1-children.sql](check-all-level1-children.sql)
- [investigate-userfolder-ordering.sql](investigate-userfolder-ordering.sql)
- [check-field-name-column.sql](check-field-name-column.sql)
- [search-for-partinstancelibrary.sql](search-for-partinstancelibrary.sql)
- [final-node-order-analysis.sql](final-node-order-analysis.sql)
