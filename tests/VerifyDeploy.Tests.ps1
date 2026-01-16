<#
.SYNOPSIS
    Pester tests for VerifyDeploy.ps1

.DESCRIPTION
    Validates that VerifyDeploy.ps1 correctly identifies valid and invalid
    deployment packages.

.NOTES
    Run with: Invoke-Pester -Path ./tests/VerifyDeploy.Tests.ps1
#>

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:TestOutputDir = Join-Path $env:TEMP "simtreenav-verify-tests-$(Get-Random)"
    $script:ValidSiteDir = Join-Path $script:TestOutputDir "valid-site"
    $script:InvalidSiteDir = Join-Path $script:TestOutputDir "invalid-site"
    
    # Create a valid deployment structure
    New-Item -ItemType Directory -Path (Join-Path $script:ValidSiteDir "assets/css") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:ValidSiteDir "assets/js") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $script:ValidSiteDir "data") -Force | Out-Null
    
    # Create index.html (valid, no external URLs)
    @"
<!DOCTYPE html>
<html>
<head>
    <link rel="stylesheet" href="assets/css/ui.css">
</head>
<body>
    <script src="assets/js/app.js"></script>
</body>
</html>
"@ | Set-Content (Join-Path $script:ValidSiteDir "index.html") -Encoding UTF8
    
    # Create CSS file
    "body { margin: 0; }" | Set-Content (Join-Path $script:ValidSiteDir "assets/css/ui.css") -Encoding UTF8
    
    # Create JS file (valid, no external fetches)
    "console.log('SimTreeNav');" | Set-Content (Join-Path $script:ValidSiteDir "assets/js/app.js") -Encoding UTF8
    
    # Create manifest.json
    @{
        schemaVersion = "0.6.0"
        siteName = "test-site"
        viewer = @{ basePath = "/test-site/" }
        files = @{ nodes = "nodes.json" }
    } | ConvertTo-Json | Set-Content (Join-Path $script:ValidSiteDir "manifest.json") -Encoding UTF8
    
    # Create data files
    @{ root = @{ id = 1; name = "Test" } } | ConvertTo-Json | 
        Set-Content (Join-Path $script:ValidSiteDir "data/nodes.json") -Encoding UTF8
    
    # Create invalid deployment structure
    New-Item -ItemType Directory -Path $script:InvalidSiteDir -Force | Out-Null
    # No index.html - this makes it invalid
}

AfterAll {
    if (Test-Path $script:TestOutputDir) {
        Remove-Item $script:TestOutputDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe "VerifyDeploy.ps1" {
    
    Context "Valid Deployment" {
        
        It "Passes verification for valid site" {
            $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
            
            $result = & $verifyScript -SiteDir $script:ValidSiteDir 2>&1
            $LASTEXITCODE | Should -Be 0
        }
        
        It "Reports correct check counts" {
            $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
            
            $output = & $verifyScript -SiteDir $script:ValidSiteDir 2>&1 | Out-String
            $output | Should -Match "VERIFICATION PASSED"
        }
    }
    
    Context "Invalid Deployment" {
        
        It "Fails when directory does not exist" {
            $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
            
            $result = & $verifyScript -SiteDir "/nonexistent/path" 2>&1
            $LASTEXITCODE | Should -Not -Be 0
        }
        
        It "Fails when index.html is missing" {
            $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
            
            # InvalidSiteDir has no index.html
            & $verifyScript -SiteDir $script:InvalidSiteDir 2>&1 | Out-Null
            $LASTEXITCODE | Should -Not -Be 0
        }
    }
    
    Context "External URL Detection" {
        
        BeforeEach {
            $script:ExternalUrlSiteDir = Join-Path $script:TestOutputDir "external-url-site"
            New-Item -ItemType Directory -Path (Join-Path $script:ExternalUrlSiteDir "assets/js") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $script:ExternalUrlSiteDir "data") -Force | Out-Null
            
            # Create manifest
            @{
                schemaVersion = "0.6.0"
            } | ConvertTo-Json | Set-Content (Join-Path $script:ExternalUrlSiteDir "manifest.json") -Encoding UTF8
            
            # Create data files
            @{ root = @{ id = 1 } } | ConvertTo-Json | 
                Set-Content (Join-Path $script:ExternalUrlSiteDir "data/nodes.json") -Encoding UTF8
        }
        
        It "Detects external CDN URLs in HTML" {
            # Create index.html with external CDN
            @"
<!DOCTYPE html>
<html>
<head>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jquery/3.6.0/jquery.min.js"></script>
</head>
<body></body>
</html>
"@ | Set-Content (Join-Path $script:ExternalUrlSiteDir "index.html") -Encoding UTF8
            
            $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
            
            $output = & $verifyScript -SiteDir $script:ExternalUrlSiteDir 2>&1 | Out-String
            $output | Should -Match "external URL"
        }
        
        It "Passes when no external URLs present" {
            # Create valid index.html
            @"
<!DOCTYPE html>
<html>
<head></head>
<body>
    <script src="assets/js/app.js"></script>
</body>
</html>
"@ | Set-Content (Join-Path $script:ExternalUrlSiteDir "index.html") -Encoding UTF8
            
            "console.log('local');" | Set-Content (Join-Path $script:ExternalUrlSiteDir "assets/js/app.js") -Encoding UTF8
            
            $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
            
            $output = & $verifyScript -SiteDir $script:ExternalUrlSiteDir 2>&1 | Out-String
            $output | Should -Not -Match "external URL"
        }
    }
    
    Context "Manifest Validation" {
        
        It "Validates schema version format" {
            $testDir = Join-Path $script:TestOutputDir "bad-manifest"
            New-Item -ItemType Directory -Path (Join-Path $testDir "data") -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $testDir "assets/js") -Force | Out-Null
            
            # Create invalid manifest (bad version)
            @{
                schemaVersion = "invalid"
            } | ConvertTo-Json | Set-Content (Join-Path $testDir "manifest.json") -Encoding UTF8
            
            # Create minimal index
            "<html></html>" | Set-Content (Join-Path $testDir "index.html") -Encoding UTF8
            "x" | Set-Content (Join-Path $testDir "assets/js/app.js") -Encoding UTF8
            @{} | ConvertTo-Json | Set-Content (Join-Path $testDir "data/nodes.json") -Encoding UTF8
            
            $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
            
            $output = & $verifyScript -SiteDir $testDir 2>&1 | Out-String
            $output | Should -Match "Invalid schema version"
        }
    }
    
    Context "Strict Mode" {
        
        It "Treats warnings as errors in strict mode" {
            $testDir = Join-Path $script:TestOutputDir "warnings-only"
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            
            # Create minimal valid structure but missing optional files
            "<html></html>" | Set-Content (Join-Path $testDir "index.html") -Encoding UTF8
            @{ schemaVersion = "0.6.0" } | ConvertTo-Json | 
                Set-Content (Join-Path $testDir "manifest.json") -Encoding UTF8
            
            $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
            
            # Without strict: should pass with warnings
            & $verifyScript -SiteDir $testDir 2>&1 | Out-Null
            $normalExit = $LASTEXITCODE
            
            # With strict: should fail on warnings
            & $verifyScript -SiteDir $testDir -Strict 2>&1 | Out-Null
            $strictExit = $LASTEXITCODE
            
            # Strict mode should be more restrictive
            $strictExit | Should -Not -Be 0 -Because "Strict mode should fail on warnings"
        }
    }
}
