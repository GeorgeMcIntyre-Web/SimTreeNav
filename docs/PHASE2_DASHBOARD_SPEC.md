# Phase 2: Management Dashboard Specification

**Version:** 1.0
**Date:** 2026-01-22
**Status:** Locked for execution

## Purpose

Generate a management reporting dashboard that tracks work activity across 5 core work types in the Siemens Process Simulation database:

1. Project Database Setup
2. Resource Library
3. Part/MFG Library
4. IPA (Process Assembly)
5. Study Nodes (including operations, movements, welds)

## Scope

**IN SCOPE:**
- Read-only queries against existing DESIGN12 schema
- HTML dashboard generation (static, no server component)
- Activity tracking based on modification timestamps
- User activity attribution from PROXY/USER_ tables
- Simple movement vs. world location change detection

**OUT OF SCOPE:**
- Real-time monitoring (dashboard is snapshot-based)
- Write operations to database
- Custom database views or stored procedures
- Authentication/authorization (assumes DB credentials already configured)
- Predictive analytics or AI features

## Views and UX Requirements

### View 1: Work Type Summary

**Purpose:** High-level overview of activity across all 5 work types

**Data displayed:**
- Work Type name
- Active items (checked out via PROXY.WORKING_VERSION_ID > 0)
- Modified items count (within date range)
- Unique users count
- Change summary (e.g., "125 moves", "45 parts", "18 ops")

**UX:**
- Table format
- Sortable columns
- Click work type row to filter detailed view

### View 2: Active Studies - Detailed View

**Purpose:** Deep dive into study node activity

