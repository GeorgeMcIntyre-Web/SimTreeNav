# ADR-0001: Deployment Model

**Status**: Accepted  
**Date**: 2026-01-16  
**Decision Makers**: SimTreeNav Core Team  
**Categories**: Architecture, Deployment, Security

## Context

SimTreeNav needs a deployment strategy that supports:
- Offline usage (air-gapped environments)
- Easy deployment to static hosting
- Optional secure access controls
- No vendor lock-in
- Deterministic outputs

The tool extracts data from Siemens Process Simulation databases and produces viewable bundles. These bundles may contain sensitive engineering data.

## Decision

**We adopt a static-first, bundle-based distribution model as the default.**

### Core Principles

1. **Static-first**: The viewer and all data are self-contained in a bundle that requires no server-side processing.

2. **Bundle-based**: Each extraction produces a complete, portable bundle that can be:
   - Opened locally via file:// protocol
   - Deployed to any static hosting provider
   - Archived for historical reference

3. **Random URL is NOT privacy**: Security must be explicitly configured; obscurity is not a security measure.

4. **Optional API is additive**: Server-side features (search, indexing, alerts) enhance but do not replace the static bundle.

## Considered Alternatives

### Alternative 1: API-First Architecture

All data stored server-side, viewer fetches from API.

**Pros:**
- Smaller client bundle
- Real-time updates
- Centralized access control

**Cons:**
- Requires server infrastructure
- Breaks offline usage
- Higher operational complexity
- Vendor lock-in risk

**Decision**: Rejected for v0.6-v0.8. May revisit for v1.0 as optional mode.

### Alternative 2: Desktop Application

Package as Electron or native app.

**Pros:**
- Rich native capabilities
- Built-in file system access
- No deployment needed

**Cons:**
- Distribution challenges (signing, updates)
- Platform-specific builds
- Higher development cost
- Doesn't enable team sharing

**Decision**: Rejected. Web viewer meets requirements with less complexity.

### Alternative 3: Self-Hosted Server

Node.js/Python server hosting both data and viewer.

**Pros:**
- Single deployment unit
- Built-in auth middleware
- Database connectivity options

**Cons:**
- Operational overhead
- Requires server maintenance
- Security responsibility shifts to operator
- Not suitable for air-gapped demo

**Decision**: Rejected for default mode. May offer as enterprise option.

## Consequences

### Positive

- **Zero infrastructure**: Users can deploy to free static hosting
- **Portability**: Bundles work anywhere (USB, intranet, cloud)
- **Determinism**: Same input → identical output (excluding timestamps)
- **Simplicity**: No runtime dependencies beyond a web browser
- **Archival**: Bundles serve as historical snapshots

### Negative

- **No real-time sync**: Changes require re-extraction
- **Large bundles**: All data included, even if not viewed
- **Auth requires hosting features**: Can't add login without platform support

### Mitigations

- Incremental sync planned for v0.8
- Chunked loading planned for v0.8
- Auth patterns documented (Cloudflare Access, etc.)

## Implementation

### Bundle Structure (v0.6)

```
bundle/
├── index.html          # Self-contained viewer
├── manifest.json       # Metadata, basePath, file list
├── assets/             # JS/CSS (no external deps)
└── data/               # JSON data files
```

### Deployment Flow

```powershell
# Extract from database
.\ExtractBundle.ps1 -Project "MyProject" -OutDir ./output/bundle

# Package for deployment
.\DeployPack.ps1 -BundlePath ./output/bundle -OutDir ./deploy/site -SiteName myproject

# Verify
.\VerifyDeploy.ps1 -SiteDir ./deploy/site

# Deploy (user's choice of platform)
# wrangler pages deploy ./deploy/site
# or git push to gh-pages
```

### Security Patterns

| Pattern | Platform | Complexity | Cost |
|---------|----------|------------|------|
| Cloudflare Access | Cloudflare | Low | Free-50 users |
| GitHub Private Repo | GitHub | Low | Paid |
| Basic Auth Worker | Cloudflare | Medium | Free |
| IP Allowlist WAF | Cloudflare | Low | Pro plan |

## Future Considerations

### v0.9: Optional API Layer

When adding API features:
- API is enhancement, not requirement
- Viewer falls back to local data if API unavailable
- API follows same security model (platform-provided auth)

### v1.0: Enterprise Options

May offer:
- SaaS mode with managed infrastructure
- On-prem mode with self-hosted API
- Hybrid with collector agents

## References

- [DEPLOYMENT.md](DEPLOYMENT.md) — Deployment instructions
- [CLOUD-BLUEPRINT.md](CLOUD-BLUEPRINT.md) — Cloud architecture design
- [ROADMAP.md](ROADMAP.md) — Version roadmap
