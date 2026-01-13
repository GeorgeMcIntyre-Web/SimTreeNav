# Quick Start Guide - Navigation Tree Viewer with Database Icons

## TL;DR - Just Run This
```powershell
.\tree-viewer-launcher.ps1
```
The launcher will:
1. Load your last configuration (or let you select server/schema/project)
2. Extract all icons from the database automatically
3. Generate the navigation tree HTML
4. Open it in your browser

## What You Get

### 🎨 Database Icons
- **95 custom icons** extracted from Oracle database
- Displayed for nodes that have custom TYPE_ID icons
- Automatic fallback to standard icons for other nodes

### 🌲 Navigation Tree
- Full hierarchical tree structure
- Expand/collapse nodes
- Search functionality
- Icon visual hierarchy
- Node counts and statistics

## How Icons Work

### Priority Order
1. **Database Icon**: If the node has a TYPE_ID and that TYPE_ID has an extracted icon → use `icons/icon_{TYPE_ID}.bmp`
2. **NICE_NAME Mapped Icon**: Otherwise → use standard icons like `StudyFolder.bmp`, `LogProject.bmp`, etc.

### Example
- A `StudyFolder` with TYPE_ID 64 → displays custom `icon_64.bmp` from database
- A `StudyFolder` with no TYPE_ID or TYPE_ID 999 (not extracted) → displays standard `StudyFolder.bmp`

## Available Commands

### 1. Interactive Tree Viewer (Recommended)
```powershell
.\tree-viewer-launcher.ps1
```
**What it does:**
- Shows menu to select server, schema, project
- Remembers your last selection
- Extracts icons automatically
- Generates tree HTML
- Opens in browser

**Options:**
- `1` - Select Server (choose database server and instance)
- `2` - Select Schema (choose schema like DESIGN1, DESIGN12, etc.)
- `3` - Load Tree (select project and generate tree)
- `4` - Exit

### 2. Direct Tree Generation
```powershell
.\generate-tree-html.ps1 -TNSName SIEMENS_PS_DB_DB01 -Schema DESIGN12 -ProjectId 18140190 -ProjectName "FORD_DEARBORN"
```
**What it does:**
- Extracts icons from database
- Generates tree for specific project
- Outputs: `navigation-tree-DESIGN12-18140190.html`

**Parameters:**
- `TNSName` - Oracle TNS name (e.g., `SIEMENS_PS_DB_DB01`)
- `Schema` - Database schema (e.g., `DESIGN12`)
- `ProjectId` - Project OBJECT_ID (e.g., `18140190`)
- `ProjectName` - Project name (e.g., `"FORD_DEARBORN"`)
- `OutputFile` - Optional custom output filename

### 3. Extract Icons Only
```powershell
.\extract-icons-hex.ps1 -Schema DESIGN12
```
**What it does:**
- Connects to database
- Extracts all icons from `DF_ICONS_DATA` table
- Saves to `icons/` directory
- Creates `extracted-type-ids.json`

**Parameters:**
- `Schema` - Database schema (default: `DESIGN12`)
- `TNSName` - Oracle TNS name (default: `SIEMENS_PS_DB_DB01`)

## File Structure

```
PsSchemaBug/
├── tree-viewer-launcher.ps1          # 🚀 START HERE - Interactive launcher
├── generate-tree-html.ps1             # Generates tree + extracts icons
├── generate-full-tree-html.ps1        # Creates HTML from tree data
├── extract-icons-hex.ps1              # Standalone icon extractor
│
├── icons/                             # 📁 Extracted icons
│   ├── icon_14.bmp
│   ├── icon_16.bmp
│   ├── icon_64.bmp
│   └── ... (95 icons total)
│
├── extracted-type-ids.json            # List of extracted TYPE_IDs
├── navigation-tree-*.html             # Generated tree HTML files
│
├── ICON-EXTRACTION-SUCCESS.md         # Full technical documentation
├── QUICK-START-GUIDE.md               # This file
└── ICON-EXTRACTION-ATTEMPTS.md        # History of failed attempts
```

## Common Scenarios

