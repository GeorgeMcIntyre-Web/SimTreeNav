# Compute Previous Run Diff
# Purpose: Compare two management data JSON files to detect study-level changes
# Date: 2026-02-03

param(
    [Parameter(Mandatory=$true)]
    [string]$PrevFile,

    [Parameter(Mandatory=$true)]
    [string]$LatestFile,

    [switch]$ShowDetails
)

<#
.SYNOPSIS
    Computes study-level changes between two management data runs.

.DESCRIPTION
    Compares prev and latest JSON files to identify which studies changed.
    A study is considered "changed" if any of these differ:
    - healthScore
    - healthStatus
    - checkedOut (WORKING_VERSION_ID)
    - modifiedInRange
    - resourceCount (from healthSignals)
    - panelCount (from healthSignals)
    - operationCount (from healthSignals)
    - studyName

.OUTPUTS
    Returns a hashtable with:
    - compareMeta: Dashboard-level comparison metadata
    - studyChanges: Dictionary of studyId -> change info
#>

function Compare-StudyData {
    param($PrevStudy, $LatestStudy)

    $changes = @()
    $changed = $false

    # Compare health score
    if ($PrevStudy.healthScore -ne $LatestStudy.healthScore) {
        $changes += "health"
        $changed = $true
    }

    # Compare health status
    if ($PrevStudy.healthStatus -ne $LatestStudy.healthStatus) {
        if ($changes -notcontains "health") {
            $changes += "health"
        }
        $changed = $true
    }

    # Compare checkout status (handle different field name variations)
    $prevWorkingVerId = if ($PrevStudy.PSObject.Properties.Name -contains 'WORKING_VERSION_ID') {
        $PrevStudy.WORKING_VERSION_ID
    } elseif ($PrevStudy.PSObject.Properties.Name -contains 'checkout_working_version_id') {
        $PrevStudy.checkout_working_version_id
    } else {
        0
    }
    
    $latestWorkingVerId = if ($LatestStudy.PSObject.Properties.Name -contains 'WORKING_VERSION_ID') {
        $LatestStudy.WORKING_VERSION_ID
    } elseif ($LatestStudy.PSObject.Properties.Name -contains 'checkout_working_version_id') {
        $LatestStudy.checkout_working_version_id
    } else {
        0
    }
    
    $prevCheckedOut = ($prevWorkingVerId -gt 0)
    $latestCheckedOut = ($latestWorkingVerId -gt 0)
    if ($prevCheckedOut -ne $latestCheckedOut) {
        $changes += "checkout"
        $changed = $true
    }

    # Compare modified in range (if present)
    if ($PrevStudy.PSObject.Properties.Name -contains 'modifiedInRange' -and 
        $LatestStudy.PSObject.Properties.Name -contains 'modifiedInRange') {
        if ($PrevStudy.modifiedInRange -ne $LatestStudy.modifiedInRange) {
            $changes += "modified"
            $changed = $true
        }
    }

    # Compare resource/panel/operation counts from healthSignals
    if ($PrevStudy.healthSignals -and $LatestStudy.healthSignals) {
        if ($PrevStudy.healthSignals.resourceCount -ne $LatestStudy.healthSignals.resourceCount) {
            $changes += "resources"
            $changed = $true
        }
        if ($PrevStudy.healthSignals.panelCount -ne $LatestStudy.healthSignals.panelCount) {
            $changes += "panels"
            $changed = $true
        }
        if ($PrevStudy.healthSignals.operationCount -ne $LatestStudy.healthSignals.operationCount) {
            $changes += "operations"
            $changed = $true
        }
    }

    # Compare study name (handle case variations)
    $prevName = if ($PrevStudy.PSObject.Properties.Name -contains 'STUDY_NAME') {
        $PrevStudy.STUDY_NAME
    } elseif ($PrevStudy.PSObject.Properties.Name -contains 'study_name') {
        $PrevStudy.study_name
    } else {
        ""
    }
    
    $latestName = if ($LatestStudy.PSObject.Properties.Name -contains 'STUDY_NAME') {
        $LatestStudy.STUDY_NAME
    } elseif ($LatestStudy.PSObject.Properties.Name -contains 'study_name') {
        $LatestStudy.study_name
    } else {
        ""
    }
    
    if ($prevName -ne $latestName) {
        $changes += "name"
        $changed = $true
    }

    return @{
        changed = $changed
        reasons = $changes
    }
}

# ========================================
# Main Logic
# ========================================

