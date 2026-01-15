# ExportBundle.Tests.ps1
# Tests for ExportBundle v0.4 enhancements

BeforeAll {
    $scriptRoot = Split-Path $PSScriptRoot -Parent
    . "$scriptRoot\src\powershell\v02\export\ExportBundle.ps1"
    . "$scriptRoot\src\powershell\v02\export\Anonymizer.ps1"
}

Describe 'Export-Bundle Basic Functionality' {
    BeforeEach {
        $testOutDir = Join-Path $TestDrive 'test-bundle'
        $testNodes = @(
            [PSCustomObject]@{
                nodeId   = 'N000001'
                name     = 'TestRoot'
                nodeType = 'Root'
                parentId = $null
                path     = '/TestRoot'
            },
            [PSCustomObject]@{
                nodeId   = 'N000002'
                name     = 'TestStation'
                nodeType = 'Station'
                parentId = 'N000001'
                path     = '/TestRoot/TestStation'
            }
        )
        $testDiff = [PSCustomObject]@{
            summary = [PSCustomObject]@{ totalChanges = 1; added = 1 }
            changes = @(
                [PSCustomObject]@{
                    changeType = 'added'
                    nodeName   = 'NewNode'
                    nodeType   = 'Station'
                }
            )
        }
    }
    
    It 'Creates bundle directory' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes | Out-Null
        
        Test-Path $testOutDir | Should -Be $true
    }
    
    It 'Creates index.html' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes | Out-Null
        
        Test-Path (Join-Path $testOutDir 'index.html') | Should -Be $true
    }
    
    It 'Creates data directory' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Diff $testDiff | Out-Null
        
        Test-Path (Join-Path $testOutDir 'data') | Should -Be $true
    }
    
    It 'Creates manifest.json' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes | Out-Null
        
        Test-Path (Join-Path $testOutDir 'manifest.json') | Should -Be $true
    }
    
    It 'Returns result object with path' {
        $result = Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes
        
        $result.path | Should -Be $testOutDir
    }
}

Describe 'Export-Bundle BundleName Parameter' {
    BeforeEach {
        $testOutDir = Join-Path $TestDrive 'name-test'
        $testNodes = @(
            [PSCustomObject]@{
                nodeId   = 'N001'
                name     = 'Root'
                nodeType = 'Root'
                parentId = $null
                path     = '/Root'
            }
        )
    }
    
    It 'Uses default bundle name' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes | Out-Null
        
        $indexContent = Get-Content (Join-Path $testOutDir 'index.html') -Raw
        $indexContent | Should -Match 'SimTreeNav Bundle'
    }
    
    It 'Uses custom bundle name' {
        Export-Bundle -OutDir $testOutDir -BundleName 'My Custom Demo' -CurrentNodes $testNodes | Out-Null
        
        $indexContent = Get-Content (Join-Path $testOutDir 'index.html') -Raw
        $indexContent | Should -Match 'My Custom Demo'
    }
    
    It 'Supports Name alias for BundleName' {
        Export-Bundle -OutDir $testOutDir -Name 'Aliased Name' -CurrentNodes $testNodes | Out-Null
        
        $indexContent = Get-Content (Join-Path $testOutDir 'index.html') -Raw
        $indexContent | Should -Match 'Aliased Name'
    }
    
    It 'Includes bundle name in manifest' {
        Export-Bundle -OutDir $testOutDir -BundleName 'Manifest Test' -CurrentNodes $testNodes | Out-Null
        
        $manifest = Get-Content (Join-Path $testOutDir 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.bundleName | Should -Be 'Manifest Test'
    }
}

Describe 'Export-Bundle Timeline Support' {
    BeforeEach {
        $testOutDir = Join-Path $TestDrive 'timeline-test'
        $testNodes = @(
            [PSCustomObject]@{
                nodeId   = 'N001'
                name     = 'Root'
                nodeType = 'Root'
                parentId = $null
                path     = '/Root'
            }
        )
        $testTimeline = @(
            [PSCustomObject]@{
                snapshotId  = 'snap_01'
                label       = 'Baseline'
                timestamp   = '2026-01-15T00:00:00Z'
                nodeCount   = 100
                changeCount = 0
                eventType   = 'baseline'
            },
            [PSCustomObject]@{
                snapshotId  = 'snap_02'
                label       = 'Changes'
                timestamp   = '2026-01-15T01:00:00Z'
                nodeCount   = 110
                changeCount = 10
                eventType   = 'bulk_paste'
            }
        )
    }
    
    It 'Includes timeline in bundle' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Timeline $testTimeline | Out-Null
        
        $indexContent = Get-Content (Join-Path $testOutDir 'index.html') -Raw
        $indexContent | Should -Match 'snap_01'
        $indexContent | Should -Match 'Baseline'
    }
    
    It 'Creates timeline.json' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Timeline $testTimeline | Out-Null
        
        Test-Path (Join-Path $testOutDir 'data' 'timeline.json') | Should -Be $true
    }
    
    It 'Sets hasTimeline flag in result' {
        $result = Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Timeline $testTimeline
        
        $result.hasTimeline | Should -Be $true
    }
    
    It 'Sets hasTimeline false when no timeline' {
        $result = Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes
        
        $result.hasTimeline | Should -Be $false
    }
}

