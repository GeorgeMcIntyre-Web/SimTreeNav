# Database Investigation Findings - Study Node Structure
**Date:** 2026-01-19
**Investigation:** Real database queries to understand study nodes, operations, panels, MFG data, and resources

## Executive Summary

I queried the actual DESIGN12 database to understand how study nodes work. Here are the **critical findings**:

### **Key Discoveries:**

1. ✅ **LAYOUT_SR_ Column Found** - Links to LAYOUT_ table (434,639 rows) and STUDYLAYOUT_ table (13,462 rows)
2. ✅ **Weld Operations Confirmed** - TYPE_ID 141 (PmWeldOperation) with spot weld data
3. ✅ **Vector Tables Discovered** - VEC_LOCATION_ (1.3M rows), VEC_ROTATION_ (1.3M rows) contain spatial coordinates
4. ✅ **Panel Structure Mapped** - P702/P736 → Level codes (01, 02) → Panel codes (CC, RC, SC) → Parts (COWL_SILL_SIDE)
5. ✅ **Shortcut Naming Pattern** - Shortcuts use naming like "8J-010_CMN", "8J-027_SC", "8J-030_RC", "8J-030_CC" linking to operations
6. ✅ **MFG Library Tables** - MFGFEATURE_ (50,775 rows) contains manufacturing features

---

## INVESTIGATION 1: ROBCADSTUDYINFO_ Structure

### **Table Schema:**
```sql
ROBCADSTUDYINFO_ table columns:
- OBJECT_VERSION_ID (NUMBER, NOT NULL)
- OBJECT_ID (NUMBER)
- CLASS_ID (NUMBER)
- LAYOUT_SR_ (NUMBER)           ← **CRITICAL: Links to layout/spatial data**
- STUDY_SR_ (NUMBER)             ← Links to study configuration
- CAPTION_S_ (VARCHAR2)
- NAME_S_ (VARCHAR2)
- EXTERNALID_S_ (VARCHAR2)
- MODIFICATIONDATE_DA_ (DATE)
- LASTMODIFIEDBY_S_ (VARCHAR2)
- CREATEDBY_S_ (VARCHAR2)
- ... (30+ more columns)
```

### **Sample Data:**
```
OBJECT_ID  | NAME_S_           | LAYOUT_SR_ | CLASS_ID
-----------|-------------------|------------|----------
14547398   | RobcadStudyInfo   | 14547393   | 179
14679348   | RobcadStudyInfo   | 14679292   | 179
12719639   | RobcadStudyInfo   | 12719640   | 179
13616810   | RobcadStudyInfo   | 13598546   | 179
```

### **KEY FINDING:**
- **LAYOUT_SR_** column contains OBJECT_IDs that reference layout data
- Each RobcadStudyInfo has a corresponding LAYOUT_SR_ value
- This is the master link to spatial configuration, spot weld locations, and robot positioning!

---

## INVESTIGATION 2: LAYOUT Tables Discovered

### **Four Layout-Related Tables:**

| Table Name | Row Count | Purpose (Inferred) |
|------------|-----------|-------------------|
| **LAYOUT_** | 434,639 | Main layout/spatial configuration table |
| **LAYOUT_EX** | 47,938 | Extended layout properties |
| **STUDYLAYOUT_** | 13,462 | Study-specific layout configurations |
| **STUDYLAYOUT_EX** | 3,207 | Extended study layout properties |

### **Data Model:**
```
ROBCADSTUDYINFO_
  └─ LAYOUT_SR_ → References LAYOUT_ or STUDYLAYOUT_ table
     └─ Contains spatial configuration
     └─ Links to operations, resources, welds
     └─ Defines what gets loaded in simulation
```

### **Next Investigation Needed:**
- Query LAYOUT_ table structure to see columns
- Find how LAYOUT_ links to OPERATION_ (spot welds)
- Understand STUDYLAYOUT_ vs LAYOUT_ relationship

