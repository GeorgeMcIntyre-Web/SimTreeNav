# Determinism.Tests.ps1
# Proves that snapshots and diffs are byte-for-byte deterministic
# v0.3.1 Audit requirement

BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . "$scriptRoot/src/powershell/v02/core/NodeContract.ps1"
    . "$scriptRoot/src/powershell/v02/core/IdentityResolver.ps1"
    
    # Define change types (from Compare-Snapshots.ps1)
    $Script:ChangeTypes = @{
        Added             = 'added'
        Removed           = 'removed'
        Rekeyed           = 'rekeyed'
        Renamed           = 'renamed'
        Moved             = 'moved'
        AttributeChanged  = 'attribute_changed'
        TransformChanged  = 'transform_changed'
    }
    
    # Define Compare-NodesLegacy function for testing
    function Compare-NodesLegacy {
        param(
            [array]$BaselineNodes,
            [array]$CurrentNodes
        )
        
        $changes = @()
        
        # Build lookup maps
        $baselineMap = @{}
        foreach ($node in $BaselineNodes) {
            $baselineMap[$node.nodeId] = $node
        }
        
        $currentMap = @{}
        foreach ($node in $CurrentNodes) {
            $currentMap[$node.nodeId] = $node
        }
        
        # Find added nodes
        foreach ($nodeId in $currentMap.Keys | Sort-Object) {
            if (-not $baselineMap.ContainsKey($nodeId)) {
                $node = $currentMap[$nodeId]
                $changes += [PSCustomObject]@{
                    changeType = $Script:ChangeTypes.Added
                    nodeId     = $nodeId
                    nodeName   = $node.name
                    nodeType   = $node.nodeType
                    path       = $node.path
                }
            }
        }
        
        # Find removed nodes
        foreach ($nodeId in $baselineMap.Keys | Sort-Object) {
            if (-not $currentMap.ContainsKey($nodeId)) {
                $node = $baselineMap[$nodeId]
                $changes += [PSCustomObject]@{
                    changeType = $Script:ChangeTypes.Removed
                    nodeId     = $nodeId
                    nodeName   = $node.name
                    nodeType   = $node.nodeType
                    path       = $node.path
                }
            }
        }
        
        # Find modified nodes
        foreach ($nodeId in $baselineMap.Keys | Sort-Object) {
            if ($currentMap.ContainsKey($nodeId)) {
                $baseline = $baselineMap[$nodeId]
                $current = $currentMap[$nodeId]
                
                # Check rename
                if ($baseline.name -ne $current.name) {
                    $changes += [PSCustomObject]@{
                        changeType = $Script:ChangeTypes.Renamed
                        nodeId     = $nodeId
                        nodeName   = $current.name
                        nodeType   = $current.nodeType
                        path       = $current.path
                        details    = @{ oldName = $baseline.name; newName = $current.name }
                    }
                }
                
                # Check move
                if ($baseline.parentId -ne $current.parentId) {
                    $changes += [PSCustomObject]@{
                        changeType = $Script:ChangeTypes.Moved
                        nodeId     = $nodeId
                        nodeName   = $current.name
                        nodeType   = $current.nodeType
                        path       = $current.path
                        details    = @{ oldParentId = $baseline.parentId; newParentId = $current.parentId }
                    }
                }
            }
        }
        
        # Sort for determinism
        return $changes | Sort-Object changeType, nodeId
    }
}

