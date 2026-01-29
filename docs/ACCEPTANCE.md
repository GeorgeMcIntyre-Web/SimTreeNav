# CI Acceptance Criteria

**Purpose:** This document defines what "green CI" means for SimTreeNav and provides a checklist for pull request approval.

**Last Updated:** January 23, 2026

---

## Definition of "Green CI"

A pull request is considered to have **passing CI** when ALL of the following conditions are met:

### ✅ Required Jobs

All three CI jobs must complete with **exit code 0**:

1. **Run Smoke Tests** ✅
   - `test/integration/Test-RunStatus.ps1` - All 6 unit tests pass
   - `test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out -SkipFullRun` - All 5 integration tests pass
   - No PowerShell errors or exceptions
   - Exit code: 0

2. **Scan for Secrets** ✅
   - No hardcoded secrets detected (passwords, tokens, API keys)
   - Patterns checked: `password=`, `token=`, `api_key=`, `secret=` in assignment context
   - Excludes: `*.ps1`, `*.sql`, `*.md`, test fixtures
   - Exit code: 0

3. **Test Summary** ✅
   - Aggregates results from smoke tests and secrets scan
   - Only runs if both previous jobs succeed
   - Exit code: 0

### 📦 Required Artifacts

The workflow must upload artifacts even on failure:

| Artifact Name | Contents | Required |
|---------------|----------|----------|
| `test-results` | `test/integration/results/*.json`<br>`out/logs/*.log`<br>`out/json/run-status.json` | Yes |

**Upload Behavior:**
- `if-no-files-found: warn` - Log warning but don't fail if files missing
- Retention: 30 days
- Always upload, even on test failure

### 🔍 Failure Messaging

When a job fails, the workflow MUST provide:

1. **Clear error message** in job annotations
2. **Specific file/line number** where failure occurred (if applicable)
3. **Test results JSON** uploaded as artifact for offline analysis
4. **Logs** from `out/logs/` for debugging

Example good failure message:
```
Run Smoke Tests failed:
  Test 4: Validate run-status.json... FAIL
  Issue: run-status.json missing required field: exitCode
  See artifact 'test-results' for full test output
```

Example bad failure message:
```
Process completed with exit code 1.
```

---

## Pull Request Checklist

Use this checklist before requesting PR review:

### 🔧 Code Quality

- [ ] **All tests pass locally**
  ```powershell
  pwsh test/integration/Test-RunStatus.ps1
  pwsh test/integration/Test-ReleaseSmoke.ps1 -OutDir ./out -SkipFullRun
  ```

- [ ] **No hardcoded secrets**
  - No passwords, tokens, or API keys in code
  - Credentials use Windows Credential Manager or config templates
  - Check with: `grep -rni -E "password\\s*=|token\\s*=" . --exclude-dir=.git`

- [ ] **Code follows standards**
  - PowerShell: 4-space indentation (.editorconfig enforced)
  - Functions have comment-based help
  - Error handling uses `$ErrorActionPreference = "Stop"`

- [ ] **Files in correct locations**
  - Scripts: `scripts/lib/` (libraries), `scripts/ops/` (operations), `scripts/debug/` (debug)
  - Tests: `test/integration/` or `test/automation/`
  - Docs: `docs/` (active) or `docs/archive/` (historical)

### 🧪 Testing

- [ ] **Unit tests added/updated** (if modifying `scripts/lib/*.ps1`)
- [ ] **Integration tests pass** with `-SkipFullRun` (CI environment)
- [ ] **Test results uploaded** (check workflow artifacts)
- [ ] **No flaky tests** (run tests 3x locally, all pass)

### 📝 Documentation

- [ ] **README.md updated** (if changing user-facing features)
- [ ] **CHANGELOG.md updated** (if notable change)
- [ ] **Function help updated** (if changing parameters)
- [ ] **PRODUCTION_RUNBOOK.md updated** (if changing operations)

### 🔄 CI Workflow

- [ ] **GitHub Actions badge is green** on PR page
- [ ] **All three jobs passed** (Run Smoke Tests, Scan for Secrets, Test Summary)
- [ ] **Artifacts uploaded successfully** (check PR artifacts tab)
- [ ] **No warnings in workflow logs** (yellow warnings acceptable, red errors not)

### 🚨 Breaking Changes

If your PR introduces breaking changes:

- [ ] **Version bump** in relevant files
- [ ] **Migration guide** in PR description or docs
- [ ] **Backward compatibility** considered (can old configs still work?)
- [ ] **Stakeholders notified** before merge

---

## Secret Scan Rules

### ✅ What Gets Scanned

**File types checked:**
- `.env`, `.ini`, `.conf`, `.config`
- `.yml`, `.yaml` (workflow files)
- `.json` (config files)
- `.xml` (credential configs)

**Patterns detected:**
```bash
password\\s*=
password\\s*:
token\\s*=
token\\s*:
api_key\\s*=
api_key\\s*:
secret\\s*=
secret\\s*:
```

### ⏭️ What Gets Excluded

**File types excluded:**
- `*.ps1`, `*.psm1`, `*.psd1` (PowerShell code - strings like "password" are legitimate)
- `*.sql` (SQL scripts - strings like "token" are column names)
- `*.md` (Documentation - discusses credentials conceptually)

**Directories excluded:**
- `test/fixtures/` (Sample data, not real credentials)
- `docs/` (Documentation)
- `.git/` (Version control metadata)

### 🔐 Legitimate Exceptions

Some patterns are acceptable:

✅ **Config templates:**
```json
{
  "password": "<YOUR_PASSWORD_HERE>",
  "token": null
}
```

