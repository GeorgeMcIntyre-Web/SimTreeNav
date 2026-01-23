# Go/No-Go Gate: SimTreeNav Production

**Date**: ___________
**Approvers**: IT Ops Lead, Product Owner (PM)

| Category | Item | Status (Pass/Fail) | Notes |
| :--- | :--- | :--- | :--- |
| **Infrastructure** | **Server Ready**: Hostname matches, OS is WinServer 2019+. | | |
| | **Path & ACLs**: `D:\SimTreeNav` exists, Service Account has WRITE to `/out`. | | |
| | **PowerShell**: Version 7.x installed and in PATH. | | |
| **Database** | **Connectivity**: `sqlplus` connects to PROD DB (ReadOnly). | | |
| | **Credentials**: Stored in WinCredMan (or approved secure method). | | |
| **Logic** | **Validation Script**: `validate-environment.ps1 -Smoke` returns Exit 0. | | |
| | **Tasks Generated**: XML files created successfully in Dry-Run. | | |
| | **Manual Test**: `dashboard-task.ps1` runs interactively without error (Optional). | | |
| **Process** | **Rollback Plan**: Backup verified, rollback steps understood. | | |
| | **Notification**: Users notified of potential maintenance window. | | |

**Decision**:
[ ] **GO** - Proceed to Apply Tasks
[ ] **NO-GO** - Resolving blocking issues first.

**Sign-off**:
IT Ops: ____________________
PM: ____________________
