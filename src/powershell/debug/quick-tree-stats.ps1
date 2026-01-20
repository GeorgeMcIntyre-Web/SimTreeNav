# Quick Tree Statistics - Fast analysis without loading entire tree into memory
# Provides essential statistics about the generated tree

param(
    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ProjectId
)

Write-Host "==== QUICK TREE STATISTICS ====" -ForegroundColor Cyan

# Find tree file
$treeFiles = Get-ChildItem "tree-data-${Schema}-${ProjectId}*.txt" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match 'clean' }

if ($treeFiles.Count -eq 0) {
    Write-Error "No tree data file found for ${Schema}/${ProjectId}"
    exit 1
}

$treeFile = $treeFiles[0]
Write-Host "File: $($treeFile.Name)" -ForegroundColor Green
Write-Host "Size: $([math]::Round($treeFile.Length / 1MB, 2)) MB" -ForegroundColor Green
Write-Host ""

# Stream-based analysis for performance
$totalNodes = 0
$levelCounts = @{}
$classCounts = @{}
$orphanCount = 0
$parentIds = @{}
$objectIds = @{}
$maxLevel = 0

Write-Host "Analyzing..." -ForegroundColor Yellow

$reader = [System.IO.StreamReader]::new($treeFile.FullName, [System.Text.Encoding]::UTF8)
try {
    while ($null -ne ($line = $reader.ReadLine())) {
        $parts = $line -split '\|'
        if ($parts.Length -ge 10) {
            $totalNodes++
            $level = [int]$parts[0]
            $parentId = $parts[1]
            $objectId = $parts[2]
            $niceName = $parts[8]

            # Track levels
            if (-not $levelCounts.ContainsKey($level)) {
                $levelCounts[$level] = 0
            }
            $levelCounts[$level]++
            if ($level -gt $maxLevel) {
                $maxLevel = $level
            }

            # Track classes
            if (-not $classCounts.ContainsKey($niceName)) {
                $classCounts[$niceName] = 0
            }
            $classCounts[$niceName]++

            # Track parent/object relationships
            $parentIds[$objectId] = $parentId
            $objectIds[$objectId] = $true

            # Progress indicator every 50K nodes
            if ($totalNodes % 50000 -eq 0) {
                Write-Host "  Processed: $totalNodes nodes..." -ForegroundColor Gray
            }
        }
    }
} finally {
    $reader.Close()
}

Write-Host ""
Write-Host "==== RESULTS ====" -ForegroundColor Cyan
Write-Host "Total Nodes:  $totalNodes" -ForegroundColor White
Write-Host "Max Depth:    $maxLevel" -ForegroundColor White
Write-Host "Node Types:   $($classCounts.Count)" -ForegroundColor White

Write-Host "`nNodes by Level:" -ForegroundColor Cyan
foreach ($level in ($levelCounts.Keys | Sort-Object)) {
    $pct = [math]::Round(($levelCounts[$level] / $totalNodes) * 100, 1)
    Write-Host "  Level $level : $($levelCounts[$level]) ($pct%)" -ForegroundColor Gray
}

Write-Host "`nTop 30 Node Types:" -ForegroundColor Cyan
$classCounts.GetEnumerator() |
    Sort-Object -Property Value -Descending |
    Select-Object -First 30 |
    ForEach-Object {
        $pct = [math]::Round(($_.Value / $totalNodes) * 100, 1)
        Write-Host "  $($_.Key) : $($_.Value) ($pct%)" -ForegroundColor Gray
    }

# Check for orphans (quick check on sample)
Write-Host "`nChecking for orphan nodes..." -ForegroundColor Yellow
$orphans = @()
foreach ($objId in ($objectIds.Keys | Select-Object -First 10000)) {
    $parentId = $parentIds[$objId]
    if ($parentId -and $parentId -ne '0' -and -not $objectIds.ContainsKey($parentId)) {
        $orphans += [PSCustomObject]@{
            ObjectId = $objId
            ParentId = $parentId
        }
        if ($orphans.Count -ge 100) {
            break  # Sample only
        }
    }
}

if ($orphans.Count -gt 0) {
    Write-Host "  WARNING: Found $($orphans.Count)+ orphan nodes (sampled)" -ForegroundColor Red
    Write-Host "  Sample orphans:" -ForegroundColor Gray
    $orphans | Select-Object -First 5 | ForEach-Object {
        Write-Host "    Node $($_.ObjectId) -> Missing Parent $($_.ParentId)" -ForegroundColor Gray
    }
} else {
    Write-Host "  No orphan nodes detected (sampled 10K nodes)" -ForegroundColor Green
}

# Check for duplicates
Write-Host "`nChecking for duplicate OBJECT_IDs..." -ForegroundColor Yellow
$duplicateCheck = $objectIds.Keys | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicateCheck.Count -gt 0) {
    Write-Host "  WARNING: Found $($duplicateCheck.Count) duplicate OBJECT_IDs!" -ForegroundColor Red
} else {
    Write-Host "  No duplicates found" -ForegroundColor Green
}

Write-Host "`n==== COMPLETE ====" -ForegroundColor Cyan
