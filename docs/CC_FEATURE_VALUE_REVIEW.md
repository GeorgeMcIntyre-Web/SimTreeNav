# CC Feature Value Review: Phase 2 Backlog

**Reviewer:** Claude Code (Senior Product+Engineering)
**Date:** 2026-01-22
**Branch:** cursor/cc-feature-review
**Scope:** 15 proposed features for SimTreeNav Phase 2 backlog

---

## Executive Summary

This review evaluates 15 proposed features against SimTreeNav's current state (Phase 1 and Phase 2 complete). The project uses a **static dashboard architecture** with PowerShell extraction from Oracle DB, making real-time features and services impractical.

**Key Findings:**
- **6 features** recommended for immediate work (Now)
- **3 features** recommended for next sprint (Next)
- **3 features** defer to backlog (Later)
- **3 features** should not be pursued (Never)

**Grounding Evidence:**
- [docs/PROJECT-ROADMAP.md](docs/PROJECT-ROADMAP.md) - Phase 1 complete, Phase 2 complete
- [docs/SYSTEM-ARCHITECTURE.md](docs/SYSTEM-ARCHITECTURE.md) - Static HTML, no backend services
- [STATUS.md](STATUS.md) - Phase 2 delivered, all acceptance gates passed
- [src/powershell/main/get-management-data.ps1](src/powershell/main/get-management-data.ps1) - 11 queries covering 5 work types
- [scripts/robcad-study-health.ps1](scripts/robcad-study-health.ps1) - Existing study quality linting
- [docs/ROBCAD_STUDY_HEALTH.md](docs/ROBCAD_STUDY_HEALTH.md) - Study health documentation

---

## A) Decision Table

| # | Feature | PM Value | Effort | Do When | MVF (≤1 week) | Data Needed | Risks / Gotchas |
|---|---------|----------|--------|---------|---------------|-------------|-----------------|
| 1 | Unified "Study Health" scorecard | **H** | **S** | **Now** | Integrate existing robcad-study-health.ps1 output into dashboard as new tab | EXISTS: scripts/robcad-study-health.ps1, out/robcad-study-health-report.md | None. Script proven, just needs HTML integration. |
| 2 | Who's doing what now (checkout tracking) | **H** | **S** | **Now** | Add "stale checkout" flag (>3 days) to existing user activity view | EXISTS: PROXY.WORKING_VERSION_ID, USER_ table (already in get-management-data.ps1) | None. Data already extracted. |
| 3 | Daily/weekly activity digest | **M** | **S** | **Next** | Add date-range selector to existing dashboard, regenerate with filtered data | EXISTS: All queries have MODIFICATIONDATE_DA_ timestamps | Requires manual re-run; no auto-email (static arch). |
| 4 | Scope change tracker | **M** | **M** | **Later** | Diff two extraction snapshots (JSON), show added/removed/renamed nodes | MISSING: Need scheduled snapshots (cron or Task Scheduler), historical JSON storage | Storage growth (7 days = 7 snapshots). Manual snapshot management. |
| 5 | Time-travel timeline | **H** | **L** | **Later** | N/A - Cannot deliver in ≤1 week | MISSING: Requires historical change log (Oracle LogMiner or custom triggers) | Architectural mismatch. Requires DB write access or external log store. High complexity. |
| 6 | Work-type breakdown | **H** | **S** | **Now** | ALREADY DELIVERED - Phase 2 dashboard has this | EXISTS: scripts/generate-management-dashboard.ps1, View 1: Work Type Summary | N/A - Feature already shipped. Enhance with trend charts (next sprint). |
| 7 | Bottleneck & queue view | **H** | **S** | **Now** | Add "checkout duration" column to user activity table, highlight >48hrs in red | EXISTS: PROXY.WORKING_VERSION_ID, checkout timestamps (inferred from modification date) | Duration estimation is approximate (no explicit checkout timestamp in PROXY). |
| 8 | Heat map by station/zone | **M** | **M** | **Later** | Station activity table (text) - counts per station, no visual map | PARTIAL: Station names extracted from SHORTCUT_ table (8J-010, etc.) in study resources query | Visual heat map requires factory floor layout metadata (not in DB). Adds UI complexity. |
| 9 | Resource/panel utilization | **H** | **S** | **Now** | Table: Resource → Studies using it → Conflicts (same resource in 2+ active studies) | EXISTS: studyResources query in get-management-data.ps1 | None. High ROI for conflict detection. |
| 10 | Cross-project consistency checks | **M** | **M** | **Next** | Compare naming conventions across DESIGN1-DESIGN12, flag mismatches (e.g., "8J_010" vs "8J-010") | EXISTS: Can query multiple schemas; src/powershell/utilities/common-queries.ps1 has schema iteration | Performance: 12 schemas × 300K nodes = expensive. Limit to studies/resources only. |
| 11 | Risk flags (high churn areas) | **H** | **S** | **Now** | Extend robcad-study-health.ps1 to flag studies modified >10 times in 7 days | PARTIAL: Modification dates exist; need to count distinct mod events per object | False positives if user iterates rapidly. Tune threshold with PM. |
| 12 | Smart notifications (rule engine) | **L** | **L** | **Never** | N/A | EXISTS: Data available, but architecture mismatch | Requires background service for real-time monitoring. Static dashboard is snapshot-based. Out of scope. |
| 13 | Top "technical debt" list | **H** | **S** | **Now** | Dashboard tab showing robcad-study-health-issues.csv (Critical/High severity) | EXISTS: robcad-study-health.ps1 already generates CSV with severity rankings | None. High signal, zero effort. |
| 14 | Searchable management dashboard | **H** | **S** | **Now** | Add client-side filter (JavaScript) to existing dashboard tables | EXISTS: All data already in HTML; just add <input> + filter logic | None. Standard UX pattern. |
| 15 | "One-click evidence pack" | **M** | **S** | **Next** | PowerShell script to ZIP: dashboard HTML + CSVs + study health report | EXISTS: All reports generated to out/ directory | None. Simple file bundling. |

