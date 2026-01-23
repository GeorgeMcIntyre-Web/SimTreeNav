# Testing and Validation Guide

## Purpose
This guide ensures that changes to the tree generation scripts don't introduce breaking changes and helps verify that all nodes from the database are correctly extracted.

## 1. Preventing Breaking Changes

### Automated Regression Tests

#### A. Node Count Validation
Before making changes, capture baseline metrics:

```powershell
# Run tree generation and capture metrics
.\src\powershell\main\tree-viewer-launcher.ps1

# Expected output includes:
# - Total nodes: ~631,318
# - Icon extraction count: 149 base icons + 5 fallbacks = 154 total
```

**Baseline Metrics (as of 2026-01-19):**
- Total data lines in HTML: 631,318
- Total unique nodes: ~631,000
- Missing TYPE_IDs: 1 (TYPE_ID 177: RobcadStudy)
- Fallback icons: 5 (108, 177, 178, 181, 183)

#### B. Critical Path Validation
These paths MUST exist in the generated tree:

```
1. PartInstanceLibrary → P702 → 01 → CC → COWL_SILL_SIDE
   - Node IDs: 18143953 → 18209343 → 18209353 → 18209355 → 18208736

2. COWL_SILL_SIDE must have 4 PartInstance children:
   - 18208727: JL34-1610110-A-18-MBR ASY FLR SD INR FRT
   - 18208739: FNA11786300_2_PNL_ASY_CWL_SD_IN_RH
   - 18208716: FNA11786290_2_PNL_ASY_CWL_SD_IN_LH
   - 18208707: NL34-1610111-A-6-MBR ASY FLR SD INR FRT LH

3. PartLibrary → P702 (separate instance from PartInstanceLibrary path)
   - Node IDs: 18143951 → 18209343
```

#### C. Manual Browser Validation Checklist
After regenerating the tree:

1. **Hard refresh browser** (Ctrl+Shift+F5)
2. **Check console for errors** - Should show no stack overflow errors
3. **Expand path**: FORD_DEARBORN → PartInstanceLibrary → P702 → 01 → CC
4. **Verify COWL_SILL_SIDE** appears under CC
5. **Verify 4 children** appear under COWL_SILL_SIDE
6. **Compare with Siemens screenshot** (if available)
7. **Check PartLibrary** path - nodes should still appear there too

### Quick Validation Script

```powershell
# Save as: test-critical-paths.ps1
$htmlFile = "navigation-tree-DESIGN12-18140190.html"

Write-Host "=== Critical Path Validation ===" -ForegroundColor Cyan

# Test 1: Check total lines
$lineCount = (Get-Content $htmlFile | Measure-Object -Line).Lines
Write-Host "`n1. Total lines: $lineCount (expected: ~631,318)" -ForegroundColor Yellow
if ($lineCount -lt 600000) {
    Write-Host "   FAIL: Line count too low!" -ForegroundColor Red
} else {
    Write-Host "   PASS" -ForegroundColor Green
}

# Test 2: Check PartInstanceLibrary → P702 path
Write-Host "`n2. PartInstanceLibrary → P702 path:" -ForegroundColor Yellow
$path1 = Select-String -Path $htmlFile -Pattern "999\|18143953\|18209343\|P702" -Quiet
if ($path1) {
    Write-Host "   PASS: PartInstanceLibrary → P702 exists" -ForegroundColor Green
} else {
    Write-Host "   FAIL: PartInstanceLibrary → P702 missing!" -ForegroundColor Red
}

# Test 3: Check P702 → 01 path
Write-Host "`n3. P702 → 01 path:" -ForegroundColor Yellow
$path2 = Select-String -Path $htmlFile -Pattern "999\|18209343\|18209353\|01" -Quiet
if ($path2) {
    Write-Host "   PASS: P702 → 01 exists" -ForegroundColor Green
} else {
    Write-Host "   FAIL: P702 → 01 missing!" -ForegroundColor Red
}

# Test 4: Check 01 → CC path
Write-Host "`n4. 01 → CC path:" -ForegroundColor Yellow
$path3 = Select-String -Path $htmlFile -Pattern "999\|18209353\|18209355\|CC" -Quiet
if ($path3) {
    Write-Host "   PASS: 01 → CC exists" -ForegroundColor Green
} else {
    Write-Host "   FAIL: 01 → CC missing!" -ForegroundColor Red
}

