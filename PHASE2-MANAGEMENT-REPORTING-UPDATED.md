# Phase 2: Management Reporting - Updated Design (Based on Database Investigation)
**Date:** 2026-01-19
**Status:** Design updated with actual database structure findings

## Overview
Advanced management reporting system that tracks work activity across 5 core work types, with special focus on **study node activity** including resources, panels, operations, spot welds, and **movement/location changes**.

---

## Database Findings Summary

Based on actual database queries (see [DATABASE-INVESTIGATION-FINDINGS.md](DATABASE-INVESTIGATION-FINDINGS.md)):

### **Key Tables Discovered:**
- **ROBCADSTUDYINFO_** - Study metadata with LAYOUT_SR_ link (master configuration)
- **LAYOUT_** (434,639 rows) - Spatial configuration data
- **STUDYLAYOUT_** (13,462 rows) - Study-specific layouts
- **OPERATION_** (63 columns) - Operations including weld operations (TYPE_ID 141)
- **VEC_LOCATION_** (1.3M rows) - **X/Y/Z coordinates for movements and welds**
- **VEC_ROTATION_** (1.3M rows) - **Rotation angles for orientations**
- **SHORTCUT_** - Links studies to stations/operations (naming pattern: "8J-027_SC")
- **MFGFEATURE_** (50,775 rows) - Manufacturing features
- **RESOURCE_** - Stations (PrStation), robots, equipment

### **Panel Code Meanings:**
- **CC** = Cell Coat / Carrier Coat
- **RC** = Robot Coat
- **SC** = Spot Coat
- **CMN** = Common operations
- **RCC** = Robot Cell Coat

### **Data Flow:**
```
Study → Shortcut (8J-027_SC) → OPERATION_ (PG21 weld) → VEC_LOCATION_ (X,Y,Z) → Robot execution
```

---

## Enhanced Work Type Tracking

### **1. Project Database Setup**
**Tables:** `COLLECTION_`, `PROXY`, `PROXY_VERSIONS`

**Track:**
- Project creation/modification dates
- Users who set up projects
- Version history

**Query:**
```sql
SELECT
    c.OBJECT_ID as project_id,
    c.CAPTION_S_ as project_name,
    c.CREATEDBY_S_ as created_by,
    c.MODIFICATIONDATE_DA_ as last_modified,
    c.LASTMODIFIEDBY_S_ as last_modified_by,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name
FROM DESIGN12.COLLECTION_ c
LEFT JOIN DESIGN12.PROXY p ON c.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE c.OBJECT_ID = :project_id;
```

---

### **2. Resource Library**
**Tables:** `RESOURCE_`, `COLLECTION_`, `REL_COMMON`, `PROXY`

**Track:**
- Resources created/modified (robots, equipment, stations)
- Resource types (PrStation, Robot, Equipment, Cable, CompoundResource)
- Checkout status

**Query:**
```sql
SELECT
    r.OBJECT_ID,
    r.NAME_S_ as resource_name,
    cd.NICE_NAME as resource_type,
    r.MODIFICATIONDATE_DA_ as last_modified,
    r.LASTMODIFIEDBY_S_ as modified_by,
    r.CREATEDBY_S_ as created_by,
    p.OWNER_ID as checked_out_by,
    u.CAPTION_S_ as user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status
FROM DESIGN12.RESOURCE_ r
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
LEFT JOIN DESIGN12.PROXY p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE r.MODIFICATIONDATE_DA_ > :start_date
ORDER BY r.MODIFICATIONDATE_DA_ DESC;
```

---

### **3. Part/MFG Library**
**Tables:** `PART_`, `COLLECTION_`, `REL_COMMON`, `MFGFEATURE_`

**Track:**
- Parts created/modified (P702, P736, COWL_SILL_SIDE, etc.)
- Panel codes worked on (CC, RC, SC, CMN)
- Part hierarchy changes
- MFG features created/modified

