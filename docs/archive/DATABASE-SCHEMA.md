# Database Schema Documentation

## Overview
Complete reference for Siemens Process Simulate Oracle database schema used by the tree viewer.

---

## Key Tables

### 1. COLLECTION_ (Node Data)
**Purpose:** Stores all object data including names, captions, and metadata.

**Structure:**
```sql
CREATE TABLE SCHEMA.COLLECTION_ (
    OBJECT_ID NUMBER PRIMARY KEY,        -- Unique node identifier
    CAPTION_S_ NVARCHAR2(255),          -- Display name
    NAME_ NVARCHAR2(255),                -- Internal name
    VERSION_NO NUMBER,                   -- Version number
    STATUS_ NUMBER,                      -- Object status
    TYPE_ID NUMBER,                      -- Foreign key to CLASS_DEFINITIONS
    -- ... additional columns
)
```

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| OBJECT_ID | NUMBER | Primary key - unique object identifier |
| CAPTION_S_ | NVARCHAR2 | Display name shown in tree |
| NAME_ | NVARCHAR2 | Internal object name |
| TYPE_ID | NUMBER | Links to CLASS_DEFINITIONS for type info |
| STATUS_ | NUMBER | Object status code |
| EXTERNAL_ID | NVARCHAR2 | External reference ID (optional) |

**Usage in Tree Viewer:**
- Primary source of node display names
- Links to CLASS_DEFINITIONS via TYPE_ID for icons
- Provides metadata for node tooltips

**Example Query:**
```sql
SELECT
    c.OBJECT_ID,
    c.CAPTION_S_,
    c.NAME_,
    c.TYPE_ID,
    c.EXTERNAL_ID
FROM DESIGN12.COLLECTION_ c
WHERE c.OBJECT_ID = 18140190;  -- FORD_DEARBORN project
```

---

### 2. REL_COMMON (Relationships)
**Purpose:** Defines parent-child relationships between objects.

**Structure:**
```sql
CREATE TABLE SCHEMA.REL_COMMON (
    REL_COMMON_ID NUMBER PRIMARY KEY,    -- Relationship ID
    OBJECT_ID NUMBER,                    -- Child object ID
    FORWARD_OBJECT_ID NUMBER,            -- Parent object ID
    PROJECT_ID NUMBER,                   -- Project scope
    SEQUENCE_NO NUMBER,                  -- Display order
    -- ... additional columns
)
```

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| REL_COMMON_ID | NUMBER | Unique relationship identifier |
| OBJECT_ID | NUMBER | Child node (points to COLLECTION_) |
| FORWARD_OBJECT_ID | NUMBER | Parent node (points to COLLECTION_) |
| PROJECT_ID | NUMBER | Limits relationships to specific project |
| SEQUENCE_NO | NUMBER | Display order (SEQ_NUMBER) |

**Multi-Parent Support:**
- A single OBJECT_ID can appear multiple times with different FORWARD_OBJECT_IDs
- Enables nodes to appear under multiple parents in tree
- Tree viewer handles circular references with cycle detection

**Usage in Tree Viewer:**
- Defines tree structure (parent-child relationships)
- SEQUENCE_NO determines node ordering
- PROJECT_ID scopes relationships to specific project

**Example Query:**
```sql
-- Find all children of a specific parent
SELECT
    r.OBJECT_ID,
    r.FORWARD_OBJECT_ID,
    r.SEQUENCE_NO,
    c.CAPTION_S_
FROM DESIGN12.REL_COMMON r
JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
WHERE r.FORWARD_OBJECT_ID = 18140190  -- Parent ID
  AND r.PROJECT_ID = 18140190         -- Project scope
ORDER BY r.SEQUENCE_NO;
```

