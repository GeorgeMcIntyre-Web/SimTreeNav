# Task Scheduler Jobs Definition

This document defines the scheduled jobs for SimTreeNav. Use `scripts/ops/install-scheduled-tasks.ps1` to generate or apply these tasks.

## Default Configuration
- **RunAs**: Service Account (e.g., `CORP\SvcSimTreeOps`)
- **Working Directory**: `D:\SimTreeNav` (Production Root)
- **Log Path**: `D:\SimTreeNav\out\logs`

## Jobs

| Job Name | Trigger | Action (Script) | Arguments (Default) | Success Criteria |
| :--- | :--- | :--- | :--- | :--- |
| **SimTreeNav-DailyDashboard** | Daily @ 06:00 AM | `scripts/ops/dashboard-task.ps1` | `-Mode Daily` | Exit Code 0, `dashboard.json` updated |
| **SimTreeNav-Monitor** | Every 15 Mins | `scripts/ops/dashboard-monitor.ps1` | `-AlertOnly` | Exit Code 0, Email sent if alert |
| **SimTreeNav-WeeklyDigest** | Monday @ 07:00 AM | `scripts/ops/send-weekly-digest.ps1` | `-Recipients "Team"` | Exit Code 0, Email sent |
| **SimTreeNav-MonthlyReport** | 1st of Month @ 05:00 AM | `scripts/ops/generate-monthly-report.ps1` | `-Format HTML` | Exit Code 0, Report generated in `/reports` |

## Dry Run Mode
All scripts support a `-DryRun` or `-WhatIf` switch where applicable, or can be run safely in a read-only mode.
The `install-scheduled-tasks.ps1` script by default **ONLY** generates XML files for inspection and does not register tasks in the OS scheduler.

## Manual Execution
To manually run a job for testing:
```powershell
pwsh ./scripts/ops/dashboard-task.ps1 -Mode Daily -Verbose
```
Check `./out/logs` for execution details.
