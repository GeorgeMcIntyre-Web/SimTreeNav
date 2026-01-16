# SimTreeNav Security & Non-Intrusive Design

## Read-Only Guarantee

SimTreeNav operates in **strict read-only mode**. This is a fundamental architectural constraint, not an optional setting.

### What We Query

| Table/View | Purpose | Typical Row Count |
|------------|---------|-------------------|
| `COLLECTION_*` views | Tree structure, parent-child relationships | Varies by schema |
| Object metadata | Names, external IDs, class names | Same as tree |
| Transform data | Position/rotation for drift analysis | Same as tree |
| Timestamps | Created/modified dates for session grouping | Same as tree |

### What We Do NOT Do

| Action | Status | Reason |
|--------|--------|--------|
| INSERT/UPDATE/DELETE | Never | Read-only by design |
| CREATE TABLE/VIEW | Never | No schema modifications |
| License bypass | Never | No interaction with licensing |
| Stored procedure calls | Never | Only SELECT queries |
| System table access | Never | No administrative queries |
| Schema dumps | Never | No structure export |

### Enforcement

1. **Connection Level**: Use a dedicated read-only database user (see `scripts/create-readonly-user.sql`)
2. **Query Level**: All queries are explicit SELECT statements
3. **Code Level**: No write operations exist in the codebase
4. **Audit Level**: All queries are logged in probe metrics

---

## Non-Intrusive Design

SimTreeNav is designed to have minimal impact on database performance.

### Probe Metrics

Every extraction includes a `probe` section in the metadata:

```json
{
  "probe": {
    "queriesExecuted": 3,
    "totalRowsScanned": 15420,
    "totalDurationMs": 847,
    "avgQueryDurationMs": 282,
    "peakMemoryEstimateMb": 12.4
  }
}
```

| Metric | Description | Healthy Range |
|--------|-------------|---------------|
| `queriesExecuted` | Number of SELECT statements | 1-10 per extraction |
| `totalRowsScanned` | Rows read across all queries | Depends on tree size |
| `totalDurationMs` | Wall-clock time for extraction | < 5000ms typical |
| `avgQueryDurationMs` | Mean query execution time | < 1000ms |
| `peakMemoryEstimateMb` | Estimated client-side memory | < 100MB |

### Two-Stage Watch Probe

For continuous monitoring (watch mode), SimTreeNav uses a two-stage approach:

**Stage A: Lightweight Detection**
- Query only timestamp columns
- Compare against last known state
- Minimal row count and duration
- Runs frequently (configurable interval)

**Stage B: Scoped Deep Probe**
- Triggered only when Stage A detects changes
- Queries only changed subtrees when possible
- Full data extraction for changed nodes

### Recommended Intervals

| Environment | Stage A Interval | Notes |
|-------------|------------------|-------|
| Development | 30 seconds | Fast feedback |
| Staging | 2 minutes | Balanced |
| Production | 5-10 minutes | Conservative |

### Query Optimization

1. **Parameterized Queries**: Reusable execution plans
2. **Index Hints**: Use existing indexes where available
3. **Pagination**: Large trees are extracted in chunks
4. **Caching**: Repeat extractions skip unchanged data

---

## Safe Configuration Options

### Safe Mode Flags

```powershell
# Minimal extraction (fastest, least intrusive)
.\Extract-Tree.ps1 -Schema DESIGN12 -RootId 12345 -SafeMode

# Custom probe interval
.\Watch-Tree.ps1 -Schema DESIGN12 -Interval 600  # 10 minutes

# Limit row count
.\Extract-Tree.ps1 -Schema DESIGN12 -MaxNodes 5000
```

### Config File Settings

```json
{
  "extraction": {
    "safeMode": true,
    "maxNodesPerQuery": 1000,
    "queryTimeoutSeconds": 30,
    "stageBThreshold": 10
  },
  "probe": {
    "enabled": true,
    "logLevel": "info"
  }
}
```

---

## Interpreting Probe Output

### Example Meta File

```json
{
  "extractedAt": "2025-01-15T14:30:00Z",
  "schema": "DESIGN12",
  "rootId": "12345",
  "nodeCount": 8542,
  "probe": {
    "queriesExecuted": 2,
    "totalRowsScanned": 8542,
    "totalDurationMs": 423,
    "avgQueryDurationMs": 211,
    "peakMemoryEstimateMb": 8.2
  }
}
```

### Warning Signs

| Condition | Action |
|-----------|--------|
| `totalDurationMs > 10000` | Consider SafeMode or smaller subtree |
| `queriesExecuted > 20` | Check for pagination issues |
| `peakMemoryEstimateMb > 500` | Use MaxNodes limit |

---

## Audit Trail

### What Is Logged

1. **Connection Metadata**: Schema, timestamp, user context
2. **Query Signatures**: Query type (not full SQL text)
3. **Performance Metrics**: Duration, row counts
4. **Error Events**: Failed queries, timeouts

### What Is NOT Logged

- Database credentials (never stored)
- Full SQL query text (only signatures)
- Actual data content (only structure)

---

## Compliance Considerations

### GDPR / Data Privacy

SimTreeNav extracts structural metadata (node names, hierarchies) but does not:
- Store personal data from the database
- Export user credentials or session data
- Create external copies of sensitive content

### Audit Requirements

The probe metrics system provides:
- Immutable extraction timestamps
- Query count and duration logs
- Clear record of what was accessed

---

## Recommended Setup

### 1. Create Read-Only User

```sql
-- See scripts/create-readonly-user.sql
CREATE USER simtreenav_readonly IDENTIFIED BY '***';
GRANT SELECT ON schema.COLLECTION_* TO simtreenav_readonly;
-- No INSERT, UPDATE, DELETE, CREATE grants
```

### 2. Use Safe Defaults

```powershell
# Always specify explicit root to limit scope
.\Extract-Tree.ps1 -Schema DESIGN12 -RootId 12345

# Enable probe logging
$env:SIMTREENAV_PROBE_LOG = "info"
```

### 3. Monitor Probe Metrics

Review `meta.json` files after each extraction to verify:
- Query counts are as expected
- Durations are acceptable
- No unexpected patterns

---

## Questions?

For security questions or concerns, review:
- `scripts/create-readonly-user.sql` - Database user setup
- `src/powershell/v02/core/*.ps1` - Core extraction logic
- `tests/*.Tests.ps1` - Test coverage including edge cases

All code is open for inspection. No obfuscation or hidden functionality.
