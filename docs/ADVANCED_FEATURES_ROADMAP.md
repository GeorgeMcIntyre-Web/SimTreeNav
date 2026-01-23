# Advanced Features Roadmap

**Project:** SimTreeNav — Phase 2
**Date:** 2026-01-23
**Status:** DRAFT

---

## Horizon 1: Pilot (Weeks 1-3)
**Focus:** Visibility & Stability. Getting the new "eyes and ears" (Monitoring, Inventory, Quality Indicators) in place without disrupting daily ops.

*   **Key Deliverables:**
    *   Server Inventory (Discovery)
    *   Dashboard Monitoring Hooks
    *   Data Quality Widgets (Basic)
*   **Success Metrics:**
    *   100% of Oracle instances discovered and listed.
    *   < 1 hour Time-to-Detect (TTD) for stalled dashboards (via Monitor).
    *   Zero regressions in Phase 1 dashboard.
*   **Risks:**
    *   Network access to secondary Oracle instances.
    *   "False Alarm" fatigue from initial monitor tuning.
*   **Owners:**
    *   Tech Lead (Arch/Scripts)
    *   Ops Lead (Deployment/Access)
*   **Gating Criteria for Horizon 2:**
    *   Monitoring script running stably in Prod for 7 days.
    *   Ops team sign-off on "System Status" vocabulary.

---

## Horizon 2: Scale (Weeks 4-6)
**Focus:** Actionable Insights. Turning data into decisions (Churn Risk, Evidence Packs).

*   **Key Deliverables:**
    *   Churn Risk / Hotspot Analysis
    *   Evidence Pack Exporter (Zip + Manifest)
    *   Naming Consistency Rules Engine
*   **Success Metrics:**
    *   Ops team uses Evidence Pack for weekly sign-off (adoption).
    *   "At Risk" studies identified 2 days before deadline on average.
*   **Risks:**
    *   Disk space consumption (Evidence Packs).
    *   Performance drag from complex Risk Scoring queries.
*   **Owners:**
    *   Product Owner (Risk definitions)
    *   Dev Team (Feature implementation)
*   **Gating Criteria for Horizon 3:**
    *   Evidence Pack export < 2 mins.
    *   Risk Score algorithm validated against past incidents.

---

## Horizon 3: Institutionalize (Weeks 7+)
**Focus:** Intelligence & User Empowerment. (Trend Timeline, Search, Self-Correction).

*   **Key Deliverables:**
    *   Trend Timeline (Historical Delta)
    *   Safe Search & Highlight
    *   User-Subscription Alerts (Email me when X changes)
*   **Success Metrics:**
    *   > 50% of users using Search daily.
    *   Weekly "Trend Report" discussed in Management meetings.
*   **Risks:**
    *   Data storage growth for historical trends.
    *   Privacy/Sensitivity of "User Performance" data.
*   **Owners:**
    *   Product Manager (Long-term vision)
    *   Ops Team (Maintenance)
