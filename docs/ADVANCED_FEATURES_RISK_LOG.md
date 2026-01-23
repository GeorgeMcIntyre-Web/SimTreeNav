# Advanced Features Risk Log

**Project:** SimTreeNav — Phase 2
**Date:** 2026-01-23

| ID | Risk Category | Description | Impact | Probability | Mitigation Strategy | Detection Method | Owner (Role) |
|----|---|---|---|---|---|---|---|
| **R-01** | **Oracle Performance** | Querying "all instances" for inventory or risk scoring loads the DBs. | High | Med | 1. Use extremely short timeouts (2s). <br> 2. Run queries serially, not parallel. <br> 3. Cache results for 15-60 mins. | Monitor Oracle session stats (CPU/IO) during run. | Database Lead |
| **R-02** | **Schema Drift** | Stored JSON history formats change, breaking "Trend Timeline". | Med | High | 1. Strict `schemaVersion` header. <br> 2. Readers must support "Migration" logic or graceful fallback (ignore old data). | Integration tests reading mixed-version JSONs. | Tech Lead |
| **R-03** | **Permissions** | Script cannot access specific schemas for "Inventory" (Permission Denied). | Med | High | 1. `Try/Catch` block around every connection attempt. <br> 2. Report "Access Denied" in UI (System Status) rather than crashing. | Log parsing for "ORA-01031" errors. | Ops Lead |
| **R-04** | **Data Accuracy** | "Data Quality" indicators flag legitimate data as errors (False Positives). | Low | Med | 1. Configurable exclusion lists (e.g., "Ignore these specific nodes"). <br> 2. Beta period where warnings are "Hidden" or visible to Admins only. | User feedback loop ("Report Issue" link). | Product Owner |
| **R-05** | **Change Fatigue** | Users overwhelmed by too many new widgets/alerts. | Med | Med | 1. Roll out features incrementally (Horizon 1, 2, 3). <br> 2. Default all alerts to "OFF" or "Digest" mode. | Usage analytics (are they turning it off?). | Product Manager |
| **R-06** | **Disk Space** | Evidence Packs and Historical Logs consume full disk. | High | Low | 1. Retention policy (auto-delete > 30 days). <br> 2. Check disk space before writing; fail gracefully if full. | `dashboard-monitor.ps1` disk check. | Ops Lead |
