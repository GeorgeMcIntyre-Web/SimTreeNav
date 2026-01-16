# AnomalyEngine Pester Tests
# Tests for Detect-Anomalies.ps1

BeforeAll {
    $enginePath = Join-Path $PSScriptRoot "..\src\powershell\ws2c-engines"
    . "$enginePath\Detect-Anomalies.ps1"
    
    # Create test data directory
    $script:testDataDir = Join-Path $PSScriptRoot "test-data"
    if (-not (Test-Path $testDataDir)) {
        New-Item -ItemType Directory -Path $testDataDir | Out-Null
    }
    
    # Sample nodes with various anomaly patterns
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
        @{
            id = "3"
            name = "Station_001"
            nodeType = "Station"
            parentId = "2"
            attributes = @{}
        },
        # Naming violation
        @{
            id = "4"
            name = "invalid name with spaces!@#"
            nodeType = "Device"
            parentId = "3"
            attributes = @{}
        },
        # Normal nodes
        @{
            id = "5"
            name = "Robot_001"
            nodeType = "Robot"
            parentId = "3"
            attributes = @{}
        },
        @{
            id = "6"
            name = "Robot_002"
            nodeType = "Robot"
            parentId = "3"
            attributes = @{}
        }
    )
    
    # Sample timeline with changes (for detecting patterns)
    $script:sampleTimeline = @(
        # Normal changes
        @{
            changeId = "c1"
            timestamp = "2024-01-01T10:00:00"
            nodeId = "3"
            changeType = "modify"
            user = "user1"
            details = @{ field = "name"; oldValue = "Stn_001"; newValue = "Station_001" }
        },
        @{
            changeId = "c2"
            timestamp = "2024-01-01T11:00:00"
            nodeId = "5"
            changeType = "add"
            user = "user1"
            details = @{}
        },
        # Mass delete spike
        @{
            changeId = "c3"
            timestamp = "2024-01-02T09:00:00"
            nodeId = "100"
            changeType = "delete"
            user = "user2"
            details = @{}
        },
        @{
            changeId = "c4"
            timestamp = "2024-01-02T09:00:05"
            nodeId = "101"
            changeType = "delete"
            user = "user2"
            details = @{}
        },
        @{
            changeId = "c5"
            timestamp = "2024-01-02T09:00:10"
            nodeId = "102"
            changeType = "delete"
            user = "user2"
            details = @{}
        },
        @{
            changeId = "c6"
            timestamp = "2024-01-02T09:00:15"
            nodeId = "103"
            changeType = "delete"
            user = "user2"
            details = @{}
        },
        @{
            changeId = "c7"
            timestamp = "2024-01-02T09:00:20"
            nodeId = "104"
            changeType = "delete"
            user = "user2"
            details = @{}
        },
        # Oscillation pattern (parent moves back and forth)
        @{
            changeId = "c8"
            timestamp = "2024-01-03T10:00:00"
            nodeId = "6"
            changeType = "move"
            user = "user1"
            details = @{ oldParentId = "3"; newParentId = "2" }
        },
        @{
            changeId = "c9"
            timestamp = "2024-01-03T10:05:00"
            nodeId = "6"
            changeType = "move"
            user = "user1"
            details = @{ oldParentId = "2"; newParentId = "3" }
        },
        @{
            changeId = "c10"
            timestamp = "2024-01-03T10:10:00"
            nodeId = "6"
            changeType = "move"
            user = "user1"
            details = @{ oldParentId = "3"; newParentId = "2" }
        },
        @{
            changeId = "c11"
            timestamp = "2024-01-03T10:15:00"
            nodeId = "6"
            changeType = "move"
            user = "user1"
            details = @{ oldParentId = "2"; newParentId = "3" }
        },
        # Transform outlier
        @{
            changeId = "c12"
            timestamp = "2024-01-04T10:00:00"
            nodeId = "5"
            changeType = "transform"
            user = "user1"
            details = @{ 
                translation = @{ x = 99999; y = 99999; z = 99999 }
                rotation = @{ x = 0; y = 0; z = 0 }
            }
        }
    )
    
    $script:nodesPath = Join-Path $testDataDir "anomaly-nodes.json"
    $sampleNodes | ConvertTo-Json -Depth 10 | Set-Content -Path $nodesPath
    
    $script:timelinePath = Join-Path $testDataDir "anomaly-timeline.json"
    $sampleTimeline | ConvertTo-Json -Depth 10 | Set-Content -Path $timelinePath
}

AfterAll {
    # Cleanup test data
    if (Test-Path $script:testDataDir) {
        Remove-Item -Path $testDataDir -Recurse -Force
    }
}

