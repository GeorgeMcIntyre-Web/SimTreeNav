# Phase 1 E2E Test Plan - Tree Viewer

## Overview
Phase 1 validates the tree viewer for large data sets, search usability, user activity, and consistent rendering across browsers. This plan includes functional, performance, data accuracy, negative, and accessibility tests.

## Preconditions
- Oracle 12c client installed
- Access to DESIGN1-12 schemas
- Credentials stored via DPAPI or Windows Credential Manager
- Known project baseline (example: FORD_DEARBORN, 310K+ nodes)

## Test Data
- Baseline XML export for validation
- Known critical paths (see verify-critical-paths.ps1)
- Expected icon count: 221
- Search term list: at least 20 terms (see Sample Search Terms)

## Estimated Execution Time
| Suite | Estimated Time |
| --- | --- |
| Functional | 60 to 90 minutes |
| Performance | 60 minutes |
| Data Accuracy | 45 to 90 minutes |
| Browser Compatibility | 30 to 45 minutes |
| Negative | 30 minutes |
| Accessibility | 30 minutes |

## Dependencies
- Data Accuracy suite requires a generated HTML file and XML baseline
- Performance suite requires caching enabled and disabled runs
- Browser tests require Edge, Chrome, and Firefox installed

## Functional Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P1-FUNC-01 | Generate tree from launcher | Run tree-viewer-launcher.ps1 with valid profile | Tree HTML generated and opens | HTML file exists and loads without errors |
| P1-FUNC-02 | Expand and collapse | Expand 5 large nodes, collapse them | No UI freeze, state maintained | Expand/collapse responds within 1 second |
| P1-FUNC-03 | Search by part name | Search for known part name | Results list shows expected node | Target node appears in results |
| P1-FUNC-04 | Search by ID | Search for known object ID | Node found and highlighted | Node is visible and focused |
| P1-FUNC-05 | Multi-project support | Generate tree for Project A and B | Both files render correctly | Both trees load and show correct titles |
| P1-FUNC-06 | User activity indicators | Verify checkout status icons | Checked-out nodes show user info | Status matches Process Simulate |
| P1-FUNC-07 | Persistent settings | Relaunch viewer after selection | Last used schema and project preserved | Values match previous session |

## Performance Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P1-PERF-01 | Cached load time | Open cached HTML file | Load time < 5 seconds | Measured load time < 5 seconds |
| P1-PERF-02 | Cold generation time | Clear cache, generate tree | Generation < 90 seconds | End-to-end < 90 seconds |
| P1-PERF-03 | Concurrency 50 users | Simulate 50 file loads | No DB spikes with cache | DB impact < 30 percent CPU |
| P1-PERF-04 | Memory stability | Use tree for 10 minutes | Memory stable under 100 MB | Browser memory < 100 MB |

## Data Accuracy Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P1-DATA-01 | Node count | Compare HTML to baseline | 310K+ nodes present | Count within 2 percent |
| P1-DATA-02 | Icon count | Verify icon map size | 221 icons mapped | Icon map count = 221 |
| P1-DATA-03 | Critical paths | Run verify-critical-paths.ps1 | All paths found | Script reports PASS |
| P1-DATA-04 | XML delta | Run validate-tree-data.ps1 | Missing nodes <= 0.5 percent | Missing node rate under threshold |
| P1-DATA-05 | Ordering | Check SEQ_NUMBER order for 3 nodes | Order matches baseline | All sample orders match |

## Browser Compatibility Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P1-BROW-01 | Edge rendering | Open HTML in Edge | Layout and icons correct | No broken icons or layout shift |
| P1-BROW-02 | Chrome rendering | Open HTML in Chrome | Layout and icons correct | No broken icons or layout shift |
| P1-BROW-03 | Firefox rendering | Open HTML in Firefox | Layout and icons correct | Search works and tree expands |

## Negative Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P1-NEG-01 | Missing icon data | Remove an icon file | Fallback icon used | Missing icon warning only |
| P1-NEG-02 | Corrupt HTML file | Truncate HTML file | Viewer fails gracefully | Clear error message shown |
| P1-NEG-03 | DB unavailable | Disconnect network | Tree generation fails safely | No crash; error surfaced |
| P1-NEG-04 | Malformed cache file | Corrupt icon-cache JSON | Regeneration proceeds | Cache bypassed; icons reload |

## Accessibility Tests

| ID | Scenario | Steps (Summary) | Expected Result | Pass/Fail Criteria |
| --- | --- | --- | --- | --- |
| P1-A11Y-01 | Keyboard navigation | Use Tab and arrow keys | Focus moves predictably | Focus visible and logical |
| P1-A11Y-02 | Screen reader labels | Use NVDA or Narrator | Tree nodes announced | Node name and level read |
| P1-A11Y-03 | Contrast | Check text and icons | Meets contrast guidelines | No critical contrast failures |

## Sample Search Terms
Use at least 20 terms across libraries, parts, resources, and studies. Example list:
- PartLibrary
- PartInstanceLibrary
- MfgLibrary
- EngineeringResourceLibrary
- RobcadStudy
- COWL_SILL_SIDE
- Robot
- Station
- Tool
- Fixture
- Weld
- Process
- Line
- Assembly
- Operation
- P702
- P703
- CC
- SOP
- INVALID_TERM_123 (expected zero)

## Troubleshooting Tips
- If node count is low, verify SQL filters were not added to COLLECTION_ queries.
- If icons are missing, clear icon cache and re-run icon extraction.
- If search is slow, confirm the tree data is loaded in memory and not re-parsed per query.

## Automated Script Coverage
- validate-tree-data.ps1: Node and XML validation
- search-functionality-test.ps1: Search term coverage
- performance-benchmark.ps1: Load time and memory proxy checks

## Example Test Data
Search term CSV example (optional):
```
term,expectedMin
PartLibrary,1
MfgLibrary,1
RobcadStudy,1
INVALID_TERM_123,0
```

## Sample Script Output
Example JSON output from validate-tree-data.ps1:
```json
{
  "test": "validate-tree-data",
  "status": "pass",
  "metrics": {
    "xmlNodeCount": 631318,
    "htmlNodeCount": 631290,
    "iconMapCount": 221,
    "missingNodeCount": 0
  }
}
```

## Reporting
- Store JSON reports under test-automation/results
- Record manual findings in a test execution report
