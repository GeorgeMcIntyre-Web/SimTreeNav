# SimTreeNav v0.5 Handoff Summary

## Repository
https://github.com/GeorgeMcIntyre-Web/SimTreeNav

## Current Branch
`cursor/simtreenav-v05-impact-drift` (pushed, up to date)

---

## COMPLETED

### v0.4 Deliverables

| Item | File | Tests |
|------|------|-------|
| ExportBundle++ | `src/powershell/v02/export/ExportBundle.ps1` | 35 tests |
| Anonymizer | `src/powershell/v02/export/Anonymizer.ps1` | 44 tests |
| DemoStory | `DemoStory.ps1` | Integrated |

**ExportBundle++ Features:**
- BundleName, Range, IncludeRawSql, MaxNodesInViewer
- Timeline support for multi-snapshot bundles
- manifest.json generation

**Anonymizer Features:**
- Stable deterministic pseudonyms: TP-####, TI-####, ST-####, OP-####, LOC-####
- Export/import mapping for internal use

**DemoStory Features:**
- 8-step narrative timeline (Baseline → Bulk Paste → Rename → Retouch → Restructure → Prototype Swap → Anomaly → Recovery)
- Generates `docs/DEMO-TALK-TRACK.md` with speaker notes
- `-Anonymize` flag for safe external sharing

### v0.5 Deliverables (WORKSTREAM 2A/2B)

| Item | File | Tests |
|------|------|-------|
| ImpactMap v1 | `src/powershell/v02/analysis/ImpactEngine.ps1` | 25 tests |
| DriftEngine v1 | `src/powershell/v02/analysis/DriftEngine.ps1` | 31 tests |

**ImpactMap v1 Features:**
- `Get-ImpactForNode` API: riskScore 0..100, directDependents[], transitiveDependents[], upstreamReferences[]
- Breakdown: dependentCountWeight, nodeTypeWeight, criticalLinkWeight
- `why[]` strings explaining risk contributors
- Deterministic JSON output (sorted by depth, nodeType, path, name, nodeId)

**DriftEngine v1 Features:**
- Prototype-instance pairing via links
- Position delta (mm, Euclidean), Rotation delta (deg, max axis with wraparound)
- Tolerance classification: Info (1-5x), Warn (5-10x), Critical (>10x)
- `Build-DriftTrend` for timeline analysis
- `Export-DriftTrendJson` for drift_trend.json
- Deterministic JSON output

### Test Status
```
Tests Passed: 272
Tests Failed: 5 (pre-existing NodeContract.ps1 issues, unrelated to new work)
New Tests: 135 (44 Anonymizer + 35 ExportBundle + 25 ImpactGraph + 31 DriftEngine)
```

---

## REMAINING

### WORKSTREAM 2C — Intelligence Engines

| # | Item | File | Status |
|---|------|------|--------|
| 6 | GoldenTemplate compliance | `ComplianceEngine.ps1` | Exists, needs enhancement |
| 7 | SimilarityEngine | `SimilarityEngine.ps1` | Exists, needs enhancement |
| 8 | AnomalyEngine | `AnomalyEngine.ps1` | Exists, needs enhancement |

**GoldenTemplate Requirements:**
- `Save-Template.ps1 -NodeId <station/subtree> -TemplateName "BMW_XYZ"`
- Template contents: required nodeTypes + min/max counts, required links, naming regex, allowed extras
- Produce `compliance.json`: score, missing, violations, extras, drift violations
- Viewer compliance tab

**SimilarityEngine Requirements:**
- `Find-Similar.ps1 -NodeId <station> -Top 10`
- Structural fingerprint: shape hash, attribute summary hash, optional minhash
- Produce `similar.json`
- Viewer tab

**AnomalyEngine Requirements:**
- Detect: mass delete spikes, transform outliers, oscillation patterns, naming violations, unusual parent moves
- Severity levels: Info/Warn/Critical with evidence references
- Produce `anomalies.json`
- Viewer alerts page

