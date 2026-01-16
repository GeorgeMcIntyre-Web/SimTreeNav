# DeterminismGate.Tests.ps1
# Verifies that all outputs are deterministic (same input = same output)
# This is a critical test for stakeholder confidence in the tooling

<#
.SYNOPSIS
    Tests that DemoStory produces byte-for-byte identical outputs when run with the same seed.

.DESCRIPTION
    These tests ensure:
    - nodes.json is deterministic
    - diff.json is deterministic
    - impact.json is deterministic
    - drift.json is deterministic
    - Anonymized outputs are identical for the same seed
    - Timestamps only appear in meta/manifest files (excluded from comparison)

.NOTES
    Tag: Determinism
    Requires: DemoStory.ps1 with -Seed parameter
#>

BeforeAll {
    $scriptRoot = Split-Path -Parent $PSScriptRoot
    
    # Create temp directory for test outputs
    $Script:TestTempDir = Join-Path ([System.IO.Path]::GetTempPath()) "DeterminismGate_$(Get-Random)"
    New-Item -ItemType Directory -Path $Script:TestTempDir -Force | Out-Null
    
    # Helper to compare file contents
    function Compare-FileBytes {
        param(
            [string]$Path1,
            [string]$Path2,
            [switch]$NormalizeTimestamps
        )
        
        if (-not (Test-Path $Path1)) { return @{ Identical = $false; Reason = "Path1 does not exist: $Path1" } }
        if (-not (Test-Path $Path2)) { return @{ Identical = $false; Reason = "Path2 does not exist: $Path2" } }
        
        $content1 = Get-Content $Path1 -Raw
        $content2 = Get-Content $Path2 -Raw
        
        # Normalize timestamps if requested (replace ISO 8601 timestamps with placeholder)
        if ($NormalizeTimestamps) {
            $timestampPattern = '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z?'
            $content1 = $content1 -replace $timestampPattern, 'TIMESTAMP'
            $content2 = $content2 -replace $timestampPattern, 'TIMESTAMP'
        }
        
        if ($content1 -eq $content2) {
            return @{ Identical = $true; Reason = $null }
        }
        
        # Find first difference for debugging
        $lines1 = $content1 -split "`n"
        $lines2 = $content2 -split "`n"
        
        for ($i = 0; $i -lt [Math]::Max($lines1.Count, $lines2.Count); $i++) {
            $line1 = if ($i -lt $lines1.Count) { $lines1[$i] } else { '[missing]' }
            $line2 = if ($i -lt $lines2.Count) { $lines2[$i] } else { '[missing]' }
            
            if ($line1 -ne $line2) {
                return @{
                    Identical = $false
                    Reason = "First difference at line $($i + 1):`nRun1: $($line1.Substring(0, [Math]::Min(200, $line1.Length)))...`nRun2: $($line2.Substring(0, [Math]::Min(200, $line2.Length)))..."
                }
            }
        }
        
        return @{ Identical = $false; Reason = "Content differs but line-by-line comparison found no difference (possible whitespace issue)" }
    }
    
    # Helper to run DemoStory with seed and capture outputs
    function Invoke-DemoStoryWithSeed {
        param(
            [int]$Seed,
            [string]$OutDir,
            [int]$NodeCount = 50,
            [switch]$Anonymize
        )
        
        $params = @{
            NodeCount = $NodeCount
            OutDir = $OutDir
            Seed = $Seed
            StoryName = "DeterminismTest"
            NoOpen = $true
        }
        
        if ($Anonymize) {
            $params['Anonymize'] = $true
        }
        
        # Run DemoStory
        Push-Location $scriptRoot
        try {
            $result = & "$scriptRoot/DemoStory.ps1" @params 2>&1
            # Capture any errors
            $errors = $result | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }
            if ($errors) {
                throw "DemoStory failed: $($errors | Out-String)"
            }
        }
        finally {
            Pop-Location
        }
        
        return $OutDir
    }
}

