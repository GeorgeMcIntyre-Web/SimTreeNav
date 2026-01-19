# XML vs HTML Validation Script
# Compares the generated HTML tree against the XML export to find missing nodes

param(
    [string]$XmlPath = "C:\Users\georgem\source\repos\cursor\SimTreeNav_data\FORD_DEARBORN.xml",
    [string]$HtmlPath = "navigation-tree-DESIGN12-18140190.html",
    [switch]$ShowMissing = $false,
    [int]$SampleSize = 20
)

Write-Host "=== XML vs HTML Validation ===" -ForegroundColor Cyan

# Verify files exist
if (-not (Test-Path $XmlPath)) {
    Write-Host "ERROR: XML file not found at: $XmlPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $HtmlPath)) {
    Write-Host "ERROR: HTML file not found at: $HtmlPath" -ForegroundColor Red
    Write-Host "Run tree-viewer-launcher.ps1 first." -ForegroundColor Yellow
    exit 1
}

# Parse XML to extract all node IDs
Write-Host "`nParsing XML export (this may take a minute)..." -ForegroundColor Yellow
try {
    [xml]$xml = Get-Content $XmlPath
} catch {
    Write-Host "ERROR: Failed to parse XML file: $_" -ForegroundColor Red
    exit 1
}

# Extract all NodeInfo/Id elements
Write-Host "Extracting node IDs from XML..." -ForegroundColor Yellow
$xmlNodes = @{}
$xmlNodesList = @()
$allElements = $xml.Data.Objects.ChildNodes
foreach ($element in $allElements) {
    if ($element.NodeInfo -and $element.NodeInfo.Id) {
        $nodeId = $element.NodeInfo.Id
        $nodeName = if ($element.name) { $element.name } else { $element.NodeInfo.Name }
        $nodeFamily = $element.NodeInfo.family

        $xmlNodes[$nodeId] = @{
            Name = $nodeName
            Family = $nodeFamily
            Type = $element.LocalName
        }
        $xmlNodesList += $nodeId
    }
}
$xmlNodeCount = $xmlNodes.Keys.Count
Write-Host "XML nodes found: $xmlNodeCount" -ForegroundColor Yellow

# Extract node IDs from HTML
Write-Host "`nExtracting nodes from HTML..." -ForegroundColor Yellow
$htmlContent = Get-Content $HtmlPath -Raw
$htmlLines = $htmlContent -split "`n" | Where-Object { $_ -match '^\d+\|' }
$htmlNodeIds = @{}
$htmlNodeSet = @{}
foreach ($line in $htmlLines) {
    $parts = $line -split '\|'
    if ($parts.Length -ge 10) {
        # Format: LEVEL|PARENT_ID|OBJECT_ID|CAPTION|NAME|EXTERNAL_ID|SEQ_NUMBER|CLASS_NAME|NICE_NAME|TYPE_ID
        $childId = $parts[2].Trim()
        if ($childId -match '^\d+$') {
            if (-not $htmlNodeSet.ContainsKey($childId)) {
                $htmlNodeSet[$childId] = $true
            }
            # Store all occurrences (for duplicate tracking)
            if (-not $htmlNodeIds.ContainsKey($childId)) {
                $htmlNodeIds[$childId] = @()
            }
            $htmlNodeIds[$childId] += $line
        }
    }
}
$htmlNodeCount = $htmlNodeSet.Keys.Count
$htmlTotalLines = $htmlLines.Count
Write-Host "HTML unique nodes: $htmlNodeCount" -ForegroundColor Yellow
Write-Host "HTML total lines: $htmlTotalLines (includes duplicates for multi-parent nodes)" -ForegroundColor White

# Compare counts
Write-Host "`n=== Comparison ===" -ForegroundColor Cyan
Write-Host "XML nodes:        $xmlNodeCount" -ForegroundColor White
Write-Host "HTML unique nodes: $htmlNodeCount" -ForegroundColor White

$percentage = if ($xmlNodeCount -gt 0) { [math]::Round(($htmlNodeCount / $xmlNodeCount) * 100, 2) } else { 0 }
Write-Host "Coverage:         $percentage%" -ForegroundColor $(if ($percentage -ge 95) { "Green" } elseif ($percentage -ge 80) { "Yellow" } else { "Red" })

if ($htmlNodeCount -ge $xmlNodeCount * 0.95) {
    Write-Host "`nPASS: HTML has >= 95% of XML nodes" -ForegroundColor Green
} elseif ($htmlNodeCount -ge $xmlNodeCount * 0.80) {
    Write-Host "`nWARNING: HTML has only $percentage% of XML nodes" -ForegroundColor Yellow
} else {
    Write-Host "`nFAIL: HTML has only $percentage% of XML nodes" -ForegroundColor Red
}

