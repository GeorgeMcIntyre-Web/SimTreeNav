# Phase 2 Advanced E2E Test Plan - Intelligence Layer

## Overview
Phase 2 Advanced validates time-travel debugging, dependency graphs, smart notifications, and heat maps. The focus is accuracy of causality, high signal alerts, and real-time visibility.

## Preconditions
- Timeline data with causality links
- Dependency graph data available or generated
- Notification service configured (email, Slack, or webhook)

## Dependencies
- P2-FUNC-03 (Timeline view) must pass before time-travel debugging tests
- Valid dependency graph data required for P2A-DEP-01 through P2A-DEP-03
- Notification delivery infrastructure required for P2A-NOTIF-01 through P2A-NOTIF-04

## Estimated Execution Time
| Suite | Estimated Time |
| --- | --- |
| Time-Travel Debugging | 60 minutes |
| Dependency Graph | 45 minutes |
| Smart Notifications | 45 minutes |
| Heat Maps | 30 minutes |

## Time-Travel Debugging Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2A-FUNC-01 | Root cause selection | Open a study timeline | Root cause flagged | Root cause candidate present |
| P2A-FUNC-02 | Causality chain | Expand event causes | Chain matches expected | All expected links exist |
| P2A-FUNC-03 | Time range filter | Filter to 7-day window | Events within range | No out-of-range events |

## Dependency Graph Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2A-DEP-01 | Graph integrity | Run dependency-graph-test.ps1 | No missing links | Zero missing edges |
| P2A-DEP-02 | Cascade detection | Update upstream node | Dependent nodes flagged | All affected nodes listed |
| P2A-DEP-03 | Cycle handling | Provide cyclic data | Cycle detected | Cycle warning reported |

## Smart Notification Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2A-NOTIF-01 | Health drop alert | Simulate health score drop | Alert delivered | Received within 60 sec |
| P2A-NOTIF-02 | Dependency update | Modify resource assembly | Alert includes dependency | Payload contains dependencyId |
| P2A-NOTIF-03 | Stalled study | Simulate no activity | Alert generated | Stalled alert received |
| P2A-NOTIF-04 | False positive rate | Run on stable dataset | Low false alerts | < 5 percent false alerts |

## Heat Map Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2A-HEAT-01 | Activity visualization | Load heat map for site | Correct intensity | Correlates with activity count |
| P2A-HEAT-02 | Real-time update | Trigger activity events | Map updates quickly | Update latency <= 5 sec |
| P2A-HEAT-03 | Conflict detection | Simulate collisions | Conflict shown | Conflict nodes highlighted |

## Negative Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P2A-NEG-01 | Missing causality links | Omit links in timeline | Graceful fallback | No crash, warning shown |
| P2A-NEG-02 | Notification service down | Disable webhook endpoint | Retry logic works | Retries logged, no data loss |
| P2A-NEG-03 | Heat map data gap | Missing activity window | Gap handled | Display with empty state |

## Troubleshooting Tips
- If root cause selection is wrong, verify parent-child edges in timeline data.
- If notifications are late, check queue backlog and retry policy.
- If heat map is delayed, verify event stream frequency and cache TTL.

## Example Test Data
Dependency edges CSV example:
```
parentId,childId
DEP-01,DEP-02
DEP-02,DEP-03
```

Expected chains JSON example:
```json
[
  ["DEP-01", "DEP-02", "DEP-03"]
]
```

## Sample Script Output
Example JSON output from dependency-graph-test.ps1:
```json
{
  "test": "dependency-graph-test",
  "status": "pass",
  "metrics": { "cycleCount": 0, "orphanCount": 0 }
}
```
