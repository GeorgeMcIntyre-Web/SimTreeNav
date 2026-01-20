# Oracle Server Load Testing Plan

**Critical Concern:** Ensure SimTreeNav doesn't overload the Oracle production server

**Date:** January 20, 2026

---

## Executive Summary

**The Risk:**
SimTreeNav queries an Oracle database with 8M+ rows. If 50 users all run queries simultaneously, we could slow down or crash the production database - impacting everyone who uses it (not just SimTreeNav).

**The Solution:**
Three-tier caching system + load testing plan to validate safe concurrent usage before full deployment.

**Bottom Line:**
With proper caching (already implemented), SimTreeNav should generate <5% additional load on Oracle server. This document provides testing plan to validate that claim.

---

## Part 1: Current Database Load Profile

### Baseline Measurements (BEFORE SimTreeNav)

**What to Measure:**

| Metric | How to Check | Baseline Value |
|--------|-------------|----------------|
| **Average CPU Usage** | Oracle AWR report, last 30 days | Target: < 60% avg |
| **Peak CPU Usage** | AWR report, max CPU in last 30 days | Target: < 85% peak |
| **Active Sessions** | `SELECT COUNT(*) FROM V$SESSION WHERE STATUS='ACTIVE'` | Typical: 10-30 |
| **Queries/Second** | AWR report, "SQL Statistics" section | Typical: 50-200/sec |
| **I/O Wait Time** | AWR report, "Wait Events" section | Target: < 10% of DB time |
| **Table Scan Frequency** | Query execution plans for COLLECTION_ table | Current: ?/day |

**How to Get This Data:**

```sql
-- Run as DBA or user with SELECT_CATALOG_ROLE
-- Generate AWR report for last 7 days
@?/rdbms/admin/awrrpt.sql

-- Check current active sessions
SELECT
    COUNT(*) as active_sessions,
    SUM(CASE WHEN status='ACTIVE' THEN 1 ELSE 0 END) as currently_active
FROM V$SESSION;

-- Check table access patterns (last 7 days)
SELECT
    sql_text,
    executions,
    disk_reads,
    buffer_gets,
    elapsed_time/1000000 as elapsed_sec
FROM V$SQL
WHERE sql_text LIKE '%COLLECTION_%'
ORDER BY executions DESC
FETCH FIRST 20 ROWS ONLY;
```

**Deliverable:**
- [ ] Baseline AWR report (PDF, save to `docs/oracle-baseline.pdf`)
- [ ] Spreadsheet with current metrics (save to `docs/oracle-baseline-metrics.xlsx`)
- [ ] Share with DBA team for review

---

## Part 2: SimTreeNav Query Profile

### What Queries Does SimTreeNav Run?

**Phase 1 Queries (Per User, Per Session):**

| Query | Frequency | Cache Lifetime | Estimated Rows | Estimated Time |
|-------|-----------|----------------|----------------|----------------|
| **Icon Extraction** | 1×/week/server | 7 days | 221 rows | 15-20 sec (first run) |
| **Tree Structure** | 1×/day/server | 24 hours | 310K rows | 40-50 sec (first run) |
| **User Activity** | 1×/hour/server | 1 hour | 50-100 rows | 1-2 sec |

**Key Insight:** With caching, most users NEVER hit the database directly - they load pre-generated HTML files.

**Database Hits Per Day (Cached):**
- Icon query: 1× per week = **0.14 queries/day**
- Tree query: 1× per day = **1 query/day**
- User activity: 24× per day = **24 queries/day**

**Total:** ~25 queries/day for entire team (not per user)

---

### Phase 2 Queries (Management Dashboard)

**Additional Queries:**

| Query | Frequency | Cache | Rows | Time |
|-------|-----------|-------|------|------|
| **Study List** | 1×/hour | 15 min | 127 rows | < 1 sec |
| **Work Type Breakdown** | 1×/hour | 15 min | 5 rows | < 1 sec |
| **Activity Timeline** | 1×/hour | 15 min | 200-500 rows | 2-3 sec |
| **Health Score Calculation** | 1×/hour | 15 min | 127 rows | 3-5 sec |

