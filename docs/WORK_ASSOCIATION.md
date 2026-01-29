# Work Association & Evidence

**Last Updated:** 2026-01-29

## Purpose

This document defines how SimTreeNav associates database changes with real simulator work and how evidence is captured per event.

## Non-Negotiable Rule

**Run status artifacts (run-status.json) are operational audit logs only.**  
They do **not** prove simulator engineering work and must never be used as evidence.

## Workflow WorkType Taxonomy (v1.2)

All emitted events use a workflow-aligned taxonomy:

- `libraries.partLibrary`
- `libraries.mfgLibrary`
- `libraries.partInstanceLibrary`
- `process.ipa`
- `resources.resourceLibrary`
- `study.layout`
- `study.robotMount`
- `study.toolMount`
- `study.accessCheck`
- `study.operationAllocation`
- `designLoop.gunCloud`

## Evidence Triangle

Each emitted event includes an `evidence` block that summarizes three independent signals:

- **Checkout:** The object is actively checked out (PROXY.WORKING_VERSION_ID > 0).
- **Write:** The object changed (MODIFICATIONDATE_DA_ changed or snapshot hash changed).
- **Delta:** Meaningful content changed (coordinates, operation counts, or relationships).

## Confidence Classification

Confidence is derived from the evidence triangle:

- **confirmed**: hasCheckout + hasWrite + hasDelta **and** attribution not weak
- **likely**: hasWrite + hasDelta with partial evidence (missing checkout or weak attribution)
- **checkout_only**: hasCheckout but no write or delta
- **unattributed**: write or delta without strong attribution

Attribution strength is computed from PROXY owner vs LASTMODIFIEDBY:

- **strong**: both present and match
- **medium**: both present but differ, or only one present
- **weak**: no attribution present

## Evidence Block Fields

```json
{
  "hasCheckout": true,
  "hasWrite": true,
  "hasDelta": true,
  "proxyOwnerId": "12345",
  "proxyOwnerName": "John Smith",
  "lastModifiedBy": "John Smith",
  "checkoutWorkingVersionId": 3,
  "writeSources": ["STUDYLAYOUT_.MODIFICATIONDATE_DA_"],
  "joinSources": ["REL_COMMON.OBJECT_ID", "OPERATION_.OBJECT_ID"],
  "deltaSummary": {
    "kind": "movement",
    "fields": ["x", "y", "z"],
    "maxAbsDelta": 1250,
    "before": { "x": 5000, "y": 3200, "z": 1500 },
    "after": { "x": 6250, "y": 3200, "z": 1500 }
  },
  "attributionStrength": "strong",
  "confidence": "confirmed"
}
```

**writeSources vs joinSources**
- `writeSources`: ONLY write-indicator columns (modification dates / last-modified fields). Shown as **Write proof** in the dashboard.
- `joinSources`: informational join keys used for relationships; does not affect evidence. Shown as **Relationships checked** in the dashboard.

## Event Context (Optional)

Events can include a lightweight `context` object for PM-friendly interpretation:

```json
{
  "context": {
    "station": "8J-010",
    "objectType": "weldOp"
  }
}
```

## Before / After Example (Short)

**Before (legacy event, no evidence):**
```json
{
  "timestamp": "2026-01-22T14:32:00Z",
  "user": "John Smith",
  "workType": "Study Movements",
  "description": "Study layout update (location vector 45102)"
}
```

**After (evidence-backed event):**
```json
{
  "timestamp": "2026-01-22T14:32:00Z",
  "user": "John Smith",
  "workType": "study.layout",
  "description": "Layout moved (dx=1250, dy=0, dz=0)",
  "context": { "objectType": "station" },
  "evidence": {
    "hasCheckout": true,
    "hasWrite": true,
    "hasDelta": true,
    "attributionStrength": "strong",
    "confidence": "confirmed"
  }
}
```

## PM Interpretation Guide (By Workflow Phase)

- **libraries.\***  
  Confirmed means a library item was added/changed with a real delta. Likely indicates a library change without checkout evidence.
- **process.ipa**  
  Confirmed indicates meaningful assembly changes; unattributed indicates changes without reliable user attribution.  
  When present, `context.allocationState` shows whether allocations are volatile, settling, or stable across recent snapshots.
- **resources.resourceLibrary**  
  Confirmed indicates device/station edits with delta; checkout_only highlights items locked but unchanged.
- **study.\***  
  Confirmed indicates layout/operation changes with verified deltas. Likely indicates edits without checkout evidence.
- **designLoop.gunCloud**  
  Confirmed indicates weld-related deltas; unattributed indicates weld updates without attribution.

## Snapshot + Diff Model

Each run writes a snapshot artifact:

```
data/output/management-snapshot-{Schema}-{ProjectId}.json
```

Snapshots store a minimal state vector per tracked object:

- objectId, objectType
- modificationDate, lastModifiedBy
- coordinates (x, y, z) where applicable
- operationCounts where available
- recordHash (stable hash of selected fields)

Diff logic uses the prior snapshot (if present) to compute:

- **hasWrite**: modificationDate or recordHash changed
- **hasDelta**: coordinates or counts changed beyond thresholds

On the first run (no prior snapshot), `hasWrite` falls back to modification timestamps and `hasDelta` remains false.

## Dashboard UX

The dashboard surfaces evidence in a compact, expandable panel:

- Confidence badge (confirmed / likely / checkout_only / unattributed)
- Evidence details section for each event
- Filters by confidence in Timeline and Activity Log
- Allocation State filter (Timeline + Activity Log) for `context.allocationState` when present
