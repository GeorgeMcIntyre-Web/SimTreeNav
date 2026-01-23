# IT Server Run Script (Production)

**Role**: IT Operations / Server Admin
**Goal**: Validate SimTreeNav deployment on the Production Server (`D:\SimTreeNav`) and capture evidence for Go-Live approval.
**Constraint**: **DO NOT** run any command with `-Apply` until explicitly authorized.

## Preparation
1.  **Log in** to the target server as the Service Account (or Admin).
2.  **Verify** `SimTreeNav_bundle.zip` has been verified (SHA256) and extracted to `D:\SimTreeNav`.
3.  **Verify** `D:\SimTreeNav\config\production.json` exists and has valid values (Database Host, SMTP).

## Execution Sequence

### A. Verify Bundle Structure
Run these commands to confirm file placement.
```powershell
dir D:\SimTreeNav
dir D:\SimTreeNav\scripts\ops
dir D:\SimTreeNav\config
dir D:\SimTreeNav\out
```

### B. Validate Environment (Smoke Test)
Checks Permissions, PowerShell Version, and Paths.
```powershell
pwsh D:\SimTreeNav\scripts\ops\validate-environment.ps1 -OutDir D:\SimTreeNav\out -Smoke
```
*Record the Exit Code (0 is Success) and the log file path.*

### C. Generate Task Scheduler XML (Dry Run)
Simulates task generation to confirm paths match the server environment.
```powershell
pwsh D:\SimTreeNav\scripts\ops\install-scheduled-tasks.ps1 -OutDir D:\SimTreeNav\out -HostRoot "D:\SimTreeNav"
```
Check outputs:
```powershell
dir D:\SimTreeNav\out\ops\tasks
```
Verify path logic (should show `D:\SimTreeNav` inside XML):
```powershell
Select-String -Path D:\SimTreeNav\out\ops\tasks\SimTreeNav-DailyDashboard.xml -Pattern "D:\\SimTreeNav" -Context 0,2
```

### D. Log Sanity Check
Confirm logs are being created and timestamped correctly.
```powershell
dir D:\SimTreeNav\out\logs
Get-ChildItem D:\SimTreeNav\out\logs | Sort-Object LastWriteTime -Descending | Select-Object -First 3
```
Read the latest log sample:
```powershell
Get-Content (Get-ChildItem D:\SimTreeNav\out\logs | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName -TotalCount 200
```

### E. Manual Dashboard Run (Optional/Advanced)
**STOP:** Only proceed if Oracle Credentials are securely stored and verified.
Run the daily dash generator purely to test database connectivity + HTML generation.
```powershell
pwsh D:\SimTreeNav\scripts\ops\dashboard-task.ps1 -Mode Daily -OutDir D:\SimTreeNav\out
```
*Verify output artifacts:*
```powershell
dir D:\SimTreeNav\out\html
dir D:\SimTreeNav\out\json
dir D:\SimTreeNav\out\zips
```

## Failure / Troubleshooting
If any step fails (Red text, Non-zero exit code):
1.  **Capture the full console output**.
2.  **List the logs**: `dir D:\SimTreeNav\out\logs`
3.  **Get content of the failure log**: `Get-Content D:\SimTreeNav\out\logs\<newest-log-file>.log`
4.  **Send** these items to the Development Team immediately.

## Completion
Once A-D (and optionally E) are complete, copy the output text and paste it into `PRODUCTION_SERVER_EVIDENCE.md` (or email it) to authorize the "Go-Live".
