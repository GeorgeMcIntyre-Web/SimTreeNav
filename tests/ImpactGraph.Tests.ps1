# ImpactGraph.Tests.ps1
# Tests for ImpactMap v1 (Blast radius)

BeforeAll {
    $scriptRoot = Split-Path $PSScriptRoot -Parent
    . "$scriptRoot\src\powershell\v02\analysis\ImpactEngine.ps1"
}

Describe 'Build-DependencyGraph' {
    BeforeAll {
        # Create test node hierarchy:
        # Root -> Station -> ResourceGroup -> Resource -> ToolInstance (links to Prototype)
        $testNodes = @(
            [PSCustomObject]@{ nodeId = 'N001'; name = 'Root'; nodeType = 'Root'; parentId = $null; path = '/Root'; links = $null }
            [PSCustomObject]@{ nodeId = 'N002'; name = 'Station_A'; nodeType = 'Station'; parentId = 'N001'; path = '/Root/Station_A'; links = $null }
            [PSCustomObject]@{ nodeId = 'N003'; name = 'RG_1'; nodeType = 'ResourceGroup'; parentId = 'N002'; path = '/Root/Station_A/RG_1'; links = $null }
            [PSCustomObject]@{ nodeId = 'N004'; name = 'Robot_1'; nodeType = 'Resource'; parentId = 'N003'; path = '/Root/Station_A/RG_1/Robot_1'; links = $null }
            [PSCustomObject]@{ nodeId = 'N005'; name = 'WeldGun_Proto'; nodeType = 'ToolPrototype'; parentId = 'N001'; path = '/Root/WeldGun_Proto'; links = $null }
            [PSCustomObject]@{ nodeId = 'N006'; name = 'WeldGun_1'; nodeType = 'ToolInstance'; parentId = 'N004'; path = '/Root/Station_A/RG_1/Robot_1/WeldGun_1'; links = [PSCustomObject]@{ prototypeId = 'N005' } }
            [PSCustomObject]@{ nodeId = 'N007'; name = 'WeldGun_2'; nodeType = 'ToolInstance'; parentId = 'N004'; path = '/Root/Station_A/RG_1/Robot_1/WeldGun_2'; links = [PSCustomObject]@{ prototypeId = 'N005' } }
        )
    }
    
    It 'Builds graph with node lookup' {
        $graph = Build-DependencyGraph -Nodes $testNodes
        
        $graph.nodes.Count | Should -Be 7
        $graph.nodes['N001'].name | Should -Be 'Root'
    }
    
    It 'Builds parent-child relationships' {
        $graph = Build-DependencyGraph -Nodes $testNodes
        
        $graph.children['N001'] | Should -Contain 'N002'
        $graph.children['N001'] | Should -Contain 'N005'
        $graph.children['N002'] | Should -Contain 'N003'
        $graph.parents['N002'] | Should -Be 'N001'
    }
    
    It 'Builds prototype-instance relationships' {
        $graph = Build-DependencyGraph -Nodes $testNodes
        
        $graph.prototypeInstances['N005'] | Should -Contain 'N006'
        $graph.prototypeInstances['N005'] | Should -Contain 'N007'
        $graph.instancePrototypes['N006'] | Should -Be 'N005'
    }
    
    It 'Returns empty collections for empty input' {
        $graph = Build-DependencyGraph -Nodes @()
        
        $graph.nodes.Count | Should -Be 0
    }
}

