<#
.SYNOPSIS
    Smoke tests for the SimTreeNav viewer

.DESCRIPTION
    Validates that the viewer HTML has correct structure and references
    without requiring a browser.

.NOTES
    Run with: Invoke-Pester -Path ./tests/ViewerSmoke.Tests.ps1
#>

BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:ViewerDir = Join-Path $script:ProjectRoot "viewer"
}

Describe "Viewer Smoke Tests" {
    
    Context "File Structure" {
        
        It "Has index.html" {
            Join-Path $script:ViewerDir "index.html" | Should -Exist
        }
        
        It "Has CSS file" {
            Join-Path $script:ViewerDir "assets/css/ui.css" | Should -Exist
        }
        
        It "Has all required JS modules" {
            $requiredModules = @(
                "state.js",
                "dataLoader.js",
                "treeView.js",
                "timelineView.js",
                "inspectorView.js",
                "app.js"
            )
            
            foreach ($module in $requiredModules) {
                $path = Join-Path $script:ViewerDir "assets/js/$module"
                $path | Should -Exist -Because "Module $module is required"
            }
        }
    }
    
    Context "HTML Structure" {
        
        BeforeAll {
            $script:IndexHtml = Get-Content (Join-Path $script:ViewerDir "index.html") -Raw
        }
        
        It "Has DOCTYPE declaration" {
            $script:IndexHtml | Should -Match "<!DOCTYPE html>"
        }
        
        It "Has proper HTML structure" {
            $script:IndexHtml | Should -Match "<html"
            $script:IndexHtml | Should -Match "<head>"
            $script:IndexHtml | Should -Match "<body>"
        }
        
        It "References CSS file" {
            $script:IndexHtml | Should -Match 'href="assets/css/ui\.css"'
        }
        
        It "References all JS modules in correct order" {
            # Order matters for dependencies
            $moduleOrder = @("state.js", "dataLoader.js", "treeView.js", "timelineView.js", "inspectorView.js", "app.js")
            
            $lastPos = -1
            foreach ($module in $moduleOrder) {
                $pos = $script:IndexHtml.IndexOf($module)
                $pos | Should -BeGreaterThan $lastPos -Because "$module should come after previous modules"
                $lastPos = $pos
            }
        }
        
        It "Has app container" {
            $script:IndexHtml | Should -Match 'id="app"'
        }
        
        It "Has loading overlay" {
            $script:IndexHtml | Should -Match 'id="loading-overlay"'
        }
        
        It "Has tree panel" {
            $script:IndexHtml | Should -Match 'id="tree-panel"'
        }
        
        It "Has center panel" {
            $script:IndexHtml | Should -Match 'id="center-panel"'
        }
        
        It "Has inspector panel" {
            $script:IndexHtml | Should -Match 'id="inspector-panel"'
        }
        
        It "Has search input" {
            $script:IndexHtml | Should -Match 'id="search-input"'
        }
        
        It "Has changed-only toggle" {
            $script:IndexHtml | Should -Match 'id="changed-only-toggle"'
        }
    }
    
    Context "No External Dependencies" {
        
        BeforeAll {
            $script:IndexHtml = Get-Content (Join-Path $script:ViewerDir "index.html") -Raw
            $script:JsFiles = Get-ChildItem (Join-Path $script:ViewerDir "assets/js") -Filter "*.js" |
                ForEach-Object { Get-Content $_.FullName -Raw }
        }
        
        It "HTML has no external CDN links" {
            $externalPatterns = @(
                'cdn\.cloudflare\.com',
                'cdnjs\.',
                'unpkg\.com',
                'jsdelivr\.net',
                'googleapis\.com'
            )
            
            foreach ($pattern in $externalPatterns) {
                $script:IndexHtml | Should -Not -Match $pattern
            }
        }
        
        It "JS has no external fetch calls" {
            foreach ($js in $script:JsFiles) {
                $js | Should -Not -Match 'fetch\s*\(\s*[''"]https?://'
            }
        }
        
        It "JS has no external script loading" {
            foreach ($js in $script:JsFiles) {
                $js | Should -Not -Match 'createElement\s*\(\s*[''"]script[''"]'
            }
        }
    }
    
    Context "JS Module Structure" {
        
        It "state.js exports AppState" {
            $content = Get-Content (Join-Path $script:ViewerDir "assets/js/state.js") -Raw
            $content | Should -Match "AppState"
        }
        
        It "dataLoader.js exports DataLoader" {
            $content = Get-Content (Join-Path $script:ViewerDir "assets/js/dataLoader.js") -Raw
            $content | Should -Match "DataLoader"
        }
        
        It "treeView.js exports TreeView" {
            $content = Get-Content (Join-Path $script:ViewerDir "assets/js/treeView.js") -Raw
            $content | Should -Match "TreeView"
        }
        
        It "timelineView.js exports TimelineView" {
            $content = Get-Content (Join-Path $script:ViewerDir "assets/js/timelineView.js") -Raw
            $content | Should -Match "TimelineView"
        }
        
        It "inspectorView.js exports InspectorView" {
            $content = Get-Content (Join-Path $script:ViewerDir "assets/js/inspectorView.js") -Raw
            $content | Should -Match "InspectorView"
        }
        
        It "app.js exports App" {
            $content = Get-Content (Join-Path $script:ViewerDir "assets/js/app.js") -Raw
            $content | Should -Match "App"
        }
    }
    
    Context "CSS Structure" {
        
        BeforeAll {
            $script:CssContent = Get-Content (Join-Path $script:ViewerDir "assets/css/ui.css") -Raw
        }
        
        It "Defines CSS variables" {
            $script:CssContent | Should -Match ":root\s*{"
            $script:CssContent | Should -Match "--bg-primary"
            $script:CssContent | Should -Match "--accent-color"
        }
        
        It "Has responsive styles" {
            $script:CssContent | Should -Match "@media"
        }
        
        It "Styles app layout" {
            $script:CssContent | Should -Match "#app"
            $script:CssContent | Should -Match "\.panel"
        }
        
        It "Styles tree view" {
            $script:CssContent | Should -Match "\.tree-row"
            $script:CssContent | Should -Match "\.tree-toggle"
        }
        
        It "Styles timeline view" {
            $script:CssContent | Should -Match "\.timeline-"
        }
        
        It "Styles inspector view" {
            $script:CssContent | Should -Match "\.inspector-"
        }
    }
}

