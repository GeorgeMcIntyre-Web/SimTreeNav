# SimTreeNav Features

## Overview

SimTreeNav is a PowerShell-based toolkit for analyzing, comparing, and visualizing manufacturing digital twin hierarchies. It transforms complex tree data into actionable insights through automated diff detection, identity resolution, and narrative analytics.

---

## Core Features

### 1. Snapshot Extraction

Extract tree structures from databases into portable JSON snapshots.

```powershell
# Basic extraction
.\src\powershell\v02\Extract-Tree.ps1 -Schema DESIGN12 -RootId 12345

# Output: snapshots/DESIGN12_12345_2025-01-15.json
```

**Capabilities:**
- Hierarchical tree traversal
- Attribute preservation (names, external IDs, class names)
- Transform data extraction (position, rotation)
- Link resolution (prototypes, twins, shortcuts)
- Probe metrics for performance monitoring

### 2. Diff Detection

Compare two snapshots to detect all changes.

```powershell
# Compare snapshots
$diff = Compare-NodesWithIdentity -BaselineNodes $baseline -CurrentNodes $current

# Change types detected:
# - added: New nodes
# - removed: Deleted nodes
# - renamed: Name changes
# - moved: Parent changes
# - transform_changed: Position/rotation changes
# - rekeyed: Identity reassignment
```

**Change Categories:**

| Type | Description | Example |
|------|-------------|---------|
| `added` | Node exists in current but not baseline | New tool added |
| `removed` | Node exists in baseline but not current | Tool deleted |
| `renamed` | Same node ID, different name | "Robot_1" → "Robot_1_STD" |
| `moved` | Same node ID, different parent | Reorganization |
| `transform_changed` | Position/rotation delta | Tool adjustment |
| `rekeyed` | Same logical node, new ID | Database rebuild |

### 3. Identity Resolution

Match nodes across snapshots even when IDs change.

```powershell
# Resolve identities
$nodes = Resolve-NodeIdentities -Nodes $rawNodes

# Compare with identity matching
$diff = Compare-NodesWithIdentity `
    -BaselineNodes $baseline `
    -CurrentNodes $current `
    -ConfidenceThreshold 0.85
```

**Identity Signals:**

| Signal | Weight | Description |
|--------|--------|-------------|
| `externalId` | 0.35 | External system identifier |
| `name+parentPath` | 0.25 | Hierarchical position |
| `contentHash` | 0.20 | Content fingerprint |
| `prototypeLink` | 0.10 | Prototype reference |
| `transformHash` | 0.05 | Position fingerprint |
| `nodeType` | 0.05 | Classification |

### 4. Watch Mode

Continuous monitoring with change detection.

```powershell
# Start watching
.\src\powershell\v02\Watch-Tree.ps1 -Schema DESIGN12 -RootId 12345 -Interval 120

# Two-stage detection:
# Stage A: Lightweight timestamp check (every interval)
# Stage B: Full extraction (only when changes detected)
```

---

## Narrative Analytics

### 5. Work Session Grouping

Group related changes into logical work sessions.

```powershell
$sessions = Group-ChangesIntoSessions `
    -Changes $diff `
    -TimeWindowMinutes 60 `
    -MinChangesPerSession 2

# Output:
# - sessionId: session_001
# - startTime / endTime
# - changeCount
# - affected subtrees
```

### 6. Intent Analysis

Automatically classify the purpose behind changes.

```powershell
$intents = Invoke-IntentAnalysis -Changes $session.changes

# Detected intents:
# - bulk_paste: Mass import (>10 adds in same subtree)
# - cleanup: Mass removal
# - standardization: Systematic renaming (_STD suffix)
# - reorganization: Multiple moves between subtrees
# - prototype_swap: Link changes to different prototypes
```

**Intent Types:**

| Intent | Trigger | Confidence |
|--------|---------|------------|
| `bulk_paste` | 10+ adds in single subtree | High |
| `cleanup` | 5+ removes | Medium |
| `standardization` | 5+ renames with pattern | High |
| `reorganization` | 3+ moves across subtrees | Medium |
| `prototype_swap` | Link changes | Medium |

---

## Analysis Engines

### 7. Impact Analysis

Understand the blast radius of any change.

```powershell
$impact = Get-ImpactForNode -NodeId "12345" -Nodes $nodes

# Returns:
# - directDependents: Immediate children, linked nodes
# - transitiveDependents: Full downstream graph
# - upstreamReferences: Nodes that reference this one
# - riskScore: 0-100 criticality rating
# - why: Human-readable explanations
```

**Risk Score Breakdown:**

| Factor | Weight | Description |
|--------|--------|-------------|
| Dependent count | 40% | More dependents = higher risk |
| Node type | 30% | Prototypes > Instances |
| Critical links | 30% | Cross-tree references |