**Database Hits Per Day (Phase 2):**
- Study queries: 24× per day
- Work type: 24× per day
- Timeline: 24× per day
- Health: 24× per day

**Total:** ~100 queries/day additional (still low)

---

## Part 3: Load Testing Scenarios

### Scenario 1: Single User (Baseline)

**Test:** One engineer generates tree from scratch (no cache)

**Expected Load:**
- 3 queries (icons, tree, user activity)
- Total time: 60-70 seconds
- CPU spike: < 5% for duration
- Impact on other users: negligible

**How to Test:**

```powershell
# Clear all caches first
Remove-Item C:\SimTreeNav\data\cache\*.* -Force

# Generate tree
cd C:\SimTreeNav\src\powershell\main
Measure-Command { .\generate-tree-html.ps1 -SchemaName "DESIGN1" }

# Check Oracle load during generation
# (Run this on DB server while generation running)
```

```sql
-- Monitor on Oracle server (run in separate session)
SELECT
    sid,
    serial#,
    username,
    status,
    sql_id,
    event,
    seconds_in_wait,
    state
FROM V$SESSION
WHERE username = 'YOUR_SIMTREENAV_USER'
AND status = 'ACTIVE';

-- Check CPU usage
SELECT
    value
FROM V$OSSTAT
WHERE stat_name = 'NUM_CPUS';

SELECT
    value
FROM V$SYSMETRIC
WHERE metric_name = 'Host CPU Usage Per Sec'
ORDER BY begin_time DESC
FETCH FIRST 1 ROW ONLY;
```

**Pass Criteria:**
- ✅ Generation completes in < 90 seconds
- ✅ Oracle CPU increase < 10%
- ✅ No wait events > 5 seconds
- ✅ Other concurrent queries not impacted

---

### Scenario 2: 10 Concurrent Users (Realistic Load)

**Test:** 10 engineers all open SimTreeNav at the same time

**Expected Load (With Caching):**
- 10 HTML file loads from cache (0 DB queries)
- Impact on Oracle: **ZERO** (files are pre-generated)

**Expected Load (WITHOUT Caching - Worst Case):**
- 10× simultaneous tree queries
- 30 concurrent queries hitting DB
- Duration: 60-90 seconds
- CPU spike: 20-40%?

**How to Test:**

```powershell
# Test script: simultaneous-load-test.ps1
# Run 10 parallel tree generations

$jobs = @()
1..10 | ForEach-Object {
    $jobs += Start-Job -ScriptBlock {
        cd C:\SimTreeNav\src\powershell\main
        .\generate-tree-html.ps1 -SchemaName "DESIGN1"
    }
}

# Wait for all jobs to complete
$jobs | Wait-Job

# Get results
$jobs | Receive-Job
$jobs | Remove-Job
```

**Monitor Oracle During Test:**

```sql
-- Check concurrent sessions
SELECT COUNT(*) as concurrent_sessions
FROM V$SESSION
WHERE username = 'YOUR_SIMTREENAV_USER'
AND status = 'ACTIVE';

-- Check wait events
SELECT
    event,
    COUNT(*) as session_count,
    AVG(wait_time) as avg_wait_ms
FROM V$SESSION_WAIT
WHERE sid IN (
    SELECT sid FROM V$SESSION
    WHERE username = 'YOUR_SIMTREENAV_USER'
)
GROUP BY event
ORDER BY session_count DESC;

-- Check CPU impact
SELECT
    TO_CHAR(begin_time, 'HH24:MI:SS') as time,
    value as cpu_pct
FROM V$SYSMETRIC_HISTORY
WHERE metric_name = 'Host CPU Utilization (%)'
AND begin_time > SYSDATE - INTERVAL '10' MINUTE
ORDER BY begin_time DESC;
```

**Pass Criteria:**
- ✅ All 10 generations complete successfully
- ✅ Oracle CPU increase < 50%
- ✅ No timeouts or connection failures
- ✅ Completion time < 120 seconds per user
- ✅ Other production queries not impacted

---

### Scenario 3: 50 Concurrent Users (Full Deployment)

