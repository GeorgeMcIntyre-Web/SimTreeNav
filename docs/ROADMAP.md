# SimTreeNav Roadmap

This document outlines the development roadmap for SimTreeNav, from the current release through enterprise-ready features.

## Version History

| Version | Status | Theme |
|---------|--------|-------|
| v0.5 | Released | Core extraction and viewer |
| v0.6 | Current | Deployable Product Surface |
| v0.7 | Planned | Analysis Engines |
| v0.8 | Planned | Performance at Scale |
| v0.9 | Planned | Optional API Layer |
| v1.0 | Vision | Enterprise Ready |

---

## v0.6 — Deployable Product Surface ✅ Current

**Theme**: Make SimTreeNav trivially deployable with a professional UX.

### Deliverables

- [x] **DeployPack.ps1** — One-command deployment package creation
- [x] **VerifyDeploy.ps1** — Validation for CI/CD integration
- [x] **DemoStory.ps1** — Synthetic data generation for testing
- [x] **basePath Support** — Deploy to any URL path
- [x] **3-Pane Pro Layout** — Tree, Timeline/Activity, Inspector
- [x] **Virtualized Tree Rendering** — Handle 10,000+ nodes
- [x] **Timeline Selector** — Navigate between snapshots
- [x] **Changed-Only Mode** — Focus on differences
- [x] **Cross-Highlighting** — Click action → highlight node
- [x] **Inspector Panels** — Identity, Drift, Impact, Links
- [x] **Keyboard Shortcuts** — Professional UX
- [x] **Offline-First** — No external network dependencies

### Acceptance Criteria

```powershell
# This workflow must succeed
.\DemoStory.ps1 -NodeCount 500 -OutDir ./output/demo_v06 -NoOpen
.\DeployPack.ps1 -BundlePath ./output/demo_v06 -OutDir ./deploy/site -SiteName simtreenav-demo
.\VerifyDeploy.ps1 -SiteDir ./deploy/site
# deploy/site can be uploaded to any static host
```

---

## v0.7 — Analysis Engines

**Theme**: Integrate compliance, similarity, and anomaly detection.

### Planned Deliverables

- [ ] **Compliance Engine**
  - Define compliance rules in JSON/YAML
  - Evaluate tree against rules
  - Generate compliance report in bundle
  - Display violations in viewer

- [ ] **Similarity Engine**
  - Compare nodes across projects/snapshots
  - Fingerprint-based matching
  - Visualize similar subtrees

- [ ] **Anomaly Detection**
  - Statistical analysis of node properties
  - Flag outliers and unexpected patterns
  - Severity scoring

- [ ] **Alerts Page**
  - New tab in viewer: "Alerts"
  - Filter by type, severity, status
  - Acknowledge/resolve workflow (local state)

### Acceptance Criteria

- Compliance rules can be defined without code changes
- Anomalies are surfaced with explanations
- Viewer shows alert counts in header

---

## v0.8 — Performance at Scale

**Theme**: Handle massive datasets with paging and streaming.

### Planned Deliverables

- [ ] **Paged Node Loading**
  - Split large trees into chunks
  - Load on-demand as user navigates
  - Chunk manifest in JSON

- [ ] **Streaming Writers**
  - PowerShell extraction writes chunks directly
  - Avoid loading entire tree in memory
  - Support 100,000+ node trees

- [ ] **Incremental Sync**
  - Detect changes since last extraction
  - Write only delta files
  - Merge deltas on load

- [ ] **Virtual Scroll Optimization**
  - GPU-accelerated rendering
  - Canvas fallback for extreme scale
  - Target: 60fps with 50,000 visible nodes

- [ ] **Bundle Compression**
  - gzip/brotli support in DeployPack
  - Automatic decompression in loader

### Acceptance Criteria

- 100,000 node tree loads in < 5 seconds
- Memory usage under 500MB for large trees
- Extraction completes in linear time

---

## v0.9 — Optional API Layer

**Theme**: Add server-side capabilities for search and indexing.

### Planned Deliverables

- [ ] **Cloudflare Workers API**
  - `/api/search` — Full-text search across nodes
  - `/api/index` — Query indexed properties
  - `/api/alerts` — Retrieve/update alert status

- [ ] **R2 Storage Integration**
  - Store bundles in Cloudflare R2
  - Generate signed URLs for access
  - Lifecycle policies for retention

- [ ] **D1 Database**
  - SQLite-based indexing
  - Fast property lookups
  - Alert state persistence

- [ ] **API Authentication**
  - JWT tokens via Cloudflare Access
  - API key support for automation
  - Rate limiting

### Acceptance Criteria

- Viewer works without API (fallback to local data)
- Search returns results in < 200ms
- API is optional, not required

---

## v1.0 — Enterprise Ready

**Theme**: Production-grade for enterprise deployment.

### Planned Deliverables

- [ ] **SaaS Ingestion**
  - Secure endpoint for bundle upload
  - Multi-tenant organization support
  - Audit logging

- [ ] **On-Prem Collector Agent**
  - Lightweight Windows service
  - Scheduled extractions
  - Anonymization/filtering options
  - Secure push to cloud storage

- [ ] **Multi-Project Dashboard**
  - Overview of all projects
  - Trend visualization
  - Cross-project comparisons

- [ ] **User Management**
  - Role-based access control
  - Project-level permissions
  - SSO integration (SAML/OIDC)

- [ ] **Retention Policies**
  - Configurable snapshot retention
  - Automatic cleanup
  - Archive to cold storage

- [ ] **Enterprise Compliance**
  - SOC 2 considerations
  - Data residency options
  - Encryption at rest

### Acceptance Criteria

- Collector agent runs unattended
- 99.9% uptime SLA capable
- Enterprise SSO integration works

---

## Backlog (Unscheduled)

These features are considered but not scheduled:

### UX Enhancements
- [ ] Dark/light theme toggle
- [ ] Customizable column layouts
- [ ] Saved filter presets
- [ ] Export to Excel/PDF
- [ ] Print-friendly views

### Integration
- [ ] Webhook notifications
- [ ] Slack/Teams alerts
- [ ] Email digest reports
- [ ] Jira integration
- [ ] REST API for external tools

### Analysis
- [ ] Machine learning anomaly detection
- [ ] Predictive drift analysis
- [ ] Natural language queries
- [ ] Graph-based impact analysis

### Platform
- [ ] Linux/macOS support for scripts
- [ ] Docker container deployment
- [ ] Kubernetes Helm chart
- [ ] Terraform infrastructure

---

## Contributing

We welcome contributions! Priority areas:

1. **Testing** — Add Pester tests for scripts
2. **Documentation** — Improve guides and examples
3. **Performance** — Optimize for large datasets
4. **Accessibility** — WCAG compliance for viewer

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## Version Policy

- **Major versions** (1.0, 2.0): Breaking changes, major features
- **Minor versions** (0.6, 0.7): New features, backwards compatible
- **Patch versions** (0.6.1, 0.6.2): Bug fixes, minor improvements

We follow [Semantic Versioning](https://semver.org/).
