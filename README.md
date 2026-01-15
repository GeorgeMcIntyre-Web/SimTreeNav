# SimTreeNav - Process Simulation Tree Viewer

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)
[![Oracle](https://img.shields.io/badge/Oracle-12c-red)](https://www.oracle.com/database/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Version](https://img.shields.io/badge/version-0.5.0-brightgreen)](CHANGELOG.md)

A PowerShell-based tree navigation and **intelligent change analysis** system for Siemens Process Simulation databases. Extracts, visualizes, snapshots, and tracks changes in hierarchical project structures with **identity-aware matching**, **intent detection**, **impact analysis**, and **offline viewer bundles**.

![Tree Viewer Preview](docs/assets/tree-viewer-screenshot.png)

## Features

### Core Features
- 🌳 **Full Tree Navigation** - Complete hierarchical visualization of Process Simulation projects
- 🎨 **Icon Extraction** - Automatic extraction and display of 95+ custom icons from database BLOB fields
- 🔍 **Search Functionality** - Real-time search across all nodes
- 📊 **Multi-Project Support** - Works with DESIGN1-5 schemas
- ⚡ **Interactive HTML** - Expand/collapse nodes, search, and navigate efficiently
- 🔧 **Custom Ordering** - Matches Siemens application node ordering
- 🚀 **Easy Setup** - Automated Oracle client installation and configuration

### v0.2 Features
- 📸 **Snapshots** - Point-in-time captures of tree state in canonical JSON format
- 🔄 **Diff Engine** - Compare snapshots to detect adds, removes, renames, moves, and attribute changes
- 👁️ **Watch Mode** - Continuous monitoring with automatic change detection
- 📈 **Timeline** - Track changes over time with hot subtree analysis
- 🎯 **Canonical Node Contract** - Consistent JSON schema across all node types

### v0.3+ Features
- 🔑 **Identity Resolution** - Stable node identity across DB rekeys with confidence scoring
- 🔄 **Rekeyed Detection** - Detects when same logical node gets a new database ID
- 📖 **Narrative Engine** - Groups raw changes into meaningful actions
- 🎯 **Work Sessions** - Clusters changes into logical work units
- 💡 **Intent Detection** - Infers work mode (retouching, restructure, bulk paste, cleanup)
- 💥 **Impact Analysis** - Computes blast radius and risk scores for changes
- 📏 **Drift Detection** - Measures divergence between definitions and operational data
- ✅ **Compliance Engine** - Golden template validation with naming conventions
- 🔍 **Similarity Search** - Find similar stations/studies via fingerprinting
- ⚠️ **Anomaly Detection** - Flags unusual patterns (mass deletion, extreme transforms)
- 📦 **Offline Bundles** - Self-contained HTML viewers for sharing without DB access
- 📚 **Explain Engine** - Generate documentation explaining node sources and relationships
- 🎭 **Demo Mode** - Full demonstration without database (anonymized data generation)
- 🗜️ **Compression** - Optional gzip compression for large snapshots

### v0.4 Features (Commercial-grade packaging)
- 📦 **ExportBundle++** - Enhanced offline bundles with BundleName, Range, Timeline support
- 🎭 **Anonymization** - Stable deterministic pseudonyms (TP-####, TI-####, ST-####, etc.)
- 📖 **DemoStory Mode** - 8-step narrative timeline with DEMO-TALK-TRACK.md generation
- 📋 **manifest.json** - Bundle metadata and file listing

### v0.5 Features (Intelligence Layer) - NEW
- 💥 **ImpactMap v1** - Enhanced blast radius with riskScore 0..100 and breakdown
- 📏 **DriftEngine v1** - Quality/divergence with tolerance classification (Info/Warn/Critical)
- 📈 **Drift Trend** - drift_trend.json tracking across timeline steps
- 🎯 **Deterministic Outputs** - Stable JSON ordering for impact.json and drift.json

## Quick Start

### Prerequisites

- Windows PowerShell 5.1 or later
- Oracle 12c Instant Client (auto-installed by setup script)
- Access to Siemens Process Simulation Oracle database
- Network connectivity to database server

### Installation

1. **Clone the repository**
   ```powershell
   git clone https://github.com/yourusername/PsSchemaBug.git
   cd PsSchemaBug
   ```

2. **Install Oracle Instant Client** (if not already installed)
   ```powershell
   .\src\powershell\database\install-oracle-client.ps1
   ```

3. **Configure database connection**
   ```powershell
   # Copy the template
   Copy-Item config\tnsnames.ora.template tnsnames.ora

   # Edit tnsnames.ora with your database server details
   notepad tnsnames.ora
   ```

4. **Set environment variables**
   ```powershell
   .\src\powershell\database\setup-env-vars.ps1
   ```

5. **Test connection**
   ```powershell
   .\src\powershell\database\test-connection.ps1
   ```

### Usage

#### Launch Interactive Viewer
```powershell
.\src\powershell\main\tree-viewer-launcher.ps1
```

This will:
- Automatically discover available database servers
- Let you select schema and project
- Extract icons from database
- Generate interactive HTML tree viewer
- Open the result in your default browser

#### Generate Tree for Specific Project
```powershell
.\src\powershell\main\generate-tree-html.ps1 `
    -TNSName "YOUR_DB" `
    -Schema "DESIGN12" `
    -ProjectId "18140190" `
    -ProjectName "FORD_DEARBORN"
```

#### Extract Icons Only
```powershell
.\src\powershell\main\extract-icons-hex.ps1 `
    -TNSName "YOUR_DB" `
    -Schema "DESIGN12"
```

### v0.2 Commands (Snapshots & Diffs)

#### Create a Snapshot
```powershell
.\src\powershell\v02\SimTreeNav.ps1 `
    -Mode Snapshot `
    -TNSName "DB01" `
    -Schema "DESIGN12" `
    -ProjectId "18140190" `
    -Label "baseline" `
    -OutDir "./snapshots" `
    -Pretty
```

Output:
```
snapshots/20260115_100000_baseline/
├── nodes.json     # All nodes in canonical format
└── meta.json      # Snapshot metadata
```

#### Compare Two Snapshots
```powershell
.\src\powershell\v02\SimTreeNav.ps1 `
    -Mode Diff `
    -BaselinePath "./snapshots/20260115_100000_baseline" `
    -CurrentPath "./snapshots/20260115_110000_current" `
    -DiffOutputPath "./diffs/diff_001" `
    -GenerateHtml `
    -Pretty
```

Output:
```
diffs/diff_001/
├── diff.json      # Structured diff with all changes
└── diff.html      # Human-readable diff report
```

#### Watch Mode (Continuous Monitoring)
```powershell
.\src\powershell\v02\SimTreeNav.ps1 `
    -Mode Watch `
    -TNSName "DB01" `
    -Schema "DESIGN12" `
    -ProjectId "18140190" `
    -IntervalSeconds 300 `
    -MaxSnapshots 100
```

This will:
- Take a snapshot every 5 minutes
- Compare each snapshot to the previous
- Generate timeline.json with change history
- Auto-cleanup old snapshots (keep last 100)

### v0.3+ Commands (Full Analysis Suite)

#### Run Full Demo (No Database Required)
```powershell
.\Demo.ps1 -NodeCount 200 -MutationRate 0.15 -CreateBundle
```

This demonstrates the complete v0.3+ workflow:
- Generates anonymized baseline snapshot (~200 nodes)
- Applies realistic mutations (renames, moves, rekeys, transforms)
- Runs identity-aware diff engine
- Groups changes into work sessions
- Detects intents (retouching, restructure, bulk paste)
- Computes impact analysis (blast radius)
- Measures drift between pairs
- Checks compliance against golden template
- Detects anomalies
- Creates offline viewer bundle
- Opens HTML reports in browser

#### Compare with Identity Resolution
```powershell
.\src\powershell\v02\SimTreeNav.ps1 `
    -Mode Diff `
    -BaselinePath "./snapshots/baseline" `
    -CurrentPath "./snapshots/current" `
    -UseIdentityMatching `
    -ConfidenceThreshold 0.85 `
    -GenerateHtml
```

#### Analysis Engine Outputs
```
output/demo/
├── diff.json          # Diff with identity resolution
├── sessions.json      # Work session groupings
├── intents.json       # Detected intents (retouching, restructure, etc.)
├── impact.json        # Impact analysis with risk scores
├── drift.json         # Drift measurements between pairs
├── compliance.json    # Compliance report with action items
├── anomalies.json     # Detected anomalies and alerts
├── explain/           # Node explanation documents
│   └── N000001.md     # Markdown explanation for node
└── bundle/            # Offline viewer bundle
    ├── index.html     # Self-contained viewer
    └── data/          # Raw JSON files
```

#### Create Offline Bundle
```powershell
# From Demo output
.\Demo.ps1 -CreateBundle

# Bundle can be shared and opened offline in any browser
```

### v0.4+ Commands (DemoStory & Anonymization)

#### Generate Demo Story (Presentation-Ready)
```powershell
# Full demo with 8-step narrative timeline
.\DemoStory.ps1 -NodeCount 500 -OutDir ./bundles/demo_v04

# With anonymization for safe external sharing
.\DemoStory.ps1 -NodeCount 500 -OutDir ./bundles/demo_anon -Anonymize -CreateZip

# Custom story name
.\DemoStory.ps1 -StoryName "Q4 Production Review" -NodeCount 300 -OutDir ./bundles/q4_review
```

Output:
```
bundles/demo_v04/
├── index.html         # Self-contained offline viewer
├── manifest.json      # Bundle metadata
├── TALK-TRACK.md      # Speaker notes for presentation
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

Also generates `docs/DEMO-TALK-TRACK.md` with scene-by-scene presentation notes.

#### Anonymization Pseudonyms
| Node Type | Prefix | Example |
|-----------|--------|---------|
| ToolPrototype | TP- | TP-4821 |
| ToolInstance | TI- | TI-3927 |
| Station | ST- | ST-7184 |
| Operation | OP- | OP-2956 |
| Location | LOC- | LOC-8412 |
| Resource | RSC- | RSC-1573 |

### v0.5 Commands (ImpactMap & Drift)

#### ImpactMap v1 (Blast Radius)
```powershell
# Get impact for a specific node
$nodes = Get-Content ./snapshots/current/nodes.json | ConvertFrom-Json
$impact = Get-ImpactForNode -NodeId 'N000002' -Nodes $nodes -MaxDepth 5

# Returns:
# - riskScore (0..100)
# - directDependents[] (depth 1)
# - transitiveDependents[] (depth 2..N)
# - upstreamReferences[]
# - breakdown: dependentCountWeight, nodeTypeWeight, criticalLinkWeight
# - why[] (explanatory strings)
```

#### DriftEngine v1 (Quality/Divergence)
```powershell
# Measure drift between prototypes and instances
$nodes = Get-Content ./snapshots/current/nodes.json | ConvertFrom-Json
$drift = Measure-Drift -Nodes $nodes

# Returns:
# - totalPairs, driftedPairs, driftRate
# - avgPositionDelta, maxPositionDelta (mm)
# - avgRotationDelta, maxRotationDelta (deg)
# - topDrifted[] with severity classification
```

#### Drift Tolerances
| Metric | Default Tolerance | Severity Classification |
|--------|-------------------|------------------------|
| Position | 2.0 mm | Info (1-5x), Warn (5-10x), Critical (>10x) |
| Rotation | 0.5 deg | Info (1-5x), Warn (5-10x), Critical (>10x) |

#### Diff Change Types (v0.3)
| Type | Description |
|------|-------------|
| `added` | New node in current |
| `removed` | Node deleted from baseline |
| `rekeyed` | Same logical node, different nodeId (NEW) |
| `renamed` | Name changed |
| `moved` | Parent/path changed |
| `attribute_changed` | Metadata changed |
| `transform_changed` | Location/pose changed |

#### Narrative Action Types (v0.3+)
| Action | Description |
|--------|-------------|
| `rename` | Node was renamed |
| `move` | Node was relocated |
| `rekeyed` | Node was rekeyed (DB ID changed) |
| `retaught_location` | Operation was retaught/relocated |
| `bulk_paste_cluster` | Multiple similar nodes added together |
| `bulk_delete` | Multiple nodes deleted from same parent |
| `station_reorganized` | Multiple related changes in one subtree |
| `tooling_change` | Tool prototype/instance changes |

### v0.3+ Analysis Engines

#### Work Sessions
Groups changes into logical work units based on temporal proximity, spatial locality, and change type patterns.
```json
{
  "sessionId": "session_001",
  "changeCount": 15,
  "subtrees": ["/Station_A/ResourceGroup_1"],
  "changeTypes": ["renamed", "moved"],
  "confidence": 0.85
}
```

#### Intent Detection
Infers what type of work was being done:
| Intent | Description |
|--------|-------------|
| `retouching_points` | Many transform changes in operations |
| `station_restructure` | High moved/renamed in resource groups |
| `bulk_paste_template` | Burst of adds with naming patterns |
| `cleanup` | Bulk deletions |
| `commissioning` | New nodes + transforms being set |
| `joining_update` | MFG/Panel + operation correlation |

#### Impact Analysis
Computes "blast radius" for changes:
- Upstream dependencies (who defines it)
- Downstream dependents (who uses it)
- Risk score (0-1) based on criticality and dependent count
- Risk levels: Info, Low, Medium, High, Critical

#### Drift Detection
Measures divergence between canonical definitions and operational data:
- Position delta (mm)
- Rotation delta (degrees)
- Attribute differences
- Configurable tolerances

#### Compliance Engine
Validates against golden templates:
- Required node types and counts
- Name pattern matching (regex)
- Required link relationships
- Compliance score with action items

#### Anomaly Detection
Flags unusual patterns:
| Anomaly | Description |
|---------|-------------|
| `MassDeletion` | Too many nodes deleted |
| `ExtremeTransform` | Position/rotation beyond bounds |
| `NamingViolations` | High rate of naming issues |
| `UnusualParentMove` | Move to unexpected parent type |
| `RapidChurn` | Same node changed repeatedly |

#### Similarity Search
Finds similar stations/studies:
- Structural fingerprints (tree shape)
- Attribute fingerprints
- Name pattern matching
- Returns top matches with similarity scores

#### Offline Bundles
Self-contained HTML viewer with embedded JSON data:
- All analysis views in one file
- Modern dark theme UI
- Works without database access
- Shareable with stakeholders

### Canonical Node Contract

All nodes follow a consistent JSON schema:

```json
{
  "nodeId": "18140190",
  "nodeType": "ResourceGroup",
  "name": "FORD_DEARBORN",
  "parentId": null,
  "path": "/FORD_DEARBORN",
  "attributes": {
    "externalId": "PP-...",
    "className": "class PmProject",
    "niceName": "Project",
    "typeId": 1
  },
  "fingerprints": {
    "contentHash": "a1b2c3d4e5f67890",
    "attributeHash": "...",
    "transformHash": null
  },
  "source": {
    "table": "COLLECTION_",
    "schema": "DESIGN12"
  }
}
```

**Node Types:**
- `ResourceGroup` - Stations, lines, cells, compound resources
- `ToolPrototype` - Tool definitions
- `ToolInstance` - Robots, equipment, devices
- `OperationGroup` - Studies, compound operations
- `Operation` - Weld, move, pick operations
- `Location` - Locations, shortcuts
- `MfgEntity` - Manufacturing definitions
- `PanelEntity` - Parts, assemblies

**Diff Change Types:**
- `added` - New nodes
- `removed` - Deleted nodes
- `renamed` - Name changed (same nodeId)
- `moved` - Parent changed (same nodeId)
- `attribute_changed` - Metadata changed
- `transform_changed` - Location/pose changed

## Project Structure

```
SimTreeNav/
├── src/powershell/
│   ├── main/                  # Core application scripts
│   │   ├── generate-tree-html.ps1
│   │   ├── tree-viewer-launcher.ps1
│   │   └── extract-icons-hex.ps1
│   ├── utilities/             # Helper modules
│   │   ├── CredentialManager.ps1
│   │   └── PCProfileManager.ps1
│   ├── database/              # Database connection & setup
│   └── v02/                   # v0.2-0.3+ Full Analysis Suite
│       ├── SimTreeNav.ps1     # Main entry point
│       ├── core/
│       │   ├── NodeContract.ps1       # Canonical node schema
│       │   └── IdentityResolver.ps1   # Identity matching & confidence
│       ├── snapshot/
│       │   └── New-Snapshot.ps1
│       ├── diff/
│       │   └── Compare-Snapshots.ps1
│       ├── narrative/
│       │   └── NarrativeEngine.ps1    # Action grouping
│       ├── analysis/                   # v0.3+ Analysis Engines
│       │   ├── WorkSessionEngine.ps1  # Session clustering
│       │   ├── IntentEngine.ps1       # Intent detection
│       │   ├── ImpactEngine.ps1       # Blast radius & risk
│       │   ├── DriftEngine.ps1        # Drift measurement
│       │   ├── ComplianceEngine.ps1   # Golden template validation
│       │   ├── SimilarityEngine.ps1   # Fingerprint matching
│       │   ├── AnomalyEngine.ps1      # Anomaly detection
│       │   └── ExplainEngine.ps1      # Node documentation
│       └── export/
│           └── ExportBundle.ps1       # Offline viewer packaging
├── docs/
│   ├── PRODUCT-VISION.md      # Full product vision & roadmap
│   ├── QUICK-START-GUIDE.md
│   ├── DATABASE-STRUCTURE-SUMMARY.md
│   └── investigation/
├── config/
│   ├── simtreenav.config.json # Configuration
│   └── tnsnames.ora.template
├── snapshots/                 # Snapshot output (generated)
├── queries/                   # SQL scripts by function
├── tests/                     # Pester tests
│   ├── DiffEngine.Tests.ps1
│   ├── IdentityResolver.Tests.ps1
│   ├── WorkSession.Tests.ps1
│   ├── ImpactEngine.Tests.ps1
│   ├── ImpactGraph.Tests.ps1      # v0.5 blast radius tests
│   ├── DriftEngine.Tests.ps1
│   ├── DriftEngineV2.Tests.ps1    # v0.5 quality/divergence tests
│   ├── ComplianceEngine.Tests.ps1
│   ├── Anonymizer.Tests.ps1       # v0.4 anonymization tests
│   └── ExportBundle.Tests.ps1     # v0.4 bundle tests
├── Demo.ps1                   # Full demo without database
└── output/                    # Generated HTML trees & bundles
```

## Documentation

- **[Quick Start Guide](docs/QUICK-START-GUIDE.md)** - Comprehensive getting started guide
- **[Product Vision](docs/PRODUCT-VISION.md)** - Full product vision and roadmap
- **[Oracle Setup](docs/README-ORACLE-SETUP.md)** - Oracle Instant Client installation and configuration
- **[Database Structure](docs/DATABASE-STRUCTURE-SUMMARY.md)** - Schema and table reference
- **[Icon Extraction](docs/investigation/ICON-EXTRACTION-SUCCESS.md)** - How icon extraction works
- **[Custom Ordering](docs/investigation/CUSTOM-ORDERING-SOLUTION.md)** - Node ordering implementation
- **[Query Examples](docs/api/QUERY-EXAMPLES.md)** - SQL query reference

## Testing

Run the Pester tests for the diff engine:

```powershell
# Install Pester if not available
Install-Module -Name Pester -Force -SkipPublisherCheck

# Run all tests
Invoke-Pester -Path .\tests\

# Run specific test file with verbose output
Invoke-Pester -Path .\tests\DiffEngine.Tests.ps1 -Output Detailed
```

**Test Coverage:**
- Node contract creation and validation
- Content/attribute/transform hash stability
- Pipe-delimited parsing
- Node type classification
- Path computation
- Diff detection (add, remove, rename, move)

## Key Features Explained

### Icon Extraction

The tool automatically extracts custom icons from the database using a clever hex encoding approach:

```sql
SELECT
    di.TYPE_ID,
    RAWTOHEX(DBMS_LOB.SUBSTR(di.CLASS_IMAGE, DBMS_LOB.GETLENGTH(di.CLASS_IMAGE), 1))
FROM SCHEMA.DF_ICONS_DATA di
WHERE di.CLASS_IMAGE IS NOT NULL
```

This avoids SQL*Plus truncation issues and successfully extracts all 95+ icons as BMP files.

### Node Ordering

After extensive database investigation, the tool implements custom ordering to match the Siemens Navigation Tree application exactly:

```sql
ORDER BY
    CASE r.OBJECT_ID
        WHEN 18195357 THEN 1  -- P702
        WHEN 18195358 THEN 2  -- P736
        WHEN 18153685 THEN 3  -- EngineeringResourceLibrary
        -- ... etc
    END
```

### Tree Navigation

Uses Oracle hierarchical queries (`CONNECT BY`) to efficiently traverse the entire project tree:

```sql
SELECT LEVEL, c.OBJECT_ID, c.CAPTION_S_, ...
FROM SCHEMA.REL_COMMON r
INNER JOIN SCHEMA.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
START WITH r.FORWARD_OBJECT_ID = @ProjectId
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
```

## Troubleshooting

### Connection Issues

```powershell
# Test Oracle connection
.\src\powershell\database\test-connection.ps1

# Verify environment variables
$env:TNS_ADMIN
$env:PATH  # Should include Oracle Instant Client
```

### Icon Extraction Fails

- Ensure you have READ access to `DF_ICONS_DATA` table
- Check Oracle Instant Client is 12c or later
- Verify `data/icons/` directory exists

### Tree Not Displaying

- Check browser console for JavaScript errors
- Verify HTML file was generated completely
- Ensure icons were extracted successfully

## Performance

- **Icon Extraction**: ~5-10 seconds for 95 icons
- **Tree Generation**: ~10-30 seconds depending on project size
- **Tree Display**: Instant (client-side JavaScript)
- **Database Size**: Works with multi-GB databases
- **Tested With**: 20,000+ nodes, 8.6M+ relationships

## Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Database Schema

The tool works with Siemens Process Simulation Oracle 12c databases:

- **COLLECTION_** - Node data (captions, status, metadata)
- **REL_COMMON** - Parent-child relationships
- **CLASS_DEFINITIONS** - Node type definitions
- **DF_ICONS_DATA** - Icon BLOB storage

See [DATABASE-STRUCTURE-SUMMARY.md](docs/DATABASE-STRUCTURE-SUMMARY.md) for detailed schema documentation.

## Known Limitations

- Hard-coded node ordering for specific project (FORD_DEARBORN)
- Requires READ access to system schemas (DESIGN1-5)
- Windows-only (PowerShell, Oracle Instant Client)
- Large trees (>10MB HTML) may be slow to load in browser

## Roadmap

### Completed (v0.3+)
- [x] Identity resolution with confidence scoring
- [x] Work session grouping
- [x] Intent detection engine
- [x] Impact analysis (blast radius)
- [x] Drift detection
- [x] Compliance engine (golden templates)
- [x] Similarity search
- [x] Anomaly detection
- [x] Offline viewer bundles
- [x] Node explanation engine

### Future
- [ ] Configuration-based node ordering
- [ ] Real-time database sync
- [ ] Cross-platform support (PowerShell Core)
- [ ] Web-based interface with live updates
- [ ] LLM integration for natural language summaries
- [ ] CI/CD integration (automated quality gates)
- [ ] Multi-project comparison dashboards

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Siemens Process Simulation database structure
- Oracle hierarchical query capabilities
- Community feedback and testing

## Support

- **Documentation**: [docs/](docs/)
- **Issues**: [GitHub Issues](https://github.com/yourusername/PsSchemaBug/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/PsSchemaBug/discussions)

---

**Note**: This is a third-party tool and is not officially supported by Siemens. Use at your own risk.

## Quick Reference

```powershell
# Full workflow
cd PsSchemaBug
.\src\powershell\main\tree-viewer-launcher.ps1  # Interactive mode

# Manual steps
.\src\powershell\main\extract-icons-hex.ps1 -TNSName "DB" -Schema "DESIGN12"
.\src\powershell\main\generate-tree-html.ps1 -TNSName "DB" -Schema "DESIGN12" -ProjectId "18140190" -ProjectName "PROJECT"

# Output
data\output\navigation-tree.html  # Open in browser
```

---

Made with ❤️ for Process Simulation engineers
