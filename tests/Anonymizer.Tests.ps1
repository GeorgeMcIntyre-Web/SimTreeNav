# Anonymizer.Tests.ps1
# Tests for dataset anonymization module

BeforeAll {
    $scriptRoot = Split-Path $PSScriptRoot -Parent
    . "$scriptRoot\src\powershell\v02\export\Anonymizer.ps1"
}

Describe 'New-AnonymizationContext' {
    It 'Creates context with default seed' {
        $ctx = New-AnonymizationContext
        
        $ctx | Should -Not -BeNullOrEmpty
        $ctx.seed | Should -Be 'simtreenav-anon'
        $ctx.nameMap | Should -BeOfType [hashtable]
        $ctx.pathMap | Should -BeOfType [hashtable]
        $ctx.idMap | Should -BeOfType [hashtable]
        $ctx.counters | Should -BeOfType [hashtable]
    }
    
    It 'Creates context with custom seed' {
        $ctx = New-AnonymizationContext -Seed 'my-custom-seed'
        
        $ctx.seed | Should -Be 'my-custom-seed'
    }
    
    It 'Sets exportMapping flag' {
        $ctx = New-AnonymizationContext -ExportMapping
        
        $ctx.exportMapping | Should -Be $true
    }
}

Describe 'Get-DeterministicPseudonym' {
    BeforeEach {
        $ctx = New-AnonymizationContext -Seed 'test-seed'
    }
    
    It 'Generates stable pseudonym for same input' {
        $result1 = Get-DeterministicPseudonym -OriginalValue 'TestStation' -NodeType 'Station' -Context $ctx
        $result2 = Get-DeterministicPseudonym -OriginalValue 'TestStation' -NodeType 'Station' -Context $ctx
        
        $result1 | Should -Be $result2
    }
    
    It 'Uses correct prefix for Station type' {
        $result = Get-DeterministicPseudonym -OriginalValue 'MyStation' -NodeType 'Station' -Context $ctx
        
        $result | Should -Match '^ST-\d{4}'
    }
    
    It 'Uses correct prefix for ToolPrototype type' {
        $result = Get-DeterministicPseudonym -OriginalValue 'MyTool' -NodeType 'ToolPrototype' -Context $ctx
        
        $result | Should -Match '^TP-\d{4}'
    }
    
    It 'Uses correct prefix for ToolInstance type' {
        $result = Get-DeterministicPseudonym -OriginalValue 'MyToolInstance' -NodeType 'ToolInstance' -Context $ctx
        
        $result | Should -Match '^TI-\d{4}'
    }
    
    It 'Uses correct prefix for Operation type' {
        $result = Get-DeterministicPseudonym -OriginalValue 'MyOp' -NodeType 'Operation' -Context $ctx
        
        $result | Should -Match '^OP-\d{4}'
    }
    
    It 'Uses correct prefix for Location type' {
        $result = Get-DeterministicPseudonym -OriginalValue 'MyLoc' -NodeType 'Location' -Context $ctx
        
        $result | Should -Match '^LOC-\d{4}'
    }
    
    It 'Uses default prefix for unknown type' {
        $result = Get-DeterministicPseudonym -OriginalValue 'Unknown' -NodeType 'SomeNewType' -Context $ctx
        
        $result | Should -Match '^NODE-\d{4}'
    }
    
    It 'Caches pseudonyms in context' {
        $result = Get-DeterministicPseudonym -OriginalValue 'CachedItem' -NodeType 'Station' -Context $ctx
        
        $ctx.nameMap['Station:CachedItem'] | Should -Be $result
    }
    
    It 'Generates different pseudonyms for different inputs' {
        $result1 = Get-DeterministicPseudonym -OriginalValue 'Station_A' -NodeType 'Station' -Context $ctx
        $result2 = Get-DeterministicPseudonym -OriginalValue 'Station_B' -NodeType 'Station' -Context $ctx
        
        $result1 | Should -Not -Be $result2
    }
    
    It 'Generates different pseudonyms for different seeds' {
        $ctx1 = New-AnonymizationContext -Seed 'seed-one'
        $ctx2 = New-AnonymizationContext -Seed 'seed-two'
        
        $result1 = Get-DeterministicPseudonym -OriginalValue 'SameName' -NodeType 'Station' -Context $ctx1
        $result2 = Get-DeterministicPseudonym -OriginalValue 'SameName' -NodeType 'Station' -Context $ctx2
        
        $result1 | Should -Not -Be $result2
    }
}

