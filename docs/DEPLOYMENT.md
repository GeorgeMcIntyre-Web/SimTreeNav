# SimTreeNav Deployment Guide

This guide covers deploying SimTreeNav bundles to static hosting platforms.

## Quick Start

```powershell
# 1. Generate a demo bundle
.\DemoStory.ps1 -NodeCount 500 -OutDir ./output/demo_v06 -NoOpen

# 2. Create deployment package
.\DeployPack.ps1 -BundlePath ./output/demo_v06 -OutDir ./deploy/site -SiteName simtreenav-demo

# 3. Verify the package
.\VerifyDeploy.ps1 -SiteDir ./deploy/site

# 4. Deploy to your hosting platform (see sections below)
```

## Deployment Package Structure

After running `DeployPack.ps1`, your deployment folder will contain:

```
deploy/site/
├── index.html           # Main viewer application
├── manifest.json        # Bundle metadata and configuration
├── assets/
│   ├── css/
│   │   └── ui.css       # Styles
│   └── js/
│       ├── app.js       # Main application
│       ├── state.js     # State management
│       ├── dataLoader.js
│       ├── treeView.js
│       ├── timelineView.js
│       └── inspectorView.js
├── data/
│   ├── nodes.json       # Tree structure
│   ├── timeline.json    # Snapshot history
│   ├── diff.json        # Change data
│   ├── actions.json     # Activity log
│   ├── impact.json      # Impact analysis
│   └── drift.json       # Drift data
├── _headers             # Cloudflare Pages headers
├── _redirects           # Cloudflare Pages redirects
├── .nojekyll            # GitHub Pages config
└── 404.html             # GitHub Pages SPA fallback
```

## BasePath Configuration

The viewer supports deployment to any URL path via `basePath` in `manifest.json`:

```json
{
  "viewer": {
    "basePath": "/simtreenav-demo/"
  }
}
```

- For root deployment: `"basePath": "/"`
- For subdirectory: `"basePath": "/projects/simtreenav/"`

The `DeployPack.ps1` script sets this automatically based on the `-SiteName` parameter.

---

## Cloudflare Pages Deployment

### Prerequisites
- Cloudflare account
- Wrangler CLI (optional, for CLI deployment)

### Option 1: Web Dashboard

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Navigate to **Workers & Pages** → **Create application** → **Pages**
3. Choose **Upload assets**
4. Drag and drop the contents of `./deploy/site/`
5. Set project name (e.g., `simtreenav-demo`)
6. Click **Deploy**

Your site will be available at: `https://simtreenav-demo.pages.dev`

### Option 2: Wrangler CLI

```bash
# Install Wrangler
npm install -g wrangler

# Login to Cloudflare
wrangler login

# Deploy
wrangler pages deploy ./deploy/site --project-name=simtreenav-demo
```

### Custom Domain

1. Go to your Pages project → **Custom domains**
2. Click **Set up a custom domain**
3. Enter your domain and follow DNS configuration

### Environment Variables (optional)

If you need to set environment variables:

1. Go to your Pages project → **Settings** → **Environment variables**
2. Add variables for build or runtime

---

## GitHub Pages Deployment

### Prerequisites
- GitHub repository
- GitHub Actions (for automated deployment)

### Option 1: Manual Upload

1. Create a new branch: `git checkout -b gh-pages`
2. Copy deployment files: `cp -r ./deploy/site/* .`
3. Commit and push: `git add . && git commit -m "Deploy" && git push origin gh-pages`
4. Go to repository **Settings** → **Pages**
5. Set source to `gh-pages` branch
6. Set folder to `/ (root)`

Your site will be available at: `https://username.github.io/repo-name/`

### Option 2: GitHub Actions

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy SimTreeNav

on:
  push:
    branches: [main]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup PowerShell
        shell: pwsh
        run: |
          ./DemoStory.ps1 -NodeCount 500 -OutDir ./output/demo -NoOpen
          ./DeployPack.ps1 -BundlePath ./output/demo -OutDir ./deploy/site -SiteName simtreenav
          ./VerifyDeploy.ps1 -SiteDir ./deploy/site
      
      - name: Upload artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: ./deploy/site
      
      - name: Deploy to GitHub Pages
        uses: actions/deploy-pages@v4
```

### Subdirectory Deployment

For deployment to `https://username.github.io/repo-name/`:

```powershell
.\DeployPack.ps1 -BundlePath ./output/demo -OutDir ./deploy/site -SiteName repo-name -BasePath /repo-name/
```

---

## Security Considerations

### ⚠️ Random URLs Are NOT Private

Deploying to a public URL (even an obscure one) does not protect your data.

