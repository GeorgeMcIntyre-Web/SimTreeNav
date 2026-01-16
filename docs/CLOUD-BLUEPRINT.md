# SimTreeNav Cloud Architecture Blueprint

This document describes the optional cloud architecture for SimTreeNav, designed for team collaboration and enterprise features.

> **Note**: This is a design document. The cloud architecture is optional and not required for core functionality. See [ADR-0001](ADR-0001-Deployment-Model.md) for the default static deployment model.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLOUDFLARE EDGE                                 │
│                                                                             │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                   │
│  │ Cloudflare  │     │ Cloudflare  │     │ Cloudflare  │                   │
│  │   Access    │────▶│   Pages     │────▶│     R2      │                   │
│  │  (Auth)     │     │  (Viewer)   │     │  (Storage)  │                   │
│  └─────────────┘     └─────────────┘     └─────────────┘                   │
│         │                   │                   │                           │
│         │            ┌──────┴──────┐           │                           │
│         │            │             │           │                           │
│         ▼            ▼             ▼           ▼                           │
│  ┌─────────────┐  ┌─────────┐  ┌─────────┐  ┌─────────────┐               │
│  │ Cloudflare  │  │ Workers │  │ Workers │  │  D1 / KV    │               │
│  │  Tunnels    │  │  (API)  │  │ (Search)│  │  (Index)    │               │
│  └─────────────┘  └─────────┘  └─────────┘  └─────────────┘               │
│         ▲                                                                   │
└─────────┼───────────────────────────────────────────────────────────────────┘
          │
          │ (Optional: Secure tunnel for on-prem data push)
          │
┌─────────┼───────────────────────────────────────────────────────────────────┐
│         │                       ON-PREMISES                                  │
│         ▼                                                                   │
│  ┌─────────────┐     ┌─────────────┐     ┌─────────────┐                   │
│  │  Collector  │────▶│   Process   │────▶│   Siemens   │                   │
│  │   Agent     │     │   Sim DB    │     │   Server    │                   │
│  └─────────────┘     └─────────────┘     └─────────────┘                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Cloudflare Pages (Static Hosting)

**Purpose**: Host the SimTreeNav viewer application.

**Configuration**:
```toml
# wrangler.toml
name = "simtreenav"
compatibility_date = "2024-01-01"

[site]
bucket = "./deploy/site"
```

**Features**:
- Global CDN distribution
- Automatic HTTPS
- Preview deployments for PRs
- Rollback capability

**Cost**: Free (unlimited sites, 500 builds/month)

---

### 2. Cloudflare Access (Authentication)

**Purpose**: Zero-trust access control for viewer and API.

**Configuration**:
```yaml
# Example Access policy
application:
  name: SimTreeNav
  domain: simtreenav.example.com
  policies:
    - name: Allow Company
      decision: allow
      include:
        - email_domain: "@example.com"
    - name: Allow Partners
      decision: allow
      include:
        - email:
            - "partner1@external.com"
            - "partner2@external.com"
```

**Authentication Options**:
- Email OTP (one-time PIN)
- SSO (Okta, Azure AD, Google Workspace)
- GitHub/GitLab (for open-source teams)
- Service tokens (for API automation)

**Cost**: Free (up to 50 users), $3/user/month (Teams)

---

### 3. Cloudflare R2 (Object Storage)

**Purpose**: Store bundle data files for large datasets.

**Structure**:
```
simtreenav-bundles/
├── org-123/
│   ├── project-abc/
│   │   ├── latest/
│   │   │   ├── nodes.json
│   │   │   ├── timeline.json
│   │   │   └── manifest.json
│   │   ├── snapshots/
│   │   │   ├── 2024-01-15T10:30:00Z/
│   │   │   └── 2024-01-14T09:00:00Z/
│   │   └── metadata.json
│   └── project-def/
│       └── ...
└── org-456/
    └── ...
```

**Features**:
- S3-compatible API
- No egress fees
- Lifecycle policies
- Object versioning

**Cost**: 
- Storage: $0.015/GB/month
- Operations: $4.50/million Class A, $0.36/million Class B

---

### 4. Cloudflare Workers (API)

**Purpose**: Serverless API for search, indexing, and data operations.

**Endpoints**:

```typescript
// routes.ts
export default {
  '/api/search': searchHandler,
  '/api/bundles': bundlesHandler,
  '/api/alerts': alertsHandler,
  '/api/upload': uploadHandler,
};
```

