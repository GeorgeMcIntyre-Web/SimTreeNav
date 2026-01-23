# Missing Nodes Analysis and Resolution

## Quick Diagnostic Commands

### Check FORD_DEARBORN (DESIGN12)
```powershell
.\RUN-MISSING-NODES-CHECK.ps1 -Environment FORD
```

### Check BMW (DESIGN1)
```powershell
.\RUN-MISSING-NODES-CHECK.ps1 -Environment BMW
```

---

## How It Works

The diagnostic tool performs these steps:

1. **Counts total nodes in database** using recursive query from project root
2. **Counts nodes by table type** (COLLECTION_, PART_, OPERATION_, etc.)
3. **Parses your generated tree** to count included nodes
4. **Extracts all node IDs from database** for comparison
5. **Identifies missing nodes** by comparing database vs generated tree
6. **Analyzes missing nodes** by table type and class

---

## Understanding the Output

### Coverage Metrics
```
Database nodes (REL_COMMON): 45,823
Generated tree nodes:        44,102
Missing nodes:               1,721
Coverage:                    96.24%
```

- **100%**: Perfect coverage (rare, but ideal)
- **98-99%**: Excellent (minor edge cases)
- **95-97%**: Good (review missing categories)
- **90-94%**: Fair (some node types incomplete)
- **<90%**: Poor (major queries missing)

### Missing Nodes by Table
```
PART_:                 1,245 (3.2% of table)
COLLECTION_:           156 (0.8% of table)
OPERATION_:            234 (1.5% of table)
STUDYCONFIGURATION_:   86 (12.3% of table)
```

High percentages indicate entire query sections may be missing.

### Missing Nodes by Class
```
PartInstance:          856
PartPrototype:         312
RobcadStudy:           89
Collection:            67
```

---

## Common Missing Node Patterns

### Pattern 1: Entire Table Type Missing
**Symptom**: 100% of a table type is missing (e.g., all TOOLINSTANCEASPECT_)

**Cause**: No UNION ALL query exists for this table type

**Fix**: Add new UNION ALL section in [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)

**Example**:
```sql
UNION ALL
-- Add TOOLINSTANCEASPECT_ nodes
SELECT
    r.FORWARD_OBJECT_ID || '|' || r.OBJECT_ID || '|' ||
    COALESCE(ti.NAME_S_, 'Unnamed') || '|' ||
    COALESCE(ti.NAME_S_, 'Unnamed') || '|' ||
    NVL(ti.EXTERNALID_S_, '') || '|' ||
    TO_CHAR(r.SEQ_NUMBER) || '|' ||
    NVL(cd.NAME, 'class PmNode') || '|' ||
    NVL(cd.NICE_NAME, 'Unknown') || '|' ||
    TO_CHAR(cd.TYPE_ID)
FROM DESIGN12.TOOLINSTANCEASPECT_ ti
INNER JOIN DESIGN12.REL_COMMON r ON ti.OBJECT_ID = r.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON ti.CLASS_ID = cd.TYPE_ID
WHERE ti.OBJECT_ID IS NOT NULL
  AND EXISTS (
    SELECT 1 FROM DESIGN12.COLLECTION_ c
    WHERE c.OBJECT_ID = r.FORWARD_OBJECT_ID
  )
```

---

### Pattern 2: Partial Table Coverage
**Symptom**: Some nodes of a table type are missing (e.g., 15% of PART_ missing)

**Cause**: WHERE clause filters are too restrictive

**Common culprits**:
1. **Parent validation too strict**:
   ```sql
   -- This may exclude valid nodes if parent is also PART_
   WHERE EXISTS (
       SELECT 1 FROM DESIGN12.COLLECTION_ c2
       WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
   )
   ```

2. **Reverse relationship filter**:
   ```sql
   -- This may exclude legitimate relationships
   AND r.FORWARD_OBJECT_ID < r.OBJECT_ID
   ```

3. **Explicit exclusions**:
   ```sql
   -- May exclude too many TYPE_IDs
   AND NVL(cd_parent.TYPE_ID, 0) NOT IN (55, 56, 57, 58, 59, 60)
   ```

**Fix**: Review WHERE clauses and relax filters incrementally

---

### Pattern 3: Ghost Node Children Missing
**Symptom**: Nodes under "ghost nodes" (like PartInstanceLibrary) are missing

**Cause**: Hardcoded OBJECT_IDs are environment-specific

**Example Problem**:
```sql
-- Line 559 in generate-tree-html.ps1
WHERE r.FORWARD_OBJECT_ID IN (
    18143953  -- PartInstanceLibrary (DESIGN12 specific!)
)
```

