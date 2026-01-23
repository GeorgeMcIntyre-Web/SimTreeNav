# Icon Fix Summary - Study Nodes

## Overview
Fixed incorrect icon display for StudyFolder and RobcadStudy nodes by using parent class icons from the database.

## Problem
- **StudyFolder (TYPE_ID 72)** and **RobcadStudy (TYPE_ID 177)** displayed yellow folder icons (incorrect)
- Icons from Siemens app showed:
  - StudyFolder: Green folder with document overlay
  - RobcadStudy: Blue/cyan icon
- Database query revealed: **None of the Study-related TYPE_IDs exist in DF_ICONS_DATA**
  - Missing: 70 (Study), 72 (StudyFolder), 108 (LocationalStudy), 177 (RobcadStudy), 178 (LineSimulationStudy), 181 (SimpleDetailedStudy), 183 (GanttStudy)

## Investigation
Traced class hierarchy in CLASS_DEFINITIONS to find parent classes with icons:

### StudyFolder (TYPE_ID 72) Hierarchy
```
72 (StudyFolder) → NO ICON
├─ 18 (Collection) → ✓ HAS ICON (1334 bytes)
   ├─ 14 (Node) → ✓ HAS ICON (1334 bytes)
      └─ 13 (PfObject) → NO ICON
```

### RobcadStudy (TYPE_ID 177) Hierarchy
```
177 (RobcadStudy) → NO ICON
├─ 108 (LocationalStudy) → NO ICON
   ├─ 70 (Study) → NO ICON
      ├─ 69 (ShortcutFolder) → ✓ HAS ICON (1334 bytes)
         ├─ 14 (Node) → ✓ HAS ICON (1334 bytes)
            └─ 13 (PfObject) → NO ICON
```

## Solution
Modified icon fallback logic in `src/powershell/main/generate-tree-html.ps1`:

1. **StudyFolder (72)** → Uses **Collection (18)** icon
2. **RobcadStudy (177)** and all Study types → Use **ShortcutFolder (69)** icon

### Fallback Mappings
```powershell
# StudyFolder inherits from Collection
TYPE_ID 72 → 18 (Collection parent class icon)

# All Study types inherit from ShortcutFolder
TYPE_ID 70  → 69 (Study → ShortcutFolder parent)
TYPE_ID 108 → 69 (LocationalStudy → ShortcutFolder parent)
TYPE_ID 177 → 69 (RobcadStudy → ShortcutFolder parent)
TYPE_ID 178 → 69 (LineSimulationStudy → ShortcutFolder parent)
TYPE_ID 181 → 69 (SimpleDetailedStudy → ShortcutFolder parent)
TYPE_ID 183 → 69 (GanttStudy → ShortcutFolder parent)
```

## Database Findings

### Icon Tables
Only 3 icon-related columns exist in DESIGN12 schema:
1. `DF_ICONS_DATA.CLASS_IMAGE` (BLOB) - Contains icon binary data
2. `DF_ICONS_DATA.TYPE_ID` (NUMBER) - Primary key for icons
3. `WIRULE_.ICON_SR_` (NUMBER) - Icon reference (not used)

### Why Study Icons Don't Exist
Study-related classes don't have icons in DF_ICONS_DATA because:
- They are specialized/derived classes added later
- Siemens app uses parent class icons for rendering
- Icons may be hardcoded in application or loaded from installation directory

## Files Modified
- `src/powershell/main/generate-tree-html.ps1` (lines 121-158)
  - Updated TYPE_ID 72 fallback: 73 → 18 (Collection)
  - Updated Study type fallbacks: 70/73 → 69 (ShortcutFolder)
  - Added documentation comments explaining class hierarchy

## Result
✅ **StudyFolder nodes** now display Collection folder icon (TYPE_ID 18)
✅ **RobcadStudy nodes** now display ShortcutFolder icon (TYPE_ID 69)
✅ All icons loaded from database (Base64 embedded in HTML)
✅ No missing icon indicators

## Commits
1. `af538f9` - Fix: Project root node now displays correct database icon (TYPE_ID 64)
2. `8ef2ef6` - Fix: Use parent class icons for Study-related nodes

## Testing
Generated tree: `navigation-tree-DESIGN12-18140190.html`
- Total nodes: ~21,910
- Icons extracted: 95 from database + 8 fallbacks = 103 total
- Verified: FORD_DEARBORN > DES_Studies > P702 > DDMP > UNDERBODY > COWL & SILL SIDE > DDMP P702_8J_010_8J_060
- Icons displaying correctly for all node types

## Related Documentation
- `ROBCADSTUDY-CHILDREN-FIX.md` - Fix for RobcadStudy children visibility
- Database queries used:
  - `check-study-type-ids.ps1` - Confirmed Study TYPE_IDs have no icons
  - `check-class-definitions-structure.ps1` - Found TYPE_ID 73 was SupplyChain, not StudyFolder
  - `trace-study-class-hierarchy.ps1` - Traced class inheritance to find parent icons
