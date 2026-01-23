# Production Server Evidence Log

**Server**: ____________________
**Date**: ____________________
**Executor**: ____________________

**Instructions**:
Run the commands below on the production server.
**Copy/Paste** the exact output from the PowerShell console into the code blocks provided.
**Do NOT** use screenshots for console text.

## A. Structure Verification
Command: `dir D:\SimTreeNav; dir D:\SimTreeNav\scripts\ops`
```text
(Paste Output Here)
```

## B. Environment Smoke Test
Command: `pwsh D:\SimTreeNav\scripts\ops\validate-environment.ps1 -OutDir D:\SimTreeNav\out -Smoke`
```text
(Paste Output Here - Look for "Exit Code: 0" and "Validation Passed")
```

## C. Task Generation (Dry Run)
Command: `pwsh D:\SimTreeNav\scripts\ops\install-scheduled-tasks.ps1 -OutDir D:\SimTreeNav\out -HostRoot "D:\SimTreeNav"`
```text
(Paste Output Here - Should list generated XML files)
```

Command: `dir D:\SimTreeNav\out\ops\tasks`
```text
(Paste Output Here)
```

Command: `Select-String -Path D:\SimTreeNav\out\ops\tasks\SimTreeNav-DailyDashboard.xml -Pattern "D:\\SimTreeNav" -Context 0,2`
```text
(Paste Output Here - Confirm absolute paths match D:\SimTreeNav)
```

## D. Log Sanity
Command: `Get-ChildItem D:\SimTreeNav\out\logs | Sort-Object LastWriteTime -Descending | Select-Object -First 3`
```text
(Paste Output Here)
```

## E. Manual Run (Optional)
Command: `pwsh D:\SimTreeNav\scripts\ops\dashboard-task.ps1 -Mode Daily -OutDir D:\SimTreeNav\out`
```text
(Paste Output Here)
```

## Sign-Off
[ ] All checks passed
[ ] No errors in logs
[ ] Secrets were NOT exposed in output

**Operator Signature**: ____________________
