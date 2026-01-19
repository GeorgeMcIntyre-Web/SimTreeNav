# Cache Status Monitor
# Shows status of all performance caches

Write-Host "`n=== Performance Cache Status ===" -ForegroundColor Cyan
Write-Host ""

$caches = Get-ChildItem -Filter "*-cache-*" -ErrorAction SilentlyContinue

if ($caches.Count -eq 0) {
    Write-Host "No caches found - run tree generation to create them" -ForegroundColor Yellow
    exit
}

$results = $caches | ForEach-Object {
    $age = (Get-Date) - $_.LastWriteTime
    $sizeKB = [math]::Round($_.Length / 1KB, 2)

    # Determine cache type and expiration
    $status = if ($_.Name -like "icon-cache-*") {
        $limit = "7 days"
        if ($age.Days -lt 7) { "Fresh ✅" } else { "Expired ⚠️" }
    } elseif ($_.Name -like "tree-cache-*") {
        $limit = "24 hours"
        if ($age.Hours -lt 24) { "Fresh ✅" } else { "Expired ⚠️" }
    } elseif ($_.Name -like "user-activity-cache-*") {
        $limit = "1 hour"
        if ($age.TotalMinutes -lt 60) { "Fresh ✅" } else { "Expired ⚠️" }
    } else {
        $limit = "Unknown"
        "Unknown"
    }

    [PSCustomObject]@{
        Cache = $_.Name
        "Size (KB)" = $sizeKB
        "Age (Hours)" = [math]::Round($age.TotalHours, 1)
        "Age (Days)" = [math]::Round($age.TotalDays, 2)
        "Lifetime" = $limit
        Status = $status
    }
}

$results | Format-Table -AutoSize

Write-Host "`nCache Summary:" -ForegroundColor Cyan
$freshCount = ($results | Where-Object { $_.Status -like "*✅*" }).Count
$expiredCount = ($results | Where-Object { $_.Status -like "*⚠️*" }).Count
Write-Host "  Fresh: $freshCount" -ForegroundColor Green
Write-Host "  Expired: $expiredCount" -ForegroundColor Yellow

if ($expiredCount -gt 0) {
    Write-Host "`nExpired caches will be refreshed on next run" -ForegroundColor Gray
}

Write-Host "`nCache Management Commands:" -ForegroundColor Cyan
Write-Host "  Clear all caches:     Remove-Item *-cache-*" -ForegroundColor Gray
Write-Host "  Clear icon cache:     Remove-Item icon-cache-*.json" -ForegroundColor Gray
Write-Host "  Clear tree cache:     Remove-Item tree-cache-*.txt" -ForegroundColor Gray
Write-Host "  Clear user activity:  Remove-Item user-activity-cache-*.js" -ForegroundColor Gray
Write-Host ""
