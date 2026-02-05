# Node types and parent–child relationships

Reference for “what can be under what” in the Siemens tree. In the DB this is **not** stored as rules—only as rows in **REL_COMMON** and in specialized tables. This doc summarizes what the tree script and investigations have found.

---

## 0. Can you understand parent–child from the DB alone?

**Short answer:** You can recover the **graph of who-is-whose-parent** from the DB with no extra docs. You **cannot** fully interpret nodes (labels, types, which table they live in) without more information.

| What | From DB only? | How |
|------|----------------|-----|
| **Edges (parent → child)** | **Yes** | **REL_COMMON**: each row is one edge. `OBJECT_ID` = child, `FORWARD_OBJECT_ID` = parent. Query by `PROJECT_ID` and you have the full set of edges for that project. You can infer direction (e.g. root has no row where it is the child; leaves never appear as parent). |
| **Which table a node lives in** | **No** | `OBJECT_ID` is just a number. It can appear in **COLLECTION_**, **ROBCADSTUDY_**, **SHORTCUT_**, **PART_**, **OPERATION_**, etc. The schema does not have one "nodes" table; there is no single place that lists "this OBJECT_ID is in this table." You need a known list of entity tables and a way to look up OBJECT_ID in each (or try each) to resolve a node. |
| **Node type / class (TYPE_ID)** | **Partly** | If you find the row (e.g. in COLLECTION_), it may have **CLASS_ID** or **TYPE_ID**; **CLASS_DEFINITIONS** maps TYPE_ID → name. So once you know which table the node is in, type is in the DB. |
| **One exception** | **No** | **TOOLINSTANCEASPECT_** parent is **ATTACHEDTO_SR_**, not REL_COMMON. So the full parent–child graph is REL_COMMON **plus** (OBJECT_ID, ATTACHEDTO_SR_) from that table. Without knowing that, you'd miss or mis-assign those edges. |

So: **parent–child structure (the tree shape)** is in the data; **interpretation (which table, type, name)** needs either this doc, the tree script, or reverse‑engineering the list of tables and the TOOLINSTANCEASPECT_ rule.

---

## 1. Where nodes live (table → type)

| Table | TYPE_ID(s) | NICE_NAME / usage |
|-------|------------|---------------------|
| **COLLECTION_** | Many | Project (64), StudyFolder (72), Collection (18), PartLibrary (46), RobcadResourceLibrary (164), etc. |
| **ROBCADSTUDY_** | 177 | RobcadStudy |
| **LINESIMULATIONSTUDY_** | 178 | LineSimulationStudy |
| **GANTTSTUDY_** | 183 | GanttStudy |
| **SIMPLEDETAILEDSTUDY_** | 181 | SimpleDetailedStudy |
| **LOCATIONALSTUDY_** | 108 | LocationalStudy |
| **SHORTCUT_** | 68 | Shortcut |
| **ROBCADSTUDYINFO_** | 179 | RobcadStudyInfo |
| **PART_** | 21, 54, 55, 133, … | CompoundPart, PartPrototype, PartInstance, **TxProcessAssembly (133)**, etc. |
| **PARTPROTOTYPE_** | (via CLASS_ID) | PartPrototype – design parts under PartLibrary / collections |
| **TOOLPROTOTYPE_** | (via CLASS_ID) | ToolPrototype – tools under collections |
| **TOOLINSTANCEASPECT_** | 74, … | ToolInstanceAspect – parent via ATTACHEDTO_SR_ |
| **RESOURCE_** | (via CLASS_ID) | Resource – robots, equipment under CompoundResource / collections |
| **OPERATION_** | 19, 62, 101, 141, … | Operation, Process, GenericRoboticOperation, WeldOperation, etc. |
| **MFGFEATURE_** | (via CLASS_ID) | MfgFeature – weld points, fixtures |
| **MODULE_** | (via CLASS_ID) | Module – subassemblies |

All of these are linked into the tree via **REL_COMMON** (OBJECT_ID = child, FORWARD_OBJECT_ID = parent), except **TOOLINSTANCEASPECT_** which uses **ATTACHEDTO_SR_** as parent.

---

## 2. What can be under **StudyFolder** (TYPE_ID 72)

Parent: a node in **COLLECTION_** with CLASS_ID = 72 (NICE_NAME StudyFolder). Children are every type that appears in REL_COMMON with that parent OBJECT_ID. From the tree script and real data:

| Child | Table | TYPE_ID | Note |
|-------|--------|---------|------|
| **StudyFolder** | COLLECTION_ | 72 | Nested folders (e.g. DES_Studies → Layout Studies, Robot Studies) |
| **RobcadStudy** | ROBCADSTUDY_ | 177 | Main study type (e.g. Sample Study, Weld Study A) |
| **LineSimulationStudy** | LINESIMULATIONSTUDY_ | 178 | Line simulation studies |
| **GanttStudy** | GANTTSTUDY_ | 183 | Gantt studies |
| **SimpleDetailedStudy** | SIMPLEDETAILEDSTUDY_ | 181 | Simple detailed studies |
| **LocationalStudy** | LOCATIONALSTUDY_ | 108 | Locational studies |
| **Collection** | COLLECTION_ | 18 | Generic collection/folder under Studies |

So under a StudyFolder you get: **more StudyFolders** (nested) and **study types** (177, 178, 183, 181, 108, etc.). The tree script adds these via the main CONNECT BY (COLLECTION_) plus explicit queries for ROBCADSTUDY_, LINESIMULATIONSTUDY_, GANTTSTUDY_, SIMPLEDETAILEDSTUDY_, LOCATIONALSTUDY_.