Describe 'Export-Bundle Anonymization' {
    BeforeEach {
        $testOutDir = Join-Path $TestDrive 'anon-bundle'
        $testNodes = @(
            [PSCustomObject]@{
                nodeId     = 'N000001'
                name       = 'SecretStation'
                nodeType   = 'Station'
                parentId   = $null
                path       = '/SecretStation'
                attributes = [PSCustomObject]@{ externalId = 'EXT-SECRET' }
                source     = [PSCustomObject]@{ table = 'SECRET_TABLE' }
            }
        )
        $testDiff = [PSCustomObject]@{
            summary = [PSCustomObject]@{ totalChanges = 1 }
            changes = @(
                [PSCustomObject]@{
                    changeType = 'renamed'
                    nodeName   = 'SecretStation'
                    nodeType   = 'Station'
                    path       = '/SecretStation'
                }
            )
        }
    }
    
    It 'Anonymizes nodes when -Anonymize specified' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Anonymize | Out-Null
        
        $indexContent = Get-Content (Join-Path $testOutDir 'index.html') -Raw
        $indexContent | Should -Not -Match 'SecretStation'
        $indexContent | Should -Match 'ST-\d{4}'
    }
    
    It 'Sets isAnonymized flag' {
        $result = Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Anonymize
        
        $result.isAnonymized | Should -Be $true
    }
    
    It 'Creates private mapping file' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Anonymize | Out-Null
        
        Test-Path (Join-Path $testOutDir '.anonymize-mapping.json') | Should -Be $true
    }
    
    It 'Uses custom anonymization seed' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Anonymize -AnonymizeSeed 'custom-seed' | Out-Null
        
        $mapping = Get-Content (Join-Path $testOutDir '.anonymize-mapping.json') -Raw | ConvertFrom-Json
        $mapping.seed | Should -Be 'custom-seed'
    }
    
    It 'Anonymizes diff data' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Diff $testDiff -Anonymize | Out-Null
        
        $diffJson = Get-Content (Join-Path $testOutDir 'data' 'diff.json') -Raw
        $diffJson | Should -Not -Match 'SecretStation'
    }
}

Describe 'Export-Bundle CreateZip' {
    BeforeEach {
        $testOutDir = Join-Path $TestDrive 'zip-test'
        $testNodes = @(
            [PSCustomObject]@{
                nodeId   = 'N001'
                name     = 'Root'
                nodeType = 'Root'
                parentId = $null
                path     = '/Root'
            }
        )
    }
    
    It 'Creates zip file when requested' {
        $result = Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -CreateZip
        
        Test-Path "$testOutDir.zip" | Should -Be $true
        $result.zipPath | Should -Be "$testOutDir.zip"
    }
    
    It 'Does not create zip by default' {
        $result = Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes
        
        $result.zipPath | Should -BeNullOrEmpty
    }
}

Describe 'Export-Bundle MaxNodesInViewer' {
    BeforeEach {
        $testOutDir = Join-Path $TestDrive 'maxnodes-test'
        # Create 100 nodes
        $testNodes = 1..100 | ForEach-Object {
            [PSCustomObject]@{
                nodeId   = "N$($_.ToString('D6'))"
                name     = "Node_$_"
                nodeType = 'Station'
                parentId = $null
                path     = "/Node_$_"
            }
        }
    }
    
    It 'Limits nodes in viewer by default (2000)' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes | Out-Null
        
        $indexContent = Get-Content (Join-Path $testOutDir 'index.html') -Raw
        # Should contain all 100 since under limit
        $indexContent | Should -Match 'Node_100'
    }
    
    It 'Respects custom MaxNodesInViewer limit' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -MaxNodesInViewer 10 | Out-Null
        
        $indexContent = Get-Content (Join-Path $testOutDir 'index.html') -Raw
        # Should not contain Node_11 since limited to 10
        $indexContent | Should -Not -Match 'Node_11'
    }
}

Describe 'Export-Bundle RawSql Support' {
    BeforeEach {
        $testOutDir = Join-Path $TestDrive 'sql-test'
        $testNodes = @(
            [PSCustomObject]@{
                nodeId   = 'N001'
                name     = 'Root'
                nodeType = 'Root'
                parentId = $null
                path     = '/Root'
            }
        )
        $testQueries = @(
            [PSCustomObject]@{
                queryName = 'GetNodes'
                sql       = 'SELECT * FROM NODES'
                duration  = 150
            }
        )
    }
    
    It 'Does not include SQL by default' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -RawSqlQueries $testQueries | Out-Null
        
        Test-Path (Join-Path $testOutDir 'data' 'queries.json') | Should -Be $false
    }
    
    It 'Includes SQL when IncludeRawSql specified' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -RawSqlQueries $testQueries -IncludeRawSql | Out-Null
        
        Test-Path (Join-Path $testOutDir 'data' 'queries.json') | Should -Be $true
    }
    
    It 'Writes queries to JSON file' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -RawSqlQueries $testQueries -IncludeRawSql | Out-Null
        
        $queriesJson = Get-Content (Join-Path $testOutDir 'data' 'queries.json') -Raw | ConvertFrom-Json
        $queriesJson[0].queryName | Should -Be 'GetNodes'
    }
}

