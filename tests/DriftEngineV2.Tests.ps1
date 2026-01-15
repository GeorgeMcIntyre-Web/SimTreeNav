# DriftEngineV2.Tests.ps1
# Tests for DriftEngine v1 (Quality / divergence)

BeforeAll {
    $scriptRoot = Split-Path $PSScriptRoot -Parent
    . "$scriptRoot\src\powershell\v02\analysis\DriftEngine.ps1"
}

Describe 'Parse-Transform' {
    It 'Parses comma-separated string with 6 values' {
        $result = Parse-Transform -Transform "100,200,300,45,90,180"
        
        $result.position | Should -Be @(100, 200, 300)
        $result.rotation | Should -Be @(45, 90, 180)
    }
    
    It 'Parses string with only 3 position values' {
        $result = Parse-Transform -Transform "100,200,300"
        
        $result.position | Should -Be @(100, 200, 300)
        $result.rotation | Should -Be @(0, 0, 0)
    }
    
    It 'Returns zeros for null transform' {
        $result = Parse-Transform -Transform $null
        
        $result.position | Should -Be @(0, 0, 0)
        $result.rotation | Should -Be @(0, 0, 0)
    }
    
    It 'Handles whitespace-separated values' {
        $result = Parse-Transform -Transform "100 200 300 45 90 180"
        
        $result.position | Should -Be @(100, 200, 300)
    }
    
    It 'Handles hashtable input' {
        $transform = @{ position = @(100, 200, 300); rotation = @(45, 90, 180) }
        $result = Parse-Transform -Transform $transform
        
        $result.position | Should -Be @(100, 200, 300)
        $result.rotation | Should -Be @(45, 90, 180)
    }
}

Describe 'Measure-PositionDelta' {
    It 'Returns 0 for identical positions' {
        $delta = Measure-PositionDelta -Position1 @(100, 200, 300) -Position2 @(100, 200, 300)
        
        $delta | Should -Be 0
    }
    
    It 'Computes correct Euclidean distance' {
        # 3-4-5 triangle: sqrt(3^2 + 4^2) = 5
        $delta = Measure-PositionDelta -Position1 @(0, 0, 0) -Position2 @(3, 4, 0)
        
        $delta | Should -Be 5
    }
    
    It 'Handles 3D distance' {
        # sqrt(1^2 + 2^2 + 2^2) = 3
        $delta = Measure-PositionDelta -Position1 @(0, 0, 0) -Position2 @(1, 2, 2)
        
        $delta | Should -Be 3
    }
    
    It 'Returns 0 for null positions' {
        $delta = Measure-PositionDelta -Position1 $null -Position2 $null
        
        $delta | Should -Be 0
    }
}

Describe 'Measure-RotationDelta' {
    It 'Returns 0 for identical rotations' {
        $delta = Measure-RotationDelta -Rotation1 @(45, 90, 180) -Rotation2 @(45, 90, 180)
        
        $delta | Should -Be 0
    }
    
    It 'Returns max axis difference' {
        $delta = Measure-RotationDelta -Rotation1 @(0, 0, 0) -Rotation2 @(10, 20, 5)
        
        $delta | Should -Be 20  # Max of 10, 20, 5
    }
    
    It 'Handles wraparound (0-360)' {
        $delta = Measure-RotationDelta -Rotation1 @(350, 0, 0) -Rotation2 @(10, 0, 0)
        
        # Difference should be 20 (not 340), accounting for wrap
        $delta | Should -BeLessOrEqual 20
    }
    
    It 'Returns 0 for null rotations' {
        $delta = Measure-RotationDelta -Rotation1 $null -Rotation2 $null
        
        $delta | Should -Be 0
    }
}

