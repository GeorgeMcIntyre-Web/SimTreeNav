<#
.SYNOPSIS
    Pester tests for DeployPack.ps1

.DESCRIPTION
    Validates that DeployPack.ps1 correctly creates deployment packages
    with all required files and proper structure.

.NOTES
    Run with: Invoke-Pester -Path ./tests/DeployPack.Tests.ps1
#>

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:TestOutputDir = Join-Path $env:TEMP "simtreenav-tests-$(Get-Random)"
    $script:BundleDir = Join-Path $script:TestOutputDir "bundle"
    $script:DeployDir = Join-Path $script:TestOutputDir "deploy"
    
    # Create test bundle with minimal data
    New-Item -ItemType Directory -Path $script:BundleDir -Force | Out-Null
    
    # Create minimal nodes.json
    @{
        root = @{
            id = 1
            name = "Test Project"
            nodeType = "Project"
            children = @(
                @{ id = 2; name = "Child 1"; nodeType = "Station"; children = @() }
                @{ id = 3; name = "Child 2"; nodeType = "Cell"; children = @() }
            )
        }
    } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $script:BundleDir "nodes.json") -Encoding UTF8
    
    # Create minimal timeline.json
    @{
        schemaVersion = "0.6.0"
        snapshots = @(
            @{ index = 0; timestamp = (Get-Date).ToString('o'); nodeCount = 3 }
        )
    } | ConvertTo-Json | Set-Content (Join-Path $script:BundleDir "timeline.json") -Encoding UTF8
    
    # Create minimal diff.json
    @{
        schemaVersion = "0.6.0"
        changes = @()
    } | ConvertTo-Json | Set-Content (Join-Path $script:BundleDir "diff.json") -Encoding UTF8
}

AfterAll {
    # Cleanup
    if (Test-Path $script:TestOutputDir) {
        Remove-Item $script:TestOutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "DeployPack.ps1" {
    
    BeforeEach {
        # Clean deploy directory before each test
        if (Test-Path $script:DeployDir) {
            Remove-Item $script:DeployDir -Recurse -Force
        }
    }
    
    Context "Output Structure" {
        
        It "Creates output directory" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "test-site"
            
            $script:DeployDir | Should -Exist
        }
        
        It "Creates manifest.json" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "test-site"
            
            $manifestPath = Join-Path $script:DeployDir "manifest.json"
            $manifestPath | Should -Exist
            
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            $manifest.schemaVersion | Should -Be "0.6.0"
            $manifest.siteName | Should -Be "test-site"
        }
        
        It "Creates data directory with JSON files" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "test-site"
            
            $dataDir = Join-Path $script:DeployDir "data"
            $dataDir | Should -Exist
            
            Join-Path $dataDir "nodes.json" | Should -Exist
            Join-Path $dataDir "timeline.json" | Should -Exist
        }
        
        It "Creates Cloudflare configuration files" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "test-site"
            
            Join-Path $script:DeployDir "_headers" | Should -Exist
            Join-Path $script:DeployDir "_redirects" | Should -Exist
        }
        
        It "Creates GitHub Pages configuration" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "test-site"
            
            Join-Path $script:DeployDir ".nojekyll" | Should -Exist
            Join-Path $script:DeployDir "404.html" | Should -Exist
        }
    }
    
    Context "BasePath Configuration" {
        
        It "Sets default basePath from SiteName" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "my-project"
            
            $manifestPath = Join-Path $script:DeployDir "manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            
            $manifest.viewer.basePath | Should -Be "/my-project/"
        }
        
        It "Uses custom basePath when provided" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "my-project" `
                -BasePath "/custom/path/"
            
            $manifestPath = Join-Path $script:DeployDir "manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            
            $manifest.viewer.basePath | Should -Be "/custom/path/"
        }
        
        It "Normalizes basePath with leading and trailing slashes" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "my-project" `
                -BasePath "noSlash"
            
            $manifestPath = Join-Path $script:DeployDir "manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            
            $manifest.viewer.basePath | Should -Match "^/"
            $manifest.viewer.basePath | Should -Match "/$"
        }
    }
    
    Context "Secure Mode" {
        
        It "Creates SECURITY.md in Secure mode" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "test-site" `
                -Mode Secure
            
            Join-Path $script:DeployDir "SECURITY.md" | Should -Exist
        }
        
        It "Sets mode in manifest" {
            $deployPackScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
            
            & $deployPackScript `
                -BundlePath $script:BundleDir `
                -OutDir $script:DeployDir `
                -SiteName "test-site" `
                -Mode Secure
            
            $manifestPath = Join-Path $script:DeployDir "manifest.json"
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            
            $manifest.mode | Should -Be "Secure"
        }
    }
}
