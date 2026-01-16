# Changelog

All notable changes to SimTreeNav will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.6.0] - 2026-01-16 - Deployable Product Surface

### Added

#### Deployment Tools
- **DeployPack.ps1** - One-command deployment package creation
  - Creates static site folder ready for Cloudflare Pages or GitHub Pages
  - Supports custom `basePath` for subdirectory deployment
  - Generates security headers and hosting configuration
  - Static and Secure deployment modes

- **VerifyDeploy.ps1** - Deployment validation for CI/CD
  - Validates all required files exist
  - Checks for external network URLs (offline compliance)
  - Verifies manifest schema version
  - Strict mode for treating warnings as errors

- **DemoStory.ps1** - Synthetic data generation
  - Generates realistic tree structures with configurable node count
  - Creates timeline with multiple snapshots
  - Generates diff, actions, impact, and drift data
  - Useful for testing and demonstrations without database access

#### Pro Viewer UX
- **3-Pane Layout** - Tree, Timeline/Activity, Inspector panels
- **Virtualized Tree Rendering** - Handle 10,000+ nodes efficiently
- **Timeline Selector** - Navigate between snapshots with play mode
- **Changed-Only Mode** - Toggle to show only modified nodes
- **Cross-Highlighting** - Click actions/diffs to highlight nodes in tree
- **Inspector Panels**:
  - Identity (logicalId, matchConfidence, fingerprint)
  - Properties (all node attributes)
  - Drift Pairing (confidence, deltas)
  - Impact Analysis (risk score, reasons)
  - Links (references, related nodes)
- **Keyboard Shortcuts**:
  - `/` - Focus search
  - `n/p` - Next/previous change
  - Arrow keys - Navigate tree
  - `c` - Toggle changed-only mode
- **Copy/Export** - Copy node path/ID, export subtree JSON

#### Architecture
- **Modular JS Architecture**:
  - `state.js` - Centralized state management
  - `dataLoader.js` - Data loading with basePath support
  - `treeView.js` - Virtualized tree rendering
  - `timelineView.js` - Timeline and activity feed
  - `inspectorView.js` - Node detail panel
  - `app.js` - Main application controller
- **basePath Support** - Deploy to any URL path

#### Documentation
- **docs/DEPLOYMENT.md** - Comprehensive deployment guide
- **docs/ROADMAP.md** - Version roadmap (v0.6 - v1.0)
- **docs/ADR-0001-Deployment-Model.md** - Architecture decision record
- **docs/CLOUD-BLUEPRINT.md** - Optional cloud architecture design

#### Testing
- **Pester Tests**:
  - DeployPack.Tests.ps1 - Deployment package validation
  - VerifyDeploy.Tests.ps1 - Verification tool tests
  - ViewerSmoke.Tests.ps1 - Viewer structure validation
- **GitHub Actions CI** - Automated testing on push/PR

### Changed
- Viewer now uses modular JavaScript architecture
- All assets use relative paths for deployment flexibility
- Data files moved to `data/` subdirectory in bundles

### Technical Details
- No external CDN dependencies (works offline)
- Deterministic outputs (same input → identical output)
- MaxNodesInViewer enforcement with warning banner
- Dark mode support via CSS custom properties

## [Unreleased]

### Initial Release - 2026-01-13

#### Added
- Interactive tree viewer launcher with dynamic server/schema discovery
- Complete tree generation from Oracle database
- Icon extraction from BLOB fields using RAWTOHEX encoding
- Support for DESIGN1-5 schemas
- HTML tree viewer with expand/collapse functionality
- Search functionality across all nodes
- Custom node ordering matching Siemens application
- Oracle 12c Instant Client installation script
- Database connection and configuration utilities
- Comprehensive SQL query library (130+ queries)
- Full documentation and investigation notes

#### Features
- **Icon Extraction**: Successfully extracts 95+ icons from DF_ICONS_DATA table
- **Tree Navigation**: Full hierarchical tree with expand/collapse
- **Search**: Real-time node search functionality
- **Custom Ordering**: Matches Siemens Navigation Tree application order
- **Multi-Schema Support**: Works with DESIGN1-5 schemas

#### Technical Highlights
- Solved SQL*Plus BLOB truncation issue using RAWTOHEX
- Implemented custom node ordering matching Siemens app
- Discovered and documented ghost node (PartInstanceLibrary)
- Extracted 95+ custom icons from database
- Hierarchical query optimization for large trees

## Project Statistics

- **PowerShell Scripts**: 12 production scripts
- **SQL Queries**: 133 investigation queries (organized into categories)
- **Documentation**: 13 markdown files
- **Icons Extracted**: 95+ custom BMP icons
- **Database Support**: Oracle 12c, DESIGN1-5 schemas
- **Code Coverage**: Icon extraction, tree generation, database analysis
- **Lines of Code**: ~2,500+ lines of PowerShell, ~4,000+ lines of SQL

## File Organization Summary

### Source Code (src/)
- **12 PowerShell scripts** organized by function
- **3 main tools**: tree viewer, tree generator, icon extractor
- **4 database utilities**: install, setup, connect, test
- **4 utility scripts**: queries, icon mapping, database exploration

### Documentation (docs/)
- **3 main guides**: Quick Start, Oracle Setup, Database Structure
- **7 investigation docs**: Icon extraction, node ordering solutions
- **2 API docs**: Query examples, project names

### Queries (133 SQL files organized into 4 categories)
- **icon-extraction/** - 18 queries for icon extraction research
- **tree-navigation/** - 9 queries for tree traversal
- **analysis/** - 55 analysis and check queries
- **investigation/** - 50 research and exploration queries

### Configuration
- Database server configuration
- Tree viewer settings
- TNS name template

### Data & Output
- Icons extracted from database (data/icons/)
- Generated HTML trees (data/output/)
- Both ignored in Git (regenerated from source)

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Create proper folder structure for the project", "status": "completed", "activeForm": "Creating proper folder structure"}, {"content": "Move PowerShell scripts to src/ directory", "status": "completed", "activeForm": "Moving PowerShell scripts"}, {"content": "Organize SQL queries into categorized folders", "status": "completed", "activeForm": "Organizing SQL queries"}, {"content": "Move documentation to docs/ folder", "status": "completed", "activeForm": "Moving documentation"}, {"content": "Organize generated outputs and data files", "status": "completed", "activeForm": "Organizing outputs and data"}, {"content": "Create .gitignore file", "status": "completed", "activeForm": "Creating .gitignore"}, {"content": "Create main README.md", "status": "completed", "activeForm": "Creating main README"}, {"content": "Clean up temporary and test files", "status": "completed", "activeForm": "Cleaning up temporary files"}]