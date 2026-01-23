# Phase 2: Management Reporting - Design Document

## Overview
Create an advanced, intuitive management reporting system that tracks work activity across the 5 core work types in Process Simulate projects.

## Core Reports

### 1. **User Activity by Work Type**
**Purpose:** Show what work each user did, categorized by work type

**Data Points:**
- User name (from `USER_` table via `PROXY.OWNER_ID`)
- Work type (derived from object CLASS_ID and location in tree)
- Object worked on (OBJECT_ID, CAPTION_S_)
- Action type (checkout, modify, create)
- Timestamp (MODIFICATIONDATE_DA_ from relevant table)
- Duration (if still checked out vs. completed)

**Query Strategy:**
```sql
-- Get active checkouts
SELECT
    u.CAPTION_S_ as user_name,
    p.OBJECT_ID,
    c.CAPTION_S_ as object_name,
    cd.NICE_NAME as object_type,
    p.WORKING_VERSION_ID,
    -- Derive work type from CLASS_ID and hierarchy
    CASE
        WHEN cd.TYPE_ID IN (177,178,183,181,108,70) THEN 'Study Nodes'
        WHEN cd.TYPE_ID = 133 THEN 'IPA Assembly'
        WHEN cd.TYPE_ID IN (46,21,55) THEN 'Part Library'
        WHEN cd.TYPE_ID IN (164,23) THEN 'Resource Library'
        ELSE 'Other'
    END as work_type
FROM PROXY p
LEFT JOIN USER_ u ON p.OWNER_ID = u.OBJECT_ID
LEFT JOIN COLLECTION_ c ON p.OBJECT_ID = c.OBJECT_ID
LEFT JOIN CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE p.PROJECT_ID = :project_id
  AND p.WORKING_VERSION_ID > 0
```

**Output Format:**
| User | Work Type | Object | Status | Time |
|------|-----------|--------|--------|------|
| John Smith | Study Nodes | DDMP P702_8J_010 | Checked Out | 2h 15m |
| Jane Doe | Part Library | COWL_SILL_SIDE | Modified | 1h 30m |

---

### 2. **Work Type Activity Summary**
**Purpose:** Overview of activity across all 5 work types

**Breakdown by Work Type:**

1. **Project Database Setup**
   - Projects created/modified
   - Users involved
   - Last modification date

2. **Resource Library**
   - Resources added/modified
   - Resource types (Robot, Equipment, Cable, etc.)
   - Checkout status

3. **Part/MFG Library**
   - Parts created/modified
   - Panel codes worked on (CC, RC, SC)
   - Part hierarchy changes

4. **IPA Assembly**
   - Process assemblies created/modified
   - Station sequences updated
   - Operation types (CMN, SC, RC, CC)

5. **Study Nodes**
   - Studies created/modified
   - Resources allocated (via Shortcuts)
   - Active simulations

**Output Format:**
```
Work Type Activity Summary - FORD_DEARBORN Project
Period: Last 7 days

1. Project Database Setup
   ✓ Last modified: 2026-01-15 by Admin User
   ✓ Status: Active

2. Resource Library (EngineeringResourceLibrary)
   ✓ 12 resources modified
   ✓ 3 resources checked out
   ✓ Active users: John Smith, Jane Doe

3. Part Library
   ✓ 45 parts modified
   ✓ Panel codes: CC (12), RC (18), SC (15)
   ✓ Active work on: COWL_SILL_SIDE, P702, P736

4. IPA Assembly
   ✓ 8 process assemblies modified
   ✓ Station sequences: 8J-010, 8J-020, 8J-030
   ✓ Operations updated: CMN (3), SC (2), RC (2), CC (1)

5. Study Nodes
   ✓ 5 studies active
   ✓ DDMP P702_8J_010_8J_060 - 3 users
   ✓ 18 resource allocations this week
```

---

### 3. **Study-Specific Activity Tracker**
**Purpose:** Detailed tracking for simulation studies (most active work area)

**Data Points:**
- Study name (from `ROBCADSTUDY_.NAME_S_`)
- Study type (RobcadStudy, LineSimulationStudy, GanttStudy, etc.)
- Users working on it (from `PROXY`)
- Resources allocated (via `SHORTCUT_` links)
- Panels/spots assigned (via LAYOUT_SR_ if accessible)
- Child count (StudyFolder, Shortcuts)
- Last modified date
- Checkout duration