Describe 'Select-SnapshotsForRange' {
    BeforeEach {
        $testDir = Join-Path $TestDrive 'snapshots'
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        
        # Create test snapshot directories with different dates
        1..5 | ForEach-Object {
            $snapDir = Join-Path $testDir "snap_$_"
            New-Item -ItemType Directory -Path $snapDir -Force | Out-Null
            # Set modification time
            (Get-Item $snapDir).LastWriteTime = (Get-Date).AddDays(-$_)
        }
    }
    
    It 'Returns specific paths when provided' {
        $paths = @('./custom1', './custom2')
        $result = Select-SnapshotsForRange -SnapshotDir $testDir -SnapshotPaths $paths
        
        $result | Should -Be $paths
    }
    
    It 'Returns last N snapshots when Range specified' {
        $result = Select-SnapshotsForRange -SnapshotDir $testDir -Range 3
        
        $result.Count | Should -Be 3
    }
    
    It 'Returns empty for non-existent directory' {
        $result = Select-SnapshotsForRange -SnapshotDir '/nonexistent' -Range 5
        
        $result.Count | Should -Be 0
    }
    
    It 'Filters by date range' {
        $fromDate = (Get-Date).AddDays(-4)
        $toDate = (Get-Date).AddDays(-2)
        
        $result = Select-SnapshotsForRange -SnapshotDir $testDir -FromDate $fromDate -ToDate $toDate
        
        $result.Count | Should -BeGreaterThan 0
        $result.Count | Should -BeLessOrEqual 3
    }
}

Describe 'New-TimelineEntry' {
    It 'Creates timeline entry with all properties' {
        $entry = New-TimelineEntry `
            -SnapshotId 'snap_test' `
            -Label 'Test Event' `
            -Timestamp (Get-Date) `
            -NodeCount 500 `
            -ChangeCount 25 `
            -EventType 'bulk_paste' `
            -Description 'Test description'
        
        $entry.snapshotId | Should -Be 'snap_test'
        $entry.label | Should -Be 'Test Event'
        $entry.nodeCount | Should -Be 500
        $entry.changeCount | Should -Be 25
        $entry.eventType | Should -Be 'bulk_paste'
        $entry.description | Should -Be 'Test description'
    }
    
    It 'Formats timestamp as ISO 8601' {
        $testTime = Get-Date '2026-01-15 10:30:00'
        $entry = New-TimelineEntry -SnapshotId 'test' -Label 'Test' -Timestamp $testTime -NodeCount 100
        
        $entry.timestamp | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}'
    }
    
    It 'Uses defaults for optional parameters' {
        $entry = New-TimelineEntry -SnapshotId 'minimal' -Label 'Minimal' -Timestamp (Get-Date) -NodeCount 50
        
        $entry.changeCount | Should -Be 0
        $entry.eventType | Should -Be 'snapshot'
        $entry.description | Should -Be ''
    }
}

Describe 'Bundle Integrity Tests' {
    BeforeEach {
        $testOutDir = Join-Path $TestDrive 'integrity-test'
        $testNodes = @(
            [PSCustomObject]@{
                nodeId   = 'N001'
                name     = 'IntegrityRoot'
                nodeType = 'Root'
                parentId = $null
                path     = '/IntegrityRoot'
            }
        )
        $testDiff = [PSCustomObject]@{
            summary = [PSCustomObject]@{ totalChanges = 1 }
            changes = @([PSCustomObject]@{ changeType = 'added'; nodeName = 'Test' })
        }
        $testSessions = @([PSCustomObject]@{ sessionId = 'S001'; changeCount = 1 })
        $testIntents = @([PSCustomObject]@{ intentType = 'BulkPaste'; confidence = 0.9 })
    }
    
    It 'Creates all expected data files' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes `
            -Diff $testDiff -Sessions $testSessions -Intents $testIntents | Out-Null
        
        Test-Path (Join-Path $testOutDir 'data' 'diff.json') | Should -Be $true
        Test-Path (Join-Path $testOutDir 'data' 'sessions.json') | Should -Be $true
        Test-Path (Join-Path $testOutDir 'data' 'intents.json') | Should -Be $true
    }
    
    It 'Index.html contains valid JSON data' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes -Diff $testDiff | Out-Null
        
        $indexContent = Get-Content (Join-Path $testOutDir 'index.html') -Raw
        # Should not contain the placeholder
        $indexContent | Should -Not -Match '__BUNDLE_DATA__'
        # Should contain actual JSON
        $indexContent | Should -Match '"meta"'
        $indexContent | Should -Match '"version"'
    }
    
    It 'Manifest lists bundle version' {
        Export-Bundle -OutDir $testOutDir -CurrentNodes $testNodes | Out-Null
        
        $manifest = Get-Content (Join-Path $testOutDir 'manifest.json') -Raw | ConvertFrom-Json
        $manifest.version | Should -Be '0.4.0'
    }
}