Describe 'Find-DriftPairs' {
    BeforeAll {
        $testNodes = @(
            [PSCustomObject]@{ 
                nodeId = 'N001'; name = 'WeldGun_Proto'; nodeType = 'ToolPrototype'
                parentId = $null; path = '/Proto'; transform = "0,0,0,0,0,0"
                links = $null
            }
            [PSCustomObject]@{ 
                nodeId = 'N002'; name = 'WeldGun_1'; nodeType = 'ToolInstance'
                parentId = 'N001'; path = '/Station/WeldGun_1'; transform = "100,200,300,0,0,0"
                links = [PSCustomObject]@{ prototypeId = 'N001' }
            }
            [PSCustomObject]@{ 
                nodeId = 'N003'; name = 'WeldGun_2'; nodeType = 'ToolInstance'
                parentId = 'N001'; path = '/Station/WeldGun_2'; transform = "150,250,350,0,0,0"
                links = [PSCustomObject]@{ prototypeId = 'N001' }
            }
        )
    }
    
    It 'Finds prototype-instance pairs' {
        $pairs = Find-DriftPairs -Nodes $testNodes
        
        $pairs.Count | Should -Be 2
        $pairs[0].relation | Should -Be 'prototype_instance'
    }
    
    It 'Returns empty for empty input' {
        $pairs = Find-DriftPairs -Nodes @()
        
        $pairs.Count | Should -Be 0
    }
    
    It 'Returns empty for nodes without links' {
        $noLinkNodes = @(
            [PSCustomObject]@{ nodeId = 'N001'; name = 'Node1'; nodeType = 'Station'; links = $null }
            [PSCustomObject]@{ nodeId = 'N002'; name = 'Node2'; nodeType = 'Station'; links = $null }
        )
        
        $pairs = Find-DriftPairs -Nodes $noLinkNodes
        
        $pairs.Count | Should -Be 0
    }
}

Describe 'Measure-PairDrift' {
    It 'Detects position drift beyond tolerance' {
        $source = [PSCustomObject]@{ 
            nodeId = 'N001'; name = 'Proto'; nodeType = 'ToolPrototype'
            transform = "0,0,0,0,0,0"
            attributes = @{}
        }
        $target = [PSCustomObject]@{ 
            nodeId = 'N002'; name = 'Instance'; nodeType = 'ToolInstance'
            transform = "100,0,0,0,0,0"  # 100mm away
            attributes = @{}
        }
        $tolerances = @{ position_mm = 0.1; rotation_deg = 0.01; attribute_count = 0 }
        
        $result = Measure-PairDrift -SourceNode $source -TargetNode $target -Tolerances $tolerances
        
        $result.hasDrift | Should -Be $true
        $result.positionDrift | Should -Be $true
        $result.positionDelta_mm | Should -Be 100
    }
    
    It 'Detects rotation drift beyond tolerance' {
        $source = [PSCustomObject]@{ 
            nodeId = 'N001'; name = 'Proto'; nodeType = 'ToolPrototype'
            transform = "0,0,0,0,0,0"
            attributes = @{}
        }
        $target = [PSCustomObject]@{ 
            nodeId = 'N002'; name = 'Instance'; nodeType = 'ToolInstance'
            transform = "0,0,0,10,0,0"  # 10deg rotation
            attributes = @{}
        }
        $tolerances = @{ position_mm = 0.1; rotation_deg = 0.01; attribute_count = 0 }
        
        $result = Measure-PairDrift -SourceNode $source -TargetNode $target -Tolerances $tolerances
        
        $result.hasDrift | Should -Be $true
        $result.rotationDrift | Should -Be $true
        $result.rotationDelta_deg | Should -Be 10
    }
    
    It 'Reports no drift when within tolerance' {
        $source = [PSCustomObject]@{ 
            nodeId = 'N001'; name = 'Proto'; nodeType = 'ToolPrototype'
            transform = "0,0,0,0,0,0"
            attributes = @{}
        }
        $target = [PSCustomObject]@{ 
            nodeId = 'N002'; name = 'Instance'; nodeType = 'ToolInstance'
            transform = "0.05,0,0,0.005,0,0"  # Within tolerance
            attributes = @{}
        }
        $tolerances = @{ position_mm = 0.1; rotation_deg = 0.01; attribute_count = 0 }
        
        $result = Measure-PairDrift -SourceNode $source -TargetNode $target -Tolerances $tolerances
        
        $result.hasDrift | Should -Be $false
    }
    
    It 'Computes severity based on delta magnitude' {
        $source = [PSCustomObject]@{ 
            nodeId = 'N001'; name = 'Proto'; nodeType = 'ToolPrototype'
            transform = "0,0,0,0,0,0"
            attributes = @{}
        }
        $target = [PSCustomObject]@{ 
            nodeId = 'N002'; name = 'Instance'; nodeType = 'ToolInstance'
            transform = "500,0,0,0,0,0"  # Large drift
            attributes = @{}
        }
        $tolerances = @{ position_mm = 0.1; rotation_deg = 0.01; attribute_count = 0 }
        
        $result = Measure-PairDrift -SourceNode $source -TargetNode $target -Tolerances $tolerances
        
        $result.severity | Should -BeGreaterThan 0
    }
}

