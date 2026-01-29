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

## CI Failure Triage

When GitHub Actions CI fails on a pull request, follow this triage process to quickly identify and fix issues.

### Quick Triage Steps

1. **Check which job failed** - Look at the PR checks status
2. **Download artifacts** - Get test results for offline analysis
3. **Identify root cause** - Follow job-specific troubleshooting
4. **Fix and re-run** - Push fix or re-run checks

### Job-Specific Troubleshooting

#### Run Smoke Tests Failed ❌

**What to check first:**
```bash
# 1. View PR checks and click "Run Smoke Tests" job
# 2. Look for which test failed (Test 1-6 for RunStatus, Test 1-5 for ReleaseSmoke)
# 3. Download "test-results" artifact from PR
# 4. Open test/integration/results/test-runstatus.json or test-release-smoke.json
```

**Common issues:**
- **Missing directory**: CI needs `out/`, `out/logs/`, `out/json/` created before tests run
- **Path separator mismatch**: Windows uses `\`, Linux uses `/` - use `Join-Path` for cross-platform
- **Environment variables**: `$env:COMPUTERNAME` doesn't exist on Linux - use `hostname` command
- **Temp directory**: `$env:TEMP` is empty on Linux - use `[System.IO.Path]::GetTempPath()`
- **Full run expected**: Test assumes Oracle - use `-SkipFullRun` parameter in CI

**How to fix:**
```powershell
# Run tests locally to reproduce
pwsh test/integration/Test-RunStatus.ps1
pwsh test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out -SkipFullRun

# Check test results JSON for specific issues
$results = Get-Content test/integration/results/test-runstatus.json | ConvertFrom-Json
$results.issues  # Array of failure reasons
```

#### Scan for Secrets Failed ❌

**What to check first:**
```bash
# 1. Click "Scan for Secrets" job in PR checks
# 2. Look at grep output showing matched patterns
# 3. Determine if real secret or false positive
```

**Common issues:**
- **Real secret detected**: Password, token, or API key in code
- **False positive**: Documentation mentioning "password" as a concept
- **Config template**: Template file with placeholder like `<YOUR_PASSWORD_HERE>`

**How to fix:**

If **real secret**:
```bash
# 1. Remove secret from code immediately
# 2. Add to .gitignore to prevent re-commit
# 3. Rotate credentials (change password/token)
# 4. Use Windows Credential Manager or config template instead
```

If **false positive**:
```bash
# 1. Add file to exclusion list in .github/workflows/ci-smoke-test.yml
# 2. Or add pattern to .secretsignore
# 3. Document why it's safe in PR comments
```

#### Artifacts Not Uploaded ⚠️

**What to check first:**
```bash
# 1. Check "Upload test results" step in job logs
# 2. Look for "No files were found" warning
# 3. Verify tests actually ran and produced output
```

**Common issues:**
- **Test didn't run**: Earlier step failed before tests executed
- **Output path wrong**: Artifact path doesn't match where tests write files
- **Directory not created**: Tests expect `out/` to exist before running

**How to fix:**
```yaml
# Ensure tests create output directories
# In test scripts:
New-Item -ItemType Directory -Path "out/logs" -Force
New-Item -ItemType Directory -Path "test/integration/results" -Force
```

### Reading Test Results Offline

After downloading the `test-results` artifact from a failed PR:

```powershell
# Extract artifact ZIP
Expand-Archive test-results.zip -DestinationPath ./test-results

# Read test results
$runStatus = Get-Content ./test-results/test/integration/results/test-runstatus.json | ConvertFrom-Json
$smokeTest = Get-Content ./test-results/test/integration/results/test-release-smoke.json | ConvertFrom-Json

# Check for failures
if ($runStatus.status -eq "fail") {
    Write-Host "RunStatus test failed:"
    $runStatus.issues | ForEach-Object { Write-Host "  - $_" }
}

if ($smokeTest.status -eq "fail") {
    Write-Host "Smoke test failed:"
    $smokeTest.issues | ForEach-Object { Write-Host "  - $_" }
}

# Check run-status.json from actual dashboard run (if present)
if (Test-Path ./test-results/out/json/run-status.json) {
    $dashStatus = Get-Content ./test-results/out/json/run-status.json | ConvertFrom-Json
    Write-Host "Dashboard exit code: $($dashStatus.exitCode)"
    Write-Host "Dashboard error: $($dashStatus.topError)"
}
```

### Re-running Failed Checks

**Option 1: Re-run from GitHub UI**
1. Go to PR page
2. Click "Checks" tab
3. Click "Re-run all jobs" (if transient failure)

**Option 2: Push empty commit** (if need to trigger fresh run)
```bash
git commit --allow-empty -m "Trigger CI re-run"
git push
```

**Option 3: Fix and push** (if code needs changes)
```bash
# Make fixes
git add .
git commit -m "Fix CI: <description>"
git push
```

### Prevention Checklist

Before pushing code, run these locally:

```powershell
# 1. Run all tests
pwsh test/integration/Test-RunStatus.ps1
pwsh test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out -SkipFullRun

# 2. Check for secrets
grep -rni -E "password\s*=|token\s*=" . --exclude-dir=.git --exclude="*.ps1" --exclude="*.sql"

# 3. Verify cross-platform code
# - No $env:COMPUTERNAME (use hostname)
# - No $env:TEMP (use [System.IO.Path]::GetTempPath())
# - No $env:USERNAME (use $env:USER on Linux)
# - Use Join-Path instead of string concatenation for paths
```

### Escalation

If CI fails repeatedly and cause is unclear:

1. **Check Actions logs** - Full workflow run logs in GitHub Actions tab
2. **Review recent changes** - Compare with last passing commit
3. **Test in clean environment** - Clone repo fresh, run tests
4. **Check for platform issues** - Compare Windows vs Linux behavior
5. **Contact maintainer** - Provide:
   - PR link
   - Downloaded test-results artifact
   - Local test results (if different from CI)
   - Error message screenshots

### Related Documentation

- [CI Acceptance Criteria](ACCEPTANCE.md) - What "green CI" means
- [Contributing Guide](../CONTRIBUTING.md) - PR workflow and standards
- [Workflow File](.github/workflows/ci-smoke-test.yml) - CI configuration

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
