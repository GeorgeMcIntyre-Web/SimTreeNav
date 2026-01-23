# Advanced Features Technical Specification

**Project:** SimTreeNav — Phase 2
**Date:** 2026-01-23

---

## 1. Architecture Sketch

The architecture maintains a "Hub and Spoke" extraction model but adds a new "Intelligence Layer" sidecar.

```
[Oracle Read-Only] <--- (1) Extract --- [PowerShell Extraction Core]
                                            |
                                            v
                                     [Raw JSON Artifacts]
                                            +
                                     [Manifest Generator]
                                            |
                                            v
     [Dashboard HTML] <--- (2) Render --- [Combined JSON Data]
            ^                               |
            |                               +---> (3) Monitor & Alert ---> [Ops Email/Log]
    (4) User Interaction                    |
            |                               +---> (5) Evidence Pack ---> [ZIP Archive]
     [Safe Search/Filter]
```

## 2. JSON Schema Evolution Strategy

To ensure zero breakage, we adopt a **Schema Versioning** & **Extension** strategy.

### Rules:
1.  **Additive Only:** Never remove existing keys from `dashboard-data.json`.
2.  **Schema Version Header:** All top-level JSON objects must include `"_meta": { "schemaVersion": "2.0.0" }`.
3.  **Extension Objects:** New features get their own top-level keys.

### Example Schema 2.0.0:
```json
{
  "_meta": {
    "schemaVersion": "2.0.0",
    "generatedAt": "2026-01-23T12:00:00Z"
  },
  "core_data": { ... },     // Phase 1 data (unchanged)
  "advanced_features": {    // NEW Phase 2 container
    "inventory": [
      { "server": "ORCL_A", "latency_ms": 12, "status": "OK" }
    ],
    "quality_metrics": {
      "orphan_nodes": 3,
      "null_timestamps": 0
    },
    "risk_scores": [
      { "study_id": "ST_001", "score": 85, "reason": "High Churn" }
    ]
  }
}
```

## 3. Contract Manifest Proposal

Every run must produce a `run-manifest.json` in `out/json/`. This acts as the "Bill of Materials" for the run.

**Path:** `out/json/run-manifest.json`

```json
{
  "runId": "GUID-1234-5678",
  "timestamp": "2026-01-23T12:00:00Z",
  "trigger": "Scheduled",
  "artifacts": [
    {
      "path": "out/html/dashboard.html",
      "type": "report",
      "sha256": "a1b2c3d4...",
      "schemaVersion": "N/A"
    },
    {
      "path": "out/json/data.json",
      "type": "data",
      "sha256": "e5f6g7h8...",
      "schemaVersion": "2.0.0"
    }
  ],
  "status": "SUCCESS",
  "exitCode": 0
}
```

## 4. Proposed Scripts & CLI Signatures

### Monitoring
**Script:** `scripts/ops/dashboard-monitor.ps1`
**Purpose:** Checks logs and manifest to verify run health.
**Signature:**
```powershell
dashboard-monitor.ps1 [[-OutDir] <String>] [[-LogDir] <String>] [-LookbackHours <Int>] [-AlertEmail <String>] [-Smoke]
```

### Reporting
**Script:** `scripts/ops/generate-weekly-digest.ps1`
**Purpose:** Summarizes last 7 days of run-manifests into a single HTML report.
**Signature:**
```powershell
generate-weekly-digest.ps1 [[-OutDir] <String>] [[-LogDir] <String>] [-DateRange <Int>] [-Smoke]
```

### Export
**Script:** `scripts/ops/export-evidence-pack.ps1`
**Purpose:** Zips up current state with manifest.
**Signature:**
```powershell
export-evidence-pack.ps1 [[-OutDir] <String>] [[-LogDir] <String>] [-RunId <String>] [-Smoke]
```

### Library
**Script:** `scripts/lib/RunManifest.ps1`
**Purpose:** Helper functions.
**Functions:**
- `New-RunManifest -RunId <Guid> -Trigger <String>`
- `Add-RunArtifact -ManifestPath <String> -ArtifactPath <String> -Type <String>`
- `Close-RunManifest -ManifestPath <String> -Status <String> -ExitCode <Int>`
