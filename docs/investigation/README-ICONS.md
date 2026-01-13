# Navigation Tree Viewer - Database Icon Extraction

## Overview
This project extracts custom BMP icons from Oracle database BLOBs and displays them in an interactive web-based navigation tree viewer for Siemens Process Simulation projects.

## 🎯 Current Status: WORKING ✅

### What Works
- ✅ **95 icons** successfully extracted from Oracle `DF_ICONS_DATA` table
- ✅ **RAWTOHEX** method reliably extracts BLOBs via SQL*Plus
- ✅ All icons validated as proper BMP files
- ✅ Icons automatically integrated into navigation tree HTML
- ✅ Fallback system for nodes without database icons
- ✅ Fully automated - no manual steps required

## 🚀 Quick Start

### For End Users
```powershell
# Just run this - everything is automatic!
.\tree-viewer-launcher.ps1
```

### For Developers
```powershell
# Extract icons only
.\extract-icons-hex.ps1 -Schema DESIGN12

# Generate tree with icons
.\generate-tree-html.ps1 -TNSName SIEMENS_PS_DB_DB01 -Schema DESIGN12 -ProjectId 18140190 -ProjectName "FORD_DEARBORN"
```

## 📁 Key Files

### Scripts
| File | Purpose | When to Use |
|------|---------|-------------|
| [tree-viewer-launcher.ps1](tree-viewer-launcher.ps1) | Interactive launcher | **Start here** - easiest way to use |
| [generate-tree-html.ps1](generate-tree-html.ps1) | Generate tree + extract icons | Direct tree generation, automation |
| [extract-icons-hex.ps1](extract-icons-hex.ps1) | Extract icons only | Troubleshooting, testing |
| [generate-full-tree-html.ps1](generate-full-tree-html.ps1) | Create HTML from data | Internal use (called by generate-tree-html.ps1) |

### Documentation
| File | Content |
|------|---------|
| [QUICK-START-GUIDE.md](QUICK-START-GUIDE.md) | 📖 **Read this first** - how to use the system |
| [ICON-EXTRACTION-SUCCESS.md](ICON-EXTRACTION-SUCCESS.md) | 📊 Technical details, testing results |
| [ICON-EXTRACTION-ATTEMPTS.md](ICON-EXTRACTION-ATTEMPTS.md) | 📜 History of what didn't work |
| [README-ICONS.md](README-ICONS.md) | 📋 This file - project overview |

### Data Files
| File/Directory | Content |
|----------------|---------|
| `icons/` | 95 extracted BMP icon files (`icon_14.bmp`, `icon_64.bmp`, etc.) |
| `extracted-type-ids.json` | JSON array of TYPE_IDs with extracted icons |
| `navigation-tree-*.html` | Generated navigation tree HTML files |

## 🔧 How It Works

### Architecture
```
┌─────────────────────────────────────────────────────────┐
│ tree-viewer-launcher.ps1                                │
│ (Interactive menu)                                       │
└────────────┬────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────┐
│ generate-tree-html.ps1                                  │
├─────────────────────────────────────────────────────────┤
│ 1. Extract icons (RAWTOHEX from Oracle BLOB)           │
│ 2. Query tree structure from database                   │
│ 3. Clean and format data                                │
│ 4. Call generate-full-tree-html.ps1                     │
└────────────┬────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────┐
│ generate-full-tree-html.ps1                             │
├─────────────────────────────────────────────────────────┤
│ 1. Read tree data                                       │
│ 2. Embed extracted TYPE_IDs                             │
│ 3. Generate HTML with JavaScript                        │
│ 4. Save to file                                         │
└────────────┬────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────┐
│ navigation-tree-*.html (opened in browser)              │
├─────────────────────────────────────────────────────────┤
│ JavaScript:                                              │
│ - Parse tree data                                        │
│ - For each node:                                         │
│   * Has TYPE_ID in extractedTypeIds?                     │
│     → Load icons/icon_{TYPE_ID}.bmp                      │
│   * Otherwise:                                           │
│     → Load mapped icon (StudyFolder.bmp, etc.)          │
│ - Render tree with expand/collapse                      │
│ - Search, statistics, etc.                              │
└─────────────────────────────────────────────────────────┘
```

### Icon Extraction Flow
```sql
-- Step 1: Query Oracle database
SELECT
    TYPE_ID || '|' ||
    DBMS_LOB.GETLENGTH(CLASS_IMAGE) || '|' ||
    RAWTOHEX(DBMS_LOB.SUBSTR(CLASS_IMAGE, DBMS_LOB.GETLENGTH(CLASS_IMAGE), 1))
FROM DESIGN12.DF_ICONS_DATA
WHERE CLASS_IMAGE IS NOT NULL;

-- Returns: 64|1334|424D3605000000000000360400002800...
--          ^   ^    ^
--          |   |    └─ Hex data (424D = "BM" header)
--          |   └────── Size in bytes
--          └────────── TYPE_ID
```

