# Tree Evidence Integration Proposal
**Date:** 2026-01-30
**Status:** Proposal for integrating tree snapshot data with evidence model
**Version:** 1.0

---

## Executive Summary

The tree snapshot system provides deterministic visibility into study tree structure, naming, and locations. This document proposes how tree changes should feed into the existing SimTreeNav evidence model to enable automated study health monitoring.

---

## Evidence Model Integration Strategy

### Stable Keys for Evidence

**Primary Key:** `(StudyId, NodeId)`
- StudyId = ROBCADSTUDY_.OBJECT_ID (stable)
- NodeId = SHORTCUT_.OBJECT_ID or COLLECTION_.OBJECT_ID (stable)
- This composite key is unique and stable across study modifications

**Why not use display_name as key?**
- Names can change (rename action)
- External IDs can be missing or duplicated
- Object IDs are immutable database primary keys

### Evidence Block Extensions

No changes to the core evidence triangle (hasCheckout, hasWrite, hasDelta). Instead, extend `deltaSummary` and `context` to support tree change types:

#### 1. Naming Change Evidence

```json
{
  "evidence": {
    "hasCheckout": true,
    "hasWrite": true,
    "hasDelta": true,
    "deltaSummary": {
      "kind": "naming",
      "fields": ["display_name"],
      "before": {
        "display_name": "r2000ic_210l_if_v02",
        "name_provenance": "RESOURCE_.NAME_S_"
      },
      "after": {
        "display_name": "r2000ic_210l_if_v02_renamed",
        "name_provenance": "RESOURCE_.NAME_S_"
      }
    }
  }
}
```

**Confidence:** `confirmed` if rename detected via tree diff + checkout + write
**Confidence:** `likely` if rename detected but no checkout (possible admin action)

---

#### 2. Movement Evidence (Enhanced)

Current movement evidence works but should reference tree snapshot provenance:

```json
{
  "evidence": {
    "hasCheckout": true,
    "hasWrite": true,
    "hasDelta": true,
    "deltaSummary": {
      "kind": "movement",
      "fields": ["x", "y", "z"],
      "maxAbsDelta": 1200.0,
      "before": {
        "x": 1350, "y": 0, "z": 0,
        "coord_provenance": "STUDYLAYOUT_.OBJECT_ID -> VEC_LOCATION_ (heuristic timestamp match)"
      },
      "after": {
        "x": 2550, "y": 0, "z": 0,
        "coord_provenance": "STUDYLAYOUT_.OBJECT_ID -> VEC_LOCATION_ (heuristic timestamp match)"
      },
      "delta": {
        "x": 1200, "y": 0, "z": 0
      },
      "mapping_type": "heuristic"
    }
  },
  "context": {
    "movementClassification": "WORLD",
    "nodeId": "18880389",
    "nodeName": "r2000ic_210l_if_v02",
    "nodeType": "Shortcut"
  }
}
```

**Movement Classification:**
- **Simple:** delta_mm < 1000mm
- **World:** delta_mm >= 1000mm
- Based on `maxAbsDelta`, not vector ID presence

---

#### 3. Structural Change Evidence

```json
{
  "evidence": {
    "hasCheckout": true,
    "hasWrite": true,
    "hasDelta": true,
    "deltaSummary": {
      "kind": "structure",
      "fields": ["parent_node_id"],
      "before": {
        "parent_node_id": "18879453"
      },
      "after": {
        "parent_node_id": "18881234"
      }
    }
  },
  "context": {
    "changeType": "parent_changed",
    "nodeId": "18880389",
    "nodeName": "r2000ic_210l_if_v02"
  }
}
```

---

#### 4. Resource Mapping Change Evidence

```json
{
  "evidence": {
    "hasCheckout": true,
    "hasWrite": true,
    "hasDelta": true,
    "deltaSummary": {
      "kind": "resourceMapping",
      "fields": ["resource_id", "resource_name"],
      "before": {
        "resource_id": "18880386",
        "resource_name": "r2000ic_210l_if_v02"
      },
      "after": {
        "resource_id": "18881500",
        "resource_name": "r2000ic_165f"
      }
    }
  },
  "context": {
    "shortcutId": "18880385",
    "shortcutName": "Robot1"
  }
}
```

---

#### 5. Node Add/Remove Evidence

