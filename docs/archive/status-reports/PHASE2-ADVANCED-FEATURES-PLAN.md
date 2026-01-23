# Phase 2 - Advanced Features Implementation Plan

**Date:** 2026-01-19
**Project:** SimTreeNav Management Reporting
**Status:** Planning

## Overview

Building on the foundational management reporting system, this document outlines the implementation plan for advanced analytics and intelligence features that will provide actionable insights and improve team collaboration.

---

## Selected Features for Implementation

### Feature 4: Time-Travel Debugging for Manufacturing Changes
**Priority:** High
**Complexity:** Medium
**Value:** Root cause analysis, impact assessment

### Feature 5: Collaborative Heat Maps
**Priority:** High
**Complexity:** Low-Medium
**Value:** Visual coordination, avoid duplication

### Feature 6: Study Health Score Dashboard
**Priority:** High
**Complexity:** Medium
**Value:** Proactive quality assurance

### Feature 12: Smart Notifications Engine
**Priority:** Medium
**Complexity:** Medium-High
**Value:** Context-aware communication

### Feature 13: Technical Debt Tracking
**Priority:** Medium
**Complexity:** Low-Medium
**Value:** Proactive maintenance

### Feature 14: Natural Language Query Interface
**Priority:** Low (Future)
**Complexity:** High
**Value:** Democratize data access

---

## Feature 4: Time-Travel Debugging

### Concept
Interactive timeline visualization showing cascading changes across all 5 work types, enabling root cause analysis and impact assessment.

### User Stories
1. As a **team lead**, I want to see what changed when a quality issue was discovered, so I can identify the root cause
2. As a **simulation engineer**, I want to understand the ripple effects of a panel change, so I can anticipate downstream impacts
3. As a **project manager**, I want to review team activity over time, so I can understand workflow patterns

### Data Requirements
- All 11 existing queries provide timestamp data (MODIFICATIONDATE_DA_)
- Need to add relationship mapping between work types
- Store LASTMODIFIEDBY_S_ for attribution

### Technical Implementation

#### Phase 1: Data Model (Week 1)
```sql
-- New query to map relationships
SELECT
    'CHANGE_RELATIONSHIP' as type,
    child_type,
    child_id,
    parent_type,
    parent_id,
    relationship_type,
    modification_timestamp
FROM (
    -- Panel -> Study relationships
    SELECT
        'STUDY' as child_type,
        rs.OBJECT_ID as child_id,
        'PANEL' as parent_type,
        p.OBJECT_ID as parent_id,
        'Uses Panel' as relationship_type,
        GREATEST(rs.MODIFICATIONDATE_DA_, p.MODIFICATIONDATE_DA_) as modification_timestamp
    FROM ROBCADSTUDY_ rs
    JOIN SHORTCUT_ s ON rs.OBJECT_ID = parent_object
    JOIN PART_ p ON s.NAME_S_ LIKE p.NAME_S_ || '%'

    UNION ALL

    -- Resource -> Study relationships
    SELECT
        'STUDY' as child_type,
        rs.OBJECT_ID as child_id,
        'RESOURCE' as parent_type,
        r.OBJECT_ID as parent_id,
        'Allocated Resource' as relationship_type,
        GREATEST(rs.MODIFICATIONDATE_DA_, r.MODIFICATIONDATE_DA_) as modification_timestamp
    FROM ROBCADSTUDY_ rs
    JOIN SHORTCUT_ s ON rs.OBJECT_ID = parent_object
    JOIN RESOURCE_ r ON s.NAME_S_ = r.NAME_S_

    UNION ALL

    -- Operation -> Study relationships
    SELECT
        'OPERATION' as child_type,
        o.OBJECT_ID as child_id,
        'STUDY' as parent_type,
        rs.OBJECT_ID as parent_id,
        'Contains Operation' as relationship_type,
        o.MODIFICATIONDATE_DA_ as modification_timestamp
    FROM OPERATION_ o
    JOIN REL_COMMON r ON o.OBJECT_ID = r.OBJECT_ID
    JOIN ROBCADSTUDY_ rs ON r.FORWARD_OBJECT_ID = rs.OBJECT_ID
)
WHERE modification_timestamp > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
ORDER BY modification_timestamp DESC;
```

#### Phase 2: Timeline Visualization (Week 2)
- HTML5 Canvas or SVG-based timeline
- D3.js for interactive timeline rendering
- Color-coded by work type:
  - Blue: Project Database
  - Green: Resource Library
  - Orange: Part/MFG Library
  - Purple: IPA Assembly
  - Red: Study Nodes