Describe 'Measure-Drift' {
    BeforeAll {
        $testNodes = @(
            [PSCustomObject]@{ 
                nodeId = 'N001'; name = 'WeldGun_Proto'; nodeType = 'ToolPrototype'
                parentId = $null; path = '/Proto'; transform = "0,0,0,0,0,0"
                links = $null; attributes = @{}
            }
            [PSCustomObject]@{ 
                nodeId = 'N002'; name = 'WeldGun_1'; nodeType = 'ToolInstance'
                parentId = 'N001'; path = '/Station/WeldGun_1'; transform = "100,200,300,10,20,30"
                links = [PSCustomObject]@{ prototypeId = 'N001' }
                attributes = @{}
            }
            [PSCustomObject]@{ 
                nodeId = 'N003'; name = 'WeldGun_2'; nodeType = 'ToolInstance'
                parentId = 'N001'; path = '/Station/WeldGun_2'; transform = "150,250,350,5,10,15"
                links = [PSCustomObject]@{ prototypeId = 'N001' }
                attributes = @{}
            }
        )
    }
    
    It 'Returns comprehensive drift report' {
        $report = Measure-Drift -Nodes $testNodes
        
        $report.totalPairs | Should -BeGreaterOrEqual 0
        $report.driftedPairs | Should -BeGreaterOrEqual 0
        $report.driftRate | Should -BeGreaterOrEqual 0
        $report.measurements | Should -Not -BeNullOrEmpty
    }
    
    It 'Computes drift statistics' {
        $report = Measure-Drift -Nodes $testNodes
        
        $report.avgPositionDelta | Should -BeGreaterOrEqual 0
        $report.maxPositionDelta | Should -BeGreaterOrEqual 0
        $report.avgRotationDelta | Should -BeGreaterOrEqual 0
        $report.maxRotationDelta | Should -BeGreaterOrEqual 0
    }
    
    It 'Returns top drifted items sorted by severity' {
        $report = Measure-Drift -Nodes $testNodes
        
        if ($report.topDrifted.Count -gt 1) {
            $report.topDrifted[0].severity | Should -BeGreaterOrEqual $report.topDrifted[1].severity
        }
    }
    
    It 'Handles empty input' {
        $report = Measure-Drift -Nodes @()
        
        $report.totalPairs | Should -Be 0
        $report.driftedPairs | Should -Be 0
    }
}

Describe 'Drift Output Determinism' {
    BeforeAll {
        $testNodes = @(
            [PSCustomObject]@{ 
                nodeId = 'N001'; name = 'Proto'; nodeType = 'ToolPrototype'
                transform = "0,0,0,0,0,0"; links = $null; attributes = @{}
            }
            [PSCustomObject]@{ 
                nodeId = 'N002'; name = 'Instance'; nodeType = 'ToolInstance'
                transform = "100,0,0,0,0,0"
                links = [PSCustomObject]@{ prototypeId = 'N001' }
                attributes = @{}
            }
        )
    }
    
    It 'Produces identical output for same input' {
        $report1 = Measure-Drift -Nodes $testNodes
        $report2 = Measure-Drift -Nodes $testNodes
        
        $report1.totalPairs | Should -Be $report2.totalPairs
        $report1.driftedPairs | Should -Be $report2.driftedPairs
        $report1.driftRate | Should -Be $report2.driftRate
    }
    
    It 'Produces deterministic measurements' {
        $report1 = Measure-Drift -Nodes $testNodes
        $report2 = Measure-Drift -Nodes $testNodes
        
        $report1.measurements[0].positionDelta_mm | Should -Be $report2.measurements[0].positionDelta_mm
        $report1.measurements[0].rotationDelta_deg | Should -Be $report2.measurements[0].rotationDelta_deg
    }
}