# Test 5: Check CC → COWL_SILL_SIDE path
Write-Host "`n5. CC → COWL_SILL_SIDE path:" -ForegroundColor Yellow
$path4 = Select-String -Path $htmlFile -Pattern "999\|18209355\|18208736\|COWL_SILL_SIDE" -Quiet
if ($path4) {
    Write-Host "   PASS: CC → COWL_SILL_SIDE exists" -ForegroundColor Green
} else {
    Write-Host "   FAIL: CC → COWL_SILL_SIDE missing!" -ForegroundColor Red
}

# Test 6: Check all 4 PartInstance children
Write-Host "`n6. COWL_SILL_SIDE children:" -ForegroundColor Yellow
$children = @(18208727, 18208739, 18208716, 18208707)
$childrenFound = 0
foreach ($child in $children) {
    if (Select-String -Path $htmlFile -Pattern "999\|18208736\|$child\|" -Quiet) {
        $childrenFound++
    }
}
Write-Host "   Found: $childrenFound/4 children" -ForegroundColor Yellow
if ($childrenFound -eq 4) {
    Write-Host "   PASS: All 4 children exist" -ForegroundColor Green
} else {
    Write-Host "   FAIL: Missing children!" -ForegroundColor Red
}

# Test 7: Check for JavaScript errors (stack overflow patterns)
Write-Host "`n7. Checking for circular reference issues:" -ForegroundColor Yellow
$hasVisited = Select-String -Path $htmlFile -Pattern "visited\.has\(" -Quiet
$hasAncestor = Select-String -Path $htmlFile -Pattern "ancestorIds\.has\(" -Quiet
if ($hasVisited -and $hasAncestor) {
    Write-Host "   PASS: Cycle detection code present" -ForegroundColor Green
} else {
    Write-Host "   FAIL: Cycle detection missing!" -ForegroundColor Red
}

Write-Host "`n=== Validation Complete ===" -ForegroundColor Cyan
```

## 2. Validating Against XML Export

The XML export at `C:\Users\georgem\source\repos\cursor\SimTreeNav_data\FORD_DEARBORN.xml` (141MB) can be used as the source of truth.

### XML Validation Strategy

#### A. Extract Node Hierarchy from XML

```powershell
# Save as: validate-against-xml.ps1
param(
    [string]$XmlPath = "C:\Users\georgem\source\repos\cursor\SimTreeNav_data\FORD_DEARBORN.xml",
    [string]$HtmlPath = "navigation-tree-DESIGN12-18140190.html"
)

Write-Host "=== XML vs HTML Validation ===" -ForegroundColor Cyan

# Parse XML to extract all node IDs and their children
Write-Host "`nParsing XML export..." -ForegroundColor Yellow
[xml]$xml = Get-Content $XmlPath

# Extract all NodeInfo/Id elements
$xmlNodes = $xml.SelectNodes("//NodeInfo/Id") | ForEach-Object { $_.InnerText }
$xmlNodeCount = $xmlNodes.Count
Write-Host "XML nodes found: $xmlNodeCount" -ForegroundColor Yellow

# Extract all parent-child relationships from XML
Write-Host "`nExtracting parent-child relationships from XML..." -ForegroundColor Yellow
$xmlRelationships = @{}
$allElements = $xml.Data.Objects.ChildNodes
foreach ($element in $allElements) {
    if ($element.NodeInfo -and $element.children) {
        $parentId = $element.NodeInfo.Id
        $childItems = $element.children.item
        if ($childItems) {
            foreach ($childRef in $childItems) {
                # Extract ID from ExternalId (format: PP-DESIGN12-...-PARENTID-CHILDID)
                if ($childRef -match '-(\d+)$') {
                    $childId = $matches[1]
                    if (-not $xmlRelationships.ContainsKey($parentId)) {
                        $xmlRelationships[$parentId] = @()
                    }
                    $xmlRelationships[$parentId] += $childId
                }
            }
        }
    }
}

Write-Host "XML parent-child relationships: $($xmlRelationships.Keys.Count)" -ForegroundColor Yellow

# Extract node IDs from HTML
Write-Host "`nExtracting nodes from HTML..." -ForegroundColor Yellow
$htmlContent = Get-Content $HtmlPath -Raw
$htmlLines = $htmlContent -split "`n" | Where-Object { $_ -match '^\d+\|' }
$htmlNodeIds = @{}
foreach ($line in $htmlLines) {
    $parts = $line -split '\|'
    if ($parts.Length -ge 3) {
        $childId = $parts[2]
        if ($childId -match '^\d+$') {
            $htmlNodeIds[$childId] = $true
        }
    }
}
$htmlNodeCount = $htmlNodeIds.Keys.Count
Write-Host "HTML unique nodes: $htmlNodeCount" -ForegroundColor Yellow

