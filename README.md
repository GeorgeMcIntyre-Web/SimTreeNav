# Siemens Process Simulation - Tree Viewer

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue)](https://github.com/PowerShell/PowerShell)
[![Oracle](https://img.shields.io/badge/Oracle-12c-red)](https://www.oracle.com/database/)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

A PowerShell-based tree navigation viewer for Siemens Process Simulation databases. Extracts, visualizes, and navigates hierarchical project structures with full icon support.

![Tree Viewer Preview](docs/assets/tree-viewer-screenshot.png)

## Features

- 🌳 **Full Tree Navigation** - Complete hierarchical visualization of Process Simulation projects
- 🎨 **Icon Extraction** - Automatic extraction and display of 95+ custom icons from database BLOB fields
- 🔍 **Search Functionality** - Real-time search across all nodes
- 📊 **Multi-Project Support** - Works with DESIGN1-5 schemas
- ⚡ **Interactive HTML** - Expand/collapse nodes, search, and navigate efficiently
- 🔧 **Custom Ordering** - Matches Siemens application node ordering
- 🚀 **Easy Setup** - Automated Oracle client installation and configuration

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

## Documentation

- **[Quick Start Guide](docs/QUICK-START-GUIDE.md)** - Comprehensive getting started guide
- **[Oracle Setup](docs/README-ORACLE-SETUP.md)** - Oracle Instant Client installation and configuration
- **[Database Structure](docs/DATABASE-STRUCTURE-SUMMARY.md)** - Schema and table reference
- **[Icon Extraction](docs/investigation/ICON-EXTRACTION-SUCCESS.md)** - How icon extraction works
- **[Custom Ordering](docs/investigation/CUSTOM-ORDERING-SOLUTION.md)** - Node ordering implementation
- **[Query Examples](docs/api/QUERY-EXAMPLES.md)** - SQL query reference

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

- [ ] Configuration-based node ordering
- [ ] Export to JSON/XML formats
- [ ] Node diff/comparison between projects
- [ ] Real-time database sync
- [ ] Cross-platform support (PowerShell Core)
- [ ] Web-based interface

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