**Hierarchical Tree Query:**
```sql
-- Get complete tree using CONNECT BY
SELECT
    LEVEL as tree_level,
    c.OBJECT_ID,
    c.CAPTION_S_,
    r.FORWARD_OBJECT_ID as parent_id,
    r.SEQUENCE_NO,
    cd.TYPE_ID,
    cd.CLASS_NAME,
    cd.NICE_NAME
FROM DESIGN12.REL_COMMON r
INNER JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
INNER JOIN DESIGN12.CLASS_DEFINITIONS cd ON c.TYPE_ID = cd.TYPE_ID
START WITH r.FORWARD_OBJECT_ID = 18140190  -- Root project ID
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
    AND PRIOR r.PROJECT_ID = r.PROJECT_ID
ORDER SIBLINGS BY r.SEQUENCE_NO NULLS LAST, c.CAPTION_S_;
```

---

### 3. CLASS_DEFINITIONS (Type Definitions)
**Purpose:** Defines object types and their properties.

**Structure:**
```sql
CREATE TABLE SCHEMA.CLASS_DEFINITIONS (
    TYPE_ID NUMBER PRIMARY KEY,          -- Type identifier
    CLASS_NAME VARCHAR2(255),            -- Class name (e.g., "class PmRobot")
    NICE_NAME VARCHAR2(255),             -- Display name (e.g., "Robot")
    DERIVED_FROM NUMBER,                 -- Parent type for inheritance
    -- ... additional columns
)
```

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| TYPE_ID | NUMBER | Primary key - unique type identifier |
| CLASS_NAME | VARCHAR2 | Technical class name |
| NICE_NAME | VARCHAR2 | User-friendly display name |
| DERIVED_FROM | NUMBER | Parent TYPE_ID for inheritance |

**Icon Inheritance:**
- Types can inherit icons from parent types via DERIVED_FROM
- Tree viewer traverses inheritance chain using CONNECT BY
- Enables 221 total icons from 95 base icons + inheritance

**Usage in Tree Viewer:**
- Maps TYPE_ID to icon files
- Provides user-friendly type names
- Enables icon inheritance

**Example Query:**
```sql
-- Get full inheritance chain for a type
SELECT
    LEVEL as inheritance_level,
    TYPE_ID,
    CLASS_NAME,
    NICE_NAME,
    DERIVED_FROM
FROM DESIGN12.CLASS_DEFINITIONS
START WITH TYPE_ID = 177  -- RobcadStudy
CONNECT BY PRIOR DERIVED_FROM = TYPE_ID;
```

---

### 4. DF_ICONS_DATA (Icon Storage)
**Purpose:** Stores icon images as BLOBs.

**Structure:**
```sql
CREATE TABLE SCHEMA.DF_ICONS_DATA (
    TYPE_ID NUMBER PRIMARY KEY,          -- Links to CLASS_DEFINITIONS
    CLASS_IMAGE BLOB,                    -- Icon image data (BMP format)
    -- ... additional columns
)
```

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| TYPE_ID | NUMBER | Links to CLASS_DEFINITIONS |
| CLASS_IMAGE | BLOB | BMP image data |

**Icon Extraction:**
- Icons stored as BMP format in BLOB fields
- Extracted using RAWTOHEX to avoid SQL*Plus truncation
- Converted to Base64 data URIs for HTML embedding

**Usage in Tree Viewer:**
- Source for all node icons
- Combined with inheritance from CLASS_DEFINITIONS
- Cached locally for 7 days

