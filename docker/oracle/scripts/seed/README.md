# Seed schema (no dump required)

Creates a Siemens-compatible schema **DESIGN1** with **lots of seed data and icons** so you can run the SimTreeNav tree viewer locally without a Data Pump dump.

## What it creates

- **User/schema:** DESIGN1 (password DESIGN1)
- **Tables:** COLLECTION_, REL_COMMON, CLASS_DEFINITIONS, DF_ICONS_DATA, PART_, USER_, PROXY, DFPROJECT
- **Scripts (run in order):**
  - **01** – Create schema and tables
  - **02** – Base seed: one project (100), Studies, Resources, Sample Study
  - **03** – Extended seed: many more nodes (Part Library, Mfg Library, Engineering Resource Library, DES_Studies, Working Folders, multiple studies, subfolders, second project 200)
  - **04** – Icon placeholders: minimal BMP BLOBs in DF_ICONS_DATA for TYPE_IDs 14, 18, 64, 69, 70, 72, 46, 162, 164, 177
- **Tree shape (project 100):**
  - Local Dev Project (100)
    - Studies (101) → Sample Study, Weld Study A, Spot Study B, Process Study
    - Resources (102) → Robots, Fixtures
    - Part Library (104) → Body Panels, Clamps
    - Mfg Library (105), Engineering Resource Library (106)
    - DES_Studies (107) → Layout Studies (112) → Line 1/2 Layout, Robot Studies (113)
    - Working Folders (108)
- **Projects in launcher:** 100 (Local Dev Project), 200 (Second Project)

## Run

From repo root or `docker/oracle`:

```powershell
.\docker\oracle\Run-SeedSchema.ps1
```

Requires: local Oracle running, listener up, sqlplus in PATH (or ORACLE_HOME set). Runs as SYS.

## Use in tree launcher

1. Switch to local: `.\src\powershell\database\docker\Switch-DatabaseTarget.ps1 -Target LOCAL`
2. Run launcher: `.\src\powershell\main\tree-viewer-launcher.ps1`
3. Select schema: **DESIGN1**
4. Select project: **Local Dev Project** (ID 100)

Icons will use app fallbacks (DF_ICONS_DATA is empty). To add more nodes, insert into COLLECTION_ and REL_COMMON.