#### Phase 3: Impact Analysis (Week 3)
- Click event to expand cascading changes
- Show dependency tree
- Highlight users involved
- Display time deltas between related changes

### Mockup Structure
```
Timeline View:
├─ [Jan 15 10:00] LipoleloM modified RC panel 702
│   └─> [Jan 15 10:15] Auto-triggered: 3 studies updated
│       ├─> [Jan 15 10:20] David: DDMP P702_8J_010L - 12 weld ops changed
│       ├─> [Jan 15 10:22] Terri: DDMP P702_8J_010R - 12 weld ops changed
│       └─> [Jan 15 10:45] DylanL: Study validation completed
```

### Success Metrics
- Reduce root cause analysis time by 50%
- Track average cascade depth (# of downstream changes)
- Measure time to identify quality issue origins

---

## Feature 5: Collaborative Heat Maps

### Concept
Visual 3D factory floor showing real-time work activity intensity, enabling team coordination and avoiding duplicate work.

### User Stories
1. As a **simulation engineer**, I want to see who's working on which stations, so I don't start duplicate work
2. As a **team lead**, I want to identify bottleneck stations, so I can reallocate resources
3. As a **new team member**, I want to see where experienced users are working, so I can ask for help on nearby stations

### Data Requirements
- Study activity data (already collected)
- Resource allocation by station (already collected via studyResources)
- Panel usage by station (already collected via studyPanels)
- User activity (already collected)

### Technical Implementation

#### Phase 1: Station Activity Aggregation (Week 1)
```sql
-- New query: Station-level activity heatmap
SELECT
    station_code,
    COUNT(DISTINCT study_id) as active_studies,
    COUNT(DISTINCT user_name) as active_users,
    STRING_AGG(DISTINCT user_name, ', ') as user_list,
    MAX(last_modified) as most_recent_activity,
    CASE
        WHEN COUNT(DISTINCT user_name) >= 3 THEN 'HOT'
        WHEN COUNT(DISTINCT user_name) = 2 THEN 'WARM'
        WHEN COUNT(DISTINCT user_name) = 1 THEN 'ACTIVE'
        ELSE 'IDLE'
    END as heat_level
FROM (
    -- Extract station from study resources
    SELECT
        rs.OBJECT_ID as study_id,
        rs.NAME_S_ as study_name,
        REGEXP_SUBSTR(s.NAME_S_, '^[^_]+') as station_code,
        rs.LASTMODIFIEDBY_S_ as user_name,
        rs.MODIFICATIONDATE_DA_ as last_modified
    FROM ##SCHEMA##.ROBCADSTUDY_ rs
    JOIN ##SCHEMA##.REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
    JOIN ##SCHEMA##.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
    WHERE rs.MODIFICATIONDATE_DA_ > SYSDATE - 1  -- Last 24 hours
)
GROUP BY station_code
ORDER BY active_users DESC, most_recent_activity DESC;
```

#### Phase 2: Visualization (Week 2)
- 2D factory floor layout (SVG-based)
- Color intensity based on heat_level:
  - RED (HOT): 3+ users active
  - YELLOW (WARM): 2 users active
  - GREEN (ACTIVE): 1 user active
  - BLUE (IDLE): Recently completed
  - GRAY: No recent activity

#### Phase 3: Interactive Features (Week 3)
- Hover: Show user names and study counts
- Click: Drill down to specific studies and users
- Auto-refresh every 5 minutes
- Desktop notification when someone starts work on "your" station

### Mockup Structure
```
Heat Map View:
┌─────────────────────────────────────┐
│  Factory Floor - 8J Line            │
├─────────────────────────────────────┤
│                                     │
│  🔴 8J-010 (HOT)                   │
│     Terri, David, DylanL            │
│     4 active studies                │
│                                     │
│  🟡 8J-020 (WARM)                  │
│     Terri, LipoleloM                │
│     2 active studies                │
│                                     │
│  🟢 8J-027 (ACTIVE)                │
│     Georgem                         │
│     1 active study                  │
│                                     │
│  🔵 8J-030 (IDLE)                  │
│     Last: David (2h ago)            │
│                                     │
└─────────────────────────────────────┘
```

### Success Metrics
- Reduce duplicate work incidents by 80%
- Measure collaboration score (users helping on same stations)
- Track station utilization patterns

---

## Feature 6: Study Health Score Dashboard

### Concept
Automated quality metrics for each study, scoring based on completeness, consistency, and best practices. Proactive quality assurance.

### User Stories
1. As a **quality engineer**, I want to identify problematic studies before review, so I can prioritize inspection
2. As a **simulation engineer**, I want to see my study health score, so I can fix issues early
3. As a **team lead**, I want to track team-wide quality trends, so I can identify training needs

### Health Score Components

#### 1. Completeness Score (30 points)
- Resource allocation complete ✓ (10 pts)
- Panel codes assigned ✓ (10 pts)
- Operation tree populated ✓ (5 pts)
- Movement locations set ✓ (5 pts)

#### 2. Consistency Score (25 points)
- Weld count matches panel design ✓ (10 pts)
- Resource types match study type ✓ (10 pts)
- Station naming follows convention ✓ (5 pts)

#### 3. Activity Score (20 points)
- Modified in last 7 days ✓ (10 pts)
- Active (not idle) status ✓ (10 pts)

#### 4. Quality Score (25 points)
- No orphaned operations ✓ (10 pts)
- No duplicate weld points ✓ (10 pts)
- Valid location coordinates ✓ (5 pts)

### Technical Implementation

#### Phase 1: Health Check Queries (Week 1)
```sql
-- New query: Study Health Score
WITH study_metrics AS (
    SELECT
        rs.OBJECT_ID as study_id,
        rs.NAME_S_ as study_name,
        rs.MODIFICATIONDATE_DA_ as last_modified,
        CASE WHEN p.WORKING_VERSION_ID > 0 THEN 1 ELSE 0 END as is_active,

        -- Completeness metrics
        (SELECT COUNT(*) FROM SHORTCUT_ s
         JOIN REL_COMMON r ON s.OBJECT_ID = r.OBJECT_ID
         WHERE r.FORWARD_OBJECT_ID = rs.OBJECT_ID
         AND s.NAME_S_ LIKE '8J-%') as resource_count,

        (SELECT COUNT(*) FROM SHORTCUT_ s
         JOIN REL_COMMON r ON s.OBJECT_ID = r.OBJECT_ID
         WHERE r.FORWARD_OBJECT_ID = rs.OBJECT_ID
         AND s.NAME_S_ LIKE '%\_%' ESCAPE '\') as panel_count,

        (SELECT COUNT(*) FROM OPERATION_ o
         JOIN REL_COMMON r ON o.OBJECT_ID = r.OBJECT_ID
         WHERE r.FORWARD_OBJECT_ID = rs.OBJECT_ID) as operation_count,

        (SELECT COUNT(*) FROM STUDYLAYOUT_ sl
         WHERE sl.STUDYINFO_SR_ IN (
            SELECT rsi.OBJECT_ID FROM ROBCADSTUDYINFO_ rsi
            WHERE rsi.STUDY_SR_ = rs.OBJECT_ID)
         AND sl.LOCATION_V_ IS NOT NULL) as location_count,

        -- Consistency metrics
        (SELECT COUNT(*) FROM OPERATION_ o
         JOIN REL_COMMON r ON o.OBJECT_ID = r.OBJECT_ID
         WHERE r.FORWARD_OBJECT_ID = rs.OBJECT_ID
         AND o.CLASS_ID = 141) as weld_operation_count,

        -- Quality metrics (orphans, duplicates)
        (SELECT COUNT(*) FROM OPERATION_ o
         WHERE o.CLASS_ID = 141
         AND NOT EXISTS (
            SELECT 1 FROM REL_COMMON r
            WHERE r.OBJECT_ID = o.OBJECT_ID)) as orphaned_operations

    FROM ##SCHEMA##.ROBCADSTUDY_ rs
    LEFT JOIN ##SCHEMA##.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
    WHERE rs.MODIFICATIONDATE_DA_ > TO_DATE('##STARTDATE##', 'YYYY-MM-DD')
)
SELECT
    study_id,
    study_name,

    -- Calculate scores
    CASE
        WHEN resource_count > 0 THEN 10 ELSE 0
    END as resource_score,

    CASE
        WHEN panel_count > 0 THEN 10 ELSE 0
    END as panel_score,

    CASE
        WHEN operation_count > 0 THEN 5 ELSE 0
    END as operation_score,

    CASE
        WHEN location_count > 0 THEN 5 ELSE 0
    END as location_score,

    CASE
        WHEN weld_operation_count > 0 THEN 10 ELSE 0
    END as weld_consistency_score,

    CASE
        WHEN last_modified > SYSDATE - 7 THEN 10 ELSE 0
    END as recent_activity_score,

    CASE
        WHEN is_active = 1 THEN 10 ELSE 0
    END as active_status_score,

    CASE
        WHEN orphaned_operations = 0 THEN 10 ELSE 0
    END as no_orphans_score,

    -- Total health score (out of 100)
    (
        CASE WHEN resource_count > 0 THEN 10 ELSE 0 END +
        CASE WHEN panel_count > 0 THEN 10 ELSE 0 END +
        CASE WHEN operation_count > 0 THEN 5 ELSE 0 END +
        CASE WHEN location_count > 0 THEN 5 ELSE 0 END +
        CASE WHEN weld_operation_count > 0 THEN 10 ELSE 0 END +
        CASE WHEN last_modified > SYSDATE - 7 THEN 10 ELSE 0 END +
        CASE WHEN is_active = 1 THEN 10 ELSE 0 END +
        CASE WHEN orphaned_operations = 0 THEN 10 ELSE 0 END
    ) as health_score,

    -- Health grade
    CASE
        WHEN health_score >= 90 THEN 'A - Excellent'
        WHEN health_score >= 80 THEN 'B - Good'
        WHEN health_score >= 70 THEN 'C - Fair'
        WHEN health_score >= 60 THEN 'D - Needs Work'
        ELSE 'F - Critical Issues'
    END as health_grade,

    -- Specific recommendations
    CASE
        WHEN resource_count = 0 THEN 'Add resources; '
        ELSE ''
    END ||
    CASE
        WHEN panel_count = 0 THEN 'Assign panel codes; '
        ELSE ''
    END ||
    CASE
        WHEN orphaned_operations > 0 THEN 'Fix ' || orphaned_operations || ' orphaned operations; '
        ELSE ''
    END as recommendations

FROM study_metrics
ORDER BY health_score ASC;  -- Show worst studies first
```

#### Phase 2: Dashboard Visualization (Week 2)
- Score breakdown by category
- Trend over time (improving/declining)
- Team averages vs individual studies
- Sortable/filterable table

#### Phase 3: Automated Alerts (Week 3)
- Email digest: Studies below 70 health score
- Warning icons in main dashboard
- Daily health score summary for team leads

### Mockup Structure
```
Study Health Dashboard:
┌────────────────────────────────────────────────┐
│  Overall Health: 78/100 (B - Good)             │
├────────────────────────────────────────────────┤
│                                                │
│  Top Issues:                                   │
│  ⚠️  3 studies below 70 health score          │
│  ⚠️  5 studies with orphaned operations       │
│  ✅ All active studies have resources          │
│                                                │
│  Study Breakdown:                              │
│  ┌──────────────────────┬──────┬──────┐       │
│  │ Study                │Score │Grade │       │
│  ├──────────────────────┼──────┼──────┤       │
│  │ DTP P736_9C_005...   │ 95   │  A   │ ✅   │
│  │ DDMP P702_8J_010L    │ 85   │  B   │ ✅   │
│  │ DDMP P702_8J_010R    │ 85   │  B   │ ✅   │
│  │ DSP P736_3C_010      │ 65   │  D   │ ⚠️   │
│  │   → Missing panels                         │
│  │   → No recent activity                     │
│  └──────────────────────┴──────┴──────┘       │
└────────────────────────────────────────────────┘
```

### Success Metrics
- Reduce quality issues found in review by 40%
- Track average health score over time
- Measure time to fix issues after detection

---

## Feature 12: Smart Notifications Engine

### Concept
Context-aware notifications that alert users to relevant changes without overwhelming them. Intelligent filtering based on user activity patterns.

### User Stories
1. As a **simulation engineer**, I want to be notified when someone modifies a study I worked on, so I can review changes
2. As a **team member**, I want to know when resources I frequently use are updated, so I can adapt my work
3. As a **project manager**, I want daily summaries of team activity, so I can stay informed without constant interruptions

### Notification Types

#### 1. Your Work Modified (High Priority)
- Someone edited a study you worked on in last 30 days
- Threshold: Modified by different user
- Frequency: Immediate

#### 2. Dependency Updated (Medium Priority)
- Panel/resource you use was updated
- Threshold: Used in 3+ of your recent studies
- Frequency: Daily digest

#### 3. Team Activity (Low Priority)
- New resources added to library
- Major project milestones
- Frequency: Weekly summary

### Technical Implementation

#### Phase 1: Notification Rules Engine (Week 1)
```sql
-- New query: Personalized notifications
WITH user_recent_work AS (
    -- Track what studies user worked on recently
    SELECT DISTINCT
        LASTMODIFIEDBY_S_ as user_name,
        OBJECT_ID as study_id,
        NAME_S_ as study_name,
        MODIFICATIONDATE_DA_ as their_work_date
    FROM ##SCHEMA##.ROBCADSTUDY_
    WHERE MODIFICATIONDATE_DA_ > SYSDATE - 30
),
subsequent_changes AS (
    -- Find studies that were modified AFTER user's work
    SELECT
        uww.user_name as notify_user,
        rs.OBJECT_ID as study_id,
        rs.NAME_S_ as study_name,
        rs.LASTMODIFIEDBY_S_ as changed_by,
        rs.MODIFICATIONDATE_DA_ as change_date,
        uww.their_work_date as user_last_worked
    FROM ##SCHEMA##.ROBCADSTUDY_ rs
    JOIN user_recent_work uww ON rs.OBJECT_ID = uww.study_id
    WHERE rs.MODIFICATIONDATE_DA_ > uww.their_work_date
    AND rs.LASTMODIFIEDBY_S_ != uww.user_name  -- Different user
    AND rs.MODIFICATIONDATE_DA_ > SYSDATE - 1  -- Last 24 hours
)
SELECT
    notify_user,
    'YOUR_WORK_MODIFIED' as notification_type,
    'High' as priority,
    study_name || ' was modified by ' || changed_by as message,
    change_date as notification_timestamp,
    ROUND((change_date - user_last_worked) * 24, 1) || ' hours after you worked on it' as context
FROM subsequent_changes
ORDER BY notification_timestamp DESC;
```

#### Phase 2: Delivery System (Week 2)
- Email digest (configurable: immediate/daily/weekly)
- In-dashboard notification bell icon
- Optional: MS Teams/Slack webhook integration
- Desktop toast notifications (optional)

#### Phase 3: User Preferences (Week 3)
- Notification settings page
- Mute specific studies/users
- Frequency controls
- Keyword filters

### Mockup Structure
```
Notification Bell (3):
┌────────────────────────────────────────────┐
│  🔔 You have 3 new notifications           │
├────────────────────────────────────────────┤
│                                            │
│  ⚠️  HIGH PRIORITY                         │
│  DTP P736_9C_005_9C_025 was modified       │
│  by DylanL                                 │
│  → 2 hours after you worked on it          │
│  [View Changes] [Dismiss]                  │
│                                            │
│  ℹ️  MEDIUM PRIORITY                       │
│  Panel SC_702 updated (you use this often) │
│  by LipoleloM                              │
│  [Review] [Dismiss]                        │
│                                            │
│  ℹ️  LOW PRIORITY                          │
│  5 new resources added to library          │
│  [Browse] [Dismiss]                        │
│                                            │
└────────────────────────────────────────────┘
```

### Success Metrics
- Notification relevance score (user clicks vs dismisses)
- Reduce missed important changes by 70%
- Track notification fatigue (opt-out rate)

---

## Feature 13: Technical Debt Tracking

### Concept
Proactive identification of accumulating database problems before they become critical. Automated health checks for data integrity.

### User Stories
1. As a **database administrator**, I want to identify orphaned records, so I can clean up the database
2. As a **team lead**, I want to see studies with no recent activity, so I can archive or reassign them
3. As a **quality engineer**, I want to find incomplete hierarchies, so I can fix data integrity issues

### Technical Debt Categories

#### 1. Orphaned Records
- **Operations without parent study**
- **Welds not linked to operations**
- **Resources not used in any study**
- **Panels with no associated operations**

#### 2. Stale Data
- **Studies marked "Active" but no modifications in 30+ days**
- **Checked-out resources never modified**
- **Idle studies that should be archived**

#### 3. Data Integrity Issues
- **Missing mandatory relationships**
- **Invalid foreign keys**
- **Duplicate weld points (same coordinates)**
- **Location vectors with NULL coordinates**

#### 4. Naming Convention Violations
- **Studies not following naming pattern**
- **Panel codes missing station prefix**
- **Operations missing category prefix**

### Technical Implementation

#### Phase 1: Debt Detection Queries (Week 1)
```sql
-- Query 1: Orphaned Operations
SELECT
    'ORPHANED_OPERATIONS' as debt_type,
    'High' as severity,
    o.OBJECT_ID as object_id,
    o.NAME_S_ as object_name,
    o.MODIFICATIONDATE_DA_ as last_modified,
    o.LASTMODIFIEDBY_S_ as last_modified_by,
    'Operation not linked to any study' as issue_description,
    'Delete or re-link to parent study' as recommended_action
FROM ##SCHEMA##.OPERATION_ o
WHERE NOT EXISTS (
    SELECT 1 FROM ##SCHEMA##.REL_COMMON r
    WHERE r.OBJECT_ID = o.OBJECT_ID
)
AND o.MODIFICATIONDATE_DA_ < SYSDATE - 7;  -- Give 7 days grace period

-- Query 2: Stale Active Studies
SELECT
    'STALE_ACTIVE_STUDY' as debt_type,
    'Medium' as severity,
    rs.OBJECT_ID as object_id,
    rs.NAME_S_ as object_name,
    rs.MODIFICATIONDATE_DA_ as last_modified,
    rs.LASTMODIFIEDBY_S_ as last_modified_by,
    'Study marked Active but no changes in ' ||
        ROUND(SYSDATE - rs.MODIFICATIONDATE_DA_) || ' days' as issue_description,
    'Check in or mark as Idle' as recommended_action
FROM ##SCHEMA##.ROBCADSTUDY_ rs
JOIN ##SCHEMA##.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
WHERE p.WORKING_VERSION_ID > 0  -- Active
AND rs.MODIFICATIONDATE_DA_ < SYSDATE - 30;

-- Query 3: Unused Resources
SELECT
    'UNUSED_RESOURCE' as debt_type,
    'Low' as severity,
    r.OBJECT_ID as object_id,
    r.NAME_S_ as object_name,
    r.MODIFICATIONDATE_DA_ as last_modified,
    r.CREATEDBY_S_ as created_by,
    'Resource created but never used in any study' as issue_description,
    'Review if still needed, consider archiving' as recommended_action
FROM ##SCHEMA##.RESOURCE_ r
WHERE NOT EXISTS (
    SELECT 1 FROM ##SCHEMA##.SHORTCUT_ s
    WHERE s.NAME_S_ = r.NAME_S_
)
AND r.CREATIONDATE_DA_ < SYSDATE - 90;  -- Created 90+ days ago

-- Query 4: Invalid Location Vectors
SELECT
    'INVALID_LOCATION' as debt_type,
    'High' as severity,
    sl.OBJECT_ID as object_id,
    rsi.NAME_S_ as study_name,
    sl.MODIFICATIONDATE_DA_ as last_modified,
    sl.LASTMODIFIEDBY_S_ as last_modified_by,
    'Location vector has NULL coordinates' as issue_description,
    'Set valid X/Y/Z coordinates' as recommended_action
FROM ##SCHEMA##.STUDYLAYOUT_ sl
JOIN ##SCHEMA##.ROBCADSTUDYINFO_ rsi ON sl.STUDYINFO_SR_ = rsi.OBJECT_ID
LEFT JOIN ##SCHEMA##.VEC_LOCATION_ vl ON sl.LOCATION_V_ = vl.OBJECT_ID
WHERE sl.LOCATION_V_ IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM ##SCHEMA##.VEC_LOCATION_ vl2
    WHERE vl2.OBJECT_ID = sl.LOCATION_V_
    AND vl2.DATA IS NOT NULL
);

-- Query 5: Naming Convention Violations
SELECT
    'NAMING_VIOLATION' as debt_type,
    'Low' as severity,
    rs.OBJECT_ID as object_id,
    rs.NAME_S_ as object_name,
    rs.MODIFICATIONDATE_DA_ as last_modified,
    rs.CREATEDBY_S_ as created_by,
    'Study name does not follow convention (Project_Station_Range)' as issue_description,
    'Rename to match convention: PROJECT_STATION_RANGE' as recommended_action
FROM ##SCHEMA##.ROBCADSTUDY_ rs
WHERE NOT REGEXP_LIKE(rs.NAME_S_, '^[A-Z]+ P[0-9]+_[0-9][A-Z]_[0-9]+')
AND rs.CREATIONDATE_DA_ > SYSDATE - 180;  -- Recent studies only
```

#### Phase 2: Debt Dashboard (Week 2)
- Summary counts by severity
- Trend over time (increasing/decreasing debt)
- Auto-prioritized list (severity + age)
- Bulk actions (delete, archive, reassign)

#### Phase 3: Automated Cleanup (Week 3)
- Scheduled daily scans
- Auto-archive studies idle > 90 days
- Email weekly summary to team leads
- Safe cleanup mode (archive, don't delete)

### Mockup Structure
```
Technical Debt Dashboard:
┌────────────────────────────────────────────────┐
│  Debt Score: 23 issues (⬇ Improving)          │
├────────────────────────────────────────────────┤
│                                                │
│  By Severity:                                  │
│  🔴 High:     7 issues                         │
│  🟡 Medium:   8 issues                         │
│  🟢 Low:      8 issues                         │
│                                                │
│  By Category:                                  │
│  Orphaned Records:           5                 │
│  Stale Data:                12                 │
│  Data Integrity:             4                 │
│  Naming Violations:          2                 │
│                                                │
│  Recent Issues:                                │
│  ┌─────────────────────────┬──────┬─────────┐ │
│  │ Issue                   │ Sev  │ Age     │ │
│  ├─────────────────────────┼──────┼─────────┤ │
│  │ 5 orphaned operations   │ High │ 45 days │ │
│  │ DSP_P736 no activity    │ Med  │ 32 days │ │
│  │ 3 unused resources      │ Low  │ 120 days│ │
│  └─────────────────────────┴──────┴─────────┘ │
│                                                │
│  [Run Cleanup Wizard] [Export Report]         │
└────────────────────────────────────────────────┘
```

### Success Metrics
- Reduce orphaned records by 90%
- Achieve <5 high-severity issues
- Track database size reduction
- Measure cleanup time saved

---

## Feature 14: Natural Language Query Interface

### Concept
Allow users to ask questions in plain English and get answers from the management database without SQL knowledge.

### User Stories
1. As a **non-technical manager**, I want to ask "who worked on P736 last week", so I can get answers without SQL
2. As a **simulation engineer**, I want to quickly find "studies using station 8J-010", so I don't have to write queries
3. As a **team lead**, I want to ask "what changed today", so I can review daily activity easily

### Example Queries

#### Simple Queries
- "Show me all studies modified by Terri last week"
- "Which users are currently working on P736 builds?"
- "Has anyone ever used panel code RCC in production?"
- "What studies use station 8J-010?"

#### Complex Queries
- "Find studies modified after Jan 15 involving station 8J-027"
- "Show me weld operations created by David with more than 50 points"
- "List all resources used in studies modified in the last 3 days"

### Technical Implementation

#### Phase 1: Query Parser (Week 1-2)
```javascript
// Pattern matching engine
const queryPatterns = [
    {
        pattern: /show.*studies.*(modified|changed|updated).*by\s+(\w+)/i,
        type: 'user_activity',
        extractUser: (match) => match[2]
    },
    {
        pattern: /who.*working.*on\s+(\w+)/i,
        type: 'active_users',
        extractProject: (match) => match[1]
    },
    {
        pattern: /studies.*(using|with).*station\s+([0-9A-Z\-]+)/i,
        type: 'station_usage',
        extractStation: (match) => match[2]
    },
    {
        pattern: /what\s+changed\s+(today|yesterday|last\s+week)/i,
        type: 'recent_changes',
        extractTimeframe: (match) => match[1]
    }
];

function parseNaturalLanguage(query) {
    for (const pattern of queryPatterns) {
        const match = query.match(pattern.pattern);
        if (match) {
            return {
                type: pattern.type,
                params: extractParams(pattern, match)
            };
        }
    }
    return { type: 'unknown', query };
}
```

#### Phase 2: SQL Generation (Week 3)
```javascript
function generateSQL(parsedQuery) {
    const templates = {
        user_activity: `
            SELECT rs.NAME_S_, rs.MODIFICATIONDATE_DA_, rs.LASTMODIFIEDBY_S_
            FROM ROBCADSTUDY_ rs
            WHERE rs.LASTMODIFIEDBY_S_ = :user
            ORDER BY rs.MODIFICATIONDATE_DA_ DESC
        `,
        active_users: `
            SELECT DISTINCT rs.LASTMODIFIEDBY_S_, COUNT(*) as study_count
            FROM ROBCADSTUDY_ rs
            JOIN PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
            WHERE rs.NAME_S_ LIKE :project || '%'
            AND p.WORKING_VERSION_ID > 0
            GROUP BY rs.LASTMODIFIEDBY_S_
        `,
        station_usage: `
            SELECT rs.NAME_S_, rs.LASTMODIFIEDBY_S_, rs.MODIFICATIONDATE_DA_
            FROM ROBCADSTUDY_ rs
            JOIN REL_COMMON r ON rs.OBJECT_ID = r.FORWARD_OBJECT_ID
            JOIN SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
            WHERE s.NAME_S_ LIKE :station || '%'
        `
    };

    return templates[parsedQuery.type];
}
```

#### Phase 3: UI Integration (Week 4)
- Search bar with autocomplete
- Suggested queries
- Result formatting
- Export to Excel/CSV

### Mockup Structure
```
Natural Language Query:
┌────────────────────────────────────────────────┐
│  🔍 Ask a question...                          │
│  "Show me all studies modified by Terri"       │
│  [Search]                                      │
├────────────────────────────────────────────────┤
│                                                │
│  Results: 8 studies found                      │
│                                                │
│  ┌──────────────────────────────────────────┐ │
│  │ DDMP P702_8J_010L                        │ │
│  │ Modified: 2026-01-19 13:00               │ │
│  │ Status: Active                           │ │
│  ├──────────────────────────────────────────┤ │
│  │ DDMP P702_8J_010R                        │ │
│  │ Modified: 2026-01-19 12:58               │ │
│  │ Status: Active                           │ │
│  └──────────────────────────────────────────┘ │
│                                                │
│  Suggested queries:                            │
│  • What changed today?                         │
│  • Show studies using station 8J-010           │
│  • Who is working on P736?                     │
└────────────────────────────────────────────────┘
```

### Success Metrics
- 80% query understanding accuracy
- Reduce time to find information by 60%
- Track most common queries for future optimization

---

## Implementation Timeline

### Phase 1 (Weeks 1-4): Foundation
- ✅ Week 1: Complete Feature 13 (Technical Debt Tracking)
- ✅ Week 2: Complete Feature 5 (Collaborative Heat Maps)
- ✅ Week 3: Complete Feature 6 (Study Health Score) - Phase 1
- ✅ Week 4: Complete Feature 6 (Study Health Score) - Phase 2

### Phase 2 (Weeks 5-8): Intelligence
- Week 5-6: Complete Feature 4 (Time-Travel Debugging)
- Week 7-8: Complete Feature 12 (Smart Notifications)

### Phase 3 (Weeks 9-12): Advanced
- Week 9-12: Complete Feature 14 (Natural Language Query) - if time permits

---

## Success Criteria

### Technical Metrics
- All features pass smoke tests
- Dashboard load time < 3 seconds
- Query response time < 5 seconds
- 99.9% uptime

### Business Metrics
- Reduce quality issues by 40%
- Reduce duplicate work by 80%
- Reduce root cause analysis time by 50%
- 90% user adoption within 3 months

### User Satisfaction
- Net Promoter Score (NPS) > 8/10
- Weekly active users > 80% of team
- Feature usage tracking per user

---

## Dependencies

### Data Requirements
- All 11 existing management queries operational ✅
- JSON data parsing completed (in progress)
- Database access via sqlplus ✅

### Technical Stack
- PowerShell for data collection ✅
- HTML/JavaScript for dashboard
- D3.js for visualizations
- Optional: Node.js backend for real-time features

### Infrastructure
- Oracle database access ✅
- Web server for dashboard hosting
- Optional: Email server for notifications
- Optional: Slack/Teams webhooks

---

## Risk Assessment

### High Risk
- **Natural Language Query accuracy**: Mitigation = Start with pattern matching, expand to ML later
- **Real-time notifications performance**: Mitigation = Use polling, not live connections

### Medium Risk
- **User adoption**: Mitigation = Training sessions, documentation, gradual rollout
- **Database query performance**: Mitigation = Add indexes, cache results, limit date ranges

### Low Risk
- **Dashboard UI complexity**: Mitigation = Iterative design, user feedback
- **Integration with existing tools**: Mitigation = Standard APIs, webhooks

---

## Next Steps

1. **Review and approve this plan**
2. **Start with Feature 13 (Technical Debt)** - Lowest complexity, immediate value
3. **Fix JSON parsing issue** in get-management-data.ps1
4. **Create HTML dashboard shell** for all features
5. **Implement features sequentially** following timeline

---

## Notes

- This plan assumes the base management reporting system (Phase 2 foundation) is complete
- Features can be implemented independently and incrementally
- User feedback will guide priority adjustments
- ML/AI features (Feature 14) are optional and can be deferred

**End of Plan**
