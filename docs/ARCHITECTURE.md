# SimTreeNav Architecture

## Pipeline Overview

```
┌─────────────┐    ┌──────────────┐    ┌──────────┐    ┌──────────┐
│   Extract   │───▶│ NodeContract │───▶│ Snapshot │───▶│ Identity │
│  (Database) │    │  (Normalize) │    │  (JSON)  │    │ Resolver │
└─────────────┘    └──────────────┘    └──────────┘    └────┬─────┘
                                                            │
                                                            ▼
┌─────────────┐    ┌──────────────┐    ┌──────────┐    ┌──────────┐
│   Viewer    │◀───│ ExportBundle │◀───│ Analysis │◀───│   Diff   │
│   (HTML)    │    │   (Bundle)   │    │ Engines  │    │ Compare  │
└─────────────┘    └──────────────┘    └──────────┘    └──────────┘
                          ▲
                          │
              ┌───────────┴───────────┐
              │                       │
        ┌─────┴─────┐           ┌─────┴─────┐
        │ Narrative │           │ Analytics │
        │  Engine   │           │  Engines  │
        └───────────┘           └───────────┘
              │                       │
        ┌─────┴─────┐           ┌─────┴─────────────┐
        │ Sessions  │           │ Impact │ Drift    │
        │ Intents   │           │ Comply │ Anomaly  │
        └───────────┘           │ Similar│ Explain  │
                                └─────────────────────┘
```

---

## Folder Structure

```
/workspace
├── DemoStory.ps1              # Narrative demo generator
├── Demo.ps1                   # Basic demo script
├── README.md                  # Project overview
│
├── docs/
│   ├── ARCHITECTURE.md        # This file
│   ├── FEATURES.md            # Feature documentation
│   ├── SECURITY-NONINTRUSIVE.md # Security guarantees
│   ├── api/                   # API documentation
│   └── investigation/         # Research notes
│
├── src/
│   └── powershell/
│       └── v02/
│           ├── core/          # Fundamental contracts
│           │   ├── NodeContract.ps1    # Canonical node format
│           │   └── IdentityResolver.ps1 # Identity matching
│           │
│           ├── diff/          # Change detection
│           │   └── Compare-Snapshots.ps1
│           │
│           ├── narrative/     # Session/Intent analysis
│           │   └── NarrativeEngine.ps1
│           │
│           ├── analysis/      # Analytical engines
│           │   ├── WorkSessionEngine.ps1
│           │   ├── IntentEngine.ps1
│           │   ├── ImpactEngine.ps1
│           │   ├── DriftEngine.ps1
│           │   ├── ComplianceEngine.ps1
│           │   ├── SimilarityEngine.ps1
│           │   ├── AnomalyEngine.ps1
│           │   └── ExplainEngine.ps1
│           │
│           └── export/        # Output generation
│               ├── ExportBundle.ps1
│               └── Anonymizer.ps1
│
├── tests/                     # Pester test suites
│   ├── DeterminismGate.Tests.ps1
│   ├── DiffEngine.Tests.ps1
│   ├── IdentityResolver.Tests.ps1
│   ├── ImpactEngine.Tests.ps1
│   ├── ImpactGraph.Tests.ps1
│   ├── DriftEngine.Tests.ps1
│   ├── DriftEngineV2.Tests.ps1
│   ├── ComplianceEngine.Tests.ps1
│   ├── Anonymizer.Tests.ps1
│   ├── ExportBundle.Tests.ps1
│   └── WorkSession.Tests.ps1
│
├── queries/                   # SQL query library
│   └── *.sql
│
└── scripts/                   # Setup and utility scripts
    ├── create-readonly-user.sql
    └── Setup-OracleConnection.ps1
```

---

## Core Components

### NodeContract.ps1

Defines the canonical node format used throughout the system.

```powershell
# Canonical node structure
[PSCustomObject]@{
    nodeId       = "12345"              # Unique identifier
    nodeType     = "Station"            # Classification
    name         = "Weld_Cell_A"        # Display name
    parentId     = "12344"              # Parent reference
    path         = "/Plant/Weld_Cell_A" # Full path
    attributes   = @{                   # Flexible metadata
        externalId = "EXT-001"
        className  = "PmStation"
        niceName   = "Weld Cell Alpha"
        typeId     = 64
    }
    links        = @{                   # Cross-references
        prototypeId = "67890"
        twinId      = $null
    }
    fingerprints = @{                   # Change detection
        contentHash   = "a1b2c3d4e5f6g7h8"
        attributeHash = "h8g7f6e5d4c3b2a1"
        transformHash = $null
    }
    transform    = "100,200,50,0,0,90"  # x,y,z,rx,ry,rz
    timestamps   = @{                   # Temporal data
        createdAt     = "2025-01-15T10:00:00Z"
        updatedAt     = "2025-01-15T14:30:00Z"
    }
    source       = @{                   # Provenance
        table  = "COLLECTION_VIEW"
        schema = "DESIGN12"
    }
}
```

