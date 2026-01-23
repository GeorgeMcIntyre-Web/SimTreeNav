# SimTreeNav - Production Deployment Plan (Phase 2)

**Project:** SimTreeNav - Phase 2 Advanced Features
**Deployment Target:** Windows Server IIS + Oracle 19c (ReadOnly)
**Go-Live:** Week of Feb 10, 2026
**Branch:** `production` (merged from `phase2-dev`)

## Overview
This plan details the additive deployment of Phase 2 features. The strategy minimizes risk by using a "side-by-side" asset approach where possible and strictly read-only database operations.

## Roles & Responsibilities
- **Dev (Agent):** Prepare release artifacts, runbook, and scripts.
- **IT Ops:** Provision service account, schedule tasks, configure IIS.
- **DBA:** Verify query performance, grant read-only schema access.
- **PM:** Conduct UAT, sign off on Go/No-Go.

## Pre-Requisites (Week 1: Jan 27 - Jan 31)
- [ ] **Service Account**: `SVC_SIMTREE_RO` created with AD group membership.
- [ ] **Database Access**: `SVC_SIMTREE_RO` granted `CONNECT`, `SELECT` on `PROD_SCHEMA`.
- [ ] **Hosting**: IIS Site `SimTreeNav` or Network Share `\\FILESERVER\SimTreeNav` provisioned.
- [ ] **SMTP**: Relay access for `scripts/ops/send-weekly-digest.ps1`.

### Decision Form (To be filled by IT/Ops)
| Item | Value (Fill in) |
| :--- | :--- |
| **Oracle Host:Port/Service** | `__________________________` |
| **Schema Name** | `__________________________` |
| **Hosting Path (Physical)** | `__________________________` |
| **URL (Internal)** | `__________________________` |
| **SMTP Server** | `__________________________` |

## Deployment Steps

### Step 0: Dry-Run Preparation (Mandatory)
Before any effective changes, execute the dry-run operations pack.
1.  **Validate Environment**:
    ```powershell
    pwsh ./scripts/ops/validate-environment.ps1 -Smoke
    ```
2.  **Generate Configs**:
    ```powershell
    pwsh ./scripts/ops/install-scheduled-tasks.ps1 -OutDir ./out
    ```
    *Verifies XML generation without registering tasks.*

### Step 0.5: Staging Rehearsal (Recommended)
Before copying to Production `D:\SimTreeNav`:
1.  Run `scripts/ops/build-deploy-bundle.ps1 -DeployRoot ./out/staging_root/SimTreeNav -Smoke` locally.
2.  Verify the bundle layout matches `D:\SimTreeNav`.
3.  Generate XMLs using the staging bundle path to confirm logic:
    ```powershell
    pwsh ./scripts/ops/install-scheduled-tasks.ps1 -HostRoot "D:\SimTreeNav" -OutDir ./out_staging
    ```

### Step 1: Smoke Test & Backup (Dev/Ops) - Feb 9
1.  **Backup** current Production `wwwroot` or share content.
    ```powershell
    Compress-Archive -Path "D:\Sites\SimTreeNav\*" -DestinationPath "D:\Backups\SimTreeNav_PrePhase2.zip"
    ```
2.  **Dry Run** scripts on Staging/Dev machine to verify config.
    ```powershell
    pwsh ./scripts/ops/dashboard-task.ps1 -DryRun -OutDir ./out_test
    ```

### Step 2: Deploy Artifacts (Ops) - Feb 10
1.  **Stop Tasks**: Disable existing scheduled tasks if any.
2.  **Copy Assets**:
    - Copy contents of `out/html/` to `D:\Sites\SimTreeNav\`.
    - Ensure `web.config` matches security requirements (if IIS).
3.  **Validate**: Open internal URL. Verify "Tree View" and "Dashboard" load.

### Step 3: Configure Automation (Ops) - Feb 10
1.  **Task Scheduler**: Import `SimTreeNav-Dashboard-Update` task (or create manually).
    - **Action**: `pwsh.exe`
    - **Arguments**: `-File "C:\Scripts\SimTreeNav\scripts\ops\dashboard-task.ps1" -Config "prod-config.json"`
    - **Trigger**: Daily at 06:00 AM.
    - **User**: `SVC_SIMTREE_RO`
2.  **Manual Trigger**: Run the task once manually.
    - Check logs in `C:\Scripts\SimTreeNav\out\logs\`.

### Step 4: Verification (DBA + PM) - Feb 11
- **DBA**: Monitor Oracle sessions during 6 AM run. Confirm no locks or high IO.
- **PM**: Check Dashboard data freshness vs source system.

## Performance & Monitoring
- **Thresholds**:
  - Dashboard Gen Time: < 5 mins
  - Oracle Session Time: < 2 mins
- **Action**: If breaches > 3 days in a row, IT Ops notifies Dev.

## Rollback Plan (Emergency)
**Trigger**: Data corruption, site down, or massive performance drag on Oracle.
1.  **Disable Task**: Stop `SimTreeNav-Dashboard-Update` in Task Scheduler.
2.  **Revert HTML**: Delete `D:\Sites\SimTreeNav\*`, extract `SimTreeNav_PrePhase2.zip`.
3.  **Notify**: Email Stakeholders "Rolled back to Phase 1".

## Change Window Strategy
- **Code Freeze**: No merges to `main` 24h before deployment.
- **Maintenance**: Updates applied Tuesdays/Thursdays only, outside 06:00-18:00 window.

---
**Status**: DRAFT (Review required by IT Ops)