# Compare counts
Write-Host "`n=== Comparison ===" -ForegroundColor Cyan
Write-Host "XML nodes: $xmlNodeCount" -ForegroundColor Yellow
Write-Host "HTML nodes: $htmlNodeCount" -ForegroundColor Yellow

if ($htmlNodeCount -ge $xmlNodeCount * 0.95) {
    Write-Host "PASS: HTML has >= 95% of XML nodes" -ForegroundColor Green
} else {
    $percentage = [math]::Round(($htmlNodeCount / $xmlNodeCount) * 100, 2)
    Write-Host "WARNING: HTML has only $percentage% of XML nodes" -ForegroundColor Red

    # Find missing nodes
    Write-Host "`nFinding missing nodes..." -ForegroundColor Yellow
    $missingCount = 0
    $sampleMissing = @()
    foreach ($xmlNodeId in $xmlNodes) {
        if (-not $htmlNodeIds.ContainsKey($xmlNodeId)) {
            $missingCount++
            if ($sampleMissing.Count -lt 10) {
                $sampleMissing += $xmlNodeId
            }
        }
    }
    Write-Host "Missing nodes: $missingCount" -ForegroundColor Red
    Write-Host "Sample missing node IDs (first 10):" -ForegroundColor Red
    $sampleMissing | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
}

Write-Host "`n=== Validation Complete ===" -ForegroundColor Cyan
```

#### B. Focused XML Validation for Critical Paths

```powershell
# Save as: validate-critical-path-xml.ps1
param(
    [string]$XmlPath = "C:\Users\georgem\source\repos\cursor\SimTreeNav_data\FORD_DEARBORN.xml"
)

Write-Host "=== Critical Path XML Validation ===" -ForegroundColor Cyan

[xml]$xml = Get-Content $XmlPath

# Find PartInstanceLibrary node (ID: 18143953)
$partInstanceLib = $xml.Data.Objects.ChildNodes | Where-Object {
    $_.NodeInfo.Id -eq "18143953"
}

if ($partInstanceLib) {
    Write-Host "`nPartInstanceLibrary (18143953) found in XML" -ForegroundColor Green
    Write-Host "Children in XML:" -ForegroundColor Yellow
    $partInstanceLib.children.item | ForEach-Object {
        if ($_ -match '-(\d+)$') {
            Write-Host "  $($matches[1])" -ForegroundColor Cyan
        }
    }
} else {
    Write-Host "`nPartInstanceLibrary (18143953) NOT found in XML!" -ForegroundColor Red
}

# Find CC node (ID: 18209355)
$ccNode = $xml.Data.Objects.ChildNodes | Where-Object {
    $_.NodeInfo.Id -eq "18209355"
}

if ($ccNode) {
    Write-Host "`nCC (18209355) found in XML" -ForegroundColor Green
    Write-Host "Children in XML:" -ForegroundColor Yellow
    $ccNode.children.item | ForEach-Object {
        if ($_ -match '-(\d+)$') {
            Write-Host "  $($matches[1])" -ForegroundColor Cyan
        }
    }
} else {
    Write-Host "`nCC (18209355) NOT found in XML!" -ForegroundColor Red
}

# Find COWL_SILL_SIDE node (ID: 18208736)
$cowlNode = $xml.Data.Objects.ChildNodes | Where-Object {
    $_.NodeInfo.Id -eq "18208736"
}

