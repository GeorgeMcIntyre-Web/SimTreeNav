# SimTreeNav Comprehensive Test Plan

## Test Overview

**Purpose:** Validate the complete integrated system (Credential Management + Icon/Tree Fixes)

**Test Environment:**
- Windows 10/11 workstation
- Oracle 12c client installed
- PowerShell 5.1 or later
- Oracle database access (des-sim-db1)

**Prerequisites:**
- Oracle environment variables set (`ORACLE_HOME`, `TNS_ADMIN`)
- TNS names configured
- Network access to database server
- User account with database read permissions

---

## Test Categories

1. **Unit Tests** - Individual components
2. **Integration Tests** - Component interactions
3. **End-to-End Tests** - Complete workflows
4. **Security Tests** - Credential protection
5. **Performance Tests** - Response times
6. **Regression Tests** - Existing functionality
7. **User Acceptance Tests** - Real-world scenarios

---

## 1. Unit Tests

### 1.1 PC Profile Manager

#### Test 1.1.1: Create New Profile
**Steps:**
1. Run `.\src\powershell\database\Initialize-PCProfile.ps1`
2. Enter profile name: "Test-Profile-001"
3. Add server: "des-sim-db1"
4. Add instance: "db01", TNS: "DB01"
5. Set as default: Yes

**Expected:**
- Profile created successfully
- JSON file updated
- Profile appears in list

**Pass Criteria:** ✅ Profile exists in `config/pc-profiles.json`

#### Test 1.1.2: Get Current Profile
**Steps:**
```powershell
Import-Module .\src\powershell\utilities\PCProfileManager.ps1
$profile = Get-CurrentPCProfile
Write-Host $profile.name
```

**Expected:** Current profile name displayed
**Pass Criteria:** ✅ Returns valid profile object

#### Test 1.1.3: Switch Profile
**Steps:**
```powershell
Set-CurrentPCProfile -ProfileName "Test-Profile-001"
$current = Get-CurrentPCProfile
```

**Expected:** Profile switched successfully
**Pass Criteria:** ✅ `$current.name` equals "Test-Profile-001"

#### Test 1.1.4: Update Last Used
**Steps:**
```powershell
Update-PCProfileLastUsed -ProfileName "Test-Profile-001" `
    -Server "des-sim-db1" `
    -Instance "db01" `
    -Schema "DESIGN12" `
    -ProjectId "18140190" `
    -ProjectName "FORD_DEARBORN"
```

**Expected:** Last used timestamp updated
**Pass Criteria:** ✅ JSON contains lastUsed section

### 1.2 Credential Manager

#### Test 1.2.1: Save Credentials (DEV Mode)
**Steps:**
1. Run `.\src\powershell\database\Initialize-DbCredentials.ps1`
2. Select mode: DEV
3. Enter TNS: "DB01"
4. Enter username: "sys"
5. Enter password: [actual password]

**Expected:**
- Encrypted XML file created
- File location: `config/.credentials/[hostname]_[user]_DB01.xml`

**Pass Criteria:** ✅ File exists and is encrypted

#### Test 1.2.2: Retrieve Credentials (Cached)
**Steps:**
```powershell
Import-Module .\src\powershell\utilities\CredentialManager.ps1
$connStr = Get-DbConnectionString -TNSName "DB01" -AsSysDBA
Write-Host $connStr
```

**Expected:** Connection string returned without prompting
**Pass Criteria:** ✅ No password prompt, connection string contains password

#### Test 1.2.3: Test Database Connection
**Steps:**
```powershell
$result = Test-DbConnection -TNSName "DB01" -AsSysDBA
```

**Expected:** Returns `$true` if connection successful
**Pass Criteria:** ✅ Connection succeeds

#### Test 1.2.4: Remove Credentials
**Steps:**
```powershell
.\src\powershell\database\Remove-DbCredentials.ps1
```
Select TNS: "DB01"

**Expected:** Credential file deleted
**Pass Criteria:** ✅ File no longer exists

### 1.3 Icon Extraction

#### Test 1.3.1: Extract Database Icons
**Steps:**
```powershell
# Run icon extraction portion of generate-tree-html.ps1
# Check output for extracted TYPE_IDs
```

**Expected:**
- Icons extracted from `DF_ICONS_DATA`
- Base64 data URIs created
- Fallback icons added for missing TYPE_IDs

**Pass Criteria:** ✅ Icon count > 0, includes fallbacks

#### Test 1.3.2: Custom Icon Directory (Post-Merge)
**Steps:**
1. Create test directory: `C:\test-icons`
2. Place BMP file: `icon_999.bmp`
3. Set custom icon directory in launcher
4. Generate tree

**Expected:** Custom icon loaded for TYPE_ID 999
**Pass Criteria:** ✅ Icon appears in HTML

#### Test 1.3.3: Icon Fallback Logic
**Steps:**
1. Generate tree for project with TYPE_ID 72 (StudyFolder)
2. Verify DF_ICONS_DATA doesn't have TYPE_ID 72
3. Check HTML for TYPE_ID 72 icon

**Expected:** Falls back to TYPE_ID 18 (Collection parent)
**Pass Criteria:** ✅ Icon displays correctly

---

## 2. Integration Tests

### 2.1 Launcher + PC Profile + Credentials

#### Test 2.1.1: First-Time Setup
**Steps:**
1. Delete all config files
2. Run `.\src\powershell\main\tree-viewer-launcher.ps1`
3. Follow prompts to create profile
4. Enter credentials when prompted
5. Select schema and generate tree

**Expected:**
- Profile created
- Credentials saved
- Tree generated successfully

**Pass Criteria:** ✅ Complete workflow without errors

#### Test 2.1.2: Subsequent Launch (Cached Credentials)
**Steps:**
1. Run `.\src\powershell\main\tree-viewer-launcher.ps1`
2. Select server/instance
3. Select schema

**Expected:** No password prompt
**Pass Criteria:** ✅ Credentials auto-retrieved

### 2.2 Tree Generation + Icon Loading

#### Test 2.2.1: Generate Tree with All Features
**Steps:**
```powershell
.\src\powershell\main\generate-tree-html.ps1 `
    -TNSName "DB01" `
    -Schema "DESIGN12" `
    -ProjectId "18140190" `
    -ProjectName "FORD_DEARBORN"
