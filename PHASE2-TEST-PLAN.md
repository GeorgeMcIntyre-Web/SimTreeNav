# Phase 2 E2E Test Plan - Management Dashboard

## Overview
Phase 2 validates the management dashboard including timelines, health scores, work type breakdowns, data refresh, and reporting.

## Preconditions
- Management data generation available (get-management-data.ps1)
- Test projects with known health score baselines
- Access to study and activity data

## Estimated Execution Time
| Suite | Estimated Time |
| --- | --- |
| Functional | 60 to 90 minutes |
| Data Refresh | 45 minutes |
| Reporting | 30 to 60 minutes |
| Concurrency | 30 minutes |

## Dependencies
- Phase 2 requires stable Phase 1 data extraction
- Health score validation requires manual review baseline

## Functional Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2-FUNC-01 | Dashboard loads | Open dashboard for project | Widgets load without error | No failed requests or empty panels |
| P2-FUNC-02 | Study list | View study list with health | Health score displayed | Score within expected range |
| P2-FUNC-03 | Timeline view | Filter by date range | Correct ordering of events | Events sorted by timestamp |
| P2-FUNC-04 | Work type breakdown | View breakdown widget | Totals match data | Counts and percentages correct |
| P2-FUNC-05 | User activity | View recent activity | Events shown and attributed | Actor and timestamp correct |

## Data Refresh Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2-REF-01 | Cache invalidation | Modify source data | Cache refreshes on schedule | Dashboard shows new data |
| P2-REF-02 | Hourly update | Wait for hourly refresh | Data timestamp changes | New timestamp within 60 min |
| P2-REF-03 | Daily snapshot | Trigger daily snapshot | Snapshot persisted | Snapshot file created |

## Reporting Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2-REP-01 | Weekly summary | Generate report | Summary totals correct | Numbers match dashboard |
| P2-REP-02 | Activity report | Export activity | File created | Export file valid format |
| P2-REP-03 | Report filters | Filter by study or user | Filter applies correctly | Only matching records shown |

## Concurrency Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2-CON-01 | 10 manager views | Open dashboard on 10 clients | No timeouts | All load within 10 seconds |
| P2-CON-02 | Concurrent filters | Apply filters in parallel | UI remains responsive | No error responses |

## Negative Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2-NEG-01 | Missing data set | Query empty project | Empty state shown | No errors, clear message |
| P2-NEG-02 | Invalid date range | End before start | Validation error | Error message displayed |
| P2-NEG-03 | Corrupt cache file | Modify cache JSON | Dashboard recovers | Cache refresh or fallback |

## Data Accuracy Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2-DATA-01 | Health score formula | Run health-score-validator.ps1 | Score within tolerance | +/- 3 points vs expected |
| P2-DATA-02 | Timeline ordering | Compare with DB query | Correct chronology | 100 percent ordered |
| P2-DATA-03 | Work breakdown totals | Compare with raw SQL | Totals match | 100 percent accuracy |

## Reporting and Outputs
- Export JSON reports from scripts to test-automation/results
- Record manual findings in the test execution report

## Example Test Data
Health score expectations CSV example:
```
studyId,expectedScore
STUDY-1001,82
STUDY-1002,74
```

## Sample Script Output
Example JSON output from health-score-validator.ps1:
```json
{
  "test": "health-score-validator",
  "status": "pass",
  "results": [
    { "studyId": "STUDY-1001", "expectedScore": 82, "actualScore": 82, "delta": 0, "status": "pass" }
  ]
}
```

## Troubleshooting Tips
- If health scores differ, verify source fields and weightings.
- If timelines are out of order, confirm timestamp field and time zone handling.
- If refresh fails, verify cache TTL and scheduled task execution.