**Search API**:
```typescript
// search.ts
interface SearchRequest {
  query: string;
  filters?: {
    nodeType?: string;
    project?: string;
    dateRange?: [string, string];
  };
  limit?: number;
}

interface SearchResponse {
  results: SearchResult[];
  total: number;
  took: number;
}

async function searchHandler(request: Request): Promise<Response> {
  const { query, filters, limit = 50 } = await request.json<SearchRequest>();
  
  // Query D1 database for indexed nodes
  const results = await searchNodes(query, filters, limit);
  
  return Response.json({
    results,
    total: results.length,
    took: Date.now() - startTime,
  });
}
```

**Upload API** (for collector agent):
```typescript
// upload.ts
async function uploadHandler(request: Request): Promise<Response> {
  // Verify service token
  const token = request.headers.get('Authorization');
  if (!validateServiceToken(token)) {
    return new Response('Unauthorized', { status: 401 });
  }
  
  // Parse multipart form data
  const formData = await request.formData();
  const bundle = formData.get('bundle');
  const metadata = JSON.parse(formData.get('metadata'));
  
  // Store in R2
  const key = `${metadata.org}/${metadata.project}/${timestamp}`;
  await R2.put(key, bundle, {
    customMetadata: metadata,
  });
  
  // Index in D1
  await indexBundle(key, metadata);
  
  return Response.json({ success: true, key });
}
```

**Cost**: Free (100K requests/day), $0.15/million requests thereafter

---

### 5. Cloudflare D1 (Database)

**Purpose**: SQLite-based database for indexing and metadata.

**Schema**:
```sql
-- Organizations
CREATE TABLE organizations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Projects
CREATE TABLE projects (
  id TEXT PRIMARY KEY,
  org_id TEXT REFERENCES organizations(id),
  name TEXT NOT NULL,
  latest_bundle_key TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Bundles
CREATE TABLE bundles (
  id TEXT PRIMARY KEY,
  project_id TEXT REFERENCES projects(id),
  r2_key TEXT NOT NULL,
  node_count INTEGER,
  snapshot_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Node Index (for search)
CREATE TABLE node_index (
  id TEXT PRIMARY KEY,
  bundle_id TEXT REFERENCES bundles(id),
  node_id TEXT NOT NULL,
  name TEXT NOT NULL,
  node_type TEXT,
  path TEXT,
  -- Full-text search
  CONSTRAINT fts_name FOREIGN KEY (name) REFERENCES node_fts(name)
);

-- Full-text search virtual table
CREATE VIRTUAL TABLE node_fts USING fts5(
  name,
  path,
  content='node_index',
  content_rowid='id'
);

-- Alerts
CREATE TABLE alerts (
  id TEXT PRIMARY KEY,
  bundle_id TEXT REFERENCES bundles(id),
  node_id TEXT,
  type TEXT NOT NULL,
  severity TEXT NOT NULL,
  message TEXT,
  acknowledged_at TIMESTAMP,
  resolved_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

**Cost**: Free (5GB storage, 5M reads/day, 100K writes/day)

---

### 6. Cloudflare Tunnels (On-Prem Connectivity)

**Purpose**: Secure connection from on-premises collector to cloud.

**Architecture**:
```
On-Prem Network          Cloudflare Edge            Workers
┌─────────────┐         ┌─────────────┐         ┌─────────────┐
│  Collector  │◀───────▶│   Tunnel    │◀───────▶│  Upload     │
│   Agent     │ Outbound│  Connector  │ Secure  │  Handler    │
│             │   Only  │             │  Tunnel │             │
└─────────────┘         └─────────────┘         └─────────────┘
```

**Benefits**:
- No inbound firewall rules needed
- mTLS authentication
- Traffic encryption
- IP hiding

**Setup**:
```bash
# Install cloudflared on collector server
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o cloudflared
chmod +x cloudflared

# Authenticate
./cloudflared tunnel login

# Create tunnel
./cloudflared tunnel create simtreenav-collector

# Configure tunnel
cat > config.yml << EOF
tunnel: <tunnel-id>
credentials-file: ~/.cloudflared/<tunnel-id>.json
ingress:
  - hostname: collector.simtreenav.example.com
    service: http://localhost:8080
  - service: http_status:404
EOF

# Run tunnel
./cloudflared tunnel run simtreenav-collector
```

**Cost**: Free (included with Access)

---

### 7. Collector Agent (On-Premises)

**Purpose**: Automated extraction and secure upload to cloud.

**Architecture**:
```powershell
# collector-agent.ps1
# Runs as Windows Service or Scheduled Task