```powershell
# Step 2: Convert hex to binary in PowerShell
$iconBytes = New-Object byte[] ($hexData.Length / 2)
for ($i = 0; $i -lt $hexData.Length; $i += 2) {
    $iconBytes[$i / 2] = [Convert]::ToByte($hexData.Substring($i, 2), 16)
}

# Step 3: Validate BMP header
$header = [System.Text.Encoding]::ASCII.GetString($iconBytes[0..1])
if ($header -eq 'BM') {
    [System.IO.File]::WriteAllBytes("icons/icon_64.bmp", $iconBytes)
}
```

```javascript
// Step 4: Load in browser
const extractedTypeIds = new Set([14, 16, 18, 19, 20, 21, ...]);

if (node.typeId && extractedTypeIds.has(node.typeId)) {
    icon.src = `icons/icon_${node.typeId}.bmp`;
} else {
    icon.src = `icons/${getIconForClass(className, caption, niceName)}`;
}
```

## 🎨 Icon System

### Icon Priority
1. **Database icons** (highest priority)
   - Extracted from `DF_ICONS_DATA.CLASS_IMAGE` as `icon_{TYPE_ID}.bmp`
   - Custom icons defined in database
   - Used when node has TYPE_ID in extracted set

2. **NICE_NAME mapped icons** (fallback)
   - Standard icons from file system: `StudyFolder.bmp`, `LogProject.bmp`, etc.
   - Used when no database icon available

### Extracted Icons
95 TYPE_IDs have custom icons in the database:
```
14, 16, 18, 19, 20, 21, 22, 23, 39, 41, 42, 44, 45, 46, 47, 48, 50, 51, 52, 53, 54,
57, 58, 62, 63, 64, 65, 68, 69, 73, 76, 80, 83, 88, 90, 91, 92, 93, 94, 96, 97, 98,
103, 104, 107, 111, 113, 114, 119, 120, 121, 122, 126, 131, 133, 134, 135, 141,
157-162, 166-175, 185-195, 197-199, 204, 206-208, 251, 321-322
```

### Icon Specifications
- Format: **BMP** (Windows Bitmap)
- Size: **16×16 pixels**
- Colors: **256-color palette** (8-bit)
- File size: **246-1,334 bytes**
- Header: Always starts with `424D` (hex) = "BM" (ASCII)

## 🛠️ Technical Details

### Why RAWTOHEX Works

The key insight: SQL*Plus truncates `UTL_ENCODE.BASE64_ENCODE()` output at 492 characters, but `RAWTOHEX()` works fine.

| Approach | Result | Why |
|----------|--------|-----|
| `BASE64_ENCODE(blob)` | ❌ Truncated | SQL*Plus limitation on base64 |
| `RAWTOHEX(blob)` | ❌ Type error | RAWTOHEX needs RAW, not BLOB |
| `RAWTOHEX(DBMS_LOB.SUBSTR(blob))` | ✅ Works! | DBMS_LOB.SUBSTR converts BLOB→RAW |

### Database Schema
```sql
-- Icon storage table
DF_ICONS_DATA (
    TYPE_ID NUMBER,           -- Links to CLASS_DEFINITIONS.TYPE_ID
    CLASS_IMAGE BLOB,         -- BMP icon data
    ...
)

-- Class definitions
CLASS_DEFINITIONS (
    TYPE_ID NUMBER PRIMARY KEY,
    NAME VARCHAR2(255),       -- e.g., "class StudyFolder"
    NICE_NAME VARCHAR2(255),  -- e.g., "StudyFolder"
    ...
)
```

### File Formats

#### extracted-type-ids.json
```json
[
  "14",
  "16",
  "18",
  ...
  "322"
]
```

#### Tree data format
```
LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
0|0|18140190|FORD_DEARBORN|FORD_DEARBORN||0|class StudyFolder|StudyFolder|64
1|18140190|18140250|P1_WELD|P1_WELD|EXTERNAL_001|1|class StudyFolder|StudyFolder|64
2|18140250|18140300|Station_A|Station_A|EXT_STA_A|1|class PmObject|Object|104
...
```

## 📊 Performance

| Operation | Time | Notes |
|-----------|------|-------|
| Icon extraction (95 icons) | ~3 seconds | One-time per tree generation |
| Hex-to-binary conversion | ~10ms per icon | In PowerShell |
| Tree query | ~2-5 seconds | Depends on project size |
| HTML generation | <1 second | Template substitution |
| **Total tree generation** | **5-10 seconds** | Includes all steps |

## 🔍 Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| "No database servers found" | Check `tnsnames.ora` exists |
| "No schemas found" | Verify database connection |
| Icons not showing | Check browser console (F12), verify icon files exist |
| "Invalid BMP header" | Some database icons corrupted - normal, will use fallback |
| Slow generation | Normal for large projects (1000+ nodes) |

