# Tree Evidence Classifier
# Maps tree changes to evidence model schema v1.3.0

function Resolve-TreeCoords {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$TreeChange,
        [Parameter(Mandatory=$true)]
        [string]$Prefix
    )

    $coordsKey = "${Prefix}_coords"
    if ($TreeChange.ContainsKey($coordsKey) -and $TreeChange[$coordsKey]) {
        $parts = $TreeChange[$coordsKey].ToString().Split(',')
        if ($parts.Count -ge 3) {
            return @{
                x = [double]$parts[0]
                y = [double]$parts[1]
                z = [double]$parts[2]
            }
        }
    }

    $xKey = "${Prefix}_x"
    $yKey = "${Prefix}_y"
    $zKey = "${Prefix}_z"
    if ($TreeChange.ContainsKey($xKey) -or $TreeChange.ContainsKey($yKey) -or $TreeChange.ContainsKey($zKey)) {
        return @{
            x = if ($TreeChange.ContainsKey($xKey)) { [double]$TreeChange[$xKey] } else { $null }
            y = if ($TreeChange.ContainsKey($yKey)) { [double]$TreeChange[$yKey] } else { $null }
            z = if ($TreeChange.ContainsKey($zKey)) { [double]$TreeChange[$zKey] } else { $null }
        }
    }

    return $null
}

function Resolve-TreeDelta {
    param(
        [hashtable]$TreeChange,
        [hashtable]$OldCoords,
        [hashtable]$NewCoords
    )

    if ($TreeChange.ContainsKey("delta_x") -or $TreeChange.ContainsKey("delta_y") -or $TreeChange.ContainsKey("delta_z")) {
        return @{
            x = if ($TreeChange.ContainsKey("delta_x")) { [double]$TreeChange.delta_x } else { $null }
            y = if ($TreeChange.ContainsKey("delta_y")) { [double]$TreeChange.delta_y } else { $null }
            z = if ($TreeChange.ContainsKey("delta_z")) { [double]$TreeChange.delta_z } else { $null }
        }
    }

    if ($OldCoords -and $NewCoords) {
        return @{
            x = [Math]::Round(($NewCoords.x - $OldCoords.x), 2)
            y = [Math]::Round(($NewCoords.y - $OldCoords.y), 2)
            z = [Math]::Round(($NewCoords.z - $OldCoords.z), 2)
        }
    }

    return $null
}

