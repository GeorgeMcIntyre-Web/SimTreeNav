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

## Run Status Diagnostics

Every dashboard task run produces a `run-status.json` file in `out/json/` that provides detailed execution diagnostics.

### Location
```
C:\Scripts\SimTreeNav\out\json\run-status.json
```

### Quick Health Check
```powershell
# Check last run status
$status = Get-Content C:\Scripts\SimTreeNav\out\json\run-status.json | ConvertFrom-Json
Write-Host "Status: $($status.status)"
Write-Host "Exit Code: $($status.exitCode)"
Write-Host "Top Error: $($status.topError)"
```

### Field Reference

| Field | Description | Example |
|-------|-------------|---------|
| `status` | Overall run outcome | "success", "failed", "partial" |
| `exitCode` | Process exit code | 0 (success), 1 (failure), 2 (dependency), 3 (unknown) |
| `topError` | First critical error | "SQL*Plus not found" |
| `steps[]` | Execution timeline | Array of step objects |
| `durations.totalMs` | Total runtime | 45000 (45 seconds) |
| `logFile` | Full log path | "C:\...\dashboard-task.log" |

### Exit Code Meanings

- **0 (Success)**: All steps completed without errors
- **1 (Expected Failure)**: Business logic error, config issue, or data problem
  - Example: Config file not found, generator script failed
- **2 (Dependency Failure)**: Missing system dependency or permission
  - Example: SQL*Plus not in PATH, output directory not writable
- **3 (Unknown Error)**: Unexpected exception or system state
  - Example: Out of memory, corrupted file

### Troubleshooting by Exit Code

#### Exit Code 1 (Expected Failure)
1. Check `topError` field in run-status.json
2. Review step that failed (status: "failed")
3. Check detailed log file (path in `logFile` field)
4. Common fixes:
   - Fix config file path
   - Correct database credentials
   - Resolve data quality issues

#### Exit Code 2 (Dependency Failure)
1. Check `EnvironmentChecks` step in run-status.json
2. Verify SQL*Plus installation: `sqlplus -version`
3. Verify output directory permissions
4. Verify PowerShell version: `$PSVersionTable.PSVersion`
5. Common fixes:
   - Install Oracle Client
   - Grant write permissions to service account
   - Upgrade PowerShell to 7+

#### Exit Code 3 (Unknown Error)
1. Review full log file
2. Check system resources (disk space, memory)
3. Contact development team with:
   - run-status.json
   - Full log file
   - System event logs
