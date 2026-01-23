# Phase 2 Backlog: 5-Agent Work Assignments

**Version:** 1.0
**Date:** 2026-01-23
**Status:** ACTIVE - Ready for Execution
**Branch:** main
**Target Delivery:** 2 weeks (10 business days)

---

## Executive Summary

Phase 2 (Management Dashboard) was successfully delivered on 2026-01-22. Latest bug fixes deployed on 2026-01-23 (commit 41e0944).

This document defines work assignments for 5 agents to implement the next priority features from the Phase 2 backlog, as identified in [CC_FEATURE_VALUE_REVIEW.md](CC_FEATURE_VALUE_REVIEW.md).

**Total Features:** 7 high-value enhancements
**Estimated Effort:** 7-9 days development + 2-3 days testing/integration
**Risk Level:** Low (all features use existing data, no architectural changes)

---

## Ground Rules for ALL Agents

### Branch Strategy
- **Source Branch:** `main` (latest commit: 41e0944)
- **Agent Branches:** `agent{N}-{feature-name}` (e.g., `agent01-study-health-tab`)
- **Merge Target:** `main`
- **PR Naming:** `feat: {feature description} (Agent {N})`

### Critical Requirements
1. **Work from main:** All agents branch from main, not from each other
2. **Create own branch:** Each agent creates their dedicated feature branch
3. **All tests must pass:** Unit tests + integration tests required before PR
4. **Merge to main:** All work merges back to main via Pull Request
5. **No breaking changes:** Do not modify Phase 1 or Phase 2 core functionality
6. **Data contract:** All JSON changes must be backward compatible

### Testing Requirements
- **Unit Tests:** PowerShell Pester tests for all new functions
- **Integration Tests:** End-to-end verification scripts
- **Test Data:** Use existing test fixtures in `test/fixtures/`
- **Coverage:** All error paths must be tested
- **Documentation:** Update relevant .md files

### Git Workflow
```powershell
# All agents follow this pattern:
git checkout main
git pull origin main
git checkout -b agent{N}-{feature-name}

# ... do work, commit frequently ...

# Before creating PR:
.\verify-management-dashboard.ps1 -Schema "DESIGN12" -ProjectId 18140190
# Ensure all tests pass

git push origin agent{N}-{feature-name}
# Create PR to main
```

---

## Agent 01: Study Health Integration Specialist

### Mission
Integrate existing [robcad-study-health.ps1](../scripts/robcad-study-health.ps1) into management dashboard as new tab.

### Branch Name
`agent01-study-health-tab`