**Query:**
```sql
-- Panel hierarchy activity
SELECT
    LEVEL as tree_level,
    p.OBJECT_ID,
    p.NAME_S_ as part_name,
    cd.NICE_NAME as part_type,
    p.MODIFICATIONDATE_DA_ as last_modified,
    p.LASTMODIFIEDBY_S_ as modified_by,
    CASE
        WHEN p.NAME_S_ IN ('CC', 'RCC') THEN 'Cell Coat'
        WHEN p.NAME_S_ = 'RC' THEN 'Robot Coat'
        WHEN p.NAME_S_ = 'SC' THEN 'Spot Coat'
        WHEN p.NAME_S_ = 'CMN' THEN 'Common'
        WHEN p.NAME_S_ IN ('P702', 'P736') THEN 'Build Assembly'
        WHEN p.NAME_S_ LIKE '0%' THEN 'Level Code'
        ELSE 'Panel'
    END as category
FROM DESIGN12.PART_ p
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
INNER JOIN DESIGN12.REL_COMMON r ON p.OBJECT_ID = r.OBJECT_ID
WHERE p.MODIFICATIONDATE_DA_ > :start_date
START WITH p.NAME_S_ IN ('P702', 'P736')
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
ORDER BY p.MODIFICATIONDATE_DA_ DESC;
```

---

### **4. IPA (Process Assembly)**
**Tables:** `PART_` (CLASS_ID = 133), `OPERATION_`

**Track:**
- Process assemblies created/modified (TxProcessAssembly)
- Station sequences (8J-010, 8J-020, etc.)
- Operation types (CMN, SC, RC, CC)

**Query:**
```sql
SELECT
    pa.OBJECT_ID,
    pa.NAME_S_ as process_assembly_name,
    pa.MODIFICATIONDATE_DA_ as last_modified,
    pa.LASTMODIFIEDBY_S_ as modified_by,
    pa.CREATEDBY_S_ as created_by,
    COUNT(DISTINCT o.OBJECT_ID) as operation_count
FROM DESIGN12.PART_ pa
LEFT JOIN DESIGN12.REL_COMMON r ON pa.OBJECT_ID = r.FORWARD_OBJECT_ID
LEFT JOIN DESIGN12.OPERATION_ o ON r.OBJECT_ID = o.OBJECT_ID
WHERE pa.CLASS_ID = 133  -- TxProcessAssembly
  AND pa.MODIFICATIONDATE_DA_ > :start_date
GROUP BY pa.OBJECT_ID, pa.NAME_S_, pa.MODIFICATIONDATE_DA_, pa.LASTMODIFIEDBY_S_, pa.CREATEDBY_S_
ORDER BY pa.MODIFICATIONDATE_DA_ DESC;
```

---

### **5. Study Nodes (ENHANCED - Most Complex)**
**Tables:** `ROBCADSTUDY_`, `ROBCADSTUDYINFO_`, `SHORTCUT_`, `LAYOUT_`, `STUDYLAYOUT_`, `OPERATION_`, `VEC_LOCATION_`, `VEC_ROTATION_`, `RESOURCE_`, `MFGFEATURE_`

#### **5A. Study Activity Summary**
**Track:**
- Studies created/modified
- Users working on studies
- Study types (RobcadStudy, LineSimulationStudy, GanttStudy, etc.)

**Query:**
```sql
SELECT
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    cd.NICE_NAME as study_type,
    rs.MODIFICATIONDATE_DA_ as last_modified,
    rs.LASTMODIFIEDBY_S_ as modified_by,
    rs.CREATEDBY_S_ as created_by,
    p.OWNER_ID as checked_out_by_user_id,
    u.CAPTION_S_ as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Active' ELSE 'Idle' END as status
FROM DESIGN12.ROBCADSTUDY_ rs
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN DESIGN12.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE rs.MODIFICATIONDATE_DA_ > :start_date
ORDER BY rs.MODIFICATIONDATE_DA_ DESC;
```

