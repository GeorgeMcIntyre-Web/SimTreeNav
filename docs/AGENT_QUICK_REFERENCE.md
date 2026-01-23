# Agent Quick Reference Cards

**Project:** SimTreeNav Phase 2 Backlog
**Date:** 2026-01-23

---

## 🔵 AGENT 01: Study Health Integration Specialist

### Your Mission
Integrate robcad-study-health.ps1 into management dashboard as new tab.

### Your Branch
```powershell
git checkout main
git pull origin main
git checkout -b agent01-study-health-tab
```

### Files You'll Create/Modify
1. **CREATE:** `src/powershell/main/get-study-health-data.ps1`
2. **MODIFY:** `scripts/generate-management-dashboard.ps1` (add Study Health tab)
3. **MODIFY:** `management-dashboard-launcher.ps1` (call study health script)
4. **CREATE:** `test/unit/Test-StudyHealthIntegration.ps1` (6 tests)

### Key Requirements
- Execute `scripts/robcad-study-health.ps1`
- Parse outputs: report.md, issues.csv, suspicious.csv
- Output JSON: `study-health-{Schema}-{ProjectId}.json`
- Add new tab to dashboard with 3 views:
  - Health Scorecard (pie chart)
  - Technical Debt Table (sortable)
  - Suspicious Names Table (sortable)

### Tests You Must Write
1. Should execute robcad-study-health.ps1 successfully
2. Should parse report.md and extract summary stats
3. Should parse issues.csv and convert to JSON
4. Should handle empty results (zero issues)
5. Should handle missing robcad-study-health.ps1 gracefully
6. Should cache study health data (15-min TTL)

### Exit Criteria Checklist
- [ ] Study health JSON generated successfully
- [ ] Dashboard displays new "Study Health" tab
- [ ] Health scorecard shows correct counts
- [ ] Technical debt table sortable and searchable
- [ ] Unit tests: 6/6 passing
- [ ] Integration test passes
- [ ] No JavaScript errors
- [ ] README.md updated

### Time Estimate: 2-3 days

### Your Handoff Message Template
```markdown
## Handoff: Agent 01 → Agent 05

**Date:** {date}
**Branch:** agent01-study-health-tab
**Commits:** {count} commits, {files} files changed
**Tests:** 6/6 passing

**Deliverables:**
- src/powershell/main/get-study-health-data.ps1
- Updated scripts/generate-management-dashboard.ps1
- Updated management-dashboard-launcher.ps1
- test/unit/Test-StudyHealthIntegration.ps1

**Integration Notes:**
- Study health JSON schema: {describe schema}
- Cache TTL: 15 minutes
- Depends on robcad-study-health.ps1 existing

**Ready for Integration:** YES
```

---

## 🟢 AGENT 02: Search & Filter Specialist

### Your Mission
Add client-side search/filter functionality to all dashboard tables.

### Your Branch
```powershell
git checkout main
git pull origin main
git checkout -b agent02-searchable-filters
```

### Files You'll Create/Modify
1. **MODIFY:** `scripts/generate-management-dashboard.ps1` (add search UI + JavaScript)
2. **CREATE:** `test/unit/Test-SearchFilters.ps1` (7 tests)

### Key Requirements
- Add search input to all 6 dashboard views
- Real-time filtering with debouncing (300ms)
- Search highlighting (yellow background)
- Global search (Ctrl+Shift+F)
- Search history (localStorage, last 5 searches)
- Result count display ("X of Y results")
- Clear button

### JavaScript Functions You'll Add
```javascript
function filterTable(tableId, searchText) { ... }
function highlightMatches(text, searchText) { ... }
function updateSearchResults(visible, total) { ... }
function clearSearch(tableId) { ... }
function globalSearch(searchText) { ... }
```

### CSS Classes You'll Add
```css
.search-container { ... }
.search-input { ... }
.search-results { ... }
.clear-search { ... }
mark { ... }  /* Highlight matched text */
```

### Tests You Must Write
1. Should filter table rows by search text
2. Should update result count correctly
3. Should highlight matched text
4. Should clear search and show all rows
5. Should handle special characters in search
6. Should persist search history to localStorage
7. Should debounce search input (not search on every keystroke)

### Exit Criteria Checklist
- [ ] Search input appears on all 6 dashboard views
- [ ] Real-time filtering works (<300ms latency)
- [ ] Search results count updates correctly
- [ ] Highlight matched text works
- [ ] Clear button resets search
- [ ] Global search (Ctrl+Shift+F) functional
- [ ] Search history persists
- [ ] Unit tests: 7/7 passing
- [ ] No JavaScript errors
- [ ] README.md updated