**Query Strategy:**
```sql
-- Get study details with user activity
SELECT
    rs.OBJECT_ID,
    rs.NAME_S_ as study_name,
    cd.NICE_NAME as study_type,
    u.CAPTION_S_ as user_working,
    rs.MODIFICATIONDATE_DA_ as last_modified,
    COUNT(DISTINCT s.OBJECT_ID) as resource_count
FROM ROBCADSTUDY_ rs
LEFT JOIN CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN PROXY p ON rs.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN USER_ u ON p.OWNER_ID = u.OBJECT_ID
LEFT JOIN REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
LEFT JOIN SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE rs.OBJECT_ID IN (
    SELECT r2.OBJECT_ID
    FROM REL_COMMON r2
    START WITH r2.FORWARD_OBJECT_ID = :project_id
    CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
)
GROUP BY rs.OBJECT_ID, rs.NAME_S_, cd.NICE_NAME, u.CAPTION_S_, rs.MODIFICATIONDATE_DA_
```

**Output Format:**
```
Study Activity Report - FORD_DEARBORN

Study: DDMP P702_8J_010_8J_060
  Type: RobcadStudy
  Status: Active (checked out)
  User: John Smith
  Last Modified: 2026-01-19 14:32:15
  Resources Allocated: 12
    - 8J-010 (Station)
    - 8J-020 (Station)
    - Robot_IR_6700 (Resource)
    - ...
  Panels/Spots: 45 spots allocated
  Work Duration: 3h 25m
```

---

### 4. **Resource Allocation Report**
**Purpose:** Track which resources are allocated to which studies/stations

**Data Points:**
- Resource name (from `RESOURCE_.NAME_S_`)
- Resource type (Robot, Equipment, Cable, etc.)
- Allocated to (Study via `SHORTCUT_` link)
- Allocation date
- User who allocated it

**Query Strategy:**
```sql
-- Get resource allocations via Shortcut links
SELECT
    r.NAME_S_ as resource_name,
    cd1.NICE_NAME as resource_type,
    rs.NAME_S_ as allocated_to_study,
    s.NAME_S_ as shortcut_name,
    p.MODIFICATIONDATE_DA_ as allocation_date,
    u.CAPTION_S_ as allocated_by
FROM SHORTCUT_ s
INNER JOIN REL_COMMON rc ON s.OBJECT_ID = rc.OBJECT_ID
INNER JOIN ROBCADSTUDY_ rs ON rc.FORWARD_OBJECT_ID = rs.OBJECT_ID
LEFT JOIN RESOURCE_ r ON s.NAME_S_ LIKE r.NAME_S_  -- Shortcut name links to resource
LEFT JOIN CLASS_DEFINITIONS cd1 ON r.CLASS_ID = cd1.TYPE_ID
LEFT JOIN PROXY p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE rs.OBJECT_ID IN (project studies...)
```

**Output Format:**
| Resource | Type | Study | Allocated By | Date |
|----------|------|-------|--------------|------|
| Robot_IR_6700 | Robot | DDMP P702_8J_010 | John Smith | 2026-01-18 |
| Station_8J_010 | Equipment | DDMP P702_8J_010 | John Smith | 2026-01-18 |

---

### 5. **Progress Tracking on P702/P736 Builds**
**Purpose:** Track progress on specific build assemblies

**Data Points:**
- Build code (P702, P736)
- Level codes worked on (01, 02, 03, etc.)
- Panel codes (CC, RC, SC)
- Parts modified/created
- Completion percentage (modified vs. total)
- Users working on it

**Query Strategy:**
```sql
-- Get P702/P736 hierarchy with modification tracking
SELECT
    p1.NAME_S_ as build_code,
    p2.NAME_S_ as level_code,
    p3.NAME_S_ as panel_code,
    COUNT(DISTINCT p4.OBJECT_ID) as total_parts,
    COUNT(DISTINCT CASE WHEN p4.MODIFICATIONDATE_DA_ > :start_date THEN p4.OBJECT_ID END) as modified_parts,
    ROUND(COUNT(DISTINCT CASE WHEN p4.MODIFICATIONDATE_DA_ > :start_date THEN p4.OBJECT_ID END) * 100.0 / COUNT(DISTINCT p4.OBJECT_ID), 1) as completion_pct
FROM PART_ p1
LEFT JOIN REL_COMMON r1 ON p1.OBJECT_ID = r1.FORWARD_OBJECT_ID
LEFT JOIN PART_ p2 ON r1.OBJECT_ID = p2.OBJECT_ID
LEFT JOIN REL_COMMON r2 ON p2.OBJECT_ID = r2.FORWARD_OBJECT_ID
LEFT JOIN PART_ p3 ON r2.OBJECT_ID = p3.OBJECT_ID
LEFT JOIN REL_COMMON r3 ON p3.OBJECT_ID = r3.FORWARD_OBJECT_ID
LEFT JOIN PART_ p4 ON r3.OBJECT_ID = p4.OBJECT_ID
WHERE p1.NAME_S_ IN ('P702', 'P736')
  AND p1.CLASS_ID = 21  -- CompoundPart
GROUP BY p1.NAME_S_, p2.NAME_S_, p3.NAME_S_
ORDER BY p1.NAME_S_, p2.NAME_S_, p3.NAME_S_
```