Describe 'ConvertTo-AnonymizedPath' {
    BeforeEach {
        $ctx = New-AnonymizationContext -Seed 'path-test'
    }
    
    It 'Anonymizes path segments' {
        $result = ConvertTo-AnonymizedPath -Path '/Root/Station/Tool' -Context $ctx
        
        $result | Should -Match '^/NODE-\d{4}/NODE-\d{4}/NODE-\d{4}$'
    }
    
    It 'Preserves leading slash' {
        $result = ConvertTo-AnonymizedPath -Path '/Root' -Context $ctx
        
        $result | Should -Match '^/'
    }
    
    It 'Handles empty path' {
        $result = ConvertTo-AnonymizedPath -Path '' -Context $ctx
        
        $result | Should -Be ''
    }
    
    It 'Caches anonymized paths' {
        $path = '/MyPath/SubPath'
        $result = ConvertTo-AnonymizedPath -Path $path -Context $ctx
        
        $ctx.pathMap[$path] | Should -Be $result
    }
    
    It 'Returns same result for same path' {
        $path = '/Consistent/Path'
        $result1 = ConvertTo-AnonymizedPath -Path $path -Context $ctx
        $result2 = ConvertTo-AnonymizedPath -Path $path -Context $ctx
        
        $result1 | Should -Be $result2
    }
}

Describe 'ConvertTo-AnonymizedNode' {
    BeforeEach {
        $ctx = New-AnonymizationContext -Seed 'node-test'
        $testNode = [PSCustomObject]@{
            nodeId     = 'N000001'
            name       = 'TestStation'
            nodeType   = 'Station'
            parentId   = 'N000000'
            path       = '/Root/TestStation'
            attributes = [PSCustomObject]@{
                externalId = 'EXT-12345'
                className  = 'StationClass'
                niceName   = 'TestStation'
                typeId     = 42
            }
            source     = [PSCustomObject]@{
                table       = 'DF_STATION_DATA'
                extractedAt = '2026-01-15T00:00:00Z'
            }
        }
    }
    
    It 'Anonymizes node name' {
        $result = ConvertTo-AnonymizedNode -Node $testNode -Context $ctx
        
        $result.name | Should -Match '^ST-\d{4}'
        $result.name | Should -Not -Be 'TestStation'
    }
    
    It 'Anonymizes node path' {
        $result = ConvertTo-AnonymizedNode -Node $testNode -Context $ctx
        
        $result.path | Should -Not -Be '/Root/TestStation'
        $result.path | Should -Match '^/'
    }
    
    It 'Preserves nodeId' {
        $result = ConvertTo-AnonymizedNode -Node $testNode -Context $ctx
        
        $result.nodeId | Should -Be 'N000001'
    }
    
    It 'Preserves nodeType' {
        $result = ConvertTo-AnonymizedNode -Node $testNode -Context $ctx
        
        $result.nodeType | Should -Be 'Station'
    }
    
    It 'Anonymizes externalId in attributes' {
        $result = ConvertTo-AnonymizedNode -Node $testNode -Context $ctx
        
        $result.attributes.externalId | Should -Match '^ANON-'
    }
    
    It 'Updates niceName to match anonymized name' {
        $result = ConvertTo-AnonymizedNode -Node $testNode -Context $ctx
        
        $result.attributes.niceName | Should -Be $result.name
    }
    
    It 'Anonymizes source table name' {
        $result = ConvertTo-AnonymizedNode -Node $testNode -Context $ctx
        
        $result.source.table | Should -Be 'ANON_DATA_TABLE'
    }
    
    It 'Tracks nodeId in context idMap' {
        $result = ConvertTo-AnonymizedNode -Node $testNode -Context $ctx
        
        $ctx.idMap['N000001'] | Should -Be 'N000001'
    }
}

