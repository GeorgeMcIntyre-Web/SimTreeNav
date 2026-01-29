<#
.SYNOPSIS
    Pester tests for WorkflowEnrichment.ps1 - workflow-aware enrichment helpers.
#>

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot "..\..\scripts\lib\WorkflowEnrichment.ps1"
    . $script:ModulePath
}

Describe 'WorkflowEnrichment Library' {
    Context 'Get-WorkflowPhase' {
        It 'returns prefix for dotted workType' {
            Get-WorkflowPhase -WorkType 'study.layout' | Should -Be 'study'
        }

        It 'returns workType when no dot' {
            Get-WorkflowPhase -WorkType 'study' | Should -Be 'study'
        }
    }

    Context 'New-LibraryDeltaSummary' {
        It 'marks new library item as libraryAdd' {
            $snapshotComparison = @{ hasDelta = $true; previousRecord = $null }
            $newRecord = @{ metadata = @{ objectName = 'PartA' } }

            $summary = New-LibraryDeltaSummary -SnapshotComparison $snapshotComparison -NewRecord $newRecord

            $summary.kind | Should -Be 'libraryAdd'
        }

        It 'marks changed library item as libraryChange' {
            $snapshotComparison = @{ hasDelta = $true; previousRecord = [pscustomobject]@{ metadata = @{ objectName = 'Old' } } }
            $newRecord = @{ metadata = @{ objectName = 'New' } }

            $summary = New-LibraryDeltaSummary -SnapshotComparison $snapshotComparison -NewRecord $newRecord

            $summary.kind | Should -Be 'libraryChange'
            $summary.before.objectName | Should -Be 'Old'
            $summary.after.objectName | Should -Be 'New'
        }
    }

    Context 'New-AllocationDeltaSummary' {
        It 'marks allocation changes when delta is detected' {
            $snapshotComparison = @{
                hasDelta = $true
                previousRecord = @{
                    operationCounts = @{ operationCount = 2; allocationFingerprint = 'abc' }
                }
            }
            $newRecord = @{ operationCounts = @{ operationCount = 4; allocationFingerprint = 'def' } }

            $summary = New-AllocationDeltaSummary -SnapshotComparison $snapshotComparison -NewRecord $newRecord

            $summary.kind | Should -Be 'allocation'
            $summary.fields | Should -Contain 'fingerprintChanged'
            $summary.operationsAddedCount | Should -Be 2
        }
    }

    Context 'New-AllocationFingerprint' {
        It 'returns deterministic hash for same inputs' {
            $first = New-AllocationFingerprint -Station '8J-010' -OperationIds @('3','1','2') -OperationCount 3
            $second = New-AllocationFingerprint -Station '8J-010' -OperationIds @('2','3','1') -OperationCount 3

            $first | Should -Be $second
        }
    }

    Context 'Get-AllocationStabilityState' {
        It 'returns volatile when most recent fingerprint changed' {
            $state = Get-AllocationStabilityState -FingerprintHistory @('a','b')
            $state | Should -Be 'volatile'
        }

        It 'returns settling when unchanged recently but not enough history' {
            $state = Get-AllocationStabilityState -FingerprintHistory @('a','b','b')
            $state | Should -Be 'settling'
        }

        It 'returns stable when unchanged for full window' {
            $state = Get-AllocationStabilityState -FingerprintHistory @('a','a','a')
            $state | Should -Be 'stable'
        }
    }

    Context 'Get-IpaWriteSources' {
        It 'includes non-PART sources for IPA' {
            $sources = Get-IpaWriteSources -OperationCount 0
            $sources | Should -Contain 'PART_.MODIFICATIONDATE_DA_'
            $sources | Should -Not -Contain 'REL_COMMON.OBJECT_ID'
        }
    }

    Context 'New-CoordinateDeltaSummary' {
        It 'returns movement summary with delta values' {
            $newRecord = @{ coordinates = @{ x = 10; y = 5; z = 0 } }
            $prevRecord = @{ coordinates = @{ x = 0; y = 5; z = 0 } }

            $summary = New-CoordinateDeltaSummary -NewRecord $newRecord -PreviousRecord $prevRecord

            $summary.kind | Should -Be 'movement'
            $summary.delta.x | Should -Be 10
        }
    }

    Context 'New-EventEnrichment' {
        It 'omits context when no contextual fields are available' {
            $enrichment = New-EventEnrichment `
                -WorkType 'process.ipa' `
                -ObjectName 'IPA_TEST' `
                -ObjectType 'TxProcessAssembly' `
                -ObjectId '123' `
                -Category '' `
                -Item $null `
                -DeltaSummary $null `
                -SnapshotComparison $null

            $enrichment.description | Should -Match 'IPA'
            $enrichment.context | Should -BeNullOrEmpty
        }

        It 'adds context objectType when detectable' {
            $item = [pscustomobject]@{ operation_category = 'Weld Operation' }
            $enrichment = New-EventEnrichment `
                -WorkType 'study.operationAllocation' `
                -ObjectName 'PG21' `
                -ObjectType 'WeldOperation' `
                -ObjectId '456' `
                -Category '' `
                -Item $item `
                -DeltaSummary $null `
                -SnapshotComparison @{ hasDelta = $true }

            $enrichment.context.objectType | Should -Be 'weldOp'
        }
    }
}