function New-TreeEvidenceBlock {
    param(
        [Parameter(Mandatory)]
        [hashtable]$TreeChange,

        [Parameter(Mandatory)]
        [hashtable]$CheckoutData,

        [Parameter(Mandatory)]
        [hashtable]$WriteData
    )

    if (-not $TreeChange) {
        return $null
    }

    $type = $null
    if ($TreeChange.ContainsKey("evidence_type")) {
        $type = $TreeChange.evidence_type
    }

    if ([string]::IsNullOrWhiteSpace($type)) {
        return $null
    }

    $studyId = [string]$TreeChange.study_id
    $studyName = $TreeChange.study_name
    $nodeId = $TreeChange.node_id
    $nodeName = if ($TreeChange.ContainsKey("node_name")) { $TreeChange.node_name } else { $TreeChange.new_name }
    $nodeType = $TreeChange.node_type
    $detectedAt = $TreeChange.detected_at

    $hasCheckout = $false
    if ($CheckoutData -and $CheckoutData.ContainsKey($studyId)) {
        $hasCheckout = [bool]$CheckoutData[$studyId]
    }

    $hasWrite = $true
    if ($WriteData -and $WriteData.ContainsKey($studyId)) {
        $hasWrite = [bool]$WriteData[$studyId]
    }

    $confidence = if ($hasCheckout -and $hasWrite) {
        "confirmed"
    } elseif ($hasWrite) {
        "likely"
    } else {
        "possible"
    }

    $contextBase = [ordered]@{
        nodeId = $nodeId
        nodeName = $nodeName
        nodeType = $nodeType
        studyId = $studyId
        studyName = $studyName
        detectedAt = $detectedAt
    }

    if ($TreeChange.ContainsKey("snapshot_files")) {
        $contextBase.snapshotFiles = $TreeChange.snapshot_files
    }

    switch ($type) {
        "rename" {
            $deltaSummary = @{
                kind = "naming"
                fields = @("display_name")
                before = @{
                    display_name = $TreeChange.old_name
                    name_provenance = $TreeChange.old_provenance
                }
                after = @{
                    display_name = $TreeChange.new_name
                    name_provenance = $TreeChange.new_provenance
                }
            }

            $contextBase.workType = "study.naming"

            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = $deltaSummary
                }
                context = $contextBase
                confidence = $confidence
            }
        }

        "movement" {
            $oldCoords = Resolve-TreeCoords -TreeChange $TreeChange -Prefix "old"
            $newCoords = Resolve-TreeCoords -TreeChange $TreeChange -Prefix "new"
            $delta = Resolve-TreeDelta -TreeChange $TreeChange -OldCoords $oldCoords -NewCoords $newCoords
            $maxAbsDelta = if ($TreeChange.ContainsKey("delta_mm")) { [double]$TreeChange.delta_mm } else { $null }

            $before = $null
            if ($oldCoords) {
                $before = @{
                    x = $oldCoords.x
                    y = $oldCoords.y
                    z = $oldCoords.z
                }
                if ($TreeChange.ContainsKey("coord_provenance")) {
                    $before.coord_provenance = $TreeChange.coord_provenance
                }
            }

            $after = $null
            if ($newCoords) {
                $after = @{
                    x = $newCoords.x
                    y = $newCoords.y
                    z = $newCoords.z
                }
                if ($TreeChange.ContainsKey("coord_provenance")) {
                    $after.coord_provenance = $TreeChange.coord_provenance
                }
            }

            $deltaSummary = @{
                kind = "movement"
                fields = @("x", "y", "z")
                maxAbsDelta = $maxAbsDelta
                before = $before
                after = $after
                delta = $delta
                mapping_type = $TreeChange.mapping_type
            }

            $contextBase.workType = "study.layout"
            if ($TreeChange.ContainsKey("movement_type")) {
                $contextBase.movementClassification = $TreeChange.movement_type
            }

            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = $deltaSummary
                }
                context = $contextBase
                confidence = $confidence
            }
        }

        "node_added" {
            $deltaSummary = @{
                kind = "topology"
                fields = @("node_count")
                operation = "add"
            }

            $contextBase.workType = "study.topology"
            $contextBase.changeType = "node_added"
            if ($TreeChange.ContainsKey("parent_node_id")) {
                $contextBase.parentNodeId = $TreeChange.parent_node_id
            }
            if ($TreeChange.ContainsKey("resource_name")) {
                $contextBase.resourceName = $TreeChange.resource_name
            }
            if ($TreeChange.ContainsKey("name_provenance")) {
                $contextBase.nameProvenance = $TreeChange.name_provenance
            }

            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = $deltaSummary
                }
                context = $contextBase
                confidence = $confidence
            }
        }

        "node_removed" {
            $deltaSummary = @{
                kind = "topology"
                fields = @("node_count")
                operation = "remove"
            }

            $contextBase.workType = "study.topology"
            $contextBase.changeType = "node_removed"
            if ($TreeChange.ContainsKey("parent_node_id")) {
                $contextBase.parentNodeId = $TreeChange.parent_node_id
            }
            if ($TreeChange.ContainsKey("resource_name")) {
                $contextBase.resourceName = $TreeChange.resource_name
            }
            if ($TreeChange.ContainsKey("name_provenance")) {
                $contextBase.nameProvenance = $TreeChange.name_provenance
            }

            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = $deltaSummary
                }
                context = $contextBase
                confidence = $confidence
            }
        }

        "structure" {
            $deltaSummary = @{
                kind = "structure"
                fields = @("parent_node_id")
                before = @{
                    parent_node_id = $TreeChange.old_parent_id
                }
                after = @{
                    parent_node_id = $TreeChange.new_parent_id
                }
            }

            $contextBase.workType = "study.structure"
            $contextBase.changeType = if ($TreeChange.ContainsKey("change_type")) { $TreeChange.change_type } else { "parent_changed" }
            if ($TreeChange.ContainsKey("name_provenance")) {
                $contextBase.nameProvenance = $TreeChange.name_provenance
            }

            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = $deltaSummary
                }
                context = $contextBase
                confidence = $confidence
            }
        }

        "resource_mapping" {
            $deltaSummary = @{
                kind = "resourceMapping"
                fields = @("resource_id", "resource_name")
                before = @{
                    resource_id = $TreeChange.old_resource_id
                    resource_name = $TreeChange.old_resource_name
                }
                after = @{
                    resource_id = $TreeChange.new_resource_id
                    resource_name = $TreeChange.new_resource_name
                }
            }

            $contextBase.workType = "study.resourceMapping"
            $contextBase.shortcutId = $nodeId
            $contextBase.shortcutName = $nodeName

            return @{
                schemaVersion = "1.3.0"
                evidence = @{
                    hasCheckout = $hasCheckout
                    hasWrite = $hasWrite
                    hasDelta = $true
                    deltaSummary = $deltaSummary
                }
                context = $contextBase
                confidence = $confidence
            }
        }

        default {
            return $null
        }
    }
}
