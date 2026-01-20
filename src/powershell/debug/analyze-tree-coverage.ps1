# Analyze Tree Coverage - Alternative approach
# Analyzes the generated tree to identify potential gaps without needing database comparison

param(
    [Parameter(Mandatory=$true)]
    [string]$Schema,

    [Parameter(Mandatory=$true)]
    [int]$ProjectId,

    [string]$ProjectName = "Unknown"
)

$ErrorActionPreference = "Stop"

Write-Host "==== TREE COVERAGE ANALYSIS ====" -ForegroundColor Cyan
Write-Host "Schema: $Schema | Project: $ProjectName (ID: $ProjectId)" -ForegroundColor Cyan
Write-Host ""

# Find the tree data file
$tnsSlug = "*"  # Use wildcard since we may not know TNS name
$cleanFiles = Get-ChildItem "tree-data-${Schema}-${ProjectId}-clean.txt" -ErrorAction SilentlyContinue

if ($cleanFiles.Count -eq 0) {
    # Try without TNS slug
    $cleanFiles = Get-ChildItem "tree-data-${Schema}-${ProjectId}*.txt" -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'clean' }
}

if ($cleanFiles.Count -eq 0) {
    Write-Error "No tree data file found. Run generate-tree-html.ps1 first."
    exit 1
}

$cleanFile = $cleanFiles[0].FullName
Write-Host "Analyzing: $($cleanFiles[0].Name)" -ForegroundColor Green
Write-Host ""

# Parse the tree data
Write-Host "[1/4] Parsing tree data..." -ForegroundColor Yellow

$nodes = @{}
$nodesByLevel = @{}
$nodesByClass = @{}
$orphanNodes = @()
$rootNode = $null

Get-Content $cleanFile -Encoding UTF8 | ForEach-Object {
    $parts = $_ -split '\|'
    if ($parts.Length -ge 10) {
        $level = [int]$parts[0]
        $parentId = $parts[1]
        $objectId = $parts[2]
        $caption = $parts[3]
        $name = $parts[4]
        $externalId = $parts[5]
        $seqNumber = $parts[6]
        $className = $parts[7]
        $niceName = $parts[8]
        $typeId = if ($parts[9]) { $parts[9] } else { '' }

        $node = [PSCustomObject]@{
            Level = $level
            ParentId = $parentId
            ObjectId = $objectId
            Caption = $caption
            Name = $name
            ExternalId = $externalId
            SeqNumber = $seqNumber
            ClassName = $className
            NiceName = $niceName
            TypeId = $typeId
            Children = @()
        }

        $nodes[$objectId] = $node

        # Track by level
        if (-not $nodesByLevel.ContainsKey($level)) {
            $nodesByLevel[$level] = @()
        }
        $nodesByLevel[$level] += $node

        # Track by class
        if (-not $nodesByClass.ContainsKey($niceName)) {
            $nodesByClass[$niceName] = 0
        }
        $nodesByClass[$niceName]++

        if ($level -eq 0) {
            $rootNode = $node
        }
    }
}

Write-Host "  Total nodes parsed: $($nodes.Count)" -ForegroundColor Green
Write-Host "  Max tree depth: $($nodesByLevel.Keys | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum)" -ForegroundColor Green

# Build parent-child relationships
Write-Host "`n[2/4] Building relationships..." -ForegroundColor Yellow

foreach ($nodeId in $nodes.Keys) {
    $node = $nodes[$nodeId]
    if ($node.ParentId -and $nodes.ContainsKey($node.ParentId)) {
        $parent = $nodes[$node.ParentId]
        $parent.Children += $nodeId
    } elseif ($node.Level -gt 0 -and -not $nodes.ContainsKey($node.ParentId)) {
        # Orphan - parent doesn't exist in tree
        $orphanNodes += $node
    }
}

Write-Host "  Parent-child links built: $($nodes.Values | Where-Object { $_.Children.Count -gt 0 } | Measure-Object | Select-Object -ExpandProperty Count)" -ForegroundColor Green
if ($orphanNodes.Count -gt 0) {
    Write-Host "  WARNING: Found $($orphanNodes.Count) orphan nodes (parent not in tree)" -ForegroundColor Red
}

# Analyze tree structure
Write-Host "`n[3/4] Analyzing tree structure..." -ForegroundColor Yellow

Write-Host "  Nodes by Level:" -ForegroundColor Cyan
foreach ($level in ($nodesByLevel.Keys | Sort-Object)) {
    Write-Host "    Level $level : $($nodesByLevel[$level].Count) nodes" -ForegroundColor Gray
}

Write-Host "`n  Top 25 Node Types:" -ForegroundColor Cyan
$topClasses = $nodesByClass.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 25
foreach ($entry in $topClasses) {
    Write-Host "    $($entry.Name) : $($entry.Value)" -ForegroundColor Gray
}

# Identify potential gaps
Write-Host "`n[4/4] Identifying potential gaps..." -ForegroundColor Yellow

$potentialIssues = @()

# Issue 1: Orphan nodes
if ($orphanNodes.Count -gt 0) {
    $potentialIssues += [PSCustomObject]@{
        Issue = "Orphan Nodes"
        Count = $orphanNodes.Count
        Severity = "HIGH"
        Description = "Nodes whose parent OBJECT_ID doesn't exist in tree"
    }

    Write-Host "`n  Orphan Nodes (parent missing):" -ForegroundColor Red
    $orphanNodes | Select-Object -First 10 | ForEach-Object {
        Write-Host "    [$($_.ObjectId)] $($_.Caption) - Missing Parent: $($_.ParentId)" -ForegroundColor Gray
    }
    if ($orphanNodes.Count -gt 10) {
        Write-Host "    ... and $($orphanNodes.Count - 10) more" -ForegroundColor Gray
    }
}