### Time Estimate: 1-2 days

### Your Handoff Message Template
```markdown
## Handoff: Agent 02 → Agent 05

**Date:** {date}
**Branch:** agent02-searchable-filters
**Commits:** {count} commits, {files} files changed
**Tests:** 7/7 passing

**Deliverables:**
- Updated scripts/generate-management-dashboard.ps1
- test/unit/Test-SearchFilters.ps1

**Integration Notes:**
- Search latency: <300ms
- Global search: Ctrl+Shift+F
- Search history stored in localStorage
- No external dependencies

**Ready for Integration:** YES
```

---

## 🟠 AGENT 03: Resource Conflict & Checkout Tracking Specialist

### Your Mission
Detect resource conflicts, flag stale checkouts, and visualize bottlenecks.

### Your Branch
```powershell
git checkout main
git pull origin main
# Wait for Agent 01 to finalize JSON schema first!
git checkout -b agent03-resource-conflicts
```

### Files You'll Create/Modify
1. **MODIFY:** `src/powershell/main/get-management-data.ps1` (add conflict queries)
2. **MODIFY:** `scripts/generate-management-dashboard.ps1` (add conflict views)
3. **CREATE:** `src/powershell/utilities/Send-StaleCheckoutReminder.ps1`
4. **CREATE:** `test/unit/Test-ResourceConflicts.ps1` (6 tests)