---

## 3. What can be under **RobcadStudy** (TYPE_ID 177)

Parent: a row in **ROBCADSTUDY_** (same OBJECT_ID in REL_COMMON as FORWARD_OBJECT_ID). Children are in **specialized tables**, not only COLLECTION_:

| Child | Table | TYPE_ID | Note |
|-------|--------|---------|------|
| **Shortcut** | SHORTCUT_ | 68 | Station refs (8J-010, …), operation shortcuts, LAYOUT, etc. |
| **RobcadStudyInfo** | ROBCADSTUDYINFO_ | 179 | Study metadata nodes |
| **StudyFolder** | COLLECTION_ | 72 | Occasionally a folder under a study |

So under a **study** you get mainly **Shortcuts** (68) and **RobcadStudyInfo** (179). The tree script only adds SHORTCUT_ explicitly; ROBCADSTUDYINFO_ is commented out but exists in the DB.

---

## 4. What can be under **Project root** (and generic COLLECTION_ in tree)

Under the project root (and any COLLECTION_ node that is “in the tree”):

| Child | Table | Parent condition |
|-------|--------|-------------------|
| StudyFolder, PartLibrary, Collection, … | COLLECTION_ | Any COLLECTION_ in tree (CONNECT BY) |
| PartPrototype, CompoundPart, … | PART_ | Parent in COLLECTION_ or PART_ (script: PART_ not in COLLECTION_) |
| TxProcessAssembly | PART_ | CLASS_ID 133; parent in temp_project_objects (any reachable node) |
| ToolPrototype | TOOLPROTOTYPE_ | Parent in COLLECTION_ in tree |
| ToolInstanceAspect | TOOLINSTANCEASPECT_ | ATTACHEDTO_SR_ in COLLECTION_ in tree |
| Resource | RESOURCE_ | Parent in COLLECTION_ in tree |
| Operation | OPERATION_ | Parent in temp_project_objects (iterative REL_COMMON) |
| MfgFeature | MFGFEATURE_ | Parent in temp_project_objects |
| Module | MODULE_ | Parent in temp_project_objects |
| PartPrototype | PARTPROTOTYPE_ | Parent in COLLECTION_ in tree (e.g. PartLibrary) |

So under the **project** you get: top-level **COLLECTION_** nodes (Studies, Resources, Part Library, Mfg Library, DES_Studies, Working Folders, …), and under those the same rules apply; plus **PART_**, **OPERATION_**, **RESOURCE_**, **TOOLPROTOTYPE_**, **MFGFEATURE_**, **MODULE_**, **PARTPROTOTYPE_**, etc., depending on parent.

---

## 5. What can be under **PartLibrary** / **PartInstanceLibrary** / PART_

- **PartLibrary** (COLLECTION_, 46): children in **COLLECTION_** (e.g. Body Panels, Clamps) and **PART_** / **PARTPROTOTYPE_** (parts).
- **PartInstanceLibrary** (ghost node, OBJECT_ID 18143953): script adds **PART_** children explicitly (no COLLECTION_ row for the ghost).
- **PART_** nodes (e.g. P702, CompoundPart): children can be **PART_** (same table) or **COLLECTION_**; TxProcessAssembly (133) can have PART_ or COLLECTION_ parents.

---

## 6. Summary by parent type

| Parent type | Child types / tables (observed in script + data) |
|-------------|----------------------------------------------------|
| **StudyFolder** (72) | StudyFolder (72), RobcadStudy (177), LineSimulationStudy (178), GanttStudy (183), SimpleDetailedStudy (181), LocationalStudy (108), Collection (18) |
| **RobcadStudy** (177) | Shortcut (68), RobcadStudyInfo (179), StudyFolder (72) |
| **Project / Collection** (generic) | COLLECTION_ (any), PART_, TOOLPROTOTYPE_, TOOLINSTANCEASPECT_, RESOURCE_, OPERATION_, MFGFEATURE_, MODULE_, PARTPROTOTYPE_ (parent in tree) |
| **PartLibrary** | COLLECTION_, PART_, PARTPROTOTYPE_ |
| **PartInstanceLibrary** (ghost) | PART_ only (script hardcodes) |
| **PART_** (e.g. TxProcessAssembly) | PART_, COLLECTION_, OPERATION_, etc. (via REL_COMMON + temp_project_objects) |

---

## 7. How we know (no “allowed children” table)

- **Dependency** = **REL_COMMON**: (OBJECT_ID, FORWARD_OBJECT_ID, PROJECT_ID, SEQ_NUMBER). If a row exists, that child is under that parent in the tree.
- **“What can be under what”** is **not** in the schema as a rule table. It comes from:
  1. **Existing data**: which (parent_id, child_id) pairs appear in REL_COMMON.
  2. **Which table the child lives in**: COLLECTION_, ROBCADSTUDY_, SHORTCUT_, PART_, etc.—each has its own query in the tree script.
  3. **Siemens application**: the real “allowed” rules are in eMPower/Process Simulate when creating/linking nodes; we only observe the result in the DB.

So this doc is the “bottom of it” for the codebase: a single place that lists node tables, types, and which parent types they appear under (StudyFolder, RobcadStudy, project root, PartLibrary, etc.), so both you and the code can reason about the DB consistently.