# Issue 2: Check for expected library nodes at level 1
$level1Nodes = $nodesByLevel[1]
$expectedLibraries = @('PartLibrary', 'PartInstanceLibrary', 'MfgLibrary', 'EngineeringResourceLibrary', 'DES_Studies')
$missingLibraries = @()

foreach ($lib in $expectedLibraries) {
    $found = $level1Nodes | Where-Object { $_.NiceName -eq $lib -or $_.Caption -like "*$lib*" }
    if (-not $found) {
        $missingLibraries += $lib
    }
}

if ($missingLibraries.Count -gt 0) {
    $potentialIssues += [PSCustomObject]@{
        Issue = "Missing Standard Libraries"
        Count = $missingLibraries.Count
        Severity = "MEDIUM"
        Description = "Expected root-level libraries not found: $($missingLibraries -join ', ')"
    }
    Write-Host "`n  Missing Standard Libraries (Level 1):" -ForegroundColor Yellow
    foreach ($lib in $missingLibraries) {
        Write-Host "    - $lib" -ForegroundColor Gray
    }
}

# Issue 3: Nodes with no children that should have children
$leafNodesByClass = @{}
foreach ($node in $nodes.Values) {
    if ($node.Children.Count -eq 0) {
        if (-not $leafNodesByClass.ContainsKey($node.NiceName)) {
            $leafNodesByClass[$node.NiceName] = 0
        }
        $leafNodesByClass[$node.NiceName]++
    }
}

$suspiciousLeafNodes = @('PartLibrary', 'Collection', 'ResourceLibrary', 'MfgLibrary')
$foundSuspicious = @()
foreach ($suspicious in $suspiciousLeafNodes) {
    if ($leafNodesByClass.ContainsKey($suspicious) -and $leafNodesByClass[$suspicious] -gt 0) {
        $foundSuspicious += "$suspicious ($($leafNodesByClass[$suspicious]))"
    }
}

if ($foundSuspicious.Count -gt 0) {
    Write-Host "`n  Suspicious Leaf Nodes (collections with no children):" -ForegroundColor Yellow
    foreach ($item in $foundSuspicious) {
        Write-Host "    - $item" -ForegroundColor Gray
    }
}

# Issue 4: Check for duplicate OBJECT_IDs
Write-Host "`n  Checking for duplicate OBJECT_IDs..." -ForegroundColor Yellow
$duplicates = $nodes.Keys | Group-Object | Where-Object { $_.Count -gt 1 }
if ($duplicates.Count -gt 0) {
    $potentialIssues += [PSCustomObject]@{
        Issue = "Duplicate Nodes"
        Count = $duplicates.Count
        Severity = "HIGH"
        Description = "Same OBJECT_ID appears multiple times in tree"
    }
    Write-Host "    WARNING: Found $($duplicates.Count) duplicate OBJECT_IDs!" -ForegroundColor Red
    $duplicates | ForEach-Object {
        Write-Host "      OBJECT_ID $($_.Name) appears $($_.Count) times" -ForegroundColor Gray
    }
} else {
    Write-Host "    No duplicates found" -ForegroundColor Green
}

# Summary Report
Write-Host "`n==== SUMMARY ====" -ForegroundColor Cyan
Write-Host "  Total Nodes:     $($nodes.Count)" -ForegroundColor White
Write-Host "  Tree Depth:      $($nodesByLevel.Keys | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum)" -ForegroundColor White
Write-Host "  Node Types:      $($nodesByClass.Count)" -ForegroundColor White
Write-Host "  Orphan Nodes:    $($orphanNodes.Count)" -ForegroundColor $(if ($orphanNodes.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  Potential Issues: $($potentialIssues.Count)" -ForegroundColor $(if ($potentialIssues.Count -gt 0) { "Yellow" } else { "Green" })

if ($potentialIssues.Count -gt 0) {
    Write-Host "`n  Issues Found:" -ForegroundColor Yellow
    $potentialIssues | ForEach-Object {
        $color = switch ($_.Severity) {
            "HIGH" { "Red" }
            "MEDIUM" { "Yellow" }
            "LOW" { "Gray" }
        }
        Write-Host "    [$($_.Severity)] $($_.Issue): $($_.Description)" -ForegroundColor $color
    }
}

# Save orphan report if any found
if ($orphanNodes.Count -gt 0) {
    $reportFile = "orphan-nodes-${Schema}-${ProjectId}.csv"
    $csvContent = "ObjectId|Caption|NiceName|ClassName|ParentId|Level`n"
    foreach ($node in $orphanNodes) {
        $csvContent += "$($node.ObjectId)|$($node.Caption)|$($node.NiceName)|$($node.ClassName)|$($node.ParentId)|$($node.Level)`n"
    }
    [System.IO.File]::WriteAllText("$PWD\$reportFile", $csvContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "`n  Orphan nodes report saved: $reportFile" -ForegroundColor Green
}

Write-Host "`n==== ANALYSIS COMPLETE ====" -ForegroundColor Cyan