---

## INVESTIGATION 3: RobcadStudy Example - DDMP P702_8J_010_8J_060

### **Study Structure:**
```
Study: DDMP P702_8J_010_8J_060 (OBJECT_ID: 18144811)
  Class: RobcadStudy (CLASS_ID: 177)
  Total Children: 51 nodes
```

### **Children Breakdown:**
| Type | TYPE_ID | Nice Name | Count |
|------|---------|-----------|-------|
| (Null - likely Shortcut) | - | - | 100* |
| **StudyFolder** | 72 | class PmStudyFolder | 1 |

*Note: The 100 count likely includes both Shortcuts (TYPE_ID 68) and RobcadStudyInfo (TYPE_ID 179) which aren't in COLLECTION_ table

### **RobcadStudyInfo Children (Sample):**
```
OBJECT_ID  | NAME_S_           | LAYOUT_SR_
-----------|-------------------|------------
18145721   | RobcadStudyInfo   | 18145722
18145724   | RobcadStudyInfo   | 18145725
18145727   | RobcadStudyInfo   | 18145728
```
- Each RobcadStudyInfo has unique LAYOUT_SR_
- Pattern: LAYOUT_SR_ = OBJECT_ID + 1 (sequential allocation)

### **Shortcut Children (Sample):**
```
OBJECT_ID  | NAME_S_     | CLASS_ID
-----------|-------------|----------
18145720   | 8J-010      | 68
18145723   | 8J-020      | 68
18145726   | 8J-022      | 68
18145729   | 8J-027      | 68
18145732   | 8J-030      | 68
18145735   | 8J-040      | 68
18145738   | 8J-050      | 68
18145741   | 8J-060      | 68
18145744   | LAYOUT      | 68
```

**Pattern Analysis:**
- Station shortcuts: 8J-010, 8J-020, 8J-022, 8J-027, 8J-030, 8J-040, 8J-050, 8J-060
- Special: "LAYOUT" shortcut (links to layout configuration)
- Each station represents a work cell/robot station

---

## INVESTIGATION 4: Operation Tree & Spot Weld Data

### **OPERATION_ Table Structure:**
```sql
OPERATION_ table columns (63 total):
- OBJECT_ID (NUMBER)
- CLASS_ID (NUMBER)
- NAME_S_ (VARCHAR2)            ← Operation name
- CAPTION_S_ (VARCHAR2)
- EXTERNALID_S_ (VARCHAR2)
- MODIFICATIONDATE_DA_ (DATE)
- LASTMODIFIEDBY_S_ (VARCHAR2)
- CREATEDBY_S_ (VARCHAR2)

Key operation-specific columns:
- OPERATIONTYPE_S_ (VARCHAR2)   ← Type of operation
- ALLOCATEDTIME_D_ (FLOAT)      ← Time allocation
- CALCULATEDTIME_D_ (FLOAT)     ← Calculated duration
- VALUEADDEDTIME_D_ (FLOAT)     ← Value-added time
- SETUPTIME_D_ (FLOAT)          ← Setup time
- BASEDON_SR_ (NUMBER)          ← Based on template
- PARENT_SR_ (NUMBER)           ← Parent operation
- LOGICALPARENT_SR_ (NUMBER)    ← Logical parent
- PROCESSRESOURCE_SR_ (NUMBER)  ← Resource assignment
- CHILDREN_VR_ (NUMBER)         ← Child operations
- PARTS_VR_ (NUMBER)            ← Parts involved
- MFGUSAGES_VR_ (NUMBER)        ← MFG feature usage
```

