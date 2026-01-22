# Phase 2: Acceptance Criteria

**Version:** 1.0
**Date:** 2026-01-22
**Status:** Definition of Done - LOCKED

## Overview

This document defines the exit criteria for Phase 2: Management Dashboard. All gates must pass before merging to main branch.

## Gate 1: Performance

### 1.1 Script Generation Time

**Metric:** Time from script invocation to HTML file created

**Targets:**
- First run (no cache): ≤60 seconds
- Cached run: ≤15 seconds

**Measurement:**
```powershell
Measure-Command {
    .\management-dashboard-launcher.ps1 `
        -TNSName "SIEMENS_PS_DB_DB01" `
        -Schema "DESIGN12" `
        -ProjectId 18140190 `
        -AutoLaunch:$false
}
```

**Pass Criteria:**
- 3 consecutive runs all meet target times
- No timeout errors

### 1.2 Browser Load Time

**Metric:** Time from HTML file open to dashboard fully rendered

**Targets:**
- Page load: ≤5 seconds
- All charts/graphs visible: ≤8 seconds

**Measurement:**
1. Open browser DevTools → Performance tab
2. Record page load
3. Check "DOMContentLoaded" and "Load" events

**Pass Criteria:**
- DOMContentLoaded: ≤3 seconds
- Load event: ≤5 seconds
- No JavaScript errors in console

### 1.3 Dashboard File Size

**Metric:** Size of generated HTML file

**Target:** ≤10 MB

**Measurement:**
```powershell
(Get-Item "data\output\management-dashboard-DESIGN12-18140190.html").Length / 1MB
```

**Pass Criteria:**
- HTML file ≤10 MB
- JSON data file ≤5 MB

### 1.4 Query Performance

**Metric:** Individual SQL query execution time

**Targets:**
- Any single query: ≤30 seconds
- Total query time (all 5 work types): ≤45 seconds

**Measurement:**
- Log timestamps before/after each query in `get-management-data.ps1`
- Report timing in console output

**Pass Criteria:**
- All queries complete within targets
- No database timeout errors

## Gate 2: Reliability

### 2.1 Zero Hard Crashes

**Requirement:** Script must never crash without graceful error message