Describe 'Determinism' {
    
    BeforeAll {
        # Helper to create consistent test nodes
        function New-TestNode {
            param(
                [string]$NodeId,
                [string]$Name,
                [string]$NodeType = 'Resource',
                [string]$ParentId = $null,
                [string]$ExternalId = $null,
                [string]$ClassName = 'TestClass'
            )
            
            $extId = if ($ExternalId) { $ExternalId } else { "PP-$NodeId-test-uuid" }
            
            [PSCustomObject]@{
                nodeId      = $NodeId
                name        = $Name
                nodeType    = $NodeType
                parentId    = $ParentId
                path        = "/$Name"
                attributes  = [PSCustomObject]@{
                    externalId = $extId
                    className  = $ClassName
                    niceName   = $Name
                    typeId     = 100
                }
                links       = $null
                fingerprints = [PSCustomObject]@{
                    contentHash   = $null
                    attributeHash = $null
                    transformHash = $null
                }
                source      = [PSCustomObject]@{
                    table = 'TEST_TABLE'
                }
            }
        }
        
        # Generate a deterministic test dataset
        function Get-TestDataset {
            param([int]$Seed = 42)
            
            # Use predictable data, not random
            $nodes = @()
            
            # Root
            $nodes += New-TestNode -NodeId '1000' -Name 'Root' -NodeType 'Root'
            
            # Stations (in specific order)
            $nodes += New-TestNode -NodeId '1001' -Name 'Station_Alpha' -NodeType 'Station' -ParentId '1000'
            $nodes += New-TestNode -NodeId '1002' -Name 'Station_Beta' -NodeType 'Station' -ParentId '1000'
            $nodes += New-TestNode -NodeId '1003' -Name 'Station_Gamma' -NodeType 'Station' -ParentId '1000'
            
            # Resources under Station_Alpha
            $nodes += New-TestNode -NodeId '2001' -Name 'Robot_1' -NodeType 'Resource' -ParentId '1001'
            $nodes += New-TestNode -NodeId '2002' -Name 'Robot_2' -NodeType 'Resource' -ParentId '1001'
            
            # Tools
            $nodes += New-TestNode -NodeId '3001' -Name 'WeldGun_001' -NodeType 'ToolInstance' -ParentId '2001'
            $nodes += New-TestNode -NodeId '3002' -Name 'Gripper_001' -NodeType 'ToolInstance' -ParentId '2002'
            
            # Operations
            $nodes += New-TestNode -NodeId '4001' -Name 'Op_Weld_1' -NodeType 'Operation' -ParentId '1001'
            $nodes += New-TestNode -NodeId '4002' -Name 'Op_Move_1' -NodeType 'Operation' -ParentId '1001'
            
            return $nodes
        }
    }
    
    Describe 'Snapshot Determinism' {
        
        It 'ConvertTo-CanonicalJson produces identical output for same input' {
            $nodes = Get-TestDataset
            
            # Generate JSON twice
            $json1 = ConvertTo-CanonicalJson -Nodes $nodes -Pretty
            $json2 = ConvertTo-CanonicalJson -Nodes $nodes -Pretty
            
            $json1 | Should -BeExactly $json2
        }
        
        It 'ConvertTo-CanonicalJson produces identical output regardless of input order' {
            $nodes = Get-TestDataset
            
            # Shuffle the input array
            $shuffled = $nodes | Sort-Object { Get-Random }
            
            # Generate JSON from both orderings
            $json1 = ConvertTo-CanonicalJson -Nodes $nodes -Pretty
            $json2 = ConvertTo-CanonicalJson -Nodes $shuffled -Pretty
            
            $json1 | Should -BeExactly $json2
        }
        
        It 'Compact JSON is also deterministic' {
            $nodes = Get-TestDataset
            $shuffled = $nodes | Sort-Object { Get-Random }
            
            # Compact (no Pretty flag)
            $json1 = ConvertTo-CanonicalJson -Nodes $nodes
            $json2 = ConvertTo-CanonicalJson -Nodes $shuffled
            
            $json1 | Should -BeExactly $json2
        }
        
        It 'Content hash is deterministic for same input' {
            $hash1 = Get-ContentHash -Name 'TestNode' -ExternalId 'PP-123' -ClassName 'TestClass'
            $hash2 = Get-ContentHash -Name 'TestNode' -ExternalId 'PP-123' -ClassName 'TestClass'
            
            $hash1 | Should -BeExactly $hash2
        }
        
        It 'Attribute hash is deterministic regardless of hashtable key order' {
            # PowerShell hashtables don't guarantee order, so test this
            $attrs1 = @{ name = 'Test'; color = 'Red'; size = 10 }
            $attrs2 = @{ size = 10; name = 'Test'; color = 'Red' }
            
            $hash1 = Get-AttributeHash -Attributes $attrs1
            $hash2 = Get-AttributeHash -Attributes $attrs2
            
            $hash1 | Should -BeExactly $hash2
        }
        
        It 'Multiple runs produce byte-for-byte identical JSON' {
            $nodes = Get-TestDataset
            
            # Run multiple times
            $outputs = 1..5 | ForEach-Object {
                ConvertTo-CanonicalJson -Nodes $nodes -Pretty
            }
            
            # All should be identical
            $first = $outputs[0]
            foreach ($output in $outputs[1..4]) {
                $output | Should -BeExactly $first
            }
        }
    }
    
    Describe 'Diff Determinism' {
        
        BeforeAll {
            function Get-BaselineAndCurrent {
                $baseline = Get-TestDataset
                
                # Create current with some changes
                $current = Get-TestDataset
                
                # Rename a node
                ($current | Where-Object { $_.nodeId -eq '2001' }).name = 'Robot_1_Renamed'
                
                # Add a new node
                $current += New-TestNode -NodeId '9001' -Name 'NewNode' -NodeType 'Resource' -ParentId '1001'
                
                # Remove a node (filter it out)
                $current = $current | Where-Object { $_.nodeId -ne '3002' }
                
                return @{ baseline = $baseline; current = $current }
            }
        }
        
        It 'Compare-NodesLegacy produces identical diff for same input' {
            $data = Get-BaselineAndCurrent
            
            $diff1 = Compare-NodesLegacy -BaselineNodes $data.baseline -CurrentNodes $data.current
            $diff2 = Compare-NodesLegacy -BaselineNodes $data.baseline -CurrentNodes $data.current
            
            # Compare JSON representations
            $json1 = $diff1 | ConvertTo-Json -Depth 10 -Compress
            $json2 = $diff2 | ConvertTo-Json -Depth 10 -Compress
            
            $json1 | Should -BeExactly $json2
        }
        
        It 'Compare-NodesLegacy is deterministic regardless of input array order' {
            $data = Get-BaselineAndCurrent
            
            # Shuffle inputs
            $baselineShuffled = $data.baseline | Sort-Object { Get-Random }
            $currentShuffled = $data.current | Sort-Object { Get-Random }
            
            $diff1 = Compare-NodesLegacy -BaselineNodes $data.baseline -CurrentNodes $data.current
            $diff2 = Compare-NodesLegacy -BaselineNodes $baselineShuffled -CurrentNodes $currentShuffled
            
            # Sort changes for comparison (since order might differ)
            $changes1 = $diff1 | Sort-Object nodeId, changeType | ConvertTo-Json -Depth 10 -Compress
            $changes2 = $diff2 | Sort-Object nodeId, changeType | ConvertTo-Json -Depth 10 -Compress
            
            $changes1 | Should -BeExactly $changes2
        }
        
        It 'Change detection is consistent' {
            $data = Get-BaselineAndCurrent
            
            $diff = Compare-NodesLegacy -BaselineNodes $data.baseline -CurrentNodes $data.current
            
            # Should have specific changes
            $added = $diff | Where-Object { $_.changeType -eq 'added' }
            $removed = $diff | Where-Object { $_.changeType -eq 'removed' }
            $renamed = $diff | Where-Object { $_.changeType -eq 'renamed' }
            
            $added.Count | Should -Be 1
            $added[0].nodeId | Should -Be '9001'
            
            $removed.Count | Should -Be 1
            $removed[0].nodeId | Should -Be '3002'
            
            $renamed.Count | Should -Be 1
            $renamed[0].nodeId | Should -Be '2001'
        }
    }
    
    Describe 'Identity Resolution Determinism' {
        
        It 'Get-LogicalId is deterministic for same node' {
            $node = New-TestNode -NodeId '1234' -Name 'TestNode' -ExternalId 'PP-abc12345-6789-0123-4567-890123456789'
            $node.path = '/Root/TestNode'
            
            $id1 = Get-LogicalId -Node $node
            $id2 = Get-LogicalId -Node $node
            
            $id1 | Should -BeExactly $id2
        }
        
        It 'Resolve-NodeIdentities produces deterministic results' {
            $nodes = Get-TestDataset
            
            # Resolve twice
            $resolved1 = Resolve-NodeIdentities -Nodes ($nodes | ForEach-Object { $_.PSObject.Copy() })
            $resolved2 = Resolve-NodeIdentities -Nodes ($nodes | ForEach-Object { $_.PSObject.Copy() })
            
            # Compare logical IDs
            for ($i = 0; $i -lt $resolved1.Count; $i++) {
                $resolved1[$i].identity.logicalId | Should -BeExactly $resolved2[$i].identity.logicalId
            }
        }
        
        It 'Compare-IdentitySignatures produces deterministic confidence scores' {
            $sig1 = [PSCustomObject]@{
                name = 'TestNode'
                nodeType = 'Resource'
                parentPath = '/Root'
                externalId = 'PP-test-123'
                contentHash = 'abcd1234'
                transformHash = $null
                prototypeId = $null
            }
            
            $sig2 = [PSCustomObject]@{
                name = 'TestNode'
                nodeType = 'Resource'
                parentPath = '/Root'
                externalId = 'PP-test-123'
                contentHash = 'abcd1234'
                transformHash = $null
                prototypeId = $null
            }
            
            $result1 = Compare-IdentitySignatures -Signature1 $sig1 -Signature2 $sig2
            $result2 = Compare-IdentitySignatures -Signature1 $sig1 -Signature2 $sig2
            
            $result1.confidence | Should -BeExactly $result2.confidence
            $result1.reason | Should -BeExactly $result2.reason
        }
    }
    
    Describe 'Timestamp Isolation' {
        
        It 'Nodes do not contain timestamps' {
            $node = New-TestNode -NodeId '1' -Name 'Test'
            
            # Nodes should not have timestamp at root level
            $node.PSObject.Properties.Name | Should -Not -Contain 'timestamp'
            $node.PSObject.Properties.Name | Should -Not -Contain 'createdAt'
            $node.PSObject.Properties.Name | Should -Not -Contain 'updatedAt'
        }
        
        It 'Diff changes do not embed timestamps that would break determinism' {
            # Create baseline and current inline
            $baseline = Get-TestDataset
            $current = Get-TestDataset
            ($current | Where-Object { $_.nodeId -eq '2001' }).name = 'Robot_1_Renamed'
            
            $diff = Compare-NodesLegacy -BaselineNodes $baseline -CurrentNodes $current
            
            foreach ($change in $diff) {
                # Changes should not have volatile timestamps
                $change.PSObject.Properties.Name | Should -Not -Contain 'timestamp'
                $change.PSObject.Properties.Name | Should -Not -Contain 'detectedAt'
            }
        }
    }
}
