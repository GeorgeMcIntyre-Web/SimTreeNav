# Branch Merge Strategy

## Current Situation

### Branch 1: Credential Management System (This Work)
**Status:** ✅ Complete and tested
**Lead:** This conversation
**Files Modified:**
- `.gitignore` - Credential exclusions
- `src/powershell/main/generate-tree-html.ps1` - Credential integration
- `src/powershell/main/tree-viewer-launcher.ps1` - Updated to v2

**New Files Added:** 16 files
- 3 utility modules (CredentialManager, PCProfileManager, Update-AllScriptsWithCredManager)
- 3 database scripts (Initialize-PCProfile, Initialize-DbCredentials, Remove-DbCredentials)
- 2 setup scripts (Setup-OracleConnection, create-readonly-user.sql)
- 2 launcher files (tree-viewer-launcher-v2, backup)
- 4 documentation files
- 1 commit summary
- 1 update utility

### Branch 2: Icon/Tree Node Fixes (Other AI Work)
**Status:** 🔄 In progress
**Lead:** Codex/Claude (other conversation)
**Commit:** 1a2e583 ("Improve icon selection for missing DB icons")
**Files Modified:**
- `generate-full-tree-html.ps1` - Custom icon loading + fallback logic
- `generate-tree-html.ps1` - Missing icon reporting improvements
- `tree-viewer-launcher.ps1` - Custom icon directory menu option

**Current Work:**
1. Extending SQL to include ToolPrototype/ToolInstance tables
2. Implementing DB-only icon extraction with fast-fail for missing icons

## Potential Merge Conflicts

### High Risk - Same File Modified
**File:** `src/powershell/main/tree-viewer-launcher.ps1`
- **Branch 1 Changes:** Complete rewrite to v2 (PC Profile-based)
- **Branch 2 Changes:** Added custom icon directory menu option
- **Conflict Type:** Structural - different versions of the file

**Resolution Strategy:**
1. Accept Branch 1 version (v2 launcher with PC Profiles)
2. Manually port Branch 2's custom icon directory feature to v2 launcher
3. Add menu option in v2's interactive menu system

### Medium Risk - Same File Modified
**File:** `src/powershell/main/generate-tree-html.ps1`
- **Branch 1 Changes:** Lines 18-24, 73-78 (credential integration)
- **Branch 2 Changes:** Icon extraction logic, missing icon reporting
- **Conflict Type:** Different sections, may overlap

**Resolution Strategy:**
1. Compare both versions side-by-side
2. Merge credential changes (top of file)
3. Merge icon improvements (middle/bottom of file)
4. Test combined functionality

### Low Risk - Different Files
- No conflicts expected for utility modules, database scripts, or docs
- Branch 2's changes to `generate-full-tree-html.ps1` don't conflict with Branch 1

## Merge Order (Recommended)

### Step 1: Commit Branch 1 (Credentials)
```powershell
# Stage credential system files
git add .gitignore
git add src/powershell/database/
git add src/powershell/utilities/
git add src/powershell/main/tree-viewer-launcher.ps1
git add src/powershell/main/tree-viewer-launcher-v2.ps1
git add src/powershell/main/tree-viewer-launcher.ps1.backup
git add scripts/
git add docs/
git add COMMIT-SUMMARY-CREDENTIALS.md

# Commit
git commit -m "feat: Add secure credential management system with PC Profiles

- Implement CredentialManager with DEV/PROD modes
- Add PCProfileManager for multi-PC configurations
- Create interactive setup wizards
- Integrate with tree-viewer-launcher (v2)
- Add Oracle environment configuration
- Update generate-tree-html.ps1 with credential support
- Add comprehensive documentation

Co-authored-by: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

### Step 2: Wait for Branch 2 to Complete
- Let other AI finish ToolPrototype/ToolInstance SQL extensions
- Let other AI complete DB-only icon extraction changes
- Review their final commit

### Step 3: Merge Branch 2 Changes
```powershell
# Create integration branch
git checkout -b integrate-icon-fixes

# Cherry-pick icon fix commit (if from different branch)
git cherry-pick 1a2e583

# OR manually apply changes if needed
# Compare and merge:
# - generate-tree-html.ps1 (both modified)
# - generate-full-tree-html.ps1 (only Branch 2)
# - tree-viewer-launcher.ps1 (conflict - needs manual merge)
```

### Step 4: Resolve tree-viewer-launcher.ps1 Conflict
**Goal:** Add custom icon directory feature to v2 launcher

**Manual Steps:**
1. Open `tree-viewer-launcher-v2.ps1` (our v2 version)
2. Find the main menu section
3. Add new menu option: "Set Custom Icon Directory"
4. Implement function to set/persist custom icon path
5. Pass custom icon path to generate-tree-html.ps1

**New menu structure:**
```
Options:
  1. Select Server
  2. Select Schema
  3. Load Tree (includes checkout status)
  4. Set Custom Icon Directory
  5. Exit
```

### Step 5: Merge generate-tree-html.ps1
**Both branches modified this file:**

**Branch 1 Changes (Lines 18-78):**
- Added credential manager import (lines 18-24)
- Modified connection string logic (lines 73-78)

**Branch 2 Changes (Icon extraction section):**
- Enhanced icon extraction with fallback embedding
- Added custom icon directory support
- Improved missing icon reporting

**Merge Strategy:**
1. Keep Branch 1's credential imports at top
2. Integrate Branch 2's enhanced icon extraction logic
3. Keep Branch 1's credential connection logic
4. Ensure custom icon directory parameter is passed through

### Step 6: Test Combined System
```powershell
# Full integration test
.\src\powershell\main\tree-viewer-launcher.ps1

# Test workflow:
# 1. Select profile (credentials auto-loaded)
# 2. Select server/instance
# 3. Select schema
# 4. Set custom icon directory (new feature)
# 5. Load tree with full icon support
```

### Step 7: Final Commit
```powershell
git add .
git commit -m "feat: Integrate icon fixes with credential system

- Merge custom icon loading with PC Profile launcher
- Combine credential auto-load with enhanced icon extraction
- Add custom icon directory to v2 launcher menu
- Resolve conflicts in generate-tree-html.ps1
- Test full integrated workflow

Integrates: 1a2e583 (Improve icon selection for missing DB icons)
Co-authored-by: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

## Testing Checklist

After merge, verify:
- [ ] PC Profile selection works
- [ ] Credentials auto-load correctly
- [ ] Oracle environment variables set
- [ ] Custom icon directory can be set via menu
- [ ] Icon extraction pulls from DB + custom dirs
- [ ] Missing icons fall back correctly
- [ ] ToolPrototype/ToolInstance nodes appear (if SQL extended)
- [ ] Tree loads with all features working
- [ ] HTML opens in browser with correct icons

## Rollback Plan

If integration fails:
```powershell
# Abort merge
git merge --abort

# OR reset to credential commit
git reset --hard HEAD~1

# Rework integration
git checkout -b integration-rework
```

## Post-Merge Tasks

1. Update main README with combined features
2. Create unified CHANGELOG entry
3. Test on clean environment
4. Archive/delete temporary test files
5. Update documentation links

---

**Notes:**
- Keep both AI commit messages for attribution
- Test each step before proceeding
- Document any issues encountered
- Keep backup of working credential system