# Find missing nodes
Write-Host "`nFinding missing nodes..." -ForegroundColor Yellow
$missingNodes = @()
foreach ($xmlNodeId in $xmlNodesList) {
    if (-not $htmlNodeSet.ContainsKey($xmlNodeId)) {
        $missingNodes += [PSCustomObject]@{
            NodeId = $xmlNodeId
            Name = $xmlNodes[$xmlNodeId].Name
            Family = $xmlNodes[$xmlNodeId].Family
            Type = $xmlNodes[$xmlNodeId].Type
        }
    }
}
$missingCount = $missingNodes.Count
Write-Host "Missing nodes: $missingCount" -ForegroundColor $(if ($missingCount -eq 0) { "Green" } elseif ($missingCount -lt 100) { "Yellow" } else { "Red" })

if ($missingCount -gt 0 -and $ShowMissing) {
    Write-Host "`nSample missing nodes (first $SampleSize):" -ForegroundColor Yellow
    $missingNodes | Select-Object -First $SampleSize | Format-Table NodeId, Name, Family, Type -AutoSize

    # Group by Family to understand patterns
    Write-Host "`nMissing nodes by Family/Type:" -ForegroundColor Yellow
    $missingNodes | Group-Object -Property Family | Sort-Object Count -Descending |
        Select-Object Count, Name | Format-Table -AutoSize

    # Export detailed missing nodes list
    $missingFile = "missing-nodes-report.csv"
    $missingNodes | Export-Csv -Path $missingFile -NoTypeInformation
    Write-Host "`nDetailed missing nodes exported to: $missingFile" -ForegroundColor Cyan
}

# Find nodes in HTML but not in XML (shouldn't happen)
Write-Host "`nFinding extra nodes in HTML..." -ForegroundColor Yellow
$extraNodes = @()
foreach ($htmlNodeId in $htmlNodeSet.Keys) {
    if (-not $xmlNodes.ContainsKey($htmlNodeId)) {
        $extraNodes += $htmlNodeId
    }
}
$extraCount = $extraNodes.Count
if ($extraCount -gt 0) {
    Write-Host "Extra nodes in HTML (not in XML): $extraCount" -ForegroundColor Yellow
    if ($ShowMissing) {
        Write-Host "Sample extra node IDs (first 10):" -ForegroundColor Yellow
        $extraNodes | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor Cyan }
    }
} else {
    Write-Host "Extra nodes in HTML (not in XML): 0" -ForegroundColor Green
}

# Check for nodes appearing multiple times (multi-parent nodes)
Write-Host "`nChecking multi-parent nodes..." -ForegroundColor Yellow
$multiParentNodes = $htmlNodeIds.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
$multiParentCount = ($multiParentNodes | Measure-Object).Count
Write-Host "Nodes with multiple parents: $multiParentCount" -ForegroundColor White
if ($multiParentCount -gt 0 -and $ShowMissing) {
    Write-Host "Sample multi-parent nodes (top 5 by occurrence):" -ForegroundColor Yellow
    $multiParentNodes | Sort-Object { $_.Value.Count } -Descending | Select-Object -First 5 | ForEach-Object {
        $nodeId = $_.Key
        $count = $_.Value.Count
        $nodeName = if ($xmlNodes.ContainsKey($nodeId)) { $xmlNodes[$nodeId].Name } else { "Unknown" }
        Write-Host "  Node $nodeId ($nodeName): appears $count times" -ForegroundColor Cyan
    }
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "XML nodes:              $xmlNodeCount" -ForegroundColor White
Write-Host "HTML unique nodes:      $htmlNodeCount" -ForegroundColor White
Write-Host "HTML total lines:       $htmlTotalLines" -ForegroundColor White
Write-Host "Missing from HTML:      $missingCount" -ForegroundColor $(if ($missingCount -eq 0) { "Green" } elseif ($missingCount -lt 100) { "Yellow" } else { "Red" })
Write-Host "Extra in HTML:          $extraCount" -ForegroundColor $(if ($extraCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "Multi-parent nodes:     $multiParentCount" -ForegroundColor White
Write-Host "Coverage:               $percentage%" -ForegroundColor $(if ($percentage -ge 95) { "Green" } elseif ($percentage -ge 80) { "Yellow" } else { "Red" })

if ($missingCount -eq 0 -and $percentage -eq 100) {
    Write-Host "`nRESULT: Perfect match! ✓" -ForegroundColor Green
    exit 0
} elseif ($percentage -ge 95) {
    Write-Host "`nRESULT: Acceptable coverage (>= 95%) ✓" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`nRESULT: Coverage below 95% threshold" -ForegroundColor Red
    Write-Host "Run with -ShowMissing flag to see details: .\validate-against-xml.ps1 -ShowMissing" -ForegroundColor Yellow
    exit 1
}
