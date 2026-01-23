# Project Reorganization Plan

## Current State
- 76 files in root directory (should be ~10)
- Mix of active code, investigation docs, and one-off scripts
- Two separate test directories
- Missing standard project files

## Proposed Changes

### 1. Create Archive Directory
```
docs/archive/
├── investigations/     # BUGFIX-*.md, FINDINGS-*.md, DATABASE-INVESTIGATION-*.md
├── status-reports/     # PHASE2-*.md, *-SUMMARY.md, *-STATUS.md
└── handoff-notes/      # HANDOFF-TO-OTHER-AI.md, PROMPT-FOR-OTHER-AI.md
```

**Move these files:**
- BUGFIX-*.md → docs/archive/investigations/
- FIX-*.md → docs/archive/investigations/
- FINDINGS-*.md, *-ANALYSIS.md → docs/archive/investigations/
- PHASE2-*.md, *-STATUS.md, *-SUMMARY.md → docs/archive/status-reports/
- COMMIT-SUMMARY-*.md, CHANGES-*.md → docs/archive/status-reports/
- HANDOFF-*.md, PROMPT-*.md, MERGE-STRATEGY.md → docs/archive/handoff-notes/
- CACHE-OPTIMIZATION-COMPLETE.md, BROWSER-PERF-FIX.md → docs/archive/status-reports/

### 2. Consolidate Test Scripts
```
test/
├── integration/          # Test-RunStatus.ps1, Test-ReleaseSmoke.ps1 (existing)
├── automation/           # Move from test-automation/
│   ├── dependency-graph-test.ps1
│   ├── health-score-validator.ps1
│   ├── performance-benchmark.ps1
│   ├── search-functionality-test.ps1
│   └── validate-tree-data.ps1
├── fixtures/             # (existing)
└── results/              # Move up from integration/results/
```

### 3. Organize Debug Scripts
```
scripts/debug/
├── analyze-study-ddmp.ps1
├── analyze-study-summary.ps1
├── cache-status.ps1
├── run-analyze-all-operations.ps1
├── run-analyze-hierarchy.ps1
├── run-coverage-check.ps1
├── run-test-operation-query.ps1
├── run-tool-query.ps1
├── run-verify-operation.ps1
├── run-verify-parent.ps1
├── run-verify-parent-final.ps1
├── validate-against-xml.ps1
├── validate-against-xml-fast.ps1
├── verify-critical-paths.ps1
└── verify-management-dashboard.ps1
```

### 4. Keep in Root (User-Facing Only)
```
/
├── README.md
├── CHANGELOG.md
├── LICENSE
├── .gitignore
├── .gitattributes              # NEW
├── .editorconfig               # NEW
├── package.json                # NEW (if needed)
├── enterprise-portal-launcher.ps1
├── management-dashboard-launcher.ps1
└── generate-ford-dearborn-tree.ps1  # If this is user-facing
```

### 5. Consolidate Documentation

**Keep in docs/ root:**
- PRODUCTION_RUNBOOK.md
- QUICK-START-GUIDE.md
- SYSTEM-ARCHITECTURE.md
- CREDENTIAL-MANAGEMENT.md

**Move to docs/planning/:**
- PROJECT-ROADMAP.md
- DELIVERABLES.md
- E2E-TESTING-STRATEGY.md
- ORACLE-LOAD-TESTING-PLAN.md

**Move to docs/testing/:**
- PHASE1-TEST-PLAN.md
- PHASE2-TEST-PLAN.md
- TEST-PLAN.md
- UAT-PLAN.md
- README-TESTING.md

### 6. Add Missing Standard Files

**.editorconfig:**
```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true

[*.ps1]
indent_style = space
indent_size = 4

[*.{json,yml,yaml}]
indent_style = space
indent_size = 2

[*.md]
indent_style = space
indent_size = 2
trim_trailing_whitespace = false
```

**.gitattributes:**
```
* text=auto
*.ps1 text eol=crlf
*.sql text eol=crlf
*.md text eol=lf
*.json text eol=lf
*.yml text eol=lf
*.yaml text eol=lf
*.sh text eol=lf
```

