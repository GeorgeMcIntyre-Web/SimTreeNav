# ComplianceEngine.Tests.ps1
# Pester tests for Golden template compliance checking

BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . "$scriptRoot/src/powershell/v02/analysis/ComplianceEngine.ps1"
}

Describe 'ComplianceEngine' {
    
    Describe 'New-GoldenTemplate' {
        It 'Creates template with defaults' {
            $template = New-GoldenTemplate -Name 'TestTemplate'
            
            $template.name | Should -Be 'TestTemplate'
            # requiredTypes starts as empty array
            $template.PSObject.Properties.Name | Should -Contain 'requiredTypes'
            $template.namingRules | Should -Not -BeNullOrEmpty
        }
        
        It 'Includes custom naming rules' {
            $rules = @{ Station = '^ST_\d+$' }
            $template = New-GoldenTemplate -Name 'Custom' -NamingRules $rules
            
            $template.namingRules.Station | Should -Be '^ST_\d+$'
        }
    }
    
    Describe 'New-TypeRequirement' {
        It 'Creates requirement with min count' {
            $req = New-TypeRequirement -NodeType 'Station' -MinCount 2
            
            $req.nodeType | Should -Be 'Station'
            $req.minCount | Should -Be 2
            $req.required | Should -BeTrue
        }
        
        It 'Creates requirement with name pattern' {
            $req = New-TypeRequirement -NodeType 'Robot' -NamePattern '^Robot_\d+$'
            
            $req.namePattern | Should -Be '^Robot_\d+$'
        }
        
        It 'Sets required flag when using -Required' {
            $req = New-TypeRequirement -NodeType 'Tool' -Required
            
            $req.required | Should -BeTrue
            $req.minCount | Should -BeGreaterOrEqual 1
        }
    }
    
    Describe 'Test-NamingConvention' {
        It 'Passes matching names' {
            $node = [PSCustomObject]@{ nodeId = 'N1'; name = 'Station_Alpha'; nodeType = 'Station' }
            $rules = @{ Station = '^Station_[A-Za-z]+$' }
            
            $result = Test-NamingConvention -Node $node -NamingRules $rules
            
            $result.passed | Should -BeTrue
        }
        
        It 'Fails non-matching names' {
            $node = [PSCustomObject]@{ nodeId = 'N1'; name = 'bad name!'; nodeType = 'Station' }
            $rules = @{ Station = '^Station_[A-Za-z]+$' }
            
            $result = Test-NamingConvention -Node $node -NamingRules $rules
            
            $result.passed | Should -BeFalse
            $result.reason | Should -Match 'Does not match'
        }
        
        It 'Passes when no rule defined' {
            $node = [PSCustomObject]@{ nodeId = 'N1'; name = 'anything'; nodeType = 'UnknownType' }
            $rules = @{ Station = '^Station_.*$' }
            
            $result = Test-NamingConvention -Node $node -NamingRules $rules
            
            $result.passed | Should -BeTrue
        }
    }
    
    Describe 'Test-TypeRequirements' {
        It 'Passes when requirements met' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'S1'; name = 'Station1'; nodeType = 'Station' }
                [PSCustomObject]@{ nodeId = 'S2'; name = 'Station2'; nodeType = 'Station' }
            )
            $requirements = @(
                (New-TypeRequirement -NodeType 'Station' -MinCount 2)
            )
            
            $results = Test-TypeRequirements -Nodes $nodes -Requirements $requirements
            
            $results[0].passed | Should -BeTrue
        }
        
        It 'Fails when minimum not met' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'S1'; name = 'Station1'; nodeType = 'Station' }
            )
            $requirements = @(
                (New-TypeRequirement -NodeType 'Station' -MinCount 3)
            )
            
            $results = Test-TypeRequirements -Nodes $nodes -Requirements $requirements
            
            $results[0].passed | Should -BeFalse
            $results[0].meetsMinimum | Should -BeFalse
        }
        
        It 'Fails when maximum exceeded' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'S1'; name = 'Station1'; nodeType = 'Station' }
                [PSCustomObject]@{ nodeId = 'S2'; name = 'Station2'; nodeType = 'Station' }
                [PSCustomObject]@{ nodeId = 'S3'; name = 'Station3'; nodeType = 'Station' }
            )
            $requirements = @(
                (New-TypeRequirement -NodeType 'Station' -MinCount 1 -MaxCount 2)
            )
            
            $results = Test-TypeRequirements -Nodes $nodes -Requirements $requirements
            
            $results[0].passed | Should -BeFalse
            $results[0].meetsMaximum | Should -BeFalse
        }
        
        It 'Reports name pattern violations' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'S1'; name = 'Station_01'; nodeType = 'Station' }
                [PSCustomObject]@{ nodeId = 'S2'; name = 'bad name'; nodeType = 'Station' }
            )
            $requirements = @(
                (New-TypeRequirement -NodeType 'Station' -MinCount 1 -NamePattern '^Station_\d+$')
            )
            
            $results = Test-TypeRequirements -Nodes $nodes -Requirements $requirements
            
            $results[0].nameViolations | Should -Contain 'bad name'
        }
    }
    
    Describe 'Test-LinkRequirements' {
        It 'Passes when links exist' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'proto'; name = 'Proto'; nodeType = 'ToolPrototype'; links = $null }
                [PSCustomObject]@{ nodeId = 'inst'; name = 'Instance'; nodeType = 'ToolInstance'; links = [PSCustomObject]@{ prototypeId = 'proto' } }
            )
            $requirements = @(
                [PSCustomObject]@{ fromType = 'ToolInstance'; toType = 'ToolPrototype'; linkType = 'prototypeId' }
            )
            
            $results = Test-LinkRequirements -Nodes $nodes -Requirements $requirements
            
            $results[0].passed | Should -BeTrue
        }
        
        It 'Fails when links missing' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'proto'; name = 'Proto'; nodeType = 'ToolPrototype'; links = $null }
                [PSCustomObject]@{ nodeId = 'inst'; name = 'Instance'; nodeType = 'ToolInstance'; links = $null }
            )
            $requirements = @(
                [PSCustomObject]@{ fromType = 'ToolInstance'; toType = 'ToolPrototype'; linkType = 'prototypeId' }
            )
            
            $results = Test-LinkRequirements -Nodes $nodes -Requirements $requirements
            
            $results[0].passed | Should -BeFalse
            $results[0].unlinkedFrom | Should -Contain 'inst'
        }
    }
    
    Describe 'Get-ComplianceLevel' {
        It 'Returns Excellent for high scores' {
            Get-ComplianceLevel -Score 0.98 | Should -Be 'Excellent'
        }
        
        It 'Returns Good for good scores' {
            Get-ComplianceLevel -Score 0.88 | Should -Be 'Good'
        }
        
        It 'Returns NonCompliant for low scores' {
            Get-ComplianceLevel -Score 0.3 | Should -Be 'NonCompliant'
        }
    }
    
    Describe 'Test-Compliance' {
        It 'Produces full compliance report' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = 'S1'; name = 'Station_01'; nodeType = 'Station' }
                [PSCustomObject]@{ nodeId = 'R1'; name = 'Robot_01'; nodeType = 'Resource' }
            )
            $template = New-GoldenTemplate -Name 'TestTemplate' -NamingRules @{
                Station = '^Station_\d+$'
                Resource = '^Robot_\d+$'
            }
            $template.requiredTypes = @(
                (New-TypeRequirement -NodeType 'Station' -MinCount 1)
            )
            
            $report = Test-Compliance -Nodes $nodes -Template $template
            
            $report | Should -Not -BeNullOrEmpty
            $report.templateName | Should -Be 'TestTemplate'
            $report.score | Should -BeGreaterOrEqual 0
            $report.level | Should -Not -BeNullOrEmpty
            $report.typeRequirements | Should -Not -BeNullOrEmpty
            $report.namingConventions | Should -Not -BeNullOrEmpty
        }
        
        It 'Generates action items' {
            $nodes = @()
            $template = New-GoldenTemplate -Name 'Strict'
            $template.requiredTypes = @(
                (New-TypeRequirement -NodeType 'Station' -MinCount 1 -Required)
            )
            
            $report = Test-Compliance -Nodes $nodes -Template $template
            
            $report.actionItems | Should -Not -BeNullOrEmpty
            ($report.actionItems | Where-Object { $_.category -eq 'MissingRequired' }) | Should -Not -BeNullOrEmpty
        }
    }
    
    Describe 'Get-ActionItems' {
        It 'Prioritizes critical items first' {
            $typeResults = @(
                [PSCustomObject]@{ nodeType = 'Station'; required = $true; meetsMinimum = $false; meetsMaximum = $true; passed = $false; minCount = 1; actualCount = 0 }
            )
            
            $actions = Get-ActionItems -TypeResults $typeResults -LinkResults @() -NamingResults @()
            
            $actions[0].severity | Should -Be 'Critical'
            $actions[0].category | Should -Be 'MissingRequired'
        }
    }
}