if ($cowlNode) {
    Write-Host "`nCOWL_SILL_SIDE (18208736) found in XML" -ForegroundColor Green
    Write-Host "Type: $($cowlNode.LocalName)" -ForegroundColor Yellow
    Write-Host "Children in XML:" -ForegroundColor Yellow
    $childCount = 0
    $cowlNode.children.item | ForEach-Object {
        if ($_ -match '-(\d+)$') {
            $childCount++
            Write-Host "  $($matches[1])" -ForegroundColor Cyan
        }
    }
    Write-Host "Total children: $childCount" -ForegroundColor Yellow
} else {
    Write-Host "`nCOWL_SILL_SIDE (18208736) NOT found in XML!" -ForegroundColor Red
}
```

## 3. Integration Testing Workflow

### Before Making Changes:

1. **Capture baseline**:
   ```powershell
   .\test-critical-paths.ps1 > baseline.txt
   ```

2. **Capture node count**:
   ```powershell
   (Get-Content navigation-tree-DESIGN12-18140190.html | Measure-Object -Line).Lines
   ```

3. **Test in browser** and take screenshots of:
   - PartInstanceLibrary → P702 → 01 → CC → COWL_SILL_SIDE (expanded)
   - Console showing no errors
   - Stats showing node counts

### After Making Changes:

1. **Regenerate tree**:
   ```powershell
   .\src\powershell\main\tree-viewer-launcher.ps1
   ```

2. **Run validation**:
   ```powershell
   .\test-critical-paths.ps1
   ```

3. **Compare results**:
   ```powershell
   # Check if node count is similar (within 1%)
   $baseline = 631318
   $current = (Get-Content navigation-tree-DESIGN12-18140190.html | Measure-Object -Line).Lines
   $diff = [math]::Abs($current - $baseline)
   $percentDiff = ($diff / $baseline) * 100

   if ($percentDiff -lt 1.0) {
       Write-Host "PASS: Node count within 1% of baseline" -ForegroundColor Green
   } else {
       Write-Host "WARNING: Node count differs by $([math]::Round($percentDiff, 2))%" -ForegroundColor Red
   }
   ```

4. **Hard refresh browser** (Ctrl+Shift+F5)

5. **Manually verify critical paths**

6. **Check console** for errors

### Committing Changes:

Only commit if all validation passes:
- ✓ Node count within expected range
- ✓ Critical paths exist
- ✓ Browser renders without errors
- ✓ Manual verification matches Siemens app

## 4. Common Breaking Changes to Avoid

### SQL Query Changes
❌ **DON'T**: Add filters like `WHERE TYPE_ID NOT IN (...)` without understanding impact
✓ **DO**: Output all relationships, let JavaScript handle filtering

❌ **DON'T**: Use `r.FORWARD_OBJECT_ID < r.OBJECT_ID` to filter bidirectional relationships
✓ **DO**: Allow JavaScript childMap to handle deduplication

### JavaScript Tree Building
❌ **DON'T**: Use `reverseKey` check that prevents same child under multiple parents
✓ **DO**: Only prevent exact duplicate: same parent + same child

❌ **DON'T**: Use recursive functions without cycle detection
✓ **DO**: Always add `visited` Set or `ancestorIds` Set to prevent infinite recursion

### Icon Handling
❌ **DON'T**: Remove fallback icon logic
✓ **DO**: Keep fallback icons for missing TYPE_IDs

## 5. Future Enhancements

### Automated Testing
Consider creating a PowerShell Pester test suite:

```powershell
# Save as: SimTreeNav.Tests.ps1
Describe "Navigation Tree Generation" {
    BeforeAll {
        .\src\powershell\main\tree-viewer-launcher.ps1 -NonInteractive
    }

    It "Should generate HTML file" {
        Test-Path "navigation-tree-DESIGN12-18140190.html" | Should -Be $true
    }

    It "Should have approximately 631,318 lines" {
        $lineCount = (Get-Content navigation-tree-DESIGN12-18140190.html | Measure-Object -Line).Lines
        $lineCount | Should -BeGreaterThan 600000
        $lineCount | Should -BeLessThan 700000
    }

    It "Should contain PartInstanceLibrary → P702 path" {
        $content = Get-Content navigation-tree-DESIGN12-18140190.html -Raw
        $content | Should -Match "999\|18143953\|18209343\|P702"
    }

    It "Should contain all 4 COWL_SILL_SIDE children" {
        $content = Get-Content navigation-tree-DESIGN12-18140190.html -Raw
        $content | Should -Match "999\|18208736\|18208727\|"
        $content | Should -Match "999\|18208736\|18208739\|"
        $content | Should -Match "999\|18208736\|18208716\|"
        $content | Should -Match "999\|18208736\|18208707\|"
    }

    It "Should have cycle detection in JavaScript" {
        $content = Get-Content navigation-tree-DESIGN12-18140190.html -Raw
        $content | Should -Match "visited\.has\("
        $content | Should -Match "ancestorIds\.has\("
    }
}
```

Run with: `Invoke-Pester .\SimTreeNav.Tests.ps1`

## 6. Contact for Issues

If validation fails or you discover missing nodes:
1. Run `test-critical-paths.ps1` and save output
2. Run `validate-against-xml.ps1` to compare with XML export
3. Document which paths are missing
4. Check git history to see what changed: `git log --oneline -10`
5. Create GitHub issue with validation output