**Extraction Query:**
```sql
-- Extract icons with inheritance
SELECT DISTINCT
    NVL(inheritance.lowest_type_id, cd.TYPE_ID) as TYPE_ID,
    RAWTOHEX(DBMS_LOB.SUBSTR(
        di.CLASS_IMAGE,
        DBMS_LOB.GETLENGTH(di.CLASS_IMAGE),
        1
    )) as HEX_DATA,
    DBMS_LOB.GETLENGTH(di.CLASS_IMAGE) as ICON_SIZE
FROM DESIGN12.CLASS_DEFINITIONS cd
LEFT JOIN DESIGN12.DF_ICONS_DATA di ON cd.TYPE_ID = di.TYPE_ID
LEFT JOIN (
    -- Find inherited icons via DERIVED_FROM chain
    SELECT
        TYPE_ID as lowest_type_id,
        CONNECT_BY_ROOT TYPE_ID as root_type_id
    FROM DESIGN12.CLASS_DEFINITIONS
    WHERE CLASS_IMAGE IS NULL
    START WITH TYPE_ID IN (SELECT TYPE_ID FROM DESIGN12.DF_ICONS_DATA)
    CONNECT BY PRIOR DERIVED_FROM = TYPE_ID
) inheritance ON cd.TYPE_ID = inheritance.root_type_id
WHERE di.CLASS_IMAGE IS NOT NULL
ORDER BY TYPE_ID;
```

---

### 5. PROXY (User Activity)
**Purpose:** Tracks object checkout status and ownership.

**Structure:**
```sql
CREATE TABLE SCHEMA.PROXY (
    OBJECT_ID NUMBER,                    -- Object being tracked
    OWNER_ID NUMBER,                     -- User who checked out
    WORKING_VERSION_ID NUMBER,           -- Working version ID
    PROJECT_ID NUMBER,                   -- Project scope
    -- ... additional columns
)
```

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| OBJECT_ID | NUMBER | Object that is checked out |
| OWNER_ID | NUMBER | User ID (links to USER_ table) |
| WORKING_VERSION_ID | NUMBER | Non-zero if checked out |
| PROJECT_ID | NUMBER | Project scope |

**Usage in Tree Viewer:**
- Shows which objects are currently checked out
- Displays owner name next to checked-out nodes
- Cached for 1 hour (frequent updates)

**User Activity Query:**
```sql
-- Get checked-out items with user names
SELECT
    p.OBJECT_ID,
    NVL(u.CAPTION_S_, '') as owner_name,
    'CHECKEDOUT' as status
FROM DESIGN12.PROXY p
LEFT JOIN DESIGN12.USER_ u ON u.OBJECT_ID = p.OWNER_ID
WHERE p.PROJECT_ID = 18140190
  AND NVL(p.WORKING_VERSION_ID, 0) > 0
  AND NVL(p.OWNER_ID, 0) > 0
ORDER BY p.OBJECT_ID;
```

---

### 6. USER_ (User Information)
**Purpose:** Stores user account information.

**Structure:**
```sql
CREATE TABLE SCHEMA.USER_ (
    OBJECT_ID NUMBER PRIMARY KEY,        -- User ID
    CAPTION_S_ NVARCHAR2(255),          -- User display name
    NAME_ NVARCHAR2(255),                -- Username
    -- ... additional columns
)
```

**Key Columns:**
| Column | Type | Description |
|--------|------|-------------|
| OBJECT_ID | NUMBER | User identifier |
| CAPTION_S_ | NVARCHAR2 | Display name |
| NAME_ | NVARCHAR2 | Username |

**Usage in Tree Viewer:**
- Provides user names for checkout display
- Links from PROXY.OWNER_ID

---

## Relationships Between Tables

```
CLASS_DEFINITIONS (Types & Inheritance)
    ├─→ TYPE_ID (Primary Key)
    ├─→ DERIVED_FROM → CLASS_DEFINITIONS.TYPE_ID (Icon inheritance)
    │
    ↓ (1:1)
DF_ICONS_DATA (Icon Storage)
    └─→ TYPE_ID → CLASS_DEFINITIONS.TYPE_ID

COLLECTION_ (Node Data)
    ├─→ OBJECT_ID (Primary Key)
    ├─→ TYPE_ID → CLASS_DEFINITIONS.TYPE_ID (Node type)
    │
    ↓ (1:N)
REL_COMMON (Relationships)
    ├─→ OBJECT_ID → COLLECTION_.OBJECT_ID (Child)
    ├─→ FORWARD_OBJECT_ID → COLLECTION_.OBJECT_ID (Parent)
    └─→ PROJECT_ID (Scope)

PROXY (Checkout Status)
    ├─→ OBJECT_ID → COLLECTION_.OBJECT_ID
    ├─→ OWNER_ID → USER_.OBJECT_ID
    └─→ PROJECT_ID (Scope)

USER_ (User Info)
    └─→ OBJECT_ID (Primary Key)
```

