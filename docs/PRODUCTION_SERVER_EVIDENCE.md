# Production Server Evidence Log

**Server**: ____________________
**Date**: ____________________
**Executor**: ____________________

This document captures the raw output of the production deployment verification steps.
**Status**: [ ] AWAITING IT OUTPUTS

## 1. Environment Validation
Command: `pwsh D:\SimTreeNav\scripts\ops\validate-environment.ps1 -OutDir D:\SimTreeNav\out -Smoke`
Output:
```text
(Paste raw output here)
```

## 2. Task Generation (Dry Run)
Command: `pwsh D:\SimTreeNav\scripts\ops\install-scheduled-tasks.ps1 -OutDir D:\SimTreeNav\out -HostRoot "D:\SimTreeNav"`
Output:
```text
(Paste raw output here)
```

## 3. Directory Listing (Tasks)
Command: `dir D:\SimTreeNav\out\ops\tasks`
Output:
```text
(Paste raw output here)
```

## 4. Manual Run (Optional)
Command: `pwsh D:\SimTreeNav\scripts\ops\dashboard-task.ps1 ...`
Output:
```text
(Paste raw output here)
```