Describe 'ConvertTo-AnonymizedNodes' {
    BeforeEach {
        $ctx = New-AnonymizationContext -Seed 'nodes-test'
        $testNodes = @(
            [PSCustomObject]@{
                nodeId     = 'N000001'
                name       = 'Station_A'
                nodeType   = 'Station'
                parentId   = $null
                path       = '/Station_A'
                attributes = [PSCustomObject]@{ externalId = 'EXT-A' }
                source     = [PSCustomObject]@{ table = 'DATA' }
            },
            [PSCustomObject]@{
                nodeId     = 'N000002'
                name       = 'Tool_B'
                nodeType   = 'ToolInstance'
                parentId   = 'N000001'
                path       = '/Station_A/Tool_B'
                attributes = [PSCustomObject]@{ externalId = 'EXT-B' }
                source     = [PSCustomObject]@{ table = 'DATA' }
            }
        )
    }
    
    It 'Anonymizes all nodes' {
        $result = ConvertTo-AnonymizedNodes -Nodes $testNodes -Context $ctx
        
        $result.Count | Should -Be 2
        $result[0].name | Should -Match '^ST-\d{4}'
        $result[1].name | Should -Match '^TI-\d{4}'
    }
    
    It 'Preserves node count' {
        $result = ConvertTo-AnonymizedNodes -Nodes $testNodes -Context $ctx
        
        $result.Count | Should -Be $testNodes.Count
    }
    
    It 'Handles empty array' {
        $result = ConvertTo-AnonymizedNodes -Nodes @() -Context $ctx
        
        $result.Count | Should -Be 0
    }
}

Describe 'ConvertTo-AnonymizedDiff' {
    BeforeEach {
        $ctx = New-AnonymizationContext -Seed 'diff-test'
        $testDiff = [PSCustomObject]@{
            summary = [PSCustomObject]@{
                totalChanges = 3
                added        = 1
                removed      = 1
                renamed      = 1
            }
            changes = @(
                [PSCustomObject]@{
                    changeType = 'added'
                    nodeName   = 'NewStation'
                    nodeType   = 'Station'
                    path       = '/Root/NewStation'
                },
                [PSCustomObject]@{
                    changeType = 'renamed'
                    nodeName   = 'RenamedTool'
                    nodeType   = 'ToolInstance'
                    oldName    = 'OldName'
                    newName    = 'NewName'
                    oldPath    = '/Root/OldName'
                    newPath    = '/Root/NewName'
                }
            )
        }
    }
    
    It 'Anonymizes nodeName in changes' {
        $result = ConvertTo-AnonymizedDiff -Diff $testDiff -Context $ctx
        
        $result.changes[0].nodeName | Should -Not -Be 'NewStation'
        $result.changes[0].nodeName | Should -Match '^ST-\d{4}'
    }
    
    It 'Anonymizes oldName and newName' {
        $result = ConvertTo-AnonymizedDiff -Diff $testDiff -Context $ctx
        
        $result.changes[1].oldName | Should -Not -Be 'OldName'
        $result.changes[1].newName | Should -Not -Be 'NewName'
    }
    
    It 'Anonymizes paths in changes' {
        $result = ConvertTo-AnonymizedDiff -Diff $testDiff -Context $ctx
        
        $result.changes[0].path | Should -Not -Be '/Root/NewStation'
        $result.changes[1].oldPath | Should -Not -Be '/Root/OldName'
        $result.changes[1].newPath | Should -Not -Be '/Root/NewName'
    }
    
    It 'Preserves change types' {
        $result = ConvertTo-AnonymizedDiff -Diff $testDiff -Context $ctx
        
        $result.changes[0].changeType | Should -Be 'added'
        $result.changes[1].changeType | Should -Be 'renamed'
    }
    
    It 'Preserves summary counts' {
        $result = ConvertTo-AnonymizedDiff -Diff $testDiff -Context $ctx
        
        $result.summary.totalChanges | Should -Be 3
        $result.summary.added | Should -Be 1
    }
}

