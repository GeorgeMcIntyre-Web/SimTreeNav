# SimilarityEngine Pester Tests
# Tests for Find-Similar.ps1

BeforeAll {
    $enginePath = Join-Path $PSScriptRoot "..\src\powershell\ws2c-engines"
    . "$enginePath\Find-Similar.ps1"
    
    # Create test data directory
    $script:testDataDir = Join-Path $PSScriptRoot "test-data"
    if (-not (Test-Path $testDataDir)) {
        New-Item -ItemType Directory -Path $testDataDir | Out-Null
    }
    
    # Sample nodes with multiple similar stations
    $script:sampleNodes = @(
        @{
            id = "1"
            name = "Project_Root"
            nodeType = "Project"
            parentId = $null
            attributes = @{}
        },
        @{
            id = "2"
            name = "Line_001"
            nodeType = "Line"
            parentId = "1"
            attributes = @{}
        },
        # First station cluster
        @{
            id = "10"
            name = "Station_A01"
            nodeType = "Station"
            parentId = "2"
            attributes = @{ cycleTime = 60; workers = 2 }
        },
        @{
            id = "11"
            name = "Robot_A01"
            nodeType = "Robot"
            parentId = "10"
            attributes = @{ model = "KUKA"; payload = 16 }
        },
        @{
            id = "12"
            name = "Device_A01"
            nodeType = "Device"
            parentId = "10"
            attributes = @{ type = "Welder" }
        },
        # Second station cluster (similar to first)
        @{
            id = "20"
            name = "Station_A02"
            nodeType = "Station"
            parentId = "2"
            attributes = @{ cycleTime = 62; workers = 2 }
        },
        @{
            id = "21"
            name = "Robot_A02"
            nodeType = "Robot"
            parentId = "20"
            attributes = @{ model = "KUKA"; payload = 16 }
        },
        @{
            id = "22"
            name = "Device_A02"
            nodeType = "Device"
            parentId = "20"
            attributes = @{ type = "Welder" }
        },
        # Third station cluster (slightly different)
        @{
            id = "30"
            name = "Station_B01"
            nodeType = "Station"
            parentId = "2"
            attributes = @{ cycleTime = 45; workers = 1 }
        },
        @{
            id = "31"
            name = "Robot_B01"
            nodeType = "Robot"
            parentId = "30"
            attributes = @{ model = "ABB"; payload = 10 }
        },
        # Fourth station cluster (very different)
        @{
            id = "40"
            name = "Station_C01"
            nodeType = "Station"
            parentId = "2"
            attributes = @{ cycleTime = 120; workers = 4 }
        },
        @{
            id = "41"
            name = "Conveyor_C01"
            nodeType = "Conveyor"
            parentId = "40"
            attributes = @{}
        },
        @{
            id = "42"
            name = "Conveyor_C02"
            nodeType = "Conveyor"
            parentId = "40"
            attributes = @{}
        },
        @{
            id = "43"
            name = "Human_C01"
            nodeType = "Human"
            parentId = "40"
            attributes = @{}
        }
    )
    
    $script:nodesPath = Join-Path $testDataDir "similarity-nodes.json"
    $sampleNodes | ConvertTo-Json -Depth 10 | Set-Content -Path $nodesPath
}

AfterAll {
    # Cleanup test data
    if (Test-Path $script:testDataDir) {
        Remove-Item -Path $testDataDir -Recurse -Force
    }
}

