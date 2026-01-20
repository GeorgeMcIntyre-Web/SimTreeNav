# Hosting & Deployment Options for SimTreeNav

**Azure, Cloudflare, Local - Which is Right for You?**

**Date:** January 20, 2026

---

## Executive Summary

**The Question:** Where should we host SimTreeNav for 50+ users?

**The Answer:** Start with **local IIS** (cheapest, fastest to deploy). Scale to **Azure Static Web Apps + Cloudflare CDN** if you need global access or >100 users.

**Key Insight:** SimTreeNav generates **static HTML files** (95 MB each). This makes hosting trivially simple - no databases, no complex backends, just file serving.

---

## Part 1: Hosting Requirements

### What SimTreeNav Needs

**Current Architecture:**
- Static HTML files (95 MB per project)
- Embedded JavaScript (no external dependencies)
- Base64-encoded icons (no separate image files)
- No server-side processing (all logic in browser)

**Hosting Requirements:**
- ✅ Serve HTML files over HTTP/HTTPS
- ✅ Handle 50-100 concurrent users
- ✅ Support file downloads (95 MB files)
- ✅ Optional: Compression (gzip reduces 95 MB → ~10 MB)

**What We DON'T Need:**
- ❌ Database server
- ❌ Application server
- ❌ Load balancer (until 1000+ users)
- ❌ Complex CDN (unless global users)

---

## Part 2: Option Comparison Matrix

| Factor | Local IIS | Azure Static Web Apps | Azure App Service | Cloudflare Pages | Network Share |
|--------|-----------|----------------------|-------------------|------------------|---------------|
| **Setup Time** | 30 min | 1-2 hours | 2-3 hours | 1 hour | 5 min |
| **Monthly Cost** | $0 | $0-10 | $50-200 | $0-20 | $0 |
| **Performance (50 users)** | Excellent | Excellent | Good | Excellent | Poor |
| **Scalability** | 100-200 users max | Unlimited | Unlimited | Unlimited | 10-20 users max |
| **Global Access** | ❌ On-prem only | ✅ Yes | ✅ Yes | ✅ Yes | ❌ On-prem only |
| **HTTPS** | ⚠️ Manual cert | ✅ Auto | ✅ Auto | ✅ Auto | ❌ No |
| **Custom Domain** | ✅ Yes | ✅ Yes | ✅ Yes | ✅ Yes | ❌ No |
| **Compression** | ✅ Yes | ✅ Auto | ✅ Auto | ✅ Auto | ❌ No |
| **Maintenance** | Low | Minimal | Medium | Minimal | Zero |

**Recommended Path:**
1. **Week 1:** Start with **Local IIS** (validate with pilot users)
2. **Month 2:** Move to **Azure Static Web Apps** (if > 50 users or need HTTPS)
3. **Month 6:** Add **Cloudflare CDN** (if global users or need <1s load times)

---

## Part 3: Detailed Option Analysis

### Option 1: Local IIS (Windows Server) - RECOMMENDED FOR START

**Best For:**
- 10-100 users on corporate network
- Quick deployment (today!)
- Zero budget

**Architecture:**

```
Users (on corporate network)
  ↓
Local IIS Server (simtreenav.company.local)
  ↓
C:\inetpub\wwwroot\simtreenav\
  ├─ tree-viewer-DESIGN1.html (95 MB)
  ├─ tree-viewer-DESIGN2.html
  └─ ...
```

**Setup Steps:**

```powershell
# 1. Enable IIS on Windows Server
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServerRole
Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer
Enable-WindowsOptionalFeature -Online -FeatureName IIS-HttpCompressionStatic

# 2. Create website directory
New-Item -Path "C:\inetpub\wwwroot\simtreenav" -ItemType Directory

# 3. Copy HTML files
Copy-Item "C:\SimTreeNav\data\output\*.html" "C:\inetpub\wwwroot\simtreenav\"

# 4. Create IIS site
Import-Module WebAdministration
New-Website -Name "SimTreeNav" `
    -PhysicalPath "C:\inetpub\wwwroot\simtreenav" `
    -Port 80 `
    -HostHeader "simtreenav.company.local"

