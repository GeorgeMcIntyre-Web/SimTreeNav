<#
.SYNOPSIS
    Verifies a SimTreeNav deployment package is valid and ready for hosting.

.DESCRIPTION
    VerifyDeploy checks that a deployment package:
    - Contains all required files (index.html, manifest.json, assets, data)
    - Has no external network URLs in HTML/JS
    - All referenced assets exist
    - manifest.json schema version is valid
    - Data files are readable JSON

.PARAMETER SiteDir
    Path to the deployment directory to verify.

.PARAMETER Strict
    Enable strict mode - fail on any warning.

.EXAMPLE
    .\VerifyDeploy.ps1 -SiteDir ./deploy/site

.EXAMPLE
    .\VerifyDeploy.ps1 -SiteDir ./deploy/site -Strict
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SiteDir,

    [Parameter()]
    [switch]$Strict
)

# Strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# Verification State
# ============================================================================

$script:errors = @()
$script:warnings = @()
$script:checks = 0
$script:passed = 0

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Check {
    param([string]$Message)
    $script:checks++
    Write-Host "  [?] $Message" -ForegroundColor Cyan -NoNewline
}

function Write-Pass {
    param([string]$Detail = '')
    $script:passed++
    $msg = if ($Detail) { " - $Detail" } else { '' }
    Write-Host "`r  [+] $($args[0] ?? '')$msg" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message, [string]$Detail = '')
    $script:errors += $Message
    $msg = if ($Detail) { " - $Detail" } else { '' }
    Write-Host "`r  [-] $Message$msg" -ForegroundColor Red
}

function Write-Warn {
    param([string]$Message, [string]$Detail = '')
    $script:warnings += $Message
    $msg = if ($Detail) { " - $Detail" } else { '' }
    Write-Host "`r  [!] $Message$msg" -ForegroundColor Yellow
}

function Test-FileExists {
    param([string]$Path, [string]$Name, [switch]$Required)
    
    Write-Check "Checking $Name..."
    
    if (Test-Path $Path) {
        Write-Pass $Name "exists"
        return $true
    }
    
    if ($Required) {
        Write-Fail "$Name missing" $Path
    } else {
        Write-Warn "$Name not found" $Path
    }
    return $false
}

function Test-JsonValid {
    param([string]$Path, [string]$Name)
    
    Write-Check "Validating $Name JSON..."
    
    if (-not (Test-Path $Path)) {
        Write-Fail "$Name not found" $Path
        return $null
    }
    
    try {
        $content = Get-Content $Path -Raw -Encoding UTF8
        $json = $content | ConvertFrom-Json
        Write-Pass $Name "valid JSON"
        return $json
    } catch {
        Write-Fail "$Name invalid JSON" $_.Exception.Message
        return $null
    }
}

function Test-NoExternalUrls {
    param([string]$Path, [string]$Name)
    
    Write-Check "Checking $Name for external URLs..."
    
    if (-not (Test-Path $Path)) {
        Write-Warn "$Name not found"
        return $true
    }
    
    $content = Get-Content $Path -Raw -Encoding UTF8
    
    # Patterns for external URLs (excluding data: URIs and relative paths)
    $externalPatterns = @(
        'https?://[a-zA-Z0-9\-\.]+\.(com|org|net|io|co|dev|app)',
        '//cdn\.',
        '//cdnjs\.',
        '//unpkg\.',
        '//jsdelivr\.',
        '//fonts\.googleapis\.',
        '//ajax\.googleapis\.'
    )
    
    $foundExternal = @()
    
    foreach ($pattern in $externalPatterns) {
        $matches = [regex]::Matches($content, $pattern)
        foreach ($match in $matches) {
            # Skip if in a comment
            if ($content.Substring([Math]::Max(0, $match.Index - 50), 50) -match '<!--' -or 
                $content.Substring([Math]::Max(0, $match.Index - 10), 10) -match '//\s*') {
                continue
            }
            $foundExternal += $match.Value
        }
    }
    
    if ($foundExternal.Count -gt 0) {
        Write-Fail "$Name contains external URLs" ($foundExternal | Select-Object -Unique | Join-String -Separator ', ')
        return $false
    }
    
    Write-Pass $Name "no external URLs"
    return $true
}