**Data displayed:**
- Study name
- Checked out by user
- Duration (time since checkout)
- Activity summary
- Expandable sections:
  - Resources allocated (Station, Robot, Layout, etc.)
  - Panels used (CC, RC, SC, CMN)
  - Operations created/modified (PG##, MOV_HOME, etc.)
  - Movements breakdown:
    - Simple moves (MOV_HOME, MOV_PNCE, small coordinate changes)
    - World location changes (large coordinate changes >1000mm)

**UX:**
- Expandable/collapsible tree
- Visual indicators: ⚠️ for world location changes
- Click to filter timeline view

### View 3: Movement/Location Activity

**Purpose:** Track robot/resource position changes

**Data displayed:**
- Study name
- Movement type (Simple, World Location Change, Weld Adjustment)
- Count
- User

**Movement Type Rules:**
- **Simple Move:** Operation name starts with "MOV_" OR coordinate change <1000mm in all axes
- **World Location Change:** Coordinate change ≥1000mm in any axis (X, Y, or Z)
- **Weld Adjustment:** Operation linked to weld feature (TYPE_ID 141) with coordinate change <1000mm

**UX:**
- Table format
- Color coding: Green (Simple), Orange (World), Blue (Weld)
- Click row to show coordinate details

### View 4: User Activity Breakdown

**Purpose:** Show individual user contributions

**Data displayed:**
- User selector dropdown
- Horizontal bar chart showing time distribution across work types
- Drill-down details per work type (e.g., "Operations: 45 created, 125 moves")

**UX:**
- Interactive selection
- Percentage and time duration display
- Click bar to filter timeline

### View 5: Recent Activity Timeline

**Purpose:** Chronological event stream

**Data displayed:**
- Timestamp
- User
- Work type
- Activity description

**UX:**
- Reverse chronological (newest first)
- Infinite scroll / "Load More" pagination
- Search and filter by user, work type, keyword

### View 6: Detailed Activity Log

**Purpose:** Searchable, filterable audit trail

**Data displayed:**
- Timestamp
- User
- Work type
- Detailed description
- For world location changes: Old coordinates, New coordinates, Delta

**UX:**
- Search box (filters all text)
- Dropdown filters: Work Type, User
- Export button (CSV)

## Data Contract: management.json

### High-Level Schema

```json
{
  "metadata": {
    "projectId": "18140190",
    "projectName": "FORD_DEARBORN",
    "schema": "DESIGN12",
    "startDate": "2026-01-15T00:00:00Z",
    "endDate": "2026-01-22T23:59:59Z",
    "generatedAt": "2026-01-22T15:30:00Z",
    "cacheExpiry": "2026-01-22T15:45:00Z"
  },
  "workTypes": {
    "projectDatabase": { /* See Section 1 */ },
    "resourceLibrary": { /* See Section 2 */ },
    "partMfgLibrary": { /* See Section 3 */ },
    "ipaAssembly": { /* See Section 4 */ },
    "studyNodes": { /* See Section 5 */ }
  },
  "users": [
    {
      "userId": "12345",
      "userName": "John Smith",
      "activitySummary": {
        "studyNodes": { "durationMinutes": 750, "actionsCount": 182 },
        "partMfgLibrary": { "durationMinutes": 195, "actionsCount": 15 },
        "ipaAssembly": { "durationMinutes": 140, "actionsCount": 8 },
        "resourceLibrary": { "durationMinutes": 70, "actionsCount": 5 },
        "projectDatabase": { "durationMinutes": 0, "actionsCount": 0 }
      }
    }
  ],
  "timeline": [
    {
      "timestamp": "2026-01-22T14:32:00Z",
      "userId": "12345",
      "userName": "John Smith",
      "workType": "studyNodes",
      "eventType": "worldLocationChange",
      "description": "8J-027 moved 1250mm in X-axis",
      "studyName": "DDMP P702_8J_010_8J_060",
      "details": {
        "objectId": "18195400",
        "objectName": "8J-027",
        "objectType": "PrStation",
        "oldLocation": { "x": 5000, "y": 3200, "z": 1500 },
        "newLocation": { "x": 6250, "y": 3200, "z": 1500 },
        "delta": { "x": 1250, "y": 0, "z": 0 }
      }
    }
  ]
}
```

### Section 1: projectDatabase

```json
{
  "activeCount": 0,
  "modifiedCount": 1,
  "uniqueUsers": ["admin"],
  "changeSummary": "1 mod",
  "items": [
    {
      "objectId": "18140190",
      "projectName": "FORD_DEARBORN",
      "createdBy": "admin",
      "lastModified": "2026-01-15T10:00:00Z",
      "lastModifiedBy": "admin",
      "checkedOutBy": null
    }
  ]
}
```

### Section 2: resourceLibrary

```json
{
  "activeCount": 3,
  "modifiedCount": 12,
  "uniqueUsers": ["John Smith", "Jane Doe"],
  "changeSummary": "12 res",
  "items": [
    {
      "objectId": "18195357",
      "resourceName": "8J-027",
      "resourceType": "PrStation",
      "createdBy": "admin",
      "lastModified": "2026-01-22T14:32:00Z",
      "lastModifiedBy": "John Smith",
      "checkedOutBy": "John Smith",
      "status": "Checked Out"
    }
  ]
}
```

### Section 3: partMfgLibrary

```json
{
  "activeCount": 8,
  "modifiedCount": 45,
  "uniqueUsers": ["John Smith", "Jane Doe", "Bob Lee", "Alice Wong"],
  "changeSummary": "45 parts",
  "items": [
    {
      "objectId": "18195360",
      "partName": "COWL_SILL_SIDE",
      "partType": "Part",
      "category": "Panel",
      "lastModified": "2026-01-19T13:45:00Z",
      "lastModifiedBy": "Jane Doe",
      "path": "P736/01/RC"
    }
  ],
  "panelCodeBreakdown": {
    "CC": 5,
    "RC": 6,
    "SC": 4,
    "CMN": 2
  }
}
```

### Section 4: ipaAssembly

```json
{
  "activeCount": 2,
  "modifiedCount": 6,
  "uniqueUsers": ["John Smith", "Jane Doe"],
  "changeSummary": "18 ops",
  "items": [
    {
      "objectId": "18200000",
      "processAssemblyName": "IPA_8J_010_020",
      "createdBy": "admin",
      "lastModified": "2026-01-20T11:00:00Z",
      "lastModifiedBy": "John Smith",
      "operationCount": 18
    }
  ]
}
```

### Section 5: studyNodes

```json
{
  "activeCount": 5,
  "modifiedCount": 8,
  "uniqueUsers": ["John Smith", "Jane Doe", "Bob Lee"],
  "changeSummary": "125 moves",
  "studies": [
    {
      "objectId": "18210000",
      "studyName": "DDMP P702_8J_010_8J_060",
      "studyType": "RobcadStudy",
      "createdBy": "admin",
      "lastModified": "2026-01-22T14:32:00Z",
      "lastModifiedBy": "John Smith",
      "checkedOutBy": "John Smith",
      "status": "Active",
      "checkoutDuration": "3h 25m",
      "resourcesAllocated": [
        {
          "objectId": "18195357",
          "resourceName": "8J-010",
          "resourceType": "PrStation",
          "allocationType": "Station Reference"
        },
        {
          "objectId": "18195358",
          "resourceName": "LAYOUT",
          "resourceType": "CompoundResource",
          "allocationType": "Layout Configuration"
        }
      ],
      "panelsUsed": [
        {
          "shortcutName": "8J-027_SC",
          "panelCode": "SC (Spot Coat)",
          "station": "8J-027"
        }
      ],
      "operations": [
        {
          "objectId": "18220000",
          "operationName": "PG21",
          "operationClass": "WeldOperation",
          "operationType": "Weld Point Group",
          "lastModified": "2026-01-22T14:15:00Z",
          "lastModifiedBy": "John Smith",
          "weldPointCount": 15,
          "allocatedTime": 12.5,
          "calculatedTime": 11.8
        }
      ],
      "movements": {
        "simpleMoves": 42,
        "worldLocationChanges": 3,
        "weldAdjustments": 8,
        "details": [
          {
            "timestamp": "2026-01-22T14:32:00Z",
            "movementType": "worldLocationChange",
            "objectId": "18195357",
            "objectName": "8J-027",
            "oldLocation": { "x": 5000, "y": 3200, "z": 1500 },
            "newLocation": { "x": 6250, "y": 3200, "z": 1500 }
          }
        ]
      }
    }
  ]
}
```

## Error Handling Rules

### Missing Sections

**Scenario:** Query returns zero rows for a work type

**Behavior:**
- Include section in JSON with `activeCount: 0, modifiedCount: 0, uniqueUsers: [], items: []`
- Dashboard displays work type row with "No activity" indicator
- Do NOT omit the section

**Example:**
```json
{
  "projectDatabase": {
    "activeCount": 0,
    "modifiedCount": 0,
    "uniqueUsers": [],
    "changeSummary": "No activity",
    "items": []
  }
}
```

### Missing Columns

**Scenario:** Database table lacks expected column (e.g., MODIFICATIONDATE_DA_)

**Behavior:**
- Log warning to console: `WARN: Column MODIFICATIONDATE_DA_ not found in table ROBCADSTUDY_`
- Use fallback: `createdDate` if available, else `null`
- Continue execution (do not crash)

### Database Connection Failure

**Scenario:** SQL query fails or times out

**Behavior:**
- Retry once after 5-second delay
- If second attempt fails, write error JSON:
  ```json
  {
    "error": true,
    "message": "Database connection failed",
    "timestamp": "2026-01-22T15:30:00Z"
  }
  ```
- Dashboard displays user-friendly error message: "Unable to load data. Check database connection."

### Coordinate Data Missing

**Scenario:** VEC_LOCATION_ table unavailable or empty

**Behavior:**
- Set `movements.simpleMoves: 0, movements.worldLocationChanges: 0, movements.details: []`
- Add note to dashboard: "Movement tracking unavailable (coordinate data missing)"
- Continue generating rest of dashboard

## Expected Output Artifacts

1. **management-DESIGN12-18140190.json** - Data file (output directory: `data/output/`)
2. **management-dashboard-DESIGN12-18140190.html** - Interactive HTML (output directory: `data/output/`)
3. **management-cache-DESIGN12-18140190.json** - Cache file (output directory: repo root, 15-minute lifetime)

## Non-Functional Requirements

**Performance:**
- Dashboard generation: <30 seconds (first run), <10 seconds (cached)
- HTML page load: <5 seconds in browser
- Dashboard file size: <10 MB

**Reliability:**
- No hard crashes (all errors handled gracefully)
- Degraded mode: If one query fails, others still run
- Clear error messages for troubleshooting

**Usability:**
- One-command execution (wrapper script)
- Works offline after initial generation
- No external dependencies (all JavaScript inline)

## Script Interface Contract

### Input Script: `get-management-data.ps1`

**Parameters:**
```powershell
-TNSName       # Database TNS name
-Schema        # Schema name (e.g., DESIGN12)
-ProjectId     # Project OBJECT_ID (e.g., 18140190)
-StartDate     # Optional, default: 7 days ago
-EndDate       # Optional, default: now
```

**Output:**
- File: `data/output/management-{Schema}-{ProjectId}.json`
- Exit code: 0 (success), 1 (failure)

### Generator Script: `generate-management-dashboard.ps1`

**Parameters:**
```powershell
-DataFile      # Path to JSON from get-management-data.ps1
-OutputFile    # Optional, default: management-dashboard-{Schema}-{ProjectId}.html
```

**Output:**
- File: `data/output/management-dashboard-{Schema}-{ProjectId}.html`
- Exit code: 0 (success), 1 (failure)

### Wrapper Script: `management-dashboard-launcher.ps1`

**Parameters:**
```powershell
-TNSName       # Database TNS name
-Schema        # Schema name
-ProjectId     # Project OBJECT_ID
-DaysBack      # Optional, default: 7
-AutoLaunch    # Optional switch, default: true (open in browser)
```

**Behavior:**
1. Run `get-management-data.ps1`
2. If successful, run `generate-management-dashboard.ps1`
3. If `-AutoLaunch`, open HTML in default browser
4. Display summary stats to console

**Example:**
```powershell
.\management-dashboard-launcher.ps1 `
    -TNSName "SIEMENS_PS_DB_DB01" `
    -Schema "DESIGN12" `
    -ProjectId 18140190 `
    -DaysBack 7 `
    -AutoLaunch
```

## Verification Checklist

- [ ] All 5 work type sections present in JSON (even if empty)
- [ ] User activity attribution matches PROXY/USER_ tables
- [ ] World location change threshold (1000mm) correctly applied
- [ ] Timeline events sorted newest-first
- [ ] Dashboard HTML opens without JavaScript errors
- [ ] Expandable sections toggle correctly
- [ ] Search/filter controls functional
- [ ] Export CSV produces valid comma-delimited file
- [ ] Cache files created with correct TTL (15 minutes)
- [ ] Errors logged to console, not silent failures

---

**Document Status:** LOCKED - No feature additions without user approval
**Last Updated:** 2026-01-22
**Owner:** Agent 01 (PM/Docs)
