# IT Handoff Message: SimTreeNav Production Deployment

**To**: IT Operations / DBA
**From**: Development Team
**Date**: 2026-01-23
**Subject**: SimTreeNav Production Release Bundle (Option B)

Please proceed with the deployment of the SimTreeNav application to the production server. This bundle contains all necessary artifacts, scripts, and documentation.

## 1. Artifact Package
- **File**: `SimTreeNav_bundle.zip`
- **SHA256 Hash**: `90DBD920760D715367CE3A46DF3476911291840E1587DB3B0BE10C293F35F1C6`
  *(Please verify hash before extraction)*

## 2. Deployment Instructions
Refer to `docs/GO_LIVE_COMMANDS.md` inside the bundle for step-by-step commands.

**High-Level Summary**:
1.  **Extract** to `D:\SimTreeNav`.
2.  **Configure** `config/production.json` (Rename template, add real values).
3.  **Validate** environment: `pwsh ./scripts/ops/validate-environment.ps1 -Smoke`.
4.  **Generate** Tasks: `pwsh ./scripts/ops/install-scheduled-tasks.ps1`.

## 3. "Go-Live" Activation
**Do NOT apply scheduled tasks immediately.**
Run the validation and generation steps first. Once "Go-Live" is approved:
- Run the apply command: `pwsh ... -Apply`.

## 4. Evidence Return
Please return the raw output of the validation command and a screenshot of the created task scheduler entries.