### 8. Drift Analysis

Detect transform drift between prototypes and instances.

```powershell
$drift = Measure-Drift -Nodes $nodes

# Finds pairs with drift:
# - Prototype ↔ Instance links
# - Twin relationships
# - Manufacturing links

# Measures:
# - Position delta (mm, Euclidean)
# - Rotation delta (degrees, max axis)
# - Attribute differences
```

**Severity Classification:**

| Level | Position Drift | Rotation Drift |
|-------|---------------|----------------|
| Info | 1-5x tolerance | 1-5x tolerance |
| Warn | 5-10x tolerance | 5-10x tolerance |
| Critical | >10x tolerance | >10x tolerance |

### 9. Compliance Checking

Validate against golden templates.

```powershell
# Define template
$template = New-GoldenTemplate -Name "WeldCellStandard"
$template.requiredTypes = @(
    (New-TypeRequirement -NodeType 'Station' -MinCount 1 -Required)
    (New-TypeRequirement -NodeType 'Resource' -MinCount 1)
)

# Check compliance
$compliance = Test-Compliance -Nodes $nodes -Template $template

# Returns:
# - score: 0.0 - 1.0
# - missing: Required items not found
# - violations: Rule breaches
# - extras: Unexpected items
```

### 10. Anomaly Detection

Automatically flag unusual patterns.

```powershell
$anomalies = Detect-Anomalies -Changes $diff -TotalNodes $baseline.Count

# Detects:
# - Mass delete spikes (>20% removal)
# - Transform outliers
# - Naming violations
# - Unusual parent moves
```

---

## Export & Visualization

### 11. Export Bundle

Generate self-contained offline viewer bundles.

```powershell
Export-Bundle `
    -OutDir "./bundles/demo" `
    -BaselineNodes $baseline `
    -CurrentNodes $current `
    -Diff $diff `
    -Sessions $sessions `
    -Intents $intents `
    -Impact $impact `
    -Drift $drift `
    -Timeline $timeline

# Creates:
# - index.html (self-contained viewer)
# - data/*.json (all analysis files)
# - manifest.json (bundle metadata)
```

### 12. Anonymizer

Prepare bundles for external sharing.

```powershell
$anonContext = New-AnonymizationContext -Seed "my-secret-seed"

$anonNodes = ConvertTo-AnonymizedNodes -Nodes $nodes -Context $anonContext

# Pseudonyms:
# - TP-#### (ToolPrototype)
# - TI-#### (ToolInstance)
# - ST-#### (Station)
# - OP-#### (Operation)
# - LOC-#### (Location)
```

### 13. Demo Story Generator

Create presentation-ready narrative demos.

```powershell
.\DemoStory.ps1 -NodeCount 300 -OutDir ./bundles/demo -Anonymize -CreateZip

# Generates 8-step timeline:
# 1. Baseline
# 2. Bulk Paste
# 3. Rename Pass
# 4. Retouch Session
# 5. Station Restructure
# 6. Prototype Swap
# 7. Anomaly Event
# 8. Recovery

# Outputs:
# - Offline bundle
# - docs/DEMO-TALK-TRACK.md (speaker notes)
```

---

## Quick Start

### Run the Full Demo in One Command

```powershell
# Generate complete demo with all features
.\DemoStory.ps1 -NodeCount 500 -OutDir ./bundles/full_demo -NoOpen

# Open the viewer
Start-Process ./bundles/full_demo/index.html
```

### Run Tests

```powershell
# All tests
Invoke-Pester -Path ./tests -Output Normal

# Specific test file
Invoke-Pester -Path ./tests/DeterminismGate.Tests.ps1 -Output Detailed
```

### Generate Anonymized Export

```powershell
.\DemoStory.ps1 -NodeCount 200 -Anonymize -CreateZip -OutDir ./bundles/external_share
# Creates: ./bundles/external_share.zip (safe for external sharing)
```

---

## Feature Status

| Feature | Status | Tests |
|---------|--------|-------|
| Snapshot Extraction | Complete | Yes |
| Diff Detection | Complete | Yes |
| Identity Resolution | Complete | Yes |
| Watch Mode | Complete | - |
| Work Sessions | Complete | Yes |
| Intent Analysis | Complete | Yes |
| Impact Analysis | Complete | Yes |
| Drift Analysis | Complete | Yes |
| Compliance | Complete | Yes |
| Anomaly Detection | Complete | Yes |
| Export Bundle | Complete | Yes |
| Anonymizer | Complete | Yes |
| Demo Story | Complete | Yes |
| Determinism Gate | Complete | Yes |

**Total Tests:** 296 passing

---

## Next Steps

See `docs/ARCHITECTURE.md` for technical details and extension points.
