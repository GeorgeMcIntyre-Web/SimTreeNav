<#
.SYNOPSIS
    Pester tests for RunStatus.ps1 library with code coverage.

.DESCRIPTION
    Unit tests using Pester framework to verify:
    - New-RunStatus creates valid run-status.json
    - Set-RunStatusStep adds and updates steps correctly
    - Complete-RunStatus finalizes with proper fields
    - Duration calculations work correctly
    - Error handling functions as expected
#>

BeforeAll {
    # Import the module under test
    $script:ModulePath = Join-Path $PSScriptRoot "..\..\scripts\lib\RunStatus.ps1"
    . $script:ModulePath

    # Create temp directory for test artifacts
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-runstatus-$(New-Guid)"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    # Cleanup temp directory
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'RunStatus Library' {
    BeforeEach {
        # Clean up any leftover files from previous tests
        Get-ChildItem -Path $script:TempDir -Filter "*.json" | Remove-Item -Force -ErrorAction SilentlyContinue
    }

    Context 'New-RunStatus' {
        It 'creates run-status.json file' {
            $statusPath = New-RunStatus -OutDir $script:TempDir -ScriptName "test-script.ps1"

            Test-Path $statusPath | Should -BeTrue
            $statusPath | Should -Match 'run-status\.json$'
        }

        It 'creates valid JSON with required schema fields' {
            $statusPath = New-RunStatus -OutDir $script:TempDir -ScriptName "test-script.ps1" -SchemaVersion "1.0.0"

            $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json

            # Verify all required fields exist
            $status.schemaVersion | Should -Be "1.0.0"
            $status.scriptName | Should -Be "test-script.ps1"
            $status.startedAt | Should -Not -BeNullOrEmpty
            $status.host | Should -Not -BeNull
            $status.host.machineName | Should -Not -BeNullOrEmpty
            $status.steps | Should -Not -BeNull
            $status.durations | Should -Not -BeNull
            $status.status | Should -Not -BeNull
            $status.exitCode | Should -Not -BeNull
            $status.PSObject.Properties['topError'] | Should -Not -BeNull
            $status.PSObject.Properties['logFile'] | Should -Not -BeNull
            $status.PSObject.Properties['completedAt'] | Should -Not -BeNull
        }

        It 'initializes with empty steps array' {
            $statusPath = New-RunStatus -OutDir $script:TempDir -ScriptName "test.ps1"

            $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
            $status.steps | Should -BeOfType [System.Array]
            $status.steps.Count | Should -Be 0
        }

        It 'sets initial status to null' {
            $statusPath = New-RunStatus -OutDir $script:TempDir -ScriptName "test.ps1"

            $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json
            $status.status | Should -BeNullOrEmpty
        }
    }

    Context 'Set-RunStatusStep' {
        BeforeEach {
            $script:statusPath = New-RunStatus -OutDir $script:TempDir -ScriptName "test.ps1"
        }

        It 'adds a new step with running status' {
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "TestStep1" -Status "running"

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json
            $step = $status.steps | Where-Object { $_.name -eq "TestStep1" }

            $step | Should -Not -BeNull
            $step.status | Should -Be "running"
            $step.startedAt | Should -Not -BeNullOrEmpty
        }

        It 'updates existing step to completed with duration' {
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "TestStep1" -Status "running"
            Start-Sleep -Milliseconds 50  # Ensure duration > 0
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "TestStep1" -Status "completed"

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json
            $step = $status.steps | Where-Object { $_.name -eq "TestStep1" }

            $step.status | Should -Be "completed"
            $step.completedAt | Should -Not -BeNullOrEmpty
            $step.durationMs | Should -BeGreaterThan 0
        }

        It 'adds duration to durations map' {
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "TestStep1" -Status "running"
            Start-Sleep -Milliseconds 50
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "TestStep1" -Status "completed"

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json

            $status.durations.testStep1Ms | Should -BeGreaterThan 0
        }

        It 'handles step with error message' {
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "FailedStep" -Status "failed" -Error "Test error message"

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json
            $step = $status.steps | Where-Object { $_.name -eq "FailedStep" }

            $step | Should -Not -BeNull
            $step.status | Should -Be "failed"
            $step.error | Should -Be "Test error message"
        }

        It 'supports multiple steps' {
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "Step1" -Status "completed"
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "Step2" -Status "running"
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "Step3" -Status "pending"

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json

            $status.steps.Count | Should -Be 3
            ($status.steps | Where-Object { $_.name -eq "Step1" }).status | Should -Be "completed"
            ($status.steps | Where-Object { $_.name -eq "Step2" }).status | Should -Be "running"
            ($status.steps | Where-Object { $_.name -eq "Step3" }).status | Should -Be "pending"
        }
    }

    Context 'Complete-RunStatus' {
        BeforeEach {
            $script:statusPath = New-RunStatus -OutDir $script:TempDir -ScriptName "test.ps1"
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "Step1" -Status "running"
            Start-Sleep -Milliseconds 50
            Set-RunStatusStep -StatusPath $script:statusPath -StepName "Step1" -Status "completed"
        }

        It 'finalizes status to success' {
            Complete-RunStatus -StatusPath $script:statusPath -Status "success" -ExitCode 0

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json

            $status.status | Should -Be "success"
            $status.exitCode | Should -Be 0
        }

        It 'finalizes status to failed with error' {
            Complete-RunStatus -StatusPath $script:statusPath -Status "failed" -ExitCode 1 -TopError "Test failure"

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json

            $status.status | Should -Be "failed"
            $status.exitCode | Should -Be 1
            $status.topError | Should -Be "Test failure"
        }

        It 'sets completedAt timestamp' {
            Complete-RunStatus -StatusPath $script:statusPath -Status "success" -ExitCode 0

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json

            $status.completedAt | Should -Not -BeNullOrEmpty
        }

        It 'calculates total duration' {
            Complete-RunStatus -StatusPath $script:statusPath -Status "success" -ExitCode 0

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json

            $status.durations.totalMs | Should -BeGreaterThan 0
        }

        It 'sets log file path when provided' {
            Complete-RunStatus -StatusPath $script:statusPath -Status "success" -ExitCode 0 -LogFile "test.log"

            $status = Get-Content -Path $script:statusPath -Raw | ConvertFrom-Json

            $status.logFile | Should -Be "test.log"
        }
    }

    Context 'Integration Workflow' {
        It 'handles complete workflow from creation to completion' {
            # Create new status
            $statusPath = New-RunStatus -OutDir $script:TempDir -ScriptName "workflow-test.ps1"

            # Add multiple steps
            Set-RunStatusStep -StatusPath $statusPath -StepName "Initialize" -Status "running"
            Start-Sleep -Milliseconds 20
            Set-RunStatusStep -StatusPath $statusPath -StepName "Initialize" -Status "completed"

            Set-RunStatusStep -StatusPath $statusPath -StepName "Process" -Status "running"
            Start-Sleep -Milliseconds 30
            Set-RunStatusStep -StatusPath $statusPath -StepName "Process" -Status "completed"

            Set-RunStatusStep -StatusPath $statusPath -StepName "Finalize" -Status "running"
            Start-Sleep -Milliseconds 10
            Set-RunStatusStep -StatusPath $statusPath -StepName "Finalize" -Status "completed"

            # Complete the run
            Complete-RunStatus -StatusPath $statusPath -Status "success" -ExitCode 0 -LogFile "workflow.log"

            # Verify final state
            $status = Get-Content -Path $statusPath -Raw | ConvertFrom-Json

            $status.scriptName | Should -Be "workflow-test.ps1"
            $status.steps.Count | Should -Be 3
            $status.status | Should -Be "success"
            $status.exitCode | Should -Be 0
            $status.logFile | Should -Be "workflow.log"
            $status.completedAt | Should -Not -BeNullOrEmpty
            $status.durations.totalMs | Should -BeGreaterThan 0

            # Verify all steps completed
            $status.steps | ForEach-Object {
                $_.status | Should -Be "completed"
                $_.durationMs | Should -BeGreaterThan 0
            }
        }
    }
}
