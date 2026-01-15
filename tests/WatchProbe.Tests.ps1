# WatchProbe.Tests.ps1
# Pester tests for two-stage watch probe

BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . "$scriptRoot/src/powershell/v02/probe/WatchProbe.ps1"
    
    # Helper to create test nodes
    function New-ProbeTestNode {
        param(
            [string]$NodeId,
            [string]$Name,
            [string]$NodeType = 'Resource',
            [string]$Path = $null,
            [string]$ContentHash = $null
        )
        
        [PSCustomObject]@{
            nodeId       = $NodeId
            name         = $Name
            nodeType     = $NodeType
            path         = if ($Path) { $Path } else { "/$Name" }
            fingerprints = [PSCustomObject]@{
                contentHash   = if ($ContentHash) { $ContentHash } else { "hash_$NodeId" }
                attributeHash = "attr_$NodeId"
                transformHash = $null
            }
        }
    }
}

Describe 'WatchProbe' {
    
    Describe 'Get-ProbeHash' {
        It 'Returns consistent hash for same nodes' {
            $nodes = @(
                New-ProbeTestNode -NodeId '100' -Name 'Node1'
                New-ProbeTestNode -NodeId '200' -Name 'Node2'
            )
            
            $hash1 = Get-ProbeHash -Nodes $nodes
            $hash2 = Get-ProbeHash -Nodes $nodes
            
            $hash1 | Should -BeExactly $hash2
        }
        
        It 'Returns consistent hash regardless of input order' {
            $nodes1 = @(
                New-ProbeTestNode -NodeId '100' -Name 'Node1'
                New-ProbeTestNode -NodeId '200' -Name 'Node2'
            )
            $nodes2 = @(
                New-ProbeTestNode -NodeId '200' -Name 'Node2'
                New-ProbeTestNode -NodeId '100' -Name 'Node1'
            )
            
            $hash1 = Get-ProbeHash -Nodes $nodes1
            $hash2 = Get-ProbeHash -Nodes $nodes2
            
            $hash1 | Should -BeExactly $hash2
        }
        
        It 'Returns different hash when content changes' {
            $nodes1 = @(
                New-ProbeTestNode -NodeId '100' -Name 'Node1' -ContentHash 'original'
            )
            $nodes2 = @(
                New-ProbeTestNode -NodeId '100' -Name 'Node1' -ContentHash 'changed'
            )
            
            $hash1 = Get-ProbeHash -Nodes $nodes1
            $hash2 = Get-ProbeHash -Nodes $nodes2
            
            $hash1 | Should -Not -Be $hash2
        }
        
        It 'Returns zero hash for empty nodes' {
            $hash = Get-ProbeHash -Nodes @()
            $hash | Should -Be '0000000000000000'
        }
    }
    
    Describe 'Get-NodeTypeDistribution' {
        It 'Counts nodes by type' {
            $nodes = @(
                New-ProbeTestNode -NodeId '1' -Name 'N1' -NodeType 'Station'
                New-ProbeTestNode -NodeId '2' -Name 'N2' -NodeType 'Station'
                New-ProbeTestNode -NodeId '3' -Name 'N3' -NodeType 'Resource'
                New-ProbeTestNode -NodeId '4' -Name 'N4' -NodeType 'Tool'
            )
            
            $dist = Get-NodeTypeDistribution -Nodes $nodes
            
            $dist['Station'] | Should -Be 2
            $dist['Resource'] | Should -Be 1
            $dist['Tool'] | Should -Be 1
        }
        
        It 'Returns empty hashtable for empty nodes' {
            $dist = Get-NodeTypeDistribution -Nodes @()
            $dist.Count | Should -Be 0
        }
    }
    
    Describe 'Invoke-StageAProbe' {
        BeforeAll {
            $testNodes = @(
                New-ProbeTestNode -NodeId '100' -Name 'Station_A' -NodeType 'Station' -Path '/Station_A'
                New-ProbeTestNode -NodeId '101' -Name 'Robot_1' -NodeType 'Resource' -Path '/Station_A/Robot_1'
                New-ProbeTestNode -NodeId '102' -Name 'Robot_2' -NodeType 'Resource' -Path '/Station_A/Robot_2'
            )
        }
        
        It 'Returns probe result with all metrics' {
            $probe = Invoke-StageAProbe -Nodes $testNodes
            
            $probe.stage | Should -Be 'A'
            $probe.totalCount | Should -Be 3
            $probe.sampleHash | Should -Not -BeNullOrEmpty
            $probe.durationMs | Should -Not -BeNullOrEmpty
            $probe.typeDistribution | Should -Not -BeNullOrEmpty
        }
        
        It 'Detects no changes when nodes are identical' {
            $probe1 = Invoke-StageAProbe -Nodes $testNodes
            $probe2 = Invoke-StageAProbe -Nodes $testNodes -PreviousProbe $probe1
            
            $probe2.hasChanges | Should -BeFalse
        }
        
        It 'Detects count change' {
            $originalNodes = @(
                New-ProbeTestNode -NodeId '1' -Name 'N1'
                New-ProbeTestNode -NodeId '2' -Name 'N2'
            )
            $changedNodes = @(
                New-ProbeTestNode -NodeId '1' -Name 'N1'
                New-ProbeTestNode -NodeId '2' -Name 'N2'
                New-ProbeTestNode -NodeId '3' -Name 'N3'
            )
            
            $probe1 = Invoke-StageAProbe -Nodes $originalNodes
            $probe2 = Invoke-StageAProbe -Nodes $changedNodes -PreviousProbe $probe1
            
            $probe2.hasChanges | Should -BeTrue
            ($probe2.changeHints | Where-Object { $_.type -eq 'count_change' }) | Should -Not -BeNullOrEmpty
        }
        
        It 'Detects hash change even with same count' {
            $originalNodes = @(
                New-ProbeTestNode -NodeId '1' -Name 'N1' -ContentHash 'original'
            )
            $changedNodes = @(
                New-ProbeTestNode -NodeId '1' -Name 'N1' -ContentHash 'modified'
            )
            
            $probe1 = Invoke-StageAProbe -Nodes $originalNodes
            $probe2 = Invoke-StageAProbe -Nodes $changedNodes -PreviousProbe $probe1
            
            $probe2.hasChanges | Should -BeTrue
            ($probe2.changeHints | Where-Object { $_.type -eq 'hash_change' }) | Should -Not -BeNullOrEmpty
        }
        
        It 'Detects type distribution change' {
            $originalNodes = @(
                New-ProbeTestNode -NodeId '1' -Name 'N1' -NodeType 'Station'
                New-ProbeTestNode -NodeId '2' -Name 'N2' -NodeType 'Resource'
            )
            $changedNodes = @(
                New-ProbeTestNode -NodeId '1' -Name 'N1' -NodeType 'Station'
                New-ProbeTestNode -NodeId '2' -Name 'N2' -NodeType 'Station'  # Type changed!
            )
            
            $probe1 = Invoke-StageAProbe -Nodes $originalNodes
            $probe2 = Invoke-StageAProbe -Nodes $changedNodes -PreviousProbe $probe1
            
            $probe2.hasChanges | Should -BeTrue
            ($probe2.changeHints | Where-Object { $_.type -eq 'type_count_change' }) | Should -Not -BeNullOrEmpty
        }
        
        It 'First probe always reports changes' {
            $probe = Invoke-StageAProbe -Nodes $testNodes -PreviousProbe $null
            
            $probe.hasChanges | Should -BeTrue
            ($probe.changeHints | Where-Object { $_.type -eq 'initial_probe' }) | Should -Not -BeNullOrEmpty
        }
    }
    
    Describe 'Invoke-StageBProbe' {
        BeforeAll {
            $testNodes = @(
                New-ProbeTestNode -NodeId '100' -Name 'Station_A' -NodeType 'Station' -Path '/Station_A'
                New-ProbeTestNode -NodeId '101' -Name 'Robot_1' -NodeType 'Resource' -Path '/Station_A/Robot_1'
                New-ProbeTestNode -NodeId '102' -Name 'Robot_2' -NodeType 'Resource' -Path '/Station_A/Robot_2'
                New-ProbeTestNode -NodeId '200' -Name 'Station_B' -NodeType 'Station' -Path '/Station_B'
            )
        }
        
        It 'Returns detailed probe metrics' {
            $probe = Invoke-StageBProbe -Nodes $testNodes
            
            $probe.stage | Should -Be 'B'
            $probe.nodesAnalyzed | Should -BeGreaterThan 0
            $probe.subtreeStats | Should -Not -BeNullOrEmpty
        }
        
        It 'Filters by node type' {
            $probe = Invoke-StageBProbe -Nodes $testNodes -NodeTypeFilter @('Station')
            
            $probe.nodesAnalyzed | Should -Be 2  # Only Station nodes
        }
        
        It 'Filters by path prefix' {
            $probe = Invoke-StageBProbe -Nodes $testNodes -PathPrefixFilter '/Station_A'
            
            $probe.nodesAnalyzed | Should -Be 3  # Station_A and its children
        }
        
        It 'Respects max nodes limit' {
            $probe = Invoke-StageBProbe -Nodes $testNodes -MaxNodes 2
            
            $probe.nodesAnalyzed | Should -Be 2
        }
    }
    
    Describe 'Invoke-TwoStageProbe' {
        BeforeAll {
            $testNodes = @(
                New-ProbeTestNode -NodeId '1' -Name 'N1' -NodeType 'Station'
                New-ProbeTestNode -NodeId '2' -Name 'N2' -NodeType 'Resource'
            )
        }
        
        It 'Runs both stages when changes detected' {
            $probe = Invoke-TwoStageProbe -Nodes $testNodes -PreviousProbe $null
            
            $probe.stageA | Should -Not -BeNullOrEmpty
            $probe.stageB | Should -Not -BeNullOrEmpty
            $probe.metrics.stagesRun | Should -Contain 'A'
            $probe.metrics.stagesRun | Should -Contain 'B'
        }
        
        It 'Skips Stage B when no changes' {
            $probe1 = Invoke-TwoStageProbe -Nodes $testNodes
            $probe2 = Invoke-TwoStageProbe -Nodes $testNodes -PreviousProbe $probe1.stageA
            
            $probe2.stageA | Should -Not -BeNullOrEmpty
            $probe2.stageB | Should -BeNullOrEmpty
            $probe2.metrics.stagesRun | Should -Not -Contain 'B'
        }
        
        It 'Forces Stage B when requested' {
            $probe1 = Invoke-TwoStageProbe -Nodes $testNodes
            $probe2 = Invoke-TwoStageProbe -Nodes $testNodes -PreviousProbe $probe1.stageA -ForceStageB
            
            $probe2.stageB | Should -Not -BeNullOrEmpty
        }
        
        It 'Returns combined metrics' {
            $probe = Invoke-TwoStageProbe -Nodes $testNodes -ForceStageB
            
            $probe.totalDurationMs | Should -Not -BeNullOrEmpty
            $probe.metrics.rowsScanned | Should -BeGreaterThan 0
            $probe.metrics.queriesRun | Should -Be 2
        }
    }
    
    Describe 'New-ProbeMetadata' {
        It 'Creates metadata for meta.json inclusion' {
            $probe = Invoke-TwoStageProbe -Nodes @(
                New-ProbeTestNode -NodeId '1' -Name 'Test'
            )
            
            $metadata = New-ProbeMetadata -ProbeResult $probe
            
            $metadata.probeDurationMs | Should -Not -BeNullOrEmpty
            $metadata.rowsScanned | Should -Not -BeNullOrEmpty
            $metadata.queriesRun | Should -Not -BeNullOrEmpty
            $metadata.estimatedCost | Should -Not -BeNullOrEmpty
            $metadata.hasChanges | Should -Not -BeNullOrEmpty
            $metadata.stagesRun | Should -Not -BeNullOrEmpty
        }
    }
}