Describe 'Export-AnonymizationMapping' {
    BeforeEach {
        $ctx = New-AnonymizationContext -Seed 'export-test'
        # Generate some pseudonyms
        Get-DeterministicPseudonym -OriginalValue 'Test1' -NodeType 'Station' -Context $ctx | Out-Null
        Get-DeterministicPseudonym -OriginalValue 'Test2' -NodeType 'ToolInstance' -Context $ctx | Out-Null
        
        $testDir = Join-Path $TestDrive 'anon-test'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $outputPath = Join-Path $testDir 'mapping.json'
    }
    
    It 'Creates mapping file' {
        Export-AnonymizationMapping -Context $ctx -OutputPath $outputPath
        
        Test-Path $outputPath | Should -Be $true
    }
    
    It 'Includes seed in mapping' {
        Export-AnonymizationMapping -Context $ctx -OutputPath $outputPath
        $mapping = Get-Content $outputPath -Raw | ConvertFrom-Json
        
        $mapping.seed | Should -Be 'export-test'
    }
    
    It 'Includes warning message' {
        Export-AnonymizationMapping -Context $ctx -OutputPath $outputPath
        $mapping = Get-Content $outputPath -Raw | ConvertFrom-Json
        
        $mapping.warning | Should -Match 'CONFIDENTIAL'
    }
    
    It 'Includes name mappings' {
        Export-AnonymizationMapping -Context $ctx -OutputPath $outputPath
        $mapping = Get-Content $outputPath -Raw | ConvertFrom-Json
        
        $mapping.nameMap | Should -Not -BeNullOrEmpty
    }
}

Describe 'Import-AnonymizationMapping' {
    BeforeEach {
        $ctx = New-AnonymizationContext -Seed 'import-test'
        Get-DeterministicPseudonym -OriginalValue 'ImportTest' -NodeType 'Station' -Context $ctx | Out-Null
        
        $testDir = Join-Path $TestDrive 'import-test'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $mappingPath = Join-Path $testDir 'mapping.json'
        Export-AnonymizationMapping -Context $ctx -OutputPath $mappingPath
    }
    
    It 'Restores seed from mapping' {
        $imported = Import-AnonymizationMapping -Path $mappingPath
        
        $imported.seed | Should -Be 'import-test'
    }
    
    It 'Restores name mappings' {
        $imported = Import-AnonymizationMapping -Path $mappingPath
        
        $imported.nameMap['Station:ImportTest'] | Should -Not -BeNullOrEmpty
    }
    
    It 'Throws for missing file' {
        { Import-AnonymizationMapping -Path 'nonexistent.json' } | Should -Throw
    }
}

Describe 'Get-AnonymizationSummary' {
    It 'Returns summary statistics' {
        $ctx = New-AnonymizationContext -Seed 'summary-test'
        Get-DeterministicPseudonym -OriginalValue 'Name1' -NodeType 'Station' -Context $ctx | Out-Null
        Get-DeterministicPseudonym -OriginalValue 'Name2' -NodeType 'Station' -Context $ctx | Out-Null
        Get-DeterministicPseudonym -OriginalValue 'Name3' -NodeType 'ToolInstance' -Context $ctx | Out-Null
        
        $summary = Get-AnonymizationSummary -Context $ctx
        
        $summary.seed | Should -Be 'summary-test'
        $summary.totalNamesAnonymized | Should -Be 3
        $summary.typeBreakdown['Station'] | Should -Be 2
        $summary.typeBreakdown['ToolInstance'] | Should -Be 1
    }
}

Describe 'Determinism Tests' {
    It 'Produces identical results for same seed and input' {
        $ctx1 = New-AnonymizationContext -Seed 'determinism'
        $ctx2 = New-AnonymizationContext -Seed 'determinism'
        
        $testNodes = @(
            [PSCustomObject]@{
                nodeId     = 'N001'
                name       = 'Station_X'
                nodeType   = 'Station'
                parentId   = $null
                path       = '/Station_X'
                attributes = [PSCustomObject]@{ externalId = 'EXT-1' }
                source     = [PSCustomObject]@{ table = 'DATA' }
            }
        )
        
        $result1 = ConvertTo-AnonymizedNodes -Nodes $testNodes -Context $ctx1
        $result2 = ConvertTo-AnonymizedNodes -Nodes $testNodes -Context $ctx2
        
        $result1[0].name | Should -Be $result2[0].name
        $result1[0].path | Should -Be $result2[0].path
    }
    
    It 'Produces different results for different seeds' {
        $ctx1 = New-AnonymizationContext -Seed 'seed-alpha'
        $ctx2 = New-AnonymizationContext -Seed 'seed-beta'
        
        $result1 = Get-DeterministicPseudonym -OriginalValue 'SameName' -NodeType 'Station' -Context $ctx1
        $result2 = Get-DeterministicPseudonym -OriginalValue 'SameName' -NodeType 'Station' -Context $ctx2
        
        $result1 | Should -Not -Be $result2
    }
}
