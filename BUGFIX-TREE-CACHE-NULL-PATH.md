# Bug Fix: Tree Cache Null Path Errors

## Issue
When using tree data cache or user activity cache (second+ run), the script crashed with:

```
Cannot bind argument to parameter 'Path' because it is null.
At generate-tree-html.ps1:1358 char:13
+ Remove-Item $sqlFile -ErrorAction SilentlyContinue
```

## Root Cause
Multiple variables were only defined inside the `if (-not $usingTreeCache)` and `if (-not $usingUserActivityCache)` blocks:

### Tree Data Cache Block:
- `$sqlFile` - SQL query file path (line 403)
- `$dataFile` - Tree data file path (line 1080)

### User Activity Cache Block:
- `$userActivityFile` - User activity SQL file path (line 1318)

When using cached data, these variables were never created, causing null reference errors during cleanup (lines 1358-1359).

## Fix
Moved variable declarations outside their respective cache check blocks.

### Tree Data Variables

**Before:**
```powershell
# Only query database if not using cache
if (-not $usingTreeCache) {
    $sqlFile = "get-tree-${Schema}-${ProjectId}.sql"  # ← Only defined here
    # ... later ...
    $dataFile = "tree-data-${Schema}-${ProjectId}.txt"  # ← Only defined here
}

# Cleanup (crashes if using cache!)
Remove-Item $sqlFile -ErrorAction SilentlyContinue  # ← $sqlFile is null!
Remove-Item $dataFile -ErrorAction SilentlyContinue  # ← $dataFile is null!
```

**After:**
```powershell
# Define file names (needed for cleanup later)
$sqlFile = "get-tree-${Schema}-${ProjectId}.sql"
$dataFile = "tree-data-${Schema}-${ProjectId}.txt"

# Only query database if not using cache
if (-not $usingTreeCache) {
    # ... query code ...
}

# Cleanup (now works with or without cache)
Remove-Item $sqlFile -ErrorAction SilentlyContinue  # ← Variables always defined
Remove-Item $dataFile -ErrorAction SilentlyContinue  # ← Safe even if files don't exist
```

### User Activity Variables

**Before:**
```powershell
# Only query database if not using cache
if (-not $usingUserActivityCache) {
    $userActivityFile = Join-Path $env:TEMP "get-user-activity-${Schema}-${ProjectId}.sql"  # ← Only defined here
}

# Cleanup (crashes if using cache!)
Remove-Item $userActivityFile -ErrorAction SilentlyContinue  # ← $userActivityFile is null!
```

**After:**
```powershell
# Define file name (needed for cleanup later)
$userActivityFile = Join-Path $env:TEMP "get-user-activity-${Schema}-${ProjectId}.sql"

# Only query database if not using cache
if (-not $usingUserActivityCache) {
    # ... query code ...
}

# Cleanup (now works with or without cache)
Remove-Item $userActivityFile -ErrorAction SilentlyContinue  # ← Variable always defined
```

## Testing

### Before Fix
```powershell
# First run - works fine (creates caches)
.\src\powershell\main\tree-viewer-launcher.ps1
# ✓ Success - all caches created

# Second run - crashes
.\src\powershell\main\tree-viewer-launcher.ps1
# ✗ ERROR: Cannot bind argument to parameter 'Path' because it is null
```

### After Fix
```powershell
# First run - works fine (creates caches)
.\src\powershell\main\tree-viewer-launcher.ps1
# ✓ Success - all caches created

# Second run - now works!
.\src\powershell\main\tree-viewer-launcher.ps1
# ✓ Success - uses all caches, completes in 8-10s
```

## Impact
- ✅ Tree data caching now works correctly on second+ runs
- ✅ User activity caching now works correctly on second+ runs
- ✅ No more null path errors during cleanup
- ✅ Cleanup files properly in both cached and non-cached scenarios
- ✅ Performance: 61.89s → 8-10s (87% improvement) now actually works!

## Files Modified
- `src/powershell/main/generate-tree-html.ps1`
  - Lines 400-402: Added `$sqlFile` and `$dataFile` initialization outside cache block
  - Removed line 1080: Duplicate `$dataFile` definition inside cache block
  - Lines 1277-1278: Added `$userActivityFile` initialization outside cache block
  - Removed line 1318: Duplicate `$userActivityFile` definition inside cache block

## Lesson Learned
When implementing caching with conditional blocks, always define file path variables OUTSIDE the conditional block if they're used for cleanup or other operations later in the script. This is the same pattern we learned from the icon caching bug fix (BUGFIX-CACHE-NULL-PATH.md).

## Related Issues
This is the same type of bug we fixed earlier for icon caching:
- See: BUGFIX-CACHE-NULL-PATH.md
- Pattern: Variables defined inside `if (-not $usingCache)` blocks cause null errors when cache is used

## Pattern to Follow
When adding new cache blocks in the future:

```powershell
# 1. Define ALL file path variables OUTSIDE the cache block
$sqlFile = "query-${Schema}.sql"
$outputFile = "data-${Schema}.txt"

# 2. Check cache and use if valid
if ($cacheAge.TotalHours -lt 24) {
    # Load from cache
} else {
    $usingCache = $false
}

# 3. Only query if not using cache
if (-not $usingCache) {
    # Create $sqlFile, $outputFile, etc.
    # Run queries
}

# 4. Cleanup (works in both scenarios)
Remove-Item $sqlFile -ErrorAction SilentlyContinue
Remove-Item $outputFile -ErrorAction SilentlyContinue
```

## Commit Message
```
fix: Initialize tree cache variables outside cache check block

When using tree data cache or user activity cache, multiple variables
were undefined:
- $sqlFile, $dataFile: causing null path errors during cleanup
- $userActivityFile: causing null path errors during cleanup

Moved all variable declarations outside the if (-not $usingTreeCache)
and if (-not $usingUserActivityCache) blocks so they're available in
both scenarios.

Fixes crashes on second+ run when using tree/user activity caches.
Same pattern as icon cache fix in BUGFIX-CACHE-NULL-PATH.md.
```

---
Date: 2026-01-19
Status: ✅ Fixed
Related: BUGFIX-CACHE-NULL-PATH.md (icon cache fix)
