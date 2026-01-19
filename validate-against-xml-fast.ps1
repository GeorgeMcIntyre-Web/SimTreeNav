# Fast XML vs HTML Validation Script
# Uses streaming XML parsing for large files (141MB+)

param(
    [string]$XmlPath = "C:\Users\georgem\source\repos\cursor\SimTreeNav_data\FORD_DEARBORN.xml",
    [string]$HtmlPath = "navigation-tree-DESIGN12-18140190.html",
    [switch]$ShowMissing = $false,
    [int]$SampleSize = 20
)

Write-Host "=== Fast XML vs HTML Validation ===" -ForegroundColor Cyan
Write-Host "Optimized for large XML files using streaming parser" -ForegroundColor Gray

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

# Step 1: Extract node IDs from XML using streaming parser (FAST)
Write-Host "`nExtracting node IDs from XML (streaming mode)..." -ForegroundColor Yellow
$xmlNodes = @{}
$xmlNodeCount = 0

# Use XmlTextReader for fast streaming parse (doesn't load entire file)
$reader = [System.Xml.XmlTextReader]::new($XmlPath)
$reader.WhitespaceHandling = [System.Xml.WhitespaceHandling]::None

try {
    $inNodeInfo = $false
    $inId = $false
    $inName = $false
    $inFamily = $false
    $currentId = $null
    $currentName = $null
    $currentFamily = $null
    $currentType = $null

    while ($reader.Read()) {
        if ($reader.NodeType -eq [System.Xml.XmlNodeType]::Element) {
            # Track when we're in NodeInfo section
            if ($reader.Name -eq "NodeInfo") {
                $inNodeInfo = $true
                $currentId = $null
                $currentName = $null
                $currentFamily = $null
                # Get parent element type (e.g., PmProject, PmCollection, etc.)
                continue
            }

            # Get element type from parent (before NodeInfo)
            if (-not $inNodeInfo -and $reader.Name -match '^Pm|^Robcad') {
                $currentType = $reader.Name
            }

            if ($inNodeInfo) {
                if ($reader.Name -eq "Id") {
                    $inId = $true
                } elseif ($reader.Name -eq "Name") {
                    $inName = $true
                } elseif ($reader.Name -eq "family") {
                    $inFamily = $true
                }
            }
        }
        elseif ($reader.NodeType -eq [System.Xml.XmlNodeType]::Text) {
            if ($inId) {
                $currentId = $reader.Value
                $inId = $false
            }
            elseif ($inName) {
                $currentName = $reader.Value
                $inName = $false
            }
            elseif ($inFamily) {
                $currentFamily = $reader.Value
                $inFamily = $false
            }
        }
        elseif ($reader.NodeType -eq [System.Xml.XmlNodeType]::EndElement) {
            if ($reader.Name -eq "NodeInfo" -and $currentId) {
                # Store this node
                $xmlNodes[$currentId] = @{
                    Name = $currentName
                    Family = $currentFamily
                    Type = $currentType
                }
                $xmlNodeCount++

                # Progress indicator every 1000 nodes
                if ($xmlNodeCount % 1000 -eq 0) {
                    Write-Host "`r  Progress: $xmlNodeCount nodes..." -NoNewline -ForegroundColor Gray
                }

                $inNodeInfo = $false
            }
        }
    }
} finally {
    $reader.Close()
}

Write-Host "`r  XML nodes found: $xmlNodeCount                    " -ForegroundColor Yellow

# Step 2: Extract node IDs from HTML (FAST - streaming read)
Write-Host "`nExtracting nodes from HTML (streaming mode)..." -ForegroundColor Yellow
$htmlNodeSet = @{}
$htmlNodeCount = 0

$streamReader = [System.IO.StreamReader]::new($HtmlPath)
try {
    while ($null -ne ($line = $streamReader.ReadLine())) {
        # Only process data lines (format: LEVEL|PARENT|CHILD|...)
        if ($line -match '^\d+\|') {
            $parts = $line -split '\|'
            if ($parts.Length -ge 10) {
                $childId = $parts[2].Trim()
                if ($childId -match '^\d+$') {
                    if (-not $htmlNodeSet.ContainsKey($childId)) {
                        $htmlNodeSet[$childId] = $true
                        $htmlNodeCount++

                        # Progress indicator every 10000 nodes
                        if ($htmlNodeCount % 10000 -eq 0) {
                            Write-Host "`r  Progress: $htmlNodeCount nodes..." -NoNewline -ForegroundColor Gray
                        }
                    }
                }
            }
        }
    }
} finally {
    $streamReader.Close()
}

Write-Host "`r  HTML unique nodes: $htmlNodeCount                    " -ForegroundColor Yellow