# 5. Enable gzip compression (reduces 95 MB → 10 MB)
Set-WebConfigurationProperty -Filter "/system.webServer/httpCompression/scheme[@name='gzip']" `
    -PSPath "IIS:\Sites\SimTreeNav" `
    -Name "staticCompressionLevel" `
    -Value 9

# 6. Add MIME type for .html (if needed)
Add-WebConfigurationProperty -Filter "//staticContent" `
    -PSPath "IIS:\Sites\SimTreeNav" `
    -Name "." `
    -Value @{fileExtension='.html'; mimeType='text/html'}

# 7. Test
Start-Process "http://simtreenav.company.local"
```

**Performance:**
- Load time: 2-3 seconds (with compression)
- Concurrent users: 100-200 (on decent server)
- Bandwidth: ~10 MB/user (with gzip)

**Pros:**
- ✅ Zero cost
- ✅ Fast deployment (30 minutes)
- ✅ Full control
- ✅ No internet dependency

**Cons:**
- ❌ On-prem only (no remote access)
- ❌ Manual HTTPS setup (need certificate)
- ❌ Limited to server capacity

**Cost:** $0/month

---

### Option 2: Azure Static Web Apps - RECOMMENDED FOR SCALE

**Best For:**
- 100-1000+ users
- Need HTTPS/custom domain
- Want automatic deployment
- Remote/global access required

**Architecture:**

```
Users (anywhere)
  ↓
Azure CDN (global edge locations)
  ↓
Azure Static Web Apps (simtreenav.azurestaticapps.net)
  ↓
Azure Blob Storage (HTML files)
  ↑
GitHub Actions (auto-deploy on commit)
```

**Setup Steps:**

```bash
# 1. Create Static Web App via Azure Portal or CLI
az staticwebapp create \
    --name simtreenav \
    --resource-group simtreenav-rg \
    --location eastus2 \
    --source https://github.com/your-org/SimTreeNav \
    --branch main \
    --app-location "data/output" \
    --sku Free

# 2. Configure custom domain (optional)
az staticwebapp hostname set \
    --name simtreenav \
    --hostname simtreenav.company.com

# 3. Enable compression (automatic)
# Azure Static Web Apps compresses automatically

# 4. Deploy files
# Option A: GitHub Actions (automatic on git push)
# .github/workflows/deploy.yml
name: Deploy SimTreeNav
on:
  push:
    branches: [main]
    paths: ['data/output/**']
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: Azure/static-web-apps-deploy@v1
        with:
          azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
          app_location: "data/output"

# Option B: Manual upload
az storage blob upload-batch \
    --account-name simtreenav \
    --destination '$web' \
    --source ./data/output \
    --pattern "*.html"
```

**Performance:**
- Load time: 1-2 seconds (global CDN)
- Concurrent users: Unlimited (autoscaling)
- Bandwidth: Included (100 GB/month free tier)

**Pros:**
- ✅ Free tier (100 GB bandwidth/month)
- ✅ Automatic HTTPS (Let's Encrypt)
- ✅ Custom domain support
- ✅ Global CDN (fast everywhere)
- ✅ Auto-deployment from GitHub
- ✅ Automatic compression

**Cons:**
- ❌ Requires Azure subscription
- ❌ More complex setup
- ❌ Internet dependency

**Cost:**
- **Free Tier:** $0/month (up to 100 GB bandwidth)
- **Standard Tier:** $9/month (250 GB bandwidth) - only if >100 users

**When to Choose This:**
- You need HTTPS
- You have remote/mobile users
- You want GitHub integration
- You're already using Azure

---

### Option 3: Azure App Service (Web App)

**Best For:**
- Need backend logic (Phase 2 Advanced features)
- Want integrated database access
- Enterprise support required

**Architecture:**

```
Users
  ↓
