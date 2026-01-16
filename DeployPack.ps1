<#
.SYNOPSIS
    Creates a deployable static site from a SimTreeNav bundle.

.DESCRIPTION
    DeployPack takes a SimTreeNav output bundle and produces a deployment-ready
    static site folder that can be uploaded to Cloudflare Pages, GitHub Pages,
    or any static hosting provider.

.PARAMETER BundlePath
    Path to the source bundle directory (output from DemoStory or extraction).

.PARAMETER OutDir
    Output directory for the deployable site.

.PARAMETER SiteName
    Name for the site (used in manifest and basePath).

.PARAMETER Mode
    Deployment mode: Static (default), or Secure (adds placeholder auth config).

.PARAMETER BasePath
    Custom base path for the site (default: /{SiteName}/).

.EXAMPLE
    .\DeployPack.ps1 -BundlePath ./output/demo_v06 -OutDir ./deploy/site -SiteName simtreenav-demo

.EXAMPLE
    .\DeployPack.ps1 -BundlePath ./output/demo_v06 -OutDir ./deploy/site -SiteName simtreenav-demo -Mode Secure
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundlePath,

    [Parameter(Mandatory = $true)]
    [string]$OutDir,

    [Parameter(Mandatory = $true)]
    [string]$SiteName,

    [Parameter()]
    [ValidateSet('Static', 'Secure')]
    [string]$Mode = 'Static',

    [Parameter()]
    [string]$BasePath
)

# Strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Status {
    param([string]$Message, [string]$Type = 'Info')
    
    $colors = @{
        'Info'    = 'Cyan'
        'Success' = 'Green'
        'Warning' = 'Yellow'
        'Error'   = 'Red'
    }
    
    $prefix = switch ($Type) {
        'Info'    { '[*]' }
        'Success' { '[+]' }
        'Warning' { '[!]' }
        'Error'   { '[-]' }
    }
    
    Write-Host "$prefix $Message" -ForegroundColor $colors[$Type]
}

