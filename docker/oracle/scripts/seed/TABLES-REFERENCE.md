# Seed tables reference (proof of understanding)

How the Siemens schema tables used by the tree viewer relate. All IDs and names below match the seed scripts.

## Table roles

| Table | Role | Key columns |
|-------|------|-------------|
| **COLLECTION_** | One row per tree node (project, folder, study, library, etc.). | `OBJECT_ID` (PK), `CAPTION_S_` (display name), `CLASS_ID` → CLASS_DEFINITIONS.TYPE_ID |
| **REL_COMMON** | Parent–child edges and display order. | `OBJECT_ID` = child, `FORWARD_OBJECT_ID` = parent, `PROJECT_ID`, `SEQ_NUMBER` |
| **CLASS_DEFINITIONS** | Type of each node (name + icon inheritance). | `TYPE_ID` (PK), `NAME`, `NICE_NAME`, `DERIVED_FROM` (parent type) |
| **DF_ICONS_DATA** | Icon image (BLOB) per type. | `TYPE_ID`, `CLASS_IMAGE` (BMP BLOB) |
| **DFPROJECT** | List of project roots for the launcher. | `PROJECTID` = COLLECTION_.OBJECT_ID of root |
| **PART_** | Part/layout nodes (optional; tree LEFT JOINs). | `OBJECT_ID`, `CLASS_ID`, `NAME_S_` |
| **USER_**, **PROXY** | Checkout display (optional). | PROXY.OBJECT_ID, OWNER_ID → USER_.OBJECT_ID |

## Relationships

- **Tree structure:** REL_COMMON.OBJECT_ID (child) and FORWARD_OBJECT_ID (parent) both point to COLLECTION_.OBJECT_ID. PROJECT_ID scopes edges to a project.
- **Node type:** COLLECTION_.CLASS_ID = CLASS_DEFINITIONS.TYPE_ID. CLASS_DEFINITIONS.DERIVED_FROM chains for icon inheritance.
- **Icons:** DF_ICONS_DATA.TYPE_ID = CLASS_DEFINITIONS.TYPE_ID; CLASS_IMAGE is BMP. If missing, front-end uses NICE_NAME → fallback icon (e.g. Project → LogProject.bmp).
- **Launcher projects:** DFPROJECT.PROJECTID must equal the OBJECT_ID of a root node in COLLECTION_ (e.g. 100, 200).

## Seed IDs (project 100)

- Root: OBJECT_ID 100 (Local Dev Project), CLASS_ID 64 (Project).
- Level 1: 101 Studies, 102 Resources, 104 Part Library, 105 Mfg Library, 106 Engineering Resource Library, 107 DES_Studies, 108 Working Folders.
- Under 101: 103 Sample Study, 109–111 (more studies).
- Under 107: 112 Layout Studies, 113 Robot Studies. Under 112: 114–115 (Line layouts).
- Under 102: 116 Robots, 117 Fixtures. Under 104: 118 Body Panels, 119 Clamps.
- REL_COMMON: REL_COMMON_ID 1–19 for project 100; 20 for project 200 (201 under 200).

## TYPE_IDs in seed

- 14 Node, 18 Collection, 64 PmProject, 69 ShortcutFolder, 70 Study, 72 PmStudyFolder, 177 PmRobcadStudy.
- 46 PmPartLibrary, 162 MaterialLibrary, 164 RobcadResourceLibrary.
- 21 CompoundPart, 62 Process, 108 LocationalStudy.

---

## How we know tree dependency and “what can be under what”

### 1. Tree node dependency (who is under whom)

**Source: REL_COMMON only.**

- Each row = one parent→child edge: `OBJECT_ID` = child, `FORWARD_OBJECT_ID` = parent (both are COLLECTION_.OBJECT_ID).
- The tree is the graph of these edges. There is no separate “dependency” table.
- We get the full tree by starting at the project root and walking REL_COMMON with `CONNECT BY` (e.g. `START WITH FORWARD_OBJECT_ID = project_id` then `CONNECT BY PRIOR OBJECT_ID = FORWARD_OBJECT_ID`).
- So “dependency” = whatever links exist in REL_COMMON for that PROJECT_ID. If a row (child_id, parent_id, project_id) exists, that child is under that parent in the tree.

### 2. What nodes can be created under what parent (from project root)

**Not in the database we use.**

- The schema we have (COLLECTION_, REL_COMMON, CLASS_DEFINITIONS, DFPROJECT, …) does **not** define “type X is allowed only under type Y.” REL_COMMON just stores (child, parent, project, seq); any OBJECT_ID can be the child of any FORWARD_OBJECT_ID.
- So “what can be created under the project root” (or under Studies, Part Library, etc.) is **not** read from a table in this schema. It is enforced by the **Siemens application** (eMPower / Process Simulate) when users create or link nodes.
- In this codebase we only **infer** a typical shape from:
  - **Existing data:** e.g. FORD_DEARBORN / J7337_Rosslyn: under the root you see Studies, Part Library, Mfg Library, DES_Studies, Working Folders, etc.
  - **Tree script:** Level‑1 ordering in `generate-tree-html.ps1` uses a fixed `ORDER BY CASE r.OBJECT_ID WHEN ...` for one real project’s OBJECT_IDs (P702, DES_Studies, Working Folders, …), which reflects how that project was structured, not a generic “allowed children” rule.
- For the **seed**, we created “under project root” and “under Studies/DES_Studies/Resources/Part Library” by copying that conventional structure (Studies, Resources, Part Library, Mfg Library, Engineering Resource Library, DES_Studies, Working Folders, then studies under Studies, etc.). So the seed mirrors observed structure; it is not driven by a DB table that lists allowed child types per parent type.

**Summary:** Dependency = REL_COMMON edges. “What can be created under what” = application rules (and convention); not stored in the tables we use.