### IdentityResolver.ps1

Matches nodes across snapshots using multiple signals.

```
Signal Weights:
├── externalId (0.35)     # Most reliable
├── name+parentPath (0.25) # Positional identity
├── contentHash (0.20)     # Content fingerprint
├── prototypeLink (0.10)   # Relationship
├── transformHash (0.05)   # Location
└── nodeType (0.05)        # Classification

Match Threshold: 0.85 (configurable)
```

### Compare-Snapshots.ps1

Detects differences between baseline and current state.

```
Change Detection Flow:
1. Build node maps (nodeId → node)
2. Detect added (in current, not in baseline)
3. Detect removed (in baseline, not in current)
4. For matched nodes:
   a. Compare name → renamed
   b. Compare parentId → moved
   c. Compare transform → transform_changed
   d. Compare fingerprints → modified
5. Apply identity resolution for unmatched
6. Detect rekeyed (same logical node, new ID)
```

---

## Analysis Engines

### ImpactEngine.ps1

Computes dependency graphs and risk scores.

```
Graph Building:
├── Parent-Child edges (structural)
├── Prototype-Instance links
├── Twin relationships
├── Generic links (shortcuts, references)
└── Reverse links (what points to this node)

Risk Score = Σ(weights):
├── dependentCountWeight (40%)
│   └── log2(dependentCount) * 10, capped at 40
├── nodeTypeWeight (30%)
│   ├── ToolPrototype: 30
│   ├── Station: 20
│   └── Other: 10
└── criticalLinkWeight (30%)
    └── crossTreeLinks * 10, capped at 30
```

### DriftEngine.ps1

Measures transform deviation between related nodes.

```
Drift Calculation:
1. Find pairs (prototype-instance, twins)
2. Parse transforms: x,y,z,rx,ry,rz
3. Position delta = √(Δx² + Δy² + Δz²) mm
4. Rotation delta = max(|Δrx|, |Δry|, |Δrz|) deg
   (with 360° wraparound handling)
5. Classify severity:
   ├── Info: 1-5x tolerance
   ├── Warn: 5-10x tolerance
   └── Critical: >10x tolerance
```

### WorkSessionEngine.ps1 & IntentEngine.ps1

Groups changes and classifies intent.

```
Session Grouping:
1. Sort changes by timestamp
2. Start new session if gap > TimeWindowMinutes
3. Merge small sessions (< MinChangesPerSession)
4. Extract affected subtrees

Intent Classification:
├── bulk_paste: >10 adds in single subtree
├── cleanup: >5 removes
├── standardization: >5 renames with pattern
├── reorganization: >3 cross-subtree moves
└── prototype_swap: link changes
```

---

## Determinism Rules

All outputs follow strict determinism for reproducibility:

### 1. Sorted Collections

```powershell
# Always sort by: depth, nodeType, path, name, nodeId
$sorted = $nodes | Sort-Object @(
    @{Expression = {$_.path.Split('/').Count}; Ascending = $true},
    @{Expression = {$_.nodeType}; Ascending = $true},
    @{Expression = {$_.path}; Ascending = $true},
    @{Expression = {$_.name}; Ascending = $true},
    @{Expression = {$_.nodeId}; Ascending = $true}
)
```

### 2. No Embedded Timestamps

```powershell
# Timestamps only in meta.json or manifest.json
# Never in data files (nodes.json, diff.json, impact.json)
```

### 3. Deterministic Hashing

```powershell
# Use SHA256 for all fingerprints
# Sort keys before hashing for stability
$sortedPairs = $attributes.GetEnumerator() | Sort-Object Name
$content = $sortedPairs -join '|'
$hash = [SHA256]::ComputeHash([Encoding]::UTF8.GetBytes($content))
```

### 4. Seeded Random for Demos

```powershell
# DemoStory supports -Seed for reproducible output
.\DemoStory.ps1 -Seed 42 -NodeCount 100

# Same seed = identical output (byte-for-byte)
```

---

## Extension Points

### Adding a New Analysis Engine

1. **Create the engine file:**

```powershell
# src/powershell/v02/analysis/NewEngine.ps1

function Invoke-NewAnalysis {
    param([array]$Nodes, [array]$Changes)
    
    # Your analysis logic
    
    return [PSCustomObject]@{
        # Deterministic output
    }
}

function Export-NewAnalysisJson {
    param($Report, [string]$OutputPath)
    
    # Sort for determinism
    # Write without timestamps in data
}

if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @('Invoke-NewAnalysis', 'Export-NewAnalysisJson')
}
```

