# Changelog

All notable changes to the Siemens Process Simulation Tree Viewer project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-01-16

### Large Tree Support Release

This release adds comprehensive support for very large trees (50k+ nodes) with
performance optimizations, virtualized viewing, and streaming data handling.

### Added

#### A) Extraction & Snapshot Performance
- **Paging Support** (`PagedQueries.ps1`): Execute large queries in chunks to prevent memory exhaustion
  - `Invoke-PagedTreeQuery`: Fetch tree data with configurable page size
  - `Get-EstimatedRowCount`: Quick node count estimation before extraction
- **Streaming JSON Writers** (`StreamingJsonWriter.ps1`): Write large JSON files without holding entire array in memory
  - `New-StreamingJsonWriter`: Create streaming writer instances
  - `Write-NodesJsonStreaming`: Stream nodes directly to disk
- **Performance Metrics** (`PerformanceMetrics.ps1`): Track and record operation performance
  - `Start-PerfSession`: Begin tracking session
  - `Record-QueryMetrics`: Log query performance (rowsScanned, durationMs)
  - `Record-MemorySnapshot`: Capture memory usage at key points
  - `Write-MetaJson`: Output full metrics to meta.json
  - `Write-ProbeJson`: Output lightweight status to probe.json

#### B) Output Optimization
- **Optional Gzip Compression** (`CompressionUtils.ps1`): Reduce output file sizes by 80-90%
  - `Compress-OutputFile`: Gzip any output file
  - `Compress-TreeOutputs`: Batch compress nodes.json, diff.json, etc.
- **Index Files**: Fast node lookups without parsing entire JSON
  - `node_index.json`: id -> offset mapping
  - `path_index.json`: full path -> id mapping
- **Deterministic Ordering**: Consistent output for diff operations

#### C) Viewer Performance
- **Virtualized Tree Viewer** (`generate-virtualized-tree-html.ps1`): Handles 50k+ nodes smoothly
  - Virtual scrolling: Only renders visible nodes (~50-100 at a time)
  - Lazy loading: Parse data on demand
  - Incremental search indexing: First 1000 results instantly
- **MaxNodesInViewer Cap**: Configurable limit with clear warning banner
  - Default: 100,000 nodes
  - Shows warning when exceeded
- **V3 Launcher** (`tree-viewer-launcher-v3.ps1`): Auto-detects large trees
  - Estimates node count before generation
  - Prompts to use virtualized viewer for large trees

#### D) Performance Test Harness
- **PerfHarness.ps1**: Benchmark tool for performance validation
  - Generates synthetic 50k/100k node datasets
  - Measures snapshot, diff, and export operations
  - Outputs detailed timing and memory stats
  - Compares against budget targets
- **PERFORMANCE-BUDGET.md**: Target runtimes and memory limits
  - 50k nodes snapshot: < 30s, < 500MB memory
  - 100k nodes snapshot: < 60s, < 800MB memory
  - Viewer scroll render: < 16ms (60fps target)

### Changed
- Tree viewer now defaults to virtualized mode for trees > 10,000 nodes
- JSON export uses streaming by default for trees > 5,000 nodes
- Added memory and timing metrics to all major operations

### Performance Targets

| Operation | 50k Nodes | 100k Nodes |
|-----------|-----------|------------|
| Snapshot Generation | < 30s | < 60s |
| Peak Memory | < 500MB | < 800MB |
| Viewer Initial Load | < 5s | < 10s |
| Scroll Render | < 16ms | < 16ms |

### New Files
- `src/powershell/utilities/PerformanceMetrics.ps1`
- `src/powershell/utilities/StreamingJsonWriter.ps1`
- `src/powershell/utilities/CompressionUtils.ps1`
- `src/powershell/utilities/PagedQueries.ps1`
- `src/powershell/main/generate-virtualized-tree-html.ps1`
- `src/powershell/main/tree-viewer-launcher-v3.ps1`
- `PerfHarness.ps1`
- `docs/PERFORMANCE-BUDGET.md`

---

## [1.0.0] - 2026-01-13

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

- **PowerShell Scripts**: 20+ production scripts
- **SQL Queries**: 133 investigation queries (organized into categories)
- **Documentation**: 15+ markdown files
- **Icons Extracted**: 95+ custom BMP icons
- **Database Support**: Oracle 12c, DESIGN1-5 schemas
- **Lines of Code**: ~4,000+ lines of PowerShell, ~4,000+ lines of SQL