### Key Requirements
- SQL query: Detect resources used in 2+ active studies
- SQL query: Find checkouts >72 hours old
- Add "Resource Conflicts & Bottlenecks" section to dashboard
- 3 views:
  - Resource Conflict Table (resource, # studies, risk level)
  - Stale Checkouts Table (study, user, duration, last modified)
  - Bottleneck Queue (horizontal bar chart by user)
- Color coding: Red (conflict/stale >72h), Yellow (potential/stale >48h)
- Email reminder template for stale checkouts

### SQL Queries You'll Write
```sql
-- Resource conflicts
SELECT resource_name, COUNT(DISTINCT study_id) as study_count, ...
FROM ... GROUP BY resource_name HAVING COUNT(...) > 1;

-- Stale checkouts
SELECT study_name, user_name, checkout_duration_hours, ...
FROM ... WHERE checkout_duration > 72;
```

### JSON Schema You'll Add
```json
{
  "resourceConflicts": [...],
  "staleCheckouts": [...]
}
```

### Tests You Must Write
1. Should detect resource used in 2+ studies
2. Should flag checkouts >72 hours as stale
3. Should calculate checkout duration correctly
4. Should handle zero conflicts gracefully
5. Should generate email reminder with correct data
6. Should sort bottleneck queue by duration descending

### Exit Criteria Checklist
- [ ] Resource conflict query returns correct data
- [ ] Stale checkout detection works (>3 days threshold)
- [ ] Bottleneck queue view displays correctly
- [ ] Color coding applied (red/yellow)
- [ ] Email reminder template works
- [ ] Unit tests: 6/6 passing
- [ ] Integration test passes
- [ ] README.md updated

### Time Estimate: 2-3 days

### Your Handoff Message Template
```markdown
## Handoff: Agent 03 → Agent 05

**Date:** {date}
**Branch:** agent03-resource-conflicts
**Commits:** {count} commits, {files} files changed
**Tests:** 6/6 passing

**Deliverables:**
- Updated src/powershell/main/get-management-data.ps1
- Updated scripts/generate-management-dashboard.ps1
- src/powershell/utilities/Send-StaleCheckoutReminder.ps1
- test/unit/Test-ResourceConflicts.ps1

**Integration Notes:**
- Stale checkout threshold: 72 hours (configurable)
- Email reminder uses mailto: protocol
- Resource conflict risk levels: High (2+ studies), Medium (potential)

**Ready for Integration:** YES
```

---

## 🟡 AGENT 04: High Churn Risk Detection Specialist

### Your Mission
Identify studies with high modification frequency (potential instability).

### Your Branch
```powershell
git checkout main
git pull origin main
git checkout -b agent04-churn-risk-flags
```

### Files You'll Create/Modify
1. **CREATE:** `src/powershell/main/get-churn-risk-data.ps1`
2. **MODIFY:** `scripts/robcad-study-health.ps1` (add churn risk check)
3. **MODIFY:** `scripts/generate-management-dashboard.ps1` (add churn risk view)
4. **CREATE:** `test/unit/Test-ChurnRiskDetection.ps1` (6 tests)

### Key Requirements
- SQL query: Count modifications per study in last 7 days
- Risk classification:
  - Critical: ≥20 mods/week
  - High: 10-19 mods/week
  - Medium: 5-9 mods/week
  - Low: <5 mods/week
- Add "High Churn Risk Studies" section to dashboard
- Risk level badges with color coding
- Daily modification breakdown (expandable)
- Recommendation tooltips

### SQL Query You'll Write
```sql
SELECT study_name, COUNT(*) as total_mods,
       COUNT(DISTINCT DATE_TRUNC('day', mod_date)) as mod_days, ...
FROM ... WHERE mod_date > SYSDATE - 7
GROUP BY study_name HAVING COUNT(*) >= 5
ORDER BY total_mods DESC;
```

### JSON Schema You'll Add
```json
{
  "churnRisks": [
    {
      "study": "...",
      "modificationCount": 15,
      "modificationDays": 5,
      "riskLevel": "High",
      "modifiedBy": ["user1", "user2"],
      "dailyBreakdown": {"Mon": 3, "Tue": 2, ...}
    }
  ]
}
```

### Tests You Must Write
1. Should count modifications correctly over 7-day window
2. Should classify churn risk levels (Critical/High/Medium/Low)
3. Should handle studies with zero modifications
4. Should aggregate multiple users modifying same study
5. Should generate daily breakdown correctly
6. Should cache churn risk data (15-min TTL)

### Exit Criteria Checklist
- [ ] Churn risk SQL query returns correct counts
- [ ] Risk level classification correct
- [ ] Dashboard displays churn risk table
- [ ] Risk badges color-coded correctly
- [ ] Daily breakdown expands on click
- [ ] Recommendation tooltips display
- [ ] Unit tests: 6/6 passing
- [ ] Integration test passes
- [ ] README.md + robcad-study-health docs updated

### Time Estimate: 1-2 days

### Your Handoff Message Template
```markdown
## Handoff: Agent 04 → Agent 05

**Date:** {date}
**Branch:** agent04-churn-risk-flags
**Commits:** {count} commits, {files} files changed
**Tests:** 6/6 passing

**Deliverables:**
- src/powershell/main/get-churn-risk-data.ps1
- Updated scripts/robcad-study-health.ps1
- Updated scripts/generate-management-dashboard.ps1
- test/unit/Test-ChurnRiskDetection.ps1

**Integration Notes:**
- Churn threshold: 10 mods/week (configurable)
- Risk levels: Critical (≥20), High (10-19), Medium (5-9)
- Cache TTL: 15 minutes

**Ready for Integration:** YES
```

---

## 🔴 AGENT 05: Integration, Testing & Documentation Lead

### Your Mission
Integrate all agent work, ensure all tests pass, and create final PR to main.

### Your Branch
```powershell
git checkout main
git pull origin main
git checkout -b agent05-integration-testing
```

### Your Phases

#### Phase 1: Setup (Days 1-2)
**Tasks:**
- [ ] Create test fixtures for all agents
- [ ] Create `test/integration/Test-Phase2Backlog.ps1`
- [ ] Define acceptance criteria checklist
- [ ] Set up daily monitoring process

#### Phase 2: Monitoring (Days 3-7)
**Tasks:**
- [ ] Review each agent's commits daily
- [ ] Run preliminary tests on agent branches
- [ ] Identify merge conflicts early
- [ ] Update PHASE2_BACKLOG_STATUS.md daily

#### Phase 3: Integration (Days 8-9)
**Tasks:**
- [ ] Merge all agent branches to agent05-integration-testing
- [ ] Resolve merge conflicts
- [ ] Run full integration test suite
- [ ] Update verify-management-dashboard.ps1

#### Phase 4: Final Testing & PR (Day 10)
**Tasks:**
- [ ] Run smoke test on DESIGN12 ProjectId 18140190
- [ ] Update documentation (README, STATUS, release notes)
- [ ] Validate performance (<60s first, <15s cached, browser <5s)
- [ ] Test browser compatibility (Edge, Chrome, Firefox)
- [ ] Create PR to main

### Files You'll Create/Modify
1. **CREATE:** `test/integration/Test-Phase2Backlog.ps1` (10+ scenarios)
2. **CREATE:** `docs/PHASE2_BACKLOG_RELEASE_NOTES.md`
3. **MODIFY:** `verify-management-dashboard.ps1` (add 4 new checks)
4. **MODIFY:** `README.md` (document all 7 new features)
5. **MODIFY:** `STATUS.md` (update completion status)
6. **CREATE:** `test/fixtures/study-health-sample.json` (for Agent 01)
7. **CREATE:** `test/fixtures/churn-risk-sample.json` (for Agent 04)

### Integration Test Scenarios
1. Study health tab renders
2. Search filters work
3. Resource conflicts detected
4. Churn risk calculated
5. All features integrated
6. Performance <60s first run
7. Performance <15s cached
8. Browser load <5s
9. Search latency <300ms
10. Zero JavaScript errors

### Final PR Checklist
- [ ] All agent branches merged
- [ ] No merge conflicts
- [ ] Unit tests: 25+ passing
- [ ] Integration tests: 10+ passing
- [ ] verify-management-dashboard.ps1: 10/10 checks passing
- [ ] Performance validated
- [ ] Browser compatibility tested
- [ ] Documentation updated
- [ ] Zero JavaScript errors
- [ ] File size <12 MB
- [ ] All original Phase 2 features working

### Time Estimate: 3-4 days

### Your Final PR Template
```markdown
# Phase 2 Backlog: 7 Dashboard Enhancements (Agents 01-05)

## Summary
Implements 7 high-value enhancements to management dashboard per CC_FEATURE_VALUE_REVIEW.md.

## Features Added
1. Study Health & Technical Debt Tab (Agent 01)
2. Searchable Dashboard Filters (Agent 02)
3. Resource Conflict Detection (Agent 03)
4. Stale Checkout Alerts (Agent 03)
5. Bottleneck Queue View (Agent 03)
6. High Churn Risk Detection (Agent 04)
7. Enhanced Study Health Linting (Agent 04)

## Testing Summary
- Unit tests: 25/25 passing
- Integration tests: 10/10 passing
- Performance: Generation 25s first, 12s cached, browser 4s
- Browser compatibility: Edge, Chrome, Firefox ✅
- Zero JavaScript errors ✅

## Files Changed
{list files}

## Breaking Changes
None. All changes backward compatible.

## Migration Guide
No migration needed. Run dashboard launcher as before.

## Reviewers
@maintainer
```

---

## 📋 Common Commands (All Agents)

### Create Your Branch
```powershell
git checkout main
git pull origin main
git checkout -b agent{N}-{feature-name}
```

### Daily Commit Pattern
```powershell
git add .
git commit -m "feat(scope): description

Detailed description

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
git push origin agent{N}-{feature-name}
```

### Run Tests
```powershell
# Your unit tests
Invoke-Pester test/unit/Test-{YourFeature}.ps1

# Integration test (after Agent 05 creates it)
Invoke-Pester test/integration/Test-Phase2Backlog.ps1

# Verification script
.\verify-management-dashboard.ps1 -Schema "DESIGN12" -ProjectId 18140190
```

### Generate Dashboard (End-to-End Test)
```powershell
.\management-dashboard-launcher.ps1 `
    -TNSName "SIEMENS_PS_DB_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18140190 `
    -DaysBack 7
```

### Update Status Tracker
```powershell
# Add your daily update to docs/PHASE2_BACKLOG_STATUS.md
code docs/PHASE2_BACKLOG_STATUS.md
# Find your agent section, update progress
```

### Get Help
1. Read your section in PHASE2_BACKLOG_AGENT_ASSIGNMENTS.md
2. Check PHASE2_DASHBOARD_SPEC.md for data contract
3. Check PHASE2_ACCEPTANCE.md for quality gates
4. Post blocker in PHASE2_BACKLOG_STATUS.md under your section
5. Tag @Agent05 for escalation

---

## 🚨 Critical Rules (ALL Agents)

1. **Work from main:** Branch from main, not from each other
2. **Create own branch:** `agent{N}-{feature-name}`
3. **All tests must pass:** Unit + integration before PR
4. **Merge to main:** All work goes to main via PR
5. **No breaking changes:** Do not modify Phase 1 or Phase 2 core
6. **Data contract:** JSON changes must be backward compatible
7. **Commit messages:** Follow format (see Git Commit Message Format)
8. **Daily updates:** Post to PHASE2_BACKLOG_STATUS.md
9. **Report blockers:** Immediately, don't guess
10. **Test locally:** Run verify-management-dashboard.ps1 before push

---

## 📞 Escalation Path

1. **For code questions:** Check PHASE2_BACKLOG_AGENT_ASSIGNMENTS.md
2. **For data questions:** Check PHASE2_DASHBOARD_SPEC.md
3. **For test questions:** Check PHASE2_ACCEPTANCE.md
4. **For blockers:** Post in PHASE2_BACKLOG_STATUS.md, tag @Agent05
5. **For critical issues:** Tag @maintainer

---

**Good luck, agents! Let's ship this! 🚀**
