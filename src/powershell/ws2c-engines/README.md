# WS2C Engines

A suite of analysis engines for the Siemens Process Simulation Navigation Tree.

## Engines

### ComplianceEngine
Templates and scoring for tree structure compliance.

**Commands:**
```powershell
# Save a template from existing nodes
Save-Template -NodesPath nodes.json -NodeId "1" -TemplateName "StationTemplate" -OutPath template.json

# Test compliance against a template
Test-TemplateCompliance -NodesPath nodes.json -TemplatePath template.json -OutPath compliance.json
```

**Template includes:**
- `requiredTypes`: min/max counts per node type
- `requiredLinks`: required parent-child relationships
- `namingRules`: regex patterns for node names
- `allowedExtras`: whether extra types are permitted
- `driftRules`: tolerance settings by nodeType

**Output (compliance.json):**
```json
{
  "score": 85,
  "missing": [],
  "violations": [{"nodeId": "4", "rule": "naming", "message": "..."}],
  "extras": [],
  "perRule": [{"ruleName": "naming", "passed": false, "score": 70}]
}
```

### SimilarityEngine
Find similar stations/subtrees using structural fingerprinting.

**Command:**
```powershell
Find-Similar -NodesPath nodes.json -NodeId "10" -Top 10 -OutPath similar.json
```

**Algorithm uses:**
- Shape hash: type distribution fingerprint
- Attribute summary hash: attribute pattern fingerprint
- Optional minhash for scalability

**Output (similar.json):**
```json
{
  "sourceNodeId": "10",
  "candidates": [
    {
      "nodeId": "20",
      "similarityScore": 0.95,
      "why": "Identical structure shape; Same node count",
      "evidence": {...}
    }
  ]
}
```

### AnomalyEngine
Detect anomalies and generate alerts.

**Command:**
```powershell
Detect-Anomalies -NodesPath nodes.json -TimelinePath timeline.json -OutPath anomalies.json
```

**Detects:**
- Mass delete spikes (5+ deletes in 60 seconds)
- Transform outliers (extreme position changes)
- Oscillation patterns (back-and-forth parent moves)
- Naming violations (invalid characters, empty names)
- Unusual parent moves (statistical outliers)

**Output (anomalies.json):**
```json
{
  "anomalies": [
    {
      "severity": "Critical",
      "title": "Mass delete spike",
      "summary": "6 nodes deleted in 2024-01-02 09:00 by user2",
      "evidence": {"nodeIds": [...], "changeIds": [...]}
    }
  ]
}
```

## Bundle Export

Combine all engine outputs into a single bundle.

```powershell
Export-Bundle -NodesPath nodes.json `
  -CompliancePath compliance.json `
  -SimilarPath similar.json `
  -AnomaliesPath anomalies.json `
  -OutPath bundle.json
```

## Demo Data

Generate sample data with intentional failures for testing:

```powershell
New-DemoStory -OutDir ./demo-output -Seed 42
```

This creates:
- `nodes.json` - Tree nodes with naming violations
- `timeline.json` - Changes with anomaly patterns
- `template.json` - Strict compliance template
- `compliance.json` - Compliance results (will have failures)
- `similar.json` - Similarity results
- `anomalies.json` - Detected anomalies (will have critical)
- `bundle.json` - Combined bundle for viewer

## Viewer

Open the interactive viewer:

```powershell
./Open-DemoViewer.ps1
```

Or open `ws2c-viewer.html` directly and load a bundle.json.

**Features:**
- **Tree View**: Expandable/collapsible navigation tree with search
- **Compliance Tab**: Score display, violation/missing/extra lists, per-rule breakdown
- **Similar Tab**: Candidate list with similarity scores and jump-to functionality
- **Alerts Tab**: Anomaly list with severity filtering and node highlighting

## Testing

Run all Pester tests:

```powershell
./tests/Run-AllTests.ps1
```

## Constraints

- Deterministic outputs with stable sort order
- Guard clauses (no else/elseif patterns)
- Tests first (Pester) for each engine
