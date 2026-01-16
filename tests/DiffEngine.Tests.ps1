# DiffEngine.Tests.ps1
# Pester tests for SimTreeNav diff detection

BeforeAll {
    # Import the modules under test
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . "$scriptRoot\src\powershell\v02\core\NodeContract.ps1"
    
    # Helper to create test nodes
    function New-TestNode {
        param(
            [string]$NodeId,
            [string]$Name,
            [string]$ParentId = $null,
            [string]$NodeType = 'ResourceGroup',
            [string]$ClassName = 'class PmCollection',
            [hashtable]$Attributes = @{}
        )
        
        New-SimTreeNode `
            -NodeId $NodeId `
            -NodeType $NodeType `
            -Name $Name `
            -ParentId $ParentId `
            -ClassName $ClassName `
            -Attributes $Attributes
    }
}

Describe 'NodeContract' {
    Context 'New-SimTreeNode' {
        It 'Creates a valid node with required fields' {
            $node = New-SimTreeNode -NodeId '12345' -NodeType 'ResourceGroup' -Name 'TestStation'
            
            $node.nodeId | Should -Be '12345'
            $node.nodeType | Should -Be 'ResourceGroup'
            $node.name | Should -Be 'TestStation'
            $node.path | Should -Be '/TestStation'
        }
        
        It 'Computes content hash consistently' {
            $node1 = New-SimTreeNode -NodeId '12345' -NodeType 'ResourceGroup' -Name 'Station1' -ClassName 'class PmStation'
            $node2 = New-SimTreeNode -NodeId '12346' -NodeType 'ResourceGroup' -Name 'Station1' -ClassName 'class PmStation'
            
            $node1.fingerprints.contentHash | Should -Be $node2.fingerprints.contentHash
        }
        
        It 'Generates different hash for different names' {
            $node1 = New-SimTreeNode -NodeId '12345' -NodeType 'ResourceGroup' -Name 'Station1'
            $node2 = New-SimTreeNode -NodeId '12346' -NodeType 'ResourceGroup' -Name 'Station2'
            
            $node1.fingerprints.contentHash | Should -Not -Be $node2.fingerprints.contentHash
        }
    }
    
    Context 'Get-ContentHash' {
        It 'Returns consistent hash for same input' {
            $hash1 = Get-ContentHash -Name 'TestNode' -ExternalId 'EXT-123' -ClassName 'class PmStation'
            $hash2 = Get-ContentHash -Name 'TestNode' -ExternalId 'EXT-123' -ClassName 'class PmStation'
            
            $hash1 | Should -Be $hash2
        }
        
        It 'Returns 16-character lowercase hex string' {
            $hash = Get-ContentHash -Name 'Test' -ExternalId '' -ClassName ''
            
            $hash.Length | Should -Be 16
            $hash | Should -Match '^[0-9a-f]+$'
        }
    }
    
    Context 'Get-AttributeHash' {
        It 'Returns null for empty attributes' {
            $hash = Get-AttributeHash -Attributes @{}
            
            $hash | Should -BeNullOrEmpty
        }
        
        It 'Returns consistent hash regardless of key order' {
            $hash1 = Get-AttributeHash -Attributes @{ b = 'two'; a = 'one' }
            $hash2 = Get-AttributeHash -Attributes @{ a = 'one'; b = 'two' }
            
            $hash1 | Should -Be $hash2
        }
        
        It 'Returns different hash for different values' {
            $hash1 = Get-AttributeHash -Attributes @{ key = 'value1' }
            $hash2 = Get-AttributeHash -Attributes @{ key = 'value2' }
            
            $hash1 | Should -Not -Be $hash2
        }
    }
    
    Context 'Get-TransformHash' {
        It 'Returns null for empty transform' {
            $hash = Get-TransformHash -Transform @()
            
            $hash | Should -BeNullOrEmpty
        }
        
        It 'Returns consistent hash for same transform' {
            $transform = @(1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 100.0, 200.0, 300.0)
            
            $hash1 = Get-TransformHash -Transform $transform
            $hash2 = Get-TransformHash -Transform $transform
            
            $hash1 | Should -Be $hash2
        }
        
        It 'Handles floating point precision' {
            $transform1 = @(1.0000001, 0.0, 0.0)
            $transform2 = @(1.0000002, 0.0, 0.0)
            
            # Should be same after rounding to 6 decimals
            $hash1 = Get-TransformHash -Transform $transform1
            $hash2 = Get-TransformHash -Transform $transform2
            
            $hash1 | Should -Be $hash2
        }
    }
    
    Context 'ConvertFrom-PipeDelimited' {
        It 'Parses valid pipe-delimited line' {
            $line = '1|12345|12346|TestStation|TestStation|EXT-001|0|class PmStation|Station|64'
            
            $node = ConvertFrom-PipeDelimited -Line $line -Schema 'DESIGN12'
            
            $node.nodeId | Should -Be '12346'
            $node.name | Should -Be 'TestStation'
            $node.parentId | Should -Be '12345'
            $node.attributes.typeId | Should -Be 64
            $node.source.schema | Should -Be 'DESIGN12'
        }
        
        It 'Returns null for invalid line' {
            $node = ConvertFrom-PipeDelimited -Line 'invalid line without pipes'
            
            $node | Should -BeNullOrEmpty
        }
        
        It 'Handles root node (parentId = 0)' {
            $line = '0|0|12345|RootProject|RootProject|EXT-ROOT|0|class PmProject|Project|1'
            
            $node = ConvertFrom-PipeDelimited -Line $line
            
            $node.parentId | Should -BeNullOrEmpty
        }
    }
    
    Context 'Get-NodeTypeFromClass' {
        It 'Maps PmStation to ResourceGroup' {
            $type = Get-NodeTypeFromClass -ClassName 'class PmStation'
            
            $type | Should -Be 'ResourceGroup'
        }
        
        It 'Maps ToolPrototype to ToolPrototype' {
            $type = Get-NodeTypeFromClass -ClassName 'class ToolPrototype'
            
            $type | Should -Be 'ToolPrototype'
        }
        
        It 'Maps RobcadStudy to OperationGroup' {
            $type = Get-NodeTypeFromClass -ClassName 'class RobcadStudy'
            
            $type | Should -Be 'OperationGroup'
        }
        
        It 'Returns Unknown for unrecognized class' {
            $type = Get-NodeTypeFromClass -ClassName 'class SomeUnknownClass'
            
            $type | Should -Be 'Unknown'
        }
    }
    
    Context 'Compute-NodePaths' {
        It 'Computes correct path for single node' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Root'; parentId = $null; path = '' }
            )
            
            $result = Compute-NodePaths -Nodes $nodes
            
            $result[0].path | Should -Be '/Root'
        }
        
        It 'Computes correct path for nested nodes' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Root'; parentId = $null; path = '' }
                [PSCustomObject]@{ nodeId = '2'; name = 'Child'; parentId = '1'; path = '' }
                [PSCustomObject]@{ nodeId = '3'; name = 'GrandChild'; parentId = '2'; path = '' }
            )
            
            $result = Compute-NodePaths -Nodes $nodes
            
            ($result | Where-Object { $_.nodeId -eq '3' }).path | Should -Be '/Root/Child/GrandChild'
        }
        
        It 'Handles circular references gracefully' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'A'; parentId = '2'; path = '' }
                [PSCustomObject]@{ nodeId = '2'; name = 'B'; parentId = '1'; path = '' }
            )
            
            # Should not throw or infinite loop
            { Compute-NodePaths -Nodes $nodes } | Should -Not -Throw
        }
    }
}

