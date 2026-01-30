# E2E Evidence Verification Script
# Purpose: Verify evidence blocks are complete and confidence levels are correctly assigned
# Date: 2026-01-29

param(
    [Parameter(Mandatory=$true)]
    [string]$ManagementDataFile
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  E2E Evidence Verification" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Data File: $ManagementDataFile" -ForegroundColor Gray
Write-Host ""

if (-not (Test-Path $ManagementDataFile)) {
    Write-Error "ERROR: Management data file not found: $ManagementDataFile"
    exit 1
}

# Load JSON data
try {
    $jsonContent = Get-Content $ManagementDataFile -Raw -Encoding UTF8
    $data = $jsonContent | ConvertFrom-Json
} catch {
    Write-Error "ERROR: Failed to parse JSON: $_"
    exit 1
}

# Initialize verification results
$verificationResults = @{
    totalEvents = 0
    eventsWithEvidence = 0
    eventsWithoutEvidence = 0
    confidenceCounts = @{
        confirmed = 0
        likely = 0
        checkout_only = 0
        unattributed = 0
    }
    triangleViolations = @()
    movementEvents = @()
    checkoutOnlyEvents = @()
    warnings = @()
}

# Check 1: Evidence exists on all events
Write-Host "[1/6] Checking evidence blocks exist on all events..." -ForegroundColor Yellow

if (-not $data.events) {
    Write-Error "ERROR: No 'events' array found in data file"
    exit 1
}

$verificationResults.totalEvents = $data.events.Count

foreach ($event in $data.events) {
    if ($event.evidence) {
        $verificationResults.eventsWithEvidence++

        # Count by confidence
        $confidence = $event.evidence.confidence
        if ($verificationResults.confidenceCounts.ContainsKey($confidence)) {
            $verificationResults.confidenceCounts[$confidence]++
        }
    } else {
        $verificationResults.eventsWithoutEvidence++
        $verificationResults.warnings += "Event missing evidence: $($event.description)"
    }
}

Write-Host "  ✓ Events with evidence: $($verificationResults.eventsWithEvidence) / $($verificationResults.totalEvents)" -ForegroundColor Green
if ($verificationResults.eventsWithoutEvidence -gt 0) {
    Write-Host "  ⚠ Events WITHOUT evidence: $($verificationResults.eventsWithoutEvidence)" -ForegroundColor Yellow
}

# Check 2: Confirmed confidence implies evidence triangle
Write-Host "`n[2/6] Verifying evidence triangle for 'confirmed' events..." -ForegroundColor Yellow

$confirmedEvents = $data.events | Where-Object { $_.evidence.confidence -eq "confirmed" }

foreach ($event in $confirmedEvents) {
    $evidence = $event.evidence

    $triangleComplete = $evidence.hasCheckout -and $evidence.hasWrite -and $evidence.hasDelta

    if (-not $triangleComplete) {
        $verificationResults.triangleViolations += @{
            event = $event.description
            hasCheckout = $evidence.hasCheckout
            hasWrite = $evidence.hasWrite
            hasDelta = $evidence.hasDelta
            attributionStrength = $evidence.attributionStrength
        }
    }
}

if ($verificationResults.triangleViolations.Count -eq 0) {
    Write-Host "  ✓ All confirmed events have complete evidence triangle" -ForegroundColor Green
} else {
    Write-Host "  ✗ Triangle violations found: $($verificationResults.triangleViolations.Count)" -ForegroundColor Red
    foreach ($violation in $verificationResults.triangleViolations) {
        Write-Host "    - $($violation.event): checkout=$($violation.hasCheckout), write=$($violation.hasWrite), delta=$($violation.hasDelta)" -ForegroundColor Red
    }
}

# Check 3: Movement events with delta summaries
Write-Host "`n[3/6] Analyzing movement events and delta summaries..." -ForegroundColor Yellow

$movementEvents = $data.events | Where-Object {
    $_.evidence.deltaSummary -and $_.evidence.deltaSummary.kind -eq "movement"
}

foreach ($event in $movementEvents) {
    $delta = $event.evidence.deltaSummary
    $maxDelta = $delta.maxAbsDelta

    $movementType = if ($maxDelta -ge 1000) { "WORLD" } else { "SIMPLE" }

    $verificationResults.movementEvents += @{
        description = $event.description
        timestamp = $event.timestamp
        user = $event.user
        maxAbsDelta = $maxDelta
        movementType = $movementType
        before = $delta.before
        after = $delta.after
        confidence = $event.evidence.confidence
    }
}

$simpleMovements = $verificationResults.movementEvents | Where-Object { $_.movementType -eq "SIMPLE" }
$worldMovements = $verificationResults.movementEvents | Where-Object { $_.movementType -eq "WORLD" }

Write-Host "  Total movement events: $($movementEvents.Count)" -ForegroundColor Gray
Write-Host "    - Simple movements (< 1000mm): $($simpleMovements.Count)" -ForegroundColor Cyan
Write-Host "    - World movements (>= 1000mm): $($worldMovements.Count)" -ForegroundColor Magenta

if ($worldMovements.Count -gt 0) {
    Write-Host "`n  World movement details:" -ForegroundColor Magenta
    foreach ($move in $worldMovements) {
        Write-Host "    [$($move.timestamp)] $($move.user): $($move.description)" -ForegroundColor White
        Write-Host "      Max delta: $($move.maxAbsDelta)mm, Confidence: $($move.confidence)" -ForegroundColor Gray
        if ($move.before) {
            Write-Host "      Before: x=$($move.before.x), y=$($move.before.y), z=$($move.before.z)" -ForegroundColor Gray
        }
        if ($move.after) {
            Write-Host "      After:  x=$($move.after.x), y=$($move.after.y), z=$($move.after.z)" -ForegroundColor Gray
        }
    }
}

# Check 4: Checkout-only events (edge case)
Write-Host "`n[4/6] Finding checkout-only events..." -ForegroundColor Yellow

$checkoutOnlyEvents = $data.events | Where-Object { $_.evidence.confidence -eq "checkout_only" }

$verificationResults.checkoutOnlyEvents = $checkoutOnlyEvents

Write-Host "  Checkout-only events: $($checkoutOnlyEvents.Count)" -ForegroundColor Gray

if ($checkoutOnlyEvents.Count -gt 0) {
    Write-Host "  (Events where object is checked out but has no write or delta)" -ForegroundColor Gray
    foreach ($event in $checkoutOnlyEvents) {
        Write-Host "    - $($event.description) by $($event.user)" -ForegroundColor Yellow
    }
}

# Check 5: Snapshot integrity
Write-Host "`n[5/6] Checking snapshot file metadata..." -ForegroundColor Yellow

if ($data.metadata.snapshotFile) {
    Write-Host "  ✓ Snapshot file referenced: $($data.metadata.snapshotFile)" -ForegroundColor Green

    # Check if snapshot file exists
    $snapshotPath = Join-Path (Split-Path $ManagementDataFile -Parent) $data.metadata.snapshotFile

    if (Test-Path $snapshotPath) {
        $snapshotContent = Get-Content $snapshotPath -Raw | ConvertFrom-Json
        Write-Host "  ✓ Snapshot file exists: $snapshotPath" -ForegroundColor Green
        Write-Host "    Records: $($snapshotContent.recordCount)" -ForegroundColor Gray
        Write-Host "    Generated: $($snapshotContent.generatedAt)" -ForegroundColor Gray
    } else {
        Write-Host "  ⚠ Snapshot file not found at: $snapshotPath" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ⚠ No snapshot file referenced in metadata" -ForegroundColor Yellow
}

# Check 6: Confidence distribution summary
Write-Host "`n[6/6] Confidence distribution summary..." -ForegroundColor Yellow

Write-Host "  Confirmed:      $($verificationResults.confidenceCounts.confirmed)" -ForegroundColor Green
Write-Host "  Likely:         $($verificationResults.confidenceCounts.likely)" -ForegroundColor Cyan
Write-Host "  Checkout Only:  $($verificationResults.confidenceCounts.checkout_only)" -ForegroundColor Yellow
Write-Host "  Unattributed:   $($verificationResults.confidenceCounts.unattributed)" -ForegroundColor Magenta

# Summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host "  Verification Summary" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

$passed = $true

if ($verificationResults.eventsWithoutEvidence -gt 0) {
    Write-Host "  ✗ FAIL: Some events missing evidence blocks" -ForegroundColor Red
    $passed = $false
}

if ($verificationResults.triangleViolations.Count -gt 0) {
    Write-Host "  ✗ FAIL: Evidence triangle violations found" -ForegroundColor Red
    $passed = $false
}

if ($passed) {
    Write-Host "  ✓ PASS: All verification checks passed" -ForegroundColor Green
} else {
    Write-Host "  ✗ FAIL: Verification checks failed" -ForegroundColor Red
}

Write-Host "`n  Evidence Quality:" -ForegroundColor White
Write-Host "    - Events with evidence: $($verificationResults.eventsWithEvidence) / $($verificationResults.totalEvents)" -ForegroundColor White
Write-Host "    - Confirmed events: $($verificationResults.confidenceCounts.confirmed)" -ForegroundColor White
Write-Host "    - Movement events: $($movementEvents.Count) (Simple: $($simpleMovements.Count), World: $($worldMovements.Count))" -ForegroundColor White

Write-Host ""

# Export verification results to JSON
$outputFile = $ManagementDataFile -replace '\.json$', '-verification.json'
$verificationResults | ConvertTo-Json -Depth 10 | Set-Content $outputFile -Encoding UTF8
Write-Host "  Verification results saved to: $outputFile" -ForegroundColor Gray
Write-Host ""

if ($passed) {
    exit 0
} else {
    exit 1
}
