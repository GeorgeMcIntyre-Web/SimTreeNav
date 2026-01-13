# Git Publication Checklist

Use this checklist to ensure the project is ready for publication to GitHub.

## Pre-Publication Checklist

### Repository Structure
- [x] Root directory is clean (only essential files)
- [x] Source code organized in `src/` directory
- [x] Documentation organized in `docs/` directory
- [x] Configuration templates in `config/` directory
- [x] SQL queries organized by category in `queries/`
- [x] Generated files in `data/` directory
- [x] Test files in `tests/` directory
- [x] Helper scripts in `scripts/` directory

### Essential Files
- [x] README.md exists and is comprehensive
- [x] LICENSE file present (MIT License)
- [x] .gitignore configured properly
- [x] CHANGELOG.md created
- [x] PROJECT-REORGANIZATION-SUMMARY.md present

### Code Organization
- [x] PowerShell scripts organized by function (main/utilities/database)
- [x] SQL queries categorized (icon-extraction, tree-navigation, analysis, investigation)
- [x] All paths are relative (not absolute)
- [x] No hard-coded credentials or sensitive data

### Documentation
- [x] Main README has quick start guide
- [x] Installation instructions clear
- [x] Usage examples provided
- [x] API documentation available
- [x] Investigation notes preserved

### Configuration
- [x] Template files provided (tnsnames.ora.template)
- [x] User-specific files gitignored (tnsnames.ora, *.json in config/)
- [x] No sensitive data in tracked files

### Git Configuration
- [x] .gitignore excludes generated files
- [x] .gitignore excludes user-specific configs
- [x] .gitignore excludes logs and temp files
- [x] .gitkeep files in empty directories

### Security
- [x] No credentials committed
- [x] Connection strings templated
- [x] User configs excluded
- [x] No sensitive database information

### Quality
- [x] Code follows consistent style
- [x] Scripts have clear naming
- [x] Documentation is up-to-date
- [x] Examples are working

## Publication Steps

### 1. Initialize Git Repository

```powershell
# Run the initialization script
.\scripts\init-git-repo.ps1

# Or manually:
git init
git add .
git commit -m "Initial commit: Siemens Process Simulation Tree Viewer"
```

**Status**: ⬜ Not started / ✅ Completed

### 2. Create GitHub Repository

1. Go to https://github.com/new
2. Fill in repository details:
   - **Name**: `siemens-process-simulation-tree-viewer` (or your choice)
   - **Description**: "PowerShell-based tree navigation viewer for Siemens Process Simulation Oracle databases with icon extraction and hierarchical visualization"
   - **Visibility**: Public or Private (your choice)
   - **Initialize**: ❌ Don't check any boxes (we already have README, LICENSE, .gitignore)
3. Click "Create repository"

**Status**: ⬜ Not started / ✅ Completed

### 3. Add Remote and Push

```powershell
# Add GitHub remote
git remote add origin https://github.com/YOUR-USERNAME/YOUR-REPO-NAME.git

# Verify remote
git remote -v

# Push to GitHub
git branch -M main
git push -u origin main
```

**Status**: ⬜ Not started / ✅ Completed

### 4. Verify on GitHub

Visit your repository URL and check:
- [x] README.md displays correctly on home page
- [x] Folder structure is organized
- [x] LICENSE is recognized
- [x] .gitignore is working (no generated files)
- [x] All links in README work

**Status**: ⬜ Not started / ✅ Completed

### 5. Configure Repository Settings

On GitHub, go to Settings:

**General**:
- [ ] Add topics/tags: `powershell`, `oracle`, `siemens`, `tree-viewer`, `process-simulation`
- [ ] Add website URL (if applicable)
- [ ] Update description if needed

**Features**:
- [ ] Enable/disable Wikis (optional)
- [ ] Enable Issues (recommended)
- [ ] Enable Discussions (optional)

**Security**:
- [ ] Enable Dependabot alerts (if available)
- [ ] Review branch protection rules

**Status**: ⬜ Not started / ✅ Completed

