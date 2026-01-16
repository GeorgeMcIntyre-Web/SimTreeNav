# DriftEngine.Tests.ps1
# Pester tests for Drift detection

BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . "$scriptRoot/src/powershell/v02/analysis/DriftEngine.ps1"
}

Describe 'DriftEngine' {
    
    Describe 'Parse-Transform' {
        It 'Parses comma-separated string' {
            $result = Parse-Transform -Transform '100,200,300,45,90,0'
            
            $result.position[0] | Should -Be 100
            $result.position[1] | Should -Be 200
            $result.position[2] | Should -Be 300
            $result.rotation[0] | Should -Be 45
            $result.rotation[1] | Should -Be 90
            $result.rotation[2] | Should -Be 0
        }
        
        It 'Handles null transform' {
            $result = Parse-Transform -Transform $null
            
            $result.position | Should -Be @(0, 0, 0)
            $result.rotation | Should -Be @(0, 0, 0)
        }
        
        It 'Handles hashtable transform' {
            $result = Parse-Transform -Transform @{ position = @(10, 20, 30); rotation = @(1, 2, 3) }
            
            $result.position[0] | Should -Be 10
            $result.rotation[2] | Should -Be 3
        }
    }
    
    Describe 'Measure-PositionDelta' {
        It 'Computes Euclidean distance' {
            $delta = Measure-PositionDelta -Position1 @(0, 0, 0) -Position2 @(3, 4, 0)
            
            $delta | Should -Be 5  # 3-4-5 triangle
        }
        
        It 'Returns 0 for identical positions' {
            $delta = Measure-PositionDelta -Position1 @(100, 200, 300) -Position2 @(100, 200, 300)
            
            $delta | Should -Be 0
        }
        
        It 'Handles null positions' {
            $delta = Measure-PositionDelta -Position1 $null -Position2 @(1, 2, 3)
            
            $delta | Should -Be 0
        }
    }
    
    Describe 'Measure-RotationDelta' {
        It 'Computes maximum rotation difference' {
            $delta = Measure-RotationDelta -Rotation1 @(0, 0, 0) -Rotation2 @(10, 5, 3)
            
            $delta | Should -Be 10
        }
        
        It 'Handles wraparound' {
            # 350 degrees and 10 degrees should have delta of 20, not 340
            $delta = Measure-RotationDelta -Rotation1 @(350, 0, 0) -Rotation2 @(10, 0, 0)
            
            $delta | Should -BeLessOrEqual 20
        }
        
        It 'Returns 0 for identical rotations' {
            $delta = Measure-RotationDelta -Rotation1 @(45, 90, 180) -Rotation2 @(45, 90, 180)
            
            $delta | Should -Be 0
        }
    }
    
    Describe 'Measure-AttributeDelta' {
        It 'Counts different attributes' {
            $node1 = [PSCustomObject]@{
                attributes = [PSCustomObject]@{
                    name = 'Original'
                    color = 'Red'
                }
            }
            $node2 = [PSCustomObject]@{
                attributes = [PSCustomObject]@{
                    name = 'Modified'
                    color = 'Red'
                }
            }
            
            $delta = Measure-AttributeDelta -Node1 $node1 -Node2 $node2
            
            $delta.count | Should -Be 1
            $delta.diffs[0].attribute | Should -Be 'name'
        }
        
        It 'Handles empty attributes' {
            $node1 = [PSCustomObject]@{ attributes = @{} }
            $node2 = [PSCustomObject]@{ attributes = @{} }
            
            $delta = Measure-AttributeDelta -Node1 $node1 -Node2 $node2
            
            $delta.count | Should -Be 0
        }
    }
    
    Describe 'Find-DriftPairs' {
        It 'Finds prototype-instance pairs' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'proto1'; name = 'Proto'; nodeType = 'ToolPrototype'; path = '/Protos/P1'; links = $null }
                [PSCustomObject]@{ nodeId = 'inst1'; name = 'Instance1'; nodeType = 'ToolInstance'; path = '/Tools/T1'; links = [PSCustomObject]@{ prototypeId = 'proto1' } }
            )
            
            $pairs = Find-DriftPairs -Nodes $nodes
            
            $pairs | Should -HaveCount 1
            $pairs[0].relation | Should -Be 'prototype_instance'
        }
        
        It 'Finds twin pairs' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'res1'; name = 'Resource1'; nodeType = 'Resource'; path = '/Res/R1'; links = $null }
                [PSCustomObject]@{ nodeId = 'op1'; name = 'Op1'; nodeType = 'Operation'; path = '/Ops/O1'; links = [PSCustomObject]@{ twinId = 'res1' } }
            )
            
            $pairs = Find-DriftPairs -Nodes $nodes
            
            $pairs | Should -HaveCount 1
            $pairs[0].relation | Should -Be 'twin'
        }
    }
    
    Describe 'Measure-PairDrift' {
        It 'Detects position drift' {
            $source = [PSCustomObject]@{
                nodeId = 'S1'; name = 'Source'; nodeType = 'ToolPrototype'
                transform = '0,0,0,0,0,0'
                attributes = @{}
            }
            $target = [PSCustomObject]@{
                nodeId = 'T1'; name = 'Target'; nodeType = 'ToolInstance'
                transform = '10,0,0,0,0,0'
                attributes = @{}
            }
            
            $result = Measure-PairDrift -SourceNode $source -TargetNode $target -Tolerances @{ position_mm = 0.1; rotation_deg = 0.01; attribute_count = 0 }
            
            $result.positionDelta_mm | Should -Be 10
            $result.positionDrift | Should -BeTrue
            $result.hasDrift | Should -BeTrue
        }
        
        It 'Detects no drift within tolerance' {
            $source = [PSCustomObject]@{
                nodeId = 'S1'; name = 'Source'; nodeType = 'Proto'
                transform = '0,0,0,0,0,0'
                attributes = @{}
            }
            $target = [PSCustomObject]@{
                nodeId = 'T1'; name = 'Target'; nodeType = 'Instance'
                transform = '0.05,0,0,0,0,0'
                attributes = @{}
            }
            
            $result = Measure-PairDrift -SourceNode $source -TargetNode $target -Tolerances @{ position_mm = 0.1; rotation_deg = 0.01; attribute_count = 0 }
            
            $result.positionDrift | Should -BeFalse
            $result.hasDrift | Should -BeFalse
        }
    }
    
    Describe 'Measure-Drift' {
        It 'Produces drift report' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'proto'; name = 'Proto'; nodeType = 'ToolPrototype'; path = '/P'; transform = '0,0,0,0,0,0'; attributes = @{}; links = $null }
                [PSCustomObject]@{ nodeId = 'inst'; name = 'Inst'; nodeType = 'ToolInstance'; path = '/I'; transform = '100,0,0,0,0,0'; attributes = @{}; links = [PSCustomObject]@{ prototypeId = 'proto' } }
            )
            
            $report = Measure-Drift -Nodes $nodes
            
            $report | Should -Not -BeNullOrEmpty
            $report.totalPairs | Should -BeGreaterOrEqual 1
            $report.timestamp | Should -Not -BeNullOrEmpty
        }
        
        It 'Handles empty node set' {
            $report = Measure-Drift -Nodes @()
            
            $report | Should -Not -BeNullOrEmpty
            $report.totalPairs | Should -Be 0
        }
    }
    
    Describe 'Compare-DriftTrend' {
        It 'Detects worsening trend' {
            $baseline = [PSCustomObject]@{
                timestamp = '2024-01-01T00:00:00Z'
                totalPairs = 10
                driftedPairs = 1
                driftRate = 0.1
                avgPositionDelta = 0.5
                avgRotationDelta = 0.1
            }
            $current = [PSCustomObject]@{
                timestamp = '2024-01-02T00:00:00Z'
                totalPairs = 10
                driftedPairs = 5
                driftRate = 0.5
                avgPositionDelta = 2.0
                avgRotationDelta = 0.5
            }
            
            $trend = Compare-DriftTrend -BaselineDrift $baseline -CurrentDrift $current
            
            $trend.trendDirection | Should -Be 'worsening'
            $trend.driftRateDelta | Should -BeGreaterThan 0
        }
        
        It 'Detects improving trend' {
            $baseline = [PSCustomObject]@{
                timestamp = '2024-01-01T00:00:00Z'
                totalPairs = 10
                driftedPairs = 5
                driftRate = 0.5
                avgPositionDelta = 2.0
                avgRotationDelta = 0.5
            }
            $current = [PSCustomObject]@{
                timestamp = '2024-01-02T00:00:00Z'
                totalPairs = 10
                driftedPairs = 1
                driftRate = 0.1
                avgPositionDelta = 0.5
                avgRotationDelta = 0.1
            }
            
            $trend = Compare-DriftTrend -BaselineDrift $baseline -CurrentDrift $current
            
            $trend.trendDirection | Should -Be 'improving'
        }
    }
}