# Step 3: Calculate coverage
Write-Host "`n=== Comparison ===" -ForegroundColor Cyan
Write-Host "XML nodes:         $xmlNodeCount" -ForegroundColor White
Write-Host "HTML unique nodes: $htmlNodeCount" -ForegroundColor White

$percentage = if ($xmlNodeCount -gt 0) { [math]::Round(($htmlNodeCount / $xmlNodeCount) * 100, 2) } else { 0 }
Write-Host "Coverage:          $percentage%" -ForegroundColor $(if ($percentage -ge 95) { "Green" } elseif ($percentage -ge 80) { "Yellow" } else { "Red" })

if ($htmlNodeCount -ge $xmlNodeCount * 0.95) {
    Write-Host "`nPASS: HTML has >= 95% of XML nodes" -ForegroundColor Green
} elseif ($htmlNodeCount -ge $xmlNodeCount * 0.80) {
    Write-Host "`nWARNING: HTML has only $percentage% of XML nodes" -ForegroundColor Yellow
} else {
    Write-Host "`nFAIL: HTML has only $percentage% of XML nodes" -ForegroundColor Red
}

# Step 4: Find missing nodes (only if requested or coverage < 95%)
$missingCount = $xmlNodeCount - $htmlNodeCount
Write-Host "`nMissing nodes: $missingCount" -ForegroundColor $(if ($missingCount -eq 0) { "Green" } elseif ($missingCount -lt 100) { "Yellow" } else { "Red" })

if ($missingCount -gt 0 -and ($ShowMissing -or $percentage -lt 95)) {
    Write-Host "`nFinding missing nodes (this may take a moment)..." -ForegroundColor Yellow
    $missingNodes = @()
    $checkedCount = 0

    foreach ($xmlNodeId in $xmlNodes.Keys) {
        if (-not $htmlNodeSet.ContainsKey($xmlNodeId)) {
            $nodeInfo = $xmlNodes[$xmlNodeId]
            $missingNodes += [PSCustomObject]@{
                NodeId = $xmlNodeId
                Name = $nodeInfo.Name
                Family = $nodeInfo.Family
                Type = $nodeInfo.Type
            }
        }

        $checkedCount++
        if ($checkedCount % 1000 -eq 0) {
            Write-Host "`r  Checked: $checkedCount / $xmlNodeCount..." -NoNewline -ForegroundColor Gray
        }
    }

    Write-Host "`r  Checked: $xmlNodeCount / $xmlNodeCount - Complete!     " -ForegroundColor Gray

    if ($missingNodes.Count -gt 0) {
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
}

# Step 5: Find extra nodes in HTML (shouldn't happen)
Write-Host "`nFinding extra nodes in HTML..." -ForegroundColor Yellow
$extraCount = 0
foreach ($htmlNodeId in $htmlNodeSet.Keys) {
    if (-not $xmlNodes.ContainsKey($htmlNodeId)) {
        $extraCount++
    }
}

if ($extraCount -gt 0) {
    Write-Host "Extra nodes in HTML (not in XML): $extraCount" -ForegroundColor Yellow
} else {
    Write-Host "Extra nodes in HTML (not in XML): 0" -ForegroundColor Green
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "XML nodes:              $xmlNodeCount" -ForegroundColor White
Write-Host "HTML unique nodes:      $htmlNodeCount" -ForegroundColor White
Write-Host "Missing from HTML:      $missingCount" -ForegroundColor $(if ($missingCount -eq 0) { "Green" } elseif ($missingCount -lt 100) { "Yellow" } else { "Red" })
Write-Host "Extra in HTML:          $extraCount" -ForegroundColor $(if ($extraCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "Coverage:               $percentage%" -ForegroundColor $(if ($percentage -ge 95) { "Green" } elseif ($percentage -ge 80) { "Yellow" } else { "Red" })

if ($missingCount -eq 0 -and $percentage -eq 100) {
    Write-Host "`nRESULT: Perfect match! All XML nodes present in HTML ✓" -ForegroundColor Green
    exit 0
} elseif ($percentage -ge 95) {
    Write-Host "`nRESULT: Acceptable coverage (>= 95%) ✓" -ForegroundColor Green
    if ($missingCount -gt 0) {
        Write-Host "Note: $missingCount nodes missing. Run with -ShowMissing to see details." -ForegroundColor Yellow
    }
    exit 0
} else {
    Write-Host "`nRESULT: Coverage below 95% threshold" -ForegroundColor Red
    Write-Host "Run with -ShowMissing flag to see details: .\validate-against-xml-fast.ps1 -ShowMissing" -ForegroundColor Yellow
    exit 1
}
