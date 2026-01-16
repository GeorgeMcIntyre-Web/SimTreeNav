# DemoStory Pester Tests
# Tests for New-DemoStory.ps1

BeforeAll {
    $enginePath = Join-Path $PSScriptRoot "..\src\powershell\ws2c-engines"
    . "$enginePath\New-DemoStory.ps1"
    
    # Create test data directory
    $script:testDataDir = Join-Path $PSScriptRoot "test-data"
    if (-not (Test-Path $testDataDir)) {
        New-Item -ItemType Directory -Path $testDataDir | Out-Null
    }
}

AfterAll {
    if (Test-Path $script:testDataDir) {
        Remove-Item -Path $testDataDir -Recurse -Force
    }
}

Describe "New-DemoStory" {
    Context "Demo Data Generation" {
        It "Should generate nodes.json" {
            $outDir = Join-Path $script:testDataDir "demo-output"
            
            New-DemoStory -OutDir $outDir
            
            Test-Path (Join-Path $outDir "nodes.json") | Should -Be $true
        }
        
        It "Should generate timeline.json" {
            $outDir = Join-Path $script:testDataDir "demo-output"
            
            New-DemoStory -OutDir $outDir
            
            Test-Path (Join-Path $outDir "timeline.json") | Should -Be $true
        }
        
        It "Should generate compliance.json" {
            $outDir = Join-Path $script:testDataDir "demo-output"
            
            New-DemoStory -OutDir $outDir
            
            Test-Path (Join-Path $outDir "compliance.json") | Should -Be $true
        }
        
        It "Should generate similar.json" {
            $outDir = Join-Path $script:testDataDir "demo-output"
            
            New-DemoStory -OutDir $outDir
            
            Test-Path (Join-Path $outDir "similar.json") | Should -Be $true
        }
        
        It "Should generate anomalies.json" {
            $outDir = Join-Path $script:testDataDir "demo-output"
            
            New-DemoStory -OutDir $outDir
            
            Test-Path (Join-Path $outDir "anomalies.json") | Should -Be $true
        }
        
        It "Should generate bundle.json" {
            $outDir = Join-Path $script:testDataDir "demo-output"
            
            New-DemoStory -OutDir $outDir
            
            Test-Path (Join-Path $outDir "bundle.json") | Should -Be $true
        }
    }
    
    Context "Compliance Failure Scenario" {
        It "Should include at least one compliance failure" {
            $outDir = Join-Path $script:testDataDir "demo-compliance"
            
            New-DemoStory -OutDir $outDir
            
            $compliance = Get-Content (Join-Path $outDir "compliance.json") | ConvertFrom-Json
            
            # Should have violations or missing items
            $hasFailure = ($compliance.violations.Count -gt 0) -or 
                          ($compliance.missing.Count -gt 0) -or 
                          ($compliance.score -lt 100)
            
            $hasFailure | Should -Be $true
        }
    }
    
    Context "Similarity Hit Scenario" {
        It "Should include at least one similarity hit" {
            $outDir = Join-Path $script:testDataDir "demo-similar"
            
            New-DemoStory -OutDir $outDir
            
            $similar = Get-Content (Join-Path $outDir "similar.json") | ConvertFrom-Json
            
            $similar.candidates.Count | Should -BeGreaterOrEqual 1
        }
        
        It "Should have similarity scores > 0.5 for top candidates" {
            $outDir = Join-Path $script:testDataDir "demo-similar-scores"
            
            New-DemoStory -OutDir $outDir
            
            $similar = Get-Content (Join-Path $outDir "similar.json") | ConvertFrom-Json
            
            if ($similar.candidates.Count -gt 0) {
                $similar.candidates[0].similarityScore | Should -BeGreaterThan 0.5
            }
        }
    }
    
    Context "Critical Anomaly Scenario" {
        It "Should include at least one critical anomaly" {
            $outDir = Join-Path $script:testDataDir "demo-anomalies"
            
            New-DemoStory -OutDir $outDir
            
            $anomalies = Get-Content (Join-Path $outDir "anomalies.json") | ConvertFrom-Json
            
            $criticalAnomalies = $anomalies.anomalies | Where-Object { $_.severity -eq "Critical" }
            
            $criticalAnomalies.Count | Should -BeGreaterOrEqual 1
        }
    }
    
    Context "Bundle Integration" {
        It "Should have bundle with all sections populated" {
            $outDir = Join-Path $script:testDataDir "demo-bundle"
            
            New-DemoStory -OutDir $outDir
            
            $bundle = Get-Content (Join-Path $outDir "bundle.json") | ConvertFrom-Json
            
            $bundle.PSObject.Properties.Name | Should -Contain "nodes"
            $bundle.PSObject.Properties.Name | Should -Contain "compliance"
            $bundle.PSObject.Properties.Name | Should -Contain "similar"
            $bundle.PSObject.Properties.Name | Should -Contain "anomalies"
        }
    }
    
    Context "Deterministic Output" {
        It "Should produce consistent node count" {
            $outDir1 = Join-Path $script:testDataDir "demo-det1"
            $outDir2 = Join-Path $script:testDataDir "demo-det2"
            
            New-DemoStory -OutDir $outDir1 -Seed 42
            New-DemoStory -OutDir $outDir2 -Seed 42
            
            $nodes1 = Get-Content (Join-Path $outDir1 "nodes.json") | ConvertFrom-Json
            $nodes2 = Get-Content (Join-Path $outDir2 "nodes.json") | ConvertFrom-Json
            
            $nodes1.Count | Should -Be $nodes2.Count
        }
    }
}
