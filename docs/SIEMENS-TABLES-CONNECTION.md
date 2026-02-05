# Siemens Tables Connection Guide

How the Siemens Tecnomatix (eMPower) Oracle schema fits together and how SimTreeNav uses it.

---

## 1. Core tables and how they connect

The navigation tree is built from **per-schema** tables (e.g. `DESIGN12`). Each design schema has the same structure.

### 1.1 Tree structure (parent–child)

| Table | Purpose | Key columns |
|-------|---------|-------------|
| **COLLECTION_** | One row per node (project, folder, study, resource, etc.). | `OBJECT_ID` (PK), `CAPTION_S_` (display name), `NAME_` / `NAME1_S_`, `TYPE_ID`, `EXTERNALID_S_` |
| **REL_COMMON** | Parent–child links. | `OBJECT_ID` (child) → COLLECTION_.OBJECT_ID, `FORWARD_OBJECT_ID` (parent) → COLLECTION_.OBJECT_ID, `PROJECT_ID`, `SEQ_NUMBER` (order) |

- **Tree root** = one row in `COLLECTION_` (e.g. project OBJECT_ID = 18140190).
- **Children** = rows in `REL_COMMON` with `FORWARD_OBJECT_ID = <parent OBJECT_ID>` and same `PROJECT_ID`; join to `COLLECTION_` on `OBJECT_ID` for names and type.
- **Order** = `ORDER BY REL_COMMON.SEQ_NUMBER NULLS LAST, COLLECTION_.CAPTION_S_`.

So: **COLLECTION_** = nodes; **REL_COMMON** = edges. Both are required for the tree.

### 1.2 Node type and icons

| Table | Purpose | Key columns |
|-------|---------|-------------|
| **CLASS_DEFINITIONS** | Object types (class names, inheritance). | `TYPE_ID` (PK), `NAME` / `CLASS_NAME`, `NICE_NAME`, `DERIVED_FROM` (parent TYPE_ID) |
| **DF_ICONS_DATA** | Icon image (BLOB) per type. | `TYPE_ID` → CLASS_DEFINITIONS, `CLASS_IMAGE` (BLOB) |

- **COLLECTION_.TYPE_ID** → **CLASS_DEFINITIONS.TYPE_ID** (node type and name).
- **CLASS_DEFINITIONS.DERIVED_FROM** → another CLASS_DEFINITIONS row (icon inheritance).
- **DF_ICONS_DATA** gives the bitmap for a TYPE_ID; if missing, the app uses the inherited type’s icon.

So: **COLLECTION_** → **CLASS_DEFINITIONS** (and **DF_ICONS_DATA**) for type and icon.

### 1.3 Checkout / user activity

| Table | Purpose | Key columns |
|-------|---------|-------------|
| **PROXY** | Checkout state per object. | `OBJECT_ID` → COLLECTION_, `OWNER_ID`, `WORKING_VERSION_ID`, `PROJECT_ID` |
| **USER_** | User names. | `OBJECT_ID` (PK), `CAPTION_S_`, `NAME_` |

- **PROXY.OBJECT_ID** = node in **COLLECTION_**.
- **PROXY.OWNER_ID** → **USER_.OBJECT_ID** for “checked out by” display.

---

## 2. Connection diagram (how tables link)

```
COLLECTION_ (nodes)
  OBJECT_ID (PK) ─────────────────────────────────────────┐
  TYPE_ID ──────► CLASS_DEFINITIONS (type names, inheritance) │
       │              TYPE_ID (PK)                            │
       │              DERIVED_FROM                            │
       │                    │                                 │
       └────────────────────┼────────────────────────────────┤
                            ▼                                 │
                    DF_ICONS_DATA (icons)                     │
                      TYPE_ID, CLASS_IMAGE (BLOB)              │
                                                              │
REL_COMMON (edges)                                            │
  OBJECT_ID (child) ─────────────────────────────────────────┘
  FORWARD_OBJECT_ID (parent) ──► COLLECTION_.OBJECT_ID
  PROJECT_ID, SEQ_NUMBER

PROXY (checkout)
  OBJECT_ID ──► COLLECTION_.OBJECT_ID
  OWNER_ID ────► USER_.OBJECT_ID
  PROJECT_ID, WORKING_VERSION_ID
```

---

## 3. How SimTreeNav uses these tables

1. **Tree data**  
   Query **REL_COMMON** + **COLLECTION_** (and **CLASS_DEFINITIONS** for type/name) for a given project root OBJECT_ID and PROJECT_ID, ordered by SEQ_NUMBER.  
   See: `generate-tree-html.ps1`, `queries/tree-navigation/*.sql`, and [DATABASE-SCHEMA.md](../DATABASE-SCHEMA.md).

2. **Icons**  
   Read **DF_ICONS_DATA** and **CLASS_DEFINITIONS** (including **DERIVED_FROM** chain), map TYPE_ID → icon; cache for 7 days.

3. **Checkout / “who has it”**  
   Join **PROXY** (WORKING_VERSION_ID > 0) to **USER_** to show owner next to nodes.

4. **Scope**  
   All queries are scoped by **PROJECT_ID** (and usually one root **OBJECT_ID**).

---

## 4. Local database vs remote

- **Local (ORACLE_LOCAL, localdb01)**  
  - Has **tablespaces and roles** (from `setup-siemens.bat`).  
  - Has **EMP_ADMIN** and system users.  
  - Does **not** have a **DESIGN*** schema or Siemens application data until you **import a Data Pump dump** into that local DB.  
  - After import you’ll have e.g. **DESIGN12** (or similar) with **COLLECTION_**, **REL_COMMON**, **CLASS_DEFINITIONS**, **DF_ICONS_DATA**, **PROXY**, **USER_**.

- **Remote (e.g. SIEMENS_PS_DB)**  
  - Usually already has one or more **DESIGN*** schemas with full data.  
  - SimTreeNav connects using the same table names and relationships; only schema name (e.g. DESIGN12) and connection (TNS) change.

So: **table connections are the same**; only the presence of a DESIGN* schema and data differs. Use **Switch-DatabaseTarget.ps1** to switch between LOCAL and REMOTE; see [AGENTS.md](../AGENTS.md).

---

## 5. Quick reference: minimum tables for tree + icons

| Schema object | Purpose |
|---------------|--------|
| **COLLECTION_** | Node names and TYPE_ID |
| **REL_COMMON** | Parent–child and order (SEQ_NUMBER) |
| **CLASS_DEFINITIONS** | Type names and icon inheritance |
| **DF_ICONS_DATA** | Icon BLOBs (optional; app can fall back to class icons) |
| **PROXY** | Checkout status (optional) |
| **USER_** | User names for PROXY (optional) |

Full reference: [DATABASE-SCHEMA.md](../DATABASE-SCHEMA.md).
