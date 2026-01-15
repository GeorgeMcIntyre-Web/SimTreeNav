# Quick Start Guide for Other AI Agent

## Overview in 60 Seconds

You need to add 2 SQL queries and fix 1 JavaScript section. Everything is ready - just copy, paste, test, and commit!

## What's Missing from the Tree

```
Current Tree:                       After Your Work:
┌─ Project                          ┌─ Project
├─ StudyFolder                      ├─ StudyFolder
│  ├─ RobcadStudy ✅               │  ├─ RobcadStudy ✅
│  └─ Operation                     │  ├─ Operation
├─ EngineeringResourceLibrary ⚠️   │  └─ ToolPrototype ⬅️ ADD THIS
│  (wrong icon)                     ├─ EngineeringResourceLibrary ✅
└─ Collection                       │  (correct icon after fix)
                                    ├─ Collection
Missing:                            │  └─ ToolInstanceAspect ⬅️ ADD THIS
- ToolPrototype nodes               └─ Resource
- ToolInstanceAspect nodes
- Correct icon for TYPE_ID 164
```

## The 3 Changes You'll Make

### Change 1: Add ToolPrototype SQL
**File:** `src/powershell/main/generate-tree-html.ps1`
**Line:** Around 295 (after RobcadStudy query)
**Action:** Copy-paste the PowerShell code from STEP 2 in HANDOFF-TO-OTHER-AI.md

### Change 2: Add ToolInstanceAspect SQL
**File:** `src/powershell/main/generate-tree-html.ps1`
**Line:** Right after Change 1
**Action:** Copy-paste the PowerShell code from STEP 3 in HANDOFF-TO-OTHER-AI.md

### Change 3: Fix Icon Selection
**File:** `src/powershell/main/generate-full-tree-html.ps1`
**Line:** Around 23161 (icon selection logic)
**Action:** Copy-paste the JavaScript code from STEP 4 in HANDOFF-TO-OTHER-AI.md

## Visual Guide to Files

```
SimTreeNav/
├─ src/powershell/main/
│  ├─ generate-tree-html.ps1        ⬅️ ADD 2 SQL QUERIES HERE
│  │   (Extracts data from Oracle)
│  │   Line ~295: Add ToolPrototype query
│  │   Line ~330: Add ToolInstance query
│  │
│  ├─ generate-full-tree-html.ps1   ⬅️ FIX ICON LOGIC HERE
│  │   (Builds HTML with JavaScript)
│  │   Line ~23161: Fix TYPE_ID 164 icon
│  │
│  └─ tree-viewer-launcher.ps1      ⬅️ USE THIS TO TEST
│      (Run this to generate tree)
│
├─ HANDOFF-TO-OTHER-AI.md           ⬅️ MAIN INSTRUCTIONS (detailed)
├─ QUICK-START-GUIDE.md             ⬅️ YOU ARE HERE (quick overview)
├─ DATABASE-QUERY-RESULTS.md        📖 Reference: Query results
└─ docs/SYSTEM-ARCHITECTURE.md      📖 Reference: System design
```

## The Only Unknown: Parent Relationship

Before you copy-paste the SQL, run this quick query to see which option to use:

```sql
SELECT
    tp.OBJECT_ID,
    tp.NAME_S_,
    tp.COLLECTIONS_VR_,
    c.CAPTION_S_ as PARENT_COLLECTION_NAME
FROM DESIGN12.TOOLPROTOTYPE_ tp
LEFT JOIN DESIGN12.COLLECTION_ c ON tp.COLLECTIONS_VR_ = c.OBJECT_ID
WHERE ROWNUM <= 3;
```

**If you see values in `PARENT_COLLECTION_NAME`:**
→ Use "Option A" from STEP 2 (COLLECTIONS_VR_ is the parent)

**If you see NULLs:**
→ Use "Option B" from STEP 2 (REL_COMMON is the parent)

## Test Checklist

After making changes, test like this:

1. ✅ Run: `.\src\powershell\main\tree-viewer-launcher.ps1`
2. ✅ Select server: `des-sim-db1`
3. ✅ Select instance: `db01`
4. ✅ Select schema: `DESIGN12`
5. ✅ Load tree for: `FORD_DEARBORN` (ID: 18140190)
6. ✅ Open tree in browser
7. ✅ Check console (F12) for icon messages
8. ✅ Verify EngineeringResourceLibrary has correct icon
9. ✅ Search tree for "Tool" to find new nodes

## Expected Console Output

**Before your fix:**
```
[ICON RENDER] Node: "EngineeringResourceLibrary" | Using DATABASE icon (Base64): TYPE_ID 164
```

**After your fix:**
```
[ICON DEBUG] Node: "EngineeringResourceLibrary" | TYPE_ID: 164 | Using class icon (DB missing): filter_library.bmp
```

## Database Connection Info

You don't need to set this up - it's already configured:
- Server: des-sim-db1
- Instance: db01
- Schema: DESIGN12
- Test Project: FORD_DEARBORN (18140190)
- Credentials: Auto-retrieved (no password prompt)

## Commit Message Template

Ready to use - just copy from STEP 6 in HANDOFF-TO-OTHER-AI.md

```bash
git commit -m "feat: Add tool node extraction and fix resource library icon

Complete tool prototype/instance node extraction and fix icon issues
...
(full template in main handoff doc)
"
```

## Time Estimate

- Reading this guide: 2 minutes
- Running verification query: 2 minutes
- Making 3 code changes: 10 minutes
- Testing: 10 minutes
- Committing: 5 minutes
- **Total: ~30 minutes**

## Need Help?

1. **Stuck?** → Check "Troubleshooting" section in HANDOFF-TO-OTHER-AI.md
2. **Confused?** → Read STEP 1-6 in detail in HANDOFF-TO-OTHER-AI.md
3. **Want more context?** → See DATABASE-QUERY-RESULTS.md

## Key Points to Remember

1. **Don't skip STEP 1** - The verification query tells you which SQL option to use
2. **Test incrementally** - Add ToolPrototype query first, test, then add ToolInstance query
3. **Check PowerShell output** - Look for "Added N nodes" messages
4. **Use browser console** - Open DevTools to see icon selection messages
5. **Clear browser cache** - Hard refresh (Ctrl+Shift+R) after icon fix

---

**Ready?** Go to [HANDOFF-TO-OTHER-AI.md](HANDOFF-TO-OTHER-AI.md) and follow STEP 1-6!

**Time to complete:** ~30 minutes

**Difficulty:** Easy (all code is ready, just copy-paste and test)

Good luck! 🚀