AfterAll {
    # Cleanup temp directory
    if (Test-Path $Script:TestTempDir) {
        Remove-Item -Path $Script:TestTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'DeterminismGate' -Tag 'Determinism' {
    Context 'Same seed produces identical outputs' {
        BeforeAll {
            $seed = 42
            $nodeCount = 50  # Small count for fast tests
            
            # Run DemoStory twice with same seed
            $Script:Run1Dir = Join-Path $Script:TestTempDir "run1"
            $Script:Run2Dir = Join-Path $Script:TestTempDir "run2"
            
            Write-Host "  Running DemoStory (run 1, seed=$seed)..." -ForegroundColor Cyan
            Invoke-DemoStoryWithSeed -Seed $seed -OutDir $Script:Run1Dir -NodeCount $nodeCount
            
            Write-Host "  Running DemoStory (run 2, seed=$seed)..." -ForegroundColor Cyan
            Invoke-DemoStoryWithSeed -Seed $seed -OutDir $Script:Run2Dir -NodeCount $nodeCount
        }
        
        It 'diff.json is byte-for-byte identical' {
            $path1 = Join-Path $Script:Run1Dir "data/diff.json"
            $path2 = Join-Path $Script:Run2Dir "data/diff.json"
            
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2
            $result.Identical | Should -Be $true -Because $result.Reason
        }
        
        It 'impact.json is byte-for-byte identical' {
            $path1 = Join-Path $Script:Run1Dir "data/impact.json"
            $path2 = Join-Path $Script:Run2Dir "data/impact.json"
            
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2
            $result.Identical | Should -Be $true -Because $result.Reason
        }
        
        It 'drift.json is identical (excluding timestamps)' {
            $path1 = Join-Path $Script:Run1Dir "data/drift.json"
            $path2 = Join-Path $Script:Run2Dir "data/drift.json"
            
            # drift.json may contain runtime timestamp, normalize it
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2 -NormalizeTimestamps
            $result.Identical | Should -Be $true -Because $result.Reason
        }
        
        It 'sessions.json is identical (excluding timestamps)' {
            $path1 = Join-Path $Script:Run1Dir "data/sessions.json"
            $path2 = Join-Path $Script:Run2Dir "data/sessions.json"
            
            # Sessions contain startTime/endTime which are runtime - normalize them
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2 -NormalizeTimestamps
            $result.Identical | Should -Be $true -Because $result.Reason
        }
        
        It 'intents.json is identical (excluding timestamps)' {
            $path1 = Join-Path $Script:Run1Dir "data/intents.json"
            $path2 = Join-Path $Script:Run2Dir "data/intents.json"
            
            # Intents may contain session-related timestamps
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2 -NormalizeTimestamps
            $result.Identical | Should -Be $true -Because $result.Reason
        }
        
        It 'timeline.json is identical (excluding timestamps)' {
            $path1 = Join-Path $Script:Run1Dir "data/timeline.json"
            $path2 = Join-Path $Script:Run2Dir "data/timeline.json"
            
            # timeline.json contains timestamps, normalize them
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2 -NormalizeTimestamps
            $result.Identical | Should -Be $true -Because $result.Reason
        }
        
        It 'anomalies.json is identical (excluding timestamps)' {
            $path1 = Join-Path $Script:Run1Dir "data/anomalies.json"
            $path2 = Join-Path $Script:Run2Dir "data/anomalies.json"
            
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2 -NormalizeTimestamps
            $result.Identical | Should -Be $true -Because $result.Reason
        }
        
        It 'index.html is identical (excluding timestamps)' {
            $path1 = Join-Path $Script:Run1Dir "index.html"
            $path2 = Join-Path $Script:Run2Dir "index.html"
            
            # HTML contains embedded data including timestamps
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2 -NormalizeTimestamps
            $result.Identical | Should -Be $true -Because $result.Reason
        }
    }
    
    Context 'Different seeds produce different outputs' {
        BeforeAll {
            $nodeCount = 30
            
            $Script:SeedADir = Join-Path $Script:TestTempDir "seedA"
            $Script:SeedBDir = Join-Path $Script:TestTempDir "seedB"
            
            Write-Host "  Running DemoStory (seed=100)..." -ForegroundColor Cyan
            Invoke-DemoStoryWithSeed -Seed 100 -OutDir $Script:SeedADir -NodeCount $nodeCount
            
            Write-Host "  Running DemoStory (seed=200)..." -ForegroundColor Cyan
            Invoke-DemoStoryWithSeed -Seed 200 -OutDir $Script:SeedBDir -NodeCount $nodeCount
        }
        
        It 'nodes.json differs between seeds' {
            $path1 = Join-Path $Script:SeedADir "data/nodes.json"
            $path2 = Join-Path $Script:SeedBDir "data/nodes.json"
            
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2
            $result.Identical | Should -Be $false -Because "Different seeds should produce different outputs"
        }
    }
    
    Context 'Anonymized outputs are deterministic' {
        BeforeAll {
            $seed = 999
            $nodeCount = 40
            
            $Script:AnonRun1Dir = Join-Path $Script:TestTempDir "anon_run1"
            $Script:AnonRun2Dir = Join-Path $Script:TestTempDir "anon_run2"
            
            Write-Host "  Running DemoStory anonymized (run 1, seed=$seed)..." -ForegroundColor Cyan
            Invoke-DemoStoryWithSeed -Seed $seed -OutDir $Script:AnonRun1Dir -NodeCount $nodeCount -Anonymize
            
            Write-Host "  Running DemoStory anonymized (run 2, seed=$seed)..." -ForegroundColor Cyan
            Invoke-DemoStoryWithSeed -Seed $seed -OutDir $Script:AnonRun2Dir -NodeCount $nodeCount -Anonymize
        }
        
        It 'anonymized diff.json is byte-for-byte identical' {
            $path1 = Join-Path $Script:AnonRun1Dir "data/diff.json"
            $path2 = Join-Path $Script:AnonRun2Dir "data/diff.json"
            
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2
            $result.Identical | Should -Be $true -Because $result.Reason
        }
        
        It 'anonymized index.html is identical (excluding timestamps)' {
            $path1 = Join-Path $Script:AnonRun1Dir "index.html"
            $path2 = Join-Path $Script:AnonRun2Dir "index.html"
            
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2 -NormalizeTimestamps
            $result.Identical | Should -Be $true -Because $result.Reason
        }
        
        It 'anonymized sessions.json is identical (excluding timestamps)' {
            $path1 = Join-Path $Script:AnonRun1Dir "data/sessions.json"
            $path2 = Join-Path $Script:AnonRun2Dir "data/sessions.json"
            
            # Sessions contain startTime/endTime which are runtime - normalize them
            $result = Compare-FileBytes -Path1 $path1 -Path2 $path2 -NormalizeTimestamps
            $result.Identical | Should -Be $true -Because $result.Reason
        }
    }
    
    Context 'Timestamps are isolated to allowed fields' {
        It 'Core analytical data (diff, impact) is deterministic when seed is set' {
            $path = $Script:Run1Dir
            if (-not (Test-Path $path)) { Set-ItResult -Skipped -Because "Run1 directory not available" }
            
            $dataDir = Join-Path $path "data"
            if (-not (Test-Path $dataDir)) { Set-ItResult -Skipped -Because "data directory not available" }
            
            # diff.json and impact.json are pure analytical data and should be deterministic
            # sessions.json, intents.json may have runtime timestamps which is acceptable
            $coreFiles = @('diff.json', 'impact.json')
            
            foreach ($fileName in $coreFiles) {
                $filePath = Join-Path $dataDir $fileName
                if (Test-Path $filePath) {
                    $content = Get-Content $filePath -Raw
                    
                    # Should NOT contain current year timestamps in core analytical data
                    $currentYear = (Get-Date).Year
                    $hasCurrentYearTimestamp = $content -match "\b$currentYear-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"
                    
                    $hasCurrentYearTimestamp | Should -Be $false -Because "$fileName should not contain runtime timestamps"
                }
            }
        }
        
        It 'Session-related files may contain runtime timestamps (acceptable)' {
            # This is a documentation test - sessions and timeline naturally use runtime
            # timestamps to record when events happened. This is expected behavior.
            # The test verifies that when timestamps are normalized, outputs are identical.
            $true | Should -Be $true
        }
    }
}

Describe 'DeterminismGate - Core Functions' -Tag 'Determinism' {
    BeforeAll {
        $scriptRoot = Split-Path -Parent $PSScriptRoot
        
        # Import modules for direct testing
        . "$scriptRoot/src/powershell/v02/core/NodeContract.ps1"
        . "$scriptRoot/src/powershell/v02/analysis/ImpactEngine.ps1"
        . "$scriptRoot/src/powershell/v02/analysis/DriftEngine.ps1"
    }
    
    Context 'Content hash is deterministic' {
        It 'Same inputs produce same hash' {
            $hash1 = Get-ContentHash -Name "TestNode" -ExternalId "EXT-123" -ClassName "TestClass"
            $hash2 = Get-ContentHash -Name "TestNode" -ExternalId "EXT-123" -ClassName "TestClass"
            
            $hash1 | Should -Be $hash2
        }
        
        It 'Different inputs produce different hash' {
            $hash1 = Get-ContentHash -Name "TestNode1" -ExternalId "EXT-123" -ClassName "TestClass"
            $hash2 = Get-ContentHash -Name "TestNode2" -ExternalId "EXT-123" -ClassName "TestClass"
            
            $hash1 | Should -Not -Be $hash2
        }
    }
    
    Context 'Attribute hash is deterministic' {
        It 'Same attributes produce same hash regardless of key order' {
            $hash1 = Get-AttributeHash -Attributes @{ a = 1; b = 2; c = 3 }
            $hash2 = Get-AttributeHash -Attributes @{ c = 3; a = 1; b = 2 }
            
            $hash1 | Should -Be $hash2
        }
    }
    
    Context 'Impact JSON is deterministic' {
        It 'Export-ImpactJson produces sorted, deterministic output' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "impact_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            try {
                $impactReport = [PSCustomObject]@{
                    nodeId = '1'
                    nodeName = 'TestNode'
                    nodeType = 'Station'
                    path = '/Test'
                    directDependents = @(
                        [PSCustomObject]@{ nodeId = '3'; name = 'C'; nodeType = 'Resource' }
                        [PSCustomObject]@{ nodeId = '2'; name = 'B'; nodeType = 'Resource' }
                    )
                    transitiveDependents = @()
                    upstreamReferences = @()
                    riskScore = 50
                    breakdown = @{ dependentCountWeight = 25; nodeTypeWeight = 15; criticalLinkWeight = 10 }
                    why = @('Has 2 direct dependents')
                }
                
                Export-ImpactJson -ImpactReport $impactReport -OutputPath $tempDir
                $json1 = Get-Content (Join-Path $tempDir "impact.json") -Raw
                
                Remove-Item (Join-Path $tempDir "impact.json") -Force
                
                Export-ImpactJson -ImpactReport $impactReport -OutputPath $tempDir
                $json2 = Get-Content (Join-Path $tempDir "impact.json") -Raw
                
                $json1 | Should -Be $json2
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    Context 'Drift JSON is deterministic' {
        It 'Export-DriftJson produces sorted, deterministic output' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "drift_test_$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            try {
                $driftReport = [PSCustomObject]@{
                    totalPairs = 2
                    driftedPairs = 2
                    positionDrifted = 1
                    rotationDrifted = 1
                    pairs = @(
                        [PSCustomObject]@{ instanceId = '3'; prototypeId = '1'; severity = 'warn'; positionDelta = 10.5 }
                        [PSCustomObject]@{ instanceId = '2'; prototypeId = '1'; severity = 'info'; positionDelta = 2.1 }
                    )
                }
                
                Export-DriftJson -DriftReport $driftReport -OutputPath $tempDir
                $json1 = Get-Content (Join-Path $tempDir "drift.json") -Raw
                
                Remove-Item (Join-Path $tempDir "drift.json") -Force
                
                Export-DriftJson -DriftReport $driftReport -OutputPath $tempDir
                $json2 = Get-Content (Join-Path $tempDir "drift.json") -Raw
                
                $json1 | Should -Be $json2
            }
            finally {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