function Test-AssetReferences {
    param([string]$HtmlPath, [string]$BaseDir)
    
    Write-Check "Checking asset references..."
    
    if (-not (Test-Path $HtmlPath)) {
        Write-Warn "index.html not found"
        return $true
    }
    
    $content = Get-Content $HtmlPath -Raw -Encoding UTF8
    $missingAssets = @()
    
    # Find CSS references
    $cssMatches = [regex]::Matches($content, 'href="([^"]+\.css)"')
    foreach ($match in $cssMatches) {
        $cssPath = $match.Groups[1].Value
        if (-not $cssPath.StartsWith('http') -and -not $cssPath.StartsWith('//')) {
            $fullPath = Join-Path $BaseDir $cssPath
            if (-not (Test-Path $fullPath)) {
                $missingAssets += "CSS: $cssPath"
            }
        }
    }
    
    # Find JS references
    $jsMatches = [regex]::Matches($content, 'src="([^"]+\.js)"')
    foreach ($match in $jsMatches) {
        $jsPath = $match.Groups[1].Value
        if (-not $jsPath.StartsWith('http') -and -not $jsPath.StartsWith('//')) {
            $fullPath = Join-Path $BaseDir $jsPath
            if (-not (Test-Path $fullPath)) {
                $missingAssets += "JS: $jsPath"
            }
        }
    }
    
    if ($missingAssets.Count -gt 0) {
        Write-Fail "Missing assets" ($missingAssets -join ', ')
        return $false
    }
    
    Write-Pass "Asset references" "all assets exist"
    return $true
}

function Test-ManifestSchema {
    param($Manifest)
    
    Write-Check "Validating manifest schema..."
    
    if (-not $Manifest) {
        Write-Fail "Manifest is null"
        return $false
    }
    
    $requiredFields = @('schemaVersion')
    $missingFields = @()
    
    foreach ($field in $requiredFields) {
        if (-not $Manifest.PSObject.Properties[$field]) {
            $missingFields += $field
        }
    }
    
    if ($missingFields.Count -gt 0) {
        Write-Fail "Manifest missing required fields" ($missingFields -join ', ')
        return $false
    }
    
    # Check schema version
    $version = $Manifest.schemaVersion
    if (-not ($version -match '^\d+\.\d+\.\d+$')) {
        Write-Fail "Invalid schema version format" $version
        return $false
    }
    
    # Check for expected structure
    if ($Manifest.viewer -and $Manifest.viewer.basePath) {
        Write-Pass "Manifest schema" "version $version, basePath: $($Manifest.viewer.basePath)"
    } else {
        Write-Pass "Manifest schema" "version $version"
    }
    
    return $true
}

function Test-DataFiles {
    param([string]$DataDir, $ManifestFiles)
    
    Write-Check "Checking data files..."
    
    if (-not (Test-Path $DataDir)) {
        Write-Warn "Data directory not found" $DataDir
        return $true
    }
    
    $dataFiles = Get-ChildItem $DataDir -Filter '*.json' -File
    
    if ($dataFiles.Count -eq 0) {
        Write-Warn "No data files found"
        return $true
    }
    
    $invalidFiles = @()
    
    foreach ($file in $dataFiles) {
        try {
            $content = Get-Content $file.FullName -Raw -Encoding UTF8
            $null = $content | ConvertFrom-Json
        } catch {
            $invalidFiles += $file.Name
        }
    }
    
    if ($invalidFiles.Count -gt 0) {
        Write-Fail "Invalid data files" ($invalidFiles -join ', ')
        return $false
    }
    
    Write-Pass "Data files" "$($dataFiles.Count) valid JSON files"
    return $true
}

function Test-OfflineCapability {
    param([string]$SiteDir)
    
    Write-Check "Checking offline capability..."
    
    # Check all HTML and JS files for fetch/XMLHttpRequest to external URLs
    $files = Get-ChildItem $SiteDir -Include '*.html', '*.js' -Recurse -File
    $externalFetches = @()
    
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        
        # Look for fetch calls to external URLs
        if ($content -match 'fetch\s*\(\s*[''"]https?://') {
            $externalFetches += "$($file.Name): external fetch"
        }
        
        # Look for XMLHttpRequest to external URLs
        if ($content -match '\.open\s*\(\s*[''"][^''"]+''\s*,\s*[''"]https?://') {
            $externalFetches += "$($file.Name): external XHR"
        }
    }
    
    if ($externalFetches.Count -gt 0) {
        Write-Fail "External network calls found" ($externalFetches -join ', ')
        return $false
    }
    
    Write-Pass "Offline capability" "no external network calls"
    return $true
}