**Fix**: Make ghost node IDs dynamic or configurable

```sql
-- Better approach: Query the ID dynamically
WHERE r.FORWARD_OBJECT_ID IN (
    SELECT r2.OBJECT_ID
    FROM DESIGN12.REL_COMMON r2
    INNER JOIN DESIGN12.PART_ p ON r2.OBJECT_ID = p.OBJECT_ID
    LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
    WHERE r2.FORWARD_OBJECT_ID = $ProjectId
      AND cd.NICE_NAME = 'PartLibrary'
      AND p.NAME_S_ LIKE '%Instance%'
)
```

---

### Pattern 4: Study Nodes Missing
**Symptom**: RobcadStudy, LineSimulationStudy, etc. nodes missing

**Cause**: Study queries require parent to exist in COLLECTION_

**Check**: Are StudyFolder COLLECTION_ nodes included?

**Fix**: Ensure StudyFolder query comes BEFORE study-specific queries

---

### Pattern 5: Deep Nested Nodes Missing
**Symptom**: Nodes at depth >5 are missing

**Cause**: Recursive query may have depth limit or cycle prevention

**Check**: Look for `CONNECT BY NOCYCLE` depth limits

**Fix**: Current SQL uses iterative approach with temp table, should handle deep nesting

---

## Systematic Debugging Process

### Step 1: Run the Diagnostic
```powershell
.\RUN-MISSING-NODES-CHECK.ps1 -Environment FORD
```

### Step 2: Review Summary Stats
Look at coverage percentage and missing node counts by table.

### Step 3: Open the CSV Report
```powershell
# View in Excel or import to PowerShell
$missing = Import-Csv "missing-nodes-report-DESIGN12-18140190.csv" -Delimiter '|'

# Group by table
$missing | Group-Object Table | Sort-Object Count -Descending

# Group by class
$missing | Group-Object NiceName | Sort-Object Count -Descending

# Find missing nodes with no children (leaf nodes - low priority)
$missing | Where-Object { $_.ChildCount -eq 0 } | Measure-Object

# Find missing nodes with children (important - their children may also be missing)
$missing | Where-Object { [int]$_.ChildCount -gt 0 } | Sort-Object { [int]$_.ChildCount } -Descending
```

### Step 4: Check Parent Status
For missing nodes with children, verify if their parents are also missing:

```powershell
# Get parent IDs of missing nodes
$parentIds = ($missing | Select-Object -ExpandProperty ParentId | Where-Object { $_ -ne '' }) -join ','

# Query database to see if parents are in generated tree
# (Manual SQL check required)
```

### Step 5: Identify the Query Section
Based on the table type, find which UNION ALL section should include it:

| Table | Query Section (approx line #) |
|-------|-------------------------------|
| COLLECTION_ | Line 430 (root), 439 (level 1), 520 (level 2+) |
| PART_ | Line 524 (non-collection parts), 552 (ghost node children), 577 (all other parts) |
| OPERATION_ | Line 905 (operations) |
| ROBCADSTUDY_ | Line 626 (RobcadStudy nodes) |
| LINESIMULATIONSTUDY_ | Line 654 (LineSimulationStudy nodes) |
| GANTTSTUDY_ | Line 682 (GanttStudy nodes) |
| SIMPLEDETAILEDSTUDY_ | Line 710 (SimpleDetailedStudy nodes) |
| LOCATIONALSTUDY_ | Line 738 (LocationalStudy nodes) |
| RESOURCE_ | Line 830 (Resource nodes) |
| TOOLPROTOTYPE_ | Line 768 (ToolPrototype nodes) |
| TOOLINSTANCEASPECT_ | Line 797 (ToolInstanceAspect nodes) |
| MFGFEATURE_ | Line 920 (MfgFeature nodes) |
| STUDYCONFIGURATION_ | Line 944 (StudyConfiguration nodes) |
| PARTPROTOTYPE_ | Line 1032 (PartPrototype nodes) |

### Step 6: Test the Query in Isolation
Extract the specific UNION ALL block and run it directly in SQL*Plus:

```sql
-- Example: Test PART_ query
SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK ON
SET HEADING ON

SELECT COUNT(*) as node_count
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN DESIGN12.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
WHERE NOT EXISTS (SELECT 1 FROM DESIGN12.COLLECTION_ c WHERE c.OBJECT_ID = p.OBJECT_ID)
  AND EXISTS (
    SELECT 1 FROM DESIGN12.COLLECTION_ c2
    WHERE c2.OBJECT_ID = r.FORWARD_OBJECT_ID
  );
```

Compare count with expected count from diagnostic.

### Step 7: Relax Filters Incrementally
Remove WHERE clauses one at a time to see which filter is excluding nodes:

```sql
-- Original query returns 10,000 rows
-- Remove parent validation
-- Now returns 12,000 rows (+2,000)
-- Those 2,000 are being excluded by parent validation

-- Try different parent validation:
WHERE r.FORWARD_OBJECT_ID IN (
    SELECT OBJECT_ID FROM temp_project_objects  -- If using temp table approach
)
```

### Step 8: Update generate-tree-html.ps1
Once you identify the fix, update the query in [generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1).

### Step 9: Re-test
```powershell
# Clear cache to force regeneration
Remove-Item tree-cache-*.txt
Remove-Item tree-data-*-clean.txt

# Regenerate
.\RUN-MISSING-NODES-CHECK.ps1 -Environment FORD
```

### Step 10: Verify Coverage Improved
Check that coverage % increased and specific missing node categories decreased.

---

## Known Issues and Fixes

### Issue #1: PartInstanceLibrary Ghost Node (DESIGN12-specific)

**Lines**: 444, 450, 459, 465, 470, 559, 1016

**Problem**: OBJECT_ID `18143953` is hardcoded for DESIGN12

**Impact**: BMW and other schemas fail to include PartInstanceLibrary children

**Fix**: Query dynamically
```sql
-- Add at top of query, before main SELECT
WITH ghost_nodes AS (
    SELECT r.OBJECT_ID, p.NAME_S_ as NAME
    FROM $Schema.REL_COMMON r
    INNER JOIN $Schema.PART_ p ON r.OBJECT_ID = p.OBJECT_ID
    LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
    WHERE r.FORWARD_OBJECT_ID = $ProjectId
      AND cd.NICE_NAME = 'PartLibrary'
      AND p.NAME_S_ LIKE '%Instance%'
)
-- Then use: WHERE r.FORWARD_OBJECT_ID IN (SELECT OBJECT_ID FROM ghost_nodes)
```

---

### Issue #2: Reverse Relationship Filter Too Aggressive

**Lines**: 562-563

```sql
AND NVL(cd_parent.TYPE_ID, 0) NOT IN (55, 56, 57, 58, 59, 60)
AND r.FORWARD_OBJECT_ID < r.OBJECT_ID
```

**Problem**: Excludes valid bi-directional relationships

**Impact**: Some part instances missing

**Fix**: Review if this is needed for ALL parts, or only specific classes

---

### Issue #3: TxProcessAssembly Hardcoded TYPE_ID

**Line**: 982

```sql
WHERE p.CLASS_ID = 133  -- TxProcessAssembly TYPE_ID
```

**Problem**: TYPE_ID may differ across schemas

**Fix**: Use NICE_NAME instead
```sql
WHERE cd.NICE_NAME = 'TxProcessAssembly'
```

---

## Validation After Fixes

After making changes, validate with:

1. **Run missing nodes check**: Coverage should increase
2. **Spot check UAT plan**: Verify critical paths still work
3. **Check for duplicates**: Ensure fixes didn't create duplicate nodes
   ```powershell
   # Check for duplicate OBJECT_IDs in generated tree
   $nodes = Get-Content "tree-data-DESIGN12-18140190-clean.txt" -Encoding UTF8
   $objectIds = $nodes | ForEach-Object { ($_ -split '\|')[2] }
   $duplicates = $objectIds | Group-Object | Where-Object { $_.Count -gt 1 }
   if ($duplicates) {
       Write-Warning "Found duplicate nodes: $($duplicates.Name -join ', ')"
   } else {
       Write-Host "No duplicates found" -ForegroundColor Green
   }
   ```
4. **Check HTML renders correctly**: Open navigation-tree.html in browser
5. **Test search**: Verify search finds newly added nodes

---

## Reporting Results

When reporting missing nodes findings:

1. Note the **environment** (DESIGN12/FORD or DESIGN1/BMW)
2. Include **coverage percentage** before and after fixes
3. Attach the **CSV report** (`missing-nodes-report-*.csv`)
4. List **tables/classes** with highest missing counts
5. Document **SQL changes** made to fix issues
6. Include **validation results** after fixes

---

## Next Steps

After running the diagnostic:

1. **Prioritize fixes** based on missing node categories
2. **Focus on COLLECTION_ and PART_ first** (most critical)
3. **Test fixes in isolation** before updating main script
4. **Validate with UAT** to ensure fixes don't break existing nodes
5. **Update documentation** with lessons learned

---

Date: 2026-01-20
Status: Diagnostic tools ready for use