if (-not (Test-Path $PrevFile)) {
    Write-Warning "Previous file not found: $PrevFile"
    return @{
        compareMeta = @{
            mode = "no_previous_run"
            prevRunAt = $null
            latestRunAt = $null
            changedStudyCount = 0
            noPreviousRun = $true
        }
        studyChanges = @{}
    }
}

if (-not (Test-Path $LatestFile)) {
    Write-Error "Latest file not found: $LatestFile"
    exit 1
}

if ($ShowDetails) {
    Write-Host "Loading previous run from: $PrevFile" -ForegroundColor Gray
    Write-Host "Loading latest run from: $LatestFile" -ForegroundColor Gray
}

# Load JSON files
try {
    $prevData = Get-Content $PrevFile -Raw | ConvertFrom-Json
    $latestData = Get-Content $LatestFile -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to load JSON files: $_"
    exit 1
}

# Extract timestamps
$prevRunAt = $prevData.metadata.generatedAt
$latestRunAt = $latestData.metadata.generatedAt

if ($ShowDetails) {
    Write-Host "Previous run: $prevRunAt" -ForegroundColor Cyan
    Write-Host "Latest run: $latestRunAt" -ForegroundColor Cyan
}

# Build study lookup for prev data
$prevStudies = @{}
foreach ($study in $prevData.studySummary) {
    # Try multiple field names for study ID
    $studyId = if ($study.OBJECT_ID) {
        $study.OBJECT_ID
    } elseif ($study.study_id) {
        $study.study_id
    } else {
        $null
    }
    
    if ($null -ne $studyId -and $studyId -ne '') {
        $prevStudies[$studyId] = $study
    }
}

# Compare each study in latest
$studyChanges = @{}
$changedCount = 0

foreach ($latestStudy in $latestData.studySummary) {
    # Try multiple field names for study ID
    $studyId = if ($latestStudy.OBJECT_ID) {
        $latestStudy.OBJECT_ID
    } elseif ($latestStudy.study_id) {
        $latestStudy.study_id
    } else {
        $null
    }
    
    # Skip if study ID is null or empty
    if ($null -eq $studyId -or $studyId -eq '') {
        continue
    }
    
    if ($prevStudies.ContainsKey($studyId)) {
        $prevStudy = $prevStudies[$studyId]
        $comparison = Compare-StudyData -PrevStudy $prevStudy -LatestStudy $latestStudy
        
        $studyChanges[$studyId] = @{
            changed = $comparison.changed
            reasons = $comparison.reasons
        }
        
        if ($comparison.changed) {
            $changedCount++
            if ($ShowDetails) {
                Write-Host "  Study $studyId changed: $($comparison.reasons -join ', ')" -ForegroundColor Yellow
            }
        }
    } else {
        # New study (not in prev)
        $studyChanges[$studyId] = @{
            changed = $true
            reasons = @("new")
        }
        $changedCount++
        if ($ShowDetails) {
            Write-Host "  Study $studyId is new" -ForegroundColor Green
        }
    }
}

# Check for removed studies
foreach ($prevStudyId in $prevStudies.Keys) {
    if ($null -eq $prevStudyId -or $prevStudyId -eq '') {
        continue
    }
    $foundInLatest = $false
    foreach ($latestStudy in $latestData.studySummary) {
        $latestId = if ($latestStudy.OBJECT_ID) { $latestStudy.OBJECT_ID } elseif ($latestStudy.study_id) { $latestStudy.study_id } else { $null }
        if ($latestId -eq $prevStudyId) {
            $foundInLatest = $true
            break
        }
    }
    if (-not $foundInLatest) {
        $studyChanges[$prevStudyId] = @{
            changed = $true
            reasons = @("removed")
        }
        $changedCount++
        if ($ShowDetails) {
            Write-Host "  Study $prevStudyId was removed" -ForegroundColor Red
        }
    }
}

if ($ShowDetails) {
    Write-Host "`nTotal changed studies: $changedCount / $($latestData.studySummary.Count)" -ForegroundColor Cyan
}

# Return result
return @{
    compareMeta = @{
        mode = "previous_run"
        prevRunAt = $prevRunAt
        latestRunAt = $latestRunAt
        prevFile = $PrevFile
        latestFile = $LatestFile
        changedStudyCount = $changedCount
        totalStudyCount = $latestData.studySummary.Count
        noPreviousRun = $false
    }
    studyChanges = $studyChanges
}