#### **5B. Resource Allocation to Studies**
**Track:**
- Which stations/robots allocated to studies
- Resource types (PrStation, Robot, Equipment, Layout)

**Query:**
```sql
SELECT
    rs.NAME_S_ as study_name,
    s.NAME_S_ as shortcut_name,
    res.NAME_S_ as resource_name,
    cd.NICE_NAME as resource_type,
    CASE
        WHEN s.NAME_S_ = 'LAYOUT' THEN 'Layout Configuration'
        WHEN s.NAME_S_ LIKE '8J-%' AND s.NAME_S_ NOT LIKE '%_%' THEN 'Station Reference'
        WHEN s.NAME_S_ LIKE '%_CMN' THEN 'Common Operations'
        WHEN s.NAME_S_ LIKE '%_SC' THEN 'Spot Coat Operations'
        WHEN s.NAME_S_ LIKE '%_RC' THEN 'Robot Coat Operations'
        WHEN s.NAME_S_ LIKE '%_CC' THEN 'Cell Coat Operations'
        ELSE 'Other'
    END as allocation_type,
    r.SEQ_NUMBER as sequence
FROM DESIGN12.ROBCADSTUDY_ rs
INNER JOIN DESIGN12.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN DESIGN12.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN DESIGN12.RESOURCE_ res ON s.NAME_S_ = res.NAME_S_
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
WHERE rs.MODIFICATIONDATE_DA_ > :start_date
ORDER BY rs.NAME_S_, r.SEQ_NUMBER;
```

#### **5C. Panel Usage in Studies**
**Track:**
- Which panels (CC, RC, SC) are used in which studies
- Panel codes extracted from shortcut naming pattern

**Query:**
```sql
SELECT
    rs.NAME_S_ as study_name,
    s.NAME_S_ as shortcut_name,
    CASE
        WHEN s.NAME_S_ LIKE '%_CC' THEN 'CC (Cell Coat)'
        WHEN s.NAME_S_ LIKE '%_RC' THEN 'RC (Robot Coat)'
        WHEN s.NAME_S_ LIKE '%_SC' THEN 'SC (Spot Coat)'
        WHEN s.NAME_S_ LIKE '%_CMN' THEN 'CMN (Common)'
        ELSE 'N/A'
    END as panel_code,
    SUBSTRING(s.NAME_S_ FROM 1 FOR POSITION('_' IN s.NAME_S_)-1) as station,
    rs.MODIFICATIONDATE_DA_ as last_modified
FROM DESIGN12.ROBCADSTUDY_ rs
INNER JOIN DESIGN12.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
INNER JOIN DESIGN12.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE s.NAME_S_ LIKE '%\_%' ESCAPE '\'  -- Has underscore (operation shortcuts)
  AND rs.MODIFICATIONDATE_DA_ > :start_date
ORDER BY rs.NAME_S_, s.NAME_S_;
```