**Output Format:**
```
P702/P736 Build Progress - Last 7 Days

P702
  ├─ 01
  │   ├─ CC: 12/45 parts modified (26.7%)
  │   ├─ RC: 18/52 parts modified (34.6%)
  │   └─ SC: 15/38 parts modified (39.5%)
  ├─ 02
  │   ├─ CC: 5/32 parts modified (15.6%)
  │   └─ ...

P736
  ├─ 01
  │   └─ ...
```

---

### 6. **Time Spent on Different Work Types**
**Purpose:** Estimate time spent on each work type

**Calculation Strategy:**
- Use `PROXY` checkout timestamps + current time (if still checked out)
- Use `PROXY_VERSIONS` for completed work duration
- Aggregate by user and work type

**Data Points:**
- User name
- Work type
- Total time (hours)
- Number of objects worked on
- Average time per object

**Output Format:**
| User | Work Type | Total Time | Objects | Avg Time/Object |
|------|-----------|------------|---------|-----------------|
| John Smith | Study Nodes | 12h 30m | 5 | 2h 30m |
| John Smith | Part Library | 3h 15m | 15 | 13m |
| Jane Doe | Resource Library | 8h 45m | 12 | 44m |

---

## Interactive Dashboard Design

### **HTML Dashboard Layout:**