Describe "DemoStory Integration" {
    
    BeforeAll {
        $script:TestOutputDir = Join-Path $env:TEMP "simtreenav-demo-test-$(Get-Random)"
    }
    
    AfterAll {
        if (Test-Path $script:TestOutputDir) {
            Remove-Item $script:TestOutputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    It "DemoStory generates valid bundle" {
        $demoScript = Join-Path $script:ProjectRoot "DemoStory.ps1"
        
        & $demoScript -NodeCount 50 -OutDir $script:TestOutputDir -NoOpen
        
        # Check all required files exist
        Join-Path $script:TestOutputDir "manifest.json" | Should -Exist
        Join-Path $script:TestOutputDir "index.html" | Should -Exist
        Join-Path $script:TestOutputDir "data/nodes.json" | Should -Exist
        Join-Path $script:TestOutputDir "data/timeline.json" | Should -Exist
    }
    
    It "Generated bundle passes verification" {
        # First run DemoStory
        $demoScript = Join-Path $script:ProjectRoot "DemoStory.ps1"
        & $demoScript -NodeCount 50 -OutDir $script:TestOutputDir -NoOpen
        
        # Then verify
        $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
        & $verifyScript -SiteDir $script:TestOutputDir
        
        $LASTEXITCODE | Should -Be 0
    }
}

Describe "DeployPack Integration" {
    
    BeforeAll {
        $script:TestOutputDir = Join-Path $env:TEMP "simtreenav-deploy-test-$(Get-Random)"
        $script:BundleDir = Join-Path $script:TestOutputDir "bundle"
        $script:DeployDir = Join-Path $script:TestOutputDir "deploy"
    }
    
    AfterAll {
        if (Test-Path $script:TestOutputDir) {
            Remove-Item $script:TestOutputDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    It "Full workflow: DemoStory -> DeployPack -> VerifyDeploy" {
        # Step 1: Generate demo bundle
        $demoScript = Join-Path $script:ProjectRoot "DemoStory.ps1"
        & $demoScript -NodeCount 100 -OutDir $script:BundleDir -NoOpen
        
        # Step 2: Create deployment package
        $deployScript = Join-Path $script:ProjectRoot "DeployPack.ps1"
        & $deployScript -BundlePath $script:BundleDir -OutDir $script:DeployDir -SiteName "test-project"
        
        # Step 3: Verify deployment
        $verifyScript = Join-Path $script:ProjectRoot "VerifyDeploy.ps1"
        & $verifyScript -SiteDir $script:DeployDir
        
        $LASTEXITCODE | Should -Be 0
    }
}