### Debug Mode
Open browser console (F12) to see:
```javascript
[ICON DEBUG] Node: "FORD_DEARBORN" | TYPE_ID: 64 | Trying database icon: icon_64.bmp
[ICON RENDER] Node: "FORD_DEARBORN" | Icon Path: "icons/icon_64.bmp?v=..." | IconFile: "icon_64.bmp"
[ICON ERROR] Failed to load icon_999.bmp, falling back to StudyFolder.bmp
```

## 📦 Requirements

### Software
- **PowerShell 7.x** or later
- **Oracle SQL*Plus** (Oracle Client)
- **Oracle Database** access with SYSDBA privileges
- **Modern web browser** (Chrome, Edge, Firefox)

### Database Access
- TNS configuration (`tnsnames.ora`)
- Connection: `sys/change_on_install@TNS_NAME AS SYSDBA`
- Schema access: `DESIGN1`, `DESIGN12`, `DESIGN4`, etc.

### Tables Used
- `DFPROJECT` - Project list
- `COLLECTION_` - Tree nodes
- `CLASS_DEFINITIONS` - Node types
- `DF_ICONS_DATA` - Icon images (BLOBs)
- `REL_COMMON` - Tree relationships

## 🎓 Learning Resources

### Documentation Order
1. **[QUICK-START-GUIDE.md](QUICK-START-GUIDE.md)** - Start here, learn by doing
2. **[README-ICONS.md](README-ICONS.md)** - This file, technical overview
3. **[ICON-EXTRACTION-SUCCESS.md](ICON-EXTRACTION-SUCCESS.md)** - Deep dive, all details
4. **[ICON-EXTRACTION-ATTEMPTS.md](ICON-EXTRACTION-ATTEMPTS.md)** - What didn't work (history)

### Key Concepts
- **TYPE_ID**: Unique identifier for node types (links to icons)
- **NICE_NAME**: Friendly name for class types (e.g., "StudyFolder")
- **BLOB extraction**: Oracle BLOB → hex string → binary file
- **Icon fallback**: Database icon → NICE_NAME icon → default icon
- **extractedTypeIds Set**: JavaScript Set of TYPE_IDs with extracted icons

## 🚦 Project Status

### Completed ✅
- [x] Icon extraction from Oracle BLOBs (RAWTOHEX method)
- [x] BMP validation and file saving
- [x] Integration with tree generation
- [x] JavaScript icon loading with fallback
- [x] Automatic extraction on every tree generation
- [x] Full documentation

### Known Limitations
- Icons re-extracted every time (no caching)
- Some database icons may be corrupted (handled with fallback)
- SQL*Plus required (no pure PowerShell solution)
- Icons overwritten between schemas (last wins)

### Future Enhancements
- [ ] Icon caching (don't re-extract if unchanged)
- [ ] Progress bar during extraction
- [ ] Icon preview in tree viewer
- [ ] Custom icon upload/override
- [ ] PNG support (in addition to BMP)
- [ ] Icon management UI

## 📝 Version History

### v2.0 (Current) - 2026-01-13
- ✅ RAWTOHEX icon extraction (replaces failed base64 approach)
- ✅ 95 icons successfully extracted
- ✅ Full integration with tree viewer
- ✅ Comprehensive documentation

### v1.0 (Failed) - 2026-01-12
- ❌ Base64 icon extraction (truncated at 492 chars)
- ❌ 0 icons extracted successfully
- ❌ All nodes used fallback icons

## 🤝 Contributing

### Reporting Issues
1. Check browser console for JavaScript errors
2. Check PowerShell output for SQL errors
3. Verify all files are present and up-to-date
4. Review documentation for known issues

### Extending Functionality
Key files to modify:
- **Icon extraction**: [extract-icons-hex.ps1](extract-icons-hex.ps1), [generate-tree-html.ps1](generate-tree-html.ps1)
- **HTML generation**: [generate-full-tree-html.ps1](generate-full-tree-html.ps1)
- **UI/styling**: Edit HTML template in generate-full-tree-html.ps1
- **Icon mapping**: Edit `getIconForClass()` function in HTML template

## 📄 License

Internal Siemens project - all rights reserved.

## 🎉 Success Metrics

- **95/95 icons** extracted successfully (100%)
- **0 failures** during extraction
- **All BMPs validated** with correct headers
- **Automatic integration** with tree viewer
- **Fallback system** works perfectly
- **User-friendly launcher** for easy access

---

**Quick Start:**
```powershell
.\tree-viewer-launcher.ps1
```

**Documentation:**
- Quick Start: [QUICK-START-GUIDE.md](QUICK-START-GUIDE.md)
- Technical Details: [ICON-EXTRACTION-SUCCESS.md](ICON-EXTRACTION-SUCCESS.md)

**Status: WORKING** ✅