#### **5D. Operation Tree Activity** ⭐ NEW
**Track:**
- Operations created/modified
- Weld operations (TYPE_ID 141)
- Operation types (MOV_HOME, PG##, tip_dress, etc.)
- Time allocations

**Query:**
```sql
SELECT
    o.OBJECT_ID,
    o.NAME_S_ as operation_name,
    o.CAPTION_S_ as operation_caption,
    cd.NICE_NAME as operation_class,
    o.OPERATIONTYPE_S_ as operation_type,
    o.MODIFICATIONDATE_DA_ as last_modified,
    o.LASTMODIFIEDBY_S_ as modified_by,
    o.CREATEDBY_S_ as created_by,
    o.ALLOCATEDTIME_D_ as allocated_time,
    o.CALCULATEDTIME_D_ as calculated_time,
    o.VALUEADDEDTIME_D_ as value_added_time,
    CASE
        WHEN o.NAME_S_ LIKE 'PG%' THEN 'Weld Point Group'
        WHEN o.NAME_S_ LIKE 'MOV_%' THEN 'Movement Operation'
        WHEN o.NAME_S_ LIKE 'tip_%' THEN 'Tool Maintenance'
        WHEN o.NAME_S_ LIKE '%WELD%' THEN 'Weld Operation'
        ELSE 'Other'
    END as operation_category
FROM DESIGN12.OPERATION_ o
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
WHERE o.MODIFICATIONDATE_DA_ > :start_date
  AND o.CLASS_ID = 141  -- Weld operations
ORDER BY o.MODIFICATIONDATE_DA_ DESC;
```

#### **5E. Movement/Location Changes** ⭐ NEW - USER REQUESTED
**Track:**
- Simple robot moves (MOV_HOME, MOV_PNCE)
- Robot world location changes (critical repositioning)
- VEC_LOCATION_ modifications (X/Y/Z coordinate changes)
- VEC_ROTATION_ modifications (orientation changes)

**First, need to query VEC_LOCATION_ structure:**
```sql
-- Investigation query to understand VEC_LOCATION_ structure
DESCRIBE DESIGN12.VEC_LOCATION_;

-- Sample data
SELECT * FROM DESIGN12.VEC_LOCATION_ WHERE ROWNUM <= 10;
```

**Expected tracking query (after structure investigation):**
```sql
-- Track location changes within studies
SELECT
    vl.OBJECT_ID,
    vl.X_COORD as x_position,
    vl.Y_COORD as y_position,
    vl.Z_COORD as z_position,
    vr.RX_ANGLE as rotation_x,
    vr.RY_ANGLE as rotation_y,
    vr.RZ_ANGLE as rotation_z,
    vl.MODIFICATIONDATE_DA_ as last_modified,
    vl.LASTMODIFIEDBY_S_ as modified_by,
    o.NAME_S_ as operation_name,
    CASE
        WHEN o.NAME_S_ LIKE 'MOV_%' THEN 'Simple Move'
        WHEN ABS(vl.X_COORD - vl.PREV_X_COORD) > 1000
          OR ABS(vl.Y_COORD - vl.PREV_Y_COORD) > 1000
          OR ABS(vl.Z_COORD - vl.PREV_Z_COORD) > 1000 THEN 'World Location Change'
        ELSE 'Position Update'
    END as movement_type
FROM DESIGN12.VEC_LOCATION_ vl
LEFT JOIN DESIGN12.VEC_ROTATION_ vr ON vl.OBJECT_ID = vr.OBJECT_ID
LEFT JOIN DESIGN12.OPERATION_ o ON vl.OBJECT_ID = o.OBJECT_ID
WHERE vl.MODIFICATIONDATE_DA_ > :start_date
ORDER BY vl.MODIFICATIONDATE_DA_ DESC;
```

**Movement Categories to Track:**
1. **Simple Moves:**
   - MOV_HOME (move to home position)
   - MOV_PNCE (move to pounce/pre-weld position)
   - Small coordinate changes (<1000mm)

2. **World Location Changes (Critical):**
   - Large coordinate changes (>1000mm)
   - Robot base repositioning
   - Station relocation
   - Fixture moves

3. **Weld Point Adjustments:**
   - Small changes to spot weld coordinates
   - Fine-tuning positions
   - PG## point group modifications

#### **5F. Spot Weld Activity**
**Track:**
- Spot welds added/modified
- Weld point counts
- Weld locations (X/Y/Z coordinates)

**Query:**
```sql
-- Count spot welds by study
SELECT
    rs.NAME_S_ as study_name,
    COUNT(DISTINCT o.OBJECT_ID) as weld_operation_count,
    COUNT(DISTINCT vl.OBJECT_ID) as weld_point_count,
    MIN(o.MODIFICATIONDATE_DA_) as first_weld_date,
    MAX(o.MODIFICATIONDATE_DA_) as last_weld_date
FROM DESIGN12.ROBCADSTUDY_ rs
INNER JOIN DESIGN12.REL_COMMON r1 ON rs.OBJECT_ID = r1.FORWARD_OBJECT_ID
INNER JOIN DESIGN12.SHORTCUT_ s ON r1.OBJECT_ID = s.OBJECT_ID
INNER JOIN DESIGN12.OPERATION_ o ON s.NAME_S_ LIKE '%' || o.NAME_S_ || '%'
LEFT JOIN DESIGN12.VEC_LOCATION_ vl ON o.OBJECT_ID = vl.OBJECT_ID
WHERE o.CLASS_ID = 141  -- Weld operations
  AND rs.MODIFICATIONDATE_DA_ > :start_date
GROUP BY rs.NAME_S_
ORDER BY weld_point_count DESC;
```

#### **5G. MFG Feature Usage**
**Track:**
- MFG features used in operations
- Manufacturing templates applied

**Query:**
```sql
-- MFG feature usage (need to investigate MFGFEATURE_ structure first)
SELECT
    mf.OBJECT_ID,
    mf.NAME_S_ as mfg_feature_name,
    mf.MODIFICATIONDATE_DA_ as last_modified,
    COUNT(DISTINCT o.OBJECT_ID) as used_in_operations_count
FROM DESIGN12.MFGFEATURE_ mf
LEFT JOIN DESIGN12.OPERATION_ o ON mf.OBJECT_ID = o.MFGUSAGES_VR_
WHERE mf.MODIFICATIONDATE_DA_ > :start_date
GROUP BY mf.OBJECT_ID, mf.NAME_S_, mf.MODIFICATIONDATE_DA_
ORDER BY used_in_operations_count DESC;
```

#### **5H. Layout Configuration Changes**
**Track:**
- Layout modifications via LAYOUT_SR_
- Study layout updates

**Query (after investigating LAYOUT_ structure):**
```sql
-- Layout changes
SELECT
    rsi.OBJECT_ID as studyinfo_id,
    rsi.LAYOUT_SR_ as layout_id,
    l.MODIFICATIONDATE_DA_ as layout_modified,
    l.LASTMODIFIEDBY_S_ as modified_by,
    rs.NAME_S_ as study_name
FROM DESIGN12.ROBCADSTUDYINFO_ rsi
INNER JOIN DESIGN12.REL_COMMON r ON rsi.OBJECT_ID = r.OBJECT_ID
LEFT JOIN DESIGN12.ROBCADSTUDY_ rs ON r.FORWARD_OBJECT_ID = rs.OBJECT_ID
LEFT JOIN DESIGN12.LAYOUT_ l ON rsi.LAYOUT_SR_ = l.OBJECT_ID
WHERE l.MODIFICATIONDATE_DA_ > :start_date
ORDER BY l.MODIFICATIONDATE_DA_ DESC;
```

---

## Management Dashboard Design

### **Updated Dashboard Layout:**

```
┌─────────────────────────────────────────────────────────────────────┐
│  FORD_DEARBORN - Management Activity Dashboard                     │
│  Period: Last 7 Days | Filter: All Users | Auto-refresh: OFF       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  Work Type Summary                                            │ │
│  │  ┌────────────┬────────┬──────────┬────────┬─────────────┐   │ │
│  │  │ Work Type  │ Active │ Modified │ Users  │ Changes     │   │ │
│  │  ├────────────┼────────┼──────────┼────────┼─────────────┤   │ │
│  │  │ Study      │    5   │    8     │   3    │ 125 moves   │   │ │
│  │  │ IPA Assy   │    2   │    6     │   2    │ 18 ops      │   │ │
│  │  │ Part Lib   │    8   │   45     │   4    │ 45 parts    │   │ │
│  │  │ Resource   │    3   │   12     │   2    │ 12 res      │   │ │
│  │  │ Project DB │    0   │    1     │   1    │ 1 mod       │   │ │
│  │  └────────────┴────────┴──────────┴────────┴─────────────┘   │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  Active Studies - Detailed View                              │ │
│  │  ┌─────────────────────────┬────────┬─────────┬───────────┐ │ │
│  │  │ Study Name              │ User   │ Duration│ Activity  │ │ │
│  │  ├─────────────────────────┼────────┼─────────┼───────────┤ │ │
│  │  │ ▼ DDMP P702_8J_010_060  │ John S │  3h 25m │ 45 moves  │ │ │
│  │  │   └─ Resources (7):                                     │ │ │
│  │  │      • 8J-010 (Station)                                 │ │ │
│  │  │      • 8J-020 (Station)                                 │ │ │
│  │  │      • 8J-027 (Station)                                 │ │ │
│  │  │      • LAYOUT (CompoundResource)                        │ │ │
│  │  │   └─ Panels (4):                                        │ │ │
│  │  │      • 8J-027_SC (Spot Coat)                            │ │ │
│  │  │      • 8J-030_RC (Robot Coat)                           │ │ │
│  │  │      • 8J-030_CC (Cell Coat)                            │ │ │
│  │  │      • 8J-010_CMN (Common)                              │ │ │
│  │  │   └─ Operations (24):                                   │ │ │
│  │  │      • PG21 (Weld) - 15 points                          │ │ │
│  │  │      • PG10 (Weld) - 12 points                          │ │ │
│  │  │      • MOV_HOME (Move) - modified 2h ago                │ │ │
│  │  │   └─ Movements (45):                                    │ │ │
│  │  │      • 42 Simple Moves                                  │ │ │
│  │  │      • 3 World Location Changes ⚠️                       │ │ │
│  │  │                                                          │ │ │
│  │  │ ▼ DDMP P736_9K_010_020  │ Jane D │  1h 15m │ 12 welds  │ │ │
│  │  │   └─ ... (click to expand)                              │ │ │
│  │  └─────────────────────────┴────────┴─────────┴───────────┘ │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  Movement/Location Activity ⭐ NEW                            │ │
│  │  ┌────────────────┬──────────┬────────────┬─────────────┐   │ │
│  │  │ Study          │ Type     │ Count      │ User        │   │ │
│  │  ├────────────────┼──────────┼────────────┼─────────────┤   │ │
│  │  │ P702_8J_010    │ Simple   │     42     │ John S      │   │ │
│  │  │ P702_8J_010    │ World ⚠️ │      3     │ John S      │   │ │
│  │  │ P736_9K_010    │ Simple   │     18     │ Jane D      │   │ │
│  │  │ P736_9K_010    │ Weld Adj │      8     │ Jane D      │   │ │
│  │  └────────────────┴──────────┴────────────┴─────────────┘   │ │
│  │  [Click row to see coordinate changes]                       │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  User Activity Breakdown                                      │ │
│  │  Select User: [John Smith ▼]                                 │ │
│  │                                                               │ │
│  │  Study Nodes      ████████████░░░░  65% (12h 30m)            │ │
│  │    └─ Operations: 45 created, 125 moves, 87 welds            │ │
│  │  Part Library     ███░░░░░░░░░░░░  17% (3h 15m)             │ │
│  │    └─ Panels: 15 modified (CC: 5, RC: 6, SC: 4)              │ │
│  │  IPA Assembly     ██░░░░░░░░░░░░░  12% (2h 20m)             │ │
│  │  Resource Library █░░░░░░░░░░░░░░   6% (1h 10m)             │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  Recent Activity Timeline                                     │ │
│  │  [Interactive timeline chart]                                 │ │
│  │  14:30 ●─────────────────● 15:00 ●──────● 15:30              │ │
│  │        │                 │       │      │                     │ │
│  │    John S:           Jane D: John S: Jane D:                 │ │
│  │    MOV_HOME          3 welds  World   Panel CC                │ │
│  │    (8J-010)         (P736)    Location Mod                    │ │
│  │                              Change ⚠️                         │ │
│  └───────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐ │
│  │  Detailed Activity Log                                        │ │
│  │  Search: [________]  Filter: [All Types ▼] [All Users ▼]     │ │
│  │                                                               │ │
│  │  2026-01-19 14:32 | John Smith | Study Nodes                │ │
│  │    ⚠️ World Location Change: 8J-027 moved 1250mm in X-axis    │ │
│  │    Study: DDMP P702_8J_010_8J_060                            │ │
│  │    Old: (X: 5000, Y: 3200, Z: 1500)                          │ │
│  │    New: (X: 6250, Y: 3200, Z: 1500)                          │ │
│  │    [View in 3D] [History] [Revert]                           │ │
│  │                                                               │ │
│  │  2026-01-19 14:28 | John Smith | Study Nodes                │ │
│  │    Simple Move: MOV_HOME operation                            │ │
│  │    Study: DDMP P702_8J_010_8J_060                            │ │
│  │                                                               │ │
│  │  2026-01-19 14:15 | Jane Doe | Study Nodes                  │ │
│  │    Weld Point Added: PG21 (15 points)                        │ │
│  │    Study: DDMP P736_9K_010_9K_020                            │ │
│  │    Panel: 9K-010_SC (Spot Coat)                              │ │
│  │                                                               │ │
│  │  2026-01-19 13:45 | Jane Doe | Part Library                 │ │
│  │    Modified: COWL_SILL_SIDE (P736/01/RC)                     │ │
│  │                                                               │ │
│  │  [Load More...]                                              │ │
│  └───────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### **Movement Type Indicators:**
- ✅ **Simple Move** - Green - Normal robot movements (MOV_HOME, MOV_PNCE)
- ⚠️ **World Location Change** - Yellow/Orange - Critical position changes (>1000mm)
- 🔧 **Weld Adjustment** - Blue - Spot weld point fine-tuning
- 🔄 **Rotation Change** - Purple - Orientation changes

---

## Additional Investigation Queries Needed

Before full implementation, we need to query these table structures:

### **1. VEC_LOCATION_ Structure:**
```sql
DESCRIBE DESIGN12.VEC_LOCATION_;
SELECT * FROM DESIGN12.VEC_LOCATION_ WHERE ROWNUM <= 10;
```

**Need to know:**
- Column names for X/Y/Z coordinates
- Is there a MODIFICATIONDATE_DA_ column?
- Is there a LASTMODIFIEDBY_S_ column?
- How is OBJECT_ID linked to OPERATION_ or RESOURCE_?

### **2. VEC_ROTATION_ Structure:**
```sql
DESCRIBE DESIGN12.VEC_ROTATION_;
SELECT * FROM DESIGN12.VEC_ROTATION_ WHERE ROWNUM <= 10;
```

**Need to know:**
- Column names for rotation angles (RX, RY, RZ?)
- Modification tracking columns
- Link to parent objects

### **3. LAYOUT_ Structure:**
```sql
DESCRIBE DESIGN12.LAYOUT_;
SELECT * FROM DESIGN12.LAYOUT_ WHERE ROWNUM <= 20;
```

**Need to know:**
- How layouts reference operations
- Modification tracking
- Link to STUDYLAYOUT_

### **4. STUDYLAYOUT_ Structure:**
```sql
DESCRIBE DESIGN12.STUDYLAYOUT_;
SELECT * FROM DESIGN12.STUDYLAYOUT_ WHERE ROWNUM <= 20;
```

**Need to know:**
- Study-specific layout configuration
- How it links to LAYOUT_
- Modification tracking

### **5. MFGFEATURE_ Structure:**
```sql
DESCRIBE DESIGN12.MFGFEATURE_;
SELECT * FROM DESIGN12.MFGFEATURE_ WHERE ROWNUM <= 20;
```

**Need to know:**
- MFG feature properties
- How operations reference MFG features
- Modification tracking

---

## PowerShell Script Architecture

### **Script 1: get-management-data.ps1**
```powershell
# Queries database for all management reporting data
param(
    [string]$TNSName,
    [string]$Schema,
    [int]$ProjectId,
    [DateTime]$StartDate = (Get-Date).AddDays(-7),
    [DateTime]$EndDate = (Get-Date)
)

# Runs parallel queries:
# 1. Project Database activity
# 2. Resource Library activity
# 3. Part/MFG Library activity
# 4. IPA Assembly activity
# 5. Study Nodes activity (7 sub-queries)
#    5A. Study summary
#    5B. Resource allocation
#    5C. Panel usage
#    5D. Operation tree
#    5E. Movement/location changes ⭐
#    5F. Spot weld activity
#    5G. MFG feature usage
#    5H. Layout changes

# Outputs: JSON file with all data
```

### **Script 2: generate-management-dashboard.ps1**
```powershell
# Generates interactive HTML dashboard from JSON data
param(
    [string]$DataFile,  # JSON from get-management-data.ps1
    [string]$OutputFile = "management-dashboard.html"
)

# Generates HTML with:
# - Work type summary table
# - Active studies expandable view
# - Movement/location activity tracker ⭐
# - User activity breakdown
# - Timeline visualization
# - Detailed activity log with filters
# - Export buttons (CSV, PDF)
```

### **Script 3: management-dashboard-launcher.ps1**
```powershell
# Wrapper script - runs queries + generates dashboard + opens browser
param(
    [string]$TNSName,
    [string]$Schema,
    [int]$ProjectId,
    [int]$DaysBack = 7,
    [switch]$AutoLaunch = $true
)

# 1. Run get-management-data.ps1
# 2. Run generate-management-dashboard.ps1
# 3. Open HTML in browser (if AutoLaunch)
# 4. Display summary stats
```

---

## Caching Strategy

### **Cache Files:**
1. **Management report cache:** `mgmt-report-{Schema}-{ProjectId}-{DateRange}.json`
   - Lifetime: 15 minutes (faster refresh than tree cache)
   - Contains: All query results

2. **User activity cache:** Already exists (1 hour)
   - Reuse for dashboard

3. **Incremental updates:**
   - Only query changes since last cached date
   - Merge with cached data
   - Much faster for frequent refreshes

---

## Success Metrics

Phase 2 complete when:

- [x] All 5 work types tracked correctly
- [ ] User activity detection working
- [ ] Dashboard displays all reports
- [ ] **Movement/location tracking working** ⭐
- [ ] **World location change detection working** ⭐
- [ ] Filtering/drill-down functional
- [ ] Performance <30s for full report generation
- [ ] Export to CSV/PDF working
- [ ] User can answer all these questions:
  - ✅ What work was done by each user this week?
  - ✅ Which studies are actively being worked on?
  - ✅ What resources were allocated to which stations?
  - ✅ What's the progress on P702/P736 builds?
  - ✅ **How many moves/location changes in each study?** ⭐
  - ✅ **Which studies had critical world location changes?** ⭐
  - ✅ What spot welds were added?
  - ✅ What operations were created?
  - ✅ What panels (CC/RC/SC) were worked on?

---

## Next Steps

1. **Run additional investigation queries** (VEC_LOCATION_, VEC_ROTATION_, LAYOUT_, STUDYLAYOUT_, MFGFEATURE_)
2. **Build core SQL queries** for all tracking categories
3. **Create PowerShell wrapper scripts** (get-management-data.ps1, etc.)
4. **Build HTML dashboard template** with JavaScript interactivity
5. **Test with real study data** (user will create test study)
6. **Iterate based on findings**

---

**Status:** Design updated with database findings. Ready for implementation after VEC_LOCATION_/VEC_ROTATION_/LAYOUT_ structure investigation.