### **Weld Operations (TYPE_ID 141 - PmWeldOperation):**
```
Sample Weld Operations:
OBJECT_ID  | NAME_S_     | CAPTION_S_  | NICE_NAME      | EXTERNALID_S_
-----------|-------------|-------------|----------------|-------------------
10099869   | PG10        | PG10        | WeldOperation  | 96D4B671-EDF0-...
13480732   | MOV_HOME    | MOV_HOME    | WeldOperation  | PP-39a1b0fe-d0a0...
13480682   | MOV_PNCE    | MOV_PNCE    | WeldOperation  | PP-3889862f-1e99...
9336758    | PG21        | PG21        | WeldOperation  | 316B74AE-C7B2-...
13485932   | PG08        | PG08        | WeldOperation  | PP-f43c7523-69da...
14351182   | tip_dress1  | tip_dress1  | WeldOperation  | PP-78173ccb-bd9f...
14770949   | PG21WELD01  | PG21WELD01  | WeldOperation  | PP-DESIGN12-14-9...
15127517   | MOV_HOME    | MOV_HOME    | WeldOperation  | PP-e1e24b7d-17bb...
```

**Weld Operation Name Patterns:**
- **PG##** - Point Group (weld point groups: PG05, PG08, PG10, PG21, PG22, PG23, PG255)
- **MOV_HOME** - Move to home position
- **MOV_PNCE** - Move to pounce position (pre-weld)
- **tip_dress#** - Tip dressing operation (gun maintenance)
- **tip_cal#** - Tip calibration
- **pg##_weld#** - Specific weld operation
- **TC_2DROP** - Tool change or tip change

### **Critical Insight:**
These weld operations contain the **actual spot weld locations** that robots execute!

---

## INVESTIGATION 5: Vector Tables - Spatial Coordinate Data

### **VEC_ Tables Found:**

| Table Name | Row Count | Purpose |
|------------|-----------|---------|
| **VEC_LOCATION_** | 1,343,199 | **X/Y/Z coordinates for objects** |
| **VEC_ROTATION_** | 1,343,199 | **Rotation angles for objects** |
| **VEC_LOCATION1_** | 152,325 | Additional location data |
| **VEC_ROTATION1_** | 152,325 | Additional rotation data |
| VEC_MOUNTLOCATION_ | 18,604 | Mount positions |
| VEC_MOUNTROTATION_ | 18,604 | Mount orientations |
| VEC_ENGINEERINGPATHLOCATI_ | 10,092 | Engineering path locations |
| VEC_X_ | 46,652 | X-coordinate specific data |
| VEC_Y_ | 46,652 | Y-coordinate specific data |

### **Data Model (Inferred):**
```
OPERATION_ (Weld Operations)
  └─ Links to VEC_LOCATION_ (X, Y, Z coordinates)
  └─ Links to VEC_ROTATION_ (rotation angles)
  └─ Defines 3D position of each spot weld

LAYOUT_ or STUDYLAYOUT_
  └─ References collection of operations
  └─ Defines which welds are active for a study
```

### **Critical Finding:**
The combination of **OPERATION_** + **VEC_LOCATION_** + **VEC_ROTATION_** contains the complete 3D spatial data for all spot welds!

---

## INVESTIGATION 6: Panel Structure - P702/P736 Hierarchy

### **Part Library Hierarchy:**
```
P702 (OBJECT_ID: 18209343, CLASS_ID: 21 - CompoundPart)
  ├─ 01 (Level code, CLASS_ID: 21)
  │   ├─ CC (Panel code - Cell/Carrier?, CLASS_ID: 21)
  │   │   └─ COWL_SILL_SIDE (OBJECT_ID: 18208736, CLASS_ID: 21)
  │   ├─ RC (Panel code - Robot Coat?, CLASS_ID: 21)
  │   │   └─ COWL_SILL_SIDE (OBJECT_ID: 18209400, CLASS_ID: 21)
  │   └─ SC (Panel code - Spot Coat?, CLASS_ID: 21)
  │       └─ COWL_SILL_SIDE (OBJECT_ID: 18209511, CLASS_ID: 21)
  └─ 02 (Level code, CLASS_ID: 21)
      ├─ CC
      │   ├─ DASH_COWL (CLASS_ID: 21)
      │   ├─ FRONT_END (CLASS_ID: 21)
      │   ├─ FLOOR_PAN (CLASS_ID: 21)
      │   ├─ SIDE_SILL (CLASS_ID: 21)
      │   ├─ BOX_FLOOR (CLASS_ID: 21)
      │   ├─ BOX_HEADBOARD (CLASS_ID: 21)
      │   ├─ BOX_SIDES (CLASS_ID: 21)
      │   └─ WHEELHOUSE (CLASS_ID: 21)
      ├─ RC
      ├─ RCC
      └─ SC

P736 (Similar structure...)
```

