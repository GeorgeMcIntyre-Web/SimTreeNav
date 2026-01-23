# Test Execution Guide

## Overview
This guide explains how to execute the regression tests and coverage checks for the MFGFEATURE_/MODULE_/TxProcessAssembly node extraction fix.

## Prerequisites
- Oracle database connection to Process Simulate environment
- PowerShell 5.1+
- Credential manager configured (or default credentials available)
- TNS configuration pointing to database server

## Test 1: Regression Validation

### Purpose
Validates that the fix correctly extracts MFGFEATURE_, MODULE_, and TxProcessAssembly nodes by comparing the correct pattern (object ID check) against the old buggy pattern (parent ID check).

### Command
```powershell
.\test-node-extraction-regression.ps1 -TNSName DESIGN1 -Schema DESIGN1 -ProjectId 20
```

### Expected Output
```
=== Node Extraction Regression Test ===
TNS: DESIGN1 | Schema: DESIGN1 | Project: 20

Running regression tests...

=== Test Results ===
OPERATION_: Count=1344 [PASS]
OPERATION_EXTRACT: Count=1344 [PASS]
MFGFEATURE_: Count=12 [PASS]
MFGFEATURE_EXTRACT: Count=12 [PASS]
MODULE_: Count=3 [PASS]
MODULE_EXTRACT: Count=3 [PASS]
TXPROCESSASSEMBLY: Count=1344 [PASS]
TXPROCESSASSEMBLY_EXTRACT: Count=1344 [PASS]
MFGFEATURE_REGRESSION: New=12 Old=0 [PASS]
MODULE_REGRESSION: New=3 Old=0 [PASS]

=== ALL TESTS PASSED ===
```

### Test Breakdown

| Test | Description | Pass Criteria |
|------|-------------|---------------|
| OPERATION_ | Baseline check - OPERATION_ objects in temp_project_objects | Count > 0 |
| OPERATION_EXTRACT | Baseline check - OPERATION_ extraction query works | Count > 0 |
| MFGFEATURE_ | MFGFEATURE_ objects in temp_project_objects | Count >= 0 (0 is OK if none exist) |
| MFGFEATURE_EXTRACT | MFGFEATURE_ extraction query returns results | Count >= 0 |
| MODULE_ | MODULE_ objects in temp_project_objects | Count >= 0 |
| MODULE_EXTRACT | MODULE_ extraction query returns results | Count >= 0 |
| TXPROCESSASSEMBLY | TxProcessAssembly objects in temp_project_objects | Count > 0 |
| TXPROCESSASSEMBLY_EXTRACT | TxProcessAssembly extraction query returns results | Count > 0 |
| MFGFEATURE_REGRESSION | Correct pattern >= Old pattern (proves fix works) | New >= Old |
| MODULE_REGRESSION | Correct pattern >= Old pattern (proves fix works) | New >= Old |

### Interpreting Results

**PASS (Exit Code 0)**: All extraction queries work correctly, regression checks confirm fix

**FAIL (Exit Code 1)**: One or more tests failed - indicates:
- Database connection issues
- Schema mismatch
- Potential regression in fix
- Missing node types in project

### Common Issues

1. **Connection Error (ORA-12154)**
   - Check TNS configuration
   - Verify database server is accessible
   - Confirm credential manager is configured

2. **Zero Counts for MFGFEATURE_/MODULE_**
   - Not a failure if the project genuinely has no MFGFEATURE_ or MODULE_ objects
   - Check manually: `SELECT COUNT(*) FROM DESIGN1.MFGFEATURE_;`

3. **Regression Test Fails (New < Old)**
   - Indicates the fix was not applied correctly
   - Re-verify WHERE clauses in generate-tree-html.ps1

## Test 2: Coverage Check

### Purpose
Displays counts of each node type discovered in the project tree, allowing you to verify completeness of extraction.

### Command
```powershell
.\RUN-COVERAGE-CHECK.ps1 -TNSName DESIGN1 -Schema DESIGN1 -ProjectId 20 -ProjectName "J10735_Mexico"
```

### Expected Output
```
=== Node Type Coverage Check ===
Project: J10735_Mexico (ID: 20)
Schema: DESIGN1 | TNS: DESIGN1

Analyzing node type coverage...

=== Coverage Results ===

  PARTPROTOTYPE_      : 167769
  COLLECTION_         : 8234
  OPERATION_          : 1344
  TxProcessAssembly   : 1344
  PART_               : 756
  RESOURCE_           : 234
  TOOLPROTOTYPE_      : 156
  SHORTCUT_           : 45
  ROBCADSTUDY_        : 23
  MFGFEATURE_         : 12
  LINESIMULATIONSTUDY_: 5
  MODULE_             : 3
  GANTTSTUDY_         : 1
  SIMPLEDETAILEDSTUDY_: 0
  LOCATIONALSTUDY_    : 0

  TOTAL_DISCOVERED    : 486188

=== ALL CRITICAL NODE TYPES PRESENT ===

Coverage check complete.
```