---

## Important Concepts

### 1. Multi-Parent Nodes
Some nodes can appear under multiple parents:

```sql
-- Example: COWL_SILL_SIDE has 5 parents
SELECT
    r.OBJECT_ID,
    c.CAPTION_S_,
    r.FORWARD_OBJECT_ID,
    p.CAPTION_S_ as parent_name
FROM DESIGN12.REL_COMMON r
JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
JOIN DESIGN12.COLLECTION_ p ON r.FORWARD_OBJECT_ID = p.OBJECT_ID
WHERE c.CAPTION_S_ = 'COWL_SILL_SIDE'
  AND r.PROJECT_ID = 18140190;

-- Result: Same node under 5 different parents
```

**Tree Viewer Handling:**
- Creates separate tree nodes for each parent relationship
- Uses cycle detection to prevent infinite recursion
- Maintains correct context for each appearance

### 2. SEQ_NUMBER Ordering
Nodes are ordered by SEQUENCE_NO field:

```sql
-- Get children in correct order
SELECT c.CAPTION_S_
FROM DESIGN12.REL_COMMON r
JOIN DESIGN12.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
WHERE r.FORWARD_OBJECT_ID = 12345
ORDER BY r.SEQUENCE_NO NULLS LAST, c.CAPTION_S_;
```

**Ordering Rules:**
1. Primary: SEQUENCE_NO (ascending)
2. Secondary: CAPTION_S_ (alphabetical)
3. NULL values last

### 3. Icon Inheritance
Icons inherit through DERIVED_FROM chain:

```
class PmNode (TYPE_ID 14) → Base icon
  └─→ class PmStudy (TYPE_ID 176) → Inherits base icon
      └─→ class PmRobcadStudy (TYPE_ID 177) → Inherits Study icon
```

**Extraction Process:**
1. Query DF_ICONS_DATA for base icons
2. Traverse CLASS_DEFINITIONS.DERIVED_FROM chain
3. Map derived types to inherited icons
4. Result: 221 total icons from 95 base + inheritance

### 4. Project Scope
Most queries limited by PROJECT_ID:

```sql
WHERE r.PROJECT_ID = 18140190  -- FORD_DEARBORN project
```

**Why This Matters:**
- Same objects can exist in multiple projects
- Relationships are project-specific
- Tree viewer scopes all queries to selected project

---

## Performance Considerations

### Indexes
Key indexes for performance:

```sql
-- Critical for tree traversal
CREATE INDEX idx_rel_forward ON REL_COMMON(FORWARD_OBJECT_ID, PROJECT_ID);
CREATE INDEX idx_rel_object ON REL_COMMON(OBJECT_ID, PROJECT_ID);

-- Critical for joins
CREATE INDEX idx_collection_id ON COLLECTION_(OBJECT_ID);
CREATE INDEX idx_collection_type ON COLLECTION_(TYPE_ID);

-- Critical for icon lookup
CREATE INDEX idx_class_def_type ON CLASS_DEFINITIONS(TYPE_ID);
CREATE INDEX idx_icons_type ON DF_ICONS_DATA(TYPE_ID);
```

### Query Optimization
**Use CONNECT BY for hierarchy:**
```sql
-- Fast hierarchical query (uses indexes)
SELECT ...
START WITH r.FORWARD_OBJECT_ID = @ProjectId
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID;
```

**Avoid repeated queries:**
- Use caching (tree viewer implements 3-tier caching)
- Extract all data in single query when possible
- Cache icons for 7 days (rarely change)