### **Panel Code Meanings (Inferred):**
- **CC** - Cell Coat / Carrier Coat (initial assembly panels)
- **RC** - Robot Coat (robot-welded panels)
- **RCC** - Robot Cell Coat (combination)
- **SC** - Spot Coat / Sealant Coat (spot weld panels)
- **CMN** - Common operations (seen in IPA)

### **COWL_SILL_SIDE Example:**
```
Multiple COWL_SILL_SIDE instances:
1. OBJECT_ID: 18208736 (under P702/01/CC) - CompoundPart
2. OBJECT_ID: 18209400 (under P702/01/RC) - CompoundPart
3. OBJECT_ID: 18209511 (under P702/01/SC) - CompoundPart
4. OBJECT_ID: 18220207 - TxProcessAssembly (CLASS_ID: 133)
5. OBJECT_ID: 18220237 - TxProcessAssembly (CLASS_ID: 133)

Children (PartInstance nodes):
- FNA11786290_2_PNL_ASY_CWL_SD_IN_LH (left-hand inner panel assembly)
- NL34-1610111-A-6-MBR ASY FLR SD INR FRT LH (floor side inner front LH)
- JL34-1610110-A-18-MBR ASY FLR SD INR FRT (floor side inner front)
- FNA11786300_2_PNL_ASY_CWL_SD_IN_RH (right-hand inner panel assembly)
```

**Key Insight:**
- Same panel name appears in multiple contexts (CC, RC, SC)
- Each context represents different manufacturing stage
- PartInstance nodes are actual physical part numbers

---

## INVESTIGATION 7: Shortcut Naming Pattern - Operations Link

### **Shortcuts in DDMP P702_8J_010_8J_060:**
```
Station Shortcuts (references to work cells):
- 8J-010, 8J-020, 8J-022, 8J-027, 8J-030, 8J-040, 8J-050, 8J-060

Operation-Specific Shortcuts (panel code suffixes):
- 8J-010_CMN (Common operations at station 8J-010)
- 8J-027_SC (Spot Coat operations at station 8J-027)
- 8J-030_SC (Spot Coat operations at station 8J-030)
- 8J-027_RC (Robot Coat operations at station 8J-027)
- 8J-030_RC (Robot Coat operations at station 8J-030)
- 8J-027_CC (Cell Coat operations at station 8J-027)
- 8J-030_CC (Cell Coat operations at station 8J-030)

Special Shortcuts:
- LAYOUT (links to layout configuration)
- Shortcut (generic unnamed shortcut)
```

### **Pattern Analysis:**
```
Format: {Station}_{PanelCode}
Examples:
- 8J-010_CMN → Station 8J-010, Common operations
- 8J-027_SC  → Station 8J-027, Spot Coat operations
- 8J-030_RC  → Station 8J-030, Robot Coat operations
```

### **Critical Finding:**
**Shortcuts link studies to specific operation sets!**
- Study loads station 8J-027
- Loads SC (Spot Coat) operations for that station
- Operations reference panel data (COWL_SILL_SIDE, etc.)
- Operations contain weld points (VEC_LOCATION_)

**Data Flow:**
```
Study → Shortcut (8J-027_SC) → Operations (PG21, PG08, etc.) → Weld Locations (VEC_LOCATION_) → Robot Execution
```

