# Siemens Process Simulation Database - Structure Summary

## Database Overview
- **Database**: Oracle 12c Enterprise Edition (12.1.0.2.0)
- **Server**: des-sim-db1
- **Instance**: db02
- **Total Size**: ~27 GB used, ~357 GB available

## Schema Structure

### Main Schemas (Process Simulation Data)
1. **DESIGN1** - 292 tables, 22.3 million rows (PRIMARY/ACTIVE)
2. **DESIGN2** - 302 tables, 24.4 million rows (PRIMARY/ACTIVE)
3. **DESIGN3** - 236 tables, 2,194 rows (MINIMAL DATA)
4. **DESIGN4** - 236 tables, 2,194 rows (MINIMAL DATA)
5. **DESIGN5** - 236 tables, 2,194 rows (MINIMAL DATA)

### Advanced Queue Schemas
- **DESIGN1_AQ** through **DESIGN5_AQ** - 10 tables each for message queuing

### Other Schemas
- **EMP_ADMIN** - Employee/Admin data

## Key Tables and Data Volumes

### Largest Tables (by row count)
1. **REL_COMMON** (DESIGN2: 8.6M rows, DESIGN1: 7.7M rows)
   - Relationship/common data table - largest in database
   
2. **PROXY** (DESIGN2: 2.8M rows, DESIGN1: 2.5M rows)
   - Proxy objects table
   
3. **PROXY_VERSIONS** (DESIGN1: 2.5M rows, DESIGN2: 2.8M rows)
   - Version tracking for proxy objects
   
4. **VEC_APCLONEDNODES1_** (DESIGN1: 1.2M rows, DESIGN2: 1.2M rows)
   - Vector/clone node data
   
5. **VEC_LOCATION1_** / **VEC_ROTATION1_** (800K+ rows each)
   - Location and rotation vector data
   
6. **EXPRESSION** (800K+ rows)
   - Expression data

### Important Application Tables

#### APPLICATION_DATA
- **Purpose**: Application-specific configuration and user data
- **Structure**:
  - USER_ID (NUMBER) - User identifier
  - APPLICATION (VARCHAR2) - Application name
  - SUB_ENTRY (VARCHAR2) - Sub-entry identifier
  - KEY (VARCHAR2) - Configuration key
  - DATA_TYPE (NUMBER) - Data type code
  - SEQ_NUMBER (NUMBER) - Sequence number
  - VALUE (CLOB) - Actual data value (CLOB for large text)
- **Row Count**: ~8,000 rows per active schema
- **Sample Data**: Contains configuration for "TnxEmpApp_TableView" and other applications

#### COLLECTION_
- **Purpose**: Main collection/object storage table
- **Structure**:
  - OBJECT_VERSION_ID (NUMBER) - Version identifier
  - OBJECT_ID (NUMBER) - Object identifier
  - CLASS_ID (NUMBER) - Class type identifier
  - EXTERNALID_S_ (VARCHAR2) - External ID (UUID format: PP-xxxxx)
  - CAPTION_S_ (VARCHAR2) - Display caption
  - NAME1_S_ (VARCHAR2) - Name field
  - STATUS_S_ (VARCHAR2) - Status (e.g., "Open")
  - CREATEDBY_S_ / LASTMODIFIEDBY_S_ (VARCHAR2) - User tracking
  - MODIFICATIONDATE_DA_ (DATE) - Last modification date
  - Plus various vector references (CHILDREN_VR_, ATTACHMENTS_VR_, etc.)
- **Row Count**: ~20,000 rows in DESIGN1, ~21,000 in DESIGN2
- **Sample Data**: Contains part information like "LI SCHOTTBLECH BUCHSE", "ZB LI PLATTE STOSSFAENGER", etc.

#### PART_ / PART_EX
- **Purpose**: Part data tables
- **Row Count**: ~29,000 rows in DESIGN1, ~28,000 in DESIGN2
- **Pattern**: Many tables have an "_EX" extension (likely extension/extra data tables)