### WORKSTREAM 3 — UX Polish

| # | Item | Status |
|---|------|--------|
| 9 | Viewer navigation upgrades | Partially done (Impact + Drift tabs exist) |
| 10 | ExplainEngine v1 | Engine exists, needs viewer integration |

**Viewer Requirements:**
- Tabs: Timeline, Actions, Impact, Drift, Compliance, Similar, Alerts, Explain
- Cross-highlighting: click action → highlight affected nodes
- Changed-only mode + expand-to-changed
- Export buttons: subtree JSON/CSV, actions.json, compliance report

### WORKSTREAM 4 — Performance

| # | Item | Status |
|---|------|--------|
| 11 | Large dataset support | Not started |
| 12 | Test suite expansion | Partially done |

**Performance Requirements:**
- Paging everywhere
- Streaming writers
- Virtualized UI lists
- Max node count caps with graceful warnings
- Measure: duration per query, memory estimation, file sizes

### WORKSTREAM 5 — Docs

| # | Item | Status |
|---|------|--------|
| 13 | docs/SECURITY-NONINTRUSIVE.md | Not started |
| 13 | docs/FEATURES.md | Not started |
| 13 | docs/ARCHITECTURE.md | Not started |

---

## FILE STRUCTURE

```
src/powershell/v02/
├── analysis/
│   ├── ImpactEngine.ps1      # v0.5 enhanced ✅
│   ├── DriftEngine.ps1       # v0.5 enhanced ✅
│   ├── ComplianceEngine.ps1  # Needs v0.5 enhancement
│   ├── SimilarityEngine.ps1  # Needs v0.5 enhancement
│   ├── AnomalyEngine.ps1     # Needs v0.5 enhancement
│   ├── ExplainEngine.ps1     # Needs viewer integration
│   ├── IntentEngine.ps1
│   └── WorkSessionEngine.ps1
├── core/
│   ├── NodeContract.ps1
│   └── IdentityResolver.ps1
├── diff/
│   └── Compare-Snapshots.ps1
├── export/
│   ├── ExportBundle.ps1      # v0.4 enhanced ✅
│   └── Anonymizer.ps1        # v0.4 new ✅
└── narrative/
    └── NarrativeEngine.ps1

tests/
├── ImpactGraph.Tests.ps1     # 25 tests ✅
├── DriftEngineV2.Tests.ps1   # 31 tests ✅
├── Anonymizer.Tests.ps1      # 44 tests ✅
├── ExportBundle.Tests.ps1    # 35 tests ✅
├── ComplianceEngine.Tests.ps1
├── DriftEngine.Tests.ps1
├── IdentityResolver.Tests.ps1
├── ImpactEngine.Tests.ps1
└── WorkSession.Tests.ps1

Root files:
├── Demo.ps1                  # Basic demo
├── DemoStory.ps1             # v0.4 narrative demo ✅
└── HANDOFF-V05.md            # This file
```

---

## CODING CONVENTIONS

### PowerShell Style
```powershell
# Guard clauses, no else/elseif
if (-not $param) { return $null }
if ($param.Count -eq 0) { return @() }

# Max 2-level nesting
foreach ($item in $collection) {
    if ($item.property) {
        # Do work (max depth)
    }
}

# Wrap Export-ModuleMember for dot-sourcing compatibility
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @('Function1', 'Function2')
}
```

### Deterministic Output Rules
- No timestamps inside data JSON (only in meta.json)
- Sort arrays by: depth, nodeType, path, name, nodeId
- Use `ConvertTo-Json -Depth 10 -Compress` for production
- Use UTF8 without BOM: `[System.IO.File]::WriteAllText($path, $json, (New-Object System.Text.UTF8Encoding $false))`

### Test-First Approach
1. Write failing tests in `tests/<Feature>.Tests.ps1`
2. Implement feature
3. Verify all tests pass
4. Commit with message: `test:` then `feat:`

---

## NON-NEGOTIABLES