Describe "Find-Similar" {
    Context "Basic Similarity Search" {
        It "Should return similar nodes sorted by score" {
            $outPath = Join-Path $script:testDataDir "similar-result.json"
            
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 10 -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            $result.candidates | Should -Not -BeNullOrEmpty
        }
        
        It "Should rank Station_A02 highest when searching for Station_A01" {
            $outPath = Join-Path $script:testDataDir "similar-a01.json"
            
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 5 -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            # Station_A02 (id=20) should be most similar to Station_A01 (id=10)
            $result.candidates[0].nodeId | Should -Be "20"
        }
        
        It "Should include similarityScore for each candidate" {
            $outPath = Join-Path $script:testDataDir "similar-scores.json"
            
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 5 -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            foreach ($candidate in $result.candidates) {
                $candidate.PSObject.Properties.Name | Should -Contain "similarityScore"
                $candidate.similarityScore | Should -BeGreaterOrEqual 0
                $candidate.similarityScore | Should -BeLessOrEqual 1
            }
        }
        
        It "Should respect the Top parameter" {
            $outPath = Join-Path $script:testDataDir "similar-top3.json"
            
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 3 -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            $result.candidates.Count | Should -BeLessOrEqual 3
        }
        
        It "Should include 'why' explanation for each match" {
            $outPath = Join-Path $script:testDataDir "similar-why.json"
            
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 5 -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            foreach ($candidate in $result.candidates) {
                $candidate.PSObject.Properties.Name | Should -Contain "why"
            }
        }
        
        It "Should include evidence references" {
            $outPath = Join-Path $script:testDataDir "similar-evidence.json"
            
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 5 -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            foreach ($candidate in $result.candidates) {
                $candidate.PSObject.Properties.Name | Should -Contain "evidence"
            }
        }
    }
    
    Context "Structural Fingerprinting" {
        It "Should use shapeHash in similarity calculation" {
            $outPath = Join-Path $script:testDataDir "similar-shape.json"
            
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 5 -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            # Verify algorithm info includes shapeHash
            $result.algorithm | Should -Not -BeNullOrEmpty
            $result.algorithm.PSObject.Properties.Name | Should -Contain "useShapeHash"
        }
        
        It "Should use attributeHash in similarity calculation" {
            $outPath = Join-Path $script:testDataDir "similar-attr.json"
            
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 5 -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            $result.algorithm.PSObject.Properties.Name | Should -Contain "useAttributeHash"
        }
    }
    
    Context "Deterministic Output" {
        It "Should produce identical results for same input" {
            $result1Path = Join-Path $script:testDataDir "similar-det1.json"
            $result2Path = Join-Path $script:testDataDir "similar-det2.json"
            
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 5 -OutPath $result1Path
            Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 5 -OutPath $result2Path
            
            $content1 = Get-Content $result1Path -Raw
            $content2 = Get-Content $result2Path -Raw
            
            $content1 | Should -Be $content2
        }
        
        It "Should have stable sort order for equal scores" {
            $outPath = Join-Path $script:testDataDir "similar-stable.json"
            
            # Run multiple times
            for ($i = 0; $i -lt 3; $i++) {
                Find-Similar -NodesPath $script:nodesPath -NodeId "10" -Top 10 -OutPath $outPath
                $result = Get-Content $outPath | ConvertFrom-Json
                
                # Candidates with same score should be sorted by nodeId
                for ($j = 1; $j -lt $result.candidates.Count; $j++) {
                    $prev = $result.candidates[$j - 1]
                    $curr = $result.candidates[$j]
                    
                    if ($prev.similarityScore -eq $curr.similarityScore) {
                        $prev.nodeId | Should -BeLessThan $curr.nodeId
                    }
                }
            }
        }
    }
    
    Context "Error Handling" {
        It "Should handle non-existent source node gracefully" {
            $outPath = Join-Path $script:testDataDir "similar-nonode.json"
            
            $result = Find-Similar -NodesPath $script:nodesPath -NodeId "999" -Top 5 -OutPath $outPath
            
            $result | Should -Be $false
        }
        
        It "Should handle empty nodes file gracefully" {
            $emptyNodesPath = Join-Path $script:testDataDir "empty-nodes.json"
            "[]" | Set-Content -Path $emptyNodesPath
            
            $outPath = Join-Path $script:testDataDir "similar-empty.json"
            
            $result = Find-Similar -NodesPath $emptyNodesPath -NodeId "1" -Top 5 -OutPath $outPath
            
            $result | Should -Be $false
        }
    }
}
