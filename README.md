# Siemens Process Simulation - Tree Viewer

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)
[![Oracle](https://img.shields.io/badge/Oracle-12c-red)](https://www.oracle.com/database/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A PowerShell-based tree navigation viewer for Siemens Process Simulation databases. Extracts, visualizes, and navigates hierarchical project structures with full icon support.

![Tree Viewer Preview](docs/assets/tree-viewer-screenshot.png)

## Features

- 🌳 **Full Tree Navigation** - Complete hierarchical visualization with 632K+ nodes, 310K+ unique nodes
- 🎨 **Icon Extraction** - Automatic extraction and display of 221 custom icons with inheritance support
- 🔍 **Search Functionality** - Real-time search across all nodes with highlighting
- 📊 **Multi-Project Support** - Works with DESIGN1-12 schemas
- ⚡ **Interactive HTML** - Lazy loading for instant display (2-5s load time)
- 🔧 **SEQ_NUMBER Ordering** - Matches Siemens application node ordering exactly
- 🚀 **Three-Tier Caching** - Icon (7d), tree (24h), and user activity (1h) caching for 87% faster generation
- ⏱️ **Performance** - Script generation: 8-10s (cached) / 62s (first run)
- 👥 **User Activity** - Shows checked-out items and owners
- 🔄 **Multi-Parent Support** - Handles nodes with multiple parents correctly
- 🧪 **Testing** - Automated validation scripts included

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

#### Generate Management Dashboard (Phase 2)

Track work activity across 5 core work types: Project DB, Resource Library, Part/MFG Library, IPA Assembly, and Study Nodes (including operations, movements, and welds).

```powershell
# One-command execution
.\management-dashboard-launcher.ps1 `
    -TNSName "SIEMENS_PS_DB_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18140190 `
    -DaysBack 7
```

This will:
- Query database for work activity in the last 7 days
- Track simple moves vs. world location changes (≥1000mm threshold)
- Attribute activity to users via PROXY/USER_ tables
- Generate interactive HTML dashboard
- Open the result in your default browser

**Output:** `data\output\management-dashboard-DESIGN12-18140190.html`

See [docs/PHASE2_DASHBOARD_SPEC.md](docs/PHASE2_DASHBOARD_SPEC.md) for full specification.

#### Extract Icons Only
```powershell
.\src\powershell\main\extract-icons-hex.ps1 `
    -TNSName "YOUR_DB" `
    -Schema "DESIGN12"
```

## Project Structure

```
PsSchemaBug/
├── src/
│   └── powershell/
│       ├── main/              # Core application scripts
│       ├── utilities/         # Helper utilities
│       └── database/          # Database connection & setup
├── docs/
│   ├── QUICK-START-GUIDE.md   # Detailed getting started guide
│   ├── README-ORACLE-SETUP.md # Oracle setup instructions
│   ├── DATABASE-STRUCTURE-SUMMARY.md
│   ├── investigation/         # Technical discoveries
│   └── api/                   # Query examples & API docs
├── config/
│   ├── database-servers.json  # Database server configuration
│   ├── tree-viewer-config.json # Application settings
│   └── tnsnames.ora.template  # Oracle TNS template
├── data/
│   ├── icons/                 # Extracted BMP icons (generated)
│   └── output/                # Generated HTML trees (generated)
├── queries/
│   ├── icon-extraction/       # Icon-related queries
│   ├── tree-navigation/       # Tree traversal queries
│   ├── analysis/              # Database analysis queries
│   └── investigation/         # Research queries
└── tests/                     # Test files and outputs
```

## Cache Management

The tool uses three-tier caching for optimal performance:

```powershell
# Check cache status
.\cache-status.ps1

# Clear all caches (force full refresh)
Remove-Item *-cache-*

# Clear specific caches
Remove-Item icon-cache-*.json        # Icons (7-day lifetime)
Remove-Item tree-cache-*.txt         # Tree data (24-hour lifetime)
Remove-Item user-activity-cache-*.js # User activity (1-hour lifetime)
```

**Cache lifetimes:**
- Icons: 7 days (rarely change)
- Tree data: 24 hours (daily updates)
- User activity: 1 hour (frequent changes)

All caches auto-refresh when expired. See [CACHE-OPTIMIZATION-COMPLETE.md](CACHE-OPTIMIZATION-COMPLETE.md) for details.

## Documentation

### Getting Started
- **[Quick Start Guide](docs/QUICK-START-GUIDE.md)** - Comprehensive getting started guide
- **[Oracle Setup](docs/README-ORACLE-SETUP.md)** - Oracle Instant Client installation and configuration

### Performance & Optimization
- **[Cache Optimization](CACHE-OPTIMIZATION-COMPLETE.md)** - Three-tier caching system (87% faster!)
- **[Browser Performance](BROWSER-PERF-FIX.md)** - Lazy loading and optimization
- **[Performance Metrics](PERFORMANCE.md)** - Detailed performance documentation

### Testing & Validation
- **[Search Test Plan](SEARCH-TEST-PLAN.md)** - Comprehensive search testing guide
- **[UAT Plan](UAT-PLAN.md)** - User acceptance testing procedures
- **[Testing Guide](TESTING.md)** - Automated validation scripts
- **[Node Extraction Regression Test](test-node-extraction-regression.ps1)** - Validates MFGFEATURE_/MODULE_/TxProcessAssembly extraction
- **[Coverage Check](RUN-COVERAGE-CHECK.ps1)** - Displays node type counts in generated tree

### Technical Reference
- **[Database Structure](docs/DATABASE-STRUCTURE-SUMMARY.md)** - Schema and table reference
- **[Icon Extraction](docs/investigation/ICON-EXTRACTION-SUCCESS.md)** - How icon extraction works
- **[Custom Ordering](docs/investigation/CUSTOM-ORDERING-SOLUTION.md)** - Node ordering implementation
- **[Query Examples](docs/api/QUERY-EXAMPLES.md)** - SQL query reference

### Bug Fixes & Changelog
- **[Icon Cache Bug Fix](BUGFIX-CACHE-NULL-PATH.md)** - Icon caching null path fix
- **[MFGFEATURE_/MODULE_ Missing Nodes Fix](BUGFIX-MFGFEATURE-MODULE-MISSING.md)** - Fixed incorrect WHERE clauses causing missing nodes
- **[Tree Cache Bug Fix](BUGFIX-TREE-CACHE-NULL-PATH.md)** - Tree caching null path fix
- **[Status](STATUS.md)** - Project status and completed items

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

### Script Generation (with Three-Tier Caching)
- **First run**: ~62 seconds (creates all caches)
- **Subsequent runs**: **8-10 seconds** (87% faster!)
- **Icon extraction**: 0.06s (cached) vs 15-20s (first run)
- **Database query**: instant (cached) vs 44s (first run)
- **User activity**: instant (cached) vs 8-10s (first run)

### Browser Performance (with Lazy Loading)
- **Initial load**: 2-5 seconds (was 30-60s before optimization)
- **Memory usage**: 50-100MB (was 500MB+ before)
- **Initial render**: ~50-100 nodes (was 310K+ nodes before)
- **Expand/collapse**: Instant
- **Search**: <3 seconds even with thousands of results

### Scalability
- **Tested with**: 632,669 tree lines, 310,203 unique nodes
- **Database size**: Multi-GB databases
- **HTML output**: ~90MB per tree
- **Cache management**: Automatic, zero configuration

See [CACHE-OPTIMIZATION-COMPLETE.md](CACHE-OPTIMIZATION-COMPLETE.md) and [PERFORMANCE.md](PERFORMANCE.md) for detailed metrics.

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

- Requires READ access to system schemas (DESIGN1-12)
- Windows-only (PowerShell 5.1+, Oracle Instant Client)
- Search only finds rendered nodes (lazy loading limits deep search)
- Cache files not synchronized across machines (local only)

## Roadmap

### Phase 1: Tree Viewer (Complete)
- [x] Three-tier caching system ✅ (Complete - 87% faster!)
- [x] Lazy loading for browser performance ✅ (Complete - 2-5s load time)
- [x] Icon inheritance support ✅ (Complete - 221 icons)
- [x] Multi-parent node support ✅ (Complete)
- [x] User activity tracking ✅ (Complete - shows checked-out items)
- [x] Automated testing ✅ (Complete - validation scripts)
- [x] RobcadStudy health report ✅ (Complete - lint report for study names)

### Phase 2: Management Dashboard (In Progress)
- [x] Dashboard specification ✅ (Complete - [docs/PHASE2_DASHBOARD_SPEC.md](docs/PHASE2_DASHBOARD_SPEC.md))
- [x] Acceptance criteria ✅ (Complete - [docs/PHASE2_ACCEPTANCE.md](docs/PHASE2_ACCEPTANCE.md))
- [ ] SQL queries for 5 work types (Agent 02)
- [ ] PowerShell data extraction script (Agent 03)
- [ ] HTML dashboard generator (Agent 04)
- [ ] Wrapper script + verification tests (Agent 05)

### Future Enhancements
- [ ] Search result counter and navigation
- [ ] Export to JSON/XML formats
- [ ] Node diff/comparison between projects
- [ ] Real-time database sync
- [ ] Cross-platform support (PowerShell Core)
- [ ] Web-based interface
- [ ] Shared cache server for teams

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