**Test:** Entire engineering team (50 people) uses SimTreeNav simultaneously

**Expected Load (With Caching):**
- 50 HTML file loads from network share/IIS (0 DB queries)
- Impact on Oracle: **ZERO**

**Expected Load (Cache Refresh Hour - Worst Case):**
- 1 tree generation (scheduled task at 6 AM)
- 3-4 queries hitting DB
- Duration: 60 seconds
- CPU spike: < 10%

**How to Test:**

**Option A: Simulate with Parallel Queries**

```sql
-- Create test script that runs 50 simultaneous queries
-- Run from SQL*Plus or Oracle SQL Developer

BEGIN
  FOR i IN 1..50 LOOP
    EXECUTE IMMEDIATE '
      INSERT INTO simtreenav_load_test_log
      SELECT
        :user_id,
        SYSDATE,
        COUNT(*)
      FROM DESIGN1.COLLECTION_
      WHERE PROJECT_ID = 1234
    ' USING i;
    COMMIT;
  END LOOP;
END;
/
```

**Option B: Stagger Real User Access**

```powershell
# Have 50 users open SimTreeNav within 5-minute window
# Monitor Oracle load during that time
# (Coordinate with team via email/meeting)
```

**Pass Criteria:**
- ✅ Oracle CPU increase < 30%
- ✅ No connection pool exhaustion
- ✅ All queries complete in < 10 seconds
- ✅ Production workload not impacted

---

## Part 4: Mitigation Strategies (If Tests Fail)

### If Single User Test Fails (Unlikely):

**Problem:** One tree generation causes >10% CPU spike

**Solutions:**
1. **Optimize Queries:** Add indexes to COLLECTION_ table on frequently queried columns
   ```sql
   CREATE INDEX idx_collection_type ON DESIGN1.COLLECTION_(TYPE_ID);
   CREATE INDEX idx_collection_project ON DESIGN1.COLLECTION_(PROJECT_ID);
   ```
2. **Reduce Row Count:** Query only necessary columns, not `SELECT *`
3. **Pagination:** Generate tree in chunks (e.g., 50K nodes at a time)

---

### If 10 Concurrent User Test Fails:

**Problem:** 10 simultaneous generations cause >50% CPU or timeouts

**Solutions:**
1. **Enforce Caching (Recommended):**
   - Never allow users to regenerate manually
   - Only scheduled task (6 AM daily) regenerates
   - All users load from cache
   - **Database load reduced by 99%**

2. **Queue System:**
   - If manual generation allowed, implement queue
   - Only 1-2 generations can run simultaneously
   - Others wait in line

3. **Read Replica:**
   - Set up Oracle read replica (secondary DB)
   - Point SimTreeNav queries to replica
   - Production DB unaffected

---

### If 50 Concurrent User Test Fails:

**Problem:** 50 HTML file loads cause network/IIS issues (not Oracle-related)

**Solutions:**
1. **CDN or Caching Proxy:** Serve HTML files from local cache
2. **Compression:** Enable gzip compression for 95 MB HTML files (reduces to ~10 MB)
3. **Local Distribution:** Copy HTML file to each user's machine weekly

---

## Part 5: Production Monitoring Plan

### Daily Checks (Automated):

**Create Monitoring Script:**

```powershell
# oracle-health-check.ps1
# Run daily at 8 AM via Task Scheduler

# Connect to Oracle
$connection = "user/password@server:1521/service"

# Check SimTreeNav query count (last 24 hours)
$query = @"
SELECT COUNT(*) as query_count
FROM V$SQL
WHERE parsing_schema_name = 'YOUR_SIMTREENAV_USER'
AND last_active_time > SYSDATE - 1
"@

$result = sqlplus -s $connection << EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
$query
EXIT
EOF

# Alert if > 200 queries/day (threshold)
if ($result -gt 200) {
    Send-MailMessage -To "dba@company.com" -Subject "SimTreeNav High Query Count" -Body "SimTreeNav ran $result queries in last 24 hours (threshold: 200)"
}

# Check for slow queries (> 30 seconds)
$slowQuery = @"
SELECT COUNT(*)
FROM V$SQL
WHERE parsing_schema_name = 'YOUR_SIMTREENAV_USER'
AND elapsed_time/1000000 > 30
"@

$slowCount = sqlplus -s $connection << EOF
SET PAGESIZE 0 FEEDBACK OFF VERIFY OFF HEADING OFF ECHO OFF
$slowQuery
EXIT
EOF

if ($slowCount -gt 0) {
    Send-MailMessage -To "dba@company.com" -Subject "SimTreeNav Slow Queries Detected" -Body "$slowCount queries took >30 seconds"
}
```