Describe 'Get-DownstreamDependents' {
    BeforeAll {
        $testNodes = @(
            [PSCustomObject]@{ nodeId = 'N001'; name = 'Root'; nodeType = 'Root'; parentId = $null; path = '/Root'; links = $null }
            [PSCustomObject]@{ nodeId = 'N002'; name = 'Station_A'; nodeType = 'Station'; parentId = 'N001'; path = '/Root/Station_A'; links = $null }
            [PSCustomObject]@{ nodeId = 'N003'; name = 'RG_1'; nodeType = 'ResourceGroup'; parentId = 'N002'; path = '/Root/Station_A/RG_1'; links = $null }
            [PSCustomObject]@{ nodeId = 'N004'; name = 'Robot_1'; nodeType = 'Resource'; parentId = 'N003'; path = '/Root/Station_A/RG_1/Robot_1'; links = $null }
            [PSCustomObject]@{ nodeId = 'N005'; name = 'WeldGun_Proto'; nodeType = 'ToolPrototype'; parentId = 'N001'; path = '/Root/WeldGun_Proto'; links = $null }
            [PSCustomObject]@{ nodeId = 'N006'; name = 'WeldGun_1'; nodeType = 'ToolInstance'; parentId = 'N004'; path = '/Root/Station_A/RG_1/Robot_1/WeldGun_1'; links = [PSCustomObject]@{ prototypeId = 'N005' } }
        )
        $graph = Build-DependencyGraph -Nodes $testNodes
    }
    
    It 'Returns direct children at depth 1' {
        $downstream = Get-DownstreamDependents -NodeId 'N002' -Graph $graph -MaxDepth 1
        
        $downstream.Count | Should -Be 1
        $downstream[0].nodeId | Should -Be 'N003'
        $downstream[0].depth | Should -Be 1
    }
    
    It 'Returns transitive dependents at depth > 1' {
        $downstream = Get-DownstreamDependents -NodeId 'N002' -Graph $graph -MaxDepth 5
        
        $downstream.Count | Should -BeGreaterThan 1
        ($downstream | Where-Object { $_.depth -gt 1 }).Count | Should -BeGreaterThan 0
    }
    
    It 'Returns prototype instances' {
        $downstream = Get-DownstreamDependents -NodeId 'N005' -Graph $graph -MaxDepth 3
        
        $downstream.nodeId | Should -Contain 'N006'
        ($downstream | Where-Object { $_.relation -eq 'instance' }).Count | Should -BeGreaterThan 0
    }
    
    It 'Respects MaxDepth limit' {
        $shallow = Get-DownstreamDependents -NodeId 'N001' -Graph $graph -MaxDepth 1
        $deep = Get-DownstreamDependents -NodeId 'N001' -Graph $graph -MaxDepth 5
        
        $shallow.Count | Should -BeLessThan $deep.Count
    }
}

Describe 'Get-UpstreamDependencies' {
    BeforeAll {
        $testNodes = @(
            [PSCustomObject]@{ nodeId = 'N001'; name = 'Root'; nodeType = 'Root'; parentId = $null; path = '/Root'; links = $null }
            [PSCustomObject]@{ nodeId = 'N002'; name = 'Station_A'; nodeType = 'Station'; parentId = 'N001'; path = '/Root/Station_A'; links = $null }
            [PSCustomObject]@{ nodeId = 'N003'; name = 'RG_1'; nodeType = 'ResourceGroup'; parentId = 'N002'; path = '/Root/Station_A/RG_1'; links = $null }
            [PSCustomObject]@{ nodeId = 'N004'; name = 'Robot_1'; nodeType = 'Resource'; parentId = 'N003'; path = '/Root/Station_A/RG_1/Robot_1'; links = $null }
            [PSCustomObject]@{ nodeId = 'N005'; name = 'WeldGun_Proto'; nodeType = 'ToolPrototype'; parentId = 'N001'; path = '/Root/WeldGun_Proto'; links = $null }
            [PSCustomObject]@{ nodeId = 'N006'; name = 'WeldGun_1'; nodeType = 'ToolInstance'; parentId = 'N004'; path = '/Root/Station_A/RG_1/Robot_1/WeldGun_1'; links = [PSCustomObject]@{ prototypeId = 'N005' } }
        )
        $graph = Build-DependencyGraph -Nodes $testNodes
    }
    
    It 'Returns parent chain' {
        $upstream = Get-UpstreamDependencies -NodeId 'N004' -Graph $graph -MaxDepth 5
        
        $upstream.nodeId | Should -Contain 'N003'  # Direct parent
        $upstream.nodeId | Should -Contain 'N002'  # Grandparent
        $upstream.nodeId | Should -Contain 'N001'  # Root
    }
    
    It 'Returns prototype for instance' {
        $upstream = Get-UpstreamDependencies -NodeId 'N006' -Graph $graph -MaxDepth 5
        
        $upstream.nodeId | Should -Contain 'N005'  # Prototype
        ($upstream | Where-Object { $_.relation -eq 'prototype' }).Count | Should -BeGreaterThan 0
    }
}

