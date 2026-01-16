# Changelog

All notable changes to SimTreeNav will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-01-16

### Added

#### Engineering Maturity
- **CI/CD Pipeline**: GitHub Actions workflow with Pester tests, PSScriptAnalyzer lint, determinism checks
- **Release Automation**: `Release.ps1` command that prints version and builds artifacts
- **Build Scripts**: `Build-Release.ps1`, `Verify-Release.ps1`, `New-Changelog.ps1`
- **Version Manifest**: `manifest.json` with schemaVersion and appVersion tracking
- **PSScriptAnalyzer Settings**: Lightweight lint configuration for PowerShell style conventions

#### Repository Hygiene
- **CONTRIBUTING.md**: Comprehensive contribution guidelines with coding standards
- **SECURITY.md**: Security policy with vulnerability disclosure process
- **Issue Templates**: Bug report and feature request templates
- **Pull Request Template**: Standardized PR checklist

#### Documentation
- **ARCHITECTURE.md**: System architecture with component diagrams
- **FEATURES.md**: Complete feature documentation
- **DEPLOYMENT.md**: Installation and configuration guide
- **ROADMAP.md**: Development roadmap with version planning
- **LICENSE**: MIT license file

#### Testing
- **Pester Test Suite**: Tests for manifest, project structure, security compliance, build scripts
- **Determinism Gate**: CI verification for required files and no hardcoded credentials
- **DeployPack + VerifyDeploy**: Release packaging and verification workflow

### Changed
- Updated README with CI badge, version badge, and improved documentation links
- Updated .gitignore to properly exclude sensitive files while including tests
- Reorganized documentation structure for better discoverability

### Security
- Added credential detection in CI pipeline
- Documented security-nonintrusive design (read-only operations)
- Added security compliance tests

---

## [0.3.0] - 2026-01-13

### Initial Release

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