```

**Expected:**
- Credentials auto-loaded
- Icons extracted (DB + fallbacks)
- Tree data extracted
- User activity extracted
- HTML generated
- Browser opens

**Pass Criteria:** ✅ HTML displays complete tree with icons

#### Test 2.2.2: Verify All Node Types (Post-Merge)
**Expected Node Types:**
- ✅ PmProject (root)
- ✅ PmCollection
- ✅ PmPartLibrary
- ✅ PmMfgLibrary
- ✅ RobcadResourceLibrary
- ✅ PmStudyFolder
- ✅ RobcadStudy
- ✅ ToolPrototype *(after merge)*
- ✅ ToolInstance *(after merge)*

**Pass Criteria:** All node types appear in tree

### 2.3 Security Integration

#### Test 2.3.1: Credential Isolation
**Steps:**
1. Save credentials as User A
2. Log out
3. Log in as User B
4. Try to access User A's credentials

**Expected:** User B cannot decrypt User A's credentials
**Pass Criteria:** ✅ Access denied or decryption fails

#### Test 2.3.2: Git Ignore Validation
**Steps:**
```powershell
git status
```

**Expected:** No sensitive files in untracked/staged list
**Pass Criteria:** ✅ No `.xml`, `config/*.json` files shown

---

## 3. End-to-End Tests

### 3.1 Complete Workflow (Clean Environment)

#### Test 3.1.1: New User Setup
**Scenario:** New user on fresh workstation

**Steps:**
1. Clone repository
2. Run `.\scripts\Setup-OracleConnection.ps1`
3. Run `.\src\powershell\database\Initialize-PCProfile.ps1`
   - Create profile "MyWorkstation"
   - Add server "des-sim-db1", instance "db01", TNS "DB01"
4. Run `.\src\powershell\database\Initialize-DbCredentials.ps1`
   - Select DEV mode
   - Enter DB01 credentials
5. Run `.\src\powershell\main\tree-viewer-launcher.ps1`
   - Select profile (auto-selected if only one)
   - Select server/instance (auto-selected if only one)
   - Select schema: DESIGN12
   - Load tree for FORD_DEARBORN

**Expected:**
- ✅ Oracle environment configured
- ✅ Profile created and saved
- ✅ Credentials encrypted and stored
- ✅ Tree generated with all features
- ✅ HTML opens in browser
- ✅ Icons display correctly
- ✅ Checkout status shows (if any)

**Pass Criteria:** Complete workflow succeeds without manual intervention

### 3.2 Multi-Instance Workflow

#### Test 3.2.1: Switch Between Instances
**Steps:**
1. Launch tree viewer
2. Select server "des-sim-db1", instance "db01"
3. Generate tree
4. Exit
5. Re-launch
6. Select server "des-sim-db1", instance "db02"
7. Generate tree

**Expected:**
- Different TNS names used (DB01 vs SIEMENS_PS_DB)
- Separate credentials if needed
- Trees from different instances

**Pass Criteria:** ✅ Both instances accessible

### 3.3 Error Recovery

#### Test 3.3.1: Invalid Credentials
**Steps:**
1. Enter wrong password
2. Try to generate tree

**Expected:**
- Connection fails
- Error message displayed
- Prompt to re-enter password

**Pass Criteria:** ✅ Graceful error handling

#### Test 3.3.2: Database Unavailable
**Steps:**
1. Disconnect from network
2. Try to generate tree

**Expected:**
- TNS error
- Clear error message
- No crash

**Pass Criteria:** ✅ Handles network errors gracefully

---

## 4. Security Tests

### 4.1 Credential Storage

#### Test 4.1.1: File Permissions (DEV Mode)
**Steps:**
```powershell
Get-Acl config\.credentials\*
```

**Expected:** Files owned by current user only
**Pass Criteria:** ✅ No other users have access

#### Test 4.1.2: Encryption Validation
**Steps:**
1. Open encrypted XML file in text editor
2. Search for plaintext password

**Expected:** No plaintext password visible
**Pass Criteria:** ✅ Password is encrypted

#### Test 4.1.3: Cross-User Access
**Steps:**
1. Save credentials as User A
2. Switch to User B
3. Try to decrypt User A's file

**Expected:** Decryption fails
**Pass Criteria:** ✅ DPAPI prevents cross-user access

### 4.2 Git Security

#### Test 4.2.1: Sensitive Files Not Committed
**Steps:**
```powershell
git add .
git status
```

**Expected:** No sensitive files staged
**Pass Criteria:** ✅ `config/.credentials/`, `*.json` ignored

#### Test 4.2.2: Clean Repository
**Steps:**
```powershell
git ls-files --others --ignored --exclude-standard
```

**Expected:** All sensitive files listed
**Pass Criteria:** ✅ All credential files ignored

---

## 5. Performance Tests

### 5.1 Icon Extraction

#### Test 5.1.1: Large Icon Set
**Steps:**
1. Time icon extraction for full database
2. Measure:
   - Query execution time
   - Hex to Base64 conversion time
   - Total time

**Expected:**
- Query: < 5 seconds
- Conversion: < 2 seconds
- Total: < 10 seconds

**Pass Criteria:** ✅ Extraction completes in reasonable time

### 5.2 Tree Generation

#### Test 5.2.1: Large Project Tree
**Steps:**
1. Generate tree for project with >5000 nodes
2. Measure:
   - Database query time
   - HTML generation time
   - Browser load time

**Expected:**
- Query: < 30 seconds
- Generation: < 10 seconds
- Load: < 5 seconds

**Pass Criteria:** ✅ Usable performance for large trees

### 5.3 Credential Retrieval

#### Test 5.3.1: Cache Hit Time
**Steps:**
```powershell
Measure-Command {
    Import-Module .\src\powershell\utilities\CredentialManager.ps1
    Get-DbConnectionString -TNSName "DB01" -AsSysDBA
}
```

**Expected:** < 100ms
**Pass Criteria:** ✅ Instant credential retrieval

---

## 6. Regression Tests

### 6.1 Verify Existing Functionality

#### Test 6.1.1: Original Tree Generation Still Works
**Steps:**
```powershell
# Use old-style command with manual password
sqlplus sys/password@DB01 as sysdba @get-tree.sql
```

**Expected:** Still functions as before
**Pass Criteria:** ✅ Backward compatible

#### Test 6.1.2: Existing HTML Features
**Test:**
- ✅ Expand/collapse nodes
- ✅ Search functionality
- ✅ Node IDs displayed
- ✅ Checkout status colors
- ✅ Icon display

**Pass Criteria:** All features working

---

## 7. User Acceptance Tests

### 7.1 Real-World Scenarios

#### Test 7.1.1: Daily Developer Workflow
**Scenario:** Developer checks project tree daily

**Steps:**
1. Morning: Launch tree viewer
2. Select last-used project (auto-remembered)
3. Generate tree
4. Afternoon: Check different schema
5. Evening: Check another project

**Expected:**
- No password prompts
- Fast launches (<5 sec)
- Remembered selections

**Pass Criteria:** ✅ Smooth daily workflow

#### Test 7.1.2: Multi-PC User
**Scenario:** User works from multiple workstations

**Steps:**
1. PC 1: Set up profile "pc1-profile"
2. PC 2: Set up profile "pc2-profile"
3. Switch between PCs
4. Profiles auto-select based on hostname

**Expected:**
- Each PC uses correct profile
- Separate credential caches
- No configuration conflicts

**Pass Criteria:** ✅ Multi-PC support works

#### Test 7.1.3: Team Lead Reviewing Projects
**Scenario:** Team lead reviews multiple projects

**Steps:**
1. Open tree for Project A
2. Review structure
3. Switch to Project B
4. Compare structures
5. Generate reports

**Expected:**
- Easy project switching
- Profile remembers last used
- Fast tree generation

**Pass Criteria:** ✅ Efficient multi-project workflow

---

## Test Execution Checklist

### Pre-Merge Tests (Credential System Only)
- [ ] 1.1 PC Profile Manager (all tests)
- [ ] 1.2 Credential Manager (all tests)
- [ ] 2.1 Launcher + PC Profile + Credentials
- [ ] 3.1 Complete Workflow (Clean Environment)
- [ ] 4.1 Credential Storage (all tests)
- [ ] 4.2 Git Security (all tests)
- [ ] 5.3 Credential Retrieval
- [ ] 6.1 Regression Tests

### Post-Merge Tests (Full Integration)
- [ ] 1.3 Icon Extraction (all tests)
- [ ] 2.2 Tree Generation + Icon Loading
- [ ] 2.3 Security Integration
- [ ] 3.2 Multi-Instance Workflow
- [ ] 3.3 Error Recovery
- [ ] 5.1 Icon Extraction Performance
- [ ] 5.2 Tree Generation Performance
- [ ] 7.1 User Acceptance Tests (all scenarios)

### Critical Path Tests (Must Pass)
- [ ] Test 3.1.1: New User Setup
- [ ] Test 2.1.2: Subsequent Launch (Cached Credentials)
- [ ] Test 2.2.1: Generate Tree with All Features
- [ ] Test 4.2.1: Sensitive Files Not Committed
- [ ] Test 7.1.1: Daily Developer Workflow

---

## Test Results Template

```markdown
## Test Execution Report

**Date:** [Date]
**Tester:** [Name]
**Environment:** [Windows Version, PowerShell Version]
**Branch:** [main | integration]

### Summary
- Total Tests: [X]
- Passed: [X]
- Failed: [X]
- Skipped: [X]
- Pass Rate: [X]%

### Failed Tests
| Test ID | Test Name | Error | Severity |
|---------|-----------|-------|----------|
| 1.2.3   | Test Connection | TNS Error | High |

### Notes
[Additional observations]

### Recommendations
[Actions to take]
```

---

## Automated Test Script (Optional)

```powershell
# test-all.ps1 - Run automated tests

param(
    [switch]$PreMerge,
    [switch]$PostMerge,
    [switch]$Quick
)

$results = @{
    Passed = 0
    Failed = 0
    Skipped = 0
}

function Test-Component {
    param($Name, $ScriptBlock)

    Write-Host "`nTesting: $Name" -ForegroundColor Cyan
    try {
        & $ScriptBlock
        Write-Host "  PASS" -ForegroundColor Green
        $script:results.Passed++
    } catch {
        Write-Host "  FAIL: $_" -ForegroundColor Red
        $script:results.Failed++
    }
}

# Unit Tests
if ($PreMerge -or -not $PostMerge) {
    Test-Component "PC Profile Manager" {
        Import-Module .\src\powershell\utilities\PCProfileManager.ps1
        $profile = Get-PCProfiles
        if (-not $profile) { throw "No profiles found" }
    }

    Test-Component "Credential Manager" {
        Import-Module .\src\powershell\utilities\CredentialManager.ps1
        # Test credential functions exist
        if (-not (Get-Command Get-DbConnectionString -ErrorAction SilentlyContinue)) {
            throw "CredentialManager not loaded"
        }
    }
}

# Integration Tests
if ($PostMerge) {
    Test-Component "Full Tree Generation" {
        $result = .\src\powershell\main\generate-tree-html.ps1 `
            -TNSName "DB01" `
            -Schema "DESIGN12" `
            -ProjectId "18140190" `
            -ProjectName "FORD_DEARBORN"

        if (-not (Test-Path "navigation-tree-DESIGN12-18140190.html")) {
            throw "HTML file not generated"
        }
    }
}

# Report
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed:  $($results.Passed)" -ForegroundColor Green
Write-Host "Failed:  $($results.Failed)" -ForegroundColor Red
Write-Host "Skipped: $($results.Skipped)" -ForegroundColor Yellow

$total = $results.Passed + $results.Failed
$passRate = if ($total -gt 0) { [math]::Round(($results.Passed / $total) * 100, 2) } else { 0 }
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 90) { "Green" } elseif ($passRate -ge 70) { "Yellow" } else { "Red" })
```

---

**Document Version:** 1.0
**Last Updated:** 2026-01-15
**Test Coordinator:** Claude Sonnet 4.5