### Scenario 1: First Time User
```powershell
# Just run the launcher
.\tree-viewer-launcher.ps1

# Follow prompts:
# 1. Select Server → choose your database server
# 2. Select Schema → choose DESIGN12 (or other schema)
# 3. Load Tree → select your project
#
# Tree opens in browser automatically!
```

### Scenario 2: Returning User
```powershell
# Run launcher - it remembers your last selection
.\tree-viewer-launcher.ps1

# Press Enter (or Y) to use last configuration
# Tree opens immediately!
```

### Scenario 3: Generate Multiple Trees
```powershell
# Interactive mode - stay in menu after each tree
.\tree-viewer-launcher.ps1

# After tree opens, press Enter in the terminal
# Menu reappears - select option 3 again for another project
```

### Scenario 4: Scripting/Automation
```powershell
# Generate tree for specific project (no interaction)
.\generate-tree-html.ps1 `
    -TNSName SIEMENS_PS_DB_DB01 `
    -Schema DESIGN12 `
    -ProjectId 18140190 `
    -ProjectName "FORD_DEARBORN" `
    -OutputFile "ford-tree.html"

# Open in browser
Start-Process ford-tree.html
```

### Scenario 5: Extract Icons for Different Schema
```powershell
# Extract icons from DESIGN1 schema
.\extract-icons-hex.ps1 -Schema DESIGN1

# Generate tree using DESIGN1
.\generate-tree-html.ps1 -TNSName SIEMENS_PS_DB_DB01 -Schema DESIGN1 -ProjectId 60 -ProjectName "My Project"
```

## Tree Viewer Features

### Navigation
- **Click** folder icon or node name → Expand/collapse
- **Expand All** button → Open entire tree
- **Collapse All** button → Close entire tree

### Search
- Type in search box → Filter nodes by name
- Case-insensitive
- Searches CAPTION, NAME, and EXTERNAL_ID fields
- Shows match count

### Statistics
- Total nodes
- Expanded nodes
- Collapsed nodes
- Leaf nodes (no children)
- Updates in real-time as you expand/collapse

### Icons
- Hover over icon → See icon filename in tooltip
- Icons from database use cache-busting to show latest version
- Missing icons automatically fall back to default icon

### Browser Console
Press F12 → Console tab to see:
- `[ICON DEBUG]` - Which TYPE_IDs are being used
- `[ICON RENDER]` - Which icon files are being loaded
- `[ICON ERROR]` - If any icons fail to load (shows fallback)

## Troubleshooting

### Problem: "No database servers found"
**Solution:** Make sure `tnsnames.ora` exists in current directory or `$TNS_ADMIN` path

### Problem: "No schemas found"
**Solution:** Check database connection:
```powershell
sqlplus sys/change_on_install@SIEMENS_PS_DB_DB01 AS SYSDBA
```

### Problem: Icons not showing in browser
**Solution:**
1. Open browser console (F12)
2. Look for errors
3. Check if `icons/icon_{TYPE_ID}.bmp` files exist
4. Try force-refresh: Ctrl+F5 (clears cache)

### Problem: Icons look wrong/corrupted
**Solution:**
1. Re-extract icons: `.\extract-icons-hex.ps1 -Schema DESIGN12`
2. Regenerate tree
3. Force-refresh browser: Ctrl+F5

### Problem: "Invalid BMP header" warnings
**Solution:** Some icons in database may be corrupted. This is normal - the system will skip those and use fallback icons.

### Problem: Tree generation is slow
**Solution:** Icon extraction takes 2-3 seconds for 95 icons. This is normal. The tree generation itself takes 5-10 seconds depending on project size.

### Problem: Can't connect to database
**Solution:**
1. Check TNS configuration: `type tnsnames.ora`
2. Test connection: `sqlplus sys/change_on_install@SIEMENS_PS_DB_DB01 AS SYSDBA`
3. Verify password is correct (default: `change_on_install`)

## Advanced Usage

### Custom Icon Directory
The system expects icons in `icons/` directory. To use a different directory:
1. Modify `$iconsDir` variable in scripts
2. Update HTML templates to reference new path

### Icon Caching
Icons are extracted every time you generate a tree. To skip re-extraction:
1. Comment out the icon extraction section in `generate-tree-html.ps1`
2. Or use pre-extracted icons from previous run

### Multiple Schemas
Each schema may have different icons:
```powershell
# Extract icons from multiple schemas
.\extract-icons-hex.ps1 -Schema DESIGN1
.\extract-icons-hex.ps1 -Schema DESIGN4
.\extract-icons-hex.ps1 -Schema DESIGN12

