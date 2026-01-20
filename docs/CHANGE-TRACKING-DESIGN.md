# Change Tracking System Design: Understanding "What Changed Over Time"

**Critical Question:** How do we make SimTreeNav smart enough to understand what "change" means and track it over time?

**Date:** January 20, 2026

---

## The Challenge

Right now, SimTreeNav shows you a **snapshot** of the database at any given moment. But to be a true simulation management system, we need to answer questions like:

- "What changed in the last week?"
- "Why did this study break?"
- "Who modified the XYZ robot, and when?"
- "What was the state of this assembly 3 days ago?"
- "Which studies were affected when the ABC part changed?"

This requires **change tracking**, **historical data**, and **causality analysis**.

---

## Part 1: What IS a "Change"?

### Types of Changes to Track

#### 1. Direct Changes (Explicit Modifications)

**What:** User explicitly edits a component in Siemens application

**Examples:**
- Engineer modifies robot reach parameter (2500mm → 2800mm)
- Engineer adds a new part to assembly
- Engineer checks out a study for editing

**Data Source:** Oracle audit tables, `SIMUSER_ACTIVITY`, `COLLECTION_` modification timestamps

**Detection Method:**
```sql
-- Compare current state to previous snapshot
SELECT
    c.OBJECT_ID,
    c.NAME,
    c.LAST_MODIFIED_DATE,
    c.LAST_MODIFIED_BY,
    s.NAME as old_name,
    s.LAST_MODIFIED_DATE as old_date
FROM DESIGN1.COLLECTION_ c
LEFT JOIN SIMTREENAV_SNAPSHOT_20260119 s ON c.OBJECT_ID = s.OBJECT_ID
WHERE c.LAST_MODIFIED_DATE > s.LAST_MODIFIED_DATE
   OR s.OBJECT_ID IS NULL -- New record
```

---

#### 2. Cascading Changes (Automatic Side-Effects)

**What:** A change to Component A automatically triggers changes to Components B, C, D

**Examples:**
- Robot specification changes → Assembly using that robot is invalidated
- Part deleted → Studies referencing that part break
- Resource moved → All assemblies using it need re-validation

**Data Source:** Relationship tables (`REL_COMMON`), dependency graphs

**Detection Method:**
```sql
-- Find all components affected by a robot change
WITH changed_robots AS (
    SELECT OBJECT_ID FROM COLLECTION_
    WHERE TYPE_ID IN (SELECT TYPE_ID FROM CLASS_DEFINITIONS WHERE NAME LIKE '%ROBOT%')
      AND LAST_MODIFIED_DATE > SYSDATE - 1
),
affected_assemblies AS (
    SELECT DISTINCT r.FORWARD_OBJECT_ID as assembly_id
    FROM REL_COMMON r
    WHERE r.OBJECT_ID IN (SELECT OBJECT_ID FROM changed_robots)
),
affected_studies AS (
    SELECT DISTINCT r2.FORWARD_OBJECT_ID as study_id
    FROM REL_COMMON r2
    WHERE r2.OBJECT_ID IN (SELECT assembly_id FROM affected_assemblies)
)
SELECT * FROM affected_studies;
```

---

#### 3. State Changes (Status Transitions)

**What:** Component moves through lifecycle states

**Examples:**
- Study status: Draft → Active → Complete → Archived
- Component status: Checked In → Checked Out → Modified → Checked In
- Health score: 85 → 68 → 45 (degrading over time)

**Data Source:** Status fields, `SIMUSER_ACTIVITY`, calculated health scores

**Detection Method:**
- Compare status field between snapshots
- Track checkout/checkin events
- Recalculate health scores daily and log changes

---

#### 4. Temporal Changes (Inactivity/Staleness)

**What:** Component hasn't changed in a long time (which is itself a "change" in state)

**Examples:**
- Study not touched in 14 days → Flag as "stale"
- Resource library not updated in 30 days → Flag as "neglected"

**Data Source:** `LAST_MODIFIED_DATE` fields

