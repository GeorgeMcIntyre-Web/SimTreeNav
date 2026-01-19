# Quick Smoke Test - 5 Minutes

## Purpose
Fast verification that all core functionality is working before full pre-flight check.

---

## Test 1: Tree Generation (2 minutes)

### Run Command
```powershell
.\src\powershell\main\tree-viewer-launcher.ps1
```

### Watch For
**Console output should show:**
```
Using cached icons (age: X days) - FAST!
Using cached tree data (age: X hours) - FAST!
Using cached user activity (age: X minutes) - FAST!

=== Performance Summary ===
Total generation time: 11.7s
```

### ✅ Expected Results
- Completes in **8-15 seconds** (if caches exist)
- OR ~62 seconds if first run (creates caches)
- Browser opens automatically
- No red error messages

### ❌ Failed If
- Takes >30s with caches present
- Error messages displayed
- Crashes or hangs
- Browser doesn't open

---

## Test 2: Browser Display (1 minute)

### What to Check
Once browser opens:

1. **Tree Visible**
   - [ ] Tree displays immediately (2-5s)
   - [ ] Root node shows: "FORD_DEARBORN" (or your project name)
   - [ ] Icons show (not broken images)

2. **Quick Interaction**
   - [ ] Click expand arrow → children appear
   - [ ] Click collapse → children hide
   - [ ] No lag or freezing

3. **Console Check**
   - [ ] Press F12 → Console tab
   - [ ] No red error messages

### ✅ Expected Results
- Fast load (2-5s)
- Tree interactive
- Icons display
- No errors

### ❌ Failed If
- Blank page
- "Loading..." forever
- Red JavaScript errors
- Broken icon images

---

## Test 3: Search Function (1 minute)

### Quick Search Test
1. In search box, type: **"Robot"** (or any common word)
2. Press Enter

### ✅ Expected Results
- Results highlighted in yellow
- Multiple matches visible
- Search completes in <3 seconds
- Parent nodes expand to show results

### Clear Test
1. Clear search box (delete text)
2. Verify highlights removed

### ✅ Expected Results
- All yellow highlights disappear
- Tree returns to normal

### ❌ Failed If
- Nothing highlights
- JavaScript error in console
- Browser freezes
- Highlights don't clear

---

## Test 4: Cache Status (1 minute)

### Run Command
```powershell
.\cache-status.ps1
```

### ✅ Expected Output
```
=== Performance Cache Status ===

Cache                                Size (KB)  Age (Hours)  Status
-----                                ---------  -----------  ------
icon-cache-DESIGN12.json                 300.5          0.1  Fresh ✅
tree-cache-DESIGN12-18140190.txt       51234.2          0.2  Fresh ✅
user-activity-cache-DESIGN12-...          12.3          0.0  Fresh ✅

Cache Summary:
  Fresh: 3
  Expired: 0
```

### ❌ Failed If
- Script errors
- No caches found (first run is OK)
- Can't read cache files

---

## Quick Results Summary

### ✅ ALL PASS - Ready for Full Check
All 4 tests passed:
- [x] Tree generation fast (8-15s)
- [x] Browser displays correctly
- [x] Search works
- [x] Caches present and working

**Next Step:** Proceed with full pre-flight check (45 minutes)

---

### ⚠️ MINOR ISSUES - Investigate
Some tests passed, some concerns:
- [ ] Generation a bit slow (15-30s)
- [ ] Search works but laggy
- [ ] One cache missing

**Next Step:** Run full pre-flight check to diagnose

---

### ❌ CRITICAL FAILURE - Must Fix
One or more tests failed badly:
- [ ] Tree generation fails
- [ ] Browser errors
- [ ] Search broken
- [ ] No caches working

**Next Step:** Document error and troubleshoot before proceeding

---

## Error Documentation (if needed)

**Test Failed:** _______________

**Error Message:**
```
[Paste error here]
```

**Console Output:**
```
[Paste relevant console output]
```

**Screenshots:** (if applicable)
- Browser error: _______________
- Console error: _______________

---

## Troubleshooting Quick Fixes

### If Generation Slow
```powershell
# Check cache ages
.\cache-status.ps1

# If old, clear and regenerate
Remove-Item *-cache-*
.\src\powershell\main\tree-viewer-launcher.ps1
```

### If Browser Shows Errors
```powershell
# Check file was created
ls navigation-tree-*.html

# Check file size (should be ~90MB)
(Get-Item navigation-tree-*.html).Length / 1MB
```

### If Search Broken
- Open browser DevTools (F12)
- Look for JavaScript errors
- Check if searchTree function exists:
  ```javascript
  typeof searchTree  // Should show: "function"
  ```

### If No Caches
```powershell
# First run is normal - caches will be created
# Check after first successful run:
Get-ChildItem -Filter "*-cache-*"
```

---

## Time to Complete

- **All Pass:** 5 minutes total
- **With Issues:** 10-15 minutes (includes troubleshooting)

---

## Next Actions

### If Smoke Test PASSES ✅
Continue with full pre-flight check:
```powershell
# Open full checklist
code PRE-FLIGHT-CHECK.md

# Or start immediately with Phase 1
# [Follow PRE-FLIGHT-CHECK.md step by step]
```

### If Smoke Test FAILS ❌
1. Document all errors (use template above)
2. Check troubleshooting section
3. Fix issues before proceeding
4. Re-run smoke test
5. Only proceed to full check when smoke test passes

---

**Status:** 📋 Ready to execute
**Estimated Time:** 5 minutes
**Prerequisites:** None (this is the first check)

**Let's verify everything works!** 🚀