#### Other Notable Tables
- **BMW_PART_** - BMW-specific part data (~8,800 rows)
- **PARTPROTOTYPE_** - Part prototype definitions (~284 rows in DESIGN1)
- **PARTINSTANCEASPECT_** - Part instance aspects (~25,000 rows)
- **ASSEMBLY_** - Assembly data (mostly empty)
- **CLASS_DEFINITIONS** - Class/metadata definitions (~527 rows)

## Database Relationships

### Foreign Key Relationships (DESIGN1)
1. **MEMBER_ARGS** → **MEMBER_DEFINITIONS** → **CLASS_DEFINITIONS**
2. **PROXY** → **CLASS_DEFINITIONS**
3. **PROXY_FROZEN_KEYS** → **PROXY** and **VERSIONS**
4. **PROXY_VERSIONS** → **PROXY**
5. **REL_COMMON** → **PROXY** (forward object relationships)
6. **SECONDARY_EXTERNAL_ID** → **PROXY**

## Table Naming Patterns

1. **Base Tables**: Main data tables (e.g., `COLLECTION_`, `PART_`, `PROXY`)
2. **_EX Tables**: Extension tables with additional data (e.g., `COLLECTION_EX`, `PART_EX`)
3. **VEC_ Tables**: Vector/mathematical data (locations, rotations, etc.)
4. **TCM_ Tables**: TCM (likely Teamcenter Manufacturing) integration tables
5. **BMW_ Tables**: BMW-specific customizations
6. **TEMP_ Tables**: Temporary/work tables

## Tablespaces

- **PP_DATA_128K** - Small data (128KB block size)
- **PP_DATA_1M** - Medium data (1MB block size) 
- **PP_DATA_10M** - Large data (10MB block size) - used for large tables
- **PP_INDEX_128K, PP_INDEX_1M, PP_INDEX_10M** - Corresponding index tablespaces
- **AQ_DATA** - Advanced Queue data
- **PERFSTAT_DATA** - Performance statistics

## Key Insights

1. **DESIGN1 and DESIGN2 are the active schemas** with substantial data (20M+ rows each)
2. **DESIGN3-5 are mostly empty** (only 2,194 rows each) - likely templates or inactive projects
3. **REL_COMMON is the largest table** - stores relationship/common data (8M+ rows)
4. **PROXY tables are central** - many foreign keys reference PROXY table
5. **Versioning is important** - PROXY_VERSIONS and VERSIONS tables track object versions
6. **External IDs use UUID format** - Pattern: PP-{uuid} (e.g., PP-aa30f61e-90f7-414c-9a47-d1796e431618)
7. **BMW-specific customizations** exist (BMW_PART_, BMW_STANDARDPART_, etc.)
8. **Application data is stored in CLOB** - VALUE column in APPLICATION_DATA uses CLOB for large text

## Data Patterns

- Most tables have corresponding "_EX" tables for extended attributes
- Vector data (locations, rotations) stored separately in VEC_* tables
- Class-based structure (CLASS_DEFINITIONS drives object types)
- Version tracking is built into the schema (VERSIONS, PROXY_VERSIONS)
- User tracking on most objects (CREATEDBY, LASTMODIFIEDBY, MODIFICATIONDATE)

## Recommended Queries for Further Exploration

```sql
-- Find all tables with data in DESIGN1
SELECT table_name, num_rows FROM dba_tables 
WHERE owner='DESIGN1' AND num_rows > 0 
ORDER BY num_rows DESC;

-- Find relationships for a specific object
SELECT * FROM DESIGN1.REL_COMMON 
WHERE forward_object_id = <object_id>;

-- Find all parts in a collection
SELECT * FROM DESIGN1.PART_ 
WHERE <join conditions>;

-- Find application configuration
SELECT * FROM DESIGN1.APPLICATION_DATA 
WHERE application = 'TnxEmpApp_TableView';
```