**Detection Method:**
```sql
-- Find stale studies
SELECT
    OBJECT_ID,
    NAME,
    LAST_MODIFIED_DATE,
    SYSDATE - LAST_MODIFIED_DATE as days_since_modified
FROM COLLECTION_
WHERE TYPE_ID IN (SELECT TYPE_ID FROM CLASS_DEFINITIONS WHERE NAME LIKE '%STUDY%')
  AND SYSDATE - LAST_MODIFIED_DATE > 14;
```

---

## Part 2: How to Capture Changes

### Option 1: Daily Snapshots (Simplest)

**How It Works:**
1. Every day at 6 AM, take a complete snapshot of the database
2. Store snapshot in a separate table: `SIMTREENAV_SNAPSHOT_YYYYMMDD`
3. Compare today's snapshot to yesterday's to find changes

**Pros:**
- ✅ Simple to implement
- ✅ No database triggers required
- ✅ Works with read-only access
- ✅ Can reconstruct any day's state

**Cons:**
- ❌ Only daily granularity (miss intra-day changes)
- ❌ Storage intensive (310K rows × 365 days = 113M rows/year)
- ❌ Comparison queries can be slow

**Implementation:**

```sql
-- Create snapshot table (run once)
CREATE TABLE SIMTREENAV_SNAPSHOT_20260120 AS
SELECT
    OBJECT_ID,
    NAME,
    TYPE_ID,
    PROJECT_ID,
    LAST_MODIFIED_DATE,
    LAST_MODIFIED_BY,
    -- Key fields only, not all columns
FROM DESIGN1.COLLECTION_
WHERE PROJECT_ID = 1234;

-- Add index for fast lookups
CREATE INDEX idx_snapshot_object ON SIMTREENAV_SNAPSHOT_20260120(OBJECT_ID);

-- Daily comparison (find changes)
SELECT
    'MODIFIED' as change_type,
    c.OBJECT_ID,
    c.NAME,
    c.LAST_MODIFIED_BY,
    c.LAST_MODIFIED_DATE,
    s.LAST_MODIFIED_DATE as previous_date
FROM DESIGN1.COLLECTION_ c
JOIN SIMTREENAV_SNAPSHOT_20260119 s ON c.OBJECT_ID = s.OBJECT_ID
WHERE c.LAST_MODIFIED_DATE > s.LAST_MODIFIED_DATE

UNION ALL

SELECT
    'ADDED' as change_type,
    c.OBJECT_ID,
    c.NAME,
    c.LAST_MODIFIED_BY,
    c.LAST_MODIFIED_DATE,
    NULL as previous_date
FROM DESIGN1.COLLECTION_ c
LEFT JOIN SIMTREENAV_SNAPSHOT_20260119 s ON c.OBJECT_ID = s.OBJECT_ID
WHERE s.OBJECT_ID IS NULL

UNION ALL

SELECT
    'DELETED' as change_type,
    s.OBJECT_ID,
    s.NAME,
    NULL as LAST_MODIFIED_BY,
    NULL as LAST_MODIFIED_DATE,
    s.LAST_MODIFIED_DATE as previous_date
FROM SIMTREENAV_SNAPSHOT_20260119 s
LEFT JOIN DESIGN1.COLLECTION_ c ON s.OBJECT_ID = c.OBJECT_ID
WHERE c.OBJECT_ID IS NULL;
```

**Storage Estimate:**
- 310K rows/day × 50 bytes/row = 15.5 MB/day
- 365 days = 5.65 GB/year
- **Manageable**

**Optimization:**
- Only store snapshots for last 90 days (reduces to ~1.4 GB)
- Archive older snapshots to compressed files

---

### Option 2: Change Log Table (Better Granularity)

**How It Works:**
1. Create a `SIMTREENAV_CHANGE_LOG` table
2. Every hour (or on-demand), query database for recent changes
3. Log only what changed (not full snapshots)

**Pros:**
- ✅ Hourly (or finer) granularity
- ✅ Less storage than full snapshots
- ✅ Faster queries (smaller table)
- ✅ Easy to build timeline from log

**Cons:**
- ❌ Can't reconstruct exact state at arbitrary time (only changes)
- ❌ Requires more complex queries
- ❌ Needs careful handling of missed changes