Describe 'Compute-RiskScore' {
    It 'Returns score between 0 and 1' {
        $node = [PSCustomObject]@{ nodeId = 'N001'; name = 'Station'; nodeType = 'Station' }
        $downstream = @(
            [PSCustomObject]@{ nodeId = 'N002'; depth = 1 }
            [PSCustomObject]@{ nodeId = 'N003'; depth = 1 }
            [PSCustomObject]@{ nodeId = 'N004'; depth = 2 }
        )
        
        $score = Compute-RiskScore -Node $node -Downstream $downstream
        
        $score | Should -BeGreaterOrEqual 0
        $score | Should -BeLessOrEqual 1
    }
    
    It 'Returns higher score for more dependents' {
        $node = [PSCustomObject]@{ nodeId = 'N001'; name = 'Station'; nodeType = 'Station' }
        $fewDependents = @([PSCustomObject]@{ nodeId = 'N002'; depth = 1 })
        $manyDependents = 1..20 | ForEach-Object { [PSCustomObject]@{ nodeId = "N$_"; depth = 1 } }
        
        $scoreFew = Compute-RiskScore -Node $node -Downstream $fewDependents
        $scoreMany = Compute-RiskScore -Node $node -Downstream $manyDependents
        
        $scoreMany | Should -BeGreaterThan $scoreFew
    }
    
    It 'Is deterministic for same input' {
        $node = [PSCustomObject]@{ nodeId = 'N001'; name = 'Station'; nodeType = 'Station' }
        $downstream = @([PSCustomObject]@{ nodeId = 'N002'; depth = 1 })
        
        $score1 = Compute-RiskScore -Node $node -Downstream $downstream
        $score2 = Compute-RiskScore -Node $node -Downstream $downstream
        
        $score1 | Should -Be $score2
    }
}

Describe 'Get-NodeImpact' {
    BeforeAll {
        $testNodes = @(
            [PSCustomObject]@{ nodeId = 'N001'; name = 'Root'; nodeType = 'Root'; parentId = $null; path = '/Root'; links = $null }
            [PSCustomObject]@{ nodeId = 'N002'; name = 'Station_A'; nodeType = 'Station'; parentId = 'N001'; path = '/Root/Station_A'; links = $null }
            [PSCustomObject]@{ nodeId = 'N003'; name = 'RG_1'; nodeType = 'ResourceGroup'; parentId = 'N002'; path = '/Root/Station_A/RG_1'; links = $null }
            [PSCustomObject]@{ nodeId = 'N004'; name = 'Robot_1'; nodeType = 'Resource'; parentId = 'N003'; path = '/Root/Station_A/RG_1/Robot_1'; links = $null }
            [PSCustomObject]@{ nodeId = 'N005'; name = 'WeldGun_Proto'; nodeType = 'ToolPrototype'; parentId = 'N001'; path = '/Root/WeldGun_Proto'; links = $null }
            [PSCustomObject]@{ nodeId = 'N006'; name = 'WeldGun_1'; nodeType = 'ToolInstance'; parentId = 'N004'; path = '/Root/Station_A/RG_1/Robot_1/WeldGun_1'; links = [PSCustomObject]@{ prototypeId = 'N005' } }
        )
    }
    
    It 'Returns complete impact object' {
        $impact = Get-NodeImpact -NodeId 'N002' -Nodes $testNodes
        
        $impact.nodeId | Should -Be 'N002'
        $impact.nodeName | Should -Be 'Station_A'
        $impact.nodeType | Should -Be 'Station'
        $impact.riskScore | Should -BeGreaterOrEqual 0
        $impact.riskLevel | Should -Not -BeNullOrEmpty
        $impact.upstreamCount | Should -BeGreaterOrEqual 0
        $impact.downstreamCount | Should -BeGreaterOrEqual 0
    }
    
    It 'Counts direct and transitive dependents separately' {
        $impact = Get-NodeImpact -NodeId 'N002' -Nodes $testNodes -MaxDepth 5
        
        $impact.directDependents | Should -BeGreaterOrEqual 0
        $impact.transitiveDependents | Should -BeGreaterOrEqual 0
    }
    
    It 'Returns null for non-existent node' {
        $impact = Get-NodeImpact -NodeId 'NONEXISTENT' -Nodes $testNodes
        
        $impact | Should -BeNullOrEmpty
    }
}