```json
{
  "evidence": {
    "hasCheckout": true,
    "hasWrite": true,
    "hasDelta": true,
    "deltaSummary": {
      "kind": "topology",
      "fields": ["node_count"],
      "before": {
        "node_count": 4
      },
      "after": {
        "node_count": 5
      }
    }
  },
  "context": {
    "changeType": "node_added",
    "addedNodes": [
      {
        "nodeId": "18882000",
        "nodeName": "r2000ic_210l_if_v02_4",
        "nodeType": "Shortcut",
        "resourceName": "r2000ic_210l_if_v02"
      }
    ]
  }
}
```

---

## Workflow Phase Mapping

Extend the existing workflow taxonomy to support tree changes:

### Current Taxonomy
- `study.checkout`
- `study.layout` (movement)
- `study.operation`
- `study.resource`

### Proposed Extensions
- `study.naming` (rename)
- `study.structure` (parent change)
- `study.topology` (add/remove nodes)
- `study.resourceMapping` (shortcut now points to different resource)

---

## Schema Version Update

**Current:** `1.2.0`
**Proposed:** `1.3.0`

### Justification
- Adds new `deltaSummary.kind` values: `naming`, `structure`, `resourceMapping`, `topology`
- Extends `context` to include `nodeId`, `nodeName`, `nodeType`, `mapping_type`
- No breaking changes to existing evidence blocks

### Migration Path
- Existing evidence blocks remain valid (backward compatible)
- New tree-based evidence uses extended fields
- Consumers can check `schemaVersion >= 1.3.0` for tree support

---

## Implementation Approach

### Phase 1: Tree Snapshot Integration (Complete)
✅ Export study tree snapshot (deterministic)
✅ Compare snapshots to detect changes
✅ Classify mappings (deterministic vs heuristic)

### Phase 2: Evidence Generation (Proposed)

1. **Modify `get-management-data.ps1`:**
   - Add tree snapshot comparison step
   - Generate evidence blocks for tree changes
   - Map tree changes to workflow phases

2. **Update Evidence Classifier:**
   - Add support for `deltaSummary.kind = naming/structure/resourceMapping/topology`
   - Extend confidence rules for tree changes
   - Document provenance for all tree-derived evidence

3. **Dashboard Updates:**
   - Add tree change visualization (rename, structure, topology)
   - Filter by tree change types
   - Show mapping_type (deterministic vs heuristic) in evidence details

### Phase 3: Study Health Rules (Proposed)

Extend study health checks to use tree snapshot data:

**Critical Issues:**
- Ambiguous layout mappings (>1 robot at same timestamp)
- Missing node names (name_provenance = "OBJECT_ID (fallback)")
- Broken resource mappings (shortcut has no resource)

**High Issues:**
- World moves (delta_mm >= 1000mm) without manager approval
- Structural changes (parent changed unexpectedly)
- Resource mapping changes (shortcut now points to different robot)

**Medium Issues:**
- Frequent renames (indicates naming confusion)
- Heuristic coordinate mappings (timestamp-based)

---

## Data Flow Diagram

```
┌─────────────────────┐
│ Process Simulate UI │
│ (Siemens)          │
└──────────┬──────────┘
           │
           │ (Save Action)
           ▼
┌─────────────────────┐
│ Oracle DB          │
│ - SHORTCUT_        │
│ - RESOURCE_        │
│ - STUDYLAYOUT_     │
│ - VEC_LOCATION_    │
└──────────┬──────────┘
           │
           │ (Query via sqlplus)
           ▼
┌─────────────────────────────┐
│ Tree Snapshot Export        │
│ (export-study-tree-snapshot)│
│ - Deterministic structure   │
│ - Name resolution           │
│ - Coordinate lookup         │
│ - Mapping classification    │
└──────────┬──────────────────┘
           │
           │ (JSON output)
           ▼
┌────────────────────────────┐
│ Tree Snapshot Files        │
│ - Baseline snapshot        │
│ - Current snapshot         │
└──────────┬─────────────────┘
           │
           │ (Compare)
           ▼
┌─────────────────────────────┐
│ Tree Diff                   │
│ (compare-study-tree-snapshots)│
│ - Renamed nodes             │
│ - Moved nodes               │
│ - Structural changes        │
│ - Resource mapping changes  │
│ - Nodes added/removed       │
└──────────┬──────────────────┘
           │
           │ (Feed into evidence model)
           ▼
┌─────────────────────────────┐
│ Evidence Blocks             │
│ - deltaSummary extended     │
│ - context with tree data    │
│ - confidence classification │
└──────────┬──────────────────┘
           │
           │ (Dashboard + reporting)
           ▼
┌─────────────────────────────┐
│ Manager View                │
│ - Timeline of tree changes  │
│ - Movement classification   │
│ - Study health alerts       │
└─────────────────────────────┘
```

