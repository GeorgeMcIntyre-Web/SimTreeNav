<#
.SYNOPSIS
    Builds a release package for SimTreeNav.

.DESCRIPTION
    Creates a deployable release package containing all necessary files.
    Reads version information from manifest.json and generates release artifacts.

.PARAMETER OutputPath
    Directory to output the release package. Default: ./dist

.PARAMETER SkipTests
    Skip running tests before building. Not recommended for production releases.

.EXAMPLE
    ./scripts/Build-Release.ps1

.EXAMPLE
    ./scripts/Build-Release.ps1 -OutputPath ./release -SkipTests
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = "./dist",
    
    [Parameter()]
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

# Get script location
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptRoot

# Change to project root
Push-Location $ProjectRoot

try {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SimTreeNav Release Builder" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    
    # Load manifest
    Write-Host "[1/6] Loading manifest..." -ForegroundColor Yellow
    $manifestPath = Join-Path $ProjectRoot "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        throw "manifest.json not found at $manifestPath"
    }
    
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    $version = $manifest.appVersion
    $appName = $manifest.appName
    
    Write-Host "  App Name: $appName" -ForegroundColor Gray
    Write-Host "  Version: $version" -ForegroundColor Gray
    Write-Host "  Schema Version: $($manifest.schemaVersion)" -ForegroundColor Gray
    Write-Host ""
    
    # Run linter
    Write-Host "[2/6] Running PSScriptAnalyzer..." -ForegroundColor Yellow
    $settingsPath = Join-Path $ProjectRoot "PSScriptAnalyzerSettings.psd1"
    if (Get-Module -ListAvailable -Name PSScriptAnalyzer) {
        $lintResults = Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings $settingsPath -Severity Error
        if ($lintResults) {
            Write-Warning "Linter found issues:"
            $lintResults | Format-Table -AutoSize
            throw "PSScriptAnalyzer found $($lintResults.Count) error(s)"
        }
        Write-Host "  ✓ Linter passed" -ForegroundColor Green
    }
    else {
        Write-Warning "  PSScriptAnalyzer not installed, skipping..."
    }
    Write-Host ""
    
    # Run tests
    if (-not $SkipTests) {
        Write-Host "[3/6] Running Pester tests..." -ForegroundColor Yellow
        $testsPath = Join-Path $ProjectRoot "tests"
        if ((Test-Path $testsPath) -and (Get-ChildItem $testsPath -Filter "*.Tests.ps1" -Recurse)) {
            if (Get-Module -ListAvailable -Name Pester) {
                $testResults = Invoke-Pester -Path $testsPath -PassThru -Output Minimal
                if ($testResults.FailedCount -gt 0) {
                    throw "Pester tests failed: $($testResults.FailedCount) failure(s)"
                }
                Write-Host "  ✓ All tests passed ($($testResults.PassedCount) tests)" -ForegroundColor Green
            }
            else {
                Write-Warning "  Pester not installed, skipping tests..."
            }
        }
        else {
            Write-Host "  No tests found, skipping..." -ForegroundColor Gray
        }
    }
    else {
        Write-Host "[3/6] Skipping tests (not recommended for releases)" -ForegroundColor Yellow
    }
    Write-Host ""
    
    # Create output directory
    Write-Host "[4/6] Preparing output directory..." -ForegroundColor Yellow
    $outputDir = Join-Path $ProjectRoot $OutputPath
    if (Test-Path $outputDir) {
        Remove-Item $outputDir -Recurse -Force
    }
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "  Output: $outputDir" -ForegroundColor Gray
    Write-Host ""
    
    # Create release package
    Write-Host "[5/6] Creating release package..." -ForegroundColor Yellow
    
    $packageName = "$appName-$version"
    $packageDir = Join-Path $outputDir $packageName
    New-Item -ItemType Directory -Path $packageDir -Force | Out-Null
    
    # Copy files according to manifest
    $includes = @(
        @{ Source = "src"; Dest = "src" },
        @{ Source = "queries"; Dest = "queries" },
        @{ Source = "docs"; Dest = "docs" },
        @{ Source = "scripts"; Dest = "scripts" },
        @{ Source = "manifest.json"; Dest = "manifest.json" },
        @{ Source = "README.md"; Dest = "README.md" },
        @{ Source = "CHANGELOG.md"; Dest = "CHANGELOG.md" },
        @{ Source = "CONTRIBUTING.md"; Dest = "CONTRIBUTING.md" },
        @{ Source = "SECURITY.md"; Dest = "SECURITY.md" },
        @{ Source = "LICENSE"; Dest = "LICENSE" },
        @{ Source = "PSScriptAnalyzerSettings.psd1"; Dest = "PSScriptAnalyzerSettings.psd1" }
    )
    
    foreach ($item in $includes) {
        $sourcePath = Join-Path $ProjectRoot $item.Source
        $destPath = Join-Path $packageDir $item.Dest
        
        if (Test-Path $sourcePath) {
            if ((Get-Item $sourcePath).PSIsContainer) {
                Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force
                $fileCount = (Get-ChildItem $sourcePath -Recurse -File).Count
                Write-Host "  Copied $($item.Source) ($fileCount files)" -ForegroundColor Gray
            }
            else {
                Copy-Item -Path $sourcePath -Destination $destPath -Force
                Write-Host "  Copied $($item.Source)" -ForegroundColor Gray
            }
        }
        else {
            Write-Warning "  Not found: $($item.Source)"
        }
    }
    
    # Remove test files from package
    Get-ChildItem -Path $packageDir -Recurse -Filter "*.Tests.ps1" | Remove-Item -Force
    
    # Create ZIP archive
    $zipPath = Join-Path $outputDir "$packageName.zip"
    Compress-Archive -Path $packageDir -DestinationPath $zipPath -Force
    Write-Host ""
    
    # Generate checksums
    Write-Host "[6/6] Generating checksums..." -ForegroundColor Yellow
    $hash = Get-FileHash -Path $zipPath -Algorithm SHA256
    $checksumFile = Join-Path $outputDir "checksums.sha256"
    "$($hash.Hash)  $packageName.zip" | Out-File $checksumFile -Encoding UTF8
    Write-Host "  SHA256: $($hash.Hash.Substring(0, 16))..." -ForegroundColor Gray
    Write-Host ""
    
    # Summary
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "  Release Build Complete!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Package: $zipPath" -ForegroundColor White
    Write-Host "  Size: $([math]::Round((Get-Item $zipPath).Length / 1KB, 2)) KB" -ForegroundColor White
    Write-Host "  Checksum: $checksumFile" -ForegroundColor White
    Write-Host ""
    
    # Output version for CI
    Write-Output "RELEASE_VERSION=$version"
    Write-Output "RELEASE_FILE=$zipPath"
}
catch {
    Write-Error "Build failed: $_"
    exit 1
}
finally {
    Pop-Location
}
