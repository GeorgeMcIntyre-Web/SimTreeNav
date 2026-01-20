# SimTreeNav E2E Testing Strategy

## Purpose
This document defines the end-to-end testing strategy for SimTreeNav across Phase 1 (Tree Viewer), Phase 2 (Management Dashboard), and Phase 2 Advanced (Intelligence Layer). It outlines test levels, environments, success criteria, risk priorities, and how testing integrates with delivery.

## System Context
- Phase 1: Tree viewer (complete) for 310K+ nodes, search, user activity
- Phase 2: Management dashboard (planned) for timeline, health scores, work breakdown
- Phase 2 Advanced: Intelligence layer (planned) for time-travel debugging, heat maps, smart notifications
- Oracle 12c database with 8M+ rows
- Must support 50 concurrent users without overloading the database

## Testing Levels
- Unit: PowerShell modules, query helpers, parsers, caching utilities
- Integration: Oracle connectivity, credential handling, caching layers, IIS and file share hosting
- System: Full workflow from connection to rendered UI or report
- End-to-End: Real user journeys across UI, reporting, and automation
- Performance: Load time, concurrency, memory, and query volume
- Security: Credential protection, read-only guarantees, XSS hardening
- Regression: Phase 1 stability with Phase 2 and Phase 2 Advanced changes
- UAT: Pilot users validate workflow and usability

## Test Environments
- Dev: local workstation, limited data sets, synthetic fixtures
- Staging: dedicated test DB clone, realistic data volume, IIS or file share
- Production (read-only): shadow testing with strict safeguards and DBA approval

## Test Data Requirements
- Sample projects: 3 to 5 representative projects with known baselines
- Synthetic data: generated studies, resources, assemblies, and timelines
- Production clone: sanitized snapshot with PII removed
- Edge cases: circular dependencies, orphan nodes, zero-node projects, 1M+ node projects

## Success Criteria by Phase

### Phase 1 (Tree Viewer)
- Page load time < 5 seconds for cached HTML on standard workstation
- Memory usage < 100 MB for browser session after 10 minutes of use
- 310K+ nodes present; icon count equals 221
- Critical path verification passes
- Search latency < 3 seconds for 20+ terms

### Phase 2 (Management Dashboard)
- Health score accuracy within +/- 3 points of manual review
- Timeline event ordering accurate to within 1 minute
- Work type breakdown totals match raw data within 1 percent
- Data refresh works (hourly updates, daily snapshots)
- 10 managers concurrent view with no timeout

### Phase 2 Advanced (Intelligence)
- Root cause identification precision >= 85 percent on curated dataset
- Dependency cascade detection accuracy >= 90 percent
- Notification delivery >= 99 percent within 60 seconds
- Heat map update latency <= 5 seconds

## Risk-Based Prioritization
Priority 0 (must pass):
- Oracle load and caching effectiveness
- Data integrity for node counts and critical paths
- Credential protection and read-only safety
- Cross-browser stability for Phase 1

Priority 1:
- Search accuracy and performance
- Timeline accuracy and health score correctness
- Regression between phases

Priority 2:
- UX refinements, non-critical analytics widgets, optional reports

## Test Execution Plan

### Schedule
- Each sprint: unit, integration, and regression tests on feature branches
- Weekly: system and E2E tests for Phase 1
- Monthly: load and performance tests, plus security review
- Pre-release: full E2E, performance, and UAT sign-off

### Entry and Exit Criteria
Entry:
- Feature complete or ready for integrated test
- Known test data set available
- Instrumentation or logging enabled

Exit:
- Priority 0 and 1 tests passed
- No open critical or high severity defects
- Performance thresholds met
- UAT success criteria met

## Defect Severity
- Critical: data loss, security breach, DB impact, or full outage
- High: core workflow broken, incorrect data, or high error rates
- Medium: partial feature failure with workaround
- Low: UI defects, cosmetic issues, non-blocking warnings

## Smoke Test Suite
- Generate tree HTML from cached data
- Load tree in browser, verify search, expand/collapse
- Verify critical path nodes exist
- Verify icon map count == 221
- Run validate-tree-data.ps1

## Traceability Matrix (Sample)
| Requirement | Test Case IDs |
| --- | --- |
| Tree navigation and search | P1-FUNC-01, P1-FUNC-03, P1-NEG-02 |
| Node completeness | P1-DATA-01, P1-DATA-02 |
| Health score accuracy | P2-DATA-02, P2-REP-02 |
| Timeline causality | P2-ADV-FUNC-01, P2-ADV-FUNC-02 |
| DB load constraints | ORA-LOAD-01, ORA-LOAD-03 |
| Credential protection | INT-SEC-01, INT-SEC-02 |

## CI/CD Integration
- On commit: run lint, unit, and fast integration tests
- Nightly: run Phase 1 E2E and validation scripts
- Weekly: run Oracle load tests in staging with DBA approval
- Publish reports as JSON and HTML in CI artifacts
- Auto-fail pipeline if P0 tests fail or performance threshold exceeded

## Reporting and Metrics
- Test results output in JSON and CSV
- Track pass rate, defect rate, and performance trends
- Maintain a rolling 4-week view of Oracle load impact

## Ownership
- QA lead: strategy and execution oversight
- Data engineer: Oracle load testing and data validation
- Dev team: unit and integration tests
- Product owner: UAT sign-off

## Related Documents
- PHASE1-TEST-PLAN.md
- PHASE2-TEST-PLAN.md
- PHASE2-ADVANCED-TEST-PLAN.md
- docs/ORACLE-LOAD-TEST-PROCEDURES.md
- UAT-PLAN.md
