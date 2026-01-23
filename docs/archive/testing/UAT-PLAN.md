# User Acceptance Testing (UAT) Plan

## Overview
User Acceptance Testing validates that SimTreeNav meets real-world expectations for engineering teams. This plan covers Phase 1 (Tree Viewer) and provides readiness gates for Phase 2 and Phase 2 Advanced.

## Objectives
- Confirm accuracy of tree content and user activity
- Validate usability for daily workflows
- Verify performance under normal usage
- Collect structured feedback and adoption signals

## Participants
- 5 to 10 pilot engineers
- 1 team lead (approver)
- 1 QA coordinator (facilitator)

## UAT Environment
- Staging or production read-only environment
- Known baseline project (example: FORD_DEARBORN)
- Latest generated HTML file and icon cache

## Entry Criteria
- Phase 1 regression suite passes
- validate-tree-data.ps1 and verify-critical-paths.ps1 pass
- No open critical or high severity defects

## Exit Criteria
- 80 percent or higher pilot satisfaction
- 70 percent or higher adoption intent
- No open critical defects
- Performance targets met

## UAT Scenarios

### Phase 1 Scenarios (Required)

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| UAT-P1-01 | Daily navigation | Open tree, find 5 known nodes | Node found quickly | Each node found in < 2 minutes |
| UAT-P1-02 | Search workflow | Run 10 search terms | Results are accurate | Each term finds at least one expected node |
| UAT-P1-03 | Multi-project | Load 2 projects in same day | No confusion, correct titles | Both loads correct and fast |
| UAT-P1-04 | User activity | Check checked-out indicators | Status matches Siemens app | No mismatches in sample |
| UAT-P1-05 | Performance | Use for 10 minutes | No freeze or lag | No UI freeze, memory stable |

### Phase 2 Scenarios (Planned)

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| UAT-P2-01 | Health overview | Review study list | Scores match expectation | <= +/- 3 points vs baseline |
| UAT-P2-02 | Timeline review | Filter by date range | Events ordered correctly | No out-of-order events |
| UAT-P2-03 | Work breakdown | Review work type chart | Totals match raw data | 100 percent match |

### Phase 2 Advanced Scenarios (Planned)

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| UAT-P2A-01 | Root cause analysis | Use time-travel debugging | Root cause identified | Matches curated expected cause |
| UAT-P2A-02 | Notifications | Receive alerts | Alerts relevant and timely | < 5 percent false positives |
| UAT-P2A-03 | Heat map | Review activity heat map | Hotspots reflect activity | Correlates to activity counts |

## Phase 1 Detailed Checklist (Expanded)

### Structural Completeness
- [ ] Root level children match Siemens Process Simulate
- [ ] Critical paths pass (verify-critical-paths.ps1)
- [ ] Deep node path matches Siemens app (5+ levels)

### Icon Verification
- [ ] Icon map count equals 221
- [ ] Representative icons match Siemens app (8 to 12 samples)
- [ ] No broken icons in tree view

### Data Accuracy
- [ ] Node names match Siemens app for 20 samples
- [ ] SEQ_NUMBER ordering matches Siemens app for 3 parents
- [ ] External IDs present when expected

### User Activity
- [ ] Checked-out items highlighted correctly
- [ ] User names displayed when available

### Usability and Performance
- [ ] Expand/collapse smooth for large branches
- [ ] Search results are accurate and fast
- [ ] No lag or freeze during 10-minute session

### Missing Node Investigation
- [ ] 10 random nodes found in HTML tree
- [ ] Any missing node logged with expected path

## Feedback Survey (Sample)
1) How satisfied are you with the tree viewer? (1 to 5)
2) Did the search results match your expectations? (1 to 5)
3) Was performance acceptable for daily use? (Yes/No)
4) What features were missing or confusing?
5) Would you use SimTreeNav weekly? (Yes/No)

## Success Criteria
- Satisfaction score >= 4.0 average
- 70 percent or higher adoption intent
- No critical defects reported

## Defect Tracking Process
- Log defects in the team tracker with severity and steps to reproduce
- QA coordinator triages within 24 hours
- Critical defects block release

## Go/No-Go Criteria
Go:
- All Phase 1 UAT scenarios passed
- Performance targets met
- Success criteria met

No-Go:
- Any critical defect
- Performance thresholds missed
- Satisfaction below 80 percent

## UAT Checklist
- [ ] Pilot users selected and trained
- [ ] Test data loaded and verified
- [ ] UAT scenarios executed
- [ ] Survey completed
- [ ] Defects logged and triaged
- [ ] Go/No-Go decision recorded

## Sign-Off

Tester: ____________________  Date: ____________________
Approver: __________________  Date: ____________________

## Notes
- Validate tree completeness with verify-critical-paths.ps1
- Use validate-tree-data.ps1 for XML baseline checks
