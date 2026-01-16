# ViewerDataLoader Pester Tests
# Tests for the viewer's data loading functionality

BeforeAll {
    $enginePath = Join-Path $PSScriptRoot "..\src\powershell\ws2c-engines"
    . "$enginePath\New-DemoStory.ps1"
    . "$enginePath\Export-Bundle.ps1"
    
    # Create test data directory
    $script:testDataDir = Join-Path $PSScriptRoot "test-data"
    if (-not (Test-Path $testDataDir)) {
        New-Item -ItemType Directory -Path $testDataDir | Out-Null
    }
    
    # Generate demo data for testing
    $script:demoDir = Join-Path $testDataDir "viewer-demo"
    New-DemoStory -OutDir $demoDir -Seed 123
}

AfterAll {
    if (Test-Path $script:testDataDir) {
        Remove-Item -Path $testDataDir -Recurse -Force
    }
}

Describe "Viewer Data Structure" {
    Context "Bundle Format" {
        It "Should have valid JSON structure" {
            $bundlePath = Join-Path $script:demoDir "bundle.json"
            
            { Get-Content $bundlePath | ConvertFrom-Json } | Should -Not -Throw
        }
        
        It "Should have nodes array" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            $bundle.nodes | Should -BeOfType [System.Array]
        }
        
        It "Should have compliance object with required fields" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            $bundle.compliance.PSObject.Properties.Name | Should -Contain "score"
            $bundle.compliance.PSObject.Properties.Name | Should -Contain "violations"
            $bundle.compliance.PSObject.Properties.Name | Should -Contain "missing"
            $bundle.compliance.PSObject.Properties.Name | Should -Contain "perRule"
        }
        
        It "Should have similar object with candidates array" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            $bundle.similar.PSObject.Properties.Name | Should -Contain "candidates"
            $bundle.similar.candidates | Should -BeOfType [System.Array]
        }
        
        It "Should have anomalies object with anomalies array" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            $bundle.anomalies.PSObject.Properties.Name | Should -Contain "anomalies"
            $bundle.anomalies.anomalies | Should -BeOfType [System.Array]
        }
    }
    
    Context "Node Structure" {
        It "Should have id field for each node" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            foreach ($node in $bundle.nodes) {
                $node.PSObject.Properties.Name | Should -Contain "id"
            }
        }
        
        It "Should have name field for each node" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            foreach ($node in $bundle.nodes) {
                $node.PSObject.Properties.Name | Should -Contain "name"
            }
        }
        
        It "Should have nodeType field for each node" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            foreach ($node in $bundle.nodes) {
                $node.PSObject.Properties.Name | Should -Contain "nodeType"
            }
        }
    }
    
    Context "Compliance Data for Viewer" {
        It "Should have violations with nodeId for highlighting" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            if ($bundle.compliance.violations.Count -gt 0) {
                $bundle.compliance.violations[0].PSObject.Properties.Name | Should -Contain "nodeId"
            }
        }
        
        It "Should have perRule breakdown for rule click" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            $bundle.compliance.perRule | Should -Not -BeNullOrEmpty
            
            foreach ($rule in $bundle.compliance.perRule) {
                $rule.PSObject.Properties.Name | Should -Contain "ruleName"
            }
        }
    }
    
    Context "Similar Data for Viewer" {
        It "Should have candidates with nodeId for jump-to" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            if ($bundle.similar.candidates.Count -gt 0) {
                $bundle.similar.candidates[0].PSObject.Properties.Name | Should -Contain "nodeId"
            }
        }
        
        It "Should have candidates with similarityScore for display" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            if ($bundle.similar.candidates.Count -gt 0) {
                $bundle.similar.candidates[0].PSObject.Properties.Name | Should -Contain "similarityScore"
            }
        }
    }
    
    Context "Anomaly Data for Viewer" {
        It "Should have anomalies with severity for filtering" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            foreach ($anomaly in $bundle.anomalies.anomalies) {
                $anomaly.PSObject.Properties.Name | Should -Contain "severity"
                $anomaly.severity | Should -BeIn @("Info", "Warn", "Critical")
            }
        }
        
        It "Should have anomalies with evidence for highlighting" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            foreach ($anomaly in $bundle.anomalies.anomalies) {
                $anomaly.PSObject.Properties.Name | Should -Contain "evidence"
            }
        }
        
        It "Should have anomalies with title for list display" {
            $bundle = Get-Content (Join-Path $script:demoDir "bundle.json") | ConvertFrom-Json
            
            foreach ($anomaly in $bundle.anomalies.anomalies) {
                $anomaly.PSObject.Properties.Name | Should -Contain "title"
                $anomaly.title | Should -Not -BeNullOrEmpty
            }
        }
    }
}
