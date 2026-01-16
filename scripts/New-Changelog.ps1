<#
.SYNOPSIS
    Generates or updates the CHANGELOG.md from git history.

.DESCRIPTION
    Creates a formatted changelog from git commits following
    Conventional Commits specification. Can generate full changelog
    or update with new entries since last tag.

.PARAMETER Version
    Version number for the new release entry.

.PARAMETER OutputPath
    Path to output the changelog. Default: ./CHANGELOG.md

.PARAMETER FromTag
    Generate entries since this git tag. Default: latest tag

.PARAMETER Full
    Generate full changelog from all tags (overwrites existing).

.EXAMPLE
    ./scripts/New-Changelog.ps1 -Version "0.4.0"

.EXAMPLE
    ./scripts/New-Changelog.ps1 -Version "0.5.0" -FromTag "v0.4.0"

.EXAMPLE
    ./scripts/New-Changelog.ps1 -Full
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Version,
    
    [Parameter()]
    [string]$OutputPath = "./CHANGELOG.md",
    
    [Parameter()]
    [string]$FromTag,
    
    [Parameter()]
    [switch]$Full
)

$ErrorActionPreference = "Stop"

function Get-CommitType {
    param([string]$Message)
    
    if ($Message -match "^feat(\(.+\))?:") { return "Added" }
    if ($Message -match "^fix(\(.+\))?:") { return "Fixed" }
    if ($Message -match "^docs(\(.+\))?:") { return "Documentation" }
    if ($Message -match "^refactor(\(.+\))?:") { return "Changed" }
    if ($Message -match "^perf(\(.+\))?:") { return "Performance" }
    if ($Message -match "^test(\(.+\))?:") { return "Testing" }
    if ($Message -match "^security(\(.+\))?:") { return "Security" }
    if ($Message -match "^deprecate(\(.+\))?:") { return "Deprecated" }
    if ($Message -match "^remove(\(.+\))?:") { return "Removed" }
    
    return $null  # Skip chore, style, etc.
}

function Format-CommitMessage {
    param([string]$Message)
    
    # Remove type prefix
    $formatted = $Message -replace "^(feat|fix|docs|refactor|perf|test|security|deprecate|remove)(\(.+\))?\s*:\s*", ""
    
    # Capitalize first letter
    if ($formatted.Length -gt 0) {
        $formatted = $formatted.Substring(0, 1).ToUpper() + $formatted.Substring(1)
    }
    
    return $formatted
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Changelog Generator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Get version from manifest if not provided
if (-not $Version) {
    $manifestPath = "./manifest.json"
    if (Test-Path $manifestPath) {
        $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
        $Version = $manifest.appVersion
        Write-Host "Using version from manifest: $Version" -ForegroundColor Gray
    }
    else {
        $Version = "Unreleased"
    }
}

# Get commits
Write-Host "Analyzing git history..." -ForegroundColor Yellow

if ($FromTag) {
    $range = "$FromTag..HEAD"
}
else {
    # Get latest tag
    $latestTag = git describe --tags --abbrev=0 2>$null
    if ($latestTag) {
        $range = "$latestTag..HEAD"
        Write-Host "  Generating entries since $latestTag" -ForegroundColor Gray
    }
    else {
        $range = ""
        Write-Host "  No tags found, using full history" -ForegroundColor Gray
    }
}

# Get git log
if ($range) {
    $commits = git log $range --pretty=format:"%s|%h|%as" 2>$null
}
else {
    $commits = git log --pretty=format:"%s|%h|%as" 2>$null
}

if (-not $commits) {
    Write-Host "No commits found" -ForegroundColor Yellow
    exit 0
}

# Categorize commits
$categories = @{
    "Added" = @()
    "Changed" = @()
    "Fixed" = @()
    "Security" = @()
    "Deprecated" = @()
    "Removed" = @()
    "Performance" = @()
    "Documentation" = @()
}

$commits | ForEach-Object {
    $parts = $_ -split "\|"
    $message = $parts[0]
    $hash = $parts[1]
    $date = $parts[2]
    
    $type = Get-CommitType -Message $message
    if ($type) {
        $formatted = Format-CommitMessage -Message $message
        $categories[$type] += "- $formatted ($hash)"
    }
}

# Generate changelog content
$date = Get-Date -Format "yyyy-MM-dd"
$content = @"
## [$Version] - $date

"@

$hasContent = $false
foreach ($category in @("Added", "Changed", "Fixed", "Security", "Deprecated", "Removed", "Performance", "Documentation")) {
    if ($categories[$category].Count -gt 0) {
        $content += "`n### $category`n`n"
        $content += ($categories[$category] -join "`n") + "`n"
        $hasContent = $true
    }
}

if (-not $hasContent) {
    $content += "`n- Minor updates and improvements`n"
}

# Update or create changelog
if ($Full -or -not (Test-Path $OutputPath)) {
    # Create new changelog
    $header = @"
# Changelog

All notable changes to SimTreeNav will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

$content
"@
    $header | Out-File $OutputPath -Encoding UTF8
    Write-Host "Created new changelog: $OutputPath" -ForegroundColor Green
}
else {
    # Insert new version at top
    $existing = Get-Content $OutputPath -Raw
    $insertPoint = $existing.IndexOf("`n## [")
    if ($insertPoint -eq -1) {
        $insertPoint = $existing.Length
    }
    
    $newContent = $existing.Substring(0, $insertPoint) + "`n" + $content + $existing.Substring($insertPoint)
    $newContent | Out-File $OutputPath -Encoding UTF8
    Write-Host "Updated changelog: $OutputPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "Changelog entry for version $Version created successfully!" -ForegroundColor Green