Describe 'Diff Detection' {
    BeforeAll {
        # Mock Compare-Nodes function inline for testing
        function Test-CompareNodes {
            param([array]$BaselineNodes, [array]$CurrentNodes)
            
            $changes = @()
            
            $baselineMap = @{}
            foreach ($node in $BaselineNodes) { $baselineMap[$node.nodeId] = $node }
            
            $currentMap = @{}
            foreach ($node in $CurrentNodes) { $currentMap[$node.nodeId] = $node }
            
            # Added
            foreach ($nodeId in $currentMap.Keys) {
                if (-not $baselineMap.ContainsKey($nodeId)) {
                    $changes += [PSCustomObject]@{
                        changeType = 'added'
                        nodeId = $nodeId
                        nodeName = $currentMap[$nodeId].name
                    }
                }
            }
            
            # Removed
            foreach ($nodeId in $baselineMap.Keys) {
                if (-not $currentMap.ContainsKey($nodeId)) {
                    $changes += [PSCustomObject]@{
                        changeType = 'removed'
                        nodeId = $nodeId
                        nodeName = $baselineMap[$nodeId].name
                    }
                }
            }
            
            # Modified
            foreach ($nodeId in $currentMap.Keys) {
                if (-not $baselineMap.ContainsKey($nodeId)) { continue }
                
                $baseline = $baselineMap[$nodeId]
                $current = $currentMap[$nodeId]
                
                if ($baseline.name -ne $current.name) {
                    $changes += [PSCustomObject]@{
                        changeType = 'renamed'
                        nodeId = $nodeId
                        oldName = $baseline.name
                        newName = $current.name
                    }
                }
                
                if ($baseline.parentId -ne $current.parentId) {
                    $changes += [PSCustomObject]@{
                        changeType = 'moved'
                        nodeId = $nodeId
                        oldParentId = $baseline.parentId
                        newParentId = $current.parentId
                    }
                }
            }
            
            return $changes
        }
    }
    
    Context 'Detect Added Nodes' {
        It 'Detects single added node' {
            $baseline = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Node1'; parentId = $null }
            )
            $current = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Node1'; parentId = $null }
                [PSCustomObject]@{ nodeId = '2'; name = 'NewNode'; parentId = '1' }
            )
            
            $changes = Test-CompareNodes -BaselineNodes $baseline -CurrentNodes $current
            
            $added = $changes | Where-Object { $_.changeType -eq 'added' }
            $added.Count | Should -Be 1
            $added[0].nodeId | Should -Be '2'
        }
        
        It 'Detects multiple added nodes' {
            $baseline = @()
            $current = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Node1'; parentId = $null }
                [PSCustomObject]@{ nodeId = '2'; name = 'Node2'; parentId = '1' }
            )
            
            $changes = Test-CompareNodes -BaselineNodes $baseline -CurrentNodes $current
            
            $added = $changes | Where-Object { $_.changeType -eq 'added' }
            $added.Count | Should -Be 2
        }
    }
    
    Context 'Detect Removed Nodes' {
        It 'Detects single removed node' {
            $baseline = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Node1'; parentId = $null }
                [PSCustomObject]@{ nodeId = '2'; name = 'ToBeRemoved'; parentId = '1' }
            )
            $current = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Node1'; parentId = $null }
            )
            
            $changes = Test-CompareNodes -BaselineNodes $baseline -CurrentNodes $current
            
            $removed = $changes | Where-Object { $_.changeType -eq 'removed' }
            $removed.Count | Should -Be 1
            $removed[0].nodeId | Should -Be '2'
        }
    }
    
    Context 'Detect Renamed Nodes' {
        It 'Detects node rename' {
            $baseline = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'OldName'; parentId = $null }
            )
            $current = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'NewName'; parentId = $null }
            )
            
            $changes = Test-CompareNodes -BaselineNodes $baseline -CurrentNodes $current
            
            $renamed = $changes | Where-Object { $_.changeType -eq 'renamed' }
            $renamed.Count | Should -Be 1
            $renamed[0].oldName | Should -Be 'OldName'
            $renamed[0].newName | Should -Be 'NewName'
        }
    }
    
    Context 'Detect Moved Nodes' {
        It 'Detects node move to different parent' {
            $baseline = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Root'; parentId = $null }
                [PSCustomObject]@{ nodeId = '2'; name = 'Parent1'; parentId = '1' }
                [PSCustomObject]@{ nodeId = '3'; name = 'Parent2'; parentId = '1' }
                [PSCustomObject]@{ nodeId = '4'; name = 'Child'; parentId = '2' }
            )
            $current = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Root'; parentId = $null }
                [PSCustomObject]@{ nodeId = '2'; name = 'Parent1'; parentId = '1' }
                [PSCustomObject]@{ nodeId = '3'; name = 'Parent2'; parentId = '1' }
                [PSCustomObject]@{ nodeId = '4'; name = 'Child'; parentId = '3' }  # Moved!
            )
            
            $changes = Test-CompareNodes -BaselineNodes $baseline -CurrentNodes $current
            
            $moved = $changes | Where-Object { $_.changeType -eq 'moved' }
            $moved.Count | Should -Be 1
            $moved[0].nodeId | Should -Be '4'
            $moved[0].oldParentId | Should -Be '2'
            $moved[0].newParentId | Should -Be '3'
        }
    }
    
    Context 'No Changes' {
        It 'Returns empty array when no changes' {
            $nodes = @(
                [PSCustomObject]@{ nodeId = '1'; name = 'Node1'; parentId = $null }
                [PSCustomObject]@{ nodeId = '2'; name = 'Node2'; parentId = '1' }
            )
            
            $changes = Test-CompareNodes -BaselineNodes $nodes -CurrentNodes $nodes
            
            $changes.Count | Should -Be 0
        }
    }
}

Describe 'Fingerprint Stability' {
    Context 'Hash Determinism' {
        It 'Same input always produces same hash' {
            $results = @()
            for ($i = 0; $i -lt 10; $i++) {
                $results += Get-ContentHash -Name 'TestNode' -ExternalId 'EXT-123' -ClassName 'class PmStation'
            }
            
            $unique = $results | Select-Object -Unique
            $unique.Count | Should -Be 1
        }
        
        It 'Hash length is always 16 characters' {
            $testCases = @(
                @{ Name = 'Short'; ExternalId = ''; ClassName = '' }
                @{ Name = 'A very long name with spaces and special characters!@#$%'; ExternalId = 'LONG-EXTERNAL-ID-12345'; ClassName = 'class VeryLongClassName' }
                @{ Name = ''; ExternalId = ''; ClassName = '' }
            )
            
            foreach ($tc in $testCases) {
                $hash = Get-ContentHash @tc
                $hash.Length | Should -Be 16
            }
        }
    }
}