**Implementation:**

```sql
-- Create change log table (run once)
CREATE TABLE SIMTREENAV_CHANGE_LOG (
    log_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    change_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    change_type VARCHAR2(20), -- 'MODIFIED', 'ADDED', 'DELETED', 'STATE_CHANGE'
    object_id NUMBER,
    object_name VARCHAR2(255),
    object_type VARCHAR2(100),
    modified_by VARCHAR2(100),
    field_changed VARCHAR2(100), -- e.g., 'REACH_PARAMETER', 'STATUS', etc.
    old_value CLOB,
    new_value CLOB,
    project_id NUMBER,
    -- Optional: store impact (affected downstream objects)
    affected_objects CLOB -- JSON array of affected OBJECT_IDs
);

CREATE INDEX idx_change_log_timestamp ON SIMTREENAV_CHANGE_LOG(change_timestamp);
CREATE INDEX idx_change_log_object ON SIMTREENAV_CHANGE_LOG(object_id);
CREATE INDEX idx_change_log_user ON SIMTREENAV_CHANGE_LOG(modified_by);

-- Hourly change detection query
INSERT INTO SIMTREENAV_CHANGE_LOG (
    change_type, object_id, object_name, object_type, modified_by, project_id
)
SELECT
    'MODIFIED',
    c.OBJECT_ID,
    c.NAME,
    cd.NAME as object_type,
    c.LAST_MODIFIED_BY,
    c.PROJECT_ID
FROM DESIGN1.COLLECTION_ c
JOIN DESIGN1.CLASS_DEFINITIONS cd ON c.TYPE_ID = cd.TYPE_ID
WHERE c.LAST_MODIFIED_DATE > SYSDATE - INTERVAL '1' HOUR
  AND c.PROJECT_ID = 1234;

COMMIT;
```

**Storage Estimate:**
- Assume 500 changes/day (busy project)
- 500 rows/day × 200 bytes/row = 100 KB/day
- 365 days = 36.5 MB/year
- **Very manageable**

---

### Option 3: Oracle Flashback (Advanced)

**How It Works:**
- Use Oracle's built-in Flashback Query feature
- Query historical data without storing snapshots

**Pros:**
- ✅ No custom storage needed
- ✅ Can query any point in time (within retention window)
- ✅ Minimal overhead