✅ **Placeholder values:**
```ini
DB_PASSWORD=CHANGEME
API_TOKEN=<replace-with-actual-token>
```

✅ **Test fixtures:**
```json
{
  "testUser": {
    "password": "fake-password-for-testing"
  }
}
```

❌ **NEVER ACCEPTABLE:**
```
DB_PASSWORD=MyRealPassword123!
API_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwxyz
```

---

## Failure Triage Quick Reference

When CI fails, follow this decision tree:

### 1️⃣ Test Failure (Run Smoke Tests)

**Symptom:** Red X on "Run Smoke Tests" job

**Triage steps:**
1. Click job to see which test failed
2. Download `test-results` artifact
3. Open `test/integration/results/test-runstatus.json` or `test-release-smoke.json`
4. Check `issues[]` array for specific failure reasons
5. Fix issue in code
6. Re-run tests locally before pushing fix

**Common causes:**
- Missing directory (`out/`, `out/logs/`, `out/json/`)
- File path mismatch (Windows `\\` vs Linux `/`)
- Cross-platform environment variable (`$env:COMPUTERNAME` vs `hostname`)
- Test assumes full Oracle environment (use `-SkipFullRun` in CI)

### 2️⃣ Secret Scan Failure (Scan for Secrets)

**Symptom:** Red X on "Scan for Secrets" job

**Triage steps:**
1. Click job to see matched patterns
2. Determine if it's a real secret or false positive
3. **If real secret:** Remove immediately, rotate credentials, add to `.gitignore`
4. **If false positive:** Add file to exclusion list in workflow or use `.secretsignore`

**Common false positives:**
- Documentation discussing "password" as a concept
- Variable names like `$passwordField`
- Test data with placeholder passwords

### 3️⃣ Artifact Upload Failure

**Symptom:** Warning "No files were found with the provided path"

**Triage steps:**
1. Check if test actually ran (look at job logs)
2. Verify output directories exist (`out/logs/`, `test/integration/results/`)
3. Check for typos in artifact paths
4. Ensure tests write results even on failure

**Expected behavior:**
- Tests should always produce result JSON files
- Logs should always be written to `out/logs/`
- Artifacts upload with warning is OK (doesn't fail PR)

### 4️⃣ Test Summary Failure

**Symptom:** Red X on "Test Summary" job

**This is a meta-failure:** It means one of the previous jobs failed. Fix the upstream job first.

---

## Workflow Trigger Rules

The CI workflow runs on:

### 🔀 Pull Request Events
```yaml
on:
  pull_request:
    branches: [ main ]
```

**When it runs:**
- Opening a new PR
- Pushing new commits to PR branch
- Re-running checks manually

**What it checks:**
- Changes in PR compared to `main`
- Full test suite (unit + integration smoke tests)
- Secret scan on all PR files

### 🚀 Push to Main Events
```yaml
on:
  push:
    branches: [ main ]
```

**When it runs:**
- Merging a PR to main
- Direct push to main (if allowed)

**What it checks:**
- Same as PR checks
- Ensures main branch is always green

---

## Acceptance Gates Summary

| Gate | Criteria | Failure Action |
|------|----------|----------------|
| **Unit Tests** | All 6 RunStatus tests pass | Block merge |
| **Integration Tests** | All 5 smoke tests pass | Block merge |
| **Secret Scan** | No hardcoded secrets detected | Block merge |
| **Artifacts** | Test results uploaded | Warn only |
| **Documentation** | PR description explains changes | Review guideline |
| **Code Review** | At least 1 approval | GitHub setting |

---

## Manager/Stakeholder View

**For non-technical reviewers:**

✅ **Green CI means:**
- All automated tests passed
- No security issues detected
- Code meets quality standards
- Safe to merge

❌ **Red CI means:**
- Something broke in the changes
- Developer must fix before merge
- Do not merge until green

🟡 **Yellow warnings are OK:**
- Usually minor issues (missing optional files)
- Developer can explain in PR comments
- Does not block merge

---

## Continuous Improvement

This acceptance criteria document should be updated when:

- New tests are added
- New quality gates are introduced
- False positive patterns are discovered
- Workflow behavior changes

**Review frequency:** Quarterly or after major CI changes

---

## Appendix: Example Workflow Runs

### ✅ Successful Run

```
✅ Run Smoke Tests (22s)
  ✅ Run unit tests (RunStatus library)
  ✅ Run integration smoke test
  ✅ Upload test results

✅ Scan for Secrets (6s)
  ✅ Scan for hardcoded secrets

✅ Test Summary (3s)
  ✅ Aggregate results
```

**Merge decision:** ✅ Approved - All gates passed

### ❌ Failed Run (Test Failure)

```
❌ Run Smoke Tests (18s)
  ✅ Run unit tests (RunStatus library)
  ❌ Run integration smoke test
     Error: Test 4 failed - run-status.json missing field
  ✅ Upload test results (artifact available)

⏭️ Scan for Secrets (skipped - depends on tests)
⏭️ Test Summary (skipped - depends on tests)
```

**Merge decision:** ❌ Blocked - Fix test failure first

### ❌ Failed Run (Secret Detected)

```
✅ Run Smoke Tests (22s)

❌ Scan for Secrets (8s)
  ❌ Scan for hardcoded secrets
     Error: Detected pattern 'password=' in config/prod.json:15

⏭️ Test Summary (skipped - depends on secrets scan)
```

**Merge decision:** ❌ Blocked - Remove secret, rotate credentials

---

**Questions?** See [CONTRIBUTING.md](CONTRIBUTING.md) or [docs/PRODUCTION_RUNBOOK.md](PRODUCTION_RUNBOOK.md)