### Features to Implement
1. **Unified Study Health Scorecard** (CC_FEATURE_VALUE_REVIEW.md #1)
2. **Technical Debt Dashboard Tab** (CC_FEATURE_VALUE_REVIEW.md #13)

### Deliverables

#### File 1: `src/powershell/main/get-study-health-data.ps1`
**Purpose:** Execute robcad-study-health.ps1 and export results to JSON

**Parameters:**
```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ProjectId,

    [string]$OutputPath = "data\output\study-health-{Schema}-{ProjectId}.json"
)
```

**Logic:**
1. Call `scripts\robcad-study-health.ps1` with same TNS/Schema/ProjectId
2. Parse outputs:
   - `out\robcad-study-health-report.md` → Extract summary stats
   - `out\robcad-study-health-issues.csv` → Parse Critical/High severity issues
   - `out\robcad-study-health-suspicious.csv` → Parse suspicious names
3. Output JSON:
```json
{
  "studyHealth": {
    "totalStudies": 42,
    "healthyStudies": 35,
    "warningStudies": 5,
    "criticalStudies": 2,
    "technicalDebt": [
      {
        "severity": "Critical",
        "study": "P702_8J_010",
        "issue": "Contains junk token: _OLD",
        "recommendation": "Rename to remove _OLD suffix"
      }
    ],
    "suspiciousNames": [
      {
        "study": "P702_8J_010_Copy",
        "reason": "Contains 'Copy' - likely unfinished work"
      }
    ]
  }
}
```

#### File 2: Update `scripts/generate-management-dashboard.ps1`
**Changes:**
1. Add new tab: "Study Health & Technical Debt"
2. Read `study-health-{Schema}-{ProjectId}.json`
3. Render 3 sub-views:
   - **Health Scorecard:** Pie chart (Healthy/Warning/Critical)
   - **Technical Debt List:** Sortable table from `technicalDebt` array
   - **Suspicious Names:** Sortable table from `suspiciousNames` array

**UI Requirements:**
- Color coding: Green (Healthy), Yellow (Warning), Red (Critical)
- Severity badges: 🔴 Critical, ⚠️ Warning
- Sortable columns: Severity, Study, Issue
- Search: Filter by study name or issue text

#### File 3: Update `management-dashboard-launcher.ps1`
**Changes:**
1. After data extraction, call `get-study-health-data.ps1`
2. Pass study health JSON to dashboard generator
3. Update console output:
   ```
   Study health analysis... DONE (3.2s)
   - 35 healthy, 5 warnings, 2 critical
   - 7 technical debt items flagged
   ```

### Unit Tests Required

**File:** `test/unit/Test-StudyHealthIntegration.ps1`

**Test Cases:**
1. `Should execute robcad-study-health.ps1 successfully`
2. `Should parse report.md and extract summary stats`
3. `Should parse issues.csv and convert to JSON`
4. `Should handle empty results (zero issues)`
5. `Should handle missing robcad-study-health.ps1 gracefully`
6. `Should cache study health data (15-min TTL)`

**Test Data:**
- Use existing `scripts/robcad-study-health.ps1` with DESIGN12
- Create sample outputs in `test/fixtures/study-health-sample-*.csv`

### Exit Criteria
- [ ] Study health JSON generated successfully
- [ ] Dashboard displays new "Study Health" tab
- [ ] Health scorecard shows correct counts (35/5/2)
- [ ] Technical debt table sortable and searchable
- [ ] Unit tests: 6/6 passing
- [ ] Integration test: `verify-management-dashboard.ps1` passes
- [ ] No JavaScript errors in browser console
- [ ] Documentation: Updated README.md with new tab description

### Time Estimate
**2-3 days** (1 day script, 1 day UI, 0.5 day testing)

---

## Agent 02: Search & Filter Specialist

### Mission
Add client-side search/filter functionality to management dashboard.

### Branch Name
`agent02-searchable-filters`

### Features to Implement
1. **Searchable Dashboard Filters** (CC_FEATURE_VALUE_REVIEW.md #14)

### Deliverables

#### File 1: Update `scripts/generate-management-dashboard.ps1`
**Changes:** Add search functionality to all tabular views

**New UI Elements:**
```html
<!-- Add to each table section -->
<div class="search-container">
  <input type="text" id="search-{section}"
         placeholder="Search {section}... (Ctrl+F)"
         class="search-input">
  <span class="search-results">0 of 0 results</span>
  <button class="clear-search">Clear</button>
</div>
```

**JavaScript Logic:**
```javascript
// Real-time search with debouncing (300ms)
function filterTable(tableId, searchText) {
  const rows = document.querySelectorAll(`#${tableId} tbody tr`);
  let visibleCount = 0;

  rows.forEach(row => {
    const text = row.textContent.toLowerCase();
    if (text.includes(searchText.toLowerCase())) {
      row.style.display = '';
      visibleCount++;
    } else {
      row.style.display = 'none';
    }
  });

  updateSearchResults(visibleCount, rows.length);
}
```

**Features to Add:**
1. **Global Search:** Searches all tables at once (Ctrl+Shift+F)
2. **Column-Specific Search:** Dropdown to select column
3. **Search Highlighting:** Yellow highlight on matched text
4. **Search History:** Remember last 5 searches (localStorage)
5. **Clear All Filters:** Button to reset all searches

#### File 2: Update CSS Styling
**Add to inline CSS in generate-management-dashboard.ps1:**
```css
.search-container {
  margin: 10px 0;
  display: flex;
  gap: 10px;
  align-items: center;
}

.search-input {
  flex: 1;
  padding: 8px 12px;
  border: 1px solid #ccc;
  border-radius: 4px;
  font-size: 14px;
}

.search-input:focus {
  outline: none;
  border-color: #007bff;
  box-shadow: 0 0 0 3px rgba(0,123,255,0.1);
}

.search-results {
  color: #666;
  font-size: 13px;
}

mark {
  background-color: #ffeb3b;
  padding: 2px 0;
}
```

### Unit Tests Required

**File:** `test/unit/Test-SearchFilters.ps1`

**Test Cases:**
1. `Should filter table rows by search text`
2. `Should update result count correctly`
3. `Should highlight matched text`
4. `Should clear search and show all rows`
5. `Should handle special characters in search`
6. `Should persist search history to localStorage`
7. `Should debounce search input (not search on every keystroke)`

**Test Method:**
- Use PowerShell to inject test data into HTML
- Use Node.js or Puppeteer for JavaScript testing (if available)
- Fallback: Manual browser testing with checklist

### Exit Criteria
- [ ] Search input appears on all 6 dashboard views
- [ ] Real-time filtering works (<300ms latency)
- [ ] Search results count updates correctly
- [ ] Highlight matched text works
- [ ] Clear button resets search
- [ ] Global search (Ctrl+Shift+F) functional
- [ ] Search history persists across page reloads
- [ ] Unit tests: 7/7 passing (or manual checklist complete)
- [ ] No JavaScript errors
- [ ] Documentation: Added "Search & Filter" section to README

### Time Estimate
**1-2 days** (0.5 day UI, 0.5 day JavaScript, 0.5-1 day testing)

---

## Agent 03: Resource Conflict & Checkout Tracking Specialist

### Mission
Detect resource conflicts and flag stale checkouts in management dashboard.

### Branch Name
`agent03-resource-conflicts`

### Features to Implement
1. **Resource Conflict Detection** (CC_FEATURE_VALUE_REVIEW.md #9)
2. **Stale Checkout Alerts** (CC_FEATURE_VALUE_REVIEW.md #2)
3. **Bottleneck Queue View** (CC_FEATURE_VALUE_REVIEW.md #7)

### Deliverables

#### File 1: Update `src/powershell/main/get-management-data.ps1`
**New Query:** Add resource conflict detection

**SQL Logic:**
```sql
-- Find resources used in multiple active studies
WITH ActiveResources AS (
  SELECT
    sl.RESOURCE_ID,
    r.NAME_S_ as resource_name,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    p.OWNER_ID as checked_out_by
  FROM DESIGN12.STUDYLAYOUT_ sl
  INNER JOIN DESIGN12.ROBCADSTUDY_ rs ON sl.STUDY_ID = rs.OBJECT_ID
  INNER JOIN DESIGN12.RESOURCE_ r ON sl.RESOURCE_ID = r.OBJECT_ID
  LEFT JOIN DESIGN12.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
  WHERE p.WORKING_VERSION_ID > 0  -- Active checkouts only
)
SELECT
  resource_name,
  COUNT(DISTINCT study_id) as study_count,
  STRING_AGG(study_name, ', ') as studies_using_resource
FROM ActiveResources
GROUP BY resource_name
HAVING COUNT(DISTINCT study_id) > 1
ORDER BY study_count DESC;
```

**Stale Checkout Detection:**
```sql
-- Find checkouts older than 3 days
SELECT
  rs.OBJECT_ID as study_id,
  rs.NAME_S_ as study_name,
  rs.MODIFICATIONDATE_DA_ as last_modified,
  u.CAPTION_S_ as checked_out_by,
  ROUND((SYSDATE - rs.MODIFICATIONDATE_DA_) * 24, 1) as checkout_duration_hours
FROM DESIGN12.ROBCADSTUDY_ rs
INNER JOIN DESIGN12.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN DESIGN12.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE p.WORKING_VERSION_ID > 0
  AND rs.MODIFICATIONDATE_DA_ < SYSDATE - 3
ORDER BY checkout_duration_hours DESC;
```

**JSON Output:**
```json
{
  "resourceConflicts": [
    {
      "resource": "8J-010_ROBOT_R1",
      "studyCount": 2,
      "studies": ["P702_8J_010", "P736_8J_010"],
      "riskLevel": "High"
    }
  ],
  "staleCheckouts": [
    {
      "study": "P702_8J_010",
      "user": "John Smith",
      "checkoutDuration": 76.5,
      "lastModified": "2026-01-20T08:15:00Z",
      "flagged": true
    }
  ]
}
```

#### File 2: Update `scripts/generate-management-dashboard.ps1`
**New Section:** "Resource Conflicts & Bottlenecks"

**UI Requirements:**
1. **Resource Conflict Table:**
   - Columns: Resource, # Studies, Studies Using, Risk Level
   - Color coding: Red (2+ studies), Yellow (potential conflict)
   - Icon: ⚠️ for conflicts

2. **Stale Checkouts Table:**
   - Columns: Study, User, Duration (hours), Last Modified, Action
   - Color coding: Red (>72 hours), Yellow (>48 hours)
   - Icon: 🚨 for >72 hours, ⏱️ for >48 hours
   - Action button: "Remind User" (opens email client)

3. **Bottleneck Queue View:**
   - Horizontal bar chart showing checkout duration by user
   - Sorted by longest checkout first
   - Tooltip: Study name + duration

#### File 3: Email Template Helper
**File:** `src/powershell/utilities/Send-StaleCheckoutReminder.ps1`

**Purpose:** Generate email reminder for stale checkouts

```powershell
param(
    [string]$UserEmail,
    [string]$StudyName,
    [double]$DurationHours
)

$subject = "Reminder: Long-running checkout - $StudyName"
$body = @"
Hi,

You've had the following study checked out for $DurationHours hours:
- Study: $StudyName

If you're finished, please check it in to allow others to work.

If you're still working, please ignore this message.

Thanks!
SimTreeNav Bot
"@

Start-Process "mailto:$UserEmail?subject=$subject&body=$body"
```

### Unit Tests Required

**File:** `test/unit/Test-ResourceConflicts.ps1`

**Test Cases:**
1. `Should detect resource used in 2+ studies`
2. `Should flag checkouts >72 hours as stale`
3. `Should calculate checkout duration correctly`
4. `Should handle zero conflicts gracefully`
5. `Should generate email reminder with correct data`
6. `Should sort bottleneck queue by duration descending`

### Exit Criteria
- [ ] Resource conflict query returns correct data
- [ ] Stale checkout detection works (>3 days threshold)
- [ ] Bottleneck queue view displays correctly
- [ ] Color coding applied (red/yellow)
- [ ] Email reminder template works
- [ ] Unit tests: 6/6 passing
- [ ] Integration test passes
- [ ] Documentation updated

### Time Estimate
**2-3 days** (1 day SQL, 1 day UI, 0.5-1 day testing)

---

## Agent 04: High Churn Risk Detection Specialist

### Mission
Identify studies with high modification frequency (potential instability).

### Branch Name
`agent04-churn-risk-flags`

### Features to Implement
1. **High Churn Risk Flags** (CC_FEATURE_VALUE_REVIEW.md #11)

### Deliverables

#### File 1: `src/powershell/main/get-churn-risk-data.ps1`
**Purpose:** Analyze modification frequency and flag high-churn studies

**Parameters:**
```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$TNSName,

    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ProjectId,

    [int]$DaysBack = 7,
    [int]$ChurnThreshold = 10  # Modifications per week
)
```

**SQL Logic:**
```sql
-- Count distinct modification events per study
WITH ModificationCounts AS (
  SELECT
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    COUNT(DISTINCT DATE_TRUNC('day', rs.MODIFICATIONDATE_DA_)) as mod_days,
    COUNT(*) as total_mods,
    MAX(rs.MODIFICATIONDATE_DA_) as last_modified,
    STRING_AGG(DISTINCT rs.LASTMODIFIEDBY_S_, ', ') as modified_by_users
  FROM DESIGN12.ROBCADSTUDY_ rs
  WHERE rs.MODIFICATIONDATE_DA_ > SYSDATE - 7
  GROUP BY rs.OBJECT_ID, rs.NAME_S_
)
SELECT
  study_id,
  study_name,
  total_mods,
  mod_days,
  last_modified,
  modified_by_users,
  CASE
    WHEN total_mods >= 20 THEN 'Critical'
    WHEN total_mods >= 10 THEN 'High'
    WHEN total_mods >= 5 THEN 'Medium'
    ELSE 'Low'
  END as churn_risk_level
FROM ModificationCounts
WHERE total_mods >= 5
ORDER BY total_mods DESC;
```

**JSON Output:**
```json
{
  "churnRisks": [
    {
      "study": "P702_8J_010",
      "modificationCount": 15,
      "modificationDays": 5,
      "lastModified": "2026-01-23T10:30:00Z",
      "modifiedBy": ["John Smith", "Jane Doe"],
      "riskLevel": "High",
      "recommendation": "Review for stability issues"
    }
  ]
}
```

#### File 2: Extend `scripts/robcad-study-health.ps1`
**New Check:** Add churn risk detection to existing health script

**Changes:**
1. Add churn risk calculation (already has modification dates)
2. Flag studies with >10 modifications in 7 days
3. Output to new CSV: `out/robcad-study-health-churn-risk.csv`

**Columns:**
- Study Name
- Modification Count (7 days)
- Risk Level (Critical/High/Medium)
- Modified By (users)
- Recommendation

#### File 3: Update `scripts/generate-management-dashboard.ps1`
**New Section:** "High Churn Risk Studies"

**UI Requirements:**
1. **Risk Level Badges:**
   - 🔴 Critical (≥20 mods/week)
   - 🟠 High (10-19 mods/week)
   - 🟡 Medium (5-9 mods/week)

2. **Churn Risk Table:**
   - Columns: Study, Mods (7 days), Risk Level, Modified By, Action
   - Sortable by modification count (default: highest first)
   - Action: "View Details" (expands to show daily breakdown)

3. **Daily Breakdown (expandable):**
   ```
   Mon: 3 mods
   Tue: 2 mods
   Wed: 5 mods (spike!)
   Thu: 1 mod
   Fri: 4 mods
   ```

4. **Recommendation Tooltip:**
   - Hover over risk badge to see recommendation
   - Example: "15 modifications in 5 days suggests active development. Review for stability before release."

### Unit Tests Required

**File:** `test/unit/Test-ChurnRiskDetection.ps1`

**Test Cases:**
1. `Should count modifications correctly over 7-day window`
2. `Should classify churn risk levels (Critical/High/Medium/Low)`
3. `Should handle studies with zero modifications`
4. `Should aggregate multiple users modifying same study`
5. `Should generate daily breakdown correctly`
6. `Should cache churn risk data (15-min TTL)`

### Exit Criteria
- [ ] Churn risk SQL query returns correct counts
- [ ] Risk level classification correct (Critical/High/Medium)
- [ ] Dashboard displays churn risk table
- [ ] Risk badges color-coded correctly
- [ ] Daily breakdown expands on click
- [ ] Recommendation tooltips display
- [ ] Unit tests: 6/6 passing
- [ ] Integration test passes
- [ ] Documentation updated (README + robcad-study-health docs)

### Time Estimate
**1-2 days** (0.5 day SQL, 0.5 day UI, 0.5 day testing)

---

## Agent 05: Integration, Testing & Documentation Lead

### Mission
Integrate all agent work, ensure all tests pass, and prepare final PR to main.

### Branch Name
`agent05-integration-testing`

### Responsibilities

#### Phase 1: Pre-Integration Validation (Days 1-2)
**Before agents start coding:**
1. Create test fixtures for all agents
   - Sample JSON data for study health
   - Sample CSV data for conflicts/checkouts
   - Sample SQL results for churn risk
2. Create integration test script: `test/integration/Test-Phase2Backlog.ps1`
3. Define acceptance criteria checklist

#### Phase 2: Agent Monitoring (Days 3-7)
**While agents work:**
1. Review each agent's commits daily
2. Run preliminary tests on agent branches
3. Identify merge conflicts early
4. Maintain `docs/PHASE2_BACKLOG_STATUS.md` (progress tracker)

#### Phase 3: Integration (Days 8-9)
**When all agents complete:**
1. Merge all agent branches to `agent05-integration-testing` branch
2. Resolve any merge conflicts
3. Run full integration test suite:
   - All unit tests from Agents 01-04
   - End-to-end dashboard generation test
   - Performance test (ensure <60s first run, <15s cached)
   - Browser compatibility test (Edge, Chrome, Firefox)
4. Update `verify-management-dashboard.ps1` to include new features

#### Phase 4: Final Testing & Documentation (Day 10)
1. **Smoke Test:**
   - Generate dashboard on DESIGN12, ProjectId 18140190
   - Verify all 7 new features functional
   - Check browser console for errors
   - Verify search performance (<300ms)

2. **Documentation Updates:**
   - Update `README.md` with new features
   - Update `STATUS.md` with completion status
   - Update `docs/PHASE2_DASHBOARD_SPEC.md` with new views
   - Create `docs/PHASE2_BACKLOG_RELEASE_NOTES.md`

3. **Performance Validation:**
   - Dashboard generation time: <60s first run, <15s cached
   - Browser load time: <5s
   - Search filter latency: <300ms
   - File size: <12 MB (was 8.2 MB, now with more features)

4. **Create Final PR:**
   - Title: `feat: Phase 2 backlog - 7 dashboard enhancements (Agents 01-05)`
   - Description: Full feature list, testing summary, acceptance gates
   - Reviewers: Assign to project maintainer

### Deliverables

#### File 1: `test/integration/Test-Phase2Backlog.ps1`
**Integration Test Suite**

```powershell
<#
.SYNOPSIS
Integration tests for Phase 2 backlog features (7 enhancements)

.DESCRIPTION
Validates:
- Study health integration (Agent 01)
- Search/filter functionality (Agent 02)
- Resource conflict detection (Agent 03)
- Churn risk detection (Agent 04)
- All features work together without conflicts
#>

Describe "Phase 2 Backlog Integration Tests" {

  Context "Agent 01: Study Health" {
    It "Should generate study health JSON" {
      # Test get-study-health-data.ps1
    }

    It "Should display study health tab in dashboard" {
      # Test HTML contains study health section
    }

    It "Should show technical debt items" {
      # Verify technical debt table renders
    }
  }

  Context "Agent 02: Search & Filters" {
    It "Should filter tables by search text" {
      # Test JavaScript filtering
    }

    It "Should update result counts" {
      # Verify "X of Y results" text
    }

    It "Should clear search filters" {
      # Test clear button
    }
  }

  Context "Agent 03: Resource Conflicts" {
    It "Should detect resource conflicts" {
      # Verify conflict detection query
    }

    It "Should flag stale checkouts >72 hours" {
      # Verify stale checkout logic
    }

    It "Should display bottleneck queue" {
      # Verify bar chart renders
    }
  }

  Context "Agent 04: Churn Risk" {
    It "Should calculate modification counts" {
      # Verify churn risk SQL
    }

    It "Should classify risk levels correctly" {
      # Test Critical/High/Medium/Low thresholds
    }

    It "Should display risk badges" {
      # Verify color coding
    }
  }

  Context "End-to-End Integration" {
    It "Should generate complete dashboard with all features" {
      # Run full workflow: data extraction → dashboard generation
    }

    It "Should complete in <60 seconds (first run)" {
      # Performance test
    }

    It "Should complete in <15 seconds (cached)" {
      # Cached performance test
    }

    It "Should load in browser <5 seconds" {
      # Browser performance test
    }
  }
}
```

#### File 2: `docs/PHASE2_BACKLOG_RELEASE_NOTES.md`
**Release Notes**

```markdown
# Phase 2 Backlog: Release Notes

**Version:** 2.1.0
**Release Date:** 2026-02-06 (estimated)
**Agents:** 01-05
**Features Added:** 7

## New Features

### 1. Study Health & Technical Debt Tab (Agent 01)
- Integrated robcad-study-health.ps1 into dashboard
- Health scorecard with pie chart (Healthy/Warning/Critical)
- Technical debt table with severity rankings
- Suspicious name detection

### 2. Searchable Dashboard Filters (Agent 02)
- Real-time search across all tables (<300ms latency)
- Global search (Ctrl+Shift+F)
- Search highlighting with yellow background
- Search history (last 5 searches persist)
- Column-specific filtering

### 3. Resource Conflict Detection (Agent 03)
- Identifies resources used in 2+ active studies
- Color-coded risk levels (Red: conflict, Yellow: potential)
- Conflict resolution recommendations

### 4. Stale Checkout Alerts (Agent 03)
- Flags checkouts >72 hours (red) and >48 hours (yellow)
- Shows checkout duration in hours
- Email reminder template for users

### 5. Bottleneck Queue View (Agent 03)
- Horizontal bar chart of checkout durations by user
- Sorted by longest checkout first
- Identifies project bottlenecks

### 6. High Churn Risk Detection (Agent 04)
- Tracks studies modified >10 times in 7 days
- Risk level classification (Critical/High/Medium)
- Daily modification breakdown
- Stability recommendations

### 7. Enhanced Study Health Linting (Agent 04)
- Churn risk detection added to robcad-study-health.ps1
- New CSV output: robcad-study-health-churn-risk.csv

## Performance

- Dashboard generation: 22-28s first run, 10-12s cached
- Browser load time: 3-4s
- Search latency: <300ms
- File size: 10.5 MB

## Testing

- Unit tests: 25 tests added (all passing)
- Integration tests: 10 scenarios (all passing)
- Browser compatibility: Edge, Chrome, Firefox (verified)

## Breaking Changes

None. All changes backward compatible with Phase 2 (v2.0).

## Migration Guide

No migration needed. Run dashboard launcher as before:

\`\`\`powershell
.\management-dashboard-launcher.ps1 -TNSName "..." -Schema "DESIGN12" -ProjectId 18140190
\`\`\`

New features automatically appear in dashboard.

## Known Issues

None.

## Contributors

- Agent 01: Study Health Integration
- Agent 02: Search & Filters
- Agent 03: Resource Conflicts & Checkouts
- Agent 04: Churn Risk Detection
- Agent 05: Integration & Testing
```

#### File 3: Update `verify-management-dashboard.ps1`
**New Checks:**
```powershell
# Add to existing verification script
Write-Host "Checking Phase 2 backlog features..." -ForegroundColor Cyan

# Check 1: Study health tab exists
if ($htmlContent -match 'study-health-tab') {
  Write-Host "PASS: Study health tab found" -ForegroundColor Green
} else {
  Write-Host "FAIL: Study health tab missing" -ForegroundColor Red
}

# Check 2: Search inputs present
$searchInputCount = ([regex]::Matches($htmlContent, 'class="search-input"')).Count
if ($searchInputCount -ge 6) {
  Write-Host "PASS: Search inputs found ($searchInputCount)" -ForegroundColor Green
} else {
  Write-Host "FAIL: Search inputs missing (found $searchInputCount, expected 6+)" -ForegroundColor Red
}

# Check 3: Resource conflict section exists
if ($htmlContent -match 'resource-conflicts') {
  Write-Host "PASS: Resource conflict section found" -ForegroundColor Green
} else {
  Write-Host "FAIL: Resource conflict section missing" -ForegroundColor Red
}

# Check 4: Churn risk section exists
if ($htmlContent -match 'churn-risk') {
  Write-Host "PASS: Churn risk section found" -ForegroundColor Green
} else {
  Write-Host "FAIL: Churn risk section missing" -ForegroundColor Red
}
```

### Exit Criteria
- [ ] All agent branches merged to `agent05-integration-testing`
- [ ] All merge conflicts resolved
- [ ] Unit tests: 25+ tests, all passing
- [ ] Integration tests: 10+ scenarios, all passing
- [ ] Performance validated (generation <60s first, <15s cached, browser <5s)
- [ ] Browser compatibility verified (Edge, Chrome, Firefox)
- [ ] Documentation updated (README, STATUS, release notes)
- [ ] `verify-management-dashboard.ps1` extended with new checks
- [ ] Final PR created to main
- [ ] PR description complete with feature list, testing summary
- [ ] All acceptance gates from PHASE2_ACCEPTANCE.md still passing

### Time Estimate
**3-4 days** (1 day setup, 1 day monitoring, 1-2 days integration/testing)

---

## Inter-Agent Dependencies

### Parallel Work (No Dependencies)
These agents can work simultaneously:
- **Agent 01** (Study Health) - Independent
- **Agent 02** (Search/Filters) - Independent
- **Agent 04** (Churn Risk) - Independent

### Sequential Dependency
- **Agent 03** (Resource Conflicts) - Must wait for Agent 01's JSON schema stabilization
- **Agent 05** (Integration) - Must wait for all agents (01-04) to complete

### Recommended Schedule

```
Week 1 (Days 1-5):
  Day 1: Agent 05 creates test fixtures + integration test framework
  Days 2-4: Agents 01, 02, 04 work in parallel
  Day 5: Agent 03 starts (after Agent 01 schema finalized)

Week 2 (Days 6-10):
  Days 6-7: Agent 03 completes, all agents finalize
  Days 8-9: Agent 05 integrates all branches, runs full test suite
  Day 10: Agent 05 creates PR, final review
```

---

## Success Criteria (Phase 2 Backlog Complete)

When Agent 05 merges final PR to main:

> "A user can generate a management dashboard that includes:
> 1. Study health scorecard with technical debt tracking
> 2. Real-time search/filter across all tables
> 3. Resource conflict detection with risk flagging
> 4. Stale checkout alerts (>72 hours)
> 5. Bottleneck queue visualization
> 6. High churn risk detection (>10 mods/week)
> 7. All features load in <5 seconds, search responds in <300ms, and all unit tests pass."

**Verified by:**
- Running `verify-management-dashboard.ps1` → `OVERALL: PASS (10/10 checks)`
- Running `test/integration/Test-Phase2Backlog.ps1` → `All tests passed`
- Browser console: Zero JavaScript errors
- Performance: Generation <60s first, <15s cached, browser <5s

---

## Communication Protocol

### Daily Standups (Async)
Each agent posts to `docs/PHASE2_BACKLOG_STATUS.md`:

```markdown
## Agent {N} - {Date}

**Progress:**
- [x] Completed: {task}
- [ ] In Progress: {task}
- [ ] Blocked: {task + reason}

**Questions/Blockers:**
- {issue description}

**Next Steps:**
- {tomorrow's plan}
```

### Handoff Messages
When agent completes work:

```markdown
## Handoff: Agent {N} → Agent 05

**Date:** {ISO date}
**Branch:** agent{N}-{feature}
**Commits:** {count} commits, {files changed} files
**Tests:** {X}/{Y} passing

**Deliverables:**
- {file path} - {description}

**Known Issues:**
- {issue + workaround if applicable}

**Integration Notes:**
- {special instructions for Agent 05}

**Ready for Integration:** YES / NO
```

### Blocking Issues
If agent encounters blocker:
1. Post to `docs/PHASE2_BACKLOG_STATUS.md` under "Blockers"
2. Tag @Agent05 for escalation
3. Propose solution or request user input
4. Do NOT proceed with assumptions

---

## Git Commit Message Format

All agents follow this format:

```
<type>(<scope>): <subject>

<body>

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `test`: Add tests
- `docs`: Documentation update
- `refactor`: Code refactoring (no behavior change)
- `perf`: Performance improvement

**Scopes:**
- `study-health`: Agent 01 work
- `search`: Agent 02 work
- `conflicts`: Agent 03 work
- `churn-risk`: Agent 04 work
- `integration`: Agent 05 work

**Examples:**
```
feat(study-health): add study health tab to dashboard

- Integrate robcad-study-health.ps1 output
- Add health scorecard with pie chart
- Display technical debt table

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

```
test(search): add unit tests for search filtering

- Test real-time filtering logic
- Test result count updates
- Test clear search functionality

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## Final Checklist (Agent 05 - Before PR to Main)

- [ ] All agent branches merged to agent05-integration-testing
- [ ] No merge conflicts
- [ ] All unit tests passing (25+ tests)
- [ ] All integration tests passing (10+ scenarios)
- [ ] `verify-management-dashboard.ps1` passing (10/10 checks)
- [ ] Performance validated:
  - [ ] Generation <60s first run
  - [ ] Generation <15s cached
  - [ ] Browser load <5s
  - [ ] Search latency <300ms
- [ ] Browser compatibility:
  - [ ] Edge (tested)
  - [ ] Chrome (tested)
  - [ ] Firefox (tested)
- [ ] Documentation updated:
  - [ ] README.md (new features)
  - [ ] STATUS.md (completion status)
  - [ ] PHASE2_BACKLOG_RELEASE_NOTES.md (created)
  - [ ] PHASE2_DASHBOARD_SPEC.md (updated schema)
- [ ] Zero JavaScript errors in browser console
- [ ] File size acceptable (<12 MB)
- [ ] All original Phase 2 features still working
- [ ] PR description complete with:
  - [ ] Feature list (7 items)
  - [ ] Testing summary
  - [ ] Performance metrics
  - [ ] Breaking changes (none expected)
  - [ ] Migration guide (not needed)

---

**Document Status:** ACTIVE - Ready for Agent Execution
**Last Updated:** 2026-01-23
**Owner:** Project Lead
**Review Date:** 2026-02-06 (after completion)
