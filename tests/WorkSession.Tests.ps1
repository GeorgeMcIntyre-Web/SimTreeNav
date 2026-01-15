# WorkSession.Tests.ps1
# Pester tests for WorkSessionEngine and IntentEngine

BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    . "$scriptRoot/src/powershell/v02/analysis/WorkSessionEngine.ps1"
    . "$scriptRoot/src/powershell/v02/analysis/IntentEngine.ps1"
}

Describe 'WorkSessionEngine' {
    
    Describe 'Get-SubtreePath' {
        It 'Extracts subtree at depth 2' {
            $result = Get-SubtreePath -Path '/Station_A/ResourceGroup_1/Robot_1/Tool_1' -Depth 2
            $result | Should -Be '/Station_A/ResourceGroup_1'
        }
        
        It 'Handles shallow paths' {
            $result = Get-SubtreePath -Path '/Station_A' -Depth 2
            $result | Should -Be '/Station_A'
        }
        
        It 'Handles null paths' {
            $result = Get-SubtreePath -Path $null -Depth 2
            $result | Should -Be '/'
        }
        
        It 'Handles empty paths' {
            $result = Get-SubtreePath -Path '' -Depth 2
            $result | Should -Be '/'
        }
    }
    
    Describe 'Group-ChangesIntoSessions' {
        It 'Groups spatially related changes' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'renamed'; nodeType = 'Resource'; path = '/Station_A/RG1/Robot1'; nodeName = 'Robot1' }
                [PSCustomObject]@{ nodeId = 'N2'; changeType = 'renamed'; nodeType = 'Resource'; path = '/Station_A/RG1/Robot2'; nodeName = 'Robot2' }
                [PSCustomObject]@{ nodeId = 'N3'; changeType = 'renamed'; nodeType = 'Resource'; path = '/Station_A/RG1/Robot3'; nodeName = 'Robot3' }
            )
            
            $sessions = Group-ChangesIntoSessions -Changes $changes -MinChangesPerSession 2
            
            $sessions | Should -HaveCount 1
            $sessions[0].changeCount | Should -Be 3
            $sessions[0].subtrees | Should -Contain '/Station_A/RG1'
        }
        
        It 'Separates spatially distant changes' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'renamed'; nodeType = 'Resource'; path = '/Station_A/RG1/Robot1'; nodeName = 'Robot1' }
                [PSCustomObject]@{ nodeId = 'N2'; changeType = 'renamed'; nodeType = 'Resource'; path = '/Station_A/RG1/Robot2'; nodeName = 'Robot2' }
                [PSCustomObject]@{ nodeId = 'N3'; changeType = 'added'; nodeType = 'Tool'; path = '/Station_Z/Tools/NewTool'; nodeName = 'NewTool' }
                [PSCustomObject]@{ nodeId = 'N4'; changeType = 'added'; nodeType = 'Tool'; path = '/Station_Z/Tools/NewTool2'; nodeName = 'NewTool2' }
            )
            
            $sessions = Group-ChangesIntoSessions -Changes $changes -MinChangesPerSession 2
            
            # Should have 2 sessions - one for Station_A renames, one for Station_Z adds
            $sessions.Count | Should -BeGreaterOrEqual 1
            $totalChanges = ($sessions | Measure-Object -Property changeCount -Sum).Sum
            $totalChanges | Should -Be 4
        }
        
        It 'Creates summary statistics' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'renamed'; nodeType = 'Resource'; path = '/Station_A/RG1/Robot1'; nodeName = 'Robot1' }
                [PSCustomObject]@{ nodeId = 'N2'; changeType = 'moved'; nodeType = 'Resource'; path = '/Station_A/RG1/Robot2'; nodeName = 'Robot2' }
                [PSCustomObject]@{ nodeId = 'N3'; changeType = 'renamed'; nodeType = 'Tool'; path = '/Station_A/RG1/Tool1'; nodeName = 'Tool1' }
            )
            
            $sessions = Group-ChangesIntoSessions -Changes $changes -MinChangesPerSession 2
            
            $sessions[0].summary | Should -Not -BeNullOrEmpty
            $sessions[0].summary.totalChanges | Should -Be 3
            $sessions[0].summary.byChangeType | Should -Not -BeNullOrEmpty
        }
        
        It 'Handles empty changes' {
            $sessions = Group-ChangesIntoSessions -Changes @() -MinChangesPerSession 2
            $sessions | Should -HaveCount 0
        }
        
        It 'Assigns confidence score' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'renamed'; nodeType = 'Resource'; path = '/Station_A/RG1/R1'; nodeName = 'R1' }
                [PSCustomObject]@{ nodeId = 'N2'; changeType = 'renamed'; nodeType = 'Resource'; path = '/Station_A/RG1/R2'; nodeName = 'R2' }
            )
            
            $sessions = Group-ChangesIntoSessions -Changes $changes -MinChangesPerSession 2
            
            $sessions[0].confidence | Should -BeGreaterOrEqual 0
            $sessions[0].confidence | Should -BeLessOrEqual 1
        }
    }
}

