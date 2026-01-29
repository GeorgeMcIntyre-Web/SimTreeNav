# Local Development Guide

**Quick reference for running tests locally and understanding CI failures**

---

## Prerequisites

**Required:**
- PowerShell 7.0+ (`pwsh --version` to check)
- Git

**Optional (for full integration tests):**
- SQL*Plus (Oracle Client)
- Database connection details

---

## Running Tests Locally

### Quick Test Suite

Run all tests that CI runs:

```powershell
# 1. Legacy unit tests (RunStatus library)
pwsh test/integration/Test-RunStatus.ps1

# 2. Pester tests with code coverage
pwsh test/unit/Invoke-CoverageTests.ps1

# 3. Integration smoke test (skip full Oracle run)
pwsh test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out -SkipFullRun

# 4. Secret scanner
bash scripts/security/scan-secrets.sh
```

**Expected time:** 30-60 seconds total

### Individual Test Categories

#### Unit Tests (Library Functions)

```powershell
# Legacy format tests
pwsh test/integration/Test-RunStatus.ps1

# Output: test/integration/results/test-runstatus.json
# Look for: "status": "pass"
```

#### Code Coverage Tests

```powershell
# Run with coverage report
pwsh test/unit/Invoke-CoverageTests.ps1

# Run in CI mode with threshold
pwsh test/unit/Invoke-CoverageTests.ps1 -CI -CoverageThreshold 70

# Output: test/unit/results/coverage-summary.json
# Look for: "percentCoverage": 70+
```

#### Integration Tests

```powershell
# Smoke test (no database required)
pwsh test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out -SkipFullRun

# Full test (requires Oracle)
pwsh test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out

# Output: test/integration/results/test-release-smoke.json
# Look for: "status": "pass", "issues": []
```

#### Secret Scan

```bash
# Run secret scanner
bash scripts/security/scan-secrets.sh

# Check exit code
echo $?  # Should be 0 for success
```

---

## Reading Test Failures

### Test Result Files

All tests produce JSON result files:

| Test Type | Result File | Success Indicator |
|-----------|-------------|-------------------|
| Legacy Unit | `test/integration/results/test-runstatus.json` | `"status": "pass"` |
| Integration | `test/integration/results/test-release-smoke.json` | `"status": "pass"` |
| Coverage | `test/unit/results/coverage-summary.json` | `"percentCoverage": 70+` |

### Reading Test JSONs

**Example failure:**

```json
{
  "test": "test-runstatus",
  "startedAt": "2026-01-29T10:30:00",
  "status": "fail",
  "issues": [
    "New-RunStatus did not create file at /tmp/test-guid/run-status.json",
    "Schema missing required field: exitCode"
  ],
  "endedAt": "2026-01-29T10:30:02"
}
```

**How to read:**
- `status`: `"pass"` or `"fail"`
- `issues[]`: Array of failure reasons (empty if passing)
- Look at the first issue - usually the root cause

### Common Failure Patterns

#### 1. Missing Directories

**Symptom:**
```
Cannot create file: Directory 'out/json' does not exist
```

**Fix:**
```powershell
mkdir -p out/logs out/json test/integration/results test/unit/results
```

**Why:** Tests expect output directories to exist before writing results.

#### 2. PowerShell Version

**Symptom:**
```
Test-PowerShellVersion: PowerShell 5.1 is insufficient. Requires version 7 or higher.
```

**Fix:**
```powershell
# Install PowerShell 7
winget install Microsoft.PowerShell
# Or download from: https://github.com/PowerShell/PowerShell/releases
```

**Why:** Library functions use PowerShell 7+ features.

#### 3. Pester Not Installed

**Symptom:**
```
Module 'Pester' not found
```

**Fix:**
```powershell
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
```

**Why:** Code coverage requires Pester 5+. The coverage script auto-installs it, but you can install manually.

#### 4. Path Separators (Windows vs Linux)

**Symptom:**
```
Cannot find path: out\logs\test.log
```