# ============================================================================
# Main Verification
# ============================================================================

Write-Host ""
Write-Host "SimTreeNav Deployment Verification v0.6.0" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verifying: $SiteDir" -ForegroundColor White
Write-Host ""

# Check if directory exists
if (-not (Test-Path $SiteDir)) {
    Write-Host "  [-] Site directory not found: $SiteDir" -ForegroundColor Red
    exit 1
}

Write-Host "Required Files:" -ForegroundColor White

# 1. Check required files
$indexExists = Test-FileExists -Path (Join-Path $SiteDir 'index.html') -Name 'index.html' -Required

Write-Host ""
Write-Host "Manifest Validation:" -ForegroundColor White

# 2. Validate manifest
$manifestPath = Join-Path $SiteDir 'manifest.json'
$manifest = Test-JsonValid -Path $manifestPath -Name 'manifest.json'
if ($manifest) {
    Test-ManifestSchema -Manifest $manifest | Out-Null
}

Write-Host ""
Write-Host "Asset Verification:" -ForegroundColor White

# 3. Check assets directory
$assetsDir = Join-Path $SiteDir 'assets'
Test-FileExists -Path $assetsDir -Name 'assets directory' | Out-Null
Test-FileExists -Path (Join-Path $assetsDir 'css') -Name 'assets/css' | Out-Null
Test-FileExists -Path (Join-Path $assetsDir 'js') -Name 'assets/js' | Out-Null

# 4. Check asset references
Test-AssetReferences -HtmlPath (Join-Path $SiteDir 'index.html') -BaseDir $SiteDir | Out-Null

Write-Host ""
Write-Host "Data Verification:" -ForegroundColor White

# 5. Check data files
$dataDir = Join-Path $SiteDir 'data'
Test-FileExists -Path $dataDir -Name 'data directory' | Out-Null
Test-DataFiles -DataDir $dataDir -ManifestFiles $manifest.files | Out-Null

Write-Host ""
Write-Host "Security Checks:" -ForegroundColor White

# 6. Check for external URLs
$indexPath = Join-Path $SiteDir 'index.html'
Test-NoExternalUrls -Path $indexPath -Name 'index.html' | Out-Null

$jsFiles = Get-ChildItem (Join-Path $SiteDir 'assets' 'js') -Filter '*.js' -File -ErrorAction SilentlyContinue
foreach ($jsFile in $jsFiles) {
    Test-NoExternalUrls -Path $jsFile.FullName -Name $jsFile.Name | Out-Null
}

Write-Host ""
Write-Host "Offline Capability:" -ForegroundColor White

# 7. Check offline capability
Test-OfflineCapability -SiteDir $SiteDir | Out-Null

# ============================================================================
# Results Summary
# ============================================================================

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Verification Results" -ForegroundColor White
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Checks:   $script:checks" -ForegroundColor White
Write-Host "  Passed:   $script:passed" -ForegroundColor Green
Write-Host "  Warnings: $($script:warnings.Count)" -ForegroundColor Yellow
Write-Host "  Errors:   $($script:errors.Count)" -ForegroundColor Red
Write-Host ""

if ($script:errors.Count -gt 0) {
    Write-Host "VERIFICATION FAILED" -ForegroundColor Red
    Write-Host ""
    Write-Host "Errors:" -ForegroundColor Red
    foreach ($error in $script:errors) {
        Write-Host "  - $error" -ForegroundColor Red
    }
    exit 1
}

if ($Strict -and $script:warnings.Count -gt 0) {
    Write-Host "VERIFICATION FAILED (Strict Mode)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Warnings treated as errors:" -ForegroundColor Yellow
    foreach ($warning in $script:warnings) {
        Write-Host "  - $warning" -ForegroundColor Yellow
    }
    exit 1
}

if ($script:warnings.Count -gt 0) {
    Write-Host "VERIFICATION PASSED WITH WARNINGS" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Warnings:" -ForegroundColor Yellow
    foreach ($warning in $script:warnings) {
        Write-Host "  - $warning" -ForegroundColor Yellow
    }
} else {
    Write-Host "VERIFICATION PASSED" -ForegroundColor Green
}

Write-Host ""
Write-Host "Deployment is ready for hosting." -ForegroundColor Green
exit 0