Describe "Detect-Anomalies" {
    Context "Anomaly Detection" {
        It "Should detect mass delete spikes" {
            $outPath = Join-Path $script:testDataDir "anomalies-result.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            $massDeleteAnomaly = $result.anomalies | Where-Object { $_.title -match "mass.*delete" -or $_.title -match "delete.*spike" }
            $massDeleteAnomaly | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect transform outliers" {
            $outPath = Join-Path $script:testDataDir "anomalies-transform.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            $transformAnomaly = $result.anomalies | Where-Object { $_.title -match "transform" -or $_.title -match "outlier" }
            $transformAnomaly | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect oscillation patterns" {
            $outPath = Join-Path $script:testDataDir "anomalies-oscillation.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            $oscillationAnomaly = $result.anomalies | Where-Object { $_.title -match "oscillat" }
            $oscillationAnomaly | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect naming violations" {
            $outPath = Join-Path $script:testDataDir "anomalies-naming.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            $namingAnomaly = $result.anomalies | Where-Object { $_.title -match "naming" }
            $namingAnomaly | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Severity Levels" {
        It "Should include severity for each anomaly" {
            $outPath = Join-Path $script:testDataDir "anomalies-severity.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            foreach ($anomaly in $result.anomalies) {
                $anomaly.PSObject.Properties.Name | Should -Contain "severity"
                $anomaly.severity | Should -BeIn @("Info", "Warn", "Critical")
            }
        }
        
        It "Should mark mass delete as Critical or Warn" {
            $outPath = Join-Path $script:testDataDir "anomalies-critical.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            $massDeleteAnomaly = $result.anomalies | Where-Object { $_.title -match "mass.*delete" -or $_.title -match "delete.*spike" }
            if ($massDeleteAnomaly) {
                $massDeleteAnomaly.severity | Should -BeIn @("Warn", "Critical")
            }
        }
    }
    
    Context "Anomaly Details" {
        It "Should include title for each anomaly" {
            $outPath = Join-Path $script:testDataDir "anomalies-title.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            foreach ($anomaly in $result.anomalies) {
                $anomaly.PSObject.Properties.Name | Should -Contain "title"
                $anomaly.title | Should -Not -BeNullOrEmpty
            }
        }
        
        It "Should include summary for each anomaly" {
            $outPath = Join-Path $script:testDataDir "anomalies-summary.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            foreach ($anomaly in $result.anomalies) {
                $anomaly.PSObject.Properties.Name | Should -Contain "summary"
            }
        }
        
        It "Should include evidence references" {
            $outPath = Join-Path $script:testDataDir "anomalies-evidence.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            foreach ($anomaly in $result.anomalies) {
                $anomaly.PSObject.Properties.Name | Should -Contain "evidence"
            }
        }
    }
    
    Context "Deterministic Output" {
        It "Should produce identical results for same input" {
            $result1Path = Join-Path $script:testDataDir "anomalies-det1.json"
            $result2Path = Join-Path $script:testDataDir "anomalies-det2.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $result1Path
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $result2Path
            
            $content1 = Get-Content $result1Path -Raw
            $content2 = Get-Content $result2Path -Raw
            
            $content1 | Should -Be $content2
        }
        
        It "Should have stable sort order" {
            $outPath = Join-Path $script:testDataDir "anomalies-stable.json"
            
            Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $script:timelinePath -OutPath $outPath
            
            $result = Get-Content $outPath | ConvertFrom-Json
            
            # Anomalies should be sorted by severity (Critical > Warn > Info), then by title
            $lastSeverityRank = 0
            $severityRanks = @{ "Critical" = 3; "Warn" = 2; "Info" = 1 }
            
            foreach ($anomaly in $result.anomalies) {
                $currentRank = $severityRanks[$anomaly.severity]
                $currentRank | Should -BeLessOrEqual $lastSeverityRank -Or $lastSeverityRank | Should -Be 0
                $lastSeverityRank = $currentRank
            }
        }
    }
    
    Context "Error Handling" {
        It "Should work with nodes-only (no timeline)" {
            $outPath = Join-Path $script:testDataDir "anomalies-notimeline.json"
            
            $result = Detect-Anomalies -NodesPath $script:nodesPath -OutPath $outPath
            
            $result | Should -Be $true
            
            $output = Get-Content $outPath | ConvertFrom-Json
            
            # Should still detect naming violations from nodes
            $output.anomalies | Should -Not -BeNullOrEmpty
        }
        
        It "Should handle empty timeline gracefully" {
            $emptyTimelinePath = Join-Path $script:testDataDir "empty-timeline.json"
            "[]" | Set-Content -Path $emptyTimelinePath
            
            $outPath = Join-Path $script:testDataDir "anomalies-emptytl.json"
            
            $result = Detect-Anomalies -NodesPath $script:nodesPath -TimelinePath $emptyTimelinePath -OutPath $outPath
            
            $result | Should -Be $true
        }
    }
}