**CONTRIBUTING.md:**
```markdown
# Contributing to SimTreeNav

## Development Setup
1. Install PowerShell 7.5+
2. Install Oracle Instant Client
3. Run scripts/ops/validate-environment.ps1

## Coding Standards
- Follow PowerShell best practices (approved verbs, PascalCase)
- All scripts must have comment-based help
- Run tests before submitting PR: test/integration/Test-*.ps1

## PR Process
1. Create feature branch: `feature/description` or `bugfix/description`
2. Run smoke tests locally
3. CI must pass (see .github/workflows/ci-smoke-test.yml)
4. Request review
```

## Implementation Steps

### Phase 1: Archive Historical Documents (Low Risk)
```powershell
# Create archive structure
New-Item -ItemType Directory -Path "docs/archive/investigations" -Force
New-Item -ItemType Directory -Path "docs/archive/status-reports" -Force
New-Item -ItemType Directory -Path "docs/archive/handoff-notes" -Force

# Move investigation docs
Move-Item -Path "BUGFIX-*.md" -Destination "docs/archive/investigations/"
Move-Item -Path "FIX-*.md" -Destination "docs/archive/investigations/"
# ... (continue for all investigation docs)

# Move status reports
Move-Item -Path "PHASE2-*.md" -Destination "docs/archive/status-reports/"
Move-Item -Path "*-SUMMARY.md" -Destination "docs/archive/status-reports/"
# ... (continue for all status reports)
```

### Phase 2: Consolidate Test Directory (Medium Risk)
```powershell
# Move test-automation scripts
Move-Item -Path "test-automation/*" -Destination "test/automation/"
Remove-Item -Path "test-automation" -Force

# Move results up one level
Move-Item -Path "test/integration/results" -Destination "test/results"
# Update test scripts to use new path
```

### Phase 3: Organize Debug Scripts (Low Risk)
```powershell
# Create debug directory
New-Item -ItemType Directory -Path "scripts/debug" -Force

# Move debug scripts
Move-Item -Path "analyze-*.ps1" -Destination "scripts/debug/"
Move-Item -Path "run-*.ps1" -Destination "scripts/debug/"
Move-Item -Path "validate-*.ps1" -Destination "scripts/debug/"
Move-Item -Path "verify-*.ps1" -Destination "scripts/debug/"
```

### Phase 4: Add Standard Files (No Risk)
```powershell
# Create .editorconfig, .gitattributes, CONTRIBUTING.md
# (content above)
```

## Benefits

1. **Clarity:** New contributors immediately see what's important
2. **Maintainability:** Easier to find relevant files
3. **Professionalism:** Follows industry-standard project structure
4. **Discoverability:** Standard files (.editorconfig, CONTRIBUTING.md) improve developer experience
5. **Version Control:** Historical docs archived but preserved

## Risks & Mitigation

- **Risk:** Breaking relative paths in scripts
  - **Mitigation:** Search for hardcoded paths, update systematically

- **Risk:** Breaking external references (docs, bookmarks)
  - **Mitigation:** Add redirects/notes in README for moved files

- **Risk:** Merge conflicts if reorganized during active development
  - **Mitigation:** Do this between feature work, coordinate with team

## Timeline

- **Phase 1 (Archive):** 30 minutes - Move historical docs
- **Phase 2 (Tests):** 1 hour - Consolidate test directories, update paths
- **Phase 3 (Debug):** 30 minutes - Move debug scripts
- **Phase 4 (Standards):** 30 minutes - Add .editorconfig, .gitattributes, CONTRIBUTING.md
- **Total:** ~2.5 hours

## Success Criteria

✅ Root directory has ≤10 files
✅ Single test/ directory with clear subdirectories
✅ All historical/investigation docs archived in docs/
✅ Standard project files present (.editorconfig, .gitattributes, CONTRIBUTING.md)
✅ All tests still pass
✅ CI workflow still works
