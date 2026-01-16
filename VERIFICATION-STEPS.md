# Verification Steps - Dynamic Icon Solution

## Current Status ⚠️

The dynamic icon solution has been **implemented in code** but the SQL query file was deleted. Here's how to complete the fix:

---

## Step 1: Restore SQL File ✅ REQUIRED

The file `get-tree-DESIGN12-18140190.sql` was deleted (shows as "D" in git status).

### Restore from Git:
```bash
cd /c/Users/georgem/source/repos/cursor/SimTreeNav
git checkout get-tree-DESIGN12-18140190.sql
```

This will restore the file from the last commit.

---

## Step 2: Check Current HTML Output

### Current State (TYPE_ID still 164):
```bash
grep "EngineeringResourceLibrary" navigation-tree-DESIGN12-18140190.html | head -1
```

**Output shows:**
```
1|18140190|18153685|EngineeringResourceLibrary|...|164
                                                    ^^^
                                                Still showing 164!
```

This is because the SQL file being used doesn't have the COALESCE logic yet.

---

## Step 3: Apply Dynamic COALESCE to SQL File

After restoring the file, you need to replace **~13 instances** of:
```sql
TO_CHAR(cd.TYPE_ID)
```

With:
```sql
-- Dynamic parent class icon lookup
TO_CHAR(COALESCE(
    (SELECT di.TYPE_ID FROM DESIGN12.DF_ICONS_DATA di WHERE di.TYPE_ID = cd.TYPE_ID),
    (SELECT di.TYPE_ID FROM DESIGN12.DF_ICONS_DATA di WHERE di.TYPE_ID = cd.DERIVED_FROM),
    cd.TYPE_ID
))
```

### Critical Locations:

1. **Line ~15** - Level 0 (Root node)
2. **Line ~40** - Level 1 ELSE clause (⚠️ MOST IMPORTANT for EngineeringResourceLibrary)
3. **Line ~75** - Level 2+ hierarchical query
4. **All table queries:**
   - PART_ table query
   - ROBCADSTUDY_ table query
   - LINESIMULATIONSTUDY_ table query
   - GANTTSTUDY_ table query
   - SIMPLEDETAILEDSTUDY_ table query
   - LOCATIONALSTUDY_ table query
   - TOOLPROTOTYPE_ table query
   - TOOLINSTANCEASPECT_ table query
   - RESOURCE_ table query
   - OPERATION_ table query
   - SHORTCUT_ table query
   - TxProcessAssembly table query

### Search & Replace Strategy:

**Option A - Manual Edit (Safest):**
1. Open `get-tree-DESIGN12-18140190.sql` in editor
2. Search for: `TO_CHAR(cd.TYPE_ID)`
3. For each occurrence, check if it already has COALESCE
4. If not, replace with the COALESCE version above

**Option B - Automated (Faster but verify after):**
Use the `apply-dynamic-icon-lookup.ps1` script (already created).

---

## Step 4: Regenerate HTML

After updating the SQL file:

```powershell
cd c:\Users\georgem\source\repos\cursor\SimTreeNav
.\regenerate-tree-simple.ps1
```

Or:
```powershell
.\src\powershell\main\tree-viewer-launcher.ps1 -LoadLast
```

---

## Step 5: Verify the Fix

### Check 1: Grep the HTML
```bash
grep "EngineeringResourceLibrary" navigation-tree-DESIGN12-18140190.html | head -1
```

**Expected output (TYPE_ID should be 48):**
```
1|18140190|18153685|EngineeringResourceLibrary|...|48
                                                    ^^
                                                Should now be 48!
```

### Check 2: Browser Console
Open `navigation-tree-DESIGN12-18140190.html` in browser and check console:

**Before fix:**
```
[ICON DEBUG] Node: "EngineeringResourceLibrary" | TYPE_ID: 164 | niceName: RobcadResourceLibrary
```

**After fix:**
```
[ICON DEBUG] Node: "EngineeringResourceLibrary" | TYPE_ID: 48 | niceName: RobcadResourceLibrary
```

### Check 3: Visual Inspection
- EngineeringResourceLibrary should show a **different icon** from its child "robcad_local" node
- Both icons should come from the database (embedded base64)
- No "Failed to load resource" errors in console for icons

---

## Step 6: Test the COALESCE Logic (Optional)

Run the test query to confirm TYPE_ID resolution:

```powershell
.\run-diagnostic-query.ps1
```

**Expected output:**
```
CHILD_TYPE_ID: 164
PARENT_TYPE_ID: 48
HAS_OWN_ICON: (null)
PARENT_HAS_ICON: 48
RESOLVED_TYPE_ID: 48  ← This confirms COALESCE works!
```

---

## Success Criteria ✓

- [ ] SQL file restored from git
- [ ] All ~13 `TO_CHAR(cd.TYPE_ID)` replaced with COALESCE
- [ ] HTML regenerated successfully
- [ ] EngineeringResourceLibrary shows TYPE_ID **48** in HTML
- [ ] Browser console shows TYPE_ID **48** for EngineeringResourceLibrary
- [ ] EngineeringResourceLibrary displays different icon from children
- [ ] No icon loading errors in console
- [ ] Test query confirms COALESCE returns TYPE_ID 48

---

## Files Already Modified ✅

These files have already been updated and don't need changes:

1. ✅ `src/powershell/main/generate-tree-html.ps1` - Removed TYPE_ID 164 hardcoded fallback
2. ✅ `src/powershell/main/generate-full-tree-html.ps1` - Removed TYPE_ID 164 from special handling
3. ✅ `DYNAMIC-ICON-SOLUTION-COMPLETE.md` - Complete documentation
4. ✅ `test-dynamic-lookup.sql` - Testing query
5. ✅ `regenerate-tree-simple.ps1` - Quick regeneration script

---

## Troubleshooting

### Issue: TYPE_ID still shows 164 after regeneration
**Cause:** SQL file wasn't updated with COALESCE logic
**Fix:** Check Step 3 - ensure ALL instances are replaced

### Issue: SQL syntax error when regenerating
**Cause:** COALESCE syntax incorrect or missing parenthesis
**Fix:** Compare with example in DYNAMIC-ICON-SOLUTION-COMPLETE.md

### Issue: Can't restore SQL file from git
**Cause:** File may have been committed as deleted
**Fix:** Check git log to find commit with the file, or recreate manually

---

## Next Issues to Address (After Icon Fix)

Once the icon fix is verified, address these data extraction issues:

1. **COWL_SILL_SIDE [18208744]** - Missing 4 PartPrototype children
2. **PartInstanceLibrary [18143953]** - Missing CompoundPart nodes and PartPrototype instances

These are separate from the icon issue and require different SQL query fixes.

---

**End of Verification Steps**