**Cons:**
- ❌ Requires Oracle Flashback license (may not have)
- ❌ Retention limited (typically 7-14 days)
- ❌ Read-only (can't modify flashback queries)

**Implementation:**

```sql
-- Query state as of 3 days ago
SELECT *
FROM DESIGN1.COLLECTION_
AS OF TIMESTAMP (SYSDATE - 3);

-- Find changes between two time points
SELECT
    current.OBJECT_ID,
    current.NAME,
    current.LAST_MODIFIED_DATE as current_date,
    historical.LAST_MODIFIED_DATE as historical_date
FROM DESIGN1.COLLECTION_ current
LEFT JOIN DESIGN1.COLLECTION_ AS OF TIMESTAMP (SYSDATE - 3) historical
  ON current.OBJECT_ID = historical.OBJECT_ID
WHERE current.LAST_MODIFIED_DATE > historical.LAST_MODIFIED_DATE
   OR historical.OBJECT_ID IS NULL;
```

**Recommendation:** Use if available, but don't depend on it (retention too short).

---

## Part 3: Building the "Change Intelligence" System

### What Makes a System "Smart" About Changes?

**Level 1: Detection** - "Something changed"
- ✅ Already achievable with snapshots or change log

**Level 2: Attribution** - "Who changed what, when"
- ✅ Log user, timestamp, object modified

**Level 3: Causality** - "Change A caused Change B"
- 🔄 Requires dependency graph analysis
- Example: Robot change → Assembly update → Study failure

**Level 4: Impact Analysis** - "If I change X, what breaks?"
- 🔄 Requires forward-looking dependency graph
- Example: "If I delete this part, 5 studies will break"

**Level 5: Predictive** - "This study is likely to fail soon"
- 🔄 Requires trend analysis and ML
- Example: Health score trending down, no recent activity → high risk

---

### Causality Detection: The Hard Part

**The Problem:**
- Engineer changes Robot_XYZ at 4:00 PM Monday
- System auto-updates Assembly_ABC at 10:00 AM Tuesday
- Study_123 fails at 2:00 PM Tuesday
- **How do we know these are related?**

**Solution 1: Dependency Graph**

Build a graph of relationships:

```
Robot_XYZ
  └─> Assembly_ABC (uses Robot_XYZ)
      └─> Study_123 (uses Assembly_ABC)
```

When Robot_XYZ changes:
1. Walk the dependency graph
2. Find all downstream objects
3. Log them as "potentially affected"
4. Monitor them for failures in next 24-48 hours
5. If they fail, link the failure to the root cause change

**Implementation:**

```sql
-- Build dependency graph (run daily)
CREATE TABLE SIMTREENAV_DEPENDENCY_GRAPH AS
WITH RECURSIVE dependencies(child_id, parent_id, depth) AS (
    -- Base case: direct relationships
    SELECT
        r.OBJECT_ID as child_id,
        r.FORWARD_OBJECT_ID as parent_id,
        1 as depth
    FROM DESIGN1.REL_COMMON r

    UNION ALL

    -- Recursive case: indirect relationships
    SELECT
        d.child_id,
        r.FORWARD_OBJECT_ID as parent_id,
        d.depth + 1
    FROM dependencies d
    JOIN DESIGN1.REL_COMMON r ON d.parent_id = r.OBJECT_ID
    WHERE d.depth < 10 -- Prevent infinite loops
)
SELECT * FROM dependencies;

CREATE INDEX idx_dep_child ON SIMTREENAV_DEPENDENCY_GRAPH(child_id);
CREATE INDEX idx_dep_parent ON SIMTREENAV_DEPENDENCY_GRAPH(parent_id);

-- Find all objects affected by Robot_XYZ change
SELECT DISTINCT
    dg.parent_id as affected_object_id,
    c.NAME as affected_object_name,
    cd.NAME as affected_object_type,
    dg.depth as degrees_of_separation
FROM SIMTREENAV_DEPENDENCY_GRAPH dg
JOIN DESIGN1.COLLECTION_ c ON dg.parent_id = c.OBJECT_ID
JOIN DESIGN1.CLASS_DEFINITIONS cd ON c.TYPE_ID = cd.TYPE_ID
WHERE dg.child_id = 12345 -- Robot_XYZ's OBJECT_ID
ORDER BY dg.depth;
```

**Result:**
```
AFFECTED_OBJECT_ID | AFFECTED_OBJECT_NAME | TYPE        | DEPTH
-------------------|---------------------|-------------|------
67890              | Assembly_ABC        | Assembly    | 1
11111              | Study_123           | Study       | 2
22222              | Study_456           | Study       | 2
```

Now when Robot_XYZ changes, we immediately know:
- 1 assembly is directly affected
- 2 studies are indirectly affected (2 degrees away)

**Store this in change log:**

```sql
UPDATE SIMTREENAV_CHANGE_LOG
SET affected_objects = '{"assemblies": [67890], "studies": [11111, 22222]}'
WHERE object_id = 12345
  AND change_timestamp = (
      SELECT MAX(change_timestamp)
      FROM SIMTREENAV_CHANGE_LOG
      WHERE object_id = 12345
  );
```

---

### Solution 2: Timeline Correlation

**The Idea:**
If Study_123 fails within 48 hours of Robot_XYZ changing, and they're related in the dependency graph, assume causality.

**Implementation:**

```sql
-- Find potential root causes for a failed study
WITH study_failure AS (
    SELECT
        object_id,
        change_timestamp as failure_time
    FROM SIMTREENAV_CHANGE_LOG
    WHERE object_id = 11111 -- Study_123
      AND change_type = 'STATE_CHANGE'
      AND new_value = 'FAILED'
    ORDER BY change_timestamp DESC
    FETCH FIRST 1 ROW ONLY
),
recent_upstream_changes AS (
    SELECT
        cl.object_id,
        cl.object_name,
        cl.change_timestamp,
        cl.modified_by,
        dg.depth as degrees_away
    FROM SIMTREENAV_CHANGE_LOG cl
    JOIN SIMTREENAV_DEPENDENCY_GRAPH dg ON cl.object_id = dg.child_id
    JOIN study_failure sf ON dg.parent_id = sf.object_id
    WHERE cl.change_timestamp BETWEEN sf.failure_time - INTERVAL '48' HOUR AND sf.failure_time
      AND cl.change_type IN ('MODIFIED', 'DELETED')
    ORDER BY dg.depth, cl.change_timestamp DESC
)
SELECT * FROM recent_upstream_changes;
```

**Result:**
```
OBJECT_ID | OBJECT_NAME | CHANGE_TIME         | MODIFIED_BY | DEGREES_AWAY
----------|-------------|---------------------|-------------|-------------
12345     | Robot_XYZ   | 2026-01-20 16:00:00 | John Doe    | 2
67890     | Assembly_ABC| 2026-01-21 10:00:00 | System      | 1
```

**Interpretation:**
"Study_123 failed on Jan 21 at 2 PM. The most likely root cause is Robot_XYZ being modified by John Doe on Jan 20 at 4 PM, which triggered an Assembly_ABC update on Jan 21 at 10 AM."

**Display in UI as Timeline:**
```
Jan 20, 4:00 PM  - Robot_XYZ modified by John Doe (reach: 2500mm → 2800mm)
                   ↓
Jan 21, 10:00 AM - Assembly_ABC auto-updated (system)
                   ↓
Jan 21, 2:00 PM  - Study_123 FAILED ⚠️

[ROOT CAUSE: Robot_XYZ reach parameter change]
```

---

## Part 4: Recommended Implementation Plan

### Phase 2 Core (Management Dashboard):

**Goal:** Show "what changed" with basic attribution

**Implementation:**
1. **Daily Snapshots** (Option 1)
   - Store full snapshot once per day
   - Compare yesterday vs. today to show changes
   - Display in timeline: "54 items modified yesterday"

2. **Change Summary View**
   - Daily digest: "23 studies modified, 8 assemblies updated, 5 resources added"
   - Group by work type (5 categories)
   - Show top contributors (who changed the most)

**Deliverable:**
- Timeline showing daily activity
- "What happened this week" summary
- No causality analysis (yet)

**Storage:** ~1.4 GB/year (90-day retention)

**Effort:** 1-2 weeks development

---

### Phase 2 Advanced (Intelligence Layer):

**Goal:** Understand causality and predict failures

**Implementation:**
1. **Hourly Change Log** (Option 2)
   - Detect changes every hour
   - Log to `SIMTREENAV_CHANGE_LOG` table
   - Capture who, what, when, old value, new value

2. **Dependency Graph** (Solution 1)
   - Build once per day
   - Store in `SIMTREENAV_DEPENDENCY_GRAPH`
   - Use for impact analysis

3. **Timeline Correlation** (Solution 2)
   - When study fails, query recent upstream changes
   - Display as "time-travel debugging" timeline
   - Show root cause with evidence

**Deliverable:**
- Time-travel debugging (root cause in 2 minutes)
- Impact analysis ("What breaks if I delete this?")
- Smart notifications ("Study_123 may be affected by your change")

**Storage:** ~40 MB/year (change log only)

**Effort:** 3-4 weeks development

---

### Phase 3 (Predictive Analytics):

**Goal:** Predict failures before they happen

**Implementation:**
1. **Health Score Trending**
   - Log health scores daily
   - Detect downward trends
   - Alert: "Study_123 health declining: 85 → 75 → 68 over 2 weeks"

2. **Staleness Detection**
   - Flag studies not touched in 14+ days
   - Alert: "Study_456 inactive for 21 days - likely abandoned"

3. **Machine Learning (Optional)**
   - Train model on historical failures
   - Features: time since last modification, health score trend, dependency complexity
   - Predict: "Study_789 has 75% chance of failing within 7 days"

**Deliverable:**
- Proactive alerts (before failures occur)
- Risk scoring for all studies
- Trend dashboards

**Effort:** 4-6 weeks (ML adds 2-3 weeks)

---

## Part 5: Data Model Summary

### Tables to Create:

```sql
-- 1. Daily snapshots (Phase 2 Core)
CREATE TABLE SIMTREENAV_SNAPSHOT_{YYYYMMDD} (
    object_id NUMBER,
    name VARCHAR2(255),
    type_id NUMBER,
    project_id NUMBER,
    last_modified_date TIMESTAMP,
    last_modified_by VARCHAR2(100),
    -- Only key fields, not all columns
    CONSTRAINT pk_snapshot PRIMARY KEY (object_id)
);

-- 2. Change log (Phase 2 Advanced)
CREATE TABLE SIMTREENAV_CHANGE_LOG (
    log_id NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    change_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    change_type VARCHAR2(20), -- 'MODIFIED', 'ADDED', 'DELETED', 'STATE_CHANGE'
    object_id NUMBER,
    object_name VARCHAR2(255),
    object_type VARCHAR2(100),
    modified_by VARCHAR2(100),
    field_changed VARCHAR2(100),
    old_value CLOB,
    new_value CLOB,
    project_id NUMBER,
    affected_objects CLOB -- JSON array
);

-- 3. Dependency graph (Phase 2 Advanced)
CREATE TABLE SIMTREENAV_DEPENDENCY_GRAPH (
    child_id NUMBER,
    parent_id NUMBER,
    depth NUMBER,
    CONSTRAINT pk_dependency PRIMARY KEY (child_id, parent_id)
);

-- 4. Health score history (Phase 3)
CREATE TABLE SIMTREENAV_HEALTH_HISTORY (
    study_id NUMBER,
    recorded_date TIMESTAMP,
    health_score NUMBER,
    completeness_score NUMBER,
    consistency_score NUMBER,
    activity_score NUMBER,
    quality_score NUMBER,
    CONSTRAINT pk_health_history PRIMARY KEY (study_id, recorded_date)
);
```

---

## Part 6: Permissions and Access

### Do We Need WRITE Access to Oracle?

**Phase 2 Core (Daily Snapshots):**
- **Option A:** Yes, need to create snapshot tables in DESIGN1 schema
- **Option B:** No, if snapshots stored in separate schema (e.g., SIMTREENAV_DATA) with own credentials

**Phase 2 Advanced (Change Log):**
- **Option A:** Yes, need to INSERT into change log table
- **Option B:** No, if change log stored outside Oracle (e.g., PostgreSQL, SQLite, CSV files)

**Recommendation:**
- Ask for **dedicated SIMTREENAV schema** with read access to DESIGN1-12
- Store snapshots, change logs, dependency graphs in SIMTREENAV schema
- This isolates SimTreeNav data from production schemas

**Grant Required:**
```sql
-- Run by DBA
CREATE USER simtreenav IDENTIFIED BY <password>;
GRANT CREATE SESSION TO simtreenav;
GRANT CREATE TABLE TO simtreenav;
GRANT CREATE VIEW TO simtreenav;
GRANT UNLIMITED TABLESPACE TO simtreenav;

-- Grant read access to production schemas
GRANT SELECT ON DESIGN1.COLLECTION_ TO simtreenav;
GRANT SELECT ON DESIGN1.REL_COMMON TO simtreenav;
GRANT SELECT ON DESIGN1.CLASS_DEFINITIONS TO simtreenav;
GRANT SELECT ON DESIGN1.SIMUSER_ACTIVITY TO simtreenav;
-- ... (grant for all tables needed)
```

---

## Part 7: Performance Considerations

### Snapshot Comparison Performance:

**Problem:** Comparing 310K rows daily can be slow

**Solution:**
```sql
-- Use hash comparison instead of row-by-row
WITH current_hash AS (
    SELECT
        ORA_HASH(object_id || name || last_modified_date || last_modified_by) as row_hash,
        object_id
    FROM DESIGN1.COLLECTION_
    WHERE project_id = 1234
),
previous_hash AS (
    SELECT
        ORA_HASH(object_id || name || last_modified_date || last_modified_by) as row_hash,
        object_id
    FROM SIMTREENAV_SNAPSHOT_20260119
)
SELECT
    COALESCE(c.object_id, p.object_id) as object_id,
    CASE
        WHEN c.row_hash IS NULL THEN 'DELETED'
        WHEN p.row_hash IS NULL THEN 'ADDED'
        WHEN c.row_hash != p.row_hash THEN 'MODIFIED'
    END as change_type
FROM current_hash c
FULL OUTER JOIN previous_hash p ON c.object_id = p.object_id
WHERE c.row_hash IS NULL
   OR p.row_hash IS NULL
   OR c.row_hash != p.row_hash;
```

**Expected Performance:** < 5 seconds for 310K rows

---

## Part 8: Testing the Change Tracking System

### Test Scenario 1: Detect Direct Change

**Setup:**
1. Take snapshot at 9:00 AM
2. Modify Robot_XYZ reach parameter at 10:00 AM
3. Take snapshot at 11:00 AM
4. Run comparison

**Expected Result:**
```
CHANGE_TYPE | OBJECT_ID | OBJECT_NAME | MODIFIED_BY | FIELD_CHANGED
------------|-----------|-------------|-------------|---------------
MODIFIED    | 12345     | Robot_XYZ   | John Doe    | REACH_PARAM
```

---

### Test Scenario 2: Detect Cascading Change

**Setup:**
1. Modify Robot_XYZ at 10:00 AM
2. System auto-updates Assembly_ABC at 10:05 AM
3. Run dependency graph query

**Expected Result:**
```
AFFECTED_OBJECT_ID | AFFECTED_OBJECT_NAME | DEPTH
-------------------|---------------------|------
67890              | Assembly_ABC        | 1
11111              | Study_123           | 2
```

---

### Test Scenario 3: Root Cause Analysis

**Setup:**
1. Study_123 fails at 2:00 PM
2. Run timeline correlation query
3. Find Robot_XYZ was changed at 10:00 AM (4 hours earlier)

**Expected Result:**
```
Timeline:
10:00 AM - Robot_XYZ modified (John Doe)
10:05 AM - Assembly_ABC auto-updated (System)
2:00 PM  - Study_123 FAILED

Root Cause: Robot_XYZ reach parameter change
```

---

## Conclusion: Making the System "Smart"

**To understand "what changed over time," SimTreeNav needs:**

1. **Data Capture** (Phase 2 Core):
   - Daily snapshots or hourly change log
   - Store who, what, when, old value, new value

2. **Dependency Mapping** (Phase 2 Advanced):
   - Build relationship graph
   - Identify upstream/downstream dependencies

3. **Causality Detection** (Phase 2 Advanced):
   - Correlate changes with failures
   - Walk dependency graph to find root causes

4. **Impact Prediction** (Phase 3):
   - Trend analysis (health scores declining)
   - Machine learning (predict failures)

**Recommended First Step:**
- Implement daily snapshots (Phase 2 Core)
- Prove value with basic change tracking
- Expand to hourly log + dependency graph (Phase 2 Advanced) once validated

**Storage Impact:** Minimal (< 2 GB/year for all tracking data)

**Performance Impact:** Low (< 5% Oracle load with proper indexing)

**Complexity:** Medium (requires careful schema design and graph algorithms)

---

**Next Steps:**
1. Review this design with DBA team
2. Request dedicated SIMTREENAV schema with write access
3. Prototype daily snapshot on 1 project (DESIGN1)
4. Measure performance and storage
5. Expand to full change tracking if successful

---

**Questions to Answer Before Implementation:**
- [ ] Do we have write access to create tables in Oracle?
- [ ] Can we get dedicated schema (SIMTREENAV) with grants?
- [ ] Is Oracle Flashback available? (nice-to-have, not required)
- [ ] What's acceptable storage limit? (we estimate < 2 GB/year)
- [ ] How far back should we retain history? (recommend 90 days)

---

**End of Change Tracking Design**

This is the technical foundation for making SimTreeNav truly "smart" about understanding what changed and why.
