# Phase 2 Advanced Features Master Plan

**Project:** SimTreeNav — Phase 2 + Production Rollout
**Date:** 2026-01-23
**Status:** DRAFT
**Agent:** 01 (Product + Architecture)

---

## 1. Executive Summary
Phase 2 builds upon the successful core dashboard by introducing **Advanced Intelligence & Automation**. Our goal is to shift from "Passive Reporting" (showing what happened) to "Proactive Insights" (showing what needs attention).

This plan outlines a safe, additive strategy to introduce advanced features like cross-schema inventory, risk scoring, and evidence pack generation. We adhere strictly to a **read-only Oracle policy** and **zero-breakage rule** for the existing Phase 1/2 core.

**Key Value Props:**
1.  **Visibility**: See *all* servers and instances, not just the primary one.
2.  **Recall**: "Time-travel" awareness of trends and historical changes.
3.  **Trust**: Automated evidence packs and data quality indicators.

---

## 2. Feature Catalog (Ranked)

### NOW (Immediate Priority - Weeks 1-2)

#### 1. Cross-Schema Server Inventory + Discovery
*   **PM Value/ROI**: Eliminates "blind spots" where unmonitored instances cause outages. High ROI for Ops stability.
*   **MVF**: A simple list of all discoverable Oracle instances and Schema versions in the `out/json/inventory.json` file, rendered in a new "System Status" tab.
*   **Data Dependencies**: Needs `ROBCADSTUDY_`, `ROBCADSTUDYINFO_` access across schemas. Output: `inventory.json`.
*   **UX Entry Point**: "System Status" Tab -> "Server Inventory" Table.
*   **Failure Modes**: Connection timeouts on remote instances; permission denied on specific schemas.
*   **Testing Approach**: Deterministic connection test list; mocked timeout responses.
*   **Interfaces**: Agent 3 needs `inventory.json` schema to build the UI adapter.

#### 2. Run Monitoring + Alerting Hooks
*   **PM Value/ROI**: Reduces "monitor fatigue". Ops only look when something is wrong.
*   **MVF**: A script that parses `out/logs/` and sends a "Red Flag" email if a critical failure occurred or if the dashboard hasn't updated in >24h.
*   **Data Dependencies**: Access to `out/logs/` and `out/json/run-manifest.json`.
*   **UX Entry Point**: Email / File Drop / Dashboard Header "Last updated: X (Alert!)".
*   **Failure Modes**: SMTP failure; Log locking.
*   **Testing Approach**: Generate dummy error logs and verify hook trigger.
*   **Interfaces**: Standardized Log Format (Agent 2 output).

#### 3. "Data Quality" Indicators
*   **PM Value/ROI**: Increases trust in the dashboard. Users know *why* data might be missing (e.g., "3 orphan nodes found").
*   **MVF**: "Data Health" sidebar widget showing count of Null timestamps, specialized nodes without parents, and missing owners.
*   **Data Dependencies**: Augmented SQL queries in `generate-management-dashboard.ps1`.
*   **UX Entry Point**: Sidebar Widget / Cell Badge (Yellow warning).
*   **Failure Modes**: False positives if logic is too strict.
*   **Testing Approach**: Inject known bad data into a test SQLite/Mock DB and verify counts.
*   **Interfaces**: `quality_metrics` object in main JSON.

### NEXT (Weeks 3-4)

#### 4. Evidence Pack Exporter
*   **PM Value/ROI**: Compliance & Archival. "One-click audit" capability.
*   **MVF**: CLI tool to ZIP up `out/html`, `out/json` + Manifest + Checksum.
*   **Data Dependencies**: All `out/*` artifacts.
*   **UX Entry Point**: "Export" button on Dashboard Header.
*   **Failure Modes**: Disk space full; File locking during zip.
*   **Testing Approach**: Verify ZIP integrity and Manifest SHA match.
*   **Interfaces**: `RunManifest.ps1` library.