2. **Add tests:**

```powershell
# tests/NewEngine.Tests.ps1

Describe 'NewEngine' {
    It 'Produces deterministic output' {
        # Test with same input twice
        # Compare results
    }
}
```

3. **Integrate into DemoStory:**

```powershell
# In DemoStory.ps1
$newReport = Invoke-NewAnalysis -Nodes $currentNodes -Changes $diff

# Add to bundle
Export-NewAnalysisJson -Report $newReport -OutputPath $dataDir
```

4. **Add viewer tab:**

```javascript
// In ExportBundle.ps1 viewer template
function renderNewAnalysis() {
    const data = window.bundleData.newAnalysis;
    // Render logic
}
```

### Adding a New Node Type

1. **Update NodeContract.ps1:**

```powershell
$Script:ValidNodeTypes = @(
    'ResourceGroup',
    'ToolPrototype',
    'ToolInstance',
    # ... existing types ...
    'NewType'  # Add here
)

function Get-NodeTypeFromClass {
    # Add mapping rules
    $defaultRules['NewType'] = @('NewTypeClass', 'AnotherNewClass')
}
```

2. **Update Anonymizer.ps1:**

```powershell
$Script:TypePrefixes = @{
    'ToolPrototype'  = 'TP'
    'ToolInstance'   = 'TI'
    # ... existing prefixes ...
    'NewType'        = 'NT'  # Add prefix
}
```

---

## Data Flow Example

```
1. User runs: .\DemoStory.ps1 -NodeCount 200

2. Baseline Generation:
   New-BaselineDataset
   └── New-StoryNode × 200
       └── NodeContract format

3. Story Events:
   Apply-BulkPasteEvent
   Apply-RenamePassEvent
   Apply-RetouchSessionEvent
   ...

4. Analysis Pipeline:
   Resolve-NodeIdentities
   └── Build identity map
   └── Assign logicalIds

   Compare-NodesWithIdentity
   └── Detect changes
   └── Match with identity

   Group-ChangesIntoSessions
   └── Time-window grouping

   Invoke-IntentAnalysis
   └── Classify each session

   Get-ImpactForChanges
   └── Build dependency graph
   └── Compute risk scores

   Measure-Drift
   └── Find pairs
   └── Measure deltas

5. Export:
   Export-Bundle
   └── Create data/*.json
   └── Embed in index.html
   └── Generate manifest.json

6. Output:
   ./bundles/demo/
   ├── index.html
   ├── manifest.json
   └── data/
       ├── diff.json
       ├── sessions.json
       ├── intents.json
       ├── impact.json
       ├── drift.json
       ├── compliance.json
       ├── anomalies.json
       └── timeline.json
```

---

## Testing Strategy

### Test Categories

| Category | Files | Purpose |
|----------|-------|---------|
| Unit | `*Engine.Tests.ps1` | Individual function behavior |
| Integration | `ExportBundle.Tests.ps1` | End-to-end pipeline |
| Determinism | `DeterminismGate.Tests.ps1` | Reproducibility |
| Contract | `DiffEngine.Tests.ps1` | NodeContract validation |

### Running Tests

```powershell
# All tests
Invoke-Pester -Path ./tests -Output Normal

# Specific file
Invoke-Pester -Path ./tests/ImpactEngine.Tests.ps1 -Output Detailed

# By tag
Invoke-Pester -Path ./tests -Tag 'Determinism' -Output Detailed

# With coverage
Invoke-Pester -Path ./tests -CodeCoverage ./src/**/*.ps1
```

---

## Performance Considerations

### Large Trees (>10,000 nodes)

1. **Extraction**: Use pagination and streaming
2. **Analysis**: Process in chunks
3. **Viewer**: Cap displayed nodes (MaxNodesInViewer)
4. **Export**: Compress JSON

### Memory Optimization

```powershell
# Stream processing pattern
foreach ($chunk in Get-NodeChunks -Path $path -ChunkSize 1000) {
    Process-Chunk -Nodes $chunk
    [GC]::Collect()  # Force garbage collection
}
```

### Probe Metrics

Always check probe output:
- `queriesExecuted < 10`
- `totalDurationMs < 5000`
- `peakMemoryEstimateMb < 100`

---

## Security Model

See `docs/SECURITY-NONINTRUSIVE.md` for full details.

Summary:
- **Read-only**: No database writes
- **Non-intrusive**: Minimal query load
- **Deterministic**: Reproducible outputs
- **Anonymizable**: Safe for external sharing