function Ensure-Directory {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-ViewerFiles {
    param(
        [string]$ViewerSource,
        [string]$Destination
    )
    
    # Copy viewer HTML
    $indexHtml = Join-Path $ViewerSource 'index.html'
    if (Test-Path $indexHtml) {
        Copy-Item $indexHtml $Destination -Force
    }
    
    # Copy assets
    $assetsSource = Join-Path $ViewerSource 'assets'
    if (Test-Path $assetsSource) {
        $assetsDest = Join-Path $Destination 'assets'
        Ensure-Directory $assetsDest
        Copy-Item "$assetsSource\*" $assetsDest -Recurse -Force
    }
}

function Copy-DataFiles {
    param(
        [string]$BundlePath,
        [string]$Destination
    )
    
    $dataDest = Join-Path $Destination 'data'
    Ensure-Directory $dataDest
    
    # List of data files to copy
    $dataFiles = @(
        'nodes.json',
        'timeline.json',
        'diff.json',
        'actions.json',
        'impact.json',
        'drift.json',
        'drift_trend.json'
    )
    
    $copiedFiles = @()
    
    foreach ($file in $dataFiles) {
        $sourcePath = Join-Path $BundlePath $file
        if (Test-Path $sourcePath) {
            Copy-Item $sourcePath $dataDest -Force
            $copiedFiles += $file
        }
    }
    
    # Also copy any other JSON files in the bundle
    Get-ChildItem -Path $BundlePath -Filter '*.json' -File | ForEach-Object {
        if ($_.Name -notin $copiedFiles -and $_.Name -ne 'manifest.json') {
            Copy-Item $_.FullName $dataDest -Force
            $copiedFiles += $_.Name
        }
    }
    
    return $copiedFiles
}

function Create-Manifest {
    param(
        [string]$Destination,
        [string]$SiteName,
        [string]$BasePath,
        [string]$Mode,
        [array]$DataFiles
    )
    
    $timestamp = Get-Date -Format 'o'
    
    $manifest = @{
        schemaVersion = '0.6.0'
        siteName      = $SiteName
        generatedAt   = $timestamp
        mode          = $Mode
        viewer        = @{
            basePath = $BasePath
        }
        files         = @{}
    }
    
    # Add data files to manifest
    foreach ($file in $DataFiles) {
        $key = $file -replace '\.json$', ''
        $manifest.files[$key] = $file
    }
    
    # Write manifest
    $manifestPath = Join-Path $Destination 'manifest.json'
    $manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath -Encoding UTF8
    
    return $manifest
}

function Update-IndexHtml {
    param(
        [string]$IndexPath,
        [string]$BasePath,
        [string]$SiteName
    )
    
    if (-not (Test-Path $IndexPath)) {
        return
    }
    
    $content = Get-Content $IndexPath -Raw -Encoding UTF8
    
    # Update title
    $content = $content -replace '<title>SimTreeNav</title>', "<title>$SiteName - SimTreeNav</title>"
    
    # Ensure paths are relative (already are, but verify)
    # The viewer uses relative paths by default, no absolute paths to fix
    
    Set-Content $IndexPath $content -Encoding UTF8
}

function Create-SecurityHeaders {
    param([string]$Destination)
    
    # Create _headers file for Cloudflare Pages
    $headersContent = @"
/*
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Content-Security-Policy: default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:;

/*.json
  Content-Type: application/json
  Cache-Control: public, max-age=3600
"@

    $headersPath = Join-Path $Destination '_headers'
    Set-Content $headersPath $headersContent -Encoding UTF8
    
    # Create _redirects file (for SPA routing if needed)
    $redirectsContent = @"
# Cloudflare Pages redirects
# SPA fallback
/*    /index.html    200
"@

    $redirectsPath = Join-Path $Destination '_redirects'
    Set-Content $redirectsPath $redirectsContent -Encoding UTF8
}

function Create-GitHubPagesConfig {
    param([string]$Destination)
    
    # Create .nojekyll to prevent Jekyll processing
    $nojekyllPath = Join-Path $Destination '.nojekyll'
    '' | Set-Content $nojekyllPath
    
    # Create 404.html for GitHub Pages SPA
    $notFoundContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Page Not Found - SimTreeNav</title>
    <script>
        // Redirect to main page for SPA
        window.location.href = window.location.origin + window.location.pathname.split('/').slice(0, 2).join('/') + '/';
    </script>
</head>
<body>
    <p>Redirecting...</p>
</body>
</html>
"@

    $notFoundPath = Join-Path $Destination '404.html'
    Set-Content $notFoundPath $notFoundContent -Encoding UTF8
}

# ============================================================================
# Main Script
# ============================================================================

Write-Status "SimTreeNav DeployPack v0.6.0" 'Info'
Write-Status "Creating deployable site from bundle..." 'Info'

# Validate inputs
if (-not (Test-Path $BundlePath)) {
    Write-Status "Bundle path not found: $BundlePath" 'Error'
    exit 1
}

# Set default basePath
if (-not $BasePath) {
    $BasePath = "/$SiteName/"
}

# Normalize basePath
if (-not $BasePath.StartsWith('/')) {
    $BasePath = "/$BasePath"
}
if (-not $BasePath.EndsWith('/')) {
    $BasePath = "$BasePath/"
}

Write-Status "Bundle: $BundlePath" 'Info'
Write-Status "Output: $OutDir" 'Info'
Write-Status "Site Name: $SiteName" 'Info'
Write-Status "Base Path: $BasePath" 'Info'
Write-Status "Mode: $Mode" 'Info'

# Create output directory
if (Test-Path $OutDir) {
    Write-Status "Cleaning existing output directory..." 'Warning'
    Remove-Item $OutDir -Recurse -Force
}
Ensure-Directory $OutDir

# Locate viewer files
$viewerPath = Join-Path $PSScriptRoot 'viewer'
if (-not (Test-Path $viewerPath)) {
    # Try relative to script location
    $viewerPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'viewer'
}

if (-not (Test-Path $viewerPath)) {
    Write-Status "Viewer not found. Creating minimal viewer structure..." 'Warning'
    # Will use embedded viewer if available in bundle
    $bundleViewer = Join-Path $BundlePath 'viewer'
    if (Test-Path $bundleViewer) {
        $viewerPath = $bundleViewer
    }
}

# Step 1: Copy viewer files
Write-Status "Copying viewer files..." 'Info'
if (Test-Path $viewerPath) {
    Copy-ViewerFiles -ViewerSource $viewerPath -Destination $OutDir
    Write-Status "Viewer files copied" 'Success'
} else {
    Write-Status "No viewer found, bundle must include viewer" 'Warning'
    # Try to copy viewer from bundle if it exists there
    $bundleIndex = Join-Path $BundlePath 'index.html'
    if (Test-Path $bundleIndex) {
        Copy-Item $bundleIndex $OutDir -Force
    }
}

# Step 2: Copy data files
Write-Status "Copying data files..." 'Info'
$dataFiles = Copy-DataFiles -BundlePath $BundlePath -Destination $OutDir
Write-Status "Copied $($dataFiles.Count) data files" 'Success'

# Step 3: Create manifest
Write-Status "Creating manifest..." 'Info'
$manifest = Create-Manifest -Destination $OutDir -SiteName $SiteName -BasePath $BasePath -Mode $Mode -DataFiles $dataFiles
Write-Status "Manifest created with schema version $($manifest.schemaVersion)" 'Success'

# Step 4: Update index.html with basePath
$indexPath = Join-Path $OutDir 'index.html'
if (Test-Path $indexPath) {
    Write-Status "Updating index.html..." 'Info'
    Update-IndexHtml -IndexPath $indexPath -BasePath $BasePath -SiteName $SiteName
}

# Step 5: Create hosting configuration files
Write-Status "Creating hosting configuration..." 'Info'
Create-SecurityHeaders -Destination $OutDir
Create-GitHubPagesConfig -Destination $OutDir
Write-Status "Created Cloudflare and GitHub Pages configs" 'Success'

# Step 6: Create security note if Secure mode
if ($Mode -eq 'Secure') {
    Write-Status "Creating security configuration placeholder..." 'Info'
    $securityNote = @"
# Security Configuration

This deployment was created in Secure mode. 

## IMPORTANT: Random URLs are NOT private!

To secure this deployment, configure one of the following:

### Cloudflare Access
1. Go to Cloudflare Zero Trust dashboard
2. Create an Access Application for this site
3. Configure authentication (SSO, email, etc.)

### Basic Auth (Cloudflare Workers)
1. Create a Worker with basic auth middleware
2. Route your domain through the Worker

### IP Allowlist
1. Use Cloudflare Firewall Rules
2. Create rules to allow specific IPs only

See docs/DEPLOYMENT.md for detailed instructions.
"@
    $securityPath = Join-Path $OutDir 'SECURITY.md'
    Set-Content $securityPath $securityNote -Encoding UTF8
}

# Final summary
Write-Host ""
Write-Status "DeployPack complete!" 'Success'
Write-Host ""
Write-Host "Output structure:" -ForegroundColor White
Get-ChildItem $OutDir -Recurse | ForEach-Object {
    $indent = '  ' * ($_.FullName.Replace($OutDir, '').Split([IO.Path]::DirectorySeparatorChar).Count - 1)
    $name = if ($_.PSIsContainer) { "$($_.Name)/" } else { $_.Name }
    Write-Host "  $indent$name" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Verify: .\VerifyDeploy.ps1 -SiteDir $OutDir" -ForegroundColor Gray
Write-Host "  2. Deploy to Cloudflare Pages or GitHub Pages" -ForegroundColor Gray
Write-Host "  3. Access at: https://your-domain$BasePath" -ForegroundColor Gray
