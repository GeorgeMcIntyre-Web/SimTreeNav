# Bug Fix: Cache Null Path and Variable Errors

## Issues
When using cached icons (second+ run), the script crashed with multiple errors:

### Error 1:
```
Cannot bind argument to parameter 'Path' because it is null.
At line:343 char:13
+ Remove-Item $extractIconsFile -ErrorAction SilentlyContinue
```

### Error 2:
```
You cannot call a method on a null-valued expression.
At line:1109 char:42
+ ... Where-Object { -not $dbIconTypeIds.ContainsKey($_) }
```

## Root Cause
Multiple variables were only defined inside the `if (-not $usingCache)` block:
- `$extractIconsFile` and `$iconsOutputFile` - File paths for cleanup
- `$dbIconTypeIds` - Hashtable for checking missing icons
- `$invalidIconEntries` and `$fallbackAddedTypeIds` - Arrays for tracking

When using cached icons, these variables were never created, causing null reference errors throughout the script.

## Fix
Moved variable declarations outside the cache check block:

**Before:**
```powershell
if (-not $usingCache) {
    # Query to extract all icons...
    $extractIconsFile = "extract-icons-${Schema}.sql"  # ← Only defined here
    $iconsOutputFile = "icons-data-${Schema}.txt"     # ← Only defined here
    # ... extraction code ...
}

# Cleanup (crashes if using cache!)
Remove-Item $extractIconsFile -ErrorAction SilentlyContinue  # ← $extractIconsFile is null!
Remove-Item $iconsOutputFile -ErrorAction SilentlyContinue   # ← $iconsOutputFile is null!
```

**After:**
```powershell
# Define file names (needed for cleanup later)
$extractIconsFile = "extract-icons-${Schema}.sql"
$iconsOutputFile = "icons-data-${Schema}.txt"

# Initialize variables needed later
$invalidIconEntries = @()
$fallbackAddedTypeIds = @()

if (-not $usingCache) {
    # Query to extract all icons...
    # ... extraction code ...
}

# Build icon type ID lookup (needed for missing icon check later)
$dbIconTypeIds = @{}
foreach ($key in $iconDataMap.Keys) {
    $dbIconTypeIds[$key] = $true
}

# Cleanup (now works with or without cache)
Remove-Item $extractIconsFile -ErrorAction SilentlyContinue  # ← Variables always defined
Remove-Item $iconsOutputFile -ErrorAction SilentlyContinue   # ← Safe even if files don't exist

# Later in script - missing icon check now works
$missingIcons = $uniqueTypeInfo.Keys | Where-Object { -not $dbIconTypeIds.ContainsKey($_) }  # ← No longer null!
```

## Testing

### Before Fix
```powershell
# First run - works fine (creates cache)
.\src\powershell\main\tree-viewer-launcher.ps1
# ✓ Success - cache created

# Second run - crashes
.\src\powershell\main\tree-viewer-launcher.ps1
# ✗ ERROR: Cannot bind argument to parameter 'Path' because it is null
```

### After Fix
```powershell
# First run - works fine (creates cache)
.\src\powershell\main\tree-viewer-launcher.ps1
# ✓ Success - cache created

# Second run - now works!
.\src\powershell\main\tree-viewer-launcher.ps1
# ✓ Success - uses cache, completes in 35-40s
```

## Impact
- ✅ Icon caching now works correctly on second+ runs
- ✅ No more null path errors
- ✅ No more null hashtable errors
- ✅ Cache files cleaned up properly in both scenarios
- ✅ Missing icon detection works with cached icons

## Files Modified
- `src/powershell/main/generate-tree-html.ps1`
  - Lines 78-87: Added variable initialization outside cache block
  - Lines 325-329: Moved `$dbIconTypeIds` creation outside cache block
  - Line 170: Removed duplicate `$invalidIconEntries` initialization

## Commit Message
```
fix: Initialize all variables outside cache check block

When using cached icons, multiple variables were undefined:
- $extractIconsFile, $iconsOutputFile: causing null path errors
- $dbIconTypeIds: causing null hashtable errors
- $invalidIconEntries, $fallbackAddedTypeIds: needed for tracking

Moved all variable declarations and initializations outside the
if (-not $usingCache) block so they're available in both scenarios.

Fixes multiple crashes on second+ run when using icon cache.
```

---
Date: 2026-01-19
Status: ✅ Fixed and verified