**Fix:** Use `Join-Path` in PowerShell:
```powershell
$logPath = Join-Path $OutDir "logs" "test.log"
```

**Why:** Windows uses `\`, Linux uses `/`. `Join-Path` handles both.

#### 5. Coverage Below Threshold

**Symptom:**
```
❌ Coverage (65.2%) below threshold (70%)
```

**Fix:** Add tests for uncovered code:
```powershell
# Check which functions need tests
cat test/unit/results/coverage-summary.json | ConvertFrom-Json | Select-Object -ExpandProperty fileDetails

# Add tests to test/unit/*.Tests.ps1
```

**Why:** CI enforces minimum coverage for library functions (informational only currently).

#### 6. Secret Scanner Failures

**Symptom:**
```
❌ HIGH RISK: config/prod.env
3:DB_PASSWORD=MySecretPassword
```

**Fix:**
1. Remove the hardcoded secret immediately
2. Add file to `.gitignore`
3. Rotate the exposed credential
4. Use environment variables: `$env:DB_PASSWORD`

**Why:** Hardcoded secrets in config files are security vulnerabilities.

---

## Understanding CI Failures

### GitHub Actions UI

**When CI fails:**

1. Go to your PR → "Checks" tab
2. Click the failing job (red X)
3. Expand the failing step
4. Look for colored output:
   - 🔴 Red = Error/Failure
   - 🟡 Yellow = Warning
   - 🟢 Green = Success

### CI Job Structure

```
Run Smoke Tests
├── Checkout code ✅
├── Verify PowerShell version ✅
├── Create output directories ✅
├── Run unit tests (RunStatus library) ❌ ← Failed here
├── Run library coverage tests ⏭️ Skipped
├── Run integration smoke test ⏭️ Skipped
└── Upload test results ✅ Always runs
```

**Failure cascades:** If step 4 fails, steps 5-6 are skipped, but artifacts still upload.

### Downloading Test Results

**From GitHub Actions:**

1. Go to PR → "Checks" tab → Click failed job
2. Scroll to bottom → "Artifacts" section
3. Download `test-results` artifact
4. Extract ZIP file
5. Open `test/integration/results/*.json` or `test/unit/results/*.json`

**What you'll find:**
- `test-runstatus.json` - Unit test results with issues array
- `test-release-smoke.json` - Integration test results
- `coverage-summary.json` - Per-file coverage percentages
- `test-results.xml` - NUnit format (for CI tools)
- `coverage.xml` - JaCoCo format (for CI tools)

### Reading CI Logs

**Good log output:**

```
=== RunStatus Library Unit Tests ===
Temp directory: /tmp/test-runstatus-a1b2c3d4

Test 1: New-RunStatus creates file...
PASS: File created at /tmp/test-runstatus-a1b2c3d4/run-status.json

Test 2: Validate initial schema...
PASS: Schema valid

...

=== Test Summary ===
Status: PASS
Report: test/integration/results/test-runstatus.json

All tests passed!
```

**Bad log output:**

```
=== RunStatus Library Unit Tests ===

Test 1: New-RunStatus creates file...
FAIL: New-RunStatus did not create file at /tmp/test/run-status.json

Test 2: Validate initial schema...
FAIL: Cannot read file: /tmp/test/run-status.json does not exist

...

=== Test Summary ===
Status: FAIL
Report: test/integration/results/test-runstatus.json

Issues found:
  - New-RunStatus did not create file at /tmp/test/run-status.json
  - Cannot read file: /tmp/test/run-status.json does not exist

Process completed with exit code 1.
```

**Analysis:** Test 1 failed, causing Test 2 to fail (dependency). Fix the file creation issue first.

---

## Debugging Workflow

### Step-by-Step Debugging

**1. Reproduce locally**
```powershell
# Run the exact command that failed in CI
pwsh test/integration/Test-RunStatus.ps1
```

**2. Check for environment differences**
```powershell
# PowerShell version
$PSVersionTable.PSVersion

# Current directory
Get-Location

# Directory structure
ls out/
ls test/integration/results/
```

**3. Run with verbose output**
```powershell
# Add -Verbose flag if supported
pwsh test/integration/Test-RunStatus.ps1 -Verbose

# Or use Write-Host debugging
```

**4. Inspect result files**
```powershell
# Pretty-print JSON results
cat test/integration/results/test-runstatus.json | ConvertFrom-Json | ConvertTo-Json -Depth 5
```

**5. Fix and re-test**
```powershell
# Fix the code
# Re-run the test
pwsh test/integration/Test-RunStatus.ps1

# Verify success
echo $LASTEXITCODE  # Should be 0
```

### Common Debug Commands

```powershell
# Check if file exists
Test-Path ./out/json/run-status.json

# Read JSON file
Get-Content ./out/json/run-status.json -Raw | ConvertFrom-Json

# List all test results
Get-ChildItem -Recurse -Filter "*.json" test/

# Check PowerShell version
$PSVersionTable.PSVersion

# Test library function directly
. ./scripts/lib/RunStatus.ps1
$statusPath = New-RunStatus -OutDir ./out -ScriptName "debug.ps1"
cat $statusPath
```

---

## Pre-Commit Checklist

Before committing changes, run this checklist:

```powershell
# 1. Create output directories
mkdir -p out/logs out/json test/integration/results test/unit/results

# 2. Run all tests
pwsh test/integration/Test-RunStatus.ps1
pwsh test/unit/Invoke-CoverageTests.ps1
pwsh test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out -SkipFullRun

# 3. Run secret scanner
bash scripts/security/scan-secrets.sh

# 4. Check for unstaged changes
git status

# 5. If all pass, commit
git add .
git commit -m "Your commit message"
```

**Expected time:** 1-2 minutes

**All tests should pass locally before pushing to GitHub.**

---

## Quick Reference Card

| Task | Command | Expected Output |
|------|---------|-----------------|
| **Run unit tests** | `pwsh test/integration/Test-RunStatus.ps1` | "All tests passed!" |
| **Run coverage** | `pwsh test/unit/Invoke-CoverageTests.ps1` | "✅ All checks passed" |
| **Run integration** | `pwsh test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out -SkipFullRun` | "All tests passed!" |
| **Scan secrets** | `bash scripts/security/scan-secrets.sh` | "✅ PASSED: No secrets detected" |
| **Check PS version** | `pwsh --version` | "PowerShell 7.x.x" |
| **Install Pester** | `Install-Module -Name Pester -Force -Scope CurrentUser` | (No output if successful) |
| **Create directories** | `mkdir -p out/logs out/json test/integration/results test/unit/results` | (Directories created) |
| **View test results** | `cat test/integration/results/test-runstatus.json` | JSON with "status": "pass" |
| **View coverage** | `cat test/unit/results/coverage-summary.json` | JSON with "percentCoverage" |

---

## Getting Help

### Troubleshooting Resources

1. **ACCEPTANCE.md** - CI acceptance criteria and failure triage
2. **PRODUCTION_RUNBOOK.md** - Operational procedures
3. **Test result JSONs** - `test/*/results/*.json` files
4. **CI logs** - GitHub Actions → PR → Checks → Download artifacts

### Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| "Tests pass locally but fail in CI" | Check PowerShell version, directory paths, environment variables |
| "Coverage is lower in CI" | Ensure all test files are committed (check `git status`) |
| "Secret scanner finds false positives" | Use placeholders like `CHANGEME`, `<YOUR_KEY_HERE>`, or `null` |
| "Can't install Pester" | Use `Install-Module -Force -SkipPublisherCheck -Scope CurrentUser` |
| "Test output not found" | Create directories first: `mkdir -p out/logs out/json test/*/results` |

### Still Stuck?

1. Check test result JSON files for detailed error messages
2. Run tests with `-Verbose` flag
3. Compare local environment to CI environment
4. Review recent commits that might have broken tests
5. Check ACCEPTANCE.md for failure triage decision tree

---

**Last Updated:** 2026-01-29 (Friday)