---

## Data Types

### Common Field Types
| Type | Usage | Example |
|------|-------|---------|
| NUMBER | IDs, counters | OBJECT_ID, TYPE_ID |
| NVARCHAR2 | Unicode text | CAPTION_S_, NAME_ |
| VARCHAR2 | ASCII text | CLASS_NAME |
| BLOB | Binary data | CLASS_IMAGE (icons) |

### Important Notes
- NVARCHAR2 supports Unicode (German umlauts, etc.)
- VARCHAR2 used for technical names
- BLOBs extracted as hex strings to avoid truncation

---

## Tree Viewer SQL Queries

### Main Tree Query
See `src/powershell/main/generate-tree-html.ps1` lines 407-1073 for the complete query used by the tree viewer.

**Key features:**
- Hierarchical traversal with CONNECT BY
- Multi-parent support (NOCYCLE)
- SEQ_NUMBER ordering
- Icon type resolution
- User activity integration
- Project scoping

### Icon Extraction Query
See `src/powershell/main/generate-tree-html.ps1` lines 97-155 for the complete icon extraction query.

**Key features:**
- RAWTOHEX for BLOB extraction
- Icon inheritance via DERIVED_FROM
- Fallback icon handling
- BMP format validation

### User Activity Query
See `src/powershell/main/generate-tree-html.ps1` lines 1295-1315 for the complete user activity query.

**Key features:**
- Checkout status detection
- Owner name resolution
- Project scoping
- Online status (if available)

---

## Schema Access Requirements

### Minimum Permissions
```sql
-- Read access to these tables
GRANT SELECT ON SCHEMA.COLLECTION_ TO user;
GRANT SELECT ON SCHEMA.REL_COMMON TO user;
GRANT SELECT ON SCHEMA.CLASS_DEFINITIONS TO user;
GRANT SELECT ON SCHEMA.DF_ICONS_DATA TO user;
GRANT SELECT ON SCHEMA.PROXY TO user;
GRANT SELECT ON SCHEMA.USER_ TO user;

-- Execute access to Oracle functions
GRANT EXECUTE ON DBMS_LOB TO user;
```

### Schemas Supported
- DESIGN1 through DESIGN12
- Each schema independent
- Tree viewer can switch between schemas

---

## Troubleshooting

### Missing Nodes
**Check relationships:**
```sql
-- Verify parent-child link exists
SELECT COUNT(*)
FROM DESIGN12.REL_COMMON
WHERE OBJECT_ID = ? AND PROJECT_ID = ?;
```

### Missing Icons
**Check icon data:**
```sql
-- Verify icon exists
SELECT TYPE_ID, DBMS_LOB.GETLENGTH(CLASS_IMAGE) as size
FROM DESIGN12.DF_ICONS_DATA
WHERE TYPE_ID = ?;
```

**Check inheritance:**
```sql
-- Trace inheritance chain
SELECT TYPE_ID, DERIVED_FROM
FROM DESIGN12.CLASS_DEFINITIONS
START WITH TYPE_ID = ?
CONNECT BY PRIOR DERIVED_FROM = TYPE_ID;
```

### Performance Issues
**Check index usage:**
```sql
-- Explain plan for tree query
EXPLAIN PLAN FOR
SELECT ...
START WITH r.FORWARD_OBJECT_ID = 18140190
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID;

-- View execution plan
SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
```

---

## References

- **Tree Viewer Code**: `src/powershell/main/generate-tree-html.ps1`
- **Query Examples**: `docs/api/QUERY-EXAMPLES.md`
- **Database Investigation**: `docs/DATABASE-STRUCTURE-SUMMARY.md`
- **Icon Extraction**: `docs/investigation/ICON-EXTRACTION-SUCCESS.md`

---

**Last Updated:** 2026-01-19
**Schema Version:** Oracle 12c
**Tested With:** DESIGN12 schema, FORD_DEARBORN project (632K+ nodes)
