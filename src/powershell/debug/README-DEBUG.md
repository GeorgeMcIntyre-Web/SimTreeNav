# Missing Nodes Debugging Guide

## Overview
This directory contains tools to identify and diagnose missing nodes in the generated navigation tree.

## Quick Start

### 1. Run the Missing Nodes Diagnostic

```powershell
cd c:\Users\georgem\source\repos\cursor\SimTreeNav

# For DESIGN12 / FORD_DEARBORN
.\src\powershell\debug\find-missing-nodes.ps1 `
    -TNSName "DES_SIM_DB2" `
    -Schema "DESIGN12" `
    -ProjectId 18140190 `
    -ProjectName "FORD_DEARBORN"

# For DESIGN1 / BMW
.\src\powershell\debug\find-missing-nodes.ps1 `
    -TNSName "DES_SIM_DB2_BMW01" `
    -Schema "DESIGN1" `
    -ProjectId 24 `
    -ProjectName "DPA_SPEC"
```

### 2. Review the Output

The script will show:
- **Total node count** in database vs generated tree
- **Coverage percentage**
- **Missing nodes by table type** (COLLECTION_, PART_, OPERATION_, etc.)
- **Missing nodes by class** (PartLibrary, RobcadStudy, etc.)
- **Sample missing nodes** with parent/child info
- **Detailed CSV report** saved to disk

## Understanding the Results

### Coverage Metrics

- **100% Coverage**: Perfect - all database nodes are in the tree
- **95-99% Coverage**: Good - minor gaps, likely edge cases
- **90-94% Coverage**: Fair - review missing node categories
- **<90% Coverage**: Poor - major queries may be missing entire node types

### Missing Node Categories

#### High Priority (Should be included)
- **COLLECTION_**: Core library/folder nodes
- **PART_**: Part instances and prototypes
- **OPERATION_**: Manufacturing operations
- **ROBCADSTUDY_**: Study nodes
- **RESOURCE_**: Robots, fixtures, devices

#### Medium Priority
- **STUDYCONFIGURATION_**: Study configs (may be internal)
- **MFGFEATURE_**: Weld points, features
- **TOOLPROTOTYPE_**: Tool definitions

#### Low Priority (May be intentionally excluded)
- **UNKNOWN_TABLE**: Nodes not in expected tables
- Internal/system nodes

## Common Causes of Missing Nodes

### 1. Missing Table Queries
**Symptom**: Entire table has 0% coverage
**Fix**: Add UNION ALL query for that table type in [generate-tree-html.ps1](../main/generate-tree-html.ps1)

### 2. Incorrect WHERE Filters
**Symptom**: Some nodes of a type are missing
**Fix**: Review WHERE clauses in SQL queries - may be too restrictive

### 3. Parent Relationship Issues
**Symptom**: Nodes with specific parent types missing
**Fix**: Check EXISTS clauses that verify parent is in COLLECTION_

### 4. Reverse Relationship Exclusions
**Symptom**: Part instances missing
**Fix**: Review filters like `r.FORWARD_OBJECT_ID < r.OBJECT_ID` (line 563)

### 5. Ghost Node Handling
**Symptom**: Children of "ghost nodes" (like PartInstanceLibrary) missing
**Fix**: Check hardcoded OBJECT_IDs - they're environment-specific

### 6. Class Type Filters
**Symptom**: Specific class types missing
**Fix**: Review TYPE_ID filters like `p.CLASS_ID = 133` (line 982)

## Detailed Analysis Steps

### Step 1: Identify the Pattern

Look at the CSV report to find patterns:

```powershell
# Open the CSV report
Import-Csv "missing-nodes-report-DESIGN12-18140190.csv" -Delimiter '|' |
    Group-Object Table |
    Sort-Object Count -Descending
```

### Step 2: Check Parent Relationships

For missing nodes, verify their parents are in the tree:

```sql
-- Run this in SQL*Plus
SELECT rc.FORWARD_OBJECT_ID, COUNT(*)
FROM DESIGN12.REL_COMMON rc
WHERE rc.OBJECT_ID IN (/* paste missing object IDs */)
GROUP BY rc.FORWARD_OBJECT_ID;
```