```
┌─────────────────────────────────────────────────────────┐
│  FORD_DEARBORN - Management Activity Dashboard         │
│  Period: Last 7 Days | Filter: All Users               │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Work Type Summary                              │   │
│  │  ┌─────────────┬──────────┬──────────┬────────┐ │   │
│  │  │ Work Type   │ Active   │ Modified │ Users  │ │   │
│  │  ├─────────────┼──────────┼──────────┼────────┤ │   │
│  │  │ Study Nodes │    5     │    8     │   3    │ │   │
│  │  │ IPA Assy    │    2     │    6     │   2    │ │   │
│  │  │ Part Lib    │    8     │   45     │   4    │ │   │
│  │  │ Resource Lib│    3     │   12     │   2    │ │   │
│  │  │ Project DB  │    0     │    1     │   1    │ │   │
│  │  └─────────────┴──────────┴──────────┴────────┘ │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Active Studies                                  │   │
│  │  ┌─────────────────────────┬────────┬─────────┐ │   │
│  │  │ Study Name              │ User   │ Duration│ │   │
│  │  ├─────────────────────────┼────────┼─────────┤ │   │
│  │  │ DDMP P702_8J_010_8J_060 │ John S │  3h 25m │ │   │
│  │  │ DDMP P736_9K_010_9K_020 │ Jane D │  1h 15m │ │   │
│  │  └─────────────────────────┴────────┴─────────┘ │   │
│  │  [Click to expand details]                       │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  User Activity Breakdown                         │   │
│  │  Select User: [John Smith ▼]                     │   │
│  │                                                   │   │
│  │  Study Nodes      ████████████░░░░  65% (12h 30m)│   │
│  │  Part Library     ███░░░░░░░░░░░░  17% (3h 15m) │   │
│  │  IPA Assembly     ██░░░░░░░░░░░░░  12% (2h 20m) │   │
│  │  Resource Library █░░░░░░░░░░░░░░   6% (1h 10m) │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Recent Activity Timeline                        │   │
│  │  [Interactive timeline showing checkouts/mods]   │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  Detailed Activity Log                           │   │
│  │  Search: [________]  Filter: [All Types ▼]      │   │
│  │                                                   │   │
│  │  2026-01-19 14:32 | John Smith | Study Nodes    │   │
│  │    Modified: DDMP P702_8J_010_8J_060            │   │
│  │                                                   │   │
│  │  2026-01-19 13:15 | Jane Doe | Part Library     │   │
│  │    Modified: COWL_SILL_SIDE                     │   │
│  │                                                   │   │
│  │  [Load More...]                                  │   │
│  └─────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### **Features:**
1. **Filtering:**
   - By date range (Last 7 days, Last 30 days, Custom)
   - By user (All, individual users)
   - By work type (All, specific type)
   - By status (Active checkouts, Completed work, All)

2. **Drill-Down:**
   - Click work type → See all objects in that category
   - Click study → See resource allocations, user activity
   - Click user → See all work done by that user

3. **Export:**
   - Export to CSV
   - Export to PDF report
   - Copy data to clipboard

4. **Real-Time Updates:**
   - Refresh button to query latest data
   - Show last refresh timestamp
   - Auto-refresh option (every 5 min)

5. **Visual Indicators:**
   - Color coding (green=active, yellow=modified recently, gray=idle)
   - Progress bars for completion percentages
   - Icons for work types
   - Status badges (Checked Out, Modified, New)

---

## Implementation Plan

### **Phase 2A: Core Queries**
1. ✓ Design query for user activity by work type
2. ✓ Design query for work type summary
3. ✓ Design query for study-specific tracking
4. ✓ Design query for resource allocation
5. ✓ Design query for P702/P736 progress

### **Phase 2B: PowerShell Scripts**
1. Create `get-management-report.ps1`
   - Takes: TNSName, Schema, ProjectId, DateRange
   - Outputs: JSON data for all 5 reports
2. Create `generate-dashboard.ps1`
   - Takes: JSON data
   - Generates: HTML dashboard
3. Create `management-dashboard-launcher.ps1`
   - Wrapper script to run queries + generate dashboard

### **Phase 2C: HTML Dashboard**
1. Create interactive HTML template
2. Add JavaScript for filtering/sorting
3. Add drill-down functionality
4. Add export capabilities
5. Style with CSS (match tree viewer theme)

### **Phase 2D: Testing**
1. Test with user's test study data
2. Verify all 5 work types tracked correctly
3. Validate user activity detection
4. Check performance with large datasets
5. User acceptance testing

---

## Database Performance Considerations

### **Optimization Strategies:**
1. **Indexes:** Ensure indexes on:
   - `PROXY.PROJECT_ID, WORKING_VERSION_ID, OWNER_ID`
   - `COLLECTION_.CLASS_ID, MODIFICATIONDATE_DA_`
   - `REL_COMMON.FORWARD_OBJECT_ID, OBJECT_ID`
   - `ROBCADSTUDY_.OBJECT_ID`
   - `PART_.CLASS_ID`

2. **Query Caching:**
   - Cache management report data (15-minute refresh)
   - Faster than tree cache due to smaller dataset
   - Cache key: `mgmt-report-{Schema}-{ProjectId}-{DateRange}.json`

3. **Incremental Updates:**
   - Only query changes since last refresh
   - Use `MODIFICATIONDATE_DA_ > :last_refresh_time`
   - Merge with cached data

4. **Parallel Queries:**
   - Run all 5 work type queries in parallel
   - Combine results in PowerShell
   - Total query time ~10-15s (vs. 60s if sequential)

---

## Success Metrics

### **Phase 2 Complete When:**
- [x] All 5 work types tracked correctly
- [ ] User activity detection working
- [ ] Dashboard displays all reports
- [ ] Filtering/drill-down functional
- [ ] Performance <30s for full report generation
- [ ] User can answer: "What work was done by each user this week?"
- [ ] User can answer: "Which studies are actively being worked on?"
- [ ] User can answer: "What resources were allocated to which stations?"
- [ ] User can answer: "What's the progress on P702/P736 builds?"

---

## Next Steps

1. **User creates test study** - So we have real data to query
2. **Build core queries** - Implement the 5 SQL queries
3. **Create PowerShell scripts** - Wrap queries in scripts
4. **Build HTML dashboard** - Interactive reporting interface
5. **Test and iterate** - Verify with real test data
6. **Production deployment** - Roll out to team

---

## Questions for User

Before implementation:
1. **Date ranges:** Default to last 7 days? Other preferences?
2. **Users:** Should we filter to specific users or show all?
3. **Export format:** CSV sufficient or need Excel/PDF?
4. **Refresh rate:** Manual refresh or auto-refresh every N minutes?
5. **Permissions:** Should all users see all activity or filter by user?

---

**Status:** Design Complete - Ready for Implementation
**Next Action:** Wait for user to create test study, then build queries
