# SimTreeNav Performance Budget

This document defines performance targets for SimTreeNav operations with large trees (50k+ nodes).

## Target Metrics

### Extraction & Snapshot Performance

| Operation | Node Count | Target Time | Target Memory | Notes |
|-----------|------------|-------------|---------------|-------|
| Data Extraction | 50,000 | < 60s | < 300MB | Paged queries, streaming |
| Data Extraction | 100,000 | < 120s | < 500MB | Paged queries, streaming |
| HTML Generation | 50,000 | < 30s | < 500MB | Virtualized viewer |
| HTML Generation | 100,000 | < 60s | < 800MB | Virtualized viewer |
| JSON Export | 50,000 | < 15s | < 400MB | Streaming writer |
| JSON Export | 100,000 | < 30s | < 600MB | Streaming writer |

### Viewer Performance

| Metric | Target | Notes |
|--------|--------|-------|
| Initial Load | < 5s | Parse + build flat list |
| Scroll Render | < 16ms | 60fps target |
| Search (first result) | < 500ms | Incremental indexing |
| Expand/Collapse | < 100ms | Rebuild flat list |
| Memory (50k nodes) | < 200MB | Browser heap |
| Memory (100k nodes) | < 400MB | Browser heap |

### Output Sizes

| Output | Node Count | Raw Size | Compressed Size |
|--------|------------|----------|-----------------|
| HTML (virtualized) | 50,000 | ~15-25MB | ~3-5MB |
| HTML (virtualized) | 100,000 | ~30-50MB | ~6-10MB |
| nodes.json | 50,000 | ~8-12MB | ~1-2MB |
| nodes.json | 100,000 | ~16-25MB | ~2-4MB |

## Hard Limits

### MaxNodesInViewer

The viewer enforces a configurable limit on nodes:

- **Default**: 100,000 nodes
- **Recommended for smooth performance**: 50,000 nodes
- **Absolute maximum**: 200,000 nodes (with warnings)

When the limit is exceeded:
1. A warning banner is displayed
2. Performance degradation is expected
3. Consider using filtered views or paged loading

### Memory Caps

| Component | Limit | Action on Exceed |
|-----------|-------|------------------|
| PowerShell extraction | 2GB | Use paged queries |
| Browser (viewer) | 1GB | Show warning, suggest filtering |
| JSON export | 1GB | Use streaming writer |

## Performance Optimization Techniques

### 1. Paging Support for DB Queries

```powershell
# Use paged queries for large extractions
Invoke-PagedTreeQuery -TNSName $tns -Schema $schema -ProjectId $id -PageSize 10000
```

### 2. Streaming JSON Writers

```powershell
# Stream nodes directly to file
$writer = New-StreamingJsonWriter -Path "nodes.json"
$writer.Open()
foreach ($node in $nodes) {
    $writer.WriteNode($node)
}
$writer.Close()
```

### 3. Virtual Scrolling in Viewer

The virtualized viewer only renders visible nodes:
- Renders ~50-100 nodes at a time
- Uses overscan for smooth scrolling
- Rebuilds flat list on expand/collapse

### 4. Incremental Search Indexing

Search builds index lazily:
- First 1000 matches returned immediately
- Full index built in background
- Debounced input (300ms delay)

### 5. Optional Gzip Compression

```powershell
# Compress output files
Compress-OutputFile -InputPath "nodes.json" -DeleteOriginal
```

Typical compression ratios: 80-90% reduction

## Measuring Performance

### Using PerfHarness.ps1

```powershell
# Run benchmarks with 50k nodes
.\PerfHarness.ps1 -NodeCount 50000

# Run benchmarks with 100k nodes
.\PerfHarness.ps1 -NodeCount 100000 -OutputDir "large-test"
```

### Performance Metrics Output

Each operation writes metrics to:
- `meta.json` - Full metrics including queries, memory snapshots
- `probe.json` - Lightweight status for monitoring

Example `probe.json`:
```json
{
  "status": "complete",
  "nodeCount": 50000,
  "totalDurationMs": 25432,
  "totalRowsScanned": 50000,
  "peakMemoryMB": 412,
  "timestamp": "2025-01-16T10:30:00Z"
}
```

## Performance Regression Testing

Run before each release:

```powershell
# Standard benchmark suite
.\PerfHarness.ps1 -NodeCount 50000
.\PerfHarness.ps1 -NodeCount 100000

# Compare results against baseline
# Results in perf-test-output/benchmark-results.json
```

### Baseline Results (Reference)

These are target baseline results for comparison:

```
50,000 Nodes:
  Data Generation: < 5s
  Snapshot Generation: < 30s
  Peak Memory: < 500MB
  Output Size: ~20MB HTML, ~10MB JSON

100,000 Nodes:
  Data Generation: < 10s
  Snapshot Generation: < 60s
  Peak Memory: < 800MB
  Output Size: ~40MB HTML, ~20MB JSON
```

## Browser Compatibility

The virtualized viewer has been tested on:

| Browser | 50k Nodes | 100k Nodes | Notes |
|---------|-----------|------------|-------|
| Chrome 120+ | Excellent | Good | Recommended |
| Edge 120+ | Excellent | Good | Chromium-based |
| Firefox 120+ | Good | Fair | Higher memory usage |
| Safari 17+ | Good | Fair | macOS only |

### Minimum Requirements

- Modern browser (2023+)
- 8GB RAM recommended
- Hardware acceleration enabled

## Troubleshooting Performance Issues

### Slow Extraction

1. Check database connectivity and query plans
2. Enable paged queries: `-PageSize 5000`
3. Check for network latency

### Slow HTML Generation

1. Use virtualized generator
2. Skip JSON export if not needed
3. Disable compression for faster generation

### Slow Viewer

1. Reduce initial expand level
2. Use search instead of manual navigation
3. Clear browser cache
4. Check browser developer tools for memory issues

### High Memory Usage

1. Use streaming JSON writer
2. Enable paged queries
3. Close other browser tabs
4. Increase page file/swap

## Future Improvements

1. **Web Workers** - Move parsing/indexing to background thread
2. **IndexedDB** - Persist large datasets locally
3. **Lazy JSON Parsing** - Parse nodes on demand
4. **Server-side Filtering** - Only fetch visible subtrees
5. **Progressive Loading** - Load tree incrementally
