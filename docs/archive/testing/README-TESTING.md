# Quick Testing Guide

## Before Making Any Changes

```powershell
# Run validation to capture baseline
.\verify-critical-paths.ps1

# All tests should PASS
```

## After Making Changes

```powershell
# Regenerate the tree
.\src\powershell\main\tree-viewer-launcher.ps1

# Run validation again
.\verify-critical-paths.ps1

# All tests should still PASS
```

## If Tests Fail

1. **Check what changed**:
   ```powershell
   git diff src/powershell/main/generate-tree-html.ps1
   git diff src/powershell/main/generate-full-tree-html.ps1
   ```

2. **Review the failing test output** - it will show exactly which path or check failed

3. **Hard refresh browser** (Ctrl+Shift+F5) to clear cache

4. **Compare with XML export** (optional, for deep validation):
   ```powershell
   .\validate-against-xml.ps1 -ShowMissing
   ```

## What the Tests Check

✓ **Node count** - Should be ~631,318 (±1%)
✓ **Critical path** - PartInstanceLibrary → P702 → 01 → CC → COWL_SILL_SIDE
✓ **Missing children** - All 4 PartInstance nodes under COWL_SILL_SIDE
✓ **Cycle detection** - JavaScript has visited/ancestorIds checks
✓ **Correct deduplication** - No reverseKey check in childMap

## Expected Test Output

```
=== Critical Path Validation ===
File: navigation-tree-DESIGN12-18140190.html

1. Total lines:
   Found: 632638 (expected: ~631,318)
   PASS

2. PartInstanceLibrary → P702 path:
   PASS: 18143953 → 18209343 exists

3. P702 → 01 path:
   PASS: 18209343 → 18209353 exists

4. 01 → CC path:
   PASS: 18209353 → 18209355 exists

5. CC → COWL_SILL_SIDE path:
   PASS: 18209355 → 18208736 exists

6. COWL_SILL_SIDE children:
   [OK] 18208716 - FNA11786290_2_PNL_ASY_CWL_SD_IN_LH
   [OK] 18208739 - FNA11786300_2_PNL_ASY_CWL_SD_IN_RH
   [OK] 18208727 - JL34-1610110-A-18-MBR ASY FLR SD INR FRT
   [OK] 18208707 - NL34-1610111-A-6-MBR ASY FLR SD INR FRT LH
   Found: 4/4 children

7. Checking for cycle detection code:
   PASS: Cycle detection code present

8. Checking childMap deduplication logic:
   PASS: Correct childMap logic (no reverseKey check)

=== Summary ===
All critical tests PASSED
```

## Common Breaking Changes to AVOID

❌ **DON'T** add SQL filters like `WHERE TYPE_ID NOT IN (...)`
❌ **DON'T** use `r.FORWARD_OBJECT_ID < r.OBJECT_ID` for bidirectional filtering
❌ **DON'T** add `reverseKey` checks in JavaScript childMap logic
❌ **DON'T** use recursion without cycle detection (visited Set)

✅ **DO** output all relationships from SQL, let JavaScript handle filtering
✅ **DO** allow same child under multiple parents (only prevent exact duplicates)
✅ **DO** add visited/ancestorIds Sets to all recursive functions
✅ **DO** run tests before committing

## Full Documentation

See [TESTING.md](TESTING.md) for complete testing guide including:
- Baseline metrics
- XML validation strategy
- Integration testing workflow
- Automated Pester test suite examples

## Quick Commands

```powershell
# Run critical path validation
.\verify-critical-paths.ps1

# Compare with XML export (shows missing nodes)
.\validate-against-xml.ps1 -ShowMissing

# Regenerate tree after changes
.\src\powershell\main\tree-viewer-launcher.ps1
```
