# Oracle Load Test Procedures

This document expands on docs/ORACLE-LOAD-TESTING-PLAN.md with step-by-step procedures, scripts, and pass/fail thresholds.

## Objectives
- Validate SimTreeNav does not overload Oracle 12c
- Measure CPU and query impact for 1, 10, and 50 users
- Prove cache effectiveness (>= 87 percent reduction in DB queries)
- Provide rollback steps if thresholds are exceeded

## Preconditions
- DBA approval for load tests and monitoring access
- AWR reporting enabled
- SimTreeNav credentials with read-only access
- Test data set and known project baseline

## Tools
- SQL*Plus or SQL Developer
- Windows PowerShell 5.1
- AWR report scripts

## Baseline Measurement Procedure (Before SimTreeNav)

1) Collect 7-day AWR report
```sql
@?/rdbms/admin/awrrpt.sql
```

2) Capture current metrics
```sql
SELECT COUNT(*) AS active_sessions
FROM V$SESSION
WHERE STATUS = 'ACTIVE';

SELECT
    metric_name,
    value
FROM V$SYSMETRIC
WHERE metric_name IN ('Host CPU Utilization (%)', 'Database CPU Time Ratio');
```

3) Save results
- Save AWR PDF to docs/oracle-baseline.pdf
- Save metrics CSV to docs/oracle-baseline-metrics.csv

Pass/Fail:
- Baseline captured and reviewed by DBA

## Test Scenario ORA-LOAD-01: Single User (No Cache)

Goal: Validate a single user generation stays under 10 percent CPU impact.

Steps:
1) Clear caches on test host
```powershell
Remove-Item -Path C:\SimTreeNav\data\cache\* -Force -ErrorAction SilentlyContinue
```
2) Start DB monitoring queries (separate session)
```sql
SELECT
    sid, serial#, status, sql_id, event, seconds_in_wait
FROM V$SESSION
WHERE username = 'SIMTREENAV_USER'
AND status = 'ACTIVE';
```
3) Run tree generation
```powershell
cd C:\Users\George\source\repos\SimTreeNav\src\powershell\main
Measure-Command { .\generate-tree-html.ps1 -TNSName "DB01" -Schema "DESIGN12" -ProjectId "18140190" -ProjectName "FORD_DEARBORN" }
```

Pass/Fail:
- CPU impact < 10 percent
- No query timeouts
- Total time < 90 seconds

## Test Scenario ORA-LOAD-02: 10 Concurrent Users

Goal: Validate 10 parallel generations stay under 50 percent CPU impact.

Steps:
1) Disable cache to simulate worst case (optional)
2) Launch 10 parallel jobs
```powershell
$jobs = 1..10 | ForEach-Object {
    Start-Job -ScriptBlock {
        cd C:\Users\George\source\repos\SimTreeNav\src\powershell\main
        .\generate-tree-html.ps1 -TNSName "DB01" -Schema "DESIGN12" -ProjectId "18140190" -ProjectName "FORD_DEARBORN"
    }
}
$jobs | Wait-Job | Out-Null
$jobs | Receive-Job | Out-Null
$jobs | Remove-Job
```
3) Monitor CPU and session counts during execution

Pass/Fail:
- CPU impact < 50 percent
- No connection pool exhaustion
- All jobs complete without errors

## Test Scenario ORA-LOAD-03: 50 Concurrent Users (Cached)

Goal: Validate 50 users reading cached output keep CPU impact < 30 percent.

Steps:
1) Pre-generate HTML during off hours
2) Have 50 users open cached HTML within 5 minutes
3) Monitor DB sessions and CPU

Pass/Fail:
- CPU impact < 30 percent
- No DB query spike for cached access

## Cache Effectiveness Test

Goal: Confirm >= 87 percent reduction in DB queries with caching.

Steps:
1) Capture query count for 30 minutes without cache
```sql
SELECT COUNT(*) AS query_count
FROM V$SQL
WHERE parsing_schema_name = 'SIMTREENAV_USER'
AND last_active_time > SYSDATE - (30/1440);
```
2) Enable cache and repeat
3) Compute reduction percentage

Pass/Fail:
- Reduction >= 87 percent

## Rollback Procedure

Trigger: CPU > 90 percent, DB timeouts, or DBA request.

Immediate actions:
1) Disable scheduled refresh tasks
2) Stop manual generation scripts
3) Serve last known good HTML snapshot
4) Notify DBA and stakeholders

Validation:
- DB metrics return to baseline
- No new SimTreeNav queries observed

## Reporting

Record the following for each scenario:
- Start and end time
- Average CPU, peak CPU
- Active sessions and query count
- Pass/Fail result

Save results to:
- docs/oracle-load-results-YYYYMMDD.csv
- docs/oracle-load-results-YYYYMMDD.json

## Example Results Template (CSV)
```
scenario,start_time,end_time,avg_cpu,peak_cpu,query_count,result
ORA-LOAD-01,2026-01-20T08:00:00Z,2026-01-20T08:02:00Z,7,9,3,pass
ORA-LOAD-02,2026-01-20T08:10:00Z,2026-01-20T08:25:00Z,32,47,30,pass
ORA-LOAD-03,2026-01-20T09:00:00Z,2026-01-20T09:10:00Z,11,18,2,pass
```