Azure App Service (simtreenav.azurewebsites.net)
  ├─ IIS (serving HTML)
  └─ PowerShell backend (optional)
  ↓
Azure SQL / Oracle on-prem (via VPN)
```

**Setup Steps:**

```bash
# 1. Create App Service Plan
az appservice plan create \
    --name simtreenav-plan \
    --resource-group simtreenav-rg \
    --sku B1 \
    --is-linux false

# 2. Create Web App
az webapp create \
    --name simtreenav \
    --plan simtreenav-plan \
    --resource-group simtreenav-rg

# 3. Deploy HTML files
az webapp deployment source config-zip \
    --name simtreenav \
    --resource-group simtreenav-rg \
    --src simtreenav-html.zip

# 4. Configure custom domain
az webapp config hostname add \
    --webapp-name simtreenav \
    --resource-group simtreenav-rg \
    --hostname simtreenav.company.com

# 5. Enable HTTPS
az webapp config set \
    --name simtreenav \
    --resource-group simtreenav-rg \
    --https-only true
```

**Pros:**
- ✅ Can run PowerShell backend
- ✅ Database connectivity (Oracle via VPN)
- ✅ Autoscaling
- ✅ Enterprise support (SLA)

**Cons:**
- ❌ More expensive ($50-200/month)
- ❌ Overkill for static files
- ❌ Complex setup

**Cost:**
- **Basic (B1):** $54/month (1 core, 1.75 GB RAM)
- **Standard (S1):** $73/month (1 core, 1.75 GB RAM, autoscale)

**When to Choose This:**
- You need backend API (Phase 2 Advanced)
- You want Oracle connectivity from Azure
- You need enterprise SLA

---

### Option 4: Cloudflare Pages - BEST FOR GLOBAL PERFORMANCE

**Best For:**
- Global users (multiple continents)
- Sub-second load times critical
- Free tier preferred
- GitHub/GitLab integration

**Architecture:**

```
Users (worldwide)
  ↓
Cloudflare Edge Network (300+ cities)
  ↓
Cloudflare Pages (simtreenav.pages.dev)
  ↓
GitHub Repository
```

**Setup Steps:**

```bash
# 1. Connect GitHub repo to Cloudflare Pages
# Via Cloudflare Dashboard:
# - Go to Pages
# - Click "Create a project"
# - Connect to GitHub: your-org/SimTreeNav
# - Build settings:
#   - Build command: (none)
#   - Build output directory: data/output

# 2. Configure custom domain
# Dashboard → Pages → simtreenav → Custom domains → Add
# simtreenav.company.com → CNAME simtreenav.pages.dev

# 3. Enable compression (automatic)
# Already enabled by default