Describe 'IntentEngine' {
    
    Describe 'Detect-RetouchingPoints' {
        It 'Detects retouching when many transforms in operations' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'transform_changed'; nodeType = 'Operation'; path = '/Station_A/Ops/Op1'; nodeName = 'Op1' }
                [PSCustomObject]@{ nodeId = 'N2'; changeType = 'transform_changed'; nodeType = 'Location'; path = '/Station_A/Ops/Loc1'; nodeName = 'Loc1' }
                [PSCustomObject]@{ nodeId = 'N3'; changeType = 'transform_changed'; nodeType = 'Operation'; path = '/Station_A/Ops/Op2'; nodeName = 'Op2' }
                [PSCustomObject]@{ nodeId = 'N4'; changeType = 'transform_changed'; nodeType = 'Location'; path = '/Station_A/Ops/Loc2'; nodeName = 'Loc2' }
            )
            
            $intent = Detect-RetouchingPoints -Changes $changes
            
            $intent | Should -Not -BeNullOrEmpty
            $intent.intentType | Should -Be 'retouching_points'
            $intent.confidence | Should -BeGreaterThan 0.5
        }
        
        It 'Does not detect retouching with few transforms' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'transform_changed'; nodeType = 'Operation'; path = '/Station_A/Ops/Op1'; nodeName = 'Op1' }
            )
            
            $intent = Detect-RetouchingPoints -Changes $changes
            
            $intent | Should -BeNullOrEmpty
        }
    }
    
    Describe 'Detect-StationRestructure' {
        It 'Detects restructure with many moves' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'moved'; nodeType = 'ResourceGroup'; path = '/Station_A/RG1'; nodeName = 'RG1' }
                [PSCustomObject]@{ nodeId = 'N2'; changeType = 'moved'; nodeType = 'ResourceGroup'; path = '/Station_A/RG2'; nodeName = 'RG2' }
                [PSCustomObject]@{ nodeId = 'N3'; changeType = 'moved'; nodeType = 'Resource'; path = '/Station_A/RG3'; nodeName = 'Robot1' }
                [PSCustomObject]@{ nodeId = 'N4'; changeType = 'renamed'; nodeType = 'Resource'; path = '/Station_A/RG4'; nodeName = 'Robot2' }
            )
            
            $intent = Detect-StationRestructure -Changes $changes
            
            $intent | Should -Not -BeNullOrEmpty
            $intent.intentType | Should -Be 'station_restructure'
        }
        
        It 'Does not detect with few moves' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'moved'; nodeType = 'Resource'; path = '/Station_A/R1'; nodeName = 'R1' }
            )
            
            $intent = Detect-StationRestructure -Changes $changes
            
            $intent | Should -BeNullOrEmpty
        }
    }
    
    Describe 'Detect-BulkPasteTemplate' {
        It 'Detects bulk paste with many adds' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'added'; nodeType = 'Tool'; path = '/Tools/Tool_001'; nodeName = 'Tool_001'; parentId = 'P1' }
                [PSCustomObject]@{ nodeId = 'N2'; changeType = 'added'; nodeType = 'Tool'; path = '/Tools/Tool_002'; nodeName = 'Tool_002'; parentId = 'P1' }
                [PSCustomObject]@{ nodeId = 'N3'; changeType = 'added'; nodeType = 'Tool'; path = '/Tools/Tool_003'; nodeName = 'Tool_003'; parentId = 'P1' }
                [PSCustomObject]@{ nodeId = 'N4'; changeType = 'added'; nodeType = 'Tool'; path = '/Tools/Tool_004'; nodeName = 'Tool_004'; parentId = 'P1' }
                [PSCustomObject]@{ nodeId = 'N5'; changeType = 'added'; nodeType = 'Tool'; path = '/Tools/Tool_005'; nodeName = 'Tool_005'; parentId = 'P1' }
                [PSCustomObject]@{ nodeId = 'N6'; changeType = 'added'; nodeType = 'Tool'; path = '/Tools/Tool_006'; nodeName = 'Tool_006'; parentId = 'P1' }
            )
            
            $intent = Detect-BulkPasteTemplate -Changes $changes
            
            $intent | Should -Not -BeNullOrEmpty
            $intent.intentType | Should -Be 'bulk_paste_template'
            $intent.details.commonPrefix | Should -Be 'Tool'
        }
        
        It 'Does not detect with few adds' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'added'; nodeType = 'Tool'; path = '/Tools/T1'; nodeName = 'T1' }
            )
            
            $intent = Detect-BulkPasteTemplate -Changes $changes
            
            $intent | Should -BeNullOrEmpty
        }
    }
    
    Describe 'Detect-Cleanup' {
        It 'Detects cleanup with many deletions' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'removed'; nodeType = 'Tool'; path = '/Old/Tool1'; nodeName = 'Tool1' }
                [PSCustomObject]@{ nodeId = 'N2'; changeType = 'removed'; nodeType = 'Tool'; path = '/Old/Tool2'; nodeName = 'Tool2' }
                [PSCustomObject]@{ nodeId = 'N3'; changeType = 'removed'; nodeType = 'Tool'; path = '/Old/Tool3'; nodeName = 'Tool3' }
                [PSCustomObject]@{ nodeId = 'N4'; changeType = 'removed'; nodeType = 'Tool'; path = '/Old/Tool4'; nodeName = 'Tool4' }
            )
            
            $intent = Detect-Cleanup -Changes $changes
            
            $intent | Should -Not -BeNullOrEmpty
            $intent.intentType | Should -Be 'cleanup'
        }
    }
    
    Describe 'Invoke-IntentAnalysis' {
        It 'Returns intents sorted by confidence' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'transform_changed'; nodeType = 'Operation'; path = '/Station_A/Ops/Op1'; nodeName = 'Op1' }
                [PSCustomObject]@{ nodeId = 'N2'; changeType = 'transform_changed'; nodeType = 'Operation'; path = '/Station_A/Ops/Op2'; nodeName = 'Op2' }
                [PSCustomObject]@{ nodeId = 'N3'; changeType = 'transform_changed'; nodeType = 'Operation'; path = '/Station_A/Ops/Op3'; nodeName = 'Op3' }
                [PSCustomObject]@{ nodeId = 'N4'; changeType = 'transform_changed'; nodeType = 'Operation'; path = '/Station_A/Ops/Op4'; nodeName = 'Op4' }
            )
            
            $intents = Invoke-IntentAnalysis -Changes $changes
            
            $intents | Should -Not -BeNullOrEmpty
            $intents[0].confidence | Should -BeGreaterOrEqual $intents[-1].confidence
        }
        
        It 'Returns unknown intent when no pattern matches' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'attribute_changed'; nodeType = 'Generic'; path = '/Misc/Node1'; nodeName = 'Node1' }
            )
            
            $intents = Invoke-IntentAnalysis -Changes $changes
            
            $intents | Should -Not -BeNullOrEmpty
            $intents[0].intentType | Should -Be 'unknown'
        }
        
        It 'Adds session ID when provided' {
            $changes = @(
                [PSCustomObject]@{ nodeId = 'N1'; changeType = 'renamed'; nodeType = 'Resource'; path = '/S/R1'; nodeName = 'R1' }
            )
            
            $intents = Invoke-IntentAnalysis -Changes $changes -SessionId 'session_001'
            
            $intents[0].sessionId | Should -Be 'session_001'
        }
    }
    
    Describe 'Get-CommonPrefix' {
        It 'Finds common prefix' {
            $result = Get-CommonPrefix -Strings @('Tool_001', 'Tool_002', 'Tool_003')
            $result | Should -Be 'Tool'
        }
        
        It 'Handles no common prefix' {
            $result = Get-CommonPrefix -Strings @('Alpha', 'Beta', 'Gamma')
            $result | Should -Be ''
        }
        
        It 'Handles single string' {
            $result = Get-CommonPrefix -Strings @('SingleName')
            $result | Should -Be 'SingleName'
        }
        
        It 'Handles empty array' {
            $result = Get-CommonPrefix -Strings @()
            $result | Should -Be ''
        }
    }
}
