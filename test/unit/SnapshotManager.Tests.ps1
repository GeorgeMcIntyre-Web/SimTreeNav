<#
.SYNOPSIS
    Pester tests for SnapshotManager.ps1 - snapshot creation and diff logic.

.DESCRIPTION
    Validates:
    - Stable hashing
    - Snapshot record creation
    - Save/Read round trip
    - Snapshot comparisons (write/delta detection)
#>

BeforeAll {
    # Import the module under test
    $script:ModulePath = Join-Path $PSScriptRoot "..\..\scripts\lib\SnapshotManager.ps1"
    . $script:ModulePath

    # Temp directory for snapshot artifacts
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-snapshot-$(New-Guid)"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'SnapshotManager Library' {
    Context 'Get-StringHash' {
        It 'returns a 16 character hash for a string' {
            $hash = Get-StringHash -InputString "test-value"
            $hash.Length | Should -Be 16
        }

        It 'returns default hash for empty input' {
            $hash = Get-StringHash -InputString ""
            $hash | Should -Be "0000000000000000"
        }
    }

    Context 'New-SnapshotRecord' {
        It 'creates a record with hash and optional fields' {
            $record = New-SnapshotRecord `
                -ObjectId "100" `
                -ObjectType "StudyLayout" `
                -ModificationDate (Get-Date "2026-01-29 10:00:00") `
                -LastModifiedBy "John Smith" `
                -Coordinates @{ x = 1; y = 2; z = 3 } `
                -OperationCounts @{ weldPointCount = 12 } `
                -Metadata @{ objectName = "8J-027" }

            $record.objectId | Should -Be "100"
            $record.objectType | Should -Be "StudyLayout"
            $record.recordHash | Should -Not -BeNullOrEmpty
            $record.coordinates.x | Should -Be 1
            $record.operationCounts.weldPointCount | Should -Be 12
            $record.metadata.objectName | Should -Be "8J-027"
        }
    }

    Context 'Save-Snapshot and Read-Snapshot' {
        It 'round-trips snapshot records to disk' {
            $record = New-SnapshotRecord `
                -ObjectId "200" `
                -ObjectType "Resource" `
                -ModificationDate (Get-Date "2026-01-29 12:00:00") `
                -LastModifiedBy "Jane Doe"

            $snapshotPath = Join-Path $script:TempDir "management-snapshot-test.json"
            Save-Snapshot -SnapshotRecords @($record) -OutputPath $snapshotPath -Schema "TEST" -ProjectId "1" | Out-Null

            Test-Path $snapshotPath | Should -BeTrue

            $loaded = Read-Snapshot -SnapshotPath $snapshotPath
            $loaded.records.Count | Should -Be 1
            $loaded.records[0].objectId | Should -Be "200"
        }
    }

    Context 'Compare-Snapshots' {
        It 'returns no changes when previous snapshot is missing' {
            $record = New-SnapshotRecord -ObjectId "1" -ObjectType "Resource"
            $result = Compare-Snapshots -ObjectId "1" -NewRecord $record -PreviousSnapshot $null

            $result.hasWrite | Should -BeFalse
            $result.hasDelta | Should -BeFalse
        }

        It 'flags new object as write + delta' {
            $record = New-SnapshotRecord -ObjectId "2" -ObjectType "Resource"
            $previous = @{ records = @() }

            $result = Compare-Snapshots -ObjectId "2" -NewRecord $record -PreviousSnapshot $previous

            $result.hasWrite | Should -BeTrue
            $result.hasDelta | Should -BeTrue
        }

        It 'detects modification date change as write' {
            $previousRecord = New-SnapshotRecord `
                -ObjectId "3" `
                -ObjectType "Study" `
                -ModificationDate (Get-Date "2026-01-28 10:00:00")

            $newRecord = New-SnapshotRecord `
                -ObjectId "3" `
                -ObjectType "Study" `
                -ModificationDate (Get-Date "2026-01-29 10:00:00")

            $previous = @{ records = @($previousRecord) }

            $result = Compare-Snapshots -ObjectId "3" -NewRecord $newRecord -PreviousSnapshot $previous

            $result.hasWrite | Should -BeTrue
            $result.hasDelta | Should -BeFalse
        }

        It 'detects coordinate delta above epsilon' {
            $previousRecord = New-SnapshotRecord `
                -ObjectId "4" `
                -ObjectType "StudyLayout" `
                -Coordinates @{ x = 0; y = 0; z = 0 }

            $newRecord = New-SnapshotRecord `
                -ObjectId "4" `
                -ObjectType "StudyLayout" `
                -Coordinates @{ x = 0; y = 0; z = 2 }

            $previous = @{ records = @($previousRecord) }

            $result = Compare-Snapshots -ObjectId "4" -NewRecord $newRecord -PreviousSnapshot $previous -CoordinateEpsilon 1.0

            $result.hasDelta | Should -BeTrue
        }

        It 'ignores coordinate delta below epsilon' {
            $previousRecord = New-SnapshotRecord `
                -ObjectId "5" `
                -ObjectType "StudyLayout" `
                -Coordinates @{ x = 0; y = 0; z = 0 }

            $newRecord = New-SnapshotRecord `
                -ObjectId "5" `
                -ObjectType "StudyLayout" `
                -Coordinates @{ x = 0; y = 0; z = 0.5 }

            $previous = @{ records = @($previousRecord) }

            $result = Compare-Snapshots -ObjectId "5" -NewRecord $newRecord -PreviousSnapshot $previous -CoordinateEpsilon 1.0

            $result.hasDelta | Should -BeFalse
        }

        It 'handles PSCustomObject operationCounts without throwing' {
            $previousRecord = New-SnapshotRecord `
                -ObjectId "6" `
                -ObjectType "Operation" `
                -OperationCounts @{ weldPointCount = 10 }

            $newRecord = New-SnapshotRecord `
                -ObjectId "6" `
                -ObjectType "Operation" `
                -OperationCounts @{ weldPointCount = 12 }

            $previous = @{
                records = @(
                    [PSCustomObject]@{
                        objectId = $previousRecord.objectId
                        objectType = $previousRecord.objectType
                        modificationDate = $previousRecord.modificationDate
                        lastModifiedBy = $previousRecord.lastModifiedBy
                        operationCounts = [PSCustomObject]@{ weldPointCount = 10 }
                        recordHash = $previousRecord.recordHash
                    }
                )
            }

            $result = Compare-Snapshots -ObjectId "6" -NewRecord $newRecord -PreviousSnapshot $previous

            $result.hasDelta | Should -BeTrue
        }
    }
}
