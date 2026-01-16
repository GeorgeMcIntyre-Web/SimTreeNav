# IdentityResolver.Tests.ps1
# Pester tests for SimTreeNav v0.3 identity resolution

BeforeAll {
    # Import the modules under test
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . "$scriptRoot\src\powershell\v02\core\NodeContract.ps1"
    . "$scriptRoot\src\powershell\v02\core\IdentityResolver.ps1"
    
    # Helper to create test nodes with full structure
    function New-TestNodeFull {
        param(
            [string]$NodeId,
            [string]$Name,
            [string]$ParentId = $null,
            [string]$Path = $null,
            [string]$NodeType = 'ResourceGroup',
            [string]$ClassName = 'class PmCollection',
            [string]$ExternalId = '',
            [string]$ContentHash = $null,
            [string]$TransformHash = $null,
            [string]$PrototypeId = $null
        )
        
        $computedPath = if ($Path) { $Path } else { "/$Name" }
        $computedContentHash = if ($ContentHash) { $ContentHash } else { 
            $bytes = [System.Text.Encoding]::UTF8.GetBytes("$Name|$ExternalId|$ClassName")
            $sha = [System.Security.Cryptography.SHA256]::Create()
            [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').Substring(0, 16).ToLower()
        }
        
        $links = @{}
        if ($PrototypeId) { $links['prototypeId'] = $PrototypeId }
        
        [PSCustomObject]@{
            nodeId      = $NodeId
            nodeType    = $NodeType
            name        = $Name
            parentId    = $ParentId
            path        = $computedPath
            attributes  = [PSCustomObject]@{
                externalId  = $ExternalId
                className   = $ClassName
                niceName    = ''
                typeId      = 0
                seqNumber   = 0
            }
            links       = [PSCustomObject]$links
            fingerprints = [PSCustomObject]@{
                contentHash   = $computedContentHash
                attributeHash = $null
                transformHash = $TransformHash
            }
            timestamps  = [PSCustomObject]@{
                createdAt     = $null
                updatedAt     = $null
                lastTouchedAt = $null
            }
            source      = [PSCustomObject]@{
                table     = 'COLLECTION_'
                query     = 'test'
                schema    = 'TEST'
            }
        }
    }
}

Describe 'IdentityResolver' {
    Context 'Get-LogicalId' {
        It 'Uses externalId when present and valid (PP-uuid format)' {
            $node = New-TestNodeFull -NodeId '12345' -Name 'TestNode' -ExternalId 'PP-12345678-abcd-1234-5678-abcdef123456'
            
            $logicalId = Get-LogicalId -Node $node
            
            $logicalId | Should -BeLike 'ext:PP-*'
            $logicalId | Should -Be 'ext:PP-12345678-abcd-1234-5678-abcdef123456'
        }
        
        It 'Falls back to structural hash when externalId is missing' {
            $node = New-TestNodeFull -NodeId '12345' -Name 'TestNode' -ExternalId ''
            
            $logicalId = Get-LogicalId -Node $node
            
            $logicalId | Should -BeLike 'struct:*'
        }
        
        It 'Falls back to structural hash when externalId is invalid format' {
            $node = New-TestNodeFull -NodeId '12345' -Name 'TestNode' -ExternalId 'INVALID-FORMAT'
            
            $logicalId = Get-LogicalId -Node $node
            
            $logicalId | Should -BeLike 'struct:*'
        }
        
        It 'Generates consistent logicalId for same node structure' {
            $node1 = New-TestNodeFull -NodeId '12345' -Name 'Station1' -Path '/Project/Station1' -NodeType 'ResourceGroup'
            $node2 = New-TestNodeFull -NodeId '99999' -Name 'Station1' -Path '/Project/Station1' -NodeType 'ResourceGroup'
            
            $logicalId1 = Get-LogicalId -Node $node1
            $logicalId2 = Get-LogicalId -Node $node2
            
            $logicalId1 | Should -Be $logicalId2
        }
        
        It 'Generates different logicalId for different paths' {
            $node1 = New-TestNodeFull -NodeId '12345' -Name 'Station1' -Path '/Project1/Station1'
            $node2 = New-TestNodeFull -NodeId '12345' -Name 'Station1' -Path '/Project2/Station1'
            
            $logicalId1 = Get-LogicalId -Node $node1
            $logicalId2 = Get-LogicalId -Node $node2
            
            $logicalId1 | Should -Not -Be $logicalId2
        }
    }
    
    Context 'Get-IdentitySignature' {
        It 'Extracts all identity signals from node' {
            $node = New-TestNodeFull -NodeId '12345' -Name 'Robot1' -Path '/Project/Station/Robot1' `
                -ExternalId 'PP-12345678-abcd-1234-5678-abcdef123456' `
                -ClassName 'class Robot' -NodeType 'ToolInstance' `
                -TransformHash 'abc123' -PrototypeId '99999'
            
            $signature = Get-IdentitySignature -Node $node
            
            $signature.nodeId | Should -Be '12345'
            $signature.name | Should -Be 'Robot1'
            $signature.nodeType | Should -Be 'ToolInstance'
            $signature.path | Should -Be '/Project/Station/Robot1'
            $signature.parentPath | Should -Be '/Project/Station'
            $signature.externalId | Should -Be 'PP-12345678-abcd-1234-5678-abcdef123456'
            $signature.className | Should -Be 'class Robot'
            $signature.transformHash | Should -Be 'abc123'
            $signature.prototypeId | Should -Be '99999'
        }
        
        It 'Computes parent path correctly' {
            $node = New-TestNodeFull -NodeId '1' -Name 'Leaf' -Path '/Root/Middle/Leaf'
            
            $signature = Get-IdentitySignature -Node $node
            
            $signature.parentPath | Should -Be '/Root/Middle'
        }
        
        It 'Handles root node (no parent path)' {
            $node = New-TestNodeFull -NodeId '1' -Name 'Root' -Path '/Root'
            
            $signature = Get-IdentitySignature -Node $node
            
            $signature.parentPath | Should -BeNullOrEmpty
        }
    }
    
    Context 'Compare-IdentitySignatures' {
        It 'Returns confidence 1.0 for exact nodeId match' {
            $sig1 = [PSCustomObject]@{ nodeId = '12345'; name = 'A'; nodeType = 'ResourceGroup'; path = '/A'; parentPath = $null; externalId = ''; className = ''; contentHash = 'abc'; transformHash = $null; prototypeId = $null }
            $sig2 = [PSCustomObject]@{ nodeId = '12345'; name = 'B'; nodeType = 'ToolInstance'; path = '/B'; parentPath = $null; externalId = ''; className = ''; contentHash = 'xyz'; transformHash = $null; prototypeId = $null }
            
            $result = Compare-IdentitySignatures -Signature1 $sig1 -Signature2 $sig2
            
            $result.confidence | Should -Be 1.0
            $result.reason | Should -Be 'exact_nodeId'
        }
        
        It 'Returns high confidence for externalId match' {
            $sig1 = [PSCustomObject]@{ nodeId = '111'; name = 'Node'; nodeType = 'ResourceGroup'; path = '/A'; parentPath = $null; externalId = 'PP-same-uuid'; className = ''; contentHash = ''; transformHash = $null; prototypeId = $null }
            $sig2 = [PSCustomObject]@{ nodeId = '222'; name = 'Node'; nodeType = 'ResourceGroup'; path = '/A'; parentPath = $null; externalId = 'PP-same-uuid'; className = ''; contentHash = ''; transformHash = $null; prototypeId = $null }
            
            $result = Compare-IdentitySignatures -Signature1 $sig1 -Signature2 $sig2
            
            $result.confidence | Should -BeGreaterThan 0.5
            $result.details | Should -Contain 'externalId'
        }
        
        It 'Returns medium confidence for name + parentPath match' {
            $sig1 = [PSCustomObject]@{ nodeId = '111'; name = 'Robot1'; nodeType = 'ToolInstance'; path = '/Project/Station/Robot1'; parentPath = '/Project/Station'; externalId = ''; className = ''; contentHash = ''; transformHash = $null; prototypeId = $null }
            $sig2 = [PSCustomObject]@{ nodeId = '222'; name = 'Robot1'; nodeType = 'ToolInstance'; path = '/Project/Station/Robot1'; parentPath = '/Project/Station'; externalId = ''; className = ''; contentHash = ''; transformHash = $null; prototypeId = $null }
            
            $result = Compare-IdentitySignatures -Signature1 $sig1 -Signature2 $sig2
            
            $result.confidence | Should -BeGreaterThan 0.3
            $result.details | Should -Contain 'name+parentPath'
        }
        
        It 'Returns low confidence for name-only match' {
            $sig1 = [PSCustomObject]@{ nodeId = '111'; name = 'CommonName'; nodeType = 'ResourceGroup'; path = '/A/CommonName'; parentPath = '/A'; externalId = ''; className = ''; contentHash = ''; transformHash = $null; prototypeId = $null }
            $sig2 = [PSCustomObject]@{ nodeId = '222'; name = 'CommonName'; nodeType = 'ToolInstance'; path = '/B/CommonName'; parentPath = '/B'; externalId = ''; className = ''; contentHash = ''; transformHash = $null; prototypeId = $null }
            
            $result = Compare-IdentitySignatures -Signature1 $sig1 -Signature2 $sig2
            
            $result.confidence | Should -BeLessThan 0.5
            $result.details | Should -Contain 'nameOnly'
        }
        
        It 'Adds bonus for nodeType match' {
            $sig1 = [PSCustomObject]@{ nodeId = '111'; name = 'Node'; nodeType = 'ToolInstance'; path = '/A'; parentPath = $null; externalId = ''; className = ''; contentHash = ''; transformHash = $null; prototypeId = $null }
            $sig2 = [PSCustomObject]@{ nodeId = '222'; name = 'Node'; nodeType = 'ToolInstance'; path = '/B'; parentPath = $null; externalId = ''; className = ''; contentHash = ''; transformHash = $null; prototypeId = $null }
            
            $result = Compare-IdentitySignatures -Signature1 $sig1 -Signature2 $sig2
            
            $result.details | Should -Contain 'nodeType'
        }
    }
    
    Context 'Resolve-NodeIdentities' {
        It 'Adds identity property to all nodes' {
            $nodes = @(
                New-TestNodeFull -NodeId '1' -Name 'Node1' -ExternalId 'PP-11111111-1111-1111-1111-111111111111'
                New-TestNodeFull -NodeId '2' -Name 'Node2' -ExternalId ''
            )
            
            $result = Resolve-NodeIdentities -Nodes $nodes
            
            $result | ForEach-Object {
                $_.identity | Should -Not -BeNullOrEmpty
                $_.identity.logicalId | Should -Not -BeNullOrEmpty
                $_.identity.signature | Should -Not -BeNullOrEmpty
            }
        }
        
        It 'Preserves original node properties' {
            $nodes = @(
                New-TestNodeFull -NodeId '123' -Name 'TestNode' -Path '/Test/TestNode'
            )
            
            $result = Resolve-NodeIdentities -Nodes $nodes
            
            $result[0].nodeId | Should -Be '123'
            $result[0].name | Should -Be 'TestNode'
            $result[0].path | Should -Be '/Test/TestNode'
        }
    }
    
    Context 'Find-MatchingNode' {
        It 'Finds exact nodeId match' {
            $source = New-TestNodeFull -NodeId '123' -Name 'Source'
            $targets = @(
                New-TestNodeFull -NodeId '456' -Name 'Other'
                New-TestNodeFull -NodeId '123' -Name 'Match'
            )
            
            $result = Find-MatchingNode -SourceNode $source -TargetNodes $targets
            
            $result.matched | Should -Be $true
            $result.matchedNode.nodeId | Should -Be '123'
            $result.matchConfidence | Should -Be 1.0
            $result.isRekeyed | Should -Be $false
        }
        
        It 'Finds rekeyed node by externalId' {
            $source = New-TestNodeFull -NodeId '111' -Name 'Node' -ExternalId 'PP-12345678-abcd-1234-5678-abcdef123456'
            $targets = @(
                New-TestNodeFull -NodeId '222' -Name 'Node' -ExternalId 'PP-12345678-abcd-1234-5678-abcdef123456'
            )
            
            $result = Find-MatchingNode -SourceNode $source -TargetNodes $targets -ConfidenceThreshold 0.5
            
            $result.matched | Should -Be $true
            $result.matchedNode.nodeId | Should -Be '222'
            $result.isRekeyed | Should -Be $true
        }
        
        It 'Returns no match when confidence below threshold' {
            $source = New-TestNodeFull -NodeId '111' -Name 'UniqueSource' -Path '/A/UniqueSource'
            $targets = @(
                New-TestNodeFull -NodeId '222' -Name 'DifferentName' -Path '/B/DifferentName'
            )
            
            $result = Find-MatchingNode -SourceNode $source -TargetNodes $targets -ConfidenceThreshold 0.9
            
            $result.matched | Should -Be $false
        }
        
        It 'Returns candidates when requested' {
            $source = New-TestNodeFull -NodeId '111' -Name 'Source'
            $targets = @(
                New-TestNodeFull -NodeId '222' -Name 'Source'
                New-TestNodeFull -NodeId '333' -Name 'Other'
            )
            
            $result = Find-MatchingNode -SourceNode $source -TargetNodes $targets -IncludeCandidates
            
            $result.candidates | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Build-IdentityMap' {
        It 'Correctly maps exact nodeId matches' {
            $baseline = @(
                New-TestNodeFull -NodeId '1' -Name 'Node1'
                New-TestNodeFull -NodeId '2' -Name 'Node2'
            )
            $current = @(
                New-TestNodeFull -NodeId '1' -Name 'Node1'
                New-TestNodeFull -NodeId '2' -Name 'Node2'
            )
            
            $result = Build-IdentityMap -BaselineNodes $baseline -CurrentNodes $current
            
            $result.mappings.Count | Should -Be 2
            $result.stats.exactMatches | Should -Be 2
            $result.stats.rekeyedMatches | Should -Be 0
            $result.addedNodes.Count | Should -Be 0
            $result.removedNodes.Count | Should -Be 0
        }
        
        It 'Detects rekeyed nodes' {
            $baseline = @(
                New-TestNodeFull -NodeId '111' -Name 'Station1' -Path '/Project/Station1' -ExternalId 'PP-11111111-1111-1111-1111-111111111111'
            )
            $current = @(
                New-TestNodeFull -NodeId '999' -Name 'Station1' -Path '/Project/Station1' -ExternalId 'PP-11111111-1111-1111-1111-111111111111'
            )
            
            $result = Build-IdentityMap -BaselineNodes $baseline -CurrentNodes $current
            
            $result.mappings.Count | Should -Be 1
            $result.mappings[0].matchType | Should -BeLike 'rekeyed*'
            $result.stats.rekeyedMatches | Should -Be 1
        }
        
        It 'Identifies added nodes' {
            $baseline = @(
                New-TestNodeFull -NodeId '1' -Name 'Existing'
            )
            $current = @(
                New-TestNodeFull -NodeId '1' -Name 'Existing'
                New-TestNodeFull -NodeId '2' -Name 'NewNode'
            )
            
            $result = Build-IdentityMap -BaselineNodes $baseline -CurrentNodes $current
            
            $result.addedNodes.Count | Should -Be 1
            $result.addedNodes[0].name | Should -Be 'NewNode'
        }
        
        It 'Identifies removed nodes' {
            $baseline = @(
                New-TestNodeFull -NodeId '1' -Name 'Existing'
                New-TestNodeFull -NodeId '2' -Name 'ToRemove'
            )
            $current = @(
                New-TestNodeFull -NodeId '1' -Name 'Existing'
            )
            
            $result = Build-IdentityMap -BaselineNodes $baseline -CurrentNodes $current
            
            $result.removedNodes.Count | Should -Be 1
            $result.removedNodes[0].name | Should -Be 'ToRemove'
        }
        
        It 'Provides accurate stats' {
            $baseline = @(
                New-TestNodeFull -NodeId '1' -Name 'Exact'
                New-TestNodeFull -NodeId '2' -Name 'Rekeyed' -ExternalId 'PP-22222222-2222-2222-2222-222222222222'
                New-TestNodeFull -NodeId '3' -Name 'Removed'
            )
            $current = @(
                New-TestNodeFull -NodeId '1' -Name 'Exact'
                New-TestNodeFull -NodeId '99' -Name 'Rekeyed' -ExternalId 'PP-22222222-2222-2222-2222-222222222222'
                New-TestNodeFull -NodeId '4' -Name 'Added'
            )
            
            $result = Build-IdentityMap -BaselineNodes $baseline -CurrentNodes $current
            
            $result.stats.totalBaseline | Should -Be 3
            $result.stats.totalCurrent | Should -Be 3
            $result.stats.exactMatches | Should -Be 1
            $result.stats.rekeyedMatches | Should -Be 1
            $result.stats.addedCount | Should -Be 1
            $result.stats.removedCount | Should -Be 1
        }
    }
}

Describe 'Diff Engine with Identity (v0.3)' {
    Context 'Rekeyed Change Detection' {
        BeforeAll {
            # Mock the Compare-NodesWithIdentity behavior for testing
            function Test-RekeyedDetection {
                param($Baseline, $Current)
                
                $identityMap = Build-IdentityMap -BaselineNodes $Baseline -CurrentNodes $Current
                $changes = @()
                
                foreach ($mapping in $identityMap.mappings) {
                    if ($mapping.matchType -like 'rekeyed*') {
                        $changes += [PSCustomObject]@{
                            changeType = 'rekeyed'
                            nodeId = $mapping.currentNodeId
                            details = @{
                                oldNodeId = $mapping.baselineNodeId
                                newNodeId = $mapping.currentNodeId
                            }
                        }
                    }
                }
                
                return $changes
            }
        }
        
        It 'Detects rekeyed node when nodeId changes but externalId matches' {
            $baseline = @(
                New-TestNodeFull -NodeId '100' -Name 'Robot1' -ExternalId 'PP-12345678-abcd-1234-5678-abcdef123456'
            )
            $current = @(
                New-TestNodeFull -NodeId '999' -Name 'Robot1' -ExternalId 'PP-12345678-abcd-1234-5678-abcdef123456'
            )
            
            $changes = Test-RekeyedDetection -Baseline $baseline -Current $current
            
            $rekeyed = $changes | Where-Object { $_.changeType -eq 'rekeyed' }
            $rekeyed.Count | Should -Be 1
            $rekeyed[0].details.oldNodeId | Should -Be '100'
            $rekeyed[0].details.newNodeId | Should -Be '999'
        }
        
        It 'Does not flag as rekeyed when nodeId is unchanged' {
            $baseline = @(
                New-TestNodeFull -NodeId '100' -Name 'Robot1' -ExternalId 'PP-12345678-abcd-1234-5678-abcdef123456'
            )
            $current = @(
                New-TestNodeFull -NodeId '100' -Name 'Robot1' -ExternalId 'PP-12345678-abcd-1234-5678-abcdef123456'
            )
            
            $changes = Test-RekeyedDetection -Baseline $baseline -Current $current
            
            $rekeyed = $changes | Where-Object { $_.changeType -eq 'rekeyed' }
            $rekeyed.Count | Should -Be 0
        }
    }
}

Describe 'Configuration' {
    Context 'Get-IdentityResolverConfig' {
        It 'Returns default configuration' {
            $config = Get-IdentityResolverConfig
            
            $config.ConfidenceThreshold | Should -Be 0.85
            $config.Weights | Should -Not -BeNullOrEmpty
            $config.Weights.ExternalId | Should -Be 1.0
        }
    }
    
    Context 'Set-IdentityResolverConfig' {
        It 'Updates confidence threshold' {
            $originalConfig = Get-IdentityResolverConfig
            $originalThreshold = $originalConfig.ConfidenceThreshold
            
            Set-IdentityResolverConfig -ConfidenceThreshold 0.9
            
            $newConfig = Get-IdentityResolverConfig
            $newConfig.ConfidenceThreshold | Should -Be 0.9
            
            # Restore
            Set-IdentityResolverConfig -ConfidenceThreshold $originalThreshold
        }
        
        It 'Updates weights' {
            $originalConfig = Get-IdentityResolverConfig
            $originalWeight = $originalConfig.Weights.NameOnly
            
            Set-IdentityResolverConfig -Weights @{ NameOnly = 0.5 }
            
            $newConfig = Get-IdentityResolverConfig
            $newConfig.Weights.NameOnly | Should -Be 0.5
            
            # Restore
            Set-IdentityResolverConfig -Weights @{ NameOnly = $originalWeight }
        }
    }
}