- Anyone with the URL can access the content
- URLs can be discovered through browser history, referrer headers, or search engines
- Sensitive data should NEVER be deployed to unprotected static hosting

### Recommended Protection Methods

#### 1. Cloudflare Access (Recommended for Teams)

Cloudflare Access provides zero-trust access control:

1. Go to [Cloudflare Zero Trust](https://one.dash.cloudflare.com)
2. Navigate to **Access** → **Applications** → **Add an application**
3. Choose **Self-hosted**
4. Configure:
   - Application name: `SimTreeNav`
   - Domain: `simtreenav-demo.pages.dev` (or your custom domain)
5. Add access policies:
   - **Email domain**: Allow `@yourcompany.com`
   - **SSO integration**: Connect your identity provider
   - **One-time PIN**: Allow specific email addresses

**Pricing**: Free for up to 50 users on the Free plan.

#### 2. Basic Authentication (Cloudflare Workers)

For simple password protection, create a Cloudflare Worker:

```javascript
// worker.js
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

async function handleRequest(request) {
  const authorization = request.headers.get('Authorization');
  
  if (!authorization) {
    return new Response('Unauthorized', {
      status: 401,
      headers: {
        'WWW-Authenticate': 'Basic realm="SimTreeNav"'
      }
    });
  }
  
  const [scheme, encoded] = authorization.split(' ');
  if (scheme !== 'Basic') {
    return new Response('Invalid auth scheme', { status: 401 });
  }
  
  const decoded = atob(encoded);
  const [user, password] = decoded.split(':');
  
  // Store credentials in Worker environment variables
  const validUser = await AUTH_KV.get('username');
  const validPass = await AUTH_KV.get('password');
  
  if (user !== validUser || password !== validPass) {
    return new Response('Forbidden', { status: 403 });
  }
  
  // Forward to Pages
  return fetch(request);
}
```

#### 3. IP Allowlist (Cloudflare WAF)

For corporate network access only:

1. Go to **Security** → **WAF** → **Custom rules**
2. Create rule:
   - Expression: `(not ip.src in {10.0.0.0/8 192.168.0.0/16 YOUR_PUBLIC_IP})`
   - Action: Block
3. Apply to your Pages domain

#### 4. GitHub Repository Access (GitHub Pages)

For private repositories:

1. Keep repository private
2. GitHub Pages will be accessible only via:
   - Repository collaborators
   - GitHub tokens
   - Enterprise SSO (if configured)

**Note**: This is only available on paid GitHub plans.

---

## Verification Checklist

Before deploying, ensure:

- [ ] `VerifyDeploy.ps1` passes without errors
- [ ] No external network URLs in HTML/JS (verified automatically)
- [ ] All data files are valid JSON
- [ ] `manifest.json` has correct `basePath`
- [ ] Security measures are configured (for sensitive data)

Run the verification:

```powershell
.\VerifyDeploy.ps1 -SiteDir ./deploy/site -Strict
```

The `-Strict` flag treats warnings as errors.

---

## Troubleshooting

### Site Shows Blank Page

1. Check browser console for JavaScript errors
2. Verify `basePath` matches deployment URL
3. Ensure all assets are loaded (Network tab)

### Data Not Loading

1. Check data files exist in `data/` directory
2. Verify JSON files are valid: `Get-Content data/nodes.json | ConvertFrom-Json`
3. Check CORS headers if loading from different origin

### 404 Errors on Refresh

For SPA routing:
- Cloudflare: Check `_redirects` file exists
- GitHub: Check `404.html` exists

### Large File Issues

GitHub Pages has a 100MB file size limit:
- Consider splitting large `nodes.json` files
- Use compression (gzip) where supported

---

## Performance Optimization

### For Large Datasets

1. **Enable Compression**
   - Cloudflare: Enabled by default
   - GitHub: Add gzip compression in build step

2. **Use CDN Caching**
   - Set appropriate `Cache-Control` headers
   - See `_headers` file for defaults

3. **Consider Data Chunking**
   - Split large node trees into chunks
   - Load on-demand as user expands tree

### Recommended Limits

| Metric | Recommended | Maximum |
|--------|------------|---------|
| Node count | < 10,000 | 50,000 |
| nodes.json size | < 5 MB | 20 MB |
| Total bundle size | < 10 MB | 100 MB |

---

## See Also

- [ROADMAP.md](ROADMAP.md) - Future development plans
- [ADR-0001-Deployment-Model.md](ADR-0001-Deployment-Model.md) - Architecture decisions
- [CLOUD-BLUEPRINT.md](CLOUD-BLUEPRINT.md) - Cloud architecture design