| Constraint | Description |
|------------|-------------|
| READ-ONLY | Database access only. No writes. No schema changes. |
| Non-intrusive | Measure query counts, row counts, durations in meta.json |
| Deterministic | All JSON outputs must be stable (same input = same output) |
| PowerShell 5.1+ | Must work on Windows PowerShell 5.1 |
| No proprietary data | No Siemens schema dumps or restricted docs |
| Backward compatible | Keep existing commands working |

---

## QUICK COMMANDS

```powershell
# Run all tests
Invoke-Pester -Path ./tests -Output Normal

# Run specific test file
Invoke-Pester -Path ./tests/ImpactGraph.Tests.ps1 -Output Detailed

# Generate demo bundle
.\DemoStory.ps1 -NodeCount 200 -OutDir ./output/test -NoOpen

# Generate anonymized demo
.\DemoStory.ps1 -NodeCount 200 -OutDir ./output/anon -Anonymize -CreateZip

# Check outputs
Get-ChildItem ./output/test/data/
```

---

## NEXT STEPS (Recommended Order)

### Step 1: Enhance ComplianceEngine (Item 6)
```powershell
# Target file: src/powershell/v02/analysis/ComplianceEngine.ps1
# Test file: tests/ComplianceEngine.Tests.ps1

# Add functions:
# - Save-Template -Nodes -NodeId -TemplateName
# - Test-TemplateCompliance -Nodes -Template
# - Export-ComplianceJson -Report -OutputPath

# Template structure:
# - requiredTypes: [{nodeType, minCount, maxCount, required}]
# - requiredLinks: [{linkType, sourceType, targetType}]
# - namingRules: [{nodeType, pattern (regex), description}]
# - allowedExtras: [nodeType patterns to ignore]
```

### Step 2: Enhance SimilarityEngine (Item 7)
```powershell
# Target file: src/powershell/v02/analysis/SimilarityEngine.ps1
# Test file: tests/SimilarityEngine.Tests.ps1

# Add functions:
# - Get-StructuralFingerprint -Nodes -RootNodeId
# - Find-SimilarNodes -Nodes -SourceNodeId -Top
# - Export-SimilarityJson -Results -OutputPath
```

### Step 3: Enhance AnomalyEngine (Item 8)
```powershell
# Target file: src/powershell/v02/analysis/AnomalyEngine.ps1
# Test file: tests/AnomalyEngine.Tests.ps1

# Add detection rules:
# - Detect-MassDeleteSpike -Changes -Threshold
# - Detect-TransformOutliers -Nodes -Bounds
# - Detect-OscillationPatterns -Changes -Window
# - Detect-NamingViolations -Nodes -Patterns

# Severity enum: Info, Warn, Critical
# Evidence: {nodeIds[], changeIds[], metrics}
```

### Step 4: Viewer Tabs (Item 9)
```powershell
# Target file: src/powershell/v02/export/ExportBundle.ps1
# Function: Get-ViewerTemplate

# Add to navigation:
# <a class="nav-item" data-section="timeline">Timeline</a>
# <a class="nav-item" data-section="similar">Similar</a>
# <a class="nav-item" data-section="alerts">Alerts</a>
# <a class="nav-item" data-section="explain">Explain</a>

# Add render functions:
# function renderTimeline() { ... }
# function renderSimilar() { ... }
# function renderAlerts() { ... }
# function renderExplain() { ... }
```

---

## DEFINITION OF DONE

For each remaining item:
- [ ] Pester tests written and passing
- [ ] Deterministic JSON output verified
- [ ] Integrated into DemoStory bundle
- [ ] Viewer tab functional (where applicable)
- [ ] README updated with usage example
- [ ] Committed with descriptive message

---

## COMMITS SO FAR (v0.5 branch)

```
480b06e test: Add ImpactGraph and DriftEngine v2 tests (TDD)
ba3c989 feat(v0.5): Enhance ImpactEngine and DriftEngine with deterministic outputs
8e07e86 docs: Update README with v0.4 and v0.5 features
```

---

*Generated: 2026-01-15*