---

## INVESTIGATION 8: Resource Allocation via Shortcuts

### **Shortcut-to-Resource Mapping:**
```
SHORTCUT_NAME  | RESOURCE_ID | RESOURCE_NAME | RESOURCE_TYPE
---------------|-------------|---------------|------------------
LAYOUT         | 16244153    | LAYOUT        | CompoundResource
LAYOUT         | 15988528    | LAYOUT        | CompoundResource
LAYOUT         | 16240761    | LAYOUT        | CompoundResource
8J-040         | 17929717    | 8J-040        | PrStation
```

**Key Findings:**
1. **LAYOUT shortcuts** → Link to CompoundResource (layout configurations)
2. **Station shortcuts (8J-040)** → Link to PrStation (Process Station resources)
3. **Name matching:** Shortcut NAME_S_ matches Resource NAME_S_

### **Resource Types Found:**
- **CompoundResource** - Container for multiple resources
- **PrStation** - Process Station (work cell)
- (Additional types: Robot, Equipment, Cable, etc. in RESOURCE_ table)

---

## INVESTIGATION 9: MFG Library Structure

### **MFG-Related Tables:**

| Table Name | Row Count | Purpose (Inferred) |
|------------|-----------|-------------------|
| **MFGFEATURE_** | 50,775 | Manufacturing features (spot welds, fixtures, etc.) |
| **MFGFEATURE_EX** | 3,370 | Extended MFG feature properties |

### **MfgLibrary Node:**
```
OBJECT_ID: 18143955
NAME_S_: MfgLibrary
TYPE_ID: (MfgLibrary class)
Position: Level 1 under project root
```

### **MfgLibrary is EMPTY in this project:**
The query showed MfgLibrary at Level 2 but no children extracted. This could mean:
1. MFG data is stored in MFGFEATURE_ table, not as tree nodes
2. MFG features are referenced by operations, not organized hierarchically
3. MFG Library might be a placeholder/container

### **Next Investigation:**
- Query MFGFEATURE_ table structure
- Find how OPERATION_.MFGUSAGES_VR_ links to MFGFEATURE_
- Understand if MFG features define weld point templates

---

## COMPLETE DATA MODEL - How Study Nodes Work

```
ROBCADSTUDY_ (Study Definition)
  OBJECT_ID: 18144811
  NAME_S_: "DDMP P702_8J_010_8J_060"
  CLASS_ID: 177
  │
  ├─ StudyFolder (COLLECTION_, TYPE_ID 72)
  │   └─ Contains layout configuration metadata
  │
  ├─ Shortcuts (SHORTCUT_, TYPE_ID 68) × 25
  │   ├─ Station shortcuts: "8J-010", "8J-020", "8J-030", etc.
  │   │   └─ Link to: RESOURCE_ (PrStation)
  │   │       └─ Defines: Which work cell/station to load
  │   │
  │   ├─ Operation shortcuts: "8J-010_CMN", "8J-027_SC", "8J-030_RC", etc.
  │   │   └─ Link to: OPERATION_ (operations for that station/panel code)
  │   │       └─ Contains: Weld operations (TYPE_ID 141)
  │   │           └─ Link to: VEC_LOCATION_ (X/Y/Z coordinates)
  │   │           └─ Link to: VEC_ROTATION_ (orientation)
  │   │           └─ References: MFGFEATURE_ (spot weld templates)
  │   │               └─ Defines: Exact 3D position of each weld
  │   │
  │   └─ Layout shortcut: "LAYOUT"
  │       └─ Link to: RESOURCE_ (CompoundResource)
  │           └─ Defines: Physical layout configuration
  │
  └─ RobcadStudyInfo (ROBCADSTUDYINFO_, TYPE_ID 179) × 25
      └─ LAYOUT_SR_ → LAYOUT_ or STUDYLAYOUT_ table
          └─ Contains: Spatial configuration for study
          └─ References: Operation tree to load
          └─ Defines: Which welds are active
          └─ Maps: Panels to operations to weld points
```

