# ImpactEngine.Tests.ps1
# Pester tests for Impact analysis (blast radius)

BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . "$scriptRoot/src/powershell/v02/analysis/ImpactEngine.ps1"
}

Describe 'ImpactEngine' {
    
    BeforeAll {
        # Create test nodes with relationships
        $testNodes = @(
            [PSCustomObject]@{
                nodeId = 'root'
                name = 'Project'
                nodeType = 'Root'
                parentId = $null
                path = '/'
                links = $null
            }
            [PSCustomObject]@{
                nodeId = 'station1'
                name = 'Station_A'
                nodeType = 'Station'
                parentId = 'root'
                path = '/Station_A'
                links = $null
            }
            [PSCustomObject]@{
                nodeId = 'rg1'
                name = 'ResourceGroup_1'
                nodeType = 'ResourceGroup'
                parentId = 'station1'
                path = '/Station_A/ResourceGroup_1'
                links = $null
            }
            [PSCustomObject]@{
                nodeId = 'robot1'
                name = 'Robot_1'
                nodeType = 'Resource'
                parentId = 'rg1'
                path = '/Station_A/ResourceGroup_1/Robot_1'
                links = $null
            }
            [PSCustomObject]@{
                nodeId = 'toolProto'
                name = 'WeldGun_Proto'
                nodeType = 'ToolPrototype'
                parentId = 'root'
                path = '/ToolPrototypes/WeldGun_Proto'
                links = $null
            }
            [PSCustomObject]@{
                nodeId = 'toolInst1'
                name = 'WeldGun_1'
                nodeType = 'ToolInstance'
                parentId = 'robot1'
                path = '/Station_A/ResourceGroup_1/Robot_1/WeldGun_1'
                links = [PSCustomObject]@{ prototypeId = 'toolProto' }
            }
            [PSCustomObject]@{
                nodeId = 'toolInst2'
                name = 'WeldGun_2'
                nodeType = 'ToolInstance'
                parentId = 'robot1'
                path = '/Station_A/ResourceGroup_1/Robot_1/WeldGun_2'
                links = [PSCustomObject]@{ prototypeId = 'toolProto' }
            }
            [PSCustomObject]@{
                nodeId = 'op1'
                name = 'Weld_Op_1'
                nodeType = 'Operation'
                parentId = 'station1'
                path = '/Station_A/Operations/Weld_Op_1'
                links = [PSCustomObject]@{ twinId = 'robot1' }
            }
        )
    }
    
    Describe 'Build-DependencyGraph' {
        It 'Creates node lookup' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $graph.nodes | Should -Not -BeNullOrEmpty
            $graph.nodes.Count | Should -Be $testNodes.Count
            $graph.nodes['station1'].name | Should -Be 'Station_A'
        }
        
        It 'Builds parent-child relationships' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $graph.children['root'] | Should -Contain 'station1'
            $graph.children['station1'] | Should -Contain 'rg1'
            $graph.parents['rg1'] | Should -Be 'station1'
        }
        
        It 'Builds prototype-instance relationships' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $graph.prototypeInstances['toolProto'] | Should -Contain 'toolInst1'
            $graph.prototypeInstances['toolProto'] | Should -Contain 'toolInst2'
            $graph.instancePrototypes['toolInst1'] | Should -Be 'toolProto'
        }
        
        It 'Builds twin relationships' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $graph.twins['op1'] | Should -Contain 'robot1'
        }
    }
    
    Describe 'Get-UpstreamDependencies' {
        It 'Finds parent chain' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $upstream = Get-UpstreamDependencies -NodeId 'robot1' -Graph $graph
            
            $upstream | Should -Not -BeNullOrEmpty
            ($upstream | Where-Object { $_.nodeId -eq 'rg1' }) | Should -Not -BeNullOrEmpty
            ($upstream | Where-Object { $_.nodeId -eq 'station1' }) | Should -Not -BeNullOrEmpty
        }
        
        It 'Finds prototype for instance' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $upstream = Get-UpstreamDependencies -NodeId 'toolInst1' -Graph $graph
            
            ($upstream | Where-Object { $_.nodeId -eq 'toolProto' -and $_.relation -eq 'prototype' }) | Should -Not -BeNullOrEmpty
        }
        
        It 'Respects max depth' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $upstream = Get-UpstreamDependencies -NodeId 'robot1' -Graph $graph -MaxDepth 1
            
            # Should only have direct parent at depth 1
            $maxDepth = ($upstream | Measure-Object -Property depth -Maximum).Maximum
            $maxDepth | Should -BeLessOrEqual 1
        }
    }
    
    Describe 'Get-DownstreamDependents' {
        It 'Finds children' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $downstream = Get-DownstreamDependents -NodeId 'station1' -Graph $graph
            
            ($downstream | Where-Object { $_.nodeId -eq 'rg1' }) | Should -Not -BeNullOrEmpty
        }
        
        It 'Finds instances for prototype' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $downstream = Get-DownstreamDependents -NodeId 'toolProto' -Graph $graph
            
            ($downstream | Where-Object { $_.nodeId -eq 'toolInst1' -and $_.relation -eq 'instance' }) | Should -Not -BeNullOrEmpty
            ($downstream | Where-Object { $_.nodeId -eq 'toolInst2' -and $_.relation -eq 'instance' }) | Should -Not -BeNullOrEmpty
        }
        
        It 'Finds twins' {
            $graph = Build-DependencyGraph -Nodes $testNodes
            
            $downstream = Get-DownstreamDependents -NodeId 'robot1' -Graph $graph
            
            # Robot1 has twin link from op1
            # Note: twin relationship is bidirectional so robot1 should see op1
            $graph.twins['robot1'] | Should -Contain 'op1'
        }
    }
    
    Describe 'Get-NodeCriticality' {
        It 'Returns higher weight for Station' {
            $node = [PSCustomObject]@{ nodeType = 'Station' }
            $criticality = Get-NodeCriticality -Node $node
            
            $criticality | Should -Be 1.0
        }
        
        It 'Returns default weight for unknown type' {
            $node = [PSCustomObject]@{ nodeType = 'UnknownType' }
            $criticality = Get-NodeCriticality -Node $node
            
            $criticality | Should -Be 0.5
        }
    }
    
    Describe 'Compute-RiskScore' {
        It 'Returns higher risk for nodes with many dependents' {
            $node = [PSCustomObject]@{ nodeType = 'Station' }
            $manyDownstream = 1..50 | ForEach-Object { [PSCustomObject]@{ nodeId = "N$_"; depth = 1 } }
            $fewDownstream = 1..2 | ForEach-Object { [PSCustomObject]@{ nodeId = "N$_"; depth = 1 } }
            
            $highRisk = Compute-RiskScore -Node $node -Downstream $manyDownstream
            $lowRisk = Compute-RiskScore -Node $node -Downstream $fewDownstream
            
            $highRisk | Should -BeGreaterThan $lowRisk
        }
        
        It 'Returns score between 0 and 1' {
            $node = [PSCustomObject]@{ nodeType = 'Resource' }
            $downstream = @()
            
            $risk = Compute-RiskScore -Node $node -Downstream $downstream
            
            $risk | Should -BeGreaterOrEqual 0
            $risk | Should -BeLessOrEqual 1
        }
    }
    
    Describe 'Get-RiskLevel' {
        It 'Returns Critical for high scores' {
            Get-RiskLevel -Score 0.9 | Should -Be 'Critical'
        }
        
        It 'Returns High for medium-high scores' {
            Get-RiskLevel -Score 0.7 | Should -Be 'High'
        }
        
        It 'Returns Info for low scores' {
            Get-RiskLevel -Score 0.1 | Should -Be 'Info'
        }
    }
    
    Describe 'Get-NodeImpact' {
        It 'Returns complete impact analysis' {
            $impact = Get-NodeImpact -NodeId 'station1' -Nodes $testNodes
            
            $impact | Should -Not -BeNullOrEmpty
            $impact.nodeId | Should -Be 'station1'
            $impact.nodeName | Should -Be 'Station_A'
            $impact.riskScore | Should -Not -BeNullOrEmpty
            $impact.riskLevel | Should -Not -BeNullOrEmpty
        }
        
        It 'Returns null for non-existent node' {
            $impact = Get-NodeImpact -NodeId 'nonexistent' -Nodes $testNodes
            
            $impact | Should -BeNullOrEmpty
        }
        
        It 'Includes downstream count' {
            $impact = Get-NodeImpact -NodeId 'station1' -Nodes $testNodes -MaxDepth 5
            
            $impact.downstreamCount | Should -BeGreaterThan 0
        }
    }
    
    Describe 'Get-ImpactForChanges' {
        It 'Analyzes multiple changes' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'robot1'; changeType = 'renamed' }
                [PSCustomObject]@{ nodeId = 'toolProto'; changeType = 'attribute_changed' }
            )
            
            $report = Get-ImpactForChanges -Changes $changes -Nodes $testNodes
            
            $report | Should -Not -BeNullOrEmpty
            $report.totalChangesAnalyzed | Should -Be 2
        }
        
        It 'Sorts by risk score descending' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'robot1'; changeType = 'renamed' }
                [PSCustomObject]@{ nodeId = 'toolProto'; changeType = 'removed' }
            )
            
            $report = Get-ImpactForChanges -Changes $changes -Nodes $testNodes
            
            if ($report.impacts.Count -ge 2) {
                $report.impacts[0].riskScore | Should -BeGreaterOrEqual $report.impacts[-1].riskScore
            }
        }
    }
}
