# Bug Fix: Encoding Variable Null Reference

## Issue
When using cached tree data, the script crashed with:
```
Exception calling "WriteAllText" with "3" argument(s): "Value cannot be null.
Parameter name: encoding"
```

## Root Cause
The UTF-8 encoding objects (`$utf8NoBom` and `$utf8WithBom`) were defined inside conditional cache blocks:
- Line 163: Inside icon cache block `if (-not $usingCache)`
- Line 1078: Inside tree cache block `if (-not $usingTreeCache)`
- Line 1135: Inside tree cache block `if (-not $usingTreeCache)`

When caches were used, these blocks were skipped, leaving the encoding variables undefined. Later code at line 1256 attempted to use `$utf8NoBom`, causing a null reference error.

## Fix
Moved encoding object definitions to the top of the script (lines 44-45), outside all conditional blocks:

```powershell
# Define UTF-8 encoding objects (used throughout for file I/O)
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$utf8WithBom = New-Object System.Text.UTF8Encoding $true
```

Removed duplicate definitions at:
- Line 163 (icon cache block)
- Line 1078 (tree cache block)
- Line 1135 (tree cache block)

## Impact
- Script now works correctly whether using cached or fresh data
- Follows same pattern as earlier cache bug fixes (BUGFIX-CACHE-NULL-PATH.md)
- No performance impact

## Testing
Verified with cached tree data - script completed successfully:
- Total time: 26.8s
- Generation time: 25.7s
- Used icon cache (0.1 days old)
- Used tree cache (1.4 hours old)
- Refreshed user activity cache (>1 hour, 18.42s to query)

## Files Modified
- [src/powershell/main/generate-tree-html.ps1](src/powershell/main/generate-tree-html.ps1)
  - Added lines 44-45: Global encoding object definitions
  - Removed line 163: Duplicate `$utf8NoBom` definition
  - Removed line 1078: Duplicate `$utf8NoBom` definition
  - Removed line 1135: Duplicate `$utf8WithBom` definition