param(
    [string]$ConfigPath = ".\collector-config.json"
)

$config = Get-Content $ConfigPath | ConvertFrom-Json

# Main extraction loop
while ($true) {
    foreach ($project in $config.projects) {
        # Extract bundle
        $bundle = Invoke-Extraction -Project $project
        
        # Anonymize if configured
        if ($config.anonymize) {
            $bundle = Invoke-Anonymization -Bundle $bundle
        }
        
        # Upload to cloud
        Invoke-Upload -Bundle $bundle -Endpoint $config.uploadEndpoint
        
        # Clean up local files
        Remove-LocalBundle -Bundle $bundle
    }
    
    # Wait for next cycle
    Start-Sleep -Seconds $config.intervalSeconds
}
```

**Configuration**:
```json
{
  "projects": [
    {
      "name": "Project A",
      "tnsName": "PROD_DB",
      "schema": "DESIGN12",
      "projectId": "18140190"
    }
  ],
  "uploadEndpoint": "https://collector.simtreenav.example.com/api/upload",
  "serviceToken": "env:SIMTREENAV_TOKEN",
  "intervalSeconds": 3600,
  "anonymize": true,
  "anonymizeRules": {
    "stripEmails": true,
    "hashUsernames": true,
    "removeComments": false
  }
}
```

---

## Security Considerations

### Data Classification

| Data Type | Sensitivity | Handling |
|-----------|-------------|----------|
| Node structure | Medium | May contain proprietary hierarchy |
| Node names | Low-High | Depends on naming conventions |
| User activity | High | Contains usernames, should anonymize |
| Timestamps | Low | Generally non-sensitive |
| External IDs | Medium | May link to other systems |

### Anonymization Options

1. **Username hashing**: Replace usernames with consistent hashes
2. **Email stripping**: Remove all email addresses
3. **ID obfuscation**: Replace internal IDs with random but consistent values
4. **Comment removal**: Strip user-added comments
5. **Path truncation**: Remove deep path segments

### Network Security

- All traffic over HTTPS/TLS 1.3
- Cloudflare WAF for API protection
- Rate limiting on all endpoints
- Service tokens with rotation policy
- Audit logging for all operations

---

## Cost Estimation

### Free Tier Coverage

| Component | Free Limit | Typical Usage |
|-----------|------------|---------------|
| Pages | Unlimited | ✅ Covered |
| Workers | 100K/day | ✅ Covered for small teams |
| R2 | 10GB | ✅ ~100 bundles |
| D1 | 5GB | ✅ ~50 projects indexed |
| Access | 50 users | ✅ Small-medium teams |

### Paid Tier (Growth)

For larger deployments:

| Component | Cost | Notes |
|-----------|------|-------|
| Workers Paid | $5/month + usage | 10M requests included |
| R2 | $0.015/GB | No egress fees |
| D1 | Included in Workers Paid | |
| Access Teams | $3/user/month | Full SSO |

**Estimated monthly cost**: $50-200 for mid-size enterprise

---

## Implementation Phases

### Phase 1: Static + Access (v0.6-0.7)
- Cloudflare Pages deployment
- Cloudflare Access for auth
- Manual bundle uploads

### Phase 2: Storage + API (v0.8-0.9)
- R2 for bundle storage
- Workers API for search
- D1 for indexing

### Phase 3: Collector + Automation (v1.0)
- On-prem collector agent
- Cloudflare Tunnels
- Automated extraction pipeline

---

## Alternatives Considered

### AWS/Azure/GCP

**Pros**: Enterprise familiarity, broader services
**Cons**: Higher complexity, egress costs, more moving parts
**Decision**: Not for default, may offer as option

### Self-Hosted (Nginx + PostgreSQL)

**Pros**: Full control, no vendor dependency
**Cons**: Operational burden, security responsibility
**Decision**: Document as option for enterprise on-prem

### Vercel/Netlify

**Pros**: Great DX, easy deployment
**Cons**: Less integrated edge compute, function limits
**Decision**: Support as alternative to Cloudflare Pages

---

## See Also

- [ADR-0001-Deployment-Model.md](ADR-0001-Deployment-Model.md) — Architecture decisions
- [DEPLOYMENT.md](DEPLOYMENT.md) — Deployment instructions
- [ROADMAP.md](ROADMAP.md) — Version roadmap