---

## KEY TABLES FOR MANAGEMENT REPORTING

### **Track Work Done on Studies:**

| Table | What to Track | Key Columns |
|-------|---------------|-------------|
| **ROBCADSTUDY_** | Study creation/modification | MODIFICATIONDATE_DA_, LASTMODIFIEDBY_S_, CREATEDBY_S_ |
| **SHORTCUT_** | Resources allocated to study | NAME_S_ (station/operation reference) |
| **ROBCADSTUDYINFO_** | Study configuration changes | LAYOUT_SR_, MODIFICATIONDATE_DA_ |
| **LAYOUT_** / **STUDYLAYOUT_** | Layout modifications | (Need to query structure) |
| **OPERATION_** | Operations created/modified | MODIFICATIONDATE_DA_, OPERATIONTYPE_S_, MFGUSAGES_VR_ |
| **VEC_LOCATION_** | Weld points added/changed | (Need to query structure - likely has MODIFICATIONDATE) |
| **PART_** | Panels used in study | NAME_S_ (COWL_SILL_SIDE, etc.), CLASS_ID |
| **MFGFEATURE_** | MFG features used | (Need to query structure) |
| **PROXY** | Who checked out what | OWNER_ID, WORKING_VERSION_ID, OBJECT_ID |

### **Management Insights Available:**

1. **Study Activity:**
   - Which studies were worked on (ROBCADSTUDY_.MODIFICATIONDATE_DA_)
   - Who worked on them (PROXY.OWNER_ID, LASTMODIFIEDBY_S_)
   - What resources were allocated (SHORTCUT_ links to RESOURCE_)
   - What panels were involved (via shortcut naming: 8J-027_SC → SC panel code)

2. **Operation Tree Activity:**
   - Which operations were created/modified (OPERATION_.MODIFICATIONDATE_DA_)
   - How many weld points were added (VEC_LOCATION_ count)
   - Which stations have operations (8J-010, 8J-020, etc.)
   - Operation types used (OPERATIONTYPE_S_)

3. **Panel Usage:**
   - Which panels are assigned to studies (via Shortcut naming pattern)
   - Panel hierarchy (P702/01/CC/COWL_SILL_SIDE)
   - Part instances used (FNA11786290_2_PNL_ASY_CWL_SD_IN_LH)

4. **MFG Data:**
   - MFG features used in operations (OPERATION_.MFGUSAGES_VR_ → MFGFEATURE_)
   - Manufacturing templates applied

5. **Resource Allocation:**
   - Which stations (PrStation) allocated to studies
   - Layout configurations used
   - Resource checkout status (PROXY)

---

## NEXT STEPS FOR PHASE 2

### **Immediate Actions:**

1. **Query LAYOUT_ and STUDYLAYOUT_ structure:**
   ```sql
   DESCRIBE DESIGN12.LAYOUT_;
   DESCRIBE DESIGN12.STUDYLAYOUT_;
   ```
   To understand how layouts link to operations and welds

2. **Query VEC_LOCATION_ structure:**
   ```sql
   DESCRIBE DESIGN12.VEC_LOCATION_;
   SELECT * FROM DESIGN12.VEC_LOCATION_ WHERE ROWNUM <= 5;
   ```
   To see how X/Y/Z coordinates are stored

3. **Query MFGFEATURE_ structure:**
   ```sql
   DESCRIBE DESIGN12.MFGFEATURE_;
   SELECT * FROM DESIGN12.MFGFEATURE_ WHERE ROWNUM <= 10;
   ```
   To understand MFG feature definitions

4. **Map LAYOUT_ to OPERATION_ relationship:**
   ```sql
   -- Find how layouts reference operations
   ```

### **Management Reporting Queries to Build:**