---

## Provenance and Audit Trail

All tree-derived evidence must include:

1. **name_provenance:** Source of display_name (e.g., RESOURCE_.NAME_S_)
2. **coord_provenance:** Source of coordinates (e.g., STUDYLAYOUT_.OBJECT_ID -> VEC_LOCATION_)
3. **mapping_type:** Classification of mapping confidence
   - `deterministic`: Direct foreign key relationship
   - `deterministic+heuristic_coords`: Resource link is deterministic, coordinates are heuristic
   - `heuristic`: Timestamp-based matching
   - `heuristic_ambiguous`: Multiple candidates at same timestamp
4. **snapshot_files:** References to baseline and current snapshot files used for comparison

---

## Testing and Validation

### Acceptance Criteria

✅ **Deterministic Behavior:**
- Same Siemens action → same tree diff output
- No spurious changes detected

✅ **Evidence Quality:**
- Rename generates `deltaSummary.kind = naming`
- Move generates `deltaSummary.kind = movement` with correct delta_mm
- Add/remove generates `deltaSummary.kind = topology`

✅ **Provenance:**
- All evidence includes source attribution
- Heuristic mappings clearly labeled
- Ambiguous mappings flagged

### Test Scenarios

1. **Rename Test:**
   - Export baseline
   - Rename robot in PS
   - Export current
   - Compare: expect `changes.renamed` with 1 entry

2. **Movement Test:**
   - Export baseline
   - Move robot 1200mm in X
   - Export current
   - Compare: expect `changes.moved` with delta_mm = 1200, classification = WORLD

3. **Add/Remove Test:**
   - Export baseline
   - Add new robot
   - Export current
   - Compare: expect `changes.nodesAdded` with 1 entry

4. **Ambiguity Test:**
   - Create 3 robots simultaneously
   - Export snapshot
   - Verify: mapping_type = "heuristic_ambiguous" for all 3

---

## Risk Mitigation

### Known Risks

1. **Timestamp Collision:**
   - **Risk:** Multiple robots created at same timestamp → ambiguous mapping
   - **Mitigation:** Clearly label as `heuristic_ambiguous`, provide workaround (touch one-by-one)
   - **Impact:** Low (rare in practice, clearly documented)

2. **Schema Evolution:**
   - **Risk:** Oracle schema changes break queries
   - **Mitigation:** Use consistent patterns (REL_COMMON traversal), validate query results
   - **Impact:** Medium (requires script updates if schema changes)

3. **Performance:**
   - **Risk:** Tree snapshot export slow for large studies (1000s of nodes)
   - **Mitigation:** Use hierarchical queries (CONNECT BY), limit depth if needed
   - **Impact:** Low (tested with realistic study sizes)

---

## Recommendations

### Immediate (Next Sprint)
1. ✅ Integrate tree snapshot export into management data pipeline
2. ✅ Generate evidence blocks for tree changes
3. ✅ Update dashboard to visualize tree change events

### Short-term (Next Month)
4. ⚠️ Add study health rules based on tree snapshot data
5. ⚠️ Implement automated alerting for ambiguous mappings
6. ⚠️ Create manager training materials for tree change interpretation

### Long-term (Next Quarter)
7. 📊 Historical trending of tree stability (rename frequency, movement patterns)
8. 📊 Predictive analytics (detect "churn" in naming or structure)
9. 📊 Integration with Siemens API (if available) for real-time change streaming

---

## Conclusion

The tree snapshot system provides a solid foundation for deterministic study health monitoring. By integrating tree changes into the evidence model, we enable:

- **Automated detection** of rename, move, structure, and topology changes
- **Clear provenance** for all evidence (deterministic vs heuristic)
- **Manager-friendly** visualization and reporting
- **Audit trail** for compliance and debugging

The proposed `schemaVersion 1.3.0` extends the evidence model without breaking backward compatibility, allowing gradual adoption of tree-based evidence.

---

**Prepared by:** Claude Code (Sonnet 4.5)
**Date:** 2026-01-30
**Status:** Ready for implementation