# Note: Icons are overwritten - last schema wins
# To keep separate: modify script to use different output directories
```

### Export Icons
All extracted icons are standard BMP files:
```powershell
# Copy icons to another location
Copy-Item icons\*.bmp C:\MyIcons\

# Convert to PNG (requires ImageMagick)
Get-ChildItem icons\*.bmp | ForEach-Object {
    magick convert $_.FullName "$($_.DirectoryName)\$($_.BaseName).png"
}
```

## Performance Tips

1. **First run is slower** - icons must be extracted
2. **Subsequent runs** - icons already exist (but are re-extracted anyway)
3. **Large projects** - may take 10-20 seconds to generate tree
4. **Browser performance** - trees with 1000+ nodes may be slow to expand/collapse

## Requirements

- PowerShell 7.x or later
- SQL*Plus (Oracle Client)
- Oracle database access (SYSDBA privileges)
- TNS configuration (tnsnames.ora)
- Modern web browser (Chrome, Edge, Firefox)

## What's Different from Before?

### Before (Failed Attempts)
- ❌ Used base64 encoding → truncated at 492 characters
- ❌ Icons were corrupted
- ❌ 0 icons extracted successfully
- ❌ All nodes used fallback icons

### Now (Working Solution)
- ✅ Uses RAWTOHEX encoding → no truncation
- ✅ Icons are valid BMPs
- ✅ 95 icons extracted successfully
- ✅ Nodes display custom database icons

## Support

### Documentation
- **Full details**: [ICON-EXTRACTION-SUCCESS.md](ICON-EXTRACTION-SUCCESS.md)
- **Quick start**: [QUICK-START-GUIDE.md](QUICK-START-GUIDE.md) (this file)
- **History**: [ICON-EXTRACTION-ATTEMPTS.md](ICON-EXTRACTION-ATTEMPTS.md)

### Scripts
- **Main launcher**: [tree-viewer-launcher.ps1](tree-viewer-launcher.ps1)
- **Tree generator**: [generate-tree-html.ps1](generate-tree-html.ps1)
- **Icon extractor**: [extract-icons-hex.ps1](extract-icons-hex.ps1)

### Getting Help
1. Check browser console (F12) for JavaScript errors
2. Check PowerShell output for SQL errors
3. Review documentation files
4. Check that all files are present and up-to-date

## Quick Reference Card

| Task | Command |
|------|---------|
| Generate tree (interactive) | `.\tree-viewer-launcher.ps1` |
| Generate specific tree | `.\generate-tree-html.ps1 -Schema DESIGN12 -ProjectId 18140190 -ProjectName "Project"` |
| Extract icons only | `.\extract-icons-hex.ps1 -Schema DESIGN12` |
| Test database connection | `sqlplus sys/change_on_install@SIEMENS_PS_DB_DB01 AS SYSDBA` |
| View extracted icons | `Get-ChildItem icons\*.bmp` |
| View extracted TYPE_IDs | `Get-Content extracted-type-ids.json` |
| Open generated tree | `Start-Process navigation-tree-*.html` |

## Success Indicators

✅ You'll know it's working when you see:
- "Successfully extracted: 95 icons" message
- "Extracted TYPE_IDs: 14,16,18,..." list
- "Done! Tree saved to: navigation-tree-*.html" message
- Tree opens in browser with custom icons
- Browser console shows `[ICON DEBUG]` messages for database icons

---

**Ready to start?** Just run:
```powershell
.\tree-viewer-launcher.ps1
```

Enjoy your navigation tree with custom database icons! 🎨🌲