Describe 'Compare-DriftTrend' {
    It 'Detects worsening trend' {
        $baseline = [PSCustomObject]@{
            timestamp = '2026-01-01T00:00:00Z'
            totalPairs = 10; driftedPairs = 2; driftRate = 0.2
            avgPositionDelta = 1.0; avgRotationDelta = 0.5
        }
        $current = [PSCustomObject]@{
            timestamp = '2026-01-15T00:00:00Z'
            totalPairs = 10; driftedPairs = 5; driftRate = 0.5
            avgPositionDelta = 2.0; avgRotationDelta = 1.0
        }
        
        $trend = Compare-DriftTrend -BaselineDrift $baseline -CurrentDrift $current
        
        $trend.trendDirection | Should -Be 'worsening'
        $trend.driftedDelta | Should -Be 3
    }
    
    It 'Detects improving trend' {
        $baseline = [PSCustomObject]@{
            timestamp = '2026-01-01T00:00:00Z'
            totalPairs = 10; driftedPairs = 5; driftRate = 0.5
            avgPositionDelta = 2.0; avgRotationDelta = 1.0
        }
        $current = [PSCustomObject]@{
            timestamp = '2026-01-15T00:00:00Z'
            totalPairs = 10; driftedPairs = 2; driftRate = 0.2
            avgPositionDelta = 1.0; avgRotationDelta = 0.5
        }
        
        $trend = Compare-DriftTrend -BaselineDrift $baseline -CurrentDrift $current
        
        $trend.trendDirection | Should -Be 'improving'
    }
    
    It 'Detects stable trend' {
        $baseline = [PSCustomObject]@{
            timestamp = '2026-01-01T00:00:00Z'
            totalPairs = 10; driftedPairs = 3; driftRate = 0.3
            avgPositionDelta = 1.0; avgRotationDelta = 0.5
        }
        $current = [PSCustomObject]@{
            timestamp = '2026-01-15T00:00:00Z'
            totalPairs = 10; driftedPairs = 3; driftRate = 0.3
            avgPositionDelta = 1.0; avgRotationDelta = 0.5
        }
        
        $trend = Compare-DriftTrend -BaselineDrift $baseline -CurrentDrift $current
        
        $trend.trendDirection | Should -Be 'stable'
    }
    
    It 'Sets appropriate alert level' {
        $baseline = [PSCustomObject]@{
            timestamp = '2026-01-01T00:00:00Z'
            totalPairs = 10; driftedPairs = 1; driftRate = 0.1
            avgPositionDelta = 1.0; avgRotationDelta = 0.5
        }
        $current = [PSCustomObject]@{
            timestamp = '2026-01-15T00:00:00Z'
            totalPairs = 10; driftedPairs = 8; driftRate = 0.8  # Big jump
            avgPositionDelta = 5.0; avgRotationDelta = 2.0
        }
        
        $trend = Compare-DriftTrend -BaselineDrift $baseline -CurrentDrift $current
        
        $trend.alertLevel | Should -Be 'Critical'
    }
}

Describe 'Tolerance Classification' {
    It 'Classifies severity based on tolerance multiples' {
        $source = [PSCustomObject]@{ 
            nodeId = 'N001'; name = 'Proto'; nodeType = 'ToolPrototype'
            transform = "0,0,0,0,0,0"; attributes = @{}
        }
        
        # 10x tolerance
        $largeTarget = [PSCustomObject]@{ 
            nodeId = 'N002'; name = 'Instance'; nodeType = 'ToolInstance'
            transform = "1,0,0,0,0,0"  # 1mm when tolerance is 0.1mm = 10x
            attributes = @{}
        }
        
        # 2x tolerance
        $smallTarget = [PSCustomObject]@{ 
            nodeId = 'N003'; name = 'Instance2'; nodeType = 'ToolInstance'
            transform = "0.2,0,0,0,0,0"  # 0.2mm when tolerance is 0.1mm = 2x
            attributes = @{}
        }
        
        $tolerances = @{ position_mm = 0.1; rotation_deg = 0.01; attribute_count = 0 }
        
        $largeResult = Measure-PairDrift -SourceNode $source -TargetNode $largeTarget -Tolerances $tolerances
        $smallResult = Measure-PairDrift -SourceNode $source -TargetNode $smallTarget -Tolerances $tolerances
        
        $largeResult.severity | Should -BeGreaterThan $smallResult.severity
    }
}
