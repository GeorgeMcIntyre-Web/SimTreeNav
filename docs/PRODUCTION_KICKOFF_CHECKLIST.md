# Production Kickoff Checklist

**Objective:** Validate that the environment is ready for Option B rollout (SimTreeNav) on Day 1.
**Roles:** IT Admin, DBA, Deployment Engineer.

## 1. Server & OS Prerequisites
- [ ] **Hostname**: Verify server hostname matches `production.json`.
  - Command: `hostname`
- [ ] **Time/Date**: Ensure server time is synchronized (NTP).
  - Command: `Get-Date`
- [ ] **PowerShell**: Verify PowerShell 7+ (pwsh) is installed.
  - Command: `pwsh --version`
- [ ] **Path Variables**: Ensure `pwsh` is in the system PATH.

## 2. Oracle Connectivity
- [ ] **Oracle Client**: Validate Oracle Instant Client (or full client) is installed.
  - Command: `sqlplus -version`
- [ ] **TNSNames**: Verify `tnsnames.ora` contains the target alias (PROD/SIMTREENAV).
  - Path: `%ORACLE_HOME%\network\admin\tnsnames.ora` OR `%TNS_ADMIN%\tnsnames.ora`
- [ ] **Connectivity Test**: Dry-run connection check (no schema changes).
  - Command: `sqlplus system/<password>@<TNS_ALIAS> @scripts/ops/check_connection.sql` (if available) or manual login.

## 3. Directory Structure & Permissions
- [ ] **Root Directory**: `D:\SimTreeNav` (or designated production root).
- [ ] **Permissions**:
  - [ ] Service Account has **Read/Execute** on `D:\SimTreeNav\scripts`.
  - [ ] Service Account has **Modify/Write** on `D:\SimTreeNav\out`.
  - [ ] Service Account has **Modify/Write** on `D:\SimTreeNav\logs`.

## 4. Hosting & Network
- [ ] **Network Share**: Verify map drive or UNC path if using File Share hosting.
  - Test: `Test-Path \\<server>\SimTreeNavShare`
- [ ] **IIS (Optional)**: If using IIS, verify site is stopped or pointing to maintenance page until cutover.
- [ ] **Firewall**: Ensure port 1521 (Oracle) is open outbound from this server.

## 5. Artifacts & Code
- [ ] **Repo State**: Repo is cloned/pulled to `production` branch (or tag).
  - Command: `git status`
- [ ] **Config**: `config/production.json` exists and contains correct values (no secrets in repo, file created manually or via secure process).

## 6. Smoke Test (Dry Run)
- [ ] **Environment Validation**:
  - Command: `pwsh ./scripts/ops/validate-environment.ps1 -Smoke`
  - Success: Exit code 0, "Validation Passed" in logs.
- [ ] **Task Generation**:
  - Command: `pwsh ./scripts/ops/install-scheduled-tasks.ps1 -OutDir ./out`
  - Success: XML files generated in `./out/ops/tasks`, no tasks registered.