---

### Weekly Oracle Health Report:

**Metrics to Track:**

| Metric | Pre-SimTreeNav | Post-SimTreeNav | Change | Threshold |
|--------|----------------|-----------------|--------|-----------|
| Avg CPU % | 45% | ? | ? | Alert if >60% |
| Peak CPU % | 78% | ? | ? | Alert if >85% |
| Queries/Day | 15,000 | ? | ? | Alert if >20,000 |
| Slow Queries (>10s) | 12/week | ? | ? | Alert if >25/week |
| Table Scans on COLLECTION_ | 200/day | ? | ? | Alert if >300/day |

**How to Generate:**

```sql
-- Run weekly, compare to baseline
-- Save to CSV for trending

SELECT
    TRUNC(begin_time) as date,
    ROUND(AVG(value), 2) as avg_cpu_pct,
    ROUND(MAX(value), 2) as peak_cpu_pct
FROM V$SYSMETRIC_HISTORY
WHERE metric_name = 'Host CPU Utilization (%)'
AND begin_time > SYSDATE - 7
GROUP BY TRUNC(begin_time)
ORDER BY date;

-- Export to CSV
SPOOL C:\SimTreeNav\logs\oracle-weekly-report.csv
[above query]
SPOOL OFF
```

---

## Part 6: Rollback Plan (If Oracle Load Is Unacceptable)

### If Production DB Impact Detected:

**Immediate Actions:**

1. **Stop Manual Tree Generation:**
   ```powershell
   # Disable manual generation script
   Rename-Item generate-tree-html.ps1 generate-tree-html.ps1.DISABLED
   ```

2. **Disable Scheduled Task:**
   ```powershell
   Disable-ScheduledTask -TaskName "SimTreeNav Daily Refresh"
   ```

3. **Serve Static Snapshot:**
   - Keep last good HTML file
   - Serve that until issue resolved
   - Add banner: "Data may be up to 48 hours old"

4. **Investigate Root Cause:**
   - Review slow query logs
   - Check for missing indexes
   - Look for N+1 query problems

5. **Implement Fix:**
   - Optimize queries
   - Add indexes
   - Reduce query frequency
   - Consider read replica

6. **Re-Test:**
   - Run load tests again
   - Validate fix reduces DB load
   - Resume operations only when safe

---

## Part 7: Pre-Deployment Checklist

### Before Phase 1 Deployment:

- [ ] **Baseline Measurement Complete**
  - [ ] AWR report saved
  - [ ] Current CPU/query metrics documented
  - [ ] DBA team reviewed and approved baseline

- [ ] **Single User Test Passed**
  - [ ] Tree generation completes in < 90 seconds
  - [ ] Oracle CPU impact < 10%
  - [ ] No slow query warnings

- [ ] **10 Concurrent User Test Passed**
  - [ ] All users complete successfully
  - [ ] Oracle CPU impact < 50%
  - [ ] No timeouts or failures

- [ ] **Caching Validated**
  - [ ] Icon cache working (7-day lifetime)
  - [ ] Tree cache working (24-hour lifetime)
  - [ ] User activity cache working (1-hour lifetime)

- [ ] **Monitoring Setup**
  - [ ] Daily health check script scheduled
  - [ ] Alert thresholds configured
  - [ ] DBA team has access to dashboards

- [ ] **Rollback Plan Documented**
  - [ ] Emergency shutdown procedure written
  - [ ] Static snapshot prepared
  - [ ] DBA contact list ready

---

### Before Phase 2 Deployment:

- [ ] **Phase 1 Oracle Impact Measured**
  - [ ] 4 weeks of production data collected
  - [ ] Confirmed <5% additional load
  - [ ] No slow queries or timeouts

- [ ] **Phase 2 Query Testing**
  - [ ] Study list query tested (< 1 second)
  - [ ] Work type query tested (< 1 second)
  - [ ] Health score query tested (< 5 seconds)
  - [ ] Timeline query tested (< 3 seconds)

- [ ] **Phase 2 Load Test Passed**
  - [ ] 50 concurrent users simulated
  - [ ] Oracle CPU impact < 30%
  - [ ] All queries complete successfully

---

## Part 8: Success Metrics

### Oracle Load Is Acceptable If:

✅ **Phase 1:**
- Average CPU increase < 5%
- Peak CPU increase < 10%
- Query count increase < 100/day
- No slow queries (> 30 seconds)
- No impact on other production workloads

✅ **Phase 2:**
- Average CPU increase < 10%
- Peak CPU increase < 20%
- Query count increase < 200/day
- All queries complete in < 10 seconds
- No user complaints about DB performance

### Oracle Load Is Unacceptable If:

❌ **Immediate Rollback Required:**
- Production DB CPU > 90%
- Other systems experiencing slowdowns
- Timeout errors for SimTreeNav users
- DBA team requests shutdown

❌ **Optimization Required:**
- Average CPU increase > 10%
- Slow queries (> 30 sec) occurring regularly
- Query count > 500/day

---

## Part 9: Optimization Opportunities

### If Load Testing Shows Issues:

**Quick Wins:**

1. **Add Indexes:**
   ```sql
   -- Indexes to speed up common queries
   CREATE INDEX idx_collection_type_project ON DESIGN1.COLLECTION_(TYPE_ID, PROJECT_ID);
   CREATE INDEX idx_rel_common_object ON DESIGN1.REL_COMMON(OBJECT_ID, FORWARD_OBJECT_ID);
   CREATE INDEX idx_simuser_activity_user ON DESIGN1.SIMUSER_ACTIVITY(LOGNAME, LAST_MODIFIED);
   ```

2. **Query Result Caching (Oracle Feature):**
   ```sql
   ALTER SESSION SET QUERY_REWRITE_ENABLED = TRUE;
   ALTER SESSION SET RESULT_CACHE_MODE = FORCE;
   ```

3. **Materialized Views (For Phase 2):**
   ```sql
   -- Pre-compute study health scores
   CREATE MATERIALIZED VIEW mv_study_health
   REFRESH COMPLETE ON DEMAND
   AS
   SELECT
       study_id,
       study_name,
       owner,
       -- health score calculation here
   FROM DESIGN1.ROBCADSTUDY_
   WHERE active = 1;

   -- Refresh hourly via scheduled job
   ```

**Long-Term Solutions:**

1. **Read Replica:**
   - Set up Oracle Active Data Guard
   - Point all SimTreeNav queries to standby DB
   - Primary DB unaffected

2. **Data Warehouse:**
   - ETL process copies relevant data to separate warehouse
   - SimTreeNav queries warehouse, not production
   - Full isolation from production workload

---

## Conclusion

**Oracle server load is a legitimate concern, but easily testable and mitigatable.**

**Plan:**
1. Measure baseline (current Oracle load)
2. Run load tests (single user, 10 users, 50 users)
3. Validate caching reduces load by 95%+
4. Deploy Phase 1 with monitoring
5. Measure actual impact for 4 weeks
6. Proceed to Phase 2 only if Oracle load is acceptable

**Expected Result:**
With three-tier caching, SimTreeNav adds <5% load to Oracle server - well within acceptable limits.

**Worst-Case Plan:**
If load is unacceptable, implement read replica or data warehouse (additional cost, but solves problem permanently).

---

**Next Steps:**
1. Schedule load testing session with DBA team (2-4 hours)
2. Run baseline measurements
3. Execute test scenarios
4. Document results
5. Get DBA sign-off before production deployment

**Contact:** [DBA Team Lead] for coordination