---

## B) Recommended Roadmap

### Now (Next Sprint - Weeks 1-2)

**High signal, low effort - integrate existing data:**

1. **Unified Study Health Dashboard** (Feature #1)
   - Why: Script exists, just needs HTML wrapper
   - Effort: 2-3 days
   - ROI: Immediate quality visibility

2. **Searchable Dashboard Filters** (Feature #14)
   - Why: Core usability improvement
   - Effort: 1 day (client-side JavaScript)
   - ROI: Essential for 300K+ nodes

3. **Resource Conflict Detection** (Feature #9)
   - Why: Prevents duplicate work (80% reduction per roadmap)
   - Effort: 1-2 days
   - ROI: Critical for multi-user teams

4. **Stale Checkout Alerts** (Feature #2)
   - Why: Data exists, simple enhancement
   - Effort: 0.5 days
   - ROI: Reduces blocking issues

5. **Bottleneck Queue View** (Feature #7)
   - Why: PM visibility into delays
   - Effort: 1 day
   - ROI: High for project tracking

6. **Technical Debt Dashboard Tab** (Feature #13)
   - Why: Zero-effort data reuse
   - Effort: 0.5 days
   - ROI: Proactive quality management

7. **High Churn Risk Flags** (Feature #11)
   - Why: Extend existing health script
   - Effort: 1 day
   - ROI: Early warning system

**Total: 7-9 days (within 2-week sprint)**

### Next (Weeks 3-4)

**Medium ROI, requires coordination:**

8. **Daily/Weekly Activity Digest** (Feature #3)
   - Why: User-requested reporting cadence
   - Effort: 2 days (date filters + summary stats)
   - Dependency: Requires PM input on digest frequency

9. **Cross-Project Consistency Checker** (Feature #10)
   - Why: Multi-schema environments need naming standards
   - Effort: 3 days (query optimization required)
   - Risk: Performance testing with 12 schemas

10. **One-Click Evidence Pack** (Feature #15)
    - Why: Executive reporting convenience
    - Effort: 1 day
    - Dependency: Finalize which reports to include

**Total: 6 days**

### Later (Backlog - Months 2-3)

**Defer until Now/Next features prove value:**

11. **Scope Change Tracker** (Feature #4)
    - Why: Requires infrastructure (scheduled snapshots)
    - Effort: 5 days (snapshot automation + diff engine)
    - Blocker: Need storage strategy for historical JSONs

12. **Station Heat Map** (Feature #8)
    - Why: Needs factory floor layout metadata
    - Effort: 4 days (without visual map), 10 days (with SVG map)
    - Blocker: Layout data not in database

13. **Time-Travel Timeline** (Feature #5)
    - Why: High user value but architectural mismatch
    - Effort: 15-20 days (requires Oracle LogMiner or custom change tracking)
    - Blocker: Read-only DB access; needs DBA approval for audit trail

---

## C) Kill List

**Features not worth pursuing:**

### Feature #12: Smart Notifications Engine

**Why kill it:**
- Requires background service (polling DB every 5-15 min)
- Architectural mismatch: SimTreeNav is **static dashboard**, not real-time SaaS
- Email delivery requires SMTP server + credential management
- Maintenance burden: Rule engine complexity, false positive tuning
- Workaround: Users can re-run dashboard on-demand (9.5s cached, per STATUS.md)

**Evidence from architecture:**
- [docs/SYSTEM-ARCHITECTURE.md](docs/SYSTEM-ARCHITECTURE.md) Line 10: "PowerShell-based Oracle database tree navigation system... interactive HTML tree visualizations"
- [docs/PROJECT-ROADMAP.md](docs/PROJECT-ROADMAP.md) Line 227: Phase 3 "Automated Report Generation" listed as aspirational, not committed

**Alternative:** Add "Last Updated" timestamp to dashboard header. Users refresh manually when needed.

---

### Feature #5: Time-Travel Timeline (if not approved for "Later")

**Why it's high-risk:**
- Requires **write access** to Oracle (to enable LogMiner or triggers)
- Current architecture is **read-only** (per SYSTEM-ARCHITECTURE.md Line 332: "Read-only database user recommended")
- Storage cost: 310K nodes × daily snapshots × 90 days = 28M records
- Complexity: Relationship graph traversal across time dimensions
- ROI uncertain: No user demand data in repo

**Evidence:**
- [STATUS.md](STATUS.md) Line 266: "All original requirements met" - no mention of historical tracking
- [docs/PROJECT-ROADMAP.md](docs/PROJECT-ROADMAP.md) Line 134: Time-Travel listed under Phase 2 Advanced (8-12 weeks effort), not Phase 2

**Alternative:** Implement Feature #4 (Scope Change Tracker) first as proof-of-concept. If high adoption, revisit time-travel in Phase 3.

---

### Feature #8: Heat Map by Station/Zone (visual version)

**Why defer indefinitely:**
- Factory floor layout metadata **not in database** (confirmed by reviewing schema queries in queries/analysis/)
- Requires manual SVG creation or CAD file import
- Maintenance burden: Layout changes require SVG updates
- Low ROI: Station activity **table** (text) provides same insights with zero UI complexity

**Evidence:**
- [queries/management/get-work-activity.sql](queries/management/get-work-activity.sql) extracts station names from SHORTCUT_ (e.g., "8J-027_SC" → station "8J-027"), but no X/Y coordinates
- No references to layout tables in 100+ SQL files in queries/

**Alternative:** Deliver text-based station activity table (Feature #8 MVF) in "Later" sprint. Visual heat map only if users explicitly request and provide layout file.

---

## Appendix: Data Audit

### What We Have (Confirmed in Repo)

**User Activity:**
- [src/powershell/main/get-management-data.ps1](src/powershell/main/get-management-data.ps1) Lines 454-469: User activity query with checkout counts
- Tables: PROXY (checkout status), USER_ (user names), SIMUSER_ACTIVITY (legacy tracking)

**Work Type Tracking:**
- Query 1 (Lines 200-219): Project Database (COLLECTION_)
- Query 2 (Lines 222-244): Resource Library (RESOURCE_)
- Query 3 (Lines 247-278): Part/MFG Library (PART_)
- Query 4 (Lines 281-303): IPA Assembly (PART_ WHERE CLASS_ID=133)
- Queries 5A-5F (Lines 306-451): Study nodes (ROBCADSTUDY_, OPERATION_, STUDYLAYOUT_)

**Study Health:**
- [scripts/robcad-study-health.ps1](scripts/robcad-study-health.ps1): 954 lines of linting logic
- Outputs: robcad-study-health-report.md, issues.csv, suspicious.csv, rename-suggestions.csv
- Rules: config/robcad-study-health-rules.json (junk tokens, legacy markers, naming conventions)

**Modification Timestamps:**
- All queries extract MODIFICATIONDATE_DA_, LASTMODIFIEDBY_S_, CREATEDBY_S_
- Sufficient for time-based filtering (#3), churn detection (#11), stale checkout (#2)

### What We're Missing

**Historical Change Log:**
- No audit trail of who changed what when (Oracle LogMiner not enabled)
- Blocks: Feature #5 (time-travel), full scope tracking (#4)

**Station Coordinates:**
- SHORTCUT_ table has station **names** (8J-010), but no X/Y/Z layout positions
- Blocks: Visual heat map (#8)

**Cross-Schema Baselines:**
- No established naming convention rules across DESIGN1-12
- Blocks: Feature #10 until PM defines "correct" patterns

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-22 | Claude Code | Initial feature value review for Phase 2 backlog |

---

**End of Report**