If parents are also missing, fix the parent query first.

### Step 3: Test Specific Queries

Extract and test individual UNION ALL blocks from [generate-tree-html.ps1](../main/generate-tree-html.ps1):

```sql
-- Example: Test PART_ query
SELECT
    r.FORWARD_OBJECT_ID || '|' || r.OBJECT_ID || '|' ||
    COALESCE(p.NAME_S_, 'Unnamed') || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown')
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE NOT EXISTS (SELECT 1 FROM DESIGN12.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND EXISTS (
    SELECT 1 FROM DESIGN12.COLLECTION_ c2
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
  );
```

### Step 4: Add Verbose Logging

Add diagnostic output to [generate-tree-html.ps1](../main/generate-tree-html.ps1):

```sql
-- Before each UNION ALL, add:
SELECT 'DEBUG: Starting PART_ query' FROM DUAL
UNION ALL
-- ... existing query ...
UNION ALL
SELECT 'DEBUG: PART_ query returned X rows' FROM DUAL
```

## Known Issues and Solutions

### Issue 1: PartInstanceLibrary Ghost Node
**OBJECT_ID**: `18143953` (hardcoded for DESIGN12)
**Problem**: This ID is environment-specific
**Solution**: Query it dynamically or make it configurable

```sql
-- Find the PartInstanceLibrary OBJECT_ID
SELECT r.OBJECT_ID
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = 18140190  -- Project root
  AND cd.NICE_NAME = 'PartLibrary'
  AND p.NAME_S_ LIKE '%Instance%';
```

### Issue 2: Reverse Relationship Filter Too Aggressive
**Line**: 563, 562
```powershell
AND NVL(cd_parent.TYPE_ID, 0) NOT IN (55, 56, 57, 58, 59, 60)
AND r.FORWARD_OBJECT_ID < r.OBJECT_ID
```
**Problem**: May exclude valid nodes
**Solution**: Review if this filter is necessary for all node types

### Issue 3: Study Nodes Missing
**Cause**: Study queries require parent to be in COLLECTION_
**Solution**: Ensure StudyFolder COLLECTION_ nodes are fetched first

## Adding More Diagnostic Queries

To add new diagnostic checks, create a new script in this directory:

```powershell
# Template: check-specific-issue.ps1
param(
    [string]$TNSName,
    [string]$Schema,
    [int]$ProjectId
)

$sql = @"
-- Your diagnostic query here
SELECT ...
FROM $Schema.YOUR_TABLE
WHERE ...
"@

# Execute and analyze results
```

## Files Generated

| File | Description |
|------|-------------|
| `missing-nodes-report-{Schema}-{ProjectId}.csv` | Full list of missing nodes with details |
| `count-all-nodes-{Schema}-{ProjectId}.sql` | Temporary SQL (auto-deleted) |
| `count-by-type-{Schema}-{ProjectId}.sql` | Temporary SQL (auto-deleted) |
| `get-all-ids-{Schema}-{ProjectId}.sql` | Temporary SQL (auto-deleted) |
| `get-missing-details-{Schema}-{ProjectId}.sql` | Temporary SQL (auto-deleted) |

## Next Steps After Finding Missing Nodes

1. **Categorize**: Group by table/class type
2. **Prioritize**: Focus on COLLECTION_ and PART_ first
3. **Root Cause**: Identify which SQL query should include them
4. **Fix**: Update [generate-tree-html.ps1](../main/generate-tree-html.ps1)
5. **Test**: Re-run generation and verify coverage improved
6. **Validate**: Use UAT plan to verify nodes are correct

## Performance Notes

- The diagnostic script runs 6 separate SQL queries
- For large databases (>100K nodes), it may take 2-3 minutes
- The script limits missing node details to first 500 for performance
- Use the CSV report for full analysis of all missing nodes

## Support

If you find missing nodes that you believe should be included:

1. Save the `missing-nodes-report-*.csv` file
2. Note the coverage percentage
3. Identify the table/class of missing nodes
4. Check if the parent nodes are also missing
5. Review the relevant SQL query in [generate-tree-html.ps1](../main/generate-tree-html.ps1)