### 6. Add Badges to README (Optional)

Update README.md with dynamic badges:

```markdown
[![GitHub stars](https://img.shields.io/github/stars/USERNAME/REPO-NAME)](https://github.com/USERNAME/REPO-NAME/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/USERNAME/REPO-NAME)](https://github.com/USERNAME/REPO-NAME/network)
[![GitHub issues](https://img.shields.io/github/issues/USERNAME/REPO-NAME)](https://github.com/USERNAME/REPO-NAME/issues)
[![License](https://img.shields.io/github/license/USERNAME/REPO-NAME)](https://github.com/USERNAME/REPO-NAME/blob/main/LICENSE)
```

**Status**: ⬜ Not started / ✅ Completed

### 7. Create Release (Optional)

Create the first release (v1.0.0):

```powershell
# Tag the release
git tag -a v1.0.0 -m "Initial release: Full tree viewer with icon extraction"

# Push the tag
git push origin v1.0.0
```

On GitHub:
1. Go to "Releases"
2. Click "Create a new release"
3. Select tag `v1.0.0`
4. Title: "v1.0.0 - Initial Release"
5. Description: Copy from CHANGELOG.md
6. Click "Publish release"

**Status**: ⬜ Not started / ✅ Completed

## Post-Publication Tasks

### Documentation
- [ ] Add screenshot to README (docs/assets/tree-viewer-screenshot.png)
- [ ] Add animated GIF showing functionality
- [ ] Create GitHub Wiki (optional)
- [ ] Add examples section

### Community
- [ ] Add CONTRIBUTING.md guide
- [ ] Add CODE_OF_CONDUCT.md
- [ ] Add issue templates
- [ ] Add pull request template

### Maintenance
- [ ] Set up branch protection for main
- [ ] Configure automated tests (if applicable)
- [ ] Add CI/CD pipeline (optional)
- [ ] Monitor issues and PRs

## Verification Commands

### Check Git Status
```powershell
git status
git log --oneline -5
git remote -v
```

### Verify .gitignore
```powershell
git status --ignored
# Should show data/icons/, data/output/, etc. as ignored
```

### Check Repository Size
```powershell
Get-ChildItem -Recurse -File | Measure-Object -Property Length -Sum |
    Select-Object @{Name="Size (MB)"; Expression={"{0:N2}" -f ($_.Sum / 1MB)}}
```

### Count Files
```powershell
# Files tracked in Git
(git ls-files).Count

# Files ignored
(git status --ignored --short | Where-Object { $_ -match '!!' }).Count

# Total files in project
(Get-ChildItem -Recurse -File).Count
```

## Common Issues & Solutions

### Issue: Generated files being tracked
**Solution**:
```powershell
git rm -r --cached data/icons/ data/output/
git commit -m "Remove generated files from tracking"
```

### Issue: Large files warning
**Solution**:
- Ensure .gitignore excludes HTML outputs (already done)
- Use Git LFS for large binary files if needed

### Issue: Sensitive data accidentally committed
**Solution**:
```powershell
# Remove from history
git filter-branch --force --index-filter "git rm --cached --ignore-unmatch path/to/file" --prune-empty --tag-name-filter cat -- --all

# Force push (DANGEROUS - use only if necessary)
git push origin main --force
```

### Issue: Links broken in README
**Solution**:
- Use relative paths: `[doc](docs/file.md)` not `[doc](/docs/file.md)`
- Test all links after publishing

## Success Criteria

✅ **Ready to publish when all these are true**:
- All checklist items marked complete
- Git repository initialized
- No sensitive data in repo
- .gitignore working correctly
- README displays correctly locally
- All documentation links work
- Scripts run successfully from new directory

## Contact & Support

After publication, update these:
- Issues: https://github.com/USERNAME/REPO-NAME/issues
- Discussions: https://github.com/USERNAME/REPO-NAME/discussions
- Email: your.email@example.com (if providing support)

---

**Project**: Siemens Process Simulation Tree Viewer
**Ready for Publication**: ✅ YES
**Last Updated**: 2026-01-13