Describe 'Get-ImpactForChanges' {
    BeforeAll {
        $testNodes = @(
            [PSCustomObject]@{ nodeId = 'N001'; name = 'Root'; nodeType = 'Root'; parentId = $null; path = '/Root'; links = $null }
            [PSCustomObject]@{ nodeId = 'N002'; name = 'Station_A'; nodeType = 'Station'; parentId = 'N001'; path = '/Root/Station_A'; links = $null }
            [PSCustomObject]@{ nodeId = 'N003'; name = 'RG_1'; nodeType = 'ResourceGroup'; parentId = 'N002'; path = '/Root/Station_A/RG_1'; links = $null }
        )
        $testChanges = @(
            [PSCustomObject]@{ nodeId = 'N002'; changeType = 'renamed' }
            [PSCustomObject]@{ nodeId = 'N003'; changeType = 'moved' }
        )
    }
    
    It 'Returns aggregate statistics' {
        $result = Get-ImpactForChanges -Changes $testChanges -Nodes $testNodes
        
        $result.totalChangesAnalyzed | Should -BeGreaterOrEqual 0
        $result.totalDownstreamImpact | Should -BeGreaterOrEqual 0
        $result.topRiskNodes | Should -Not -BeNullOrEmpty
    }
    
    It 'Sorts by risk score descending' {
        $result = Get-ImpactForChanges -Changes $testChanges -Nodes $testNodes
        
        if ($result.impacts.Count -gt 1) {
            $result.impacts[0].riskScore | Should -BeGreaterOrEqual $result.impacts[1].riskScore
        }
    }
}

Describe 'Impact Output Determinism' {
    BeforeAll {
        $testNodes = @(
            [PSCustomObject]@{ nodeId = 'N001'; name = 'Root'; nodeType = 'Root'; parentId = $null; path = '/Root'; links = $null }
            [PSCustomObject]@{ nodeId = 'N002'; name = 'Station_A'; nodeType = 'Station'; parentId = 'N001'; path = '/Root/Station_A'; links = $null }
            [PSCustomObject]@{ nodeId = 'N003'; name = 'RG_1'; nodeType = 'ResourceGroup'; parentId = 'N002'; path = '/Root/Station_A/RG_1'; links = $null }
            [PSCustomObject]@{ nodeId = 'N004'; name = 'Robot_1'; nodeType = 'Resource'; parentId = 'N003'; path = '/Root/Station_A/RG_1/Robot_1'; links = $null }
        )
    }
    
    It 'Produces identical output for same input' {
        $impact1 = Get-NodeImpact -NodeId 'N002' -Nodes $testNodes
        $impact2 = Get-NodeImpact -NodeId 'N002' -Nodes $testNodes
        
        $impact1.riskScore | Should -Be $impact2.riskScore
        $impact1.downstreamCount | Should -Be $impact2.downstreamCount
        $impact1.upstreamCount | Should -Be $impact2.upstreamCount
    }
    
    It 'Produces identical JSON for same input' {
        $impact1 = Get-NodeImpact -NodeId 'N002' -Nodes $testNodes
        $impact2 = Get-NodeImpact -NodeId 'N002' -Nodes $testNodes
        
        $json1 = $impact1 | ConvertTo-Json -Depth 5 -Compress
        $json2 = $impact2 | ConvertTo-Json -Depth 5 -Compress
        
        $json1 | Should -Be $json2
    }
}

Describe 'Get-RiskLevel' {
    It 'Returns Critical for score >= 0.8' {
        Get-RiskLevel -Score 0.8 | Should -Be 'Critical'
        Get-RiskLevel -Score 1.0 | Should -Be 'Critical'
    }
    
    It 'Returns High for score >= 0.6' {
        Get-RiskLevel -Score 0.6 | Should -Be 'High'
        Get-RiskLevel -Score 0.7 | Should -Be 'High'
    }
    
    It 'Returns Medium for score >= 0.4' {
        Get-RiskLevel -Score 0.4 | Should -Be 'Medium'
        Get-RiskLevel -Score 0.5 | Should -Be 'Medium'
    }
    
    It 'Returns Low for score >= 0.2' {
        Get-RiskLevel -Score 0.2 | Should -Be 'Low'
        Get-RiskLevel -Score 0.3 | Should -Be 'Low'
    }
    
    It 'Returns Info for score < 0.2' {
        Get-RiskLevel -Score 0.1 | Should -Be 'Info'
        Get-RiskLevel -Score 0 | Should -Be 'Info'
    }
}
