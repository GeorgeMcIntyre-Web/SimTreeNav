<#
.SYNOPSIS
    Pester tests for EvidenceClassifier.ps1 - Evidence-based work classification.

.DESCRIPTION
    Tests all classification logic including:
    - Attribution strength calculation
    - Confidence classification matrix
    - Evidence block creation
    - Evidence quality validation
#>

BeforeAll {
    # Import the module under test
    $script:ModulePath = Join-Path $PSScriptRoot "..\..\scripts\lib\EvidenceClassifier.ps1"
    . $script:ModulePath
}

Describe 'EvidenceClassifier Library' {
    Context 'Workflow workType taxonomy' {
        It 'returns allowed taxonomy values' {
            $types = Get-WorkflowWorkTypeList
            $types | Should -Not -BeNullOrEmpty
            $types | Should -Contain 'study.layout'
            $types | Should -Contain 'process.ipa'
        }

        It 'validates allowed workType values' {
            Test-WorkTypeAllowed -WorkType 'resources.resourceLibrary' | Should -BeTrue
            Test-WorkTypeAllowed -WorkType 'unknown.type' | Should -BeFalse
        }

        It 'maps legacy workType values to workflow taxonomy' {
            $mapped = Normalize-WorkType -WorkType 'Project Database'
            $mapped | Should -Be 'process.ipa'
        }

        It 'maps part library items with MFG object types to mfgLibrary' {
            $mapped = Normalize-WorkType -WorkType 'PART_LIBRARY' -ObjectType 'ManufacturingFeature'
            $mapped | Should -Be 'libraries.mfgLibrary'
        }

        It 'returns null for unknown workType values' {
            $mapped = Normalize-WorkType -WorkType 'LegacyUnknown'
            $mapped | Should -BeNullOrEmpty
        }
    }

    Context 'Get-AttributionStrength' {
        It 'returns "strong" when proxyOwner matches lastModifiedBy' {
            $strength = Get-AttributionStrength `
                -ProxyOwnerName "John Smith" `
                -LastModifiedBy "John Smith"

            $strength | Should -Be "strong"
        }

        It 'returns "strong" when proxyOwner matches lastModifiedBy with aligned timestamps' {
            $checkoutTime = Get-Date "2026-01-29 10:00:00"
            $modTime = Get-Date "2026-01-29 10:05:00"

            $strength = Get-AttributionStrength `
                -ProxyOwnerName "John Smith" `
                -LastModifiedBy "John Smith" `
                -CheckoutTimestamp $checkoutTime `
                -ModificationTimestamp $modTime

            $strength | Should -Be "strong"
        }

        It 'returns "medium" when proxyOwner and lastModifiedBy differ' {
            $strength = Get-AttributionStrength `
                -ProxyOwnerName "John Smith" `
                -LastModifiedBy "Jane Doe"

            $strength | Should -Be "medium"
        }

        It 'returns "medium" when only proxyOwner is present' {
            $strength = Get-AttributionStrength `
                -ProxyOwnerName "John Smith" `
                -LastModifiedBy ""

            $strength | Should -Be "medium"
        }

        It 'returns "medium" when only lastModifiedBy is present' {
            $strength = Get-AttributionStrength `
                -ProxyOwnerName "" `
                -LastModifiedBy "Jane Doe"

            $strength | Should -Be "medium"
        }

        It 'returns "weak" when both fields are empty' {
            $strength = Get-AttributionStrength `
                -ProxyOwnerName "" `
                -LastModifiedBy ""

            $strength | Should -Be "weak"
        }

        It 'returns "weak" when both fields are null' {
            $strength = Get-AttributionStrength `
                -ProxyOwnerName $null `
                -LastModifiedBy $null

            $strength | Should -Be "weak"
        }
    }

    Context 'Get-Confidence - Classification Matrix' {
        It 'returns "confirmed" when hasCheckout + hasWrite + hasDelta (gold standard)' {
            $confidence = Get-Confidence `
                -HasCheckout $true `
                -HasWrite $true `
                -HasDelta $true `
                -AttributionStrength "strong"

            $confidence | Should -Be "confirmed"
        }

        It 'returns "confirmed" even with medium attribution if all flags true' {
            $confidence = Get-Confidence `
                -HasCheckout $true `
                -HasWrite $true `
                -HasDelta $true `
                -AttributionStrength "medium"

            $confidence | Should -Be "confirmed"
        }

        It 'returns "likely" when hasWrite + hasDelta but no checkout' {
            $confidence = Get-Confidence `
                -HasCheckout $false `
                -HasWrite $true `
                -HasDelta $true `
                -AttributionStrength "medium"

            $confidence | Should -Be "likely"
        }

        It 'returns "likely" when all flags true but weak attribution' {
            $confidence = Get-Confidence `
                -HasCheckout $true `
                -HasWrite $true `
                -HasDelta $true `
                -AttributionStrength "weak"

            $confidence | Should -Be "likely"
        }

        It 'returns "checkout_only" when hasCheckout but no write or delta' {
            $confidence = Get-Confidence `
                -HasCheckout $true `
                -HasWrite $false `
                -HasDelta $false `
                -AttributionStrength "strong"

            $confidence | Should -Be "checkout_only"
        }

        It 'returns "likely" when hasWrite + hasDelta but weak attribution' {
            $confidence = Get-Confidence `
                -HasCheckout $false `
                -HasWrite $true `
                -HasDelta $true `
                -AttributionStrength "weak"

            $confidence | Should -Be "likely"
        }

        It 'returns "unattributed" when only hasWrite with weak attribution' {
            $confidence = Get-Confidence `
                -HasCheckout $false `
                -HasWrite $true `
                -HasDelta $false `
                -AttributionStrength "weak"

            $confidence | Should -Be "unattributed"
        }

        It 'returns "unattributed" when all flags false' {
            $confidence = Get-Confidence `
                -HasCheckout $false `
                -HasWrite $false `
                -HasDelta $false `
                -AttributionStrength "weak"

            $confidence | Should -Be "unattributed"
        }
    }

    Context 'WriteSources validation' {
        It 'flags invalid writeSources entries' {
            $violations = Get-WriteSourceViolations -WriteSources @(
                'REL_COMMON.OBJECT_ID',
                'OPERATION_.ID',
                'SOME_TABLE.PUID'
            )

            $violations.Count | Should -Be 3
        }

        It 'accepts mod date writeSources entries' {
            Test-WriteSourcesValid -WriteSources @('OPERATION_.MODIFICATIONDATE_DA_') | Should -BeTrue
        }

        It 'allows joinSources to include OBJECT_ID' {
            $joinSources = @('REL_COMMON.OBJECT_ID', 'OPERATION_.OBJECT_ID')
            $joinSources | Should -Contain 'REL_COMMON.OBJECT_ID'
        }

        It 'requires valid writeSources when hasWrite is true' {
            $evidence = @{
                hasWrite = $true
                writeSources = @('PART_.MODIFICATIONDATE_DA_')
            }

            Test-EvidenceWriteSources -Evidence $evidence | Should -BeTrue
        }
    }
    Context 'Get-Confidence - Full Matrix' {
        It 'matches the confidence matrix for all combinations' {
            $strengths = @("strong", "medium", "weak")
            $bools = @($false, $true)

            foreach ($hasCheckout in $bools) {
                foreach ($hasWrite in $bools) {
                    foreach ($hasDelta in $bools) {
                        foreach ($strength in $strengths) {
                            $expected = "unattributed"
                            if ($hasCheckout -and $hasWrite -and $hasDelta -and $strength -ne "weak") {
                                $expected = "confirmed"
                            } elseif ($hasWrite -and $hasDelta) {
                                $expected = "likely"
                            } elseif ($hasCheckout -and -not $hasWrite -and -not $hasDelta) {
                                $expected = "checkout_only"
                            }

                            $actual = Get-Confidence `
                                -HasCheckout $hasCheckout `
                                -HasWrite $hasWrite `
                                -HasDelta $hasDelta `
                                -AttributionStrength $strength

                            $actual | Should -Be $expected
                        }
                    }
                }
            }
        }
    }

    Context 'New-EvidenceBlock - Basic Creation' {
        It 'creates evidence block with all required fields' {
            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -ProxyOwnerId "100" `
                -ProxyOwnerName "John Smith" `
                -LastModifiedBy "John Smith" `
                -CheckoutWorkingVersionId 5 `
                -ModificationDate (Get-Date "2026-01-29 10:00:00") `
                -WriteSources @("ROBCADSTUDY_.MODIFICATIONDATE_DA_")

            $evidence | Should -Not -BeNullOrEmpty
            $evidence.hasCheckout | Should -Be $true
            $evidence.hasWrite | Should -Be $true
            $evidence.hasDelta | Should -Be $false
            $evidence.attributionStrength | Should -Be "strong"
            $evidence.confidence | Should -Be "unattributed"
            $evidence.proxyOwnerId | Should -Be "100"
            $evidence.proxyOwnerName | Should -Be "John Smith"
            $evidence.lastModifiedBy | Should -Be "John Smith"
        }

        It 'creates evidence block with minimal fields' {
            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study"

            $evidence | Should -Not -BeNullOrEmpty
            $evidence.hasCheckout | Should -Be $false
            $evidence.hasWrite | Should -Be $false
            $evidence.hasDelta | Should -Be $false
            $evidence.confidence | Should -Be "unattributed"
        }

        It 'includes writeSources when provided' {
            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -WriteSources @("OPERATION_.MODIFICATIONDATE_DA_", "VEC_LOCATION_.DATA")

            $evidence.writeSources | Should -Not -BeNullOrEmpty
            $evidence.writeSources.Count | Should -Be 2
            $evidence.writeSources[0] | Should -Be "OPERATION_.MODIFICATIONDATE_DA_"
        }

        It 'includes deltaSummary when provided' {
            $deltaSummary = @{
                kind = "movement"
                fields = @("x", "y", "z")
                maxAbsDelta = 1250.5
                before = @{ x = 5000; y = 3200; z = 1500 }
                after = @{ x = 6250; y = 3200; z = 1500 }
            }

            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Resource" `
                -DeltaSummary $deltaSummary

            $evidence.deltaSummary | Should -Not -BeNullOrEmpty
            $evidence.deltaSummary.kind | Should -Be "movement"
            $evidence.deltaSummary.maxAbsDelta | Should -Be 1250.5
            $evidence.hasDelta | Should -Be $true
        }

        It 'includes snapshotComparison when provided' {
            $snapshotComp = @{
                hasWrite = $true
                hasDelta = $true
                changes = @("Coordinates changed: max delta = 1250mm")
            }

            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -SnapshotComparison $snapshotComp

            $evidence.hasWrite | Should -Be $true
            $evidence.hasDelta | Should -Be $true
            $evidence.snapshotComparison | Should -Not -BeNullOrEmpty
        }

        It 'respects snapshotComparison flags when writeSources are empty' {
            $snapshotComp = @{
                hasWrite = $false
                hasDelta = $false
                changes = @()
            }

            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -SnapshotComparison $snapshotComp

            $evidence.hasWrite | Should -Be $false
            $evidence.hasDelta | Should -Be $false
        }
    }

    Context 'New-EvidenceBlock - Confidence Classification Integration' {
        It 'classifies as "confirmed" for checkout + write + delta' {
            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -ProxyOwnerName "John Smith" `
                -LastModifiedBy "John Smith" `
                -CheckoutWorkingVersionId 5 `
                -WriteSources @("ROBCADSTUDY_.MODIFICATIONDATE_DA_") `
                -DeltaSummary @{ kind = "movement"; maxAbsDelta = 1250 }

            $evidence.confidence | Should -Be "confirmed"
            $evidence.hasCheckout | Should -Be $true
            $evidence.hasWrite | Should -Be $true
            $evidence.hasDelta | Should -Be $true
        }

        It 'classifies as "checkout_only" for checkout without changes' {
            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -ProxyOwnerName "John Smith" `
                -CheckoutWorkingVersionId 5

            $evidence.confidence | Should -Be "checkout_only"
            $evidence.hasCheckout | Should -Be $true
            $evidence.hasWrite | Should -Be $false
            $evidence.hasDelta | Should -Be $false
        }

        It 'classifies as "likely" for write + delta without checkout' {
            $snapshotComp = @{
                hasWrite = $true
                hasDelta = $true
                changes = @("Modification date changed")
            }

            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -LastModifiedBy "John Smith" `
                -SnapshotComparison $snapshotComp

            $evidence.confidence | Should -Be "likely"
        }

        It 'classifies as "likely" for write + delta without attribution' {
            $snapshotComp = @{
                hasWrite = $true
                hasDelta = $true
                changes = @("Coordinates changed")
            }

            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -SnapshotComparison $snapshotComp

            $evidence.confidence | Should -Be "likely"
            $evidence.attributionStrength | Should -Be "weak"
        }
    }

    Context 'Test-EvidenceQuality' {
        It 'returns high quality score for confirmed evidence' {
            $evidence = @{
                hasCheckout = $true
                hasWrite = $true
                hasDelta = $true
                attributionStrength = "strong"
                confidence = "confirmed"
                proxyOwnerName = "John Smith"
                lastModifiedBy = "John Smith"
                writeSources = @("ROBCADSTUDY_.MODIFICATIONDATE_DA_")
            }

            $quality = Test-EvidenceQuality -Evidence $evidence

            $quality.isValid | Should -Be $true
            $quality.qualityScore | Should -Be 100
            $quality.warnings.Count | Should -Be 0
        }

        It 'warns when confirmed evidence missing proxyOwnerName' {
            $evidence = @{
                hasCheckout = $true
                hasWrite = $true
                hasDelta = $true
                attributionStrength = "strong"
                confidence = "confirmed"
                lastModifiedBy = "John Smith"
            }

            $quality = Test-EvidenceQuality -Evidence $evidence

            $quality.warnings | Should -Contain "Confirmed work missing proxyOwnerName"
        }

        It 'recommends query enhancement for weak attribution' {
            $evidence = @{
                hasCheckout = $false
                hasWrite = $true
                hasDelta = $false
                attributionStrength = "weak"
                confidence = "unattributed"
            }

            $quality = Test-EvidenceQuality -Evidence $evidence

            $quality.recommendations | Should -Contain "Consider enhancing queries to include LASTMODIFIEDBY_S_ field"
        }

        It 'recommends checkout review for checkout_only' {
            $evidence = @{
                hasCheckout = $true
                hasWrite = $false
                hasDelta = $false
                attributionStrength = "medium"
                confidence = "checkout_only"
            }

            $quality = Test-EvidenceQuality -Evidence $evidence

            $quality.recommendations | Should -Contain "Object checked out but unchanged - possible stale checkout"
        }

        It 'warns for unattributed work' {
            $evidence = @{
                hasCheckout = $false
                hasWrite = $true
                hasDelta = $true
                attributionStrength = "weak"
                confidence = "unattributed"
            }

            $quality = Test-EvidenceQuality -Evidence $evidence

            $quality.warnings | Should -Contain "Real work detected but attribution missing or contradictory"
        }

        It 'assigns quality scores correctly' {
            $confirmedEvidence = @{ confidence = "confirmed" }
            $likelyEvidence = @{ confidence = "likely" }
            $checkoutOnlyEvidence = @{ confidence = "checkout_only" }
            $unattributedEvidence = @{ confidence = "unattributed" }

            (Test-EvidenceQuality -Evidence $confirmedEvidence).qualityScore | Should -Be 100
            (Test-EvidenceQuality -Evidence $likelyEvidence).qualityScore | Should -Be 75
            (Test-EvidenceQuality -Evidence $checkoutOnlyEvidence).qualityScore | Should -Be 50
            (Test-EvidenceQuality -Evidence $unattributedEvidence).qualityScore | Should -Be 25
        }
    }

    Context 'Edge Cases and Error Handling' {
        It 'handles null values gracefully in attribution strength' {
            $strength = Get-AttributionStrength `
                -ProxyOwnerName $null `
                -LastModifiedBy $null

            $strength | Should -Be "weak"
        }

        It 'handles default datetime values' {
            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -ModificationDate ([datetime]::MinValue) `
                -CheckoutDate ([datetime]::MinValue)

            $evidence | Should -Not -BeNullOrEmpty
            $evidence.confidence | Should -Be "unattributed"
        }

        It 'handles empty arrays in writeSources' {
            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -WriteSources @()

            $evidence.hasWrite | Should -Be $false
            ($evidence.Keys -contains 'writeSources') | Should -BeFalse
        }

        It 'handles deltaSummary with zero delta' {
            $deltaSummary = @{
                kind = "movement"
                maxAbsDelta = 0
            }

            $evidence = New-EvidenceBlock `
                -ObjectId "12345" `
                -ObjectType "Study" `
                -DeltaSummary $deltaSummary

            $evidence.hasDelta | Should -Be $false
        }
    }
}