**Test Scenarios:**
1. Database unreachable
2. Invalid credentials
3. Missing table (e.g., VEC_LOCATION_ not present)
4. Empty result set (no activity in date range)
5. Partial data (some work types have data, others don't)
6. Corrupt cache file

**Pass Criteria:**
- All scenarios produce error message
- Exit code: 1 (failure), not unhandled exception
- No PowerShell stack traces visible to user

### 2.2 Degraded Mode Support

**Requirement:** If one work type fails, others still process

**Test Scenario:**
- Comment out RESOURCE_ table in query
- Re-run dashboard generation

**Expected Behavior:**
```json
{
  "resourceLibrary": {
    "error": true,
    "message": "Query failed: Invalid object name RESOURCE_",
    "activeCount": 0,
    "modifiedCount": 0,
    "uniqueUsers": [],
    "items": []
  }
}
```

**Pass Criteria:**
- Dashboard generates successfully
- resourceLibrary section shows "No data (query failed)"
- Other 4 work types display correctly

### 2.3 Cache Invalidation

**Requirement:** Cache expires after 15 minutes, forcing fresh query

**Test Steps:**
1. Generate dashboard (creates cache)
2. Wait 16 minutes OR manually set cache file timestamp to 16 minutes ago
3. Re-run dashboard generation

**Expected Behavior:**
- Console output: "Cache expired, running fresh queries"
- New cache file created with current timestamp

**Pass Criteria:**
- Dashboard reflects latest database state
- Cache file timestamp updated

### 2.4 Error Message Clarity

**Requirement:** User can troubleshoot from error message alone

**Test:**
- Provide invalid TNSName
- Check console output

**Good Error Message Example:**
```
ERROR: Database connection failed
  TNS Name: INVALID_DB
  Schema: DESIGN12
  Error: ORA-12154: TNS:could not resolve the connect identifier specified

Troubleshooting:
  1. Check tnsnames.ora contains entry for INVALID_DB
  2. Verify TNS_ADMIN environment variable: C:\oracle\network\admin
  3. Test connection: sqlplus user/pass@INVALID_DB
```

**Pass Criteria:**
- Error message includes actionable troubleshooting steps
- No technical jargon without explanation
- Contact info or documentation link provided

## Gate 3: Reproducibility

### 3.1 One-Command Execution

**Requirement:** New contributor can generate dashboard without reading code

**Test:**
- Fresh Windows VM (or colleague's machine)
- Provide only README.md
- Ask to generate management dashboard

**Pass Criteria:**
- User runs single command from README
- Dashboard opens in browser
- No "What do I do next?" questions

**Command (from README):**
```powershell
.\management-dashboard-launcher.ps1 `
    -TNSName "SIEMENS_PS_DB_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18140190
```

### 3.2 Documented Data Contract

**Requirement:** JSON schema fully documented in PHASE2_DASHBOARD_SPEC.md

**Test:**
1. Read PHASE2_DASHBOARD_SPEC.md
2. Without reading script source, predict JSON structure
3. Generate actual JSON
4. Compare

**Pass Criteria:**
- All JSON keys documented
- Data types match
- Sample values provided
- No undocumented keys in actual output

### 3.3 Verification Script

**Requirement:** Automated script validates dashboard correctness

**Script:** `verify-management-dashboard.ps1`

**Checks:**
1. JSON file exists
2. HTML file exists
3. All 5 work type sections present
4. Timeline array not empty (if activity exists)
5. User list not empty (if activity exists)
6. No JavaScript errors in HTML (via headless browser test)

**Usage:**
```powershell
.\verify-management-dashboard.ps1 -Schema "DESIGN12" -ProjectId 18140190
```

**Output:**
```
PASS: JSON file exists
PASS: HTML file exists
PASS: All 5 work types present
PASS: Timeline has 127 events
PASS: 4 unique users found
PASS: HTML loads without JavaScript errors
PASS: All required sections rendered

OVERALL: PASS (7/7 checks)
```

**Pass Criteria:**
- Verification script included in PR
- All checks pass on test data
- Script documented in README

### 3.4 Sample Data Provided

**Requirement:** Anonymized test data for development/testing

**Files:**
- `test/fixtures/management-sample-DESIGN12-18140190.json`
- `test/fixtures/management-sample-empty.json` (zero activity)

**Pass Criteria:**
- Sample JSON validates against schema
- Generator script can process sample data without database
- Empty data sample produces valid "No activity" dashboard

## Gate 4: Functional Correctness

### 4.1 Work Type Summary Accuracy

**Test:**
1. Generate dashboard
2. Manually count active/modified items in database for one work type (e.g., Study Nodes)
3. Compare dashboard counts

**SQL Verification Query:**
```sql
-- Count active studies (checked out)
SELECT COUNT(*) FROM DESIGN12.ROBCADSTUDY_ rs
INNER JOIN DESIGN12.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
WHERE p.WORKING_VERSION_ID > 0;

-- Count modified studies (last 7 days)
SELECT COUNT(*) FROM DESIGN12.ROBCADSTUDY_ rs
WHERE rs.MODIFICATIONDATE_DA_ > SYSDATE - 7;
```

**Pass Criteria:**
- Dashboard counts match manual SQL counts (±5% tolerance for race conditions)
- All 5 work types verified

### 4.2 World Location Change Detection

**Test:**
1. Find known world location change in VEC_LOCATION_ table
   ```sql
   SELECT * FROM DESIGN12.VEC_LOCATION_
   WHERE ABS(X_COORD - LAG(X_COORD) OVER (PARTITION BY OBJECT_ID ORDER BY MODIFICATIONDATE_DA_)) > 1000
   ```
2. Verify it appears in dashboard as "World Location Change"

**Pass Criteria:**
- Dashboard flags all coordinate changes ≥1000mm as "World Location Change"
- Simple moves (<1000mm) correctly categorized
- Movement type icons/colors display correctly

### 4.3 User Activity Attribution

**Test:**
1. Check PROXY table for specific user checkout
   ```sql
   SELECT p.OBJECT_ID, u.CAPTION_S_ FROM DESIGN12.PROXY p
   INNER JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
   WHERE u.CAPTION_S_ = 'John Smith' AND p.WORKING_VERSION_ID > 0;
   ```
2. Verify dashboard shows same items as checked out by John Smith

**Pass Criteria:**
- User attribution matches PROXY.OWNER_ID → USER_.CAPTION_S_
- No "Unknown user" entries when USER_ record exists

### 4.4 Timeline Chronological Order

**Test:**
1. Check timeline section in JSON
2. Verify timestamps are newest-first

**Pass Criteria:**
- `timeline[0].timestamp > timeline[1].timestamp > ... > timeline[n].timestamp`
- Dashboard displays events newest at top

### 4.5 Empty State Handling

**Test:**
1. Query date range with zero activity (e.g., future date)
   ```powershell
   .\management-dashboard-launcher.ps1 -StartDate "2030-01-01" -EndDate "2030-01-02"
   ```
2. Verify dashboard displays gracefully

**Expected Dashboard Content:**
- Work Type Summary: All rows show "0 / 0 / 0 / No activity"
- Active Studies: "No studies active in date range"
- Timeline: "No activity to display"

**Pass Criteria:**
- No broken UI elements
- Clear messaging why no data shown
- No JavaScript null reference errors

## Gate 5: Documentation

### 5.1 README Updated

**Checklist:**
- [ ] "Generate Management Dashboard" section added
- [ ] Command example with actual TNSName/Schema/ProjectId
- [ ] Screenshot of dashboard (optional but recommended)
- [ ] Link to PHASE2_DASHBOARD_SPEC.md and PHASE2_ACCEPTANCE.md

**Pass Criteria:**
- New contributor can find dashboard instructions in <60 seconds
- Copy-paste command works without modification (except credentials)

### 5.2 PHASE2_DASHBOARD_SPEC.md Complete

**Checklist:**
- [ ] Purpose and scope defined
- [ ] All 6 dashboard views documented
- [ ] management.json schema fully specified
- [ ] Error handling rules documented
- [ ] Script interface contract provided

**Pass Criteria:**
- Specification document approved by PM/stakeholder
- No "TBD" or "TODO" placeholders

### 5.3 PHASE2_ACCEPTANCE.md Complete

**Checklist:**
- [ ] Performance targets defined
- [ ] Reliability gates specified
- [ ] Reproducibility tests documented
- [ ] Functional correctness tests listed

**Pass Criteria:**
- This document (you're reading it!)
- All gates measurable without ambiguity

## Gate 6: Code Quality

### 6.1 No Hardcoded Values

**Test:** Search codebase for project-specific strings

**Forbidden:**
```powershell
# BAD - hardcoded
$TNSName = "SIEMENS_PS_DB_DB01"
$Schema = "DESIGN12"
```

**Required:**
```powershell
# GOOD - parameterized
param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,
    [Parameter(Mandatory=$true)]
    [string]$Schema
)
```

**Pass Criteria:**
- No hardcoded TNSName, Schema, ProjectId in scripts
- All values passed via parameters

### 6.2 Error Handling Present

**Test:** Search for bare SQL execution without try/catch

**Required Pattern:**
```powershell
try {
    $result = Invoke-Sqlcmd -Query $query -ConnectionString $connString -ErrorAction Stop
} catch {
    Write-Error "Query failed: $_"
    # Handle error gracefully
}
```

**Pass Criteria:**
- All SQL queries wrapped in try/catch
- All file I/O wrapped in try/catch
- No `$ErrorActionPreference = "SilentlyContinue"` (hides errors)

### 6.3 Console Output Clarity

**Test:** Run script and review console output

**Required Elements:**
- Progress indicators: "Querying resource library... DONE"
- Timing information: "Completed in 12.3 seconds"
- Cache status: "Using cached data (expires in 8 minutes)"
- Final summary: "Dashboard generated: data\output\management-dashboard-DESIGN12-18140190.html"

**Pass Criteria:**
- User knows what script is doing at each step
- Success/failure clearly indicated
- Output file path displayed

## Final Acceptance Checklist

Before merging PR to main:

- [ ] Gate 1: Performance - All targets met
- [ ] Gate 2: Reliability - Zero crashes, degraded mode works
- [ ] Gate 3: Reproducibility - One-command execution confirmed
- [ ] Gate 4: Functional Correctness - Data accuracy verified
- [ ] Gate 5: Documentation - README, spec, and acceptance docs complete
- [ ] Gate 6: Code Quality - No hardcoded values, error handling present
- [ ] Verification script passes on test data
- [ ] PR reviewed by at least one other agent (Agent 02, 03, 04, or 05)
- [ ] No merge conflicts with main branch
- [ ] Git commit message follows format: "feat: add management dashboard (Phase 2)"

## Success Statement

When all gates pass:

> "A new contributor can read README.md, run one command, and produce a management dashboard artifact showing work activity across all 5 work types, with world location changes flagged, in under 60 seconds (first run) or 15 seconds (cached run), without encountering any hard crashes or unclear error messages."

---

**Document Status:** LOCKED - Definition of Done
**Last Updated:** 2026-01-22
**Owner:** Agent 01 (PM/Docs)
