# Bundle Pester Tests
# Tests for Export-Bundle.ps1

BeforeAll {
    $enginePath = Join-Path $PSScriptRoot "..\src\powershell\ws2c-engines"
    . "$enginePath\Export-Bundle.ps1"
    
    # Create test data directory
    $script:testDataDir = Join-Path $PSScriptRoot "test-data"
    if (-not (Test-Path $testDataDir)) {
        New-Item -ItemType Directory -Path $testDataDir | Out-Null
    }
    
    # Sample nodes
    $script:sampleNodes = @(
        @{ id = "1"; name = "Project"; nodeType = "Project"; parentId = $null; attributes = @{} }
        @{ id = "2"; name = "Line_001"; nodeType = "Line"; parentId = "1"; attributes = @{} }
        @{ id = "3"; name = "Station_001"; nodeType = "Station"; parentId = "2"; attributes = @{} }
    )
    
    # Sample compliance data
    $script:sampleCompliance = @{
        score = 85
        missing = @()
        violations = @(@{ rule = "naming"; nodeId = "3"; message = "Name mismatch" })
        extras = @()
        perRule = @(@{ ruleName = "naming"; passed = $false; score = 70 })
    }
    
    # Sample similarity data
    $script:sampleSimilar = @{
        sourceNodeId = "3"
        candidates = @(
            @{ nodeId = "10"; similarityScore = 0.95; why = "Same structure"; evidence = @() }
        )
        algorithm = @{ useShapeHash = $true; useAttributeHash = $true }
    }
    
    # Sample anomalies data
    $script:sampleAnomalies = @{
        anomalies = @(
            @{
                severity = "Critical"
                title = "Mass Delete Spike"
                summary = "5 nodes deleted in 20 seconds"
                evidence = @{ changeIds = @("c3", "c4", "c5"); nodeIds = @("100", "101", "102") }
            }
        )
    }
    
    # Write test files
    $script:nodesPath = Join-Path $testDataDir "bundle-nodes.json"
    $sampleNodes | ConvertTo-Json -Depth 10 | Set-Content -Path $nodesPath
    
    $script:compliancePath = Join-Path $testDataDir "bundle-compliance.json"
    $sampleCompliance | ConvertTo-Json -Depth 10 | Set-Content -Path $compliancePath
    
    $script:similarPath = Join-Path $testDataDir "bundle-similar.json"
    $sampleSimilar | ConvertTo-Json -Depth 10 | Set-Content -Path $similarPath
    
    $script:anomaliesPath = Join-Path $testDataDir "bundle-anomalies.json"
    $sampleAnomalies | ConvertTo-Json -Depth 10 | Set-Content -Path $anomaliesPath
}

AfterAll {
    if (Test-Path $script:testDataDir) {
        Remove-Item -Path $testDataDir -Recurse -Force
    }
}

Describe "Export-Bundle" {
    Context "Bundle Creation" {
        It "Should create a valid bundle file" {
            $bundlePath = Join-Path $script:testDataDir "test-bundle.json"
            
            $result = Export-Bundle -NodesPath $script:nodesPath -OutPath $bundlePath
            
            $result | Should -Be $true
            Test-Path $bundlePath | Should -Be $true
        }
        
        It "Should include nodes section" {
            $bundlePath = Join-Path $script:testDataDir "bundle-nodes-section.json"
            
            Export-Bundle -NodesPath $script:nodesPath -OutPath $bundlePath
            
            $bundle = Get-Content $bundlePath | ConvertFrom-Json
            
            $bundle.PSObject.Properties.Name | Should -Contain "nodes"
            $bundle.nodes | Should -Not -BeNullOrEmpty
        }
        
        It "Should include metadata section" {
            $bundlePath = Join-Path $script:testDataDir "bundle-meta.json"
            
            Export-Bundle -NodesPath $script:nodesPath -OutPath $bundlePath
            
            $bundle = Get-Content $bundlePath | ConvertFrom-Json
            
            $bundle.PSObject.Properties.Name | Should -Contain "metadata"
            $bundle.metadata.PSObject.Properties.Name | Should -Contain "version"
            $bundle.metadata.PSObject.Properties.Name | Should -Contain "generatedAt"
        }
    }
    
    Context "Optional Sections" {
        It "Should include compliance section when provided" {
            $bundlePath = Join-Path $script:testDataDir "bundle-with-compliance.json"
            
            Export-Bundle -NodesPath $script:nodesPath -CompliancePath $script:compliancePath -OutPath $bundlePath
            
            $bundle = Get-Content $bundlePath | ConvertFrom-Json
            
            $bundle.PSObject.Properties.Name | Should -Contain "compliance"
            $bundle.compliance.score | Should -Be 85
        }
        
        It "Should include similar section when provided" {
            $bundlePath = Join-Path $script:testDataDir "bundle-with-similar.json"
            
            Export-Bundle -NodesPath $script:nodesPath -SimilarPath $script:similarPath -OutPath $bundlePath
            
            $bundle = Get-Content $bundlePath | ConvertFrom-Json
            
            $bundle.PSObject.Properties.Name | Should -Contain "similar"
            $bundle.similar.candidates | Should -Not -BeNullOrEmpty
        }
        
        It "Should include anomalies section when provided" {
            $bundlePath = Join-Path $script:testDataDir "bundle-with-anomalies.json"
            
            Export-Bundle -NodesPath $script:nodesPath -AnomaliesPath $script:anomaliesPath -OutPath $bundlePath
            
            $bundle = Get-Content $bundlePath | ConvertFrom-Json
            
            $bundle.PSObject.Properties.Name | Should -Contain "anomalies"
            $bundle.anomalies.anomalies | Should -Not -BeNullOrEmpty
        }
        
        It "Should include all engine sections when all provided" {
            $bundlePath = Join-Path $script:testDataDir "bundle-full.json"
            
            Export-Bundle -NodesPath $script:nodesPath `
                -CompliancePath $script:compliancePath `
                -SimilarPath $script:similarPath `
                -AnomaliesPath $script:anomaliesPath `
                -OutPath $bundlePath
            
            $bundle = Get-Content $bundlePath | ConvertFrom-Json
            
            $bundle.PSObject.Properties.Name | Should -Contain "compliance"
            $bundle.PSObject.Properties.Name | Should -Contain "similar"
            $bundle.PSObject.Properties.Name | Should -Contain "anomalies"
        }
    }
    
    Context "Deterministic Output" {
        It "Should produce consistent output structure" {
            $bundle1Path = Join-Path $script:testDataDir "bundle-det1.json"
            $bundle2Path = Join-Path $script:testDataDir "bundle-det2.json"
            
            Export-Bundle -NodesPath $script:nodesPath `
                -CompliancePath $script:compliancePath `
                -SimilarPath $script:similarPath `
                -AnomaliesPath $script:anomaliesPath `
                -OutPath $bundle1Path
            
            Export-Bundle -NodesPath $script:nodesPath `
                -CompliancePath $script:compliancePath `
                -SimilarPath $script:similarPath `
                -AnomaliesPath $script:anomaliesPath `
                -OutPath $bundle2Path
            
            $bundle1 = Get-Content $bundle1Path | ConvertFrom-Json
            $bundle2 = Get-Content $bundle2Path | ConvertFrom-Json
            
            # Compare structure (not timestamps)
            $bundle1.nodes.Count | Should -Be $bundle2.nodes.Count
            $bundle1.compliance.score | Should -Be $bundle2.compliance.score
        }
    }
}
