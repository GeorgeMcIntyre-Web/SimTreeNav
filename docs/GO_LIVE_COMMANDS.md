# SimTreeNav - Go-Live Commands (Production / Option B)

**Objective:** Deploy SimTreeNav "Option B" to Production using the clean bundle.
**Prereq:** `SVC_SIMTREE_RO` account created, Oracle `SIM_CORE` accessible.

## 1. Copy Bundle
Copy the content of the `SimTreeNav` release folder to the destination root (e.g., `D:\SimTreeNav`).
```powershell
# From your staging/release drive
Copy-Item "Z:\Releases\SimTreeNav_v1.2" "D:\SimTreeNav" -Recurse
```

## 2. Configuration (NO SECRETS in Repo)
1. Rename template:
   ```powershell
   Rename-Item "D:\SimTreeNav\config\production.template.json" "production.json"
   ```
2. Edit `D:\SimTreeNav\config\production.json` with **Real Values**:
   - Host/Service for Oracle
   - Log paths (if different)
   - SMTP details

## 3. Validation (Dry Run)
Validate the environment is ready (permissions, ps version, time).
```powershell
cd D:\SimTreeNav
pwsh ./scripts/ops/validate-environment.ps1 -OutDir ./out -Smoke
```
*Expected: Exit Code 0, "Validation Passed"*

## 4. Generate Task Definitions
Create the Scheduled Task XML files for review.
```powershell
pwsh ./scripts/ops/install-scheduled-tasks.ps1 -OutDir ./out -HostRoot "D:\SimTreeNav"
```
*Expected: XML files in `D:\SimTreeNav\out\ops\tasks\`*

## 5. Apply Tasks (Go-Live)
Register the tasks in Windows Task Scheduler.
```powershell
pwsh ./scripts/ops/install-scheduled-tasks.ps1 -OutDir ./out -HostRoot "D:\SimTreeNav" -Apply -RunAsUser "CORP\SVC_SIMTREE_RO"
```
*Expected: Tasks registered successfully.*

## 6. Verification
- **Logs**: Check `D:\SimTreeNav\out\logs\`
- **Dashboard**: Open `\\<Server>\SimTreeNavShare\dashboard\index.html` (or IIS URL).

## Rollback
If critical failure occurs:
1. **Disable Tasks**:
   ```powershell
   Disable-ScheduledTask -TaskName "SimTreeNav-*"
   ```
2. **Revert Files**: Restore backup of `D:\SimTreeNav`.