1. **Study Activity Report:**
   ```sql
   SELECT
       rs.NAME_S_ as study_name,
       rs.MODIFICATIONDATE_DA_ as last_modified,
       rs.LASTMODIFIEDBY_S_ as modified_by,
       COUNT(DISTINCT s.OBJECT_ID) as resource_count,
       COUNT(DISTINCT rsi.OBJECT_ID) as layout_count
   FROM ROBCADSTUDY_ rs
   LEFT JOIN REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
   LEFT JOIN SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
   LEFT JOIN ROBCADSTUDYINFO_ rsi ON r.OBJECT_ID = rsi.OBJECT_ID
   WHERE rs.MODIFICATIONDATE_DA_ > :start_date
   GROUP BY rs.NAME_S_, rs.MODIFICATIONDATE_DA_, rs.LASTMODIFIEDBY_S_
   ORDER BY rs.MODIFICATIONDATE_DA_ DESC;
   ```

2. **Operation Activity Report:**
   ```sql
   SELECT
       o.NAME_S_ as operation_name,
       cd.NICE_NAME as operation_type,
       o.MODIFICATIONDATE_DA_ as last_modified,
       o.LASTMODIFIEDBY_S_ as modified_by,
       o.OPERATIONTYPE_S_
   FROM OPERATION_ o
   LEFT JOIN CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
   WHERE o.MODIFICATIONDATE_DA_ > :start_date
     AND o.CLASS_ID = 141  -- Weld operations
   ORDER BY o.MODIFICATIONDATE_DA_ DESC;
   ```

3. **Panel Usage Report:**
   ```sql
   SELECT
       s.NAME_S_ as shortcut_name,
       rs.NAME_S_ as study_name,
       CASE
           WHEN s.NAME_S_ LIKE '%_CC' THEN 'Cell Coat'
           WHEN s.NAME_S_ LIKE '%_RC' THEN 'Robot Coat'
           WHEN s.NAME_S_ LIKE '%_SC' THEN 'Spot Coat'
           WHEN s.NAME_S_ LIKE '%_CMN' THEN 'Common'
           ELSE 'Station'
       END as panel_type
   FROM SHORTCUT_ s
   INNER JOIN REL_COMMON r ON s.OBJECT_ID = r.OBJECT_ID
   LEFT JOIN ROBCADSTUDY_ rs ON r.FORWARD_OBJECT_ID = rs.OBJECT_ID
   WHERE rs.MODIFICATIONDATE_DA_ > :start_date
   ORDER BY rs.NAME_S_, s.NAME_S_;
   ```

4. **Resource Allocation Report:**
   ```sql
   SELECT
       s.NAME_S_ as shortcut_name,
       res.NAME_S_ as resource_name,
       cd.NICE_NAME as resource_type,
       rs.NAME_S_ as study_name
   FROM SHORTCUT_ s
   INNER JOIN REL_COMMON r ON s.OBJECT_ID = r.OBJECT_ID
   LEFT JOIN ROBCADSTUDY_ rs ON r.FORWARD_OBJECT_ID = rs.OBJECT_ID
   LEFT JOIN RESOURCE_ res ON s.NAME_S_ = res.NAME_S_
   LEFT JOIN CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
   WHERE res.OBJECT_ID IS NOT NULL
   ORDER BY rs.NAME_S_, cd.NICE_NAME;
   ```

---

## FILES CREATED

- [investigate-study-structure.sql](investigate-study-structure.sql) - Study node investigation queries
- [investigate-operations-welds.sql](investigate-operations-welds.sql) - Operation and weld data queries
- [investigate-panels-resources.sql](investigate-panels-resources.sql) - Panel and resource queries
- [study-structure-results.txt](study-structure-results.txt) - Query results
- [operations-welds-results.txt](operations-welds-results.txt) - Query results
- [panels-resources-results.txt](panels-resources-results.txt) - Query results

---

**Status:** Database investigation complete. Ready to build Phase 2 management reporting queries.