#### 5. Churn Risk Scoring
*   **PM Value/ROI**: Proactive intervention. Identify studies/users "at risk" of delay.
*   **MVF**: "Hotspot" table showing top 5 studies with highest daily change rate.
*   **Data Dependencies**: Historical run data (requires persistence or diffing).
*   **UX Entry Point**: "Risk Radar" Panel.
*   **Failure Modes**: History missing (first run).
*   **Testing Approach**: Comparative tests against seeded historical data.
*   **Interfaces**: `risk_score` field in study JSON object.

### LATER (Weeks 5+)

#### 6. Safe Search + Highlight
*   **PM Value/ROI**: Usability. Finding needle in haystack without breaking UI state.
*   **MVF**: Client-side JS filter that highlights matching rows/nodes without reloading the DOM or breaking event listeners.
*   **Data Dependencies**: Client-side only.

#### 7. Trend Timeline
*   **PM Value/ROI**: Executive reporting (Weekly deltas).
*   **MVF**: Sparkline charts for "Total Active Studies" over last 4 weeks.
*   **Data Dependencies**: Persistent history storage (JSON or DB).

---

## 3. Implementation Playbook

**Phase 2.1: Foundation (Agent 01 - Done)**
1.  Establish Docs & Plans.
2.  Create Stub Scripts for robust operations.
3.  Define JSON Schemas.

**Phase 2.2: Core Logic Expansion (Agent 02)**
1.  Implement `dashboard-monitor.ps1` logic (Log parsing).
2.  Implement `RunManifest.ps1` library (Artifact tracking).
3.  Add "Data Quality" SQL queries to extraction scripts (Read-Only).
4.  Verify performance impact (must stay < 5min runtime).

**Phase 2.3: UI & Experience (Agent 03)**
1.  Update Dashboard HTML/JS to consume `quality_metrics`.
2.  Add "System Status" tab for Inventory.
3.  Wire up "Export" button to trigger `export-evidence-pack.ps1` (via backend launcher if applicable, or just manual instructions for now).

**Phase 2.4: Verification & Rollout (Agent 10)**
1.  End-to-End Test: Run extraction -> Dashboard Render -> Monitor Check -> Zip Export.
2.  UAT with Ops team.

---

## 4. Acceptance Gates & Definition of Done

**Definition of Done (DoD):**
*   [ ] Code committed to `main` via PR.
*   [ ] Zero touch on HOT files (Phase 1 core preserved).
*   [ ] Read-only Oracle access verified (no DML found).
*   [ ] `RunManifest` generated for every run.
*   [ ] All scripts return Exit Code 0 on success, non-zero on failure.
*   [ ] Logs generated in `out/logs/`.
*   [ ] Documentation updated.

**Acceptance Gates:**
*   **Gate 1 (Tech)**: `Scripts/ops/*.ps1` pass syntax check and run with `-Smoke` flag.
*   **Gate 2 (Product)**: Dashboard shows "System Status" tab with correct data.
*   **Gate 3 (Ops)**: Evidence Pack ZIP extracts correctly and Manifest hash matches.

---

## 5. Handoff Block

### What Agent 2 Needs:
*   The Stubs in `scripts/ops/` and `scripts/lib/` to begin implementing logic.
*   The `ADVANCED_FEATURES_TECH_SPEC.md` for JSON schema fields (`quality_metrics`, `inventory`).

### What Agent 3 Needs:
*   The UX Entry Points defined in "Feature Catalog" (System Status Tab, Risk Radar).
*   Sample JSON data structure (mocked in Tech Spec) to build UI components in parallel.

### Parallel Work Opportunities:
*   Agent 2 can build the **SQL Extraction Logic** for "Data Quality".
*   Agent 3 can build the **Frontend Components** (Quality Widget, Server Table) using mock JSON.
*   Agent 10 can write the **Test Scenarios** based on Failure Modes.
