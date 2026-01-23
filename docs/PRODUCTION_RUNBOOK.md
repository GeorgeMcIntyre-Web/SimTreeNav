# Production Runbook for SimTreeNav

**Scope:** Operational maintenance and troubleshooting of SimTreeNav Phase 2.
**Audience:** IT Operations, Level 1 Support.

## Quick Checks (Is it working?)

Run these from the application server/task scheduler user context:

1.  **Check Output Age**:
    ```powershell
    # Should show recent files (today's date)
    Get-ChildItem D:\Sites\SimTreeNav\html\*.html | Select Name, LastWriteTime
    ```
2.  **Check Logs**:
    Open `C:\Scripts\SimTreeNav\out\logs\dashboard-task.log`. Look for "SUCCESS".
    ```powershell
    Get-Content -Tail 20 C:\Scripts\SimTreeNav\out\logs\dashboard-task.log
    ```
3.  **Run Smoke Probe**:
    ```powershell
    # Quick connectivity and permission check
    pwsh C:\Scripts\SimTreeNav\scripts\ops\dashboard-monitor.ps1 -Smoke
    ```

## Common Failures & Fixes

### 1. Oracle Connection Failed (ORA-12154 / TNS)
- **Symptom**: Log shows `ORA-12154: TNS:could not resolve the connect identifier`.
- **Cause**: `tnsnames.ora` missing or Env Var `TNS_ADMIN` not set.
- **Fix**:
  - Verify `Config/prod-config.json` has correct TNS alias or full connection string.
  - Test connectivity: `tnsping <SERVICE_NAME>`.

### 2. "SQL*Plus Not Found"
- **Symptom**: Script exits with "SQLPlus executable not specified or found".
- **Fix**: Ensure Oracle Client is installed and `sqlplus.exe` is in `%PATH%`.

### 3. File Lock / Permission Denied
- **Symptom**: `UnauthorizedAccessException` when writing `out/html`.
- **Cause**: IIS Worker Process might be locking files or User lacks Write perms.
- **Fix**:
  - Check ACLs on `D:\Sites\SimTreeNav`. Service Account needs `Modify`.
  - Check open handles: `Get-Process | Where-Object { $_.Path -like "*SimTreeNav*" }`.

### 4. Task Scheduler "0x1"
- **Symptom**: Task fails silently or exits with 1.
- **Fix**: Run the script manually in PowerShell as the Service Account to see output.
  ```powershell
  Start-Process pwsh -Credential (Get-Credential) -ArgumentList "-File ..."
  ```

## Recovery Steps

### Restarting the Cycle
If a daily run fails, you can safe-retry it manually:
```powershell
pwsh C:\Scripts\SimTreeNav\scripts\ops\dashboard-task.ps1 -Force
```

### Emergency Rollback
See `PRODUCTION_DEPLOYMENT_PLAN.md` -> "Rollback Plan".

## Log Format
Logs are located at `out/logs/`.
Format: `[yyyy-MM-dd HH:mm:ss] [LEVEL] Message`
Example:
```
[2026-02-10 06:01:05] [INFO] Starting Dashboard Generation
[2026-02-10 06:02:10] [ERROR] Oracle Connection Timeout
```