# 4. Deploy
git add data/output/*.html
git commit -m "Update tree viewer"
git push
# Auto-deploys in ~30 seconds
```

**Performance:**
- Load time: 500ms-1s (global edge network)
- Concurrent users: Unlimited
- Bandwidth: Unlimited (on free tier!)

**Pros:**
- ✅ **Free tier with unlimited bandwidth** (!)
- ✅ Fastest global performance (300+ edge locations)
- ✅ Automatic HTTPS
- ✅ Custom domain support
- ✅ Auto-deployment from GitHub
- ✅ DDoS protection included
- ✅ Web analytics included

**Cons:**
- ❌ No backend logic (static only)
- ❌ 25 MB file size limit per file (might need chunking for 95 MB HTML)
- ❌ Requires GitHub/GitLab account

**Cost:**
- **Free Tier:** $0/month (unlimited bandwidth!)
- **Pro Tier:** $20/month (only if need > 500 builds/month)

**File Size Workaround:**

If HTML files exceed 25 MB limit:

```powershell
# Split large HTML into chunks
$htmlContent = Get-Content tree-viewer-DESIGN1.html -Raw
$chunkSize = 20MB
$chunks = [Math]::Ceiling($htmlContent.Length / $chunkSize)

for ($i = 0; $i -lt $chunks; $i++) {
    $start = $i * $chunkSize
    $chunk = $htmlContent.Substring($start, [Math]::Min($chunkSize, $htmlContent.Length - $start))
    $chunk | Out-File "tree-viewer-DESIGN1-chunk-$i.html"
}

# JavaScript to reassemble in browser
```

**When to Choose This:**
- You have global/remote users
- You want best-in-class performance
- You don't want to pay for bandwidth
- You already use Cloudflare for DNS

---

### Option 5: Azure + Cloudflare (Hybrid - BEST OF BOTH WORLDS)

**Architecture:**

```
Users
  ↓
Cloudflare CDN (caching layer, 300+ edge locations)
  ↓
Azure Static Web Apps (origin server)
  ↓
GitHub (auto-deploy)
```

**Why Combine?**
- Azure Static Web Apps: Easy deployment, GitHub integration
- Cloudflare: Global CDN, free bandwidth, WAF

**Setup:**

```bash
# 1. Deploy to Azure Static Web Apps (as above)
az staticwebapp create --name simtreenav ...

# 2. Point Cloudflare to Azure
# Cloudflare Dashboard → DNS → Add record:
# Type: CNAME
# Name: simtreenav
# Target: simtreenav.azurestaticapps.net
# Proxy: ON (orange cloud)

# 3. Configure Cloudflare caching
# Page Rules → Create:
# URL: simtreenav.company.com/*
# Cache Level: Cache Everything
# Edge Cache TTL: 1 hour
# Browser Cache TTL: 4 hours
```

**Performance:**
- Load time: 300-800ms (Cloudflare edge cache)
- Bandwidth: Unlimited (Cloudflare free tier)

**Pros:**
- ✅ Best of both worlds
- ✅ Azure deployment simplicity
- ✅ Cloudflare global performance
- ✅ Free bandwidth
- ✅ DDoS protection

**Cons:**
- ❌ Slightly more complex setup
- ❌ Two services to manage

**Cost:**
- Azure Static Web Apps: $0-9/month
- Cloudflare: $0/month (free tier)
- **Total: $0-9/month**

**When to Choose This:**
- You want the absolute best performance
- You have budget for Azure ($9/month) but not bandwidth costs
- You want enterprise-grade security (Cloudflare WAF)

---

## Part 4: Hosting Decision Tree

```
START: How many users?

├─ < 50 users (on corporate network)
│  └─> Local IIS ($0/month)
│
├─ 50-100 users (corporate network)
│  ├─ Need HTTPS? → Azure Static Web Apps ($0-9/month)
│  └─ No HTTPS needed? → Local IIS ($0/month)
│
├─ 100-500 users (corporate + some remote)
│  ├─ Global users? → Cloudflare Pages ($0/month)
│  └─ US-only? → Azure Static Web Apps ($9/month)
│
└─ 500+ users (global)
   └─> Azure + Cloudflare Hybrid ($9/month)
```

---

## Part 5: Performance Comparison

### Load Time Benchmarks (95 MB HTML file)

| Hosting Option | No Compression | With gzip | Location |
|----------------|----------------|-----------|----------|
| Network Share | 60-90 seconds | N/A | Corporate LAN |
| Local IIS | 3-5 seconds | 2-3 seconds | Corporate LAN |
| Azure Static Web Apps | 5-8 seconds | 2-4 seconds | US East |
| Cloudflare Pages | 4-6 seconds | 1-2 seconds | Global average |
| Azure + Cloudflare | 3-5 seconds | **500ms-1.5s** | Global average |

**Key Insight:** Compression is critical (95 MB → 10 MB = 9× faster)

---

## Part 6: Cost Comparison (Annual)

### 50 Users

| Option | Setup | Annual Cost | Total 3-Year |
|--------|-------|-------------|--------------|
| Local IIS | $0 | $0 | **$0** |
| Azure Static Web Apps (Free) | $0 | $0 | **$0** |
| Azure Static Web Apps (Standard) | $0 | $108 | **$324** |
| Cloudflare Pages | $0 | $0 | **$0** |
| Azure + Cloudflare | $0 | $108 | **$324** |

---

### 200 Users

| Option | Setup | Annual Cost | Total 3-Year |
|--------|-------|-------------|--------------|
| Local IIS | $0 | $0 | **$0** |
| Azure Static Web Apps (Standard) | $0 | $108 | **$324** |
| Cloudflare Pages | $0 | $0 | **$0** |
| Azure + Cloudflare | $0 | $108 | **$324** |

**Winner for Cost:** Cloudflare Pages ($0/month, unlimited bandwidth)

**Winner for Simplicity:** Local IIS (30 min setup, $0 cost)

---

## Part 7: Security Considerations

### HTTPS / SSL Certificates

**Local IIS:**
```powershell
# Option A: Self-signed certificate (internal only)
New-SelfSignedCertificate -DnsName "simtreenav.company.local" `
    -CertStoreLocation "cert:\LocalMachine\My"

# Option B: Company CA certificate (recommended)
# Request from internal Certificate Authority

# Option C: Let's Encrypt (if publicly accessible)
Install-Module -Name Posh-ACME
New-PACertificate -Domain "simtreenav.company.com" -AcceptTOS
```

**Azure / Cloudflare:**
- Automatic HTTPS (Let's Encrypt)
- Free SSL certificate
- Auto-renewal

---

### Access Control

**Local IIS:**
```powershell
# Option A: Windows Authentication (AD integration)
Set-WebConfigurationProperty -Filter "/system.webServer/security/authentication/windowsAuthentication" `
    -Name "enabled" -Value "True" -PSPath "IIS:\Sites\SimTreeNav"

# Option B: IP whitelisting
Add-WebConfigurationProperty -Filter "/system.webServer/security/ipSecurity" `
    -Name "." -Value @{ipAddress="192.168.1.0"; subnetMask="255.255.255.0"; allowed="true"}
```

**Azure Static Web Apps:**
```bash
# Built-in authentication (AAD, GitHub, etc.)
az staticwebapp appsettings set \
    --name simtreenav \
    --setting-names "AUTH_AAD_CLIENT_ID=<your-client-id>"
```

**Cloudflare:**
```
# Cloudflare Access (zero-trust)
Dashboard → Access → Create application
- Allow: email ends with @company.com
```

---

## Part 8: Deployment Automation

### Auto-Refresh Workflow (Daily Tree Generation)

**Option 1: Local (Windows Task Scheduler)**

```powershell
# Script: daily-refresh.ps1
cd C:\SimTreeNav\src\powershell\main
.\generate-tree-html.ps1 -SchemaName "DESIGN1"

# Copy to IIS
Copy-Item C:\SimTreeNav\data\output\*.html C:\inetpub\wwwroot\simtreenav\ -Force

# Task Scheduler
$action = New-ScheduledTaskAction -Execute "PowerShell.exe" `
    -Argument "-File C:\SimTreeNav\scripts\daily-refresh.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At 6am
Register-ScheduledTask -TaskName "SimTreeNav Daily Refresh" `
    -Action $action -Trigger $trigger
```

---

**Option 2: Azure (GitHub Actions + Auto-Deploy)**

```yaml
# .github/workflows/daily-refresh.yml
name: Daily Tree Refresh
on:
  schedule:
    - cron: '0 6 * * *'  # 6 AM daily
jobs:
  refresh:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v2

      - name: Generate tree
        run: |
          cd src/powershell/main
          .\generate-tree-html.ps1 -SchemaName "DESIGN1"

      - name: Commit changes
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add data/output/*.html
          git commit -m "Automated tree refresh"
          git push

      # Auto-deploys to Azure Static Web Apps via existing workflow
```

---

**Option 3: Cloudflare (GitHub Actions + Auto-Deploy)**

```yaml
# .github/workflows/cloudflare-deploy.yml
name: Deploy to Cloudflare Pages
on:
  push:
    branches: [main]
    paths: ['data/output/**']
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: cloudflare/wrangler-action@v3
        with:
          apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
          accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
          command: pages publish data/output --project-name=simtreenav
```

---

## Part 9: Recommended Implementation Path

### Week 1: Start Simple

**Deploy to Local IIS:**
1. Follow [QUICK-START-DEPLOYMENT.md](QUICK-START-DEPLOYMENT.md)
2. Use local IIS (30 min setup, $0 cost)
3. Test with 5-10 pilot users
4. Validate performance and gather feedback

**Success Criteria:**
- ✅ Load time < 5 seconds
- ✅ 90%+ pilot users can access
- ✅ No server crashes

---

### Month 1: Add HTTPS (If Needed)

**Upgrade to Azure Static Web Apps OR Cloudflare Pages:**
- If you need HTTPS → Azure Static Web Apps
- If you want global CDN → Cloudflare Pages
- If you want both → Azure + Cloudflare

**Migration Steps:**
1. Create Azure/Cloudflare account
2. Push HTML files to GitHub
3. Connect GitHub to hosting platform
4. Update DNS (if custom domain)
5. Test thoroughly
6. Switch users over (gradual rollout)

---

### Month 3: Optimize Performance

**Add Cloudflare CDN (If Not Already):**
- Point Cloudflare to Azure origin
- Enable caching rules
- Monitor load times (target < 1 second)

**Result:** Sub-second load times globally

---

## Part 10: Custom Domain Setup

### Company Domain (simtreenav.company.com)

**DNS Configuration (Cloudflare):**

```
# A record (if using Azure App Service)
Type: A
Name: simtreenav
Value: 20.14.212.43 (Azure IP)
Proxy: ON

# CNAME record (if using Azure Static Web Apps or Cloudflare Pages)
Type: CNAME
Name: simtreenav
Target: simtreenav.azurestaticapps.net (or simtreenav.pages.dev)
Proxy: ON
```

**Azure Configuration:**

```bash
# Add custom domain to Azure Static Web App
az staticwebapp hostname set \
    --name simtreenav \
    --hostname simtreenav.company.com

# HTTPS is automatic (Let's Encrypt)
```

**Result:** `https://simtreenav.company.com` (fully branded)

---

## Conclusion & Recommendations

### Start Here (Week 1):
**Local IIS** - Free, fast, easy
- 30-minute setup
- $0 cost
- Perfect for 10-100 corporate users
- Follow [QUICK-START-DEPLOYMENT.md](QUICK-START-DEPLOYMENT.md)

### Scale Here (Month 2):
**Cloudflare Pages** - Free, global, unlimited bandwidth
- 1-hour setup
- $0/month
- Perfect for 100-1000+ users worldwide
- Best performance

### Enterprise Option (If Needed):
**Azure Static Web Apps + Cloudflare CDN** - Best of both worlds
- 2-hour setup
- $9/month (Azure Standard tier)
- Enterprise support, SLA, GitHub integration
- Global CDN performance

---

### Cost Summary (3-Year Total)

| Hosting Option | 50 Users | 200 Users | 1000 Users |
|----------------|----------|-----------|------------|
| Local IIS | **$0** | **$0** | N/A (can't scale) |
| Cloudflare Pages | **$0** | **$0** | **$0** |
| Azure Static Web Apps | **$0-324** | **$324** | **$324** |
| Azure + Cloudflare | **$324** | **$324** | **$324** |

**Winner:** Cloudflare Pages (free forever, unlimited scale)

**Runner-Up:** Local IIS (free, but limited to corporate network)

---

**Next Steps:**
1. Deploy Phase 1 to Local IIS today (30 minutes)
2. Pilot with 10 users for 2 weeks
3. If successful, migrate to Cloudflare Pages (1 hour)
4. Add custom domain (optional, 30 minutes)
5. Enjoy sub-second global load times at $0/month

---

**End of Hosting & Deployment Options**
