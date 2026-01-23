# Phase 2 Advanced Features Master Plan - Implementation Plan

## Goal Description
Create the "Phase 2 Advanced Features Master Plan" document set and optional script stubs. This establishes the roadmap, technical specifications, and risk log for the next phase of SimTreeNav, focused on adding value without destabilizing the core.

## User Review Required
> [!IMPORTANT]
> This is a docs-only + stubs change. No core logic in Phase 1/2 will be touched.

## Proposed Changes

### Documentation
#### [NEW] [PHASE2_ADVANCED_MASTER_PLAN.md](file:///c:/Users/georgem/source/repos/codex/SimTreeNav/docs/PHASE2_ADVANCED_MASTER_PLAN.md)
Executive summary, ranked feature catalog (Now/Next/Later), feature details (PM value, MVF, data dependencies, UX, failure modes), implementation playbook, acceptance gates, and handoff block.

#### [NEW] [ADVANCED_FEATURES_ROADMAP.md](file:///c:/Users/georgem/source/repos/codex/SimTreeNav/docs/ADVANCED_FEATURES_ROADMAP.md)
Three horizons: Pilot, Scale, Institutionalize. Success metrics, risks, owners.

#### [NEW] [ADVANCED_FEATURES_TECH_SPEC.md](file:///c:/Users/georgem/source/repos/codex/SimTreeNav/docs/ADVANCED_FEATURES_TECH_SPEC.md)
Architecture sketch, JSON schema evolution, contract manifest proposal, and new script definitions.

#### [NEW] [ADVANCED_FEATURES_RISK_LOG.md](file:///c:/Users/georgem/source/repos/codex/SimTreeNav/docs/ADVANCED_FEATURES_RISK_LOG.md)
Risks tied to Oracle, schema drift, permissions, data accuracy, change fatigue.

### Scripts (Stubs)
#### [NEW] [scripts/ops/dashboard-monitor.ps1](file:///c:/Users/georgem/source/repos/codex/SimTreeNav/scripts/ops/dashboard-monitor.ps1)
Stub for monitoring dashboard logs.

#### [NEW] [scripts/ops/generate-weekly-digest.ps1](file:///c:/Users/georgem/source/repos/codex/SimTreeNav/scripts/ops/generate-weekly-digest.ps1)
Stub for generating weekly HTML/ZIP digests.

#### [NEW] [scripts/ops/export-evidence-pack.ps1](file:///c:/Users/georgem/source/repos/codex/SimTreeNav/scripts/ops/export-evidence-pack.ps1)
Stub for exporting evidence packs (zip + manifest).

#### [NEW] [scripts/lib/RunManifest.ps1](file:///c:/Users/georgem/source/repos/codex/SimTreeNav/scripts/lib/RunManifest.ps1)
Helper stub to write manifest.

## Verification Plan

### Automated Tests
- **Repo Check**: `git status` to verify file creation.
- **Stub Execution**: Run each stub with `-OutDir ./out` and verify it exits with code 1 and a "Not implemented" message.
  ```powershell
  ./scripts/ops/dashboard-monitor.ps1 -OutDir ./out
  if ($LASTEXITCODE -ne 1) { Write-Error "Expected exit code 1" }
  ```

### Manual Verification
- Review generated markdown files for compliance with "Content requirements".