### Interpreting Results

**Green numbers**: Node type has significant presence (>= 10 nodes)
**Yellow numbers**: Low count (< 10 nodes) - may be legitimate
**Gray numbers**: Zero count - node type not present in project

**Critical Node Types** (must be present):
- OPERATION_
- MFGFEATURE_ (if manufacturing features exist in project)
- MODULE_ (if modules exist in project)
- TxProcessAssembly

### Before vs After Fix

**Before Fix (Buggy Code):**
```
  OPERATION_          : 1344  ✅
  TxProcessAssembly   : 0     ❌ (was missing due to parent check)
  MFGFEATURE_         : 0     ❌ (was missing due to parent check)
  MODULE_             : 0     ❌ (was missing due to parent check)
```

**After Fix (Correct Code):**
```
  OPERATION_          : 1344  ✅
  TxProcessAssembly   : 1344  ✅ (now extracted correctly)
  MFGFEATURE_         : 12    ✅ (now extracted correctly)
  MODULE_             : 3     ✅ (now extracted correctly)
```

## Test 3: Full Tree Regeneration

### Purpose
End-to-end validation by regenerating the entire tree and verifying node counts.

### Command (Existing Script)
```powershell
.\REGENERATE-QUICK.ps1
```

Or directly:
```powershell
.\src\powershell\main\generate-tree-html.ps1 `
    -TNSName DESIGN1 `
    -Schema DESIGN1 `
    -ProjectId 20 `
    -ProjectName "J10735_Mexico"
```

### Expected Output
```
Generating tree for:
  TNS Name: DESIGN1
  Schema: DESIGN1
  Project: J10735_Mexico (ID: 20)

Extracting icons from database...
  Using cached icons (age: 2.3 days) - FAST!
  Loaded 221 icons from cache

Querying database...
Cleaning data and fixing encoding...

=== Performance Summary ===
Total generation time: 8.45s

Done! Tree saved to: navigation-tree.html
```

### Validation Steps

1. Open `navigation-tree.html` in browser
2. Use search to find MFGFEATURE_ nodes (search for "MfgFeature")
3. Use search to find MODULE_ nodes (search for "Module")
4. Navigate manually to known node locations
5. Compare with Process Simulate UI

## Troubleshooting

### Database Connection Issues

If tests fail with connection errors:

1. **Check TNS configuration**
   ```powershell
   Get-Content tnsnames.ora
   ```

2. **Test connection manually**
   ```powershell
   .\src\powershell\database\test-connection.ps1
   ```

3. **Verify credentials**
   ```powershell
   sqlplus sys/change_on_install@DESIGN1 AS SYSDBA
   ```

### Schema/Project Mismatch

If tests return zero nodes:

1. **Verify project exists**
   ```sql
   SELECT OBJECT_ID, CAPTION_S_ FROM DESIGN1.COLLECTION_ WHERE OBJECT_ID = 20;
   ```

2. **Check if schema has data**
   ```sql
   SELECT COUNT(*) FROM DESIGN1.OPERATION_;
   SELECT COUNT(*) FROM DESIGN1.MFGFEATURE_;
   SELECT COUNT(*) FROM DESIGN1.MODULE_;
   ```

3. **Use correct project ID**
   - Run tree-viewer-launcher.ps1 to auto-discover projects
   - Or query: `SELECT OBJECT_ID, CAPTION_S_ FROM DESIGN1.DFPROJECT;`

## Success Criteria

The fix is validated when:

1. ✅ Regression test exits with code 0 (all tests pass)
2. ✅ Coverage check shows non-zero counts for OPERATION_, TxProcessAssembly
3. ✅ Coverage check shows >= counts for MFGFEATURE_/MODULE_ compared to old code
4. ✅ Full tree regeneration completes without errors
5. ✅ Generated tree displays MFGFEATURE_/MODULE_ nodes that were previously missing
6. ✅ Node counts match Process Simulate UI

## Continuous Testing

Add regression test to your validation workflow:

```powershell
# In your deployment script:
.\test-node-extraction-regression.ps1 -TNSName DESIGN1 -Schema DESIGN1 -ProjectId 20
if ($LASTEXITCODE -ne 0) {
    Write-Error "Regression tests failed!"
    exit 1
}

.\RUN-COVERAGE-CHECK.ps1 -TNSName DESIGN1 -Schema DESIGN1 -ProjectId 20 -ProjectName "TestProject"
```

This ensures the fix remains in place and no future changes break node extraction.